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
        self.brief = self.state / 'brief.txt'
        self.brief.write_text('G01: retain and verify the source guard.\n')
        self.run = {'id': 'one', 'marker': 'Review-Run-ID: unique', 'round': 2,
                    'model': 'opencode-go/claude-haiku-5-5', 'effort': 'high',
                    'title': 'R2: Haiku', 'scope': str(self.scope), 'base': 'base', 'from': 'first', 'head': 'head',
                    'briefFile': str(self.brief), 'obligations': [{'id': 'G01', 'description': 'Verify source guard'}],
                    'providerTimeoutMs': 120000, 'providerTimeoutReason': 'Local provider operation calibration'}

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
        self.assertIn('opencode-go/qwen3.8-max', second['models'])
        self.assertNotIn('openrouter/anthropic/claude-sonnet-5.5', second['models'])
        self.assertIn('G01', second['runs'][0]['reviewContract'])
        self.assertTrue(loader.is_relative_to(self.repo))
        loader.unlink()  # Lost loader must not lose ownership of its exclusion rule.
        self.brief.write_text('G01: updated durable contract.\n')
        self.invoke('prepare')
        third = json.loads((self.state / 'runtime.json').read_text())
        self.assertNotEqual(second['runtimeDigest'], third['runtimeDigest'])
        self.invoke('remove')
        self.assertFalse(loader.exists())
        self.assertEqual('# user policy\n*.local\n', exclude.read_text())

    def test_bad_marker_active_child_and_missing_receipt_fail_explicitly(self):
        self.save([{**self.run, 'marker': 'bare-id'}])
        self.assertIn('complete Review-Run-ID', self.invoke('prepare', False).stderr)
        self.save([{**self.run, 'taskId': 'active-task', 'status': 'running'}])
        self.assertIn('terminal owned tasks', self.invoke('prepare', False).stderr)
        self.assertIn('ownership receipt', self.invoke('remove', False).stderr)

    def test_execution_permissions_are_frozen_and_force_a_runtime_reload(self):
        self.save([self.run])
        self.invoke('prepare')
        first = json.loads((self.state / 'runtime.json').read_text())
        self.save([{**self.run, 'executionTools': ['shell', 'browser']}])
        self.assertIn('fixed named checks', self.invoke('prepare', False).stderr)
        self.save([{**self.run, 'checks': [{'id': 'verify', 'executable': sys.executable,
                   'args': ['-c', 'print(42)'], 'cwd': str(self.repo), 'timeoutMs': 5000,
                   'timeoutReason': 'Local trivial command'}]}])
        self.invoke('prepare')
        second = json.loads((self.state / 'runtime.json').read_text())
        self.assertNotEqual(first['runtimeDigest'], second['runtimeDigest'])
        self.assertEqual('verify', second['runs'][0]['checks'][0]['id'])
        for invalid in ('shell', ['shell', 'shell'], [''], ['pingu_review_source']):
            self.save([{**self.run, 'executionTools': invalid}])
            self.assertIn('executionTools', self.invoke('prepare', False).stderr)

    def test_wrong_provider_and_excluded_models_cannot_be_registered(self):
        for model in ('openrouter/z-ai/glm-5.3-flash', 'openrouter/anthropic/claude-haiku-5.5',
                      'opencode-go/glm-5.2', 'opencode-go/gemini-4-argon'):
            self.save([{**self.run, 'model': model}])
            self.assertIn('accepted review policy', self.invoke('prepare', False).stderr)

    def test_completed_historical_run_does_not_block_a_go_recheck(self):
        historical = {**self.run, 'model': 'openrouter/z-ai/glm-5.3-flash',
                      'status': 'completed', 'taskId': 'old-task'}
        recheck = {**self.run, 'id': 'go-recheck', 'marker': 'Review-Run-ID: go-recheck',
                   'model': 'opencode-go/glm-5.3-flash'}
        self.save([historical, recheck])
        self.invoke('prepare')
        config = json.loads((self.state / 'runtime.json').read_text())
        self.assertEqual(['go-recheck'], [r['id'] for r in config['runs']])
        self.assertNotIn(historical['model'], config['models'])
        self.assertEqual([historical, recheck], json.loads(self.ledger.read_text())['runs'])


if __name__ == '__main__':
    unittest.main()
