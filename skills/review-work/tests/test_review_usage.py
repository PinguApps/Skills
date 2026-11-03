import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('review_usage', Path(__file__).parents[1] / 'scripts/review_usage.py')
usage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(usage)


class UsageTests(unittest.TestCase):
    def test_model_replacement_requires_terminal_cause_specific_unused_route(self):
        original = {'id': 'stalled', 'marker': 'Review-Run-ID: stalled', 'head': 'head',
                    'round': 1, 'status': 'failed', 'model': usage.POLICY['models']['glm']['id']}
        ledger = {'runs': [original], 'route': {'category': 'agent-policy',
                  'reviewers': [['haiku', 'high'], ['glm', 'high']],
                  'escalationByCategory': {'agent-policy': [['kimi-code', 'default'], ['qwen', 'medium']]}}}
        run = {'id': 'replacement', 'marker': 'Review-Run-ID: replacement', 'head': 'head', 'round': 1,
               'model': usage.POLICY['models']['kimi-code']['id'], 'effort': 'default', 'replacementOf': 'stalled',
               'recovery': {'cause': 'model cycle', 'changedCondition': 'different eligible model',
                            'evidence': 'persisted stalled question', 'reason': 'model-specific repetition', 'category': 'agent-policy'}}
        usage.validate_assignment(ledger, run)
        ledger['runs'].append({'id': 'planned', 'marker': 'Review-Run-ID: planned', 'head': 'head', 'model': run['model']})
        usage.validate_assignment(ledger, run)  # An unsent registration is not a dispatched model.
        ledger['runs'].pop()
        with self.assertRaisesRegex(ValueError, 'cause-specific'):
            usage.validate_assignment(ledger, {**run, 'recovery': {}})
        with self.assertRaisesRegex(ValueError, 'next eligible unused'):
            usage.validate_assignment(ledger, {**run, 'model': usage.POLICY['models']['qwen']['id'], 'effort': 'medium'})
        original['status'] = 'running'
        with self.assertRaisesRegex(ValueError, 'terminal predecessor'):
            usage.validate_assignment(ledger, run)
        original['status'] = 'failed'
        ledger['runs'].append({**run, 'id': 'already-used', 'marker': 'Review-Run-ID: used', 'taskId': 'dispatched'})
        with self.assertRaisesRegex(ValueError, 'next eligible unused'):
            usage.validate_assignment(ledger, run)

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
        execution_run = {**run, 'executionTools': ['shell', 'browser']}
        execution_records = [{**records[0], 'tools': ['browser', 'pingu_review_source', 'shell']}, *records[1:]]
        self.assertEqual(result, usage.billed_usage(execution_records, execution_run, 'session'))
        with self.assertRaisesRegex(ValueError, 'filtered-tool guard'):
            usage.billed_usage(execution_records, run, 'session')
        with self.assertRaisesRegex(ValueError, 'filtered-tool guard'):
            usage.billed_usage(records, execution_run, 'session')
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

    def test_go_cash_list_price_and_allowance_are_separate_for_both_protocols(self):
        run = {'model': 'opencode-go/glm-5.3-flash', 'effort': 'high'}
        common = {'requestID': 'call', 'sessionID': 'session', **run}
        value = {'cost': 0, 'opencode': {'billing_source': 'go', 'list_cost': .02, 'allowance': .02,
            'tokens': {'input': 100, 'cache_read': 600, 'cache_write_5m': 10, 'cache_write_1h': 20,
                       'output': 40, 'reasoning': 25}}}
        records = [{'event': 'guard', 'tools': ['pingu_review_source']},
                   {**common, 'event': 'request', 'kind': 'primary'},
                   {**common, 'event': 'response', 'status': 200},
                   {**common, 'event': 'usage', 'generationID': 'go-id', 'usage': value}]
        # Go's own token receipt has the same semantics for chat and Anthropic.
        for native in ({'prompt_tokens': 730, 'completion_tokens': 40}, {'input_tokens': 100, 'output_tokens': 40}):
            result = usage.billed_usage([*records[:-1], {**records[-1], 'usage': {**native, **value}}], run, 'session')
            self.assertEqual((730, 40, 25, 600, 30), tuple(result[k] for k in ('input', 'output', 'reasoning', 'cacheRead', 'cacheWrite')))
            self.assertTrue(result['billed'])
            self.assertEqual('0', result['costUSD'])
            self.assertEqual({'listCostUSD': '0.02', 'allowanceUSD': '0.02', 'billingSources': ['go']}, result['goUsage'])
        for key in ('tokens', 'list_cost', 'allowance'):
            broken = {**value, 'opencode': {k: v for k, v in value['opencode'].items() if k != key}}
            with self.assertRaises(usage.IncompleteUsage):
                usage.billed_usage([*records[:-1], {**records[-1], 'usage': broken}], run, 'session')
        for patch in ({'billing_source': 'byok'}, {'estimated': True}, {'allowance': -1}):
            broken = {**value, 'opencode': {**value['opencode'], **patch}}
            with self.assertRaises(ValueError):
                usage.billed_usage([*records[:-1], {**records[-1], 'usage': broken}], run, 'session')
        extra = {**value, 'cost': .02, 'opencode': {**value['opencode'], 'billing_source': 'balance'}}
        result = usage.billed_usage([*records[:-1], {**records[-1], 'usage': extra}], run, 'session')
        self.assertEqual('0.02', result['costUSD'])
        self.assertEqual('0', result['goUsage']['allowanceUSD'])

    def test_go_report_combines_allocated_cost_and_exposes_raw_subscription_usage(self):
        common = {'round': 1, 'effort': 'high', 'base': 'a' * 40, 'from': 'a' * 40, 'head': 'b' * 40}
        counts = {'input': 100, 'cacheRead': 60, 'cacheWrite': 0, 'output': 20, 'billed': True, 'source': 'provider'}
        text = usage.render({'mergePolicy': 'manual', 'goCostAllocation': usage.POLICY['goCostAllocation'], 'runs': [
            {**common, 'model': 'openrouter/anthropic/claude-haiku-5.5', 'usage': {**counts, 'costUSD': '.03'}},
            {**common, 'model': 'opencode-go/glm-5.3-flash', 'usage': {**counts, 'costUSD': '0',
                'goUsage': {'listCostUSD': '.02', 'allowanceUSD': '.08', 'billingSources': ['go']}}}]})
        self.assertIn('| glm-5.3-flash | 100 | 60 | 0 | 20 | $0.013333 |', text)
        self.assertIn('| **Total** | 200 | 120 | 0 | 40 | $0.043333 |', text)
        self.assertIn('| glm-5.3-flash | $0.020000 | $0.080000 |', text)
        self.assertIn('Total review cost: $0.043333', text)
        self.assertNotIn('Total billed review cost: $0.05', text)
        self.assertNotIn('Accounting incomplete', text)

    def test_go_cost_uses_its_monthly_share_in_the_main_cost_column(self):
        basis = {'monthlyFeeUSD': '10', 'monthlyAllowanceUSD': '60', 'billingSource': 'go'}
        common = {'round': 1, 'effort': 'high', 'base': 'a' * 40, 'from': 'a' * 40, 'head': 'b' * 40}
        counts = {'input': 100, 'cacheRead': 60, 'cacheWrite': 0, 'output': 20,
                  'billed': True, 'source': 'provider'}
        go = {**common, 'model': 'opencode-go/glm-5.3-flash', 'usage': {**counts, 'costUSD': '0',
              'goUsage': {'listCostUSD': '.15', 'allowanceUSD': '.6', 'billingSources': ['go']}}}
        haiku = {**common, 'model': 'openrouter/anthropic/claude-haiku-5.5',
                 'usage': {**counts, 'costUSD': '.03'}}
        text = usage.render({'mergePolicy': 'manual', 'goCostAllocation': basis, 'runs': [haiku, go]})
        self.assertIn('| glm-5.3-flash | 100 | 60 | 0 | 20 | $0.100000 |', text)
        self.assertIn('| **Total** | 200 | 120 | 0 | 40 | $0.130000 |', text)
        self.assertIn('Total review cost: $0.130000', text)
        self.assertNotIn('Cost USD (billed)', text)
        self.assertEqual('0', go['usage']['costUSD'], 'Rendering must preserve the original cash receipt')
        mostly_used = {**go, 'usage': {**go['usage'], 'goUsage': {
            **go['usage']['goUsage'], 'allowanceUSD': '54'}}}
        text = usage.render({'mergePolicy': 'manual', 'goCostAllocation': basis, 'runs': [mostly_used]})
        self.assertIn('Total review cost: $9.000000', text, 'Unused allowance stays unallocated')
        text = usage.render({'mergePolicy': 'manual', 'runs': [go]})
        self.assertIn('Accounting incomplete', text)
        self.assertNotIn('Total review cost: $0.000000', text, 'A missing allocation basis is not zero cost')
        self.assertIn('| glm-5.3-flash | 100 (partial) | 60 (partial) | 0 (partial) | 20 (partial) | unavailable |', text)
        extra = {**go, 'usage': {**go['usage'], 'costUSD': '.02', 'goUsage': {
            **go['usage']['goUsage'], 'allowanceUSD': '0', 'billingSources': ['balance']}}}
        text = usage.render({'mergePolicy': 'manual', 'goCostAllocation': basis, 'runs': [extra]})
        self.assertIn('Total review cost: $0.020000', text, 'Balance usage is charged once, without subscription allocation')
        unsupported = {**go, 'usage': {**go['usage'], 'goUsage': {
            **go['usage']['goUsage'], 'billingSources': ['go-plus']}}}
        text = usage.render({'mergePolicy': 'manual', 'goCostAllocation': basis, 'runs': [unsupported]})
        self.assertIn('Accounting incomplete', text, 'Go Plus must not use the Go allocation basis')
        with self.assertRaisesRegex(ValueError, 'allowance must be positive'):
            usage.render({'mergePolicy': 'manual', 'goCostAllocation': {**basis, 'monthlyAllowanceUSD': '0'}, 'runs': [go]})

    def test_allocation_basis_is_snapshotted_and_explicitly_migrated(self):
        with tempfile.TemporaryDirectory(prefix='review-cost-basis-') as directory:
            root = Path(directory)
            ledger, scope, output = root/'ledger.json', root/'scope.json', root/'report.md'
            scope.write_text(json.dumps({'repo': str(root), 'route': {'roundCap': 5, 'checklists': ['security']}}))
            with patch('sys.argv', ['review_usage.py', '--ledger', str(ledger), 'init', '--repo', str(root), '--scope', str(scope)]):
                usage.main()
            saved = usage.load(ledger)
            self.assertEqual(usage.POLICY['goCostAllocation'], saved['goCostAllocation'])
            with patch.dict(usage.POLICY, {'goCostAllocation': {**usage.POLICY['goCostAllocation'], 'monthlyFeeUSD': '999'}}):
                self.assertEqual('10', usage.load(ledger)['goCostAllocation']['monthlyFeeUSD'])
            with patch('sys.argv', ['review_usage.py', '--ledger', str(ledger), 'render', '--output', str(output),
                                   '--go-monthly-fee-usd', '10', '--go-monthly-allowance-usd', '60']):
                usage.main()
            self.assertEqual({'monthlyFeeUSD': '10', 'monthlyAllowanceUSD': '60', 'billingSource': 'go'}, usage.load(ledger)['goCostAllocation'])

    def test_missing_go_metadata_retains_known_receipts_and_labelled_estimate(self):
        run = {'model': 'opencode-go/glm-5.3-flash', 'effort': 'high'}
        common = {'requestID': 'known', 'sessionID': 'session', **run}
        value = {'cost': 0, 'opencode': {'billing_source': 'go', 'list_cost': .02, 'allowance': .08,
            'tokens': {'input': 100, 'cache_read': 0, 'cache_write_5m': 0, 'cache_write_1h': 0,
                       'output': 40, 'reasoning': 25}}}
        records = [{'event': 'guard', 'tools': ['pingu_review_source']},
                   {**common, 'event': 'request', 'kind': 'primary'},
                   {**common, 'event': 'response', 'status': 200},
                   {**common, 'event': 'usage', 'generationID': 'known-id', 'usage': value}]
        estimate_message = self.message('estimate')
        estimate_message['model'] = {'providerID': 'opencode-go', 'id': 'glm-5.3-flash', 'variant': 'high'}
        estimate = usage.reported_usage([estimate_message], run['model'], run['effort'])
        missing_values = [{'cost': 0}, {'cost': 0, 'opencode': {k: v for k, v in value['opencode'].items()
                                                            if k != 'billing_source'}}]
        for missing in missing_values:
            attempt = [*records, {**common, 'requestID': 'missing', 'event': 'request', 'kind': 'primary'},
                       {**common, 'requestID': 'missing', 'event': 'response', 'status': 200},
                       {**common, 'requestID': 'missing', 'event': 'usage', 'generationID': 'missing-id', 'usage': missing}]
            for allow_estimate in (False, True):
                captured = dict(run)
                if allow_estimate:
                    usage.collect_usage(captured, attempt, 'session', estimate, True)
                    self.assertIs(estimate, captured['usage'])
                    self.assertFalse(captured['usage']['billed'])
                else:
                    with self.assertRaises(usage.IncompleteUsage):
                        usage.collect_usage(captured, attempt, 'session', estimate, False)
                    self.assertIsNone(captured['usage'])
                self.assertTrue(captured['accountingIncomplete'])
                self.assertEqual(['missing'], captured['partialBilledUsage']['missingUsageMessageIDs'])
                self.assertEqual('0.08', captured['partialBilledUsage']['goUsage']['allowanceUSD'])

    def test_go_report_shows_partial_receipts_without_inventing_usage(self):
        run = {'round': 1, 'model': 'opencode-go/glm-5.3-flash', 'effort': 'high',
               'base': 'a' * 40, 'from': 'a' * 40, 'head': 'b' * 40}
        common = {'requestID': 'known', 'sessionID': 'session', 'model': run['model'], 'effort': run['effort']}
        value = {'cost': 0, 'opencode': {'billing_source': 'go', 'list_cost': .02, 'allowance': .08,
            'tokens': {'input': 100, 'cache_read': 0, 'cache_write_5m': 0, 'cache_write_1h': 0,
                       'output': 40, 'reasoning': 25}}}
        records = [{'event': 'guard', 'tools': ['pingu_review_source']},
                   {**common, 'event': 'request', 'kind': 'primary'},
                   {**common, 'event': 'response', 'status': 200},
                   {**common, 'event': 'usage', 'generationID': 'known-id', 'usage': value},
                   {**common, 'requestID': 'missing', 'event': 'request', 'kind': 'primary'},
                   {**common, 'requestID': 'missing', 'event': 'response', 'status': 200}]
        complete = {**run, 'round': 2, 'usage': {**usage.go_usage(value), 'billed': True,
            'source': 'provider', 'costUSD': '0',
            'goUsage': {'listCostUSD': '.01', 'allowanceUSD': '.04', 'billingSources': ['go']}}}
        estimate_message = self.message('estimate')
        estimate_message['model'] = {'providerID': 'opencode-go', 'id': 'glm-5.3-flash', 'variant': 'high'}
        estimate = usage.reported_usage([estimate_message], run['model'], run['effort'])
        for allow_estimate in (False, True):
            captured = dict(run)
            try:
                usage.collect_usage(captured, records, 'session', estimate, allow_estimate)
            except usage.IncompleteUsage:
                self.assertFalse(allow_estimate)
            text = usage.render({'mergePolicy': 'manual', 'runs': [captured, complete]})
            self.assertIn('| glm-5.3-flash | $0.020000 (partial) | $0.080000 (partial) |', text)
            self.assertIn('| **Total** | $0.030000 (partial) | $0.120000 (partial) |', text)
            self.assertIn('Accounting incomplete', text)
            self.assertNotIn('Total billed review cost', text)
            # Without even one normalized receipt, zero accumulators are not evidence.
            empty = dict(run)
            try:
                usage.collect_usage(empty, [records[0], *records[-2:]], 'session', estimate, allow_estimate)
            except usage.IncompleteUsage:
                self.assertFalse(allow_estimate)
            empty_text = usage.render({'mergePolicy': 'manual', 'runs': [empty]})
            self.assertIn('| glm-5.3-flash | unavailable | unavailable |', empty_text)
            self.assertNotIn('$0.000000', empty_text)

    def test_default_effort_and_ui_concern_assignments_are_validated(self):
        ledger = {'runs': [], 'route': {'reviewers': [['haiku', 'high']],
            'escalationByConcern': {'ui': {'visual': [['kimi-code', 'default']], 'logic': [['kimi', 'high']]}}}}
        run = {'id': 'one', 'marker': 'Review-Run-ID: visual', 'model': 'opencode-go/kimi-k2.7-code', 'effort': 'default'}
        usage.validate_assignment(ledger, run)
        message = self.message('kimi')
        message['model'] = {'providerID': 'opencode-go', 'id': 'kimi-k2.7-code'}
        self.assertEqual([], usage.reported_usage([message], run['model'], 'default')['missingUsageMessageIDs'])
        with self.assertRaises(ValueError):
            usage.validate_assignment(ledger, {**run, 'model': 'opencode-go/gemini-4-argon'})

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
