// Durable, run-local evidence and assessment state. Reads are not assessments.
import { existsSync, readFileSync, writeFileSync, renameSync } from 'node:fs';
import { createHash } from 'node:crypto';

export class ReviewProgress {
  constructor(path, run) {
    this.path = path;
    const identity = JSON.stringify([run.head, run.scope, run.obligations, run.checks]);
    this.identity = createHash('sha256').update(identity).digest('hex');
    this.state = existsSync(path) ? JSON.parse(readFileSync(path, 'utf8')) : {
      identity: this.identity, version: 0, lastRequestVersion: -1,
      evidence: {}, assessments: {}, questions: {}, ranges: {}, halt: null,
    };
    if (this.state.identity !== this.identity) throw new Error('Progress identity changed; use a new run and reconcile coverage');
    this.obligations = new Set(run.obligations.map(item => item.id));
    this.requiredChecks = new Map(run.obligations.map(item => [item.id, item.checks ?? []]));
  }
  save() {
    writeFileSync(this.path + '.tmp', JSON.stringify(this.state));
    renameSync(this.path + '.tmp', this.path);
  }
  stop(reason) {
    this.state.halt ??= { outcome: 'INCOMPLETE', reason, at: new Date().toISOString() };
    this.save();
    throw new Error('INCOMPLETE: ' + this.state.halt.reason);
  }
  active() { if (this.state.halt) this.stop(this.state.halt.reason); }
  beforeRequest(kind = 'primary') {
    this.active();
    const cursor = kind === 'compaction' ? 'lastCompactionVersion' : 'lastRequestVersion';
    if (this.state.version === this.state[cursor])
      this.stop('No new evidence or assessment since the previous ' + kind + ' request');
    this.state[cursor] = this.state.version;
    this.save();
  }
  evidence(key, description, advances = true) {
    this.active();
    const id = createHash('sha256').update(key).digest('hex');
    if (!Object.hasOwn(this.state.evidence, id)) {
      this.state.evidence[id] = description;
      if (advances) this.state.version++;
      this.save();
    }
    return id;
  }
  source(input, page, description) {
    this.active();
    if (input.operation === 'search')
      return this.evidence('search:' + (page.content ?? JSON.stringify(page)), description);
    const text = page.content ?? '';
    const key = JSON.stringify([input.operation, input.ref, input.path ?? '']);
    const start = input.offset ?? 0, end = start + text.length;
    const ranges = this.state.ranges[key] ?? [];
    const advances = end > start && !ranges.some(([a, b]) => a <= start && b >= end);
    let merged = [start, end];
    const kept = [];
    for (const range of ranges) {
      if (range[1] < merged[0] || range[0] > merged[1]) kept.push(range);
      else merged = [Math.min(range[0], merged[0]), Math.max(range[1], merged[1])];
    }
    if (end > start) this.state.ranges[key] = [...kept, merged].sort((a, b) => a[0] - b[0]);
    return this.evidence(JSON.stringify([key, start, text]), description, advances);
  }
  checkpoint(input) {
    this.active();
    if (!this.obligations.has(input.obligation)) throw new Error('Unknown review obligation');
    if (input.action === 'incomplete') this.stop(input.reason?.trim() || 'Required review evidence unavailable');
    const refs = input.evidence ?? [];
    if (!input.reason?.trim() || !refs.length || refs.some(id => !Object.hasOwn(this.state.evidence, id)))
      throw new Error('Checkpoint requires a concrete reason and observed evidence IDs');
    if (input.action === 'question') {
      if (!input.question?.trim() || !input.settleWhen?.trim()) throw new Error('Question requires an ID and settlement criterion');
      // Opening/renaming questions alone cannot keep inference alive.
      const question = { obligation: input.obligation, reason: input.reason, settleWhen: input.settleWhen, evidence: refs };
      const prior = Object.hasOwn(this.state.questions, input.question) ? this.state.questions[input.question] : undefined;
      if (prior && JSON.stringify(prior) !== JSON.stringify(question)) throw new Error('Question already registered');
      Object.defineProperty(this.state.questions, input.question, { value: question, enumerable: true, configurable: true, writable: true });
    } else if (input.action === 'resolve') {
      const question = this.state.questions[input.question];
      if (!question || question.obligation !== input.obligation) throw new Error('Unknown question for obligation');
      if (!question.resolution) {
        question.resolution = { reason: input.reason, evidence: refs };
      }
    } else if (input.action === 'assess') {
      if (this.requiredChecks.get(input.obligation).some(check => !refs.some(id =>
        this.state.evidence[id]?.check === check && this.state.evidence[id]?.exitCode === 0)))
        throw new Error('Required named checks must succeed and be cited before assessment');
      if (Object.values(this.state.questions).some(q => q.obligation === input.obligation && !q.resolution))
        throw new Error('Resolve outstanding questions before assessing this obligation');
      if (!Object.hasOwn(this.state.assessments, input.obligation)) {
        Object.defineProperty(this.state.assessments, input.obligation, { value: { reason: input.reason, evidence: refs }, enumerable: true, configurable: true, writable: true });
        this.state.version++;
      }
    } else throw new Error('Unknown checkpoint action');
    this.save();
    return this.state;
  }
}
