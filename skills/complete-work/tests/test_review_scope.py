import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('review_scope', Path(__file__).parents[1] / 'scripts/review_scope.py')
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)


class ReviewScopeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        review.run_git(self.repo, 'init', '--quiet', '--initial-branch=main', isolated=True)
        self.write('initial.txt', 'initial\n')
        self.base = self.save()

    def write(self, name, content):
        target = self.repo / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content if isinstance(content, bytes) else content.encode())

    def save(self):
        review.run_git(self.repo, '-c', 'core.autocrlf=false', 'add', '--all', '--force')
        review.run_git(self.repo, '-c', 'user.name=Review test', '-c',
                       'user.email=review@example.test', '-c', 'commit.gpgsign=false',
                       'commit', '--quiet', '-m', 'fixture')
        return review.commit(self.repo, 'HEAD')

    def test_nested_gitignore_semantics_and_policy_visibility(self):
        self.write('.pragentignore', '*.pen\n/blocked/\n/open/*\n!/open/manual.cs\n')
        self.write('design/.pragentignore', '!manual.pen\n')
        self.write('blocked/.pragentignore', '!manual.cs\n')
        head = self.save()
        scope = review.Scope(self.repo, head)
        matches = scope.matching(['a.pen', 'A.PEN', 'design/manual.pen', 'design/other.pen',
                                  'blocked/manual.cs', 'blocked/.pragentignore',
                                  'open/generated.cs', 'open/manual.cs'])
        self.assertTrue(matches['a.pen']['excluded'])
        self.assertFalse(matches['A.PEN']['excluded'])
        self.assertFalse(matches['design/manual.pen']['excluded'])
        self.assertTrue(matches['design/other.pen']['excluded'])
        self.assertTrue(matches['blocked/manual.cs']['excluded'])
        self.assertFalse(matches['blocked/.pragentignore']['excluded'])
        self.assertFalse(matches['open/manual.cs']['excluded'])
        self.assertEqual('.pragentignore', matches['a.pen']['policy'])
        self.assertEqual(1, matches['a.pen']['line'])

    def test_gitignore_is_independent_and_head_rules_block_historical_reads(self):
        self.write('secret.json', '{"doNotReturn":"historical content"}')
        old = self.save()
        self.write('.gitignore', 'visible.cs\n')
        self.write('.pragentignore', '/secret.json\n')
        self.write('visible.cs', 'review me\n')
        scope = review.Scope(self.repo, self.save())
        result = scope.read('secret.json', old)
        self.assertTrue(result['excluded'])
        self.assertNotIn('content', result)
        self.assertTrue(result['complete'])
        self.assertFalse(scope.matching(['visible.cs'])['visible.cs']['excluded'])

    def test_crlf_policy_bytes_and_batch_boundaries(self):
        self.write('.pragentignore', b'/secret.json\r\n*.pen\r\n')
        self.write('secret.json', 'DO_NOT_LEAK\n')
        self.write('area/a.cs', 'code\n')
        self.write('area-other/a.cs', 'other\n')
        scope = review.Scope(self.repo, self.save())
        self.assertIn('\r\n', scope.policies['.pragentignore'])
        self.assertTrue(scope.read('secret.json', scope.head)['excluded'])
        batch = scope.manifest(self.base, prefixes=['area'])
        self.assertEqual({'.pragentignore', 'area/a.cs'}, {row['path'] for row in batch['selected']})

    def test_json_requires_behaviour_classification_and_non_utf8_is_assessed(self):
        self.write('appsettings.json', '{}\n')
        self.write('legacy.txt', b'not utf8 \xff\n')
        manifest = review.Scope(self.repo, self.save()).manifest(self.base)
        self.assertEqual(['legacy.txt'], manifest['needsExclusionAssessment'])
        manifest['totals']['code']['band'] = 'none'
        with self.assertRaisesRegex(ValueError, 'Classify'):
            review.route_for(manifest, [], False)

    def test_incremental_range_and_policy_change_reset(self):
        self.write('.pragentignore', 'hidden.json\n')
        self.write('hidden.json', '{}\n')
        self.write('first.cs', 'first\n')
        first = self.save()
        self.write('second.md', 'second\n')
        second = self.save()
        delta = review.Scope(self.repo, second).manifest(self.base, first)
        self.assertEqual(first, delta['from'])
        self.assertEqual(['second.md'], [x['path'] for x in delta['selected']])
        self.write('.pragentignore', '# include JSON again\n')
        current = review.Scope(self.repo, self.save()).manifest(self.base, second)
        self.assertTrue(current['policyReset'])
        self.assertEqual(self.base, current['from'])
        self.assertIn('hidden.json', [x['path'] for x in current['selected']])

    def test_rename_into_exclusion_keeps_only_original_deletion(self):
        self.write('source.cs', 'reviewable\nsecond\n')
        old = self.save()
        self.write('.pragentignore', 'generated/\n')
        (self.repo / 'generated').mkdir()
        (self.repo / 'source.cs').rename(self.repo / 'generated/source.cs')
        result = review.Scope(self.repo, self.save()).manifest(old)
        row = next(x for x in result['selected'] if x['old'] == 'source.cs')
        self.assertEqual(['source.cs'], row['visiblePaths'])
        self.assertEqual(2, row['deletions'])
        self.assertEqual(0, row['additions'])

    def test_media_requires_explicit_policy_and_documentation_is_separate(self):
        self.write('design.pen', 'serialized design\n' * 20)
        self.write('plan.md', 'documentation\n' * 100)
        self.write('config.json', '{}\n')
        self.write('app.cs', 'code\n' * 3)
        result = review.Scope(self.repo, self.save()).manifest(self.base)
        self.assertEqual(['design.pen'], result['needsExclusionAssessment'])
        self.assertEqual({'files': 2, 'lines': 101}, result['totals']['documentation'])
        self.write('.pragentignore', '*.pen\n')
        result = review.Scope(self.repo, self.save()).manifest(self.base)
        self.assertEqual([], result['needsExclusionAssessment'])
        self.assertEqual(1, len(result['excluded']))
        self.assertEqual(['design.pen'], [row['path'] for row in result['newExclusionsRequiringJustification']])

    def test_unreadable_policy_fails_closed_and_paths_cannot_escape(self):
        self.write('.pragentignore', b'\xff\xfe')
        with self.assertRaises(UnicodeError):
            review.Scope(self.repo, self.save())
        for path in ('../outside', '/absolute', 'C:/outside', 'nested\\file'):
            with self.assertRaises(ValueError):
                review.safe_path(path)

    def test_independent_size_bands(self):
        self.assertEqual('standard', review.size_band('code', 30, 1500))
        self.assertEqual('small', review.size_band('documentation', 30, 1500))
        self.assertEqual('large', review.size_band('documentation', 500, 60000))
        self.assertEqual('large', review.size_band('code', 90, 4200))
        self.assertEqual('very large', review.size_band('code', 121, 100))

    def test_reader_diff_and_search_do_not_expose_excluded_content(self):
        self.write('.pragentignore', 'private/\n')
        self.write('private/data.json', '{"secret":"DO_NOT_LEAK"}\n')
        self.write('public.cs', 'VISIBLE\n')
        head = self.save()
        scope = review.Scope(self.repo, head)
        manifest = self.repo / 'scope.json'
        manifest.write_text(json.dumps(scope.manifest(self.base)), encoding='utf-8')
        command = [sys.executable, '-B', str(Path(review.__file__)), '--repo', str(self.repo), '--head', head]
        for args in (['diff', '--scope', str(manifest)],
                     ['search', '--ref', head, '--pattern', 'DO_NOT_LEAK|VISIBLE']):
            output = subprocess.check_output(command + args, text=True)
            self.assertNotIn('DO_NOT_LEAK', output)
            self.assertIn('VISIBLE', output)

    def test_category_precedence_and_size_gated_integration(self):
        manifest = {'totals': {'code': {'files': 30, 'band': 'standard'}}}
        route = review.route_for(manifest, ['ui', 'security'], True)
        self.assertEqual('security', route['category'])
        self.assertEqual([['haiku', 'high'], ['mimo', 'thinking']], route['reviewers'])
        self.assertEqual(5, route['roundCap'])
        self.assertIsNone(route['integration'])
        manifest['totals']['code']['band'] = 'large'
        self.assertEqual(['step', 'medium'], review.route_for(manifest, ['compatibility'], True)['integration'])


if __name__ == '__main__':
    unittest.main()
