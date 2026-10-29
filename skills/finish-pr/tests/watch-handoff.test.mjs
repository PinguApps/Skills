import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';
import test from 'node:test';

const helper = fileURLToPath(new URL('../scripts/get-pr-review-state.ps1', import.meta.url));
const pwsh = process.env.PINGU_TEST_PWSH || 'pwsh';
const quota = {
  id: 5698955850, state: 'COMMENTED', commit_id: 'head',
  submitted_at: '2026-10-29T14:00:59Z',
  user: { login: 'copilot-pull-request-reviewer[bot]', type: 'Bot' },
  body: 'Copilot was unable to review this pull request because the user who requested the review has insufficient remaining quota.',
};
const clean = { ...quota, body: 'Copilot reviewed 8 files and generated no new comments.' };
function classify(reviews) {
  const command = `. '${helper.replaceAll("'", "''")}' -Library; ` +
    '$reviews = @([Console]::In.ReadToEnd() | ConvertFrom-Json); ' +
    "Get-CopilotReviewState -Reviews $reviews -HeadSha head " +
    "-RequestedReviewers @(@{login='Copilot';type='Bot'}) " +
    "-ReviewRequestedAt '2026-10-29T14:00:00Z' | ConvertTo-Json -Depth 20";
  return JSON.parse(execFileSync(pwsh, ['-NoProfile', '-Command', command], {
    input: JSON.stringify(reviews), encoding: 'utf8',
  }));
}

// Model of the upstream subscribe/reconcile contract, not an installed watcher.
// Barriers replace timing/sleeps; wakes cannot drain until the active turn ends.
function modelHost({ reconcile = true } = {}) {
  const reviews = [];
  let subscribed = false;
  let activeTurn = true;
  const queued = new Set();
  return {
    publish(review) { reviews.push(review); if (subscribed) queued.add('change'); },
    read() { return structuredClone(reviews); },
    register(duringReconcile = () => {}) {
      subscribed = true;
      duringReconcile();
      if (reconcile) queued.add('reconcile');
    },
    endTurn() { activeTurn = false; },
    drain() { if (activeTurn) return []; const wakes = [...queued]; queued.clear(); return wakes; },
  };
}

test('real helper ends a stale running verdict when quota precedes the final refresh', () => {
  assert.equal(classify([]).state, 'running');
  const host = modelHost();
  host.publish(quota);
  const refreshed = classify(host.read());
  assert.equal(refreshed.state, 'quota-pass');
  assert.equal(refreshed.clean, false);
});

for (const phase of ['between refresh and registration', 'during reconciliation', 'after registration']) {
  for (const result of [quota, clean]) {
    test(`simulated atomic host: ${result === quota ? 'quota' : 'ordinary review'} ${phase} resumes through real helper`, () => {
      const host = modelHost();
      assert.equal(classify(host.read()).state, 'running');
      if (phase === 'between refresh and registration') host.publish(result);
      host.register(() => { if (phase === 'during reconciliation') host.publish(result); });
      if (phase === 'after registration') host.publish(result);
      assert.deepEqual(host.drain(), [], 'A wake must survive the still-active turn.');
      host.endTurn();
      const wakes = host.drain();
      if (phase === 'between refresh and registration') assert.deepEqual(wakes, ['reconcile']);
      else assert.ok(wakes.includes('change'));
      const resumed = classify(host.read());
      assert.equal(resumed.state, result === quota ? 'quota-pass' : 'completed');
      assert.equal(resumed.clean, result !== quota);
    });
  }
}

test('simulated atomic host: an ordinary pending review remains pending after reconciliation', () => {
  const host = modelHost();
  host.register(); host.endTurn();
  assert.ok(host.drain().length);
  assert.equal(classify(host.read()).state, 'running');
  host.publish(clean);
  assert.ok(host.drain().length);
  assert.equal(classify(host.read()).state, 'completed');
});

test('negative control: later-events-only registration loses a result in the gap', () => {
  const host = modelHost({ reconcile: false });
  assert.equal(classify(host.read()).state, 'running');
  host.publish(quota);
  host.register(); host.endTurn();
  assert.deepEqual(host.drain(), [], 'The unsafe contract cannot resume without another event.');
  assert.equal(classify(host.read()).state, 'quota-pass', 'The result exists but was missed.');
});

// Optional read-only probe of the installed bundle's *actual* pure evaluator.
// This diagnoses the known unsupported contract; it is not full reactor/delivery
// integration and deliberately does not register a live watch or mutate a PR.
test('installed T3 evaluator probe: records the registration gap and later-event behaviour', {
  skip: !process.env.PINGU_T3_WATCH_BUNDLE && 'Set PINGU_T3_WATCH_BUNDLE to the extracted installed server bundle.',
}, () => {
  const bundle = readFileSync(process.env.PINGU_T3_WATCH_BUNDLE, 'utf8');
  const start = bundle.indexOf('function evaluatePullRequestWatch(');
  const end = bundle.indexOf('\nfunction snippet(', start);
  assert.ok(start >= 0 && end > start, 'Installed evaluator layout changed; inspect rather than assuming compatibility.');
  const evaluate = vm.runInNewContext(bundle.slice(start, end) + '\nevaluatePullRequestWatch', {
    isFailedCheck: check => ['failure', 'cancelled', 'action-required'].includes(check.status),
  });
  const watch = {
    startedAt: '2026-10-29T14:01:29Z', remarksThrough: '2026-10-29T14:01:29Z',
    remarkIds: [], headSha: 'head', failedChecks: [], passed: true,
    passedChecks: ['CI'], conflicting: false, wakes: 0,
  };
  const detail = { headSha: 'head', viewer: 'owner', capabilities: {},
    mergeability: 'mergeable', checks: [{ name: 'CI', status: 'success', required: true }] };
  const remark = { id: String(quota.id), kind: 'review', reviewState: quota.state,
    author: { login: quota.user.login }, body: quota.body, createdAt: quota.submitted_at };
  const lost = evaluate(watch, detail, [remark], Date.parse('2026-10-29T14:02:00Z'));
  assert.equal(lost.changes.length, 0, 'Probe expected the documented later-events-only host; re-audit the changed contract.');
  const later = evaluate(watch, detail, [{ ...remark, createdAt: '2026-10-29T14:01:30Z' }], Date.parse('2026-10-29T14:02:00Z'));
  assert.equal(later.changes[0].kind, 'remarks');
  assert.equal(classify([quota]).state, 'quota-pass');
  console.log('HOST LIMITATION CONFIRMED: the real evaluator loses the pre-registration quota review; a later review wakes. Full host delivery remains unverified.');
});
