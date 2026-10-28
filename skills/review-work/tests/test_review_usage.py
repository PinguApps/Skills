import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('review_usage', Path(__file__).parents[1] / 'scripts/review_usage.py')
usage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(usage)


class UsageTests(unittest.TestCase):
    def message(self, identifier, cost=.005):
        return {'type': 'assistant', 'id': identifier,
                'time': {'completed': 2},
                'model': {'providerID': 'openrouter', 'id': 'anthropic/claude-haiku-5.5', 'variant': 'high'},
                'cost': cost, 'tokens': {'input': 100, 'output': 50, 'reasoning': 20,
                                        'cache': {'read': 80, 'write': 10}}}

    def test_counts_all_steps_once_without_double_counting_reasoning(self):
        first = self.message('one')
        result = usage.reported_usage([first, first, self.message('two')], 'openrouter/anthropic/claude-haiku-5.5')
        self.assertEqual(380, result['input'])
        self.assertEqual(140, result['output'])
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
        self.assertEqual('marker', usage.user_text({'type': 'user', 'text': 'marker'}))

    def test_live_v2_correlation_and_pagination_are_not_guessed(self):
        root = str(Path.cwd())
        session = {'id': 'exact', 'location': {'directory': root}}
        user = {'type': 'user', 'text': 'Wrapper\r\nReview-Run-ID: unique\r\nTask', 'time': {'created': 1}}
        responses = [
            {'data': [session], 'cursor': {'next': 'page2'}},
            {'data': [user], 'cursor': {}},
            {'data': [], 'cursor': {}},
        ]
        with patch.object(usage, 'api', side_effect=responses):
            match, messages = usage.correlate('/absolute/opencode', {'marker': 'Review-Run-ID: unique'}, root)
        self.assertEqual('exact', match['id'])
        self.assertEqual([user], messages)
        with patch.object(usage, 'api', return_value={'data': [], 'hasMore': True}):
            with self.assertRaisesRegex(ValueError, 'pagination'):
                list(usage.pages('/absolute/opencode', 'list'))

    def test_billed_usage_uses_response_cost_and_counts_reasoning_once(self):
        run = {'model': 'openrouter/anthropic/claude-haiku-5.5', 'effort': 'high'}
        common = {'requestID': 'call', 'sessionID': 'session', **run}
        records = [
            {'event': 'guard', 'tools': ['pingu_review_source']},
            {**common, 'event': 'request', 'kind': 'primary'},
            {**common, 'event': 'response', 'status': 200},
            {**common, 'event': 'usage', 'generationID': 'gen-exact', 'usage': {
                'cost': .12345, 'prompt_tokens': 100, 'completion_tokens': 40,
                'completion_tokens_details': {'reasoning_tokens': 25},
                'prompt_tokens_details': {'cached_tokens': 60, 'cache_write_tokens': 10}}},
            {**common, 'event': 'end', 'complete': True},
        ]
        result = usage.billed_usage(records, run, 'session')
        self.assertEqual(40, result['output'])
        self.assertEqual(25, result['reasoning'])
        self.assertEqual('0.12345', result['costUSD'])
        self.assertEqual(['gen-exact'], result['generationIDs'])
        self.assertTrue(result['billed'])
        self.assertEqual(result, usage.billed_usage(records[:-1], run, 'session'), 'Final provider usage is authoritative without stream EOF')
        with self.assertRaises(usage.IncompleteUsage):
            usage.billed_usage(records[:-2], run, 'session')

    def test_partial_or_response_less_capture_uses_only_labelled_estimate(self):
        run = {'model': 'openrouter/anthropic/claude-haiku-5.5', 'effort': 'high'}
        estimate = usage.reported_usage([self.message('one')], run['model'], run['effort'])
        records = [{'event': 'bound', 'sessionID': 'session'},
                   {'event': 'guard', 'sessionID': 'session', 'tools': ['pingu_review_source']}]
        usage.collect_usage(run, records, 'session', estimate, True)
        self.assertFalse(run['usage']['billed'])
        self.assertTrue(run['accountingIncomplete'])
        self.assertIn('no-transport-requests', run['partialBilledUsage']['missingUsageMessageIDs'])
        with self.assertRaises(usage.IncompleteUsage):
            usage.collect_usage(run, records, 'session', estimate, False)
        self.assertIsNone(run['usage'])
        records.append({'event': 'blocked-tool', 'tool': 'read'})
        with self.assertRaisesRegex(ValueError, 'guard breach'):
            usage.collect_usage(run, records, 'session', estimate, True)
        with self.assertRaisesRegex(ValueError, 'different review session'):
            usage.collect_usage(run, [{'event': 'bound', 'sessionID': 'foreign'}], 'session', estimate, True)

    def test_route_assignment_and_fresh_marker_are_enforced(self):
        ledger = {'runs': [], 'route': {'reviewers': [['haiku', 'high']], 'escalationByCategory': {'general': [['sonnet', 'high']]}}}
        run = {'id': 'one', 'marker': 'Review-Run-ID: unique', 'model': 'openrouter/anthropic/claude-haiku-5.5', 'effort': 'high'}
        usage.validate_assignment(ledger, run)
        with self.assertRaisesRegex(ValueError, 'complete Review-Run-ID'):
            usage.validate_assignment(ledger, {**run, 'marker': 'unique'})
        with self.assertRaisesRegex(ValueError, 'outside the recorded route'):
            usage.validate_assignment(ledger, {**run, 'effort': 'medium'})
        ledger['runs'].append(run)
        with self.assertRaisesRegex(ValueError, 'fresh marker'):
            usage.validate_assignment(ledger, {**run, 'id': 'two'})
        ledger['benchmarkAuthorization'] = {'reason': 'User requested a medium comparison', 'assignments': [['haiku', 'medium']]}
        usage.validate_assignment(ledger, {**run, 'effort': 'medium'})

    def test_billed_and_estimated_subtotals_never_become_a_mixed_total(self):
        estimate = usage.reported_usage([self.message('one')], 'openrouter/anthropic/claude-haiku-5.5')
        common = {'round': 2, 'roundLabel': '2A', 'model': 'Haiku', 'effort': 'high', 'from': 'previous', 'head': 'head'}
        text = usage.render({'mergePolicy': 'manual', 'runs': [
            {**common, 'usage': estimate}, {**common, 'usage': {**estimate, 'billed': True, 'costUSD': '.12'}}]})
        self.assertIn('Round 2A', text)
        self.assertIn('Recorded billed subtotal: $0.12', text)
        self.assertIn('Recorded estimate subtotal (not billed): $0.01', text)
        self.assertNotIn('$0.13', text)
        self.assertNotIn('Total billed review cost', text)

    def test_top_level_model_metadata_is_not_silently_skipped(self):
        message = self.message('top')
        model = message.pop('model')
        message.update(providerID=model['providerID'], modelID=model['id'], variant=model['variant'])
        result = usage.reported_usage([message], 'openrouter/anthropic/claude-haiku-5.5', 'high')
        self.assertEqual('0.005', result['costUSD'])

    def test_estimate_only_and_missing_rounds_do_not_imply_zero_billed_spend(self):
        estimate = usage.reported_usage([self.message('one')], 'openrouter/anthropic/claude-haiku-5.5')
        common = {'round': 2, 'model': 'Haiku', 'effort': 'high', 'from': 'before', 'head': 'after'}
        for evidence in (estimate, None):
            text = usage.render({'mergePolicy': 'manual', 'runs': [{**common, 'usage': evidence}]})
            self.assertIn('Round billed subtotal: unavailable', text)
            self.assertIn('Recorded billed subtotal: unavailable', text)
            self.assertNotIn('billed subtotal: $0.00', text)
        zero = {**estimate, 'billed': True, 'costUSD': '0'}
        text = usage.render({'mergePolicy': 'manual', 'runs': [{**common, 'usage': zero}]})
        self.assertIn('Total billed review cost: $0.00', text, 'Verified zero usage is distinct from missing usage')

    def test_round_report_shows_outcome_time_scope_and_short_comparison_links(self):
        first, second, third = 'a' * 40, 'b' * 40, 'c' * 40
        common = {'model': 'openrouter/anthropic/claude-haiku-5.5', 'effort': 'high', 'base': first}
        text = usage.render({'mergePolicy': 'manual', 'repositoryUrl': 'https://github.com/example/repo', 'runs': [
            {**common, 'round': 1, 'from': first, 'head': second, 'verdict': 'CHANGES',
             'timing': {'seconds': 65}},
            {**common, 'round': 2, 'from': second, 'head': third, 'verdict': 'APPROVE'}]})
        self.assertIn('| claude-haiku-5.5 | high | CHANGES | 1m 5s |', text)
        self.assertIn('| claude-haiku-5.5 | high | APPROVE | unavailable |', text)
        self.assertIn('| Full review | [aaaaaaa..bbbbbbb](https://github.com/example/repo/compare/aaaaaaa..bbbbbbb)', text)
        self.assertIn('| Incremental review | [bbbbbbb..ccccccc]', text)
        self.assertNotIn('openrouter/anthropic/', text)
        self.assertNotIn(first, text)
        # Headings remain visible while each round's tables/subtotals are closed.
        inside = False
        for line in text.splitlines():
            if line == '<details>':
                self.assertFalse(inside)
                inside = True
            elif line == '</details>':
                inside = False
            elif line.startswith(('## ', '### ', 'Merge policy:')):
                self.assertFalse(inside, line)
            elif line.startswith('| Model | Effort'):
                self.assertTrue(inside)
        self.assertFalse(inside)
        self.assertEqual(2, text.count('<summary>Review details</summary>'))
        self.assertNotIn('<details open', text)

    def test_totals_group_models_across_rounds_and_sum_unrounded_billed_costs(self):
        common = {'effort': 'high', 'base': 'a' * 40, 'from': 'a' * 40, 'head': 'b' * 40}
        def run(round_number, model, cost):
            return {**common, 'round': round_number, 'model': model,
                    'usage': {'input': 100, 'cacheRead': 60, 'cacheWrite': 10, 'output': 20,
                              'costUSD': cost, 'billed': True, 'source': 'provider'}}
        text = usage.render({'mergePolicy': 'manual', 'runs': [
            run(1, 'openrouter/anthropic/claude-haiku-5.5', '.124'),
            run(1, 'openrouter/z-ai/glm-5.3-flash', '.06'),
            run(2, 'openrouter/anthropic/claude-haiku-5.5', '.126')]})
        self.assertIn('### Totals', text)
        totals = text.split('### Totals', 1)[1]
        self.assertIn('| claude-haiku-5.5 | 200 | 120 | 20 | 40 | $0.25 |', totals)
        self.assertIn('| glm-5.3-flash | 100 | 60 | 10 | 20 | $0.06 |', totals)
        self.assertIn('| **Total** | 300 | 180 | 30 | 60 | $0.31 |', totals)
        self.assertNotIn('Estimate USD', totals)

    def test_totals_preserve_partial_counts_and_separate_estimates(self):
        common = {'model': 'openrouter/anthropic/claude-haiku-5.5', 'effort': 'high',
                  'round': 1, 'from': 'before', 'head': 'after'}
        record = {'input': 100, 'cacheRead': 60, 'cacheWrite': 10, 'output': 20, 'source': 'provider'}
        text = usage.render({'mergePolicy': 'manual', 'runs': [
            {**common, 'usage': {**record, 'costUSD': '.12', 'billed': True}},
            {**common, 'usage': {**record, 'costUSD': '.02', 'billed': False}},
            {**common, 'usage': None}]})
        totals = text.split('### Totals', 1)[1]
        self.assertIn('Estimate USD (not billed)', totals)
        self.assertIn('| **Total** | 200 (partial) | 120 (partial) | 20 (partial) | 40 (partial) | $0.12 | $0.02 |', totals)
        self.assertNotIn('$0.14', totals)

    def test_timing_is_measured_not_inferred_from_tokens_or_missing_clocks(self):
        self.assertEqual(5.5, usage.session_timing({'time': {'created': 1000, 'idle': 6500}})['seconds'])
        for times in ({}, {'idle': 5000}, {'created': 5000, 'idle': 1000}, {'created': True, 'idle': 5000}):
            self.assertIsNone(usage.session_timing({'time': times}))
        self.assertEqual('unavailable', usage.duration({}))
        self.assertEqual('0s', usage.duration({'timing': {'seconds': 0}}))


if __name__ == '__main__':
    unittest.main()
