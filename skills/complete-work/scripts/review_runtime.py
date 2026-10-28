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
        record = json.loads(receipt.read_text(encoding='utf-8'))
        if loader.exists():
            if str(loader) != record['loader'] or hashlib.sha256(loader.read_bytes()).hexdigest() != record['sha256']:
                raise ValueError('Loader changed; preserve it and reconcile ownership')
            loader.unlink()
        print('Removed owned runtime loader; retained usage and results outside the repository.')
        return
    config_path = state / 'runtime.json'
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
    config = {'repo': str(repo), 'state': str(state), 'python': sys.executable,
              'helper': str(scripts / 'review_scope.py'), 'runs': ledger['runs']}
    digest = hashlib.sha256()
    for file in (scripts / 'review-runtime.mjs', scripts / 'review_scope.py', refs / 'review-policy.json'):
        digest.update(file.read_bytes())
    config['runtimeDigest'] = digest.hexdigest()
    for run in config['runs']:
        for key in ('id', 'marker', 'head', 'from', 'base', 'scope', 'title', 'model', 'effort'):
            if not run.get(key):
                raise ValueError('Runtime run requires ' + key)
        if Path(run['id']).name != run['id'] or '/' in run['id'] or '\\' in run['id']:
            raise ValueError('Invalid run ID')
        manifest = json.loads(Path(run['scope']).read_text(encoding='utf-8-sig'))
        if Path(manifest['repo']).resolve() != repo or manifest['head'] != run['head']:
            raise ValueError('Runtime scope belongs to another worktree/head')
    config_path.write_text(json.dumps(config, indent=2), encoding='utf-8')
    content = ('import runtime from ' + json.dumps((scripts / 'review-runtime.mjs').as_uri() + '?v=' + config['runtimeDigest']) + ';\n'
               'export default runtime(' + json.dumps(str(config_path)) + ');\n').encode()
    if loader.exists():
        prior = json.loads(receipt.read_text(encoding='utf-8')) if receipt.exists() else {}
        if prior.get('loader') != str(loader) or prior.get('sha256') != hashlib.sha256(loader.read_bytes()).hexdigest():
            raise ValueError('Existing loader is not owned by this run')
        if loader.read_bytes() != content:
            raise ValueError('Runtime loader changed; reconcile before updating')
    else:
        loader.parent.mkdir(parents=True, exist_ok=True)
        with loader.open('xb') as stream:
            stream.write(content)
    receipt.write_text(json.dumps({'loader': str(loader), 'sha256': hashlib.sha256(content).hexdigest()}, indent=2), encoding='utf-8')
    print(json.dumps({'loader': str(loader), 'config': str(config_path),
                      'ready': str(state / 'runtime-ready.json')}))


if __name__ == '__main__':
    main()
