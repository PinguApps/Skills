import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import runtime, { streamUsage, pricingCeiling } from '../scripts/review-runtime.mjs';
const pricingGuard = JSON.parse(readFileSync(new URL('../references/review-policy.json', import.meta.url), 'utf8')).pricingGuard;

test('pricing bumps lower effective input limit; flat prices keep native window', () => {
  const model = {limit: {context: 1_000_000}, cost: [
    {input: .1, output: .5, cache: {read: .01}},
    {tier: {type: 'context', size: 100_000}, input: .5, output: 2.5, cache: {read: .05}},
  ]};
  assert.deepEqual(pricingCeiling(model, pricingGuard.inputFraction), {threshold: 100_000, input: 70_000});
  assert.equal(pricingCeiling({...model, cost: [model.cost[0]]}, pricingGuard.inputFraction), undefined);
  assert.deepEqual(pricingCeiling({...model, cost: [model.cost[1]]}, pricingGuard.inputFraction), {threshold: 100_000, input: 70_000});
  assert.deepEqual(pricingCeiling({...model, cost: [
    {input: 1, output: 1}, {tier: {type: 'context', size: 100_000}, input: 1, output: 1, cache: {read: .1}},
  ]}, pricingGuard.inputFraction), {threshold: 100_000, input: 70_000});
});

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

test('provider usage survives consumer cancellation; malformed capture leaves response bytes intact', async () => {
  const records = [];
  const data = 'data: {"id":"gen-cancel","usage":{"cost":0.01,"prompt_tokens":5,"completion_tokens":3}}\n\n';
  const response = streamUsage(new Response(new ReadableStream({start(controller) {
    controller.enqueue(new TextEncoder().encode(data));
  }}), {headers: {'content-type': 'text/event-stream'}}), value => records.push(value));
  const reader = response.body.getReader();
  await reader.read();
  await reader.cancel();
  assert.equal(records.filter(r => r.event === 'usage').length, 1);
  assert.equal(records.filter(r => r.event === 'end' && r.complete).length, 0);
  const malformed = 'data: not-json\n\ndata: [DONE]\n\n';
  const errors = [];
  assert.equal(await streamUsage(new Response(malformed, {headers: {'content-type': 'text/event-stream'}}), value => errors.push(value)).text(), malformed);
  assert.ok(errors.some(r => r.event === 'capture-error'));
  assert.ok(!errors.some(r => r.event === 'end' && r.complete));
  const oversized = JSON.stringify({content: 'x'.repeat(4_000_001)});
  assert.equal(await streamUsage(new Response(oversized), value => errors.push(value)).text(), oversized);
});

test('registered review markers fail closed and overlapping requests keep exact correlation', async () => {
  const state = mkdtempSync(join(tmpdir(), 'review-runtime-test-'));
  try {
    const run = {id: 'owned', marker: 'Review-Run-ID: valid', title: 'R2: GLM',
      model: 'openrouter/z-ai/glm-5.3-flash', effort: 'high'};
    const config = join(state, 'runtime.json');
    writeFileSync(config, JSON.stringify({state, pricingGuard, models: ['openrouter/anthropic/claude-haiku-5.5'], runs: [run]}));
    const hooks = new Map();
    const protectedModels = [];
    await runtime(config).setup({app: {version: 'test'},
      model: {transform: async callback => callback({list: () => [{providerID: 'openrouter', id: 'anthropic/claude-haiku-5.5',
        limit: {context: 1_000_000}, cost: [{input: 1}, {input: 2, tier: {type: 'context', size: 100_000}}]}],
        update: (provider, id, callback) => {const draft = {limit: {}}; callback(draft); protectedModels.push(draft);}}), list: async () => []},
      session: {hook: async (name, callback) => hooks.set(name, callback)},
      tool: {transform: async callback => callback({add() {}}), hook: async () => {}},
    });
    assert.equal(protectedModels[0].limit.input, 70_000, 'Later escalation models receive ceilings before any session uses them');
    for (const marker of ['Review-Run-ID: unknown', 'Review-Run-ID: ', 'Review-Run-ID: valid\nReview-Run-ID: extra']) {
      await assert.rejects(async () => hooks.get('prompt')({sessionID: 'unbound', prompt: {text: marker}}), /Unregistered or malformed/);
    }
    const prompt = {sessionID: 'session', prompt: {text: run.marker, files: ['ambient'], agents: ['ambient'], skills: ['ambient']}};
    await hooks.get('prompt')(prompt);
    assert.deepEqual(prompt.prompt.files, []);
    const model = {providerID: 'openrouter', id: 'z-ai/glm-5.3-flash', variant: 'high'};
    const guard = {sessionID: 'session', model, tools: {pingu_review_source: {}, read: {}}};
    await hooks.get('context')(guard);
    await hooks.get('compaction')({sessionID: 'session', model});
    const title = {sessionID: 'session'}; await hooks.get('title')(title); assert.equal(title.result, run.title);
    const request = body => new Request('https://openrouter.ai/api/v1/chat/completions', {method: 'POST', body: JSON.stringify(body)});
    await assert.rejects(hooks.get('http.request')({sessionID: 'session', model, kind: 'primary', request: request({provider: {only: ['pinned']}})}), /unpinned/);
    await assert.rejects(hooks.get('http.request')({sessionID: 'session', model, kind: 'unknown', request: request({})}), /Unknown review request kind/);
    const first = {sessionID: 'session', model, kind: 'primary', request: request({})};
    const second = {sessionID: 'session', model, kind: 'compaction', request: request({})};
    await hooks.get('http.request')(first); await hooks.get('http.request')(second);
    for (const event of [second, first]) {
      event.response = new Response(JSON.stringify({id: 'gen-' + event.kind, usage: {cost: .01, prompt_tokens: 1, completion_tokens: 1}}));
      await hooks.get('http.response')(event); await event.response.text();
    }
    const journal = readFileSync(join(state, 'owned.transport.jsonl'), 'utf8').trim().split('\n').map(JSON.parse);
    for (const usage of journal.filter(r => r.event === 'usage')) {
      const original = journal.find(r => r.event === 'request' && r.requestID === usage.requestID);
      assert.equal(usage.generationID, 'gen-' + original.kind);
    }
    assert.deepEqual(JSON.parse(readFileSync(join(state, 'runtime-ready.json'), 'utf8')).registeredRuns, ['owned']);
  } finally {
    assert.ok(state.startsWith(join(tmpdir(), 'review-runtime-test-')));
    rmSync(state, {recursive: true, force: true});
  }
});

test('owned review gets only the source tool; another session keeps its tools', async () => {
  const state = mkdtempSync(join(tmpdir(), 'review-runtime-test-'));
  try {
    const run = {id: 'run', marker: 'Review-Run-ID: opaque', title: 'R1: Haiku',
      model: 'openrouter/anthropic/claude-haiku-5.5', effort: 'high'};
    const config = join(state, 'runtime.json');
    writeFileSync(config, JSON.stringify({state, pricingGuard, runs: [run]}));
    const hooks = new Map();
    let sourceTool;
    await runtime(config).setup({app: {version: 'test'},
      model: {transform: async callback => callback({list: () => []}), list: async () => []},
      session: {hook: async (name, callback) => hooks.set(name, callback)},
      tool: {transform: async callback => callback({add(tool) { sourceTool = tool; }}),
        hook: async (name, callback) => hooks.set('tool.' + name, callback)},
    });
    assert.equal(sourceTool.options.codemode, false, 'source reader must be directly visible, not hidden in Code Mode');
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

test('tier reserve limits output and source bursts while the contract survives native compaction', async () => {
  const state = mkdtempSync(join(tmpdir(), 'review-runtime-test-'));
  try {
    const run = {id: 'tiered', marker: 'Review-Run-ID: tiered', model: 'openrouter/anthropic/claude-haiku-5.5',
      effort: 'high', head: 'head', from: 'from', base: 'base', reviewContract: 'G01 and G22 must remain in the review contract.'};
    const config = join(state, 'runtime.json');
    writeFileSync(config, JSON.stringify({state, repo: state, helper: 'unused-reader.py', python: join(state, 'missing-python.exe'), pricingGuard, runs: [run]}));
    writeFileSync(join(state, 'tiered.transport.jsonl'), JSON.stringify({event: 'source', operation: 'diff',
      offset: 12000, nextOffset: 24000, complete: false}) + '\n');
    const hooks = new Map(); let source;
    await runtime(config).setup({app: {version: 'test'},
      model: {transform: async callback => callback({list: () => [{providerID: 'openrouter', id: 'anthropic/claude-haiku-5.5',
        limit: {context: 1_000_000}, cost: [{input: 1}, {input: 2, tier: {type: 'context', size: 100_000}}]}],
        update: (provider, id, callback) => callback({limit: {}})}), list: async () => []},
      session: {hook: async (name, callback) => hooks.set(name, callback)},
      tool: {transform: async callback => callback({add(tool) {source = tool;}}), hook: async () => {}},
    });
    await hooks.get('prompt')({sessionID: 'session', prompt: {text: run.marker}});
    const model = {providerID: 'openrouter', id: 'anthropic/claude-haiku-5.5', variant: 'high'};
    // Mirrors SessionModelRequest.prepare in OpenCode 2.1.4: generation options
    // belong to context/compaction, while model.request has only URL/headers.
    const request = {sessionID: 'session', model, kind: 'primary', baseURL: 'https://openrouter.ai', headers: {}};
    if (hooks.has('model.request')) await hooks.get('model.request')(request);
    for (const hook of ['context', 'compaction']) {
      const event = {sessionID: 'session', model, options: {maxTokens: 131072}, tools: {pingu_review_source: {}}};
      await hooks.get(hook)(event);
      assert.equal(event.options.maxTokens, 8192, hook + ' must cap generation before native protocol lowering');
      assert.ok(event.system.some(part => part.text.includes('G01 and G22')));
      const systemText = event.system.map(part => part.text).join('\n');
      assert.equal(systemText.includes('Source paging progress'), hook === 'compaction',
        'Only compaction needs changing progress metadata; primary prefixes remain stable for caching');
      if (hook === 'compaction') assert.ok(systemText.includes('"nextOffset":24000'), 'Native summaries receive durable paging cursors');
    }
    const native = body => new Request('https://openrouter.ai/api/v1/chat/completions', {method: 'POST', body: JSON.stringify(body)});
    await assert.rejects(hooks.get('http.request')({...request, request: native({max_tokens: 32000})}), /output reserve/);
    await hooks.get('http.request')({...request, request: native({max_tokens: 8192})});
    const first = source.execute({operation: 'search', pattern: 'needle', path: 'scope/file.py'}, {sessionID: 'session'}).catch(error => error);
    const second = await source.execute({operation: 'read', path: 'other.py'}, {sessionID: 'session'});
    assert.equal(JSON.parse(second.content).deferred, true, 'Parallel source calls cannot exceed the reserved page budget');
    const failedProcess = await first;
    assert.equal(failedProcess.code, 'ENOENT');
    const prefix = failedProcess.spawnargs.indexOf('--path-prefix');
    assert.equal(failedProcess.spawnargs[prefix + 1], 'scope/file.py', 'A search path must not silently become a whole-repository search');
  } finally {
    assert.ok(state.startsWith(join(tmpdir(), 'review-runtime-test-')));
    rmSync(state, {recursive: true, force: true});
  }
});
