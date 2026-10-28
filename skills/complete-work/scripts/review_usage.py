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
        lines = re.findall(r'^Review-Run-ID: \S+$', user_text(users[0]), flags=re.MULTILINE) if users else []
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
        model = message.get('model', {})
        if model.get('providerID', '') + '/' + model.get('id', model.get('modelID', '')) != expected_model:
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
            'messageIDs': sorted(ids), 'missingUsageMessageIDs': missing}


def billed_usage(records, run, session_id):
    responses, usage, finished = {}, {}, set()
    guards = []
    for entry in records:
        if entry.get('event') == 'guard':
            guards.append(entry)
        if entry.get('event') not in ('request', 'response', 'usage', 'end'):
            continue
        if entry.get('sessionID') != session_id or entry.get('model') != run['model'] or entry.get('effort') != run['effort']:
            raise ValueError('Transport record belongs to a different review session/model/effort')
        request = entry['requestID']
        if entry['event'] == 'request':
            responses[request] = entry
        elif entry['event'] == 'usage':
            usage[request] = entry
        elif entry.get('complete'):
            finished.add(request)
    if not responses or not guards or any(g['tools'] != ['pingu_review_source'] for g in guards):
        raise ValueError('Missing filtered-tool guard or transport evidence')
    totals = dict(input=0, output=0, reasoning=0, cacheRead=0, cacheWrite=0)
    cost = Decimal('0')
    generation_ids, missing = set(), []
    peak_prompt, compaction_calls = 0, 0
    for request in responses:
        item = usage.get(request, {})
        value = item.get('usage', {})
        if request not in finished or value.get('cost') is None or not item.get('generationID'):
            missing.append(request)
            continue
        generation = item['generationID']
        if generation in generation_ids:
            raise ValueError('Duplicate OpenRouter generation across physical requests; reconcile before summing')
        generation_ids.add(generation)
        if value.get('prompt_tokens') is None or value.get('completion_tokens') is None:
            raise ValueError('Missing billed token counts')
        totals['input'] += value['prompt_tokens']
        peak_prompt = max(peak_prompt, value['prompt_tokens'])
        compaction_calls += responses[request].get('kind') == 'compaction'
        totals['output'] += value['completion_tokens']
        totals['reasoning'] += value.get('completion_tokens_details', {}).get('reasoning_tokens', 0)
        for field, key in [('cacheRead', 'cached_tokens'), ('cacheWrite', 'cache_write_tokens')]:
            amount = value.get('prompt_tokens_details', {}).get(key)
            totals[field] = None if amount is None or totals[field] is None else totals[field] + amount
        cost += Decimal(str(value['cost']))
    return {**totals, 'costUSD': str(cost), 'billed': True, 'source': 'OpenRouter response usage.cost',
            'peakPromptTokens': peak_prompt, 'modelCalls': len(responses), 'compactionCalls': compaction_calls,
            'generationIDs': sorted(generation_ids), 'missingUsageMessageIDs': missing}


def money(value):
    return '$' + str(Decimal(str(value)).quantize(Decimal('.01'), rounding=ROUND_HALF_UP))


def render(ledger):
    lines = ['## AI review', '', 'Merge policy: ' + ledger['mergePolicy'], '']
    total = Decimal('0')
    unavailable = False
    estimated = any(not run.get('usage', {}).get('billed', False) for run in ledger['runs'])
    for round_number in sorted(set(run['round'] for run in ledger['runs'])):
        runs = [run for run in ledger['runs'] if run['round'] == round_number]
        notes = []
        lines += [f'### Round {round_number}', '',
                  '| Model | Effort | Input total | Cache read | Cache write | Output total | Cost USD |',
                  '|---|---|---:|---:|---:|---:|---:|']
        subtotal = Decimal('0')
        for run in runs:
            usage = run.get('usage')
            if usage is None or usage.get('missingUsageMessageIDs'):
                unavailable = True
            if usage is None:
                lines.append(f"| {run['model']} | {run['effort']} | unavailable | unavailable | unavailable | unavailable | unavailable |")
                continue
            subtotal += Decimal(usage['costUSD'])
            counts = ['unavailable' if usage.get(key) is None else f'{usage[key]:,}' for key in ('input', 'cacheRead', 'cacheWrite', 'output')]
            qualifier = '' if usage.get('billed') else ' estimate'
            lines.append(f"| {run['model']} | {run['effort']} | " + ' | '.join(counts) + f" | {money(usage['costUSD'])}{qualifier} |")
            notes.append(f"Reviewed `{run['from']}` → `{run['head']}`; outcome: {run.get('verdict', 'not recorded')}. Cost source: {usage['source']}.")
        total += subtotal
        lines += ['', *notes, '', '**Round subtotal: ' + money(subtotal) + '**', '']
    label = 'Total recorded estimate (billed total unavailable)' if estimated else 'Total billed review cost'
    lines += ['**' + label + ': ' + money(total) + '**', '',
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
        expected = POLICY['roundCaps']['securityOrState' if {'security', 'state'} & set(scope['route']['checklists']) else 'normal']
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
        old = next((item for item in ledger['runs'] if item['id'] == run['id']), None)
        if old:
            if any(old[key] != run[key] for key in ['marker', 'model', 'effort', 'from', 'head', 'round']):
                raise ValueError('Run identity changed')
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
        estimate = reported_usage(messages, run['model'], run['effort'])
        journal = Path(args.ledger).parent / (run['id'] + '.transport.jsonl')
        if journal.exists():
            run['usage'] = billed_usage([json.loads(line) for line in journal.read_text(encoding='utf-8').splitlines()], run, session['id'])
            if run['usage']['missingUsageMessageIDs'] and not args.allow_estimate:
                raise ValueError('Incomplete OpenRouter billing evidence; retain journal and reconcile')
        elif args.allow_estimate:
            run['usage'] = estimate
        else:
            raise ValueError('Missing actual OpenRouter usage capture; no billed total can be claimed')
        run['openCodeEstimate'] = estimate
        save(args.ledger, ledger)
        print(json.dumps({'runID': run['id'], 'sessionID': session['id'], 'usage': run['usage']}, indent=2))
    else:
        Path(args.output).write_text(render(ledger), encoding='utf-8')


if __name__ == '__main__':
    main()
