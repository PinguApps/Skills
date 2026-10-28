"""Prepare/remove a worktree-local OpenCode review plugin without editing config.

Keep the manifest/config/transport journals outside the repository. This helper
only installs one new, uniquely named loader file; it never overwrites user files.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import sys
import re
from review_scope import run_git


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ledger', required=True)
    parser.add_argument('command', choices=['prepare', 'remove'])
    args = parser.parse_args()
    ledger_path = Path(args.ledger).resolve()
    ledger = json.loads(ledger_path.read_text(encoding='utf-8-sig'))
    state = ledger_path.parent
    repo = Path(ledger['repo']).resolve()
    identity = hashlib.sha256(str(ledger_path).encode()).hexdigest()[:12]
    loader = repo / '.opencode' / 'plugins' / ('pingu-review-' + identity + '.js')
    receipt = state / 'runtime-install.json'
    if args.command == 'remove':
        if not receipt.exists():
            raise ValueError('Missing runtime ownership receipt; preserve any loader and reconcile before removal')
        record = json.loads(receipt.read_text(encoding='utf-8'))
        if loader.exists():
            if str(loader) != record['loader'] or hashlib.sha256(loader.read_bytes()).hexdigest() != record['sha256']:
                raise ValueError('Loader changed; preserve it and reconcile ownership')
            loader.unlink()
        if record.get('excludeAdded'):
            exclude = Path(record['excludePath'])
            if exclude.exists():
                lines = exclude.read_text(encoding='utf-8').splitlines(keepends=True)
                if sum(line.rstrip('\r\n') == record['excludeRule'] for line in lines) == 1:
                    exclude.write_bytes(''.join(line for line in lines if line.rstrip('\r\n') != record['excludeRule']).encode())
        print('Removed owned runtime loader; retained usage and results outside the repository.')
        return
    config_path = state / 'runtime.json'
    if any(run.get('taskId') and run.get('status') not in ('completed', 'failed', 'cancelled', 'interrupted')
           for run in ledger['runs']):
        raise ValueError('Settle/verify terminal owned tasks and record status before preparing the runtime')
    source = state / 'runtime-source'
    scripts = source / 'scripts'
    refs = source / 'references'
    scripts.mkdir(parents=True, exist_ok=True)
    refs.mkdir(parents=True, exist_ok=True)
    authored = Path(__file__).resolve().parent
    # Freeze the trusted helper and policy, independent of edits being reviewed.
    for filename in ('review_scope.py', 'review-runtime.mjs'):
        shutil.copyfile(authored / filename, scripts / filename)
    shutil.copyfile(authored.parent / 'references/review-policy.json', refs / 'review-policy.json')
    policy = json.loads((refs / 'review-policy.json').read_text(encoding='utf-8'))
    config = {'repo': str(repo), 'state': str(state), 'python': sys.executable,
              'helper': str(scripts / 'review_scope.py'), 'runs': ledger['runs'],
              'pricingGuard': policy['pricingGuard'],
              'models': [m['id'] for m in policy['models'].values()]}
    digest = hashlib.sha256()
    for file in (scripts / 'review-runtime.mjs', scripts / 'review_scope.py', refs / 'review-policy.json'):
        digest.update(file.read_bytes())
    for run in config['runs']:
        for key in ('id', 'marker', 'head', 'from', 'base', 'scope', 'title', 'model', 'effort'):
            if not run.get(key):
                raise ValueError('Runtime run requires ' + key)
        if not re.fullmatch(r'Review-Run-ID: \S+', run['marker']):
            raise ValueError('marker must be a complete Review-Run-ID: <opaque> line')
        if not run.get('taskId') and not run.get('briefFile'):
            raise ValueError('New reviewer runs require a durable briefFile before dispatch')
        if Path(run['id']).name != run['id'] or '/' in run['id'] or '\\' in run['id']:
            raise ValueError('Invalid run ID')
        manifest = json.loads(Path(run['scope']).read_text(encoding='utf-8-sig'))
        if Path(manifest['repo']).resolve() != repo or manifest['head'] != run['head']:
            raise ValueError('Runtime scope belongs to another worktree/head')
        if run.get('briefFile'):
            brief = Path(run['briefFile']).resolve()
            if not brief.is_relative_to(state) or brief.stat().st_size > 64000:
                raise ValueError('Review brief must be a bounded file in the owned external run directory')
            run['reviewContract'] = brief.read_text(encoding='utf-8')
    # New registrations must reload the plugin and publish a fresh ready receipt.
    digest.update(json.dumps([{k: r.get(k) for k in ('id', 'marker', 'model', 'effort', 'head', 'from', 'base', 'scope', 'title', 'reviewContract')}
                              for r in config['runs']], sort_keys=True).encode())
    config['runtimeDigest'] = digest.hexdigest()
    config_path.write_text(json.dumps(config, indent=2), encoding='utf-8')
    content = ('import runtime from ' + json.dumps((scripts / 'review-runtime.mjs').as_uri() + '?v=' + config['runtimeDigest']) + ';\n'
               'export default runtime(' + json.dumps(str(config_path)) + ');\n').encode()
    prior = json.loads(receipt.read_text(encoding='utf-8')) if receipt.exists() else {}
    if prior and prior.get('loader') != str(loader):
        raise ValueError('Runtime ownership receipt belongs to another loader')
    if loader.exists():
        if prior.get('loader') != str(loader) or prior.get('sha256') != hashlib.sha256(loader.read_bytes()).hexdigest():
            raise ValueError('Existing loader is not owned by this run')
        loader.write_bytes(content)
    else:
        loader.parent.mkdir(parents=True, exist_ok=True)
        with loader.open('xb') as stream:
            stream.write(content)
    # Append only the owned filename; preserve all existing info/exclude rules.
    exclude = Path(run_git(repo, 'rev-parse', '--path-format=absolute', '--git-path', 'info/exclude').decode().strip())
    rule = '/' + loader.relative_to(repo).as_posix()
    existing = exclude.read_text(encoding='utf-8') if exclude.exists() else ''
    added = rule not in existing.splitlines()
    if added:
        exclude.parent.mkdir(parents=True, exist_ok=True)
        with exclude.open('a', encoding='utf-8', newline='\n') as stream:
            stream.write(('\n' if existing and not existing.endswith('\n') else '') + rule + '\n')
    receipt.write_text(json.dumps({'loader': str(loader), 'sha256': hashlib.sha256(content).hexdigest(),
                                 'excludePath': str(exclude), 'excludeRule': rule,
                                 'excludeAdded': added or prior.get('excludeAdded', False)}, indent=2), encoding='utf-8')
    print(json.dumps({'loader': str(loader), 'config': str(config_path),
                      'ready': str(state / 'runtime-ready.json')}))


if __name__ == '__main__':
    main()
