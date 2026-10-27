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
        data = response.get('data', [])
        if not isinstance(data, list):
            raise ValueError('Unexpected OpenCode list response')
        yield from data
        cursor = response.get('cursor', {}).get('next') if isinstance(response.get('cursor'), dict) else None
        if not cursor:
            return
        if cursor in seen:
            raise ValueError('Repeated OpenCode pagination cursor')
        seen.add(cursor)
        params['cursor'] = cursor


def user_text(message):
    if message.get('type') != 'user':
        return ''
    content = message.get('content', [])
    if isinstance(content, str):
        return content
    return '\n'.join(part.get('text', '') for part in content if isinstance(part, dict))


def correlate(executable, run, directory):
    matches = []
    for session in pages(executable, 'session.list', directory=directory, limit=100):
        messages = list(pages(executable, 'session.message.list', sessionID=session['id'], limit=100))
        if any(run['marker'] in user_text(message) for message in messages):
            matches.append((session, messages))
    if len(matches) != 1:
        raise ValueError(f'Expected one session containing the exact run marker; found {len(matches)}')
    return matches[0]


def reported_usage(messages, expected_model):
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
        if model and model.get('providerID', '') + '/' + model.get('modelID', '') != expected_model:
            raise ValueError('Unexpected auxiliary model in review session: ' + str(model))
        tokens = message.get('tokens')
        if tokens is None or message.get('cost') is None:
            # Streaming/tool-only messages without usage must not turn into $0.
            missing.append(identifier)
            continue
        for source, target in [('input', 'input'), ('output', 'output'), ('reasoning', 'reasoning')]:
            totals[target] += tokens.get(source, 0)
        totals['cacheRead'] += tokens.get('cache', {}).get('read', 0)
        totals['cacheWrite'] += tokens.get('cache', {}).get('write', 0)
        cost += Decimal(str(message['cost']))
    return {**totals, 'costUSD': str(cost), 'source': 'OpenCode reported; billed-cost provenance requires verification',
            'messageIDs': sorted(ids), 'missingUsageMessageIDs': missing}


def money(value):
    return '$' + str(Decimal(str(value)).quantize(Decimal('.01'), rounding=ROUND_HALF_UP))


def render(ledger):
    lines = ['## AI review', '', 'Merge policy: ' + ledger['mergePolicy'], '']
    total = Decimal('0')
    unavailable = False
    for round_number in sorted(set(run['round'] for run in ledger['runs'])):
        runs = [run for run in ledger['runs'] if run['round'] == round_number]
        notes = []
        lines += [f'### Round {round_number}', '',
                  '| Model | Effort | Input (reported) | Cache read | Cache write | Output (reported) | Cost USD |',
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
            lines.append(f"| {run['model']} | {run['effort']} | {usage['input']:,} | {usage['cacheRead']:,} | {usage['cacheWrite']:,} | {usage['output']:,} | {money(usage['costUSD'])} |")
            notes.append(f"Reviewed `{run['from']}` → `{run['head']}`; outcome: {run.get('verdict', 'not recorded')}. Cost source: {usage['source']}.")
        total += subtotal
        lines += ['', *notes, '', '**Round subtotal: ' + money(subtotal) + '**', '']
    lines += ['**Total recorded review cost: ' + money(total) + '**', '',
              'Review costs cover pre-PR sessions only. Output and reasoning are recorded separately; reasoning is not added to output a second time.']
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
    init.add_argument('--sensitive', action='store_true', help='Security/auth/permissions/data-loss/state route: cap at five')
    record = sub.add_parser('record')
    record.add_argument('--run-file', required=True)
    collect = sub.add_parser('collect')
    collect.add_argument('--run-id', required=True)
    collect.add_argument('--opencode', required=True)
    output = sub.add_parser('render')
    output.add_argument('--output', required=True)
    args = parser.parse_args()
    if args.command == 'init':
        if Path(args.ledger).exists():
            raise ValueError('Ledger exists; resume it rather than resetting review history')
        save(args.ledger, {'repo': str(Path(args.repo).resolve()), 'mergePolicy': args.merge_policy,
                           'roundCap': POLICY['roundCaps']['securityOrState' if args.sensitive else 'normal'], 'runs': []})
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
        session, messages = correlate(args.opencode, run, ledger['repo'])
        run['sessionID'] = session['id']
        run['usage'] = reported_usage(messages, run['model'])
        save(args.ledger, ledger)
        print(json.dumps({'runID': run['id'], 'sessionID': session['id'], 'usage': run['usage']}, indent=2))
    else:
        Path(args.output).write_text(render(ledger), encoding='utf-8')


if __name__ == '__main__':
    main()
