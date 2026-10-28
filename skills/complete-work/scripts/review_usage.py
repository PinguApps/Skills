"""Collect review-only OpenCode session usage and render per-round PR accounting.

The parent records run IDs before delegation and task/thread IDs afterwards.
No inference requests or credentials are made/read by this helper.
"""
import argparse
from decimal import Decimal, ROUND_HALF_UP
import json
import os
from pathlib import Path
import subprocess
import re

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
        if expected_effort and model.get('variant') != expected_effort:
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
        super().__init__('Incomplete OpenRouter billing evidence; retain journal and reconcile')
        self.partial = partial


def billed_usage(records, run, session_id):
    requests, responses, usage, capture_errors = {}, {}, {}, set()
    guards = []
    for entry in records:
        if entry.get('sessionID') and entry['sessionID'] != session_id:
            raise ValueError('Transport record belongs to a different review session')
        if entry.get('event') == 'blocked-tool':
            raise ValueError('Review tool guard breach; investigate before accepting coverage')
        if entry.get('event') == 'guard':
            if entry.get('tools') != ['pingu_review_source']:
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
                value.get('cost') is None or value.get('prompt_tokens') is None or
                value.get('completion_tokens') is None or not item.get('generationID')):
            missing.append(request)
            continue
        generation = item['generationID']
        if generation in generation_ids:
            raise ValueError('Duplicate OpenRouter generation across physical requests; reconcile before summing')
        generation_ids.add(generation)
        totals['input'] += value['prompt_tokens']
        peak_prompt = max(peak_prompt, value['prompt_tokens'])
        compaction_calls += requests[request].get('kind') == 'compaction'
        totals['output'] += value['completion_tokens']
        totals['reasoning'] += value.get('completion_tokens_details', {}).get('reasoning_tokens', 0)
        for field, key in [('cacheRead', 'cached_tokens'), ('cacheWrite', 'cache_write_tokens')]:
            amount = value.get('prompt_tokens_details', {}).get(key)
            totals[field] = None if amount is None or totals[field] is None else totals[field] + amount
        cost += Decimal(str(value['cost']))
    result = {**totals, 'costUSD': str(cost), 'billed': not missing, 'source': 'OpenRouter response usage.cost',
            'peakPromptTokens': peak_prompt, 'modelCalls': len(requests), 'compactionCalls': compaction_calls,
            'generationIDs': sorted(generation_ids), 'missingUsageMessageIDs': missing}
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
    allowed = list(route['reviewers'])
    for chain in route.get('escalationByCategory', {}).values():
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


def money(value):
    return '$' + str(Decimal(str(value)).quantize(Decimal('.01'), rounding=ROUND_HALF_UP))


def render(ledger):
    lines = ['## AI review', '', 'Merge policy: ' + ledger['mergePolicy'], '']
    billed_total, estimate_total = Decimal('0'), Decimal('0')
    unavailable = False
    estimated = False
    for round_number, label in sorted(set((r['round'], r.get('roundLabel', str(r['round']))) for r in ledger['runs'])):
        runs = [run for run in ledger['runs'] if (run['round'], run.get('roundLabel', str(run['round']))) == (round_number, label)]
        notes = []
        lines += [f'### Round {label}', '',
                  '| Model | Effort | Input total | Cache read | Cache write | Output total | Cost USD |',
                  '|---|---|---:|---:|---:|---:|---:|']
        billed_subtotal, estimate_subtotal = Decimal('0'), Decimal('0')
        for run in runs:
            usage = run.get('usage')
            if usage is None or usage.get('missingUsageMessageIDs') or run.get('accountingIncomplete'):
                unavailable = True
            if usage is None:
                lines.append(f"| {run['model']} | {run['effort']} | unavailable | unavailable | unavailable | unavailable | unavailable |")
                continue
            if usage.get('billed'):
                billed_subtotal += Decimal(usage['costUSD'])
            else:
                estimated = True
                estimate_subtotal += Decimal(usage['costUSD'])
            counts = ['unavailable' if usage.get(key) is None else f'{usage[key]:,}' for key in ('input', 'cacheRead', 'cacheWrite', 'output')]
            qualifier = '' if usage.get('billed') else ' estimate'
            lines.append(f"| {run['model']} | {run['effort']} | " + ' | '.join(counts) + f" | {money(usage['costUSD'])}{qualifier} |")
            notes.append(f"Reviewed `{run['from']}` → `{run['head']}`; outcome: {run.get('verdict', 'not recorded')}. Cost source: {usage['source']}.")
        billed_total += billed_subtotal
        estimate_total += estimate_subtotal
        lines += ['', *notes, '', '**Round billed subtotal: ' + money(billed_subtotal) + '**', '']
        if any(r.get('usage') and not r['usage'].get('billed') for r in runs):
            lines += ['**Round estimate subtotal (not billed): ' + money(estimate_subtotal) + '**', '']
    label = 'Recorded billed subtotal' if estimated or unavailable else 'Total billed review cost'
    lines += ['**' + label + ': ' + money(billed_total) + '**', '']
    if estimated:
        lines += ['**Recorded estimate subtotal (not billed): ' + money(estimate_total) + '**', '']
    lines += [
              'Pre-PR sessions only. Input total includes cache reads/writes; output total includes reasoning exactly once.']
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
    record = sub.add_parser('record')
    record.add_argument('--run-file', required=True)
    collect = sub.add_parser('collect')
    collect.add_argument('--run-id', required=True)
    collect.add_argument('--opencode', required=True)
    collect.add_argument('--task-state', required=True, help='Saved terminal T3 task_status structured result')
    collect.add_argument('--allow-estimate', action='store_true', help='Record incomplete billing evidence honestly; never supplies review approval')
    output = sub.add_parser('render')
    output.add_argument('--output', required=True)
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
                           'roundCap': cap, 'route': scope['route'], 'runs': []})
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
        Path(args.output).write_text(render(ledger), encoding='utf-8')


if __name__ == '__main__':
    main()
