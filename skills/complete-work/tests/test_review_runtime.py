import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

SCRIPTS = Path(__file__).parents[1] / 'scripts'
spec = importlib.util.spec_from_file_location('review_scope', SCRIPTS / 'review_scope.py')
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)


class RuntimePreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='review-runtime-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        review.run_git(self.repo, 'init', '--quiet', '--initial-branch=main', isolated=True)
        self.state = self.root / 'state'
        self.state.mkdir()
        self.scope = self.state / 'scope.json'
        self.scope.write_text(json.dumps({'repo': str(self.repo), 'head': 'head'}))
        self.ledger = self.state / 'ledger.json'
        self.run = {'id': 'one', 'marker': 'Review-Run-ID: unique', 'round': 2,
                    'model': 'openrouter/anthropic/claude-haiku-5.5', 'effort': 'high',
                    'title': 'R2: Haiku', 'scope': str(self.scope), 'base': 'base', 'from': 'first', 'head': 'head'}

    def save(self, runs):
        self.ledger.write_text(json.dumps({'repo': str(self.repo), 'runs': runs}))

    def invoke(self, command, success=True):
        result = subprocess.run([sys.executable, '-B', str(SCRIPTS / 'review_runtime.py'),
                                 '--ledger', str(self.ledger), command], capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stderr)
        return result

    def test_new_run_forces_reload_and_cleanup_preserves_user_exclusions(self):
        exclude = self.repo / '.git/info/exclude'
        exclude.write_text('# user policy\n*.local\n')
        self.save([self.run])
        self.invoke('prepare')
        first = json.loads((self.state / 'runtime.json').read_text())
        receipt = json.loads((self.state / 'runtime-install.json').read_text())
        loader = Path(receipt['loader'])
        first_loader = loader.read_bytes()
        self.assertTrue(review.run_git(self.repo, 'check-ignore', loader.relative_to(self.repo).as_posix()))
        self.save([self.run, {**self.run, 'id': 'two', 'marker': 'Review-Run-ID: next'}])
        self.invoke('prepare')
        second = json.loads((self.state / 'runtime.json').read_text())
        self.assertNotEqual(first['runtimeDigest'], second['runtimeDigest'])
        self.assertNotEqual(first_loader, loader.read_bytes())
        self.assertEqual({'one', 'two'}, {r['id'] for r in second['runs']})
        self.assertIn('openrouter/anthropic/claude-sonnet-5.5', second['models'])
        self.invoke('remove')
        self.assertFalse(loader.exists())
        self.assertEqual('# user policy\n*.local\n', exclude.read_text())

    def test_bad_marker_active_child_and_missing_receipt_fail_explicitly(self):
        self.save([{**self.run, 'marker': 'bare-id'}])
        self.assertIn('complete Review-Run-ID', self.invoke('prepare', False).stderr)
        self.save([{**self.run, 'taskId': 'active-task', 'status': 'running'}])
        self.assertIn('terminal owned tasks', self.invoke('prepare', False).stderr)
        self.assertIn('ownership receipt', self.invoke('remove', False).stderr)


if __name__ == '__main__':
    unittest.main()
