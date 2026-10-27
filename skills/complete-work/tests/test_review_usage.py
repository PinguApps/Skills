import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('review_usage', Path(__file__).parents[1] / 'scripts/review_usage.py')
usage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(usage)


class UsageTests(unittest.TestCase):
    def message(self, identifier, cost=.005):
        return {'type': 'assistant', 'id': identifier,
                'model': {'providerID': 'openrouter', 'modelID': 'anthropic/claude-haiku-5.5'},
                'cost': cost, 'tokens': {'input': 100, 'output': 50, 'reasoning': 20,
                                        'cache': {'read': 80, 'write': 10}}}

    def test_counts_all_steps_once_without_double_counting_reasoning(self):
        first = self.message('one')
        result = usage.reported_usage([first, first, self.message('two')], 'openrouter/anthropic/claude-haiku-5.5')
        self.assertEqual(200, result['input'])
        self.assertEqual(100, result['output'])
        self.assertEqual(40, result['reasoning'])
        self.assertEqual(160, result['cacheRead'])
        self.assertEqual('0.010', result['costUSD'])
        self.assertEqual('$0.01', usage.money(result['costUSD']))

    def test_missing_usage_and_auxiliary_models_do_not_become_free_reviews(self):
        incomplete = self.message('missing')
        del incomplete['tokens']
        result = usage.reported_usage([incomplete], 'openrouter/anthropic/claude-haiku-5.5')
        self.assertEqual(['missing'], result['missingUsageMessageIDs'])
        extra = self.message('other')
        extra['model'] = {'providerID': 'openai', 'modelID': 'gpt-example'}
        with self.assertRaises(ValueError):
            usage.reported_usage([extra], 'openrouter/anthropic/claude-haiku-5.5')

    def test_rounds_render_separately_and_missing_cost_is_explicit(self):
        record = usage.reported_usage([self.message('one')], 'openrouter/anthropic/claude-haiku-5.5')
        ledger = {'mergePolicy': 'manual', 'runs': [
            {'round': 1, 'model': 'Haiku', 'effort': 'medium', 'from': 'base', 'head': 'first', 'usage': record},
            {'round': 2, 'model': 'Haiku', 'effort': 'medium', 'from': 'first', 'head': 'second'}]}
        text = usage.render(ledger)
        self.assertIn('### Round 1', text)
        self.assertIn('### Round 2', text)
        self.assertIn('Accounting incomplete', text)
        self.assertIn('$0.01', text)
        self.assertNotIn('Post-PR rounds', text)

    def test_only_user_messages_can_correlate_a_run(self):
        self.assertEqual('', usage.user_text({'type': 'assistant', 'content': [{'text': 'marker'}]}))
        self.assertEqual('marker', usage.user_text({'type': 'user', 'content': [{'type': 'text', 'text': 'marker'}]}))


if __name__ == '__main__':
    unittest.main()
