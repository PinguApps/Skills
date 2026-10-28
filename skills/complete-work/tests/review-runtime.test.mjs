import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import runtime, { streamUsage } from '../scripts/review-runtime.mjs';

test('stream capture preserves byte content and records final billed usage only', async () => {
  const text = 'data: {"id":"gen-1","choices":[{"delta":{"content":"private response"}}]}\r\n\r\n' +
    'data: {"id":"gen-1","usage":{"prompt_tokens":12,"completion_tokens":7,"cost":0.004}}\r\n\r\n' +
    'data: [DONE]\r\n\r\n';
  const bytes = new TextEncoder().encode(text);
  const records = [];
  const input = new Response(new ReadableStream({start(controller) {
    for (let i = 0; i < bytes.length; i += 7) controller.enqueue(bytes.slice(i, i + 7));
    controller.close();
  }}), { headers: { 'content-type': 'text/event-stream' } });
  assert.equal(await streamUsage(input, value => records.push(value)).text(), text);
  assert.deepEqual(records, [
    {event: 'usage', generationID: 'gen-1', usage: {prompt_tokens: 12, completion_tokens: 7, cost: .004}},
    {event: 'end', complete: true},
  ]);
  assert.ok(!JSON.stringify(records).includes('private response'));
});

test('owned review gets only the source tool; another session keeps its tools', async () => {
  const state = mkdtempSync(join(tmpdir(), 'review-runtime-test-'));
  try {
    const run = {id: 'run', marker: 'Review-Run-ID: opaque', title: 'Subagent Test R1 Haiku',
      model: 'openrouter/anthropic/claude-haiku-5.5', effort: 'high'};
    const config = join(state, 'runtime.json');
    writeFileSync(config, JSON.stringify({state, runs: [run]}));
    const hooks = new Map();
    await runtime(config).setup({app: {version: 'test'},
      session: {hook: async (name, callback) => hooks.set(name, callback)},
      tool: {transform: async callback => callback({add() {}}),
        hook: async (name, callback) => hooks.set('tool.' + name, callback)},
    });
    await hooks.get('prompt')({sessionID: 'owned', prompt: {text: 'Wrapper\n' + run.marker + '\nReview'}});
    const event = {sessionID: 'owned', model: {providerID: 'openrouter', id: 'anthropic/claude-haiku-5.5', variant: 'high'},
      tools: {shell: {}, read: {}, pingu_review_source: {}}};
    await hooks.get('context')(event);
    assert.deepEqual(Object.keys(event.tools), ['pingu_review_source']);
    await assert.rejects(hooks.get('tool.execute.before')({sessionID: 'owned', tool: 'read'}), /only use/);
    const unrelated = {...event, sessionID: 'other', tools: {shell: {}}};
    await hooks.get('context')(unrelated);
    assert.deepEqual(Object.keys(unrelated.tools), ['shell']);
    assert.ok(readFileSync(join(state, 'runtime-ready.json'), 'utf8').includes('test'));
  } finally { rmSync(state, {recursive: true, force: true}); }
});
