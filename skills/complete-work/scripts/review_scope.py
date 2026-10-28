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
        self._trees = {self.head: self.head_tree}
        self._matches = {}
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
        if all(path in self._matches for path in paths):
            return {path: self._matches[path] for path in paths}
        with tempfile.TemporaryDirectory(prefix='review-policy-') as directory:
            sandbox = Path(directory)
            template = sandbox / 'empty-template'
            template.mkdir()
            run_git(sandbox, 'init', '--quiet', '--template=' + str(template),
                    '--initial-branch=review', isolated=True)
            for path, content in self.policies.items():
                target = sandbox / PurePosixPath(path).parent / '.gitignore'
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(content.encode('utf-8'))
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
        self._matches.update(result)
        return result

    def read(self, path, ref, offset=0, limit=12000):
        path = safe_path(path)
        match = self.matching([path])[path]
        if match['excluded']:
            return {**match, 'path': path, 'complete': True, 'nextOffset': None}
        if PurePosixPath(path).suffix.lower() in MEDIA:
            return {'path': path, 'needsExclusionAssessment': True, 'reason': 'media/artifact needs an explicit ignore rule'}
        sha = ref if ref in self._trees else commit(self.repo, ref)
        if sha not in self._trees:
            self._trees[sha] = tree(self.repo, sha)
        entry = self._trees[sha].get(path)
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

    def search(self, ref, pattern, prefix=''):
        if not pattern.strip():
            raise ValueError('Search requires a nonempty pattern')
        pattern = re.compile(pattern)
        prefix = safe_path(prefix).rstrip('/') if prefix else ''
        entries = tree(self.repo, commit(self.repo, ref))
        names = [p for p in entries if not prefix or p == prefix or p.startswith(prefix + '/')]
        matches = self.matching(names)
        names = [p for p in names if not matches[p]['excluded']]
        if len(names) > 200:
            return {'needsNarrowerPrefix': True, 'candidateFiles': len(names), 'fileLimit': 200}
        assessments = [p for p in names if PurePosixPath(p).suffix.lower() in MEDIA or
                       entries[p][0] not in ('100644', '100755') or entries[p][1] != 'blob']
        names = [p for p in names if p not in assessments]
        if not names:
            return {'matches': [], 'needsExclusionAssessment': assessments}
        request = ('\n'.join(entries[p][2] for p in names) + '\n').encode()
        sizes = run_git(self.repo, 'cat-file', '--batch-check=%(objectsize)', input=request)
        if sum(int(n) for n in sizes.splitlines()) > 8_000_000:
            return {'needsNarrowerPrefix': True, 'byteLimit': 8_000_000, 'needsExclusionAssessment': assessments}
        raw = run_git(self.repo, 'cat-file', '--batch', input=request)
        offset, hits = 0, []
        for name in names:
            end = raw.index(b'\n', offset)
            length = int(raw[offset:end].split()[-1])
            content = raw[end + 1:end + 1 + length]
            offset = end + length + 2
            try:
                if b'\0' in content:
                    raise UnicodeError('binary')
                text = content.decode('utf-8-sig')
            except UnicodeError:
                assessments.append(name)
                continue
            for number, line in enumerate(text.splitlines(), 1):
                if pattern.search(line):
                    hits.append({'path': name, 'line': number, 'text': line})
                    if len(hits) >= 500:
                        return {'matches': hits, 'needsNarrowerPrefix': True, 'needsExclusionAssessment': assessments}
        return {'matches': hits, 'needsExclusionAssessment': assessments}

    def manifest(self, base, previous=None, prefixes=None):
        base = commit(self.repo, base)
        prefixes = [safe_path(prefix).rstrip('/') for prefix in prefixes or []]
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
            if prefixes and not any(p == prefix or p.startswith(prefix + '/')
                                    for p in (old, new) for prefix in prefixes) and not any(
                                        PurePosixPath(p).name == '.pragentignore' for p in (old, new)):
                continue
            changes.append({'old': old, 'path': new, 'additions': additions.decode(),
                            'deletions': deletions.decode()})
        matches = self.matching(p for row in changes for p in (row['old'], row['path']))
        original_policy = Scope(self.repo, base)
        newly_excluded = []
        if original_policy.digest != self.digest:
            inventory = set(self.head_tree) | {row['old'] for row in changes}
            current_matches = self.matching(inventory)
            original_matches = original_policy.matching(inventory)
            newly_excluded = [{'path': path, **current_matches[path]} for path in sorted(inventory)
                              if current_matches[path]['excluded'] and not original_matches[path]['excluded']]
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
            # Git can call non-UTF8 bytes text; never decode its diff with replacement.
            if any(self.read(p, ref, limit=1).get('needsExclusionAssessment')
                   for p in visible for ref in (start, self.head)):
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
                'batchPrefixes': prefixes,
                'newExclusionsRequiringJustification': newly_excluded,
                'selected': selected, 'excluded': excluded,
                'needsExclusionAssessment': sorted(set(assessments))}


def size_band(kind, files, lines):
    if not files:
        return 'none'
    for label, line_limit, file_limit in POLICY['bands'][kind]:
        if lines <= line_limit and files <= file_limit:
            return label
    return 'very large' if kind == 'code' else 'large'


def category_profile(category, totals):
    profile = next(r for r in POLICY['routes'] if r['category'] == category).copy()
    for variant in profile.get('variants', []):
        if ('codeBands' in variant and totals['code']['band'] not in variant['codeBands'] or
                'documentationBands' in variant and totals['documentation']['band'] not in variant['documentationBands']):
            continue
        profile.update(variant)
        break
    return profile


def route_for(manifest, categories, cross_boundary, areas=None):
    valid = {r['category'] for r in POLICY['routes']}
    rules = []
    categories = list(dict.fromkeys(categories))
    for area in areas or []:
        category, separator, prefix = area.partition('=')
        if not separator or category not in valid:
            raise ValueError('Expected --area <category>=<repository-relative-path-prefix>')
        rules.append((category, safe_path(prefix).rstrip('/')))
        if category not in categories:
            categories.append(category)
    if set(categories) - valid:
        raise ValueError('Unknown review category')
    if not categories:
        if manifest['totals']['code']['files'] or any(
                PurePosixPath(row['path']).suffix.lower() in ('.json', '.jsonc', '.json5')
                for row in manifest.get('selected', [])):
            raise ValueError('Classify code/configuration behaviour with explicit --category; JSON size alone is not a documentation route')
        categories = ['documentation']
    categories = [r['category'] for r in POLICY['routes'] if r['category'] in categories]
    primary = categories[0]
    totals = {kind: {**values, 'band': size_band(kind, values['files'], values.get('lines', 0))}
              for kind, values in manifest['totals'].items()}
    totals.setdefault('documentation', {'files': 0, 'lines': 0, 'band': 'none'})
    groups = {}
    for row in manifest.get('selected', []):
        path = row.get('visiblePaths', [row['path']])[-1]
        matches = [(len(prefix), category) for category, prefix in rules
                   if path == prefix or path.startswith(prefix + '/')]
        nearest = {category for length, category in matches if length == max(n for n, _ in matches)}
        if len(nearest) > 1:
            raise ValueError('Conflicting review areas for ' + path)
        category = next(iter(nearest)) if nearest else primary
        group = groups.setdefault(category, {'category': category, 'paths': [], 'totals': {
            kind: {'files': 0, 'lines': 0} for kind in ('code', 'documentation')}})
        group['paths'].append(path)
        values = group['totals'][row['kind']]
        values['files'] += 1
        values['lines'] += row['additions'] + row['deletions']
    mixing = POLICY['mixing']
    for group in groups.values():
        for kind, values in group['totals'].items():
            values['band'] = size_band(kind, **values)
        code, docs = group['totals']['code'], group['totals']['documentation']
        group['score'] = (code['lines'] + mixing['documentationWeight'] * docs['lines'] +
                          mixing['fileWeight'] * (code['files'] + docs['files']))
    total_score = sum(group['score'] for group in groups.values())
    for group in groups.values():
        group['share'] = group['score'] / total_score if total_score else 0
        group['substantial'] = (group['share'] >= mixing['minimumShare'] and (
            sum(v['files'] for v in group['totals'].values()) >= mixing['minimumFiles'] or
            any(v['lines'] >= mixing['minimumLines'][kind] for kind, v in group['totals'].items())))
    substantive = sorted((g for g in groups.values() if g['substantial']),
                         key=lambda g: (-g['score'], categories.index(g['category'])))
    protected = bool(set(categories) & set(mixing['protectedCategories']))
    mixed = not protected and len(substantive) >= 2
    selected = [g['category'] for g in substantive[:2]] if mixed else [primary]
    profiles = {category: category_profile(category, groups[category]['totals'] if category in groups else totals)
                for category in categories}
    if not mixed:
        profiles[primary] = category_profile(primary, totals)
        reviewers = profiles[primary]['reviewers']
        assignments = [{'category': primary, 'model': model, 'effort': effort, 'coverage': 'full'}
                       for model, effort in reviewers]
    else:
        assignments = []
        for category in selected:
            profile = profiles[category]
            candidates = sorted(profile['reviewers'], key=lambda pair: pair[0] != profile['lead'])
            model, effort = next(pair for pair in candidates if pair[0] not in {a['model'] for a in assignments})
            assignments.append({'category': category, 'model': model, 'effort': effort, 'coverage': 'full'})
        reviewers = [[a['model'], a['effort']] for a in assignments]
    assigned = {model for model, _ in reviewers}
    escalations = {category: [pair for pair in profile['escalation'] if pair[0] not in assigned]
                   for category, profile in profiles.items()}
    band = totals['code']['band']
    return {'decisionDate': POLICY['decisionDate'], 'category': primary, 'checklists': categories,
            'mixed': mixed, 'selectedCategories': selected, 'areas': list(groups.values()),
            'reviewers': reviewers, 'reviewerAssignments': assignments,
            'escalation': escalations[primary][0] if escalations[primary] else None,
            'escalationByCategory': escalations,
            'integration': POLICY['integration']['model'] if cross_boundary and band in POLICY['integration']['codeBands'] else None,
            'integrationMode': POLICY['integration']['mode'],
            'roundCap': POLICY['roundCaps']['securityOrState' if set(POLICY['mixing']['protectedCategories']) & set(categories) else 'normal']}


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
    manifest.add_argument('--area', action='append', default=[], help='Category=path-prefix; repeat for substantive mixed areas')
    manifest.add_argument('--cross-boundary-contract', action='store_true')
    manifest.add_argument('--path-prefix', action='append', default=[], help='Coherent batch; repeat for multiple areas')
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
        result = scope.manifest(args.base, args.previous, args.path_prefix)
        for kind, values in result['totals'].items():
            values['band'] = size_band(kind, **values)
        # Classify the full task, even when serving one batch or an incremental fix.
        # A small fix must not erase the original mixed/risk responsibilities.
        routing_scope = result if result['from'] == result['base'] and not args.path_prefix else scope.manifest(args.base)
        result['route'] = route_for(routing_scope, args.category, args.cross_boundary_contract, args.area)
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
        fresh = scope.manifest(saved['base'], saved['from'] if saved['from'] != saved['base'] else None,
                               saved.get('batchPrefixes'))
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
        text = json.dumps(scope.search(args.ref, args.pattern, args.path_prefix))
        end = min(len(text), args.offset + args.limit)
        print(json.dumps({'content': text[args.offset:end], 'complete': end == len(text),
                          'nextOffset': end if end < len(text) else None}))


if __name__ == '__main__':
    main()
