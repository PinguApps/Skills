"""Build committed review scope and serve content through head .pragentignore rules.

Uses Git's matcher in a disposable policy-only repository, never the caller's
.gitignore or personal excludes. No third-party Python packages are required.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tempfile

POLICY = json.loads((Path(__file__).parents[1] / 'references/review-policy.json').read_text(encoding='utf-8'))
DOC = set(POLICY['documentationExtensions'])
MEDIA = set(('.png .jpg .jpeg .gif .svg .svgz .webp .avif .ico .bmp .tif .tiff '
             '.heic .pen .fig .psd .mp3 .mp4 .mov .webm .wav .ogg .flac '
             '.woff .woff2 .ttf .otf .eot .pdf .zip .gz .7z .rar .dll .exe '
             '.pdb .wasm .nupkg .docx .xlsx .pptx').split())


def run_git(repo, *args, input=None, isolated=False, allowed=(0,)):
    executable = shutil.which('git')
    if not executable:
        raise RuntimeError('Git is required')
    env = dict(os.environ)
    # Remove inherited repository/index overrides without changing PATH.
    for key in list(env):
        if key.startswith('GIT_'):
            env.pop(key)
    if isolated:
        env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL=os.devnull)
    result = subprocess.run([executable, '-C', str(repo), *args], input=input,
                            capture_output=True, env=env)
    if result.returncode not in allowed:
        raise RuntimeError(result.stderr.decode('utf-8', errors='replace').strip())
    return result.stdout


def commit(repo, ref):
    return run_git(repo, 'rev-parse', '--verify', ref + '^{commit}').decode().strip()


def tree(repo, ref):
    entries = {}
    for row in run_git(repo, 'ls-tree', '-rz', ref).split(b'\0'):
        if row:
            meta, name = row.split(b'\t', 1)
            mode, kind, sha = meta.decode().split()
            entries[name.decode('utf-8')] = (mode, kind, sha)
    return entries


def safe_path(path):
    value = PurePosixPath(path)
    if not path or '\\' in path or ':' in path or value.is_absolute() or '..' in value.parts:
        raise ValueError('Expected a repository-relative /-separated path')
    return str(value)


class Scope:
    def __init__(self, repo, head):
        self.repo = Path(repo).resolve()
        root = Path(run_git(self.repo, 'rev-parse', '--show-toplevel').decode().strip()).resolve()
        if root != self.repo:
            raise ValueError('--repo must be the current worktree root, not a subdirectory')
        self.head = commit(self.repo, head)
        self.head_tree = tree(self.repo, self.head)
        self.policies = {}
        digest = hashlib.sha256()
        for path, (mode, kind, sha) in sorted(self.head_tree.items()):
            if PurePosixPath(path).name != '.pragentignore':
                continue
            if mode not in ('100644', '100755') or kind != 'blob':
                raise ValueError('Policy must be a regular UTF-8 file: ' + path)
            raw = run_git(self.repo, 'cat-file', 'blob', sha)
            content = raw.decode('utf-8-sig')
            if '\0' in content:
                raise ValueError('Binary ignore policy: ' + path)
            self.policies[path] = content
            digest.update(path.encode() + b'\0' + raw + b'\0')
        self.digest = digest.hexdigest()

    def matching(self, paths):
        paths = list(dict.fromkeys(safe_path(p) for p in paths))
        if not paths:
            return {}
        with tempfile.TemporaryDirectory(prefix='review-policy-') as directory:
            sandbox = Path(directory)
            template = sandbox / 'empty-template'
            template.mkdir()
            run_git(sandbox, 'init', '--quiet', '--template=' + str(template),
                    '--initial-branch=review', isolated=True)
            for path, content in self.policies.items():
                target = sandbox / PurePosixPath(path).parent / '.gitignore'
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_text(content, encoding='utf-8')
            for path in paths:
                (sandbox / PurePosixPath(path).parent).mkdir(parents=True, exist_ok=True)
            raw = run_git(sandbox, '-c', 'core.ignoreCase=false', '-c',
                          'core.excludesFile=' + os.devnull, 'check-ignore',
                          '--no-index', '--verbose', '--non-matching', '-z', '--stdin',
                          input=('\0'.join(paths) + '\0').encode(), isolated=True,
                          allowed=(0, 1))
        values = raw.decode('utf-8').split('\0')
        result = {}
        for i in range(0, len(values) - 1, 4):
            source, line, pattern, path = values[i:i + 4]
            excluded = bool(pattern) and not pattern.startswith('!')
            if PurePosixPath(path).name == '.pragentignore':
                excluded = False
            result[path] = {'excluded': excluded, 'policy': source.replace('.gitignore', '.pragentignore')
                            if source else None, 'line': int(line) if line else None,
                            'pattern': pattern or None}
        return result

    def read(self, path, ref, offset=0, limit=12000):
        path = safe_path(path)
        match = self.matching([path])[path]
        if match['excluded']:
            return {**match, 'path': path, 'complete': True, 'nextOffset': None}
        sha = commit(self.repo, ref)
        entry = tree(self.repo, sha).get(path)
        if not entry:
            return {'path': path, 'exists': False, 'complete': True, 'nextOffset': None}
        if entry[0] not in ('100644', '100755') or entry[1] != 'blob':
            return {'path': path, 'needsExclusionAssessment': True, 'reason': 'non-regular file'}
        raw = run_git(self.repo, 'cat-file', 'blob', entry[2])
        try:
            if b'\0' in raw[:8000]:
                raise UnicodeError('binary')
            text = raw.decode('utf-8-sig')
        except UnicodeError:
            return {'path': path, 'needsExclusionAssessment': True, 'reason': 'binary/non-UTF8'}
        end = min(offset + limit, len(text))
        return {'path': path, 'ref': sha, 'content': text[offset:end], 'offset': offset,
                'complete': end == len(text), 'nextOffset': end if end < len(text) else None}

    def manifest(self, base, previous=None):
        base = commit(self.repo, base)
        start = base
        reset = False
        if previous:
            old = Scope(self.repo, previous)
            if run_git(self.repo, 'merge-base', old.head, self.head).decode().strip() != old.head:
                raise ValueError('Previous reviewed commit is not an ancestor; reconcile coverage')
            reset = old.digest != self.digest
            if not reset:
                start = old.head
        rows = run_git(self.repo, 'diff', '--no-ext-diff', '--no-textconv',
                       '--numstat', '-z', '--find-renames', start, self.head).split(b'\0')
        changes = []
        i = 0
        while i < len(rows) and rows[i]:
            additions, deletions, name = rows[i].split(b'\t', 2)
            i += 1
            old = new = name.decode('utf-8')
            if not name:
                old, new = rows[i].decode('utf-8'), rows[i + 1].decode('utf-8')
                i += 2
            changes.append({'old': old, 'path': new, 'additions': additions.decode(),
                            'deletions': deletions.decode()})
        matches = self.matching(p for row in changes for p in (row['old'], row['path']))
        totals = {kind: {'files': 0, 'lines': 0} for kind in ('code', 'documentation')}
        selected, excluded, assessments = [], [], []
        for row in changes:
            visible = list(dict.fromkeys(p for p in (row['old'], row['path']) if not matches[p]['excluded']))
            for p in dict.fromkeys((row['old'], row['path'])):
                if matches[p]['excluded']:
                    excluded.append({'path': p, **matches[p]})
            if not visible:
                continue
            if row['additions'] == '-' or any(PurePosixPath(p).suffix.lower() in MEDIA for p in visible):
                assessments.extend(visible)
                continue
            additions, deletions = int(row['additions']), int(row['deletions'])
            if row['old'] != row['path'] and len(visible) == 1:
                p = visible[0]
                result = self.read(p, start if p == row['old'] else self.head, limit=2**31)
                if 'content' not in result:
                    assessments.append(p)
                    continue
                additions, deletions = (0, len(result['content'].splitlines())) if p == row['old'] else (len(result['content'].splitlines()), 0)
            kind = 'documentation' if PurePosixPath(visible[-1]).suffix.lower() in DOC else 'code'
            totals[kind]['files'] += 1
            totals[kind]['lines'] += additions + deletions
            selected.append({**row, 'visiblePaths': visible, 'kind': kind,
                             'additions': additions, 'deletions': deletions})
        return {'repo': str(self.repo), 'base': base, 'from': start, 'head': self.head,
                'policyDigest': self.digest, 'policyReset': reset, 'totals': totals,
                'selected': selected, 'excluded': excluded,
                'needsExclusionAssessment': sorted(set(assessments))}


def size_band(kind, files, lines):
    if not files:
        return 'none'
    for label, line_limit, file_limit in POLICY['bands'][kind]:
        if lines <= line_limit and files <= file_limit:
            return label
    return 'very large' if kind == 'code' else 'large'


def route_for(manifest, categories, cross_boundary):
    valid = {r['category'] for r in POLICY['routes']}
    if set(categories) - valid:
        raise ValueError('Unknown review category')
    if not categories:
        categories = ['general' if manifest['totals']['code']['files'] else 'documentation']
    chosen = next(r for r in POLICY['routes'] if r['category'] in categories)
    reviewers = chosen['reviewers']
    band = manifest['totals']['code']['band']
    if chosen['category'] == 'general':
        if band == 'small':
            reviewers = [['haiku', 'medium'], ['glm', 'high']]
        elif band in ('large', 'very large'):
            reviewers = [['haiku', 'high'], ['minimax', 'high']]
    return {'category': chosen['category'], 'checklists': categories, 'reviewers': reviewers,
            'escalation': chosen['escalation'],
            'integration': ['step', 'medium'] if cross_boundary and band in ('large', 'very large') else None,
            'roundCap': POLICY['roundCaps']['securityOrState' if {'security', 'state'} & set(categories) else 'normal']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo', required=True)
    parser.add_argument('--head', required=True)
    sub = parser.add_subparsers(dest='command', required=True)
    manifest = sub.add_parser('scope')
    manifest.add_argument('--base', required=True)
    manifest.add_argument('--previous')
    manifest.add_argument('--output', required=True)
    manifest.add_argument('--category', action='append', default=[])
    manifest.add_argument('--cross-boundary-contract', action='store_true')
    for name in ('read', 'diff', 'search'):
        child = sub.add_parser(name)
        child.add_argument('--offset', type=int, default=0)
        child.add_argument('--limit', type=int, default=12000)
        if name == 'read':
            child.add_argument('--ref', required=True)
            child.add_argument('--path', required=True)
        elif name == 'diff':
            child.add_argument('--scope', required=True)
        else:
            child.add_argument('--ref', required=True)
            child.add_argument('--pattern', required=True)
            child.add_argument('--path-prefix', default='')
    args = parser.parse_args()
    scope = Scope(args.repo, args.head)
    if args.command == 'scope':
        result = scope.manifest(args.base, args.previous)
        for kind, values in result['totals'].items():
            values['band'] = size_band(kind, **values)
        result['route'] = route_for(result, args.category, args.cross_boundary_contract)
        Path(args.output).write_text(json.dumps(result, indent=2), encoding='utf-8')
        print(json.dumps(result, indent=2))
    elif args.offset < 0 or args.limit < 1:
        raise ValueError('offset must be non-negative and limit positive')
    elif args.command == 'read':
        print(json.dumps(scope.read(args.path, args.ref, args.offset, args.limit)))
    elif args.command == 'diff':
        saved = json.loads(Path(args.scope).read_text(encoding='utf-8'))
        if saved['head'] != scope.head or saved['policyDigest'] != scope.digest or Path(saved['repo']).resolve() != scope.repo:
            raise ValueError('Scope does not belong to this worktree/head/policy')
        # Rebuild instead of trusting editable visiblePaths in a saved manifest.
        fresh = scope.manifest(saved['base'], saved['from'] if saved['from'] != saved['base'] else None)
        if fresh['needsExclusionAssessment']:
            raise ValueError('Assess and commit missing artifact exclusions before review')
        chunks = []
        for row in fresh['selected']:
            paths = [':(literal)' + p for p in row['visiblePaths']]
            renames = '--no-renames' if row['old'] != row['path'] and len(paths) == 1 else '--find-renames'
            chunks.append(run_git(scope.repo, 'diff', '--no-ext-diff', '--no-textconv',
                                  renames, fresh['from'], scope.head, '--', *paths).decode('utf-8'))
        text = '\n'.join(chunks)
        end = min(len(text), args.offset + args.limit)
        print(json.dumps({'content': text[args.offset:end], 'complete': end == len(text),
                          'nextOffset': end if end < len(text) else None}))
    else:
        pattern = re.compile(args.pattern)
        names = [p for p in tree(scope.repo, commit(scope.repo, args.ref)) if p.startswith(args.path_prefix)]
        matches = scope.matching(names)
        hits = []
        for name in names:
            if matches[name]['excluded']:
                continue
            result = scope.read(name, args.ref, limit=2**31)
            for number, line in enumerate(result.get('content', '').splitlines(), 1):
                if pattern.search(line):
                    hits.append({'path': name, 'line': number, 'text': line})
        text = json.dumps(hits)
        end = min(len(text), args.offset + args.limit)
        print(json.dumps({'content': text[args.offset:end], 'complete': end == len(text),
                          'nextOffset': end if end < len(text) else None}))


if __name__ == '__main__':
    main()
