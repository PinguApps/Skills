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
      evidence: {}, assessments: {}, questions: {}, ranges: {}, phase: 'review', halt: null,
      actions: [], history: [], analysisVersion: 0, checkpointPlans: {}, challenge: null,
    };
    if (this.state.identity !== this.identity) throw new Error('Progress identity changed; use a new run and reconcile coverage');
    this.state = { actions: [], history: [], analysisVersion: 0, checkpointPlans: {}, challenge: null, ...this.state };
    this.obligations = new Set(run.obligations.map(item => item.id));
    this.requiredChecks = new Map(run.obligations.map(item => [item.id, item.checks ?? []]));
  }
  save() {
    writeFileSync(this.path + '.tmp', JSON.stringify(this.state));
    renameSync(this.path + '.tmp', this.path);
  }
  stop(reason, outcome = 'NEEDS_DIAGNOSIS') {
    this.state.halt ??= { outcome, reason, at: new Date().toISOString() };
    this.save();
    throw new Error(this.state.halt.outcome + ': ' + this.state.halt.reason);
  }
  active() { if (this.state.halt) this.stop(this.state.halt.reason); }
  beforeRequest(kind = 'primary') {
    this.active();
    // Reasoning and native compaction are opaque. Neither is evidence of a stall.
    if (kind === 'compaction') return;
    const revision = JSON.stringify([this.state.version, this.state.analysisVersion]);
    if (revision !== this.state.lastRevision) {
      this.state.history = [];
      this.state.challenge = null;
      this.state.phase = 'review';
    } else if (this.state.actions.length) {
      const trace = JSON.stringify(this.state.actions);
      if (this.state.history.includes(trace)) {
        const challenge = this.state.challenge;
        if (challenge?.trace === trace && challenge.delivered)
          this.stop('Identical investigation actions/results recurred after reconciliation with unchanged evidence and analysis; parent diagnosis required');
        this.state.challenge = { trace, delivered: false };
        this.state.phase = 'reconcile';
      } else this.state.history.push(trace);
    }
    this.state.lastRevision = revision;
    this.state.actions = [];
    this.save();
  }
  reconciliationDelivered() {
    if (this.state.challenge) { this.state.challenge.delivered = true; this.save(); }
  }
  action(type, input, result) {
    const canonical = value => Array.isArray(value) ? value.map(canonical) : value && typeof value === 'object'
      ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
    this.state.actions.push(canonical({ type, input, result }));
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
    let id;
    if (input.operation === 'search') {
      id = this.evidence('search:' + (page.content ?? JSON.stringify(page)), description);
      this.action('source', input, id);
      return id;
    }
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
    id = this.evidence(JSON.stringify([key, start, text]), description, advances);
    this.action('source', input, id);
    return id;
  }
  checkpoint(input) {
    this.active();
    if (!this.obligations.has(input.obligation)) throw new Error('Unknown review obligation');
    if (input.action === 'incomplete') {
      if (!input.reason?.trim()) throw new Error('Report the concrete missing evidence or setup before requesting diagnosis');
      this.stop('Obligation ' + input.obligation + ': ' + input.reason, 'BLOCKER_REPORTED');
    }
    const refs = input.evidence ?? [];
    if (!input.reason?.trim() || (!['question', 'reconcile'].includes(input.action) && !refs.length) || refs.some(id => !Object.hasOwn(this.state.evidence, id)))
      throw new Error('Checkpoint requires a concrete reason and observed evidence IDs');
    const priorAnalysis = JSON.stringify([this.state.questions, this.state.assessments, this.state.checkpointPlans]);
    if (input.action === 'question') {
      if (!input.question?.trim() || !input.settleWhen?.trim()) throw new Error('Question requires an ID and settlement criterion');
      // Questions are analysis state, not source coverage or approval.
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
    } else if (input.action === 'reconcile') {
      if (!input.nextAction?.trim() || !input.settleWhen?.trim()) throw new Error('Reconciliation requires a concrete next action and settlement criterion');
      this.state.checkpointPlans[input.obligation] = { reason: input.reason, nextAction: input.nextAction, settleWhen: input.settleWhen, evidence: refs };
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
    if (priorAnalysis !== JSON.stringify([this.state.questions, this.state.assessments, this.state.checkpointPlans])) this.state.analysisVersion++;
    this.save();
    return this.state;
  }
}
