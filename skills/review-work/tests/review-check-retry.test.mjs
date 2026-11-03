import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtempSync, rmSync, writeFileSync, readFileSync, unlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import runtime from '../scripts/review-runtime.mjs';
test('failed checks rerun, preserve failure evidence and cache the eventual success', async () => {
const root = mkdtempSync(join(tmpdir(), 'review-failed-check-'));
try {
  const marker = join(root, 'executions.txt');
  const policy = JSON.parse(readFileSync(new URL('../references/review-policy.json', import.meta.url)));
  const config = join(root, 'runtime.json');
  const script = "const fs=require('node:fs'); fs.appendFileSync(process.argv[1],'x'); process.exit(fs.readFileSync(process.argv[1],'utf8').length===1?1:0)";
  const run = { id: 'failed-check', head: 'head', scope: 'scope', marker: 'Review-Run-ID: failed-check',
    obligations: [{ id: 'A', description: 'Assess actual test result', checks: ['test'] }],
    checks: [{ id: 'test', executable: process.execPath, args: ['-e', script, marker], cwd: root, timeoutMs: 5000 }] };
  writeFileSync(config, JSON.stringify({ state: root, pricingGuard: policy.pricingGuard, modelPolicy: policy.models, runs: [run] }));
  const hooks = new Map(), tools = new Map();
  await runtime(config).setup({ app: { version: 'test' }, model: { transform: async cb => cb({ list: () => [] }), list: async () => [] },
    session: { hook: async (id, cb) => hooks.set(id, cb) },
    tool: { transform: async cb => cb({ add: tool => tools.set(tool.name, tool) }), hook: async () => {}, list: async () => [] } });
  await hooks.get('prompt')({ sessionID: 's', prompt: { text: run.marker } });
  const check = tools.get('pingu_review_check');
  const first = JSON.parse((await check.execute({ id: 'test' }, { sessionID: 's' })).content);
  assert.equal(first.exitCode, 1);
  const second = JSON.parse((await check.execute({ id: 'test' }, { sessionID: 's' })).content);
  assert.equal(second.exitCode, 0, 'A failed result must not permanently poison the check cache');
  assert.equal(readFileSync(marker, 'utf8'), 'xx');
  const third = JSON.parse((await check.execute({ id: 'test' }, { sessionID: 's' })).content);
  assert.ok(third.cached);
  assert.equal(third.evidence, second.evidence);
  const progress = JSON.parse(readFileSync(join(root, 'failed-check.progress.json')));
  assert.equal(progress.evidence[first.evidence].exitCode, 1);
  assert.equal(progress.evidence[second.evidence].exitCode, 0);
  unlinkSync(progress.evidence[second.evidence].resultFile);
  const recovered = JSON.parse((await check.execute({ id: 'test' }, { sessionID: 's' })).content);
  assert.equal(recovered.exitCode, 0);
  assert.ok(!recovered.cached);
  const cachedAgain = JSON.parse((await check.execute({ id: 'test' }, { sessionID: 's' })).content);
  assert.ok(cachedAgain.cached);
  assert.equal(readFileSync(marker, 'utf8'), 'xxx');
} finally { rmSync(root, { recursive: true, force: true }); }

});
