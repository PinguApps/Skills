import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { ReviewProgress } from '../scripts/review-progress.mjs';
import runtime, { requestDeadline, deadlineResponse } from '../scripts/review-runtime.mjs';

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'review-progress-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const run = { id: 'test', head: 'head', scope: 'scope', obligations: [{ id: 'A', description: 'Check cancellation' }] };
  const path = join(root, 'progress.json');
  return { root, run, path, progress: new ReviewProgress(path, run) };
}

test('only recurrence of an identical cycle after delivered reconciliation requests diagnosis', t => {
  const { progress: p, run, path } = fixture(t);
  const read = () => p.source({ operation: 'diff', ref: 'head' }, { content: 'cleanup' }, {});
  p.beforeRequest();
  const id = read();
  p.beforeRequest();
  read(); p.beforeRequest(); // first unchanged completed trace
  read(); p.beforeRequest(); // cycle suspicion, not a verdict
  assert.equal(p.state.phase, 'reconcile');
  assert.equal(p.state.halt, null);
  // Merely preparing a warning cannot prove the model received it.
  read(); p.beforeRequest();
  assert.equal(p.state.halt, null);
  p.reconciliationDelivered();
  assert.equal(read(), id);
  assert.throws(() => p.beforeRequest(), /NEEDS_DIAGNOSIS/);
  assert.equal(p.state.halt.outcome, 'NEEDS_DIAGNOSIS');
  assert.throws(() => new ReviewProgress(path, run).beforeRequest(), /NEEDS_DIAGNOSIS/);
  assert.throws(() => new ReviewProgress(path, { ...run, head: 'new' }), /identity changed/);
});

test('reasoning, consolidation and native compaction alone never classify a review as stalled', t => {
  const { progress: p } = fixture(t);
  for (let step = 0; step < 500; step++) {
    p.beforeRequest();
    p.beforeRequest('compaction');
  }
  assert.equal(p.state.phase, 'review');
  assert.equal(p.state.halt, null);
  assert.deepEqual(p.state.assessments, {});
});

test('large progressing review has no aggregate cap and evidence access never supplies assessment', t => {
  const { progress: p } = fixture(t);
  for (let page = 0; page < 500; page++) {
    p.beforeRequest();
    p.evidence('page:' + page, { page });
  }
  assert.deepEqual(p.state.assessments, {});
  const id = p.evidence('last', {});
  assert.throws(() => p.checkpoint({ action: 'assess', obligation: 'unknown', reason: 'ok', evidence: [id] }), /Unknown/);
  assert.throws(() => p.checkpoint({ action: 'assess', obligation: 'A', reason: 'ok', evidence: ['invented'] }), /observed evidence/);
});

test('overlapping and out-of-range reads do not fabricate new evidence coverage or imply a stall', t => {
  const { progress: p } = fixture(t);
  p.source({ operation: 'read', path: 'a', ref: 'head' }, { content: 'abcdef' }, {});
  p.beforeRequest();
  const version = p.state.version;
  p.source({ operation: 'read', path: 'a', ref: 'head', offset: 2 }, { content: 'cde' }, {});
  p.source({ operation: 'read', path: 'invented', ref: 'head', offset: 9999 }, { content: '' }, {});
  p.beforeRequest();
  assert.equal(p.state.version, version);
  assert.equal(p.state.halt, null);
});

test('legitimate rechecking with a concrete changed analysis plan clears suspicion', t => {
  const { progress: p, path, run } = fixture(t);
  const read = () => p.source({ operation: 'diff', ref: 'head' }, { content: 'cleanup' }, {});
  p.beforeRequest(); const id = read(); p.beforeRequest();
  read(); p.beforeRequest(); read(); p.beforeRequest();
  p.reconciliationDelivered();
  p.checkpoint({ action: 'reconcile', obligation: 'A', reason: 'Compare the existing cleanup evidence against cancellation during startup',
    nextAction: 'Recheck the already read cleanup path for startup ordering', settleWhen: 'Establish whether cleanup registration precedes startup', evidence: [id] });
  read(); p.beforeRequest();
  const resumed = new ReviewProgress(path, run);
  assert.equal(resumed.state.phase, 'review');
  assert.equal(resumed.state.halt, null);
  assert.deepEqual(resumed.state.assessments, {});
});

test('initial questions, tool corrections and resolutions are analysis rather than evidence-access requirements', t => {
  const { progress: p } = fixture(t);
  p.beforeRequest();
  p.action('tool-error', { invalid: 'first attempt' }, 'missing parameter'); p.beforeRequest();
  p.checkpoint({ action: 'question', obligation: 'A', question: 'initial', reason: 'Does cancellation clean up?', settleWhen: 'Inspect cleanup', evidence: [] });
  p.beforeRequest();
  const id = p.source({ operation: 'diff', ref: 'head' }, { content: 'cleanup' }, {});
  p.beforeRequest();
  p.checkpoint({ action: 'resolve', obligation: 'A', question: 'initial', reason: 'Cleanup verified', evidence: [id] });
  p.beforeRequest();
  assert.equal(p.state.phase, 'review');
  assert.equal(p.state.halt, null);
});

test('named check executes an actual child process once and cannot accept arbitrary commands', async t => {
  const { root, run } = fixture(t);
  const policy = JSON.parse(await (await import('node:fs/promises')).readFile(new URL('../references/review-policy.json', import.meta.url)));
  const marker = join(root, 'executions.txt');
  const config = join(root, 'runtime.json');
  const script = "require('node:fs').appendFileSync(process.argv[1], 'x'); console.log(process.env.DOTNET_ADD_GLOBAL_TOOLS_TO_PATH)";
  writeFileSync(config, JSON.stringify({ state: root, pricingGuard: policy.pricingGuard, modelPolicy: policy.models,
    runs: [{ ...run, marker: 'Review-Run-ID: test', checks: [{ id: 'real', executable: process.execPath,
      args: ['-e', script, marker], cwd: root, timeoutMs: 5000 }] }] }));
  const hooks = new Map(), tools = new Map();
  await runtime(config).setup({ app: { version: 'test' }, model: { transform: async cb => cb({ list: () => [] }), list: async () => [] },
    session: { hook: async (id, cb) => hooks.set(id, cb) },
    tool: { transform: async cb => cb({ add: tool => tools.set(tool.name, tool) }), hook: async () => {}, list: async () => [] } });
  await hooks.get('prompt')({ sessionID: 's', prompt: { text: 'Review-Run-ID: test' } });
  const check = tools.get('pingu_review_check');
  await assert.rejects(check.execute({ id: 'shell' }, { sessionID: 's' }), /Unknown named check/);
  const first = JSON.parse((await check.execute({ id: 'real' }, { sessionID: 's' })).content);
  assert.equal(first.exitCode, 0);
  assert.equal(first.stdout.trim(), '0');
  assert.equal(JSON.parse((await check.execute({ id: 'real' }, { sessionID: 's' })).content).cached, true);
  const { readFileSync } = await import('node:fs');
  assert.equal(readFileSync(marker, 'utf8'), 'x');
});

test('provider deadline cancels a silent body and preserves operation failure', async () => {
  let timedOut = false, cancelled = false;
  const deadline = requestDeadline(new Request('https://example.test'), 25, () => { timedOut = true; });
  const response = deadlineResponse(new Response(new ReadableStream({ cancel() { cancelled = true; } })), deadline);
  // Keep the test event loop alive while production uses an unref timer.
  const keepAlive = setTimeout(() => {}, 1000);
  try { await assert.rejects(response.text(), /deadline exceeded/); }
  finally { clearTimeout(keepAlive); }
  assert.ok(timedOut && cancelled && deadline.request.signal.aborted);
});
