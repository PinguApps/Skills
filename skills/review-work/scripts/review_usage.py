"""Collect review-only OpenCode session usage and render per-round PR accounting.

The parent records run IDs before delegation and task/thread IDs afterwards.
No inference requests or credentials are made/read by this helper.
"""
import argparse
from decimal import Decimal, ROUND_HALF_UP
import json
from html import escape
import math
import os
from pathlib import Path
import subprocess
import re
from urllib.parse import urlsplit

POLICY = json.loads((Path(__file__).parents[1] / 'references/review-policy.json').read_text(encoding='utf-8'))

def load(path):
    return json.loads(Path(path).read_text(encoding='utf-8-sig'))


def save(path, value):
    target = Path(path)
    temporary = target.with_suffix(target.suffix + '.tmp')
    temporary.write_text(json.dumps(value, indent=2), encoding='utf-8')
    temporary.replace(target)


def api(executable, operation, **params):
    if not Path(executable).is_absolute():
        raise ValueError('Use an absolute OpenCode executable path')
    args = [executable, 'api', operation]
    for key, value in params.items():
        args += ['--param', key + '=' + str(value)]
    env = {**os.environ, 'OPENCODE_DISABLE_AUTOUPDATE': 'true',
           'OPENCODE_DISABLE_LSP_DOWNLOAD': 'true', 'OPENCODE_DISABLE_PRUNE': 'true'}
    result = subprocess.run(args, capture_output=True, text=True, encoding='utf-8',
                            errors='strict', timeout=60, env=env)
    if result.returncode:
        raise RuntimeError('OpenCode API failed: ' + result.stderr[:300])
    return json.loads(result.stdout)


def pages(executable, operation, **params):
    seen = set()
    while True:
        response = api(executable, operation, **params)
        if set(response) - {'data', 'cursor'}:
            raise ValueError('Unexpected OpenCode pagination fields')
        data = response.get('data', [])
        if not isinstance(data, list):
            raise ValueError('Unexpected OpenCode list response')
        yield from data
        cursor_info = response.get('cursor', {})
        if not isinstance(cursor_info, dict) or set(cursor_info) - {'next', 'previous'}:
            raise ValueError('Unexpected OpenCode cursor shape')
        cursor = cursor_info.get('next')
        if not cursor:
            return
        if cursor in seen:
            raise ValueError('Repeated OpenCode pagination cursor')
        seen.add(cursor)
        params['cursor'] = cursor


def user_text(message):
    if message.get('type') != 'user':
        return ''
    if isinstance(message.get('text'), str):
        return message['text']
    content = message.get('content', [])
    if isinstance(content, str):
        return content
    return '\n'.join(part.get('text', '') for part in content if isinstance(part, dict))


def correlate(executable, run, directory):
    matches = []
    for session in pages(executable, 'session.list', directory=Path(directory).as_posix(), limit=100):
        if Path(session['location']['directory']).resolve() != Path(directory).resolve():
            continue
        if run.get('sessionID') and session['id'] != run['sessionID']:
            continue
        messages = list(pages(executable, 'session.message.list', sessionID=session['id'], limit=100))
        users = sorted((m for m in messages if m.get('type') == 'user'), key=lambda m: m['time']['created'])
        lines = re.findall(r'^Review-Run-ID: \S+$', user_text(users[0]).replace('\r\n', '\n'), flags=re.MULTILINE) if users else []
        if lines == [run['marker']]:
            matches.append((session, messages))
    if len(matches) != 1:
        raise ValueError(f'Expected one session containing the exact run marker; found {len(matches)}')
    return matches[0]


def reported_usage(messages, expected_model, expected_effort=None):
    totals = {'input': 0, 'output': 0, 'reasoning': 0, 'cacheRead': 0, 'cacheWrite': 0}
    cost = Decimal('0')
    ids = set()
    missing = []
    for message in messages:
        if message.get('type') not in ('assistant', 'compaction'):
            continue
        identifier = message['id']
        if identifier in ids:
            continue
        ids.add(identifier)
        model = message.get('model') or {'providerID': message.get('providerID'),
                                        'id': message.get('modelID'), 'variant': message.get('variant')}
        if str(model.get('providerID', '')) + '/' + str(model.get('id', model.get('modelID', ''))) != expected_model:
            raise ValueError('Unexpected auxiliary model in review session: ' + str(model))
        if expected_effort and (model.get('variant') or 'default') != expected_effort:
            raise ValueError('Unexpected review effort: ' + str(model))
        tokens = message.get('tokens')
        if tokens is None or message.get('cost') is None or (
                message['type'] == 'assistant' and not message.get('time', {}).get('completed')):
            # Streaming/tool-only messages without usage must not turn into $0.
            missing.append(identifier)
            continue
        for source, target in [('input', 'input'), ('output', 'output'), ('reasoning', 'reasoning')]:
            totals[target] += tokens.get(source, 0)
        totals['cacheRead'] += tokens.get('cache', {}).get('read', 0)
        totals['cacheWrite'] += tokens.get('cache', {}).get('write', 0)
        cost += Decimal(str(message['cost']))
    # OpenCode 2.1.4 usage.ts uses visibleOutputTokens, separately from reasoning.
    # OpenRouter completion_tokens already includes reasoning; never add it there.
    totals['input'] += totals['cacheRead'] + totals['cacheWrite']
    totals['output'] += totals['reasoning']
    return {**totals, 'costUSD': str(cost), 'billed': False, 'source': 'OpenCode catalogue estimate, not billed spend',
            'messageIDs': sorted(ids), 'missingUsageMessageIDs': missing if ids else ['no-usage-messages']}


class IncompleteUsage(ValueError):
    def __init__(self, partial):
        super().__init__('Incomplete provider billing evidence; retain journal and reconcile')
        self.partial = partial


def amount(value, *, integer=False):
    if isinstance(value, bool) or not isinstance(value, (int, float, str)):
        raise ValueError('Invalid provider usage number')
    number = Decimal(str(value))
    if not number.is_finite() or number < 0 or (integer and number != number.to_integral_value()):
        raise ValueError('Invalid provider usage number')
    return int(number) if integer else number


def go_usage(value):
    metadata = value['opencode']
    source = metadata['billing_source']
    if source not in ('go', 'go-plus', 'balance') or metadata.get('estimated'):
        raise ValueError('Unexpected OpenCode Go billing source or estimate')
    tokens = metadata['tokens']
    counts = {key: amount(tokens[key], integer=True) for key in
              ('input', 'output', 'reasoning', 'cache_read', 'cache_write_5m', 'cache_write_1h')}
    charge = amount(value['cost'])
    if source in ('go', 'go-plus') and charge:
        raise ValueError('Covered Go usage unexpectedly reports a cash charge')
    return {
        'input': counts['input'] + counts['cache_read'] + counts['cache_write_5m'] + counts['cache_write_1h'],
        'output': counts['output'], 'reasoning': counts['reasoning'],
        'cacheRead': counts['cache_read'], 'cacheWrite': counts['cache_write_5m'] + counts['cache_write_1h'],
        'costUSD': charge, 'listCostUSD': amount(metadata['list_cost']),
        'allowanceUSD': amount(metadata['allowance']) if source in ('go', 'go-plus') else Decimal('0'),
        'billingSource': source,
    }


def billed_usage(records, run, session_id):
    requests, responses, usage, capture_errors = {}, {}, {}, set()
    guards = []
    for entry in records:
        if entry.get('sessionID') and entry['sessionID'] != session_id:
            raise ValueError('Transport record belongs to a different review session')
        if entry.get('event') == 'blocked-tool':
            raise ValueError('Review tool guard breach; investigate before accepting coverage')
        if entry.get('event') == 'guard':
            expected = ['pingu_review_source', *run.get('executionTools', [])]
            if run.get('obligations'):
                expected += ['pingu_review_checkpoint', 'pingu_review_check']
            if sorted(entry.get('tools', [])) != sorted(expected):
                raise ValueError('Invalid filtered-tool guard')
            guards.append(entry)
        if entry.get('event') not in ('request', 'response', 'usage', 'end', 'capture-error'):
            continue
        if entry.get('sessionID') != session_id or entry.get('model') != run['model'] or entry.get('effort') != run['effort']:
            raise ValueError('Transport record belongs to a different review session/model/effort')
        request = entry['requestID']
        if entry['event'] == 'request':
            if request in requests:
                raise ValueError('Duplicate physical request ID')
            if entry.get('kind') not in ('primary', 'compaction', 'title', 'generate'):
                raise ValueError('Unknown review request kind')
            requests[request] = entry
        elif entry['event'] == 'response':
            responses[request] = entry
        elif entry['event'] == 'usage':
            usage[request] = entry
        elif entry['event'] == 'capture-error':
            capture_errors.add(request)
    if (set(responses) | set(usage) | capture_errors) - set(requests):
        raise ValueError('Transport response has no matching physical request')
    totals = dict(input=0, output=0, reasoning=0, cacheRead=0, cacheWrite=0)
    cost = Decimal('0')
    go = run['model'].startswith('opencode-go/')
    list_cost, allowance = Decimal('0'), Decimal('0')
    billing_sources = set()
    generation_ids, missing = set(), []
    peak_prompt, compaction_calls = 0, 0
    if not guards:
        missing.append('filtered-tool-guard')
    if not requests:
        missing.append('no-transport-requests')
    for request in requests:
        item = usage.get(request, {})
        value = item.get('usage', {})
        # OpenCode cancels the stream after the final usage event. EOF is not
        # billing evidence; terminal task/session + every physical response is.
        if (request in capture_errors or not 200 <= responses.get(request, {}).get('status', 0) < 300 or
                value.get('cost') is None or not item.get('generationID')):
            missing.append(request)
            continue
        generation = item['generationID']
        if generation in generation_ids:
            raise ValueError('Duplicate provider generation across physical requests; reconcile before summing')
        generation_ids.add(generation)
        if go:
            try:
                normalized = go_usage(value)
            except KeyError:
                missing.append(request)
                continue
            for key in totals:
                totals[key] += normalized[key]
            cost += normalized['costUSD']
            list_cost += normalized['listCostUSD']
            allowance += normalized['allowanceUSD']
            billing_sources.add(normalized['billingSource'])
            prompt = normalized['input']
        else:
            if value.get('prompt_tokens') is None or value.get('completion_tokens') is None:
                missing.append(request)
                continue
            prompt = amount(value['prompt_tokens'], integer=True)
            totals['input'] += prompt
            totals['output'] += amount(value['completion_tokens'], integer=True)
            totals['reasoning'] += amount(value.get('completion_tokens_details', {}).get('reasoning_tokens', 0), integer=True)
            for field, key in [('cacheRead', 'cached_tokens'), ('cacheWrite', 'cache_write_tokens')]:
                count = value.get('prompt_tokens_details', {}).get(key)
                totals[field] = None if count is None or totals[field] is None else totals[field] + amount(count, integer=True)
            cost += amount(value['cost'])
        peak_prompt = max(peak_prompt, prompt)
        compaction_calls += requests[request].get('kind') == 'compaction'
    result = {**totals, 'costUSD': str(cost), 'billed': not missing,
            'source': ('OpenCode Go' if go else 'OpenRouter') + ' response usage.cost',
            'peakPromptTokens': peak_prompt, 'modelCalls': len(requests), 'compactionCalls': compaction_calls,
            'generationIDs': sorted(generation_ids), 'missingUsageMessageIDs': missing}
    if go:
        result['goUsage'] = {'listCostUSD': str(list_cost), 'allowanceUSD': str(allowance),
                             'billingSources': sorted(billing_sources)}
    if missing:
        result['source'] = 'Partial provider evidence; full billed total unavailable'
        raise IncompleteUsage(result)
    return result


def collect_usage(run, records, session_id, estimate, allow_estimate):
    try:
        run['usage'] = billed_usage(records or [], run, session_id)
        run.pop('partialBilledUsage', None)
        run.pop('accountingIncomplete', None)
        run.pop('accountingError', None)
    except IncompleteUsage as error:
        run['partialBilledUsage'] = error.partial
        run['usage'] = estimate if allow_estimate and estimate['messageIDs'] else None
        run['accountingIncomplete'] = True
        if not allow_estimate:
            raise


def validate_assignment(ledger, run):
    if not re.fullmatch(r'Review-Run-ID: \S+', run['marker']):
        raise ValueError('marker must be a complete Review-Run-ID: <opaque> line')
    if any(r['marker'] == run['marker'] and r['id'] != run['id'] for r in ledger['runs']):
        raise ValueError('Use a fresh marker for each launch/retry')
    route = ledger['route']
    if run.get('replacementOf'):
        original = next((r for r in ledger['runs'] if r['id'] == run['replacementOf']), None)
        if (not original or original.get('status') not in ('completed', 'failed', 'cancelled', 'interrupted') or
                original['head'] != run['head'] or original['round'] != run['round']):
            raise ValueError('Replacement requires a terminal predecessor on the same revision/round')
        recovery = run.get('recovery', {})
        if any(not recovery.get(key, '').strip() for key in ('cause', 'changedCondition', 'evidence', 'reason')):
            raise ValueError('Replacement requires cause-specific recovery evidence and justification')
        category = recovery.get('category')
        if not route.get('category') or category != route['category']:
            raise ValueError('Replacement must retain the full slot highest-risk category')
        chain = route.get('escalationByCategory', {}).get(category, [])
        concerns = route.get('escalationByConcern', {}).get(category)
        if concerns:
            if recovery.get('concern') not in concerns:
                raise ValueError('Replacement requires a valid category concern')
            chain = concerns[recovery['concern']]
        used = {r['model'] for r in ledger['runs'] if r['head'] == run['head'] and r['id'] != run['id']
                and (r.get('taskId') or r.get('threadId') or r.get('sessionID'))}
        eligible = [(key, effort) for key, effort in chain if POLICY['models'][key]['id'] not in used]
        if not eligible or (run['model'], run['effort']) != (POLICY['models'][eligible[0][0]]['id'], eligible[0][1]):
            raise ValueError('Replacement must use the next eligible unused category model; exhausted chains block')
    allowed = list(route['reviewers'])
    for chain in route.get('escalationByCategory', {}).values():
        allowed.extend(chain)
    for concerns in route.get('escalationByConcern', {}).values():
        for chain in concerns.values():
            allowed.extend(chain)
    if route.get('escalation'):
        allowed.append(route['escalation'])
    if route.get('integration'):
        allowed.append(route['integration'])
    override = ledger.get('benchmarkAuthorization', {})
    if override.get('reason'):
        allowed.extend(override.get('assignments', []))
    if not any(POLICY['models'].get(key, {}).get('id') == run['model'] and effort == run['effort']
               for key, effort in allowed):
        raise ValueError('Model/effort is outside the recorded route or explicit benchmark authorization')


def money(value, places=2):
    return '$' + format(Decimal(str(value)).quantize(Decimal(1).scaleb(-places), rounding=ROUND_HALF_UP), f'.{places}f')


def session_timing(session):
    times = session.get('time', {})
    start, end = times.get('created'), times.get('idle')
    if any(isinstance(v, bool) or not isinstance(v, (int, float)) or not math.isfinite(v)
           for v in (start, end)) or end < start:
        return None
    return {'startMs': start, 'endMs': end, 'seconds': (end - start) / 1000,
            'source': 'OpenCode session created to terminal idle; includes tools and compaction'}


def duration(run):
    seconds = (run.get('timing') or {}).get('seconds')
    if isinstance(seconds, bool) or not isinstance(seconds, (int, float)) or not math.isfinite(seconds) or seconds < 0:
        return 'unavailable'
    seconds = int(Decimal(str(seconds)).quantize(Decimal('1'), rounding=ROUND_HALF_UP))
    minutes, seconds = divmod(seconds, 60)
    hours, minutes = divmod(minutes, 60)
    return (f'{hours}h ' if hours else '') + (f'{minutes}m ' if hours or minutes else '') + f'{seconds}s'


def cell(value):
    return escape(str(value), quote=False).replace('|', '\\|').replace('\n', ' ').replace('\r', ' ')


def repository_url(value):
    if not value:
        return None
    parts = urlsplit(value)
    if parts.scheme != 'https' or not parts.netloc or parts.username or parts.password or parts.query or parts.fragment or any(c.isspace() for c in value):
        raise ValueError('Use the verified HTTPS repository web URL without query/fragment')
    return value.rstrip('/')


def model_name(run):
    return cell(run['model'].rsplit('/', 1)[-1])


def review_range(run, url):
    before, after = str(run['from'])[:7], str(run['head'])[:7]
    label = cell(before + '..' + after)
    # GitHub's two-dot view matches the exact endpoint diff used by the reader.
    if url and all(re.fullmatch(r'[0-9a-fA-F]{7,64}', str(run[key])) for key in ('from', 'head')):
        return f'[{label}]({url}/compare/{before}..{after})'
    return label


def review_type(run):
    if run.get('base'):
        return 'Full review' if run['from'] == run['base'] else 'Incremental review'
    return 'unavailable'


def incomplete(run):
    usage = run.get('usage')
    return usage is None or usage.get('costUSD') is None or bool(usage.get('missingUsageMessageIDs')) or bool(run.get('accountingIncomplete'))


def allocated_run(run, basis):
    """Build the report view without rewriting authoritative cash receipts."""
    captured = run.get('usage')
    if not run['model'].startswith('opencode-go/') or not captured or not captured.get('billed'):
        return run
    go = captured.get('goUsage') or {}
    sources = set(go.get('billingSources', []))
    cost = amount(captured['costUSD'])
    if not sources or sources - {'balance', (basis or {}).get('billingSource')} or go.get('allowanceUSD') is None:
        return {**run, 'usage': {**captured, 'costUSD': None}}
    if sources != {'balance'}:
        if not basis:
            return {**run, 'usage': {**captured, 'costUSD': None}}
        fee, pool = amount(basis['monthlyFeeUSD']), amount(basis['monthlyAllowanceUSD'])
        if pool == 0:
            raise ValueError('Monthly Go allowance must be positive')
        cost += amount(go['allowanceUSD']) / pool * fee
    return {**run, 'usage': {**captured, 'costUSD': str(cost),
                           'source': captured['source'] + '; Go fee allocated by monthly allowance share'}}


def totals_row(label, runs, include_estimates, format_cost=money):
    values = []
    for key in ('input', 'cacheRead', 'cacheWrite', 'output'):
        known = [r['usage'][key] for r in runs if r.get('usage') and r['usage'].get(key) is not None]
        partial = len(known) != len(runs) or any(incomplete(r) for r in runs)
        values.append((f'{sum(known):,}' + (' (partial)' if partial else '')) if known else 'unavailable')
    for billed in ([True, False] if include_estimates else [True]):
        evidence = [r['usage'] for r in runs if r.get('usage') and r['usage'].get('costUSD') is not None and bool(r['usage'].get('billed')) == billed]
        if evidence:
            values.append(format_cost(sum((Decimal(u['costUSD']) for u in evidence), Decimal('0'))))
        else:
            values.append('—' if not billed and all(not incomplete(r) for r in runs) else 'unavailable')
    return '| ' + label + ' | ' + ' | '.join(values) + ' |'


def go_table(runs):
    go_runs = [r for r in runs if r['model'].startswith('opencode-go/')]
    if not go_runs:
        return []
    lines = ['', 'Go subscription usage (not additional billed spend):', '',
             '| Go model | List-price usage USD | Allowance usage USD |', '|---|---:|---:|']
    groups = [(model_name(next(r for r in go_runs if r['model'] == model)),
               [r for r in go_runs if r['model'] == model]) for model in dict.fromkeys(r['model'] for r in go_runs)]
    for label, group in [*groups, ('**Total**', go_runs)]:
        evidence = []
        for run in group:
            captured = run.get('usage') or {}
            if captured.get('billed'):
                evidence.append(captured.get('goUsage'))
            else:
                partial = (run.get('partialBilledUsage') or {}).get('goUsage')
                # Empty accumulators are not an authoritative zero receipt.
                evidence.append(partial if partial and partial.get('billingSources') else None)
        values = []
        for key in ('listCostUSD', 'allowanceUSD'):
            known = [amount(u[key]) for u in evidence if u and u.get(key) is not None]
            partial = len(known) != len(group) or any(incomplete(r) for r in group)
            values.append(('$' + format(sum(known, Decimal('0')), '.6f') + (' (partial)' if partial else '')) if known else 'unavailable')
        lines.append('| ' + label + ' | ' + ' | '.join(values) + ' |')
    return lines + ['']


def render(ledger):
    lines = ['## AI review', '', 'Merge policy: ' + ledger['mergePolicy'], '']
    go = any(r['model'].startswith('opencode-go/') for r in ledger['runs'])
    basis = ledger.get('goCostAllocation')
    raw_runs = ledger['runs']
    runs_view = [allocated_run(r, basis) for r in raw_runs]
    format_cost = (lambda value: money(value, 6)) if go else money
    if go:
        if basis:
            lines += [f"Cost basis: API cash charges + Go allowance used / ${cell(basis['monthlyAllowanceUSD'])} × ${cell(basis['monthlyFeeUSD'])} monthly fee.",
                      'Go cost is subscription allocation, not an extra cash charge. Unused allowance stays unallocated.', '']
        else:
            lines += ['Go allocation basis unavailable; covered Go costs cannot be reported as zero.', '']
    url = repository_url(ledger.get('repositoryUrl'))
    billed_total, estimate_total = Decimal('0'), Decimal('0')
    billed_rows = 0
    unavailable = False
    estimated = False
    for round_number, label in sorted(set((r['round'], r.get('roundLabel', str(r['round']))) for r in runs_view)):
        runs = [run for run in runs_view if (run['round'], run.get('roundLabel', str(run['round']))) == (round_number, label)]
        lines += [f'### Round {label}', '',
                  '<details>', '<summary>Review details</summary>', '',
                  '| Model | Effort | Outcome | Time | Input total | Cache read | Cache write | Output total | Cost USD |',
                  '|---|---|---|---|---:|---:|---:|---:|---:|']
        billed_subtotal, estimate_subtotal = Decimal('0'), Decimal('0')
        round_billed_rows = 0
        for run in runs:
            usage = run.get('usage')
            if incomplete(run):
                unavailable = True
            prefix = f"| {model_name(run)} | {cell(run['effort'])} | {cell(run.get('verdict', 'unavailable'))} | {duration(run)} | "
            if usage is None:
                lines.append(prefix + 'unavailable | unavailable | unavailable | unavailable | unavailable |')
                continue
            if usage.get('costUSD') is None:
                pass
            elif usage.get('billed'):
                round_billed_rows += 1
                billed_subtotal += Decimal(usage['costUSD'])
            else:
                estimated = True
                estimate_subtotal += Decimal(usage['costUSD'])
            counts = ['unavailable' if usage.get(key) is None else f'{usage[key]:,}' for key in ('input', 'cacheRead', 'cacheWrite', 'output')]
            qualifier = '' if usage.get('billed') else ' estimate'
            displayed_cost = format_cost(usage['costUSD']) + qualifier if usage.get('costUSD') is not None else 'unavailable'
            lines.append(prefix + ' | '.join(counts) + f" | {displayed_cost} |")
        billed_total += billed_subtotal
        billed_rows += round_billed_rows
        estimate_total += estimate_subtotal
        lines += ['', '| Model | Review type | Commit range |', '|---|---|---|']
        lines += [f'| {model_name(run)} | {review_type(run)} | {review_range(run, url)} |' for run in runs]
        sources = sorted({r['usage']['source'] for r in runs if r.get('usage')})
        lines += ['', 'Cost sources: ' + '; '.join(cell(source) for source in sources) + '.' if sources else 'Cost source: unavailable.', '',
                  ('**Round review cost subtotal: ' if go else '**Round billed subtotal: ') + (format_cost(billed_subtotal) if round_billed_rows else 'unavailable') + '**', '']
        if any(r.get('usage') and not r['usage'].get('billed') for r in runs):
            lines += ['**Round estimate subtotal (not billed): ' + format_cost(estimate_subtotal) + '**', '']
        lines += go_table([r for r in raw_runs if (r['round'], r.get('roundLabel', str(r['round']))) == (round_number, label)])
        lines += ['</details>', '']
    lines += ['### Totals', '',
              '| Model | Input total | Cache read | Cache write | Output total | ' + ('Cost USD' if go else 'Cost USD (billed)') + ' |' + (' Estimate USD (not billed) |' if estimated else ''),
              '|---|---:|---:|---:|---:|---:|' + ('---:|' if estimated else '')]
    models = dict.fromkeys(r['model'] for r in runs_view)
    for model in models:
        runs = [r for r in runs_view if r['model'] == model]
        lines.append(totals_row(model_name(runs[0]), runs, estimated, format_cost))
    lines += [totals_row('**Total**', runs_view, estimated, format_cost), '']
    label = ('Recorded review cost subtotal' if estimated or unavailable else 'Total review cost') if go else ('Recorded billed subtotal' if estimated or unavailable else 'Total billed review cost')
    lines += ['**' + label + ': ' + (format_cost(billed_total) if billed_rows else 'unavailable') + '**', '']
    if estimated:
        lines += ['**Recorded estimate subtotal (not billed): ' + format_cost(estimate_total) + '**', '']
    if go:
        lines += ['<details>', '<summary>Provider accounting audit</summary>', '']
        lines += go_table(raw_runs)
        lines += ['Raw cash, list-price and allowance receipts remain unchanged in the ledger. Credit-purchase fees and tax are excluded.', '</details>', '']
    lines += [
              'Pre-PR sessions only. Input total includes cache reads/writes; output total includes reasoning exactly once.',
              'Time is session wall time, including tool steps and native compaction, excluding time queued before session creation.',
              'Totals use unrounded costs; displayed dollars use ' + ('six decimals' if go else 'cents') + '. Partial token totals show known usage only.']
    if not url:
        lines += ['', 'Repository URL unavailable; short ranges are shown without explicit comparison links.']
    if unavailable:
        lines += ['', '**Accounting incomplete:** missing usage is not zero cost.']
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ledger', required=True)
    sub = parser.add_subparsers(dest='command', required=True)
    init = sub.add_parser('init')
    init.add_argument('--repo', required=True)
    init.add_argument('--merge-policy', choices=['automatic', 'manual'], default='automatic')
    init.add_argument('--scope', required=True, help='Use the classified scope route and its round cap')
    init.add_argument('--repository-url', help='Verified HTTPS repository web URL for short commit comparison links')
    record = sub.add_parser('record')
    record.add_argument('--run-file', required=True)
    collect = sub.add_parser('collect')
    collect.add_argument('--run-id', required=True)
    collect.add_argument('--opencode', required=True)
    collect.add_argument('--task-state', required=True, help='Saved terminal T3 task_status structured result')
    collect.add_argument('--allow-estimate', action='store_true', help='Record incomplete billing evidence honestly; never supplies review approval')
    output = sub.add_parser('render')
    output.add_argument('--output', required=True)
    output.add_argument('--repository-url', help='Repository web URL when rendering a legacy ledger')
    output.add_argument('--go-monthly-fee-usd', help='Explicitly record the Go allocation fee on an existing ledger')
    output.add_argument('--go-monthly-allowance-usd', help='Weighted monthly Go pool in receipt allowance dollars')
    output.add_argument('--go-billing-source', choices=['go', 'go-plus'], help='Verified subscription source; otherwise retain the ledger source')
    args = parser.parse_args()
    if args.command == 'init':
        if Path(args.ledger).exists():
            raise ValueError('Ledger exists; resume it rather than resetting review history')
        scope = load(args.scope)
        if Path(scope['repo']).resolve() != Path(args.repo).resolve():
            raise ValueError('Scope belongs to another worktree')
        cap = scope['route']['roundCap']
        expected = POLICY['roundCaps']['securityOrState' if set(POLICY['mixing']['protectedCategories']) & set(scope['route']['checklists']) else 'normal']
        if cap != expected:
            raise ValueError('Invalid route cap')
        save(args.ledger, {'repo': str(Path(args.repo).resolve()), 'mergePolicy': args.merge_policy,
                           'repositoryUrl': repository_url(args.repository_url),
                           'roundCap': cap, 'route': scope['route'], 'runs': [],
                           'goCostAllocation': POLICY['goCostAllocation']})
        return
    ledger = load(args.ledger)
    if args.command == 'record':
        run = load(args.run_file)
        for key in ['id', 'round', 'marker', 'model', 'effort', 'from', 'head']:
            if not run.get(key):
                raise ValueError('Missing run field: ' + key)
        if not isinstance(run['round'], int) or not 1 <= run['round'] <= ledger['roundCap']:
            raise ValueError('Review round exceeds the run cap')
        model = next((m for m in POLICY['models'].values() if m['id'] == run['model']), None)
        if not model or run['effort'] not in model['efforts']:
            raise ValueError('Model/effort is not in the accepted review policy')
        validate_assignment(ledger, run)
        old = next((item for item in ledger['runs'] if item['id'] == run['id']), None)
        if old:
            if any(old[key] != run[key] for key in ['marker', 'model', 'effort', 'from', 'head', 'round']):
                raise ValueError('Run identity changed')
            if any(old.get(key) and run.get(key) and old[key] != run[key] for key in ('taskId', 'threadId', 'sessionID')):
                raise ValueError('A retried launch requires a fresh run ID/marker, not a replacement task/session')
            old.update(run)
        else:
            ledger['runs'].append(run)
        save(args.ledger, ledger)
    elif args.command == 'collect':
        run = next(item for item in ledger['runs'] if item['id'] == args.run_id)
        state = load(args.task_state)
        if state.get('taskId') != run.get('taskId') or state.get('childThreadId') != run.get('threadId') or state.get('status') not in ('completed', 'failed', 'cancelled', 'interrupted') or state.get('hasPendingChildRuns') or state.get('hasPendingQuestion'):
            raise ValueError('Usage collection requires the owned terminal T3 task, without live descendants/questions')
        session, messages = correlate(args.opencode, run, ledger['repo'])
        run['sessionID'] = session['id']
        if not session.get('outcome') or not session.get('time', {}).get('idle'):
            raise ValueError('OpenCode session is not terminal')
        run['timing'] = session_timing(session)
        run['status'] = state['status']
        try:
            estimate = reported_usage(messages, run['model'], run['effort'])
            run['openCodeEstimate'] = estimate
            journal = Path(args.ledger).parent / (run['id'] + '.transport.jsonl')
            records = [json.loads(line) for line in journal.read_text(encoding='utf-8').splitlines()] if journal.exists() else []
            collect_usage(run, records, session['id'], estimate, args.allow_estimate)
        except ValueError as error:
            run['accountingError'] = str(error)
            run['usage'] = None
            save(args.ledger, ledger)
            raise
        save(args.ledger, ledger)
        print(json.dumps({'runID': run['id'], 'sessionID': session['id'], 'usage': run['usage']}, indent=2))
    else:
        if args.go_billing_source and not args.go_monthly_fee_usd:
            raise ValueError('Provide both Go allocation amounts with a billing source')
        if bool(args.go_monthly_fee_usd) != bool(args.go_monthly_allowance_usd):
            raise ValueError('Provide both Go allocation amounts together')
        if args.go_monthly_fee_usd:
            fee, pool = amount(args.go_monthly_fee_usd), amount(args.go_monthly_allowance_usd)
            if pool == 0:
                raise ValueError('Monthly Go allowance must be positive')
            source = args.go_billing_source or ledger.get('goCostAllocation', {}).get('billingSource')
            if source not in ('go', 'go-plus'):
                raise ValueError('Provide the verified Go billing source')
            ledger['goCostAllocation'] = {'monthlyFeeUSD': str(fee), 'monthlyAllowanceUSD': str(pool), 'billingSource': source}
            save(args.ledger, ledger)
        if args.repository_url:
            ledger['repositoryUrl'] = repository_url(args.repository_url)
        Path(args.output).write_text(render(ledger), encoding='utf-8')


if __name__ == '__main__':
    main()
