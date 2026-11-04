# Progress, incomplete reviews and recovery

For implementation callers, apply complete-work's [continuation and stopping
contract](../../complete-work/SKILL.md#continuation-and-stopping-contract) to
publication gaps and diagnostic returns; the caller owns recovery and progression.

Read before preparing reviewers and whenever a run stops without valid approval.
Use the frozen runtime for enforcement; instructions alone cannot stop a looping
or unresponsive reviewer. There is no aggregate token, request or duration budget.
Existing pricing reserves and review-round caps retain their separate purposes.

## Prepare a finite review contract

Record `obligations` in each run: objects with unique `id`, concrete `description`
and optional `checks` containing required named-check IDs. Account for the complete
assigned diff, acceptance criteria, applicable categories and required runtime
verification. Reading a path is evidence access, not an assessment of behaviour.
The parent reconciles this checklist with the scope manifest before dispatch and
checks the assessments against evidence afterwards. A model-authored checklist or
verdict alone cannot certify complete coverage.

Record `checks` as fixed definitions: `id`, absolute `executable`, string `args`,
absolute `cwd`, optional child-only `env`, positive `timeoutMs` and `timeoutReason`.
Inspect commands/scripts and side effects before approving them. Execute scripts
from trusted immutable artifacts; fixed arguments do not sandbox an unsafe script.
Supply distinct disposable resources for concurrent reviewers. Checks must own
and clean up any processes/resources they launch, including on cancellation.
PATH and persistent settings remain unchanged. Set `executionTools: []`;
`pingu_review_check` replaces general shell/browser tools. UI checks may use a
fixed approved browser-test script. If the available checks cannot exercise a
required interaction, report the missing check rather than granting unrestricted
execution or calling the source review sufficient.

Set `providerTimeoutMs` and `providerTimeoutReason` for each physical inference
operation, including response consumption and compaction. Choose the deadline
from provider guarantees, observed operation timings or an explicit operational
expectation, with room for the assigned model's reasoning. Check deadlines follow
the same rule. These are justified per-operation deadlines, not universal review
limits. Silent hangs cannot be recovered automatically without a time threshold.

## Reviewer progress

Source results and named checks return durable evidence IDs. Successful named
checks are cached for the committed snapshot; failed checks may run again.
Identical results retain their evidence identity, so retrying the same failure
does not fabricate progress or erase the earlier failure. Use
`pingu_review_checkpoint` with `action: assess`, `obligation`, a concrete `reason`
and observed `evidence` IDs to record an assessment. Resolve outstanding questions
first. Assess means examined, not necessarily correct: preserve actionable findings
and return CHANGES when appropriate. Required checks must execute before assessment. A failing check is valid evidence
for CHANGES; approval still requires the parent to verify successful required checks.

Before context reads/searches, register `action: question` with its `obligation`,
unique `question` ID, concrete failure concern in `reason`, `evidence` IDs when available
and a `settleWhen` criterion. An initial question may arise from supplied requirements
with an empty evidence list; assessments and resolutions require observed evidence. Pass that question ID to source reads/searches.
Use `action: resolve` with evidence and reasoning when settled. Initial diff paging
requires no question. Further exploration must address an outstanding obligation.
Once all obligations are assessed, return the final verdict.

The runtime persists evidence coverage, assessments, question/analysis changes and
completed tool-action traces. Registering or renaming unresolved questions does
not advance analysis; evidence-backed resolutions and concrete plans do. Missing checkpoints, reasoning-only requests, native
compaction, individual tool errors, rereading and unchanged source are **not** proof
of a stall. They never automatically produce INCOMPLETE. Resolving a question or
changing the analysis plan can be meaningful progress without reading new source.

Only recurrence of an identical completed investigation trace against unchanged
evidence **and analysis** raises a cycle suspicion. The runtime first supplies a
reconciliation prompt. Use `action: reconcile`, `obligation`, concrete `reason`,
`nextAction`, `settleWhen` and available `evidence` IDs to explain legitimate
rechecking or a different discriminating step. A changed plan, resolved question,
new evidence or assessment clears the suspicion. Novel prose alone is not proof
of useful work; the parent evaluates its substance when diagnosing.

If that same trace recurs after the reconciliation prompt was actually sent, the
runtime hands back NEEDS_DIAGNOSIS with the trace and durable state. This interrupts
a demonstrated mechanical cycle; it does **not** classify the review INCOMPLETE
or prove a semantic deadlock. A prepared but unsent prompt cannot satisfy this gate.
Single repeated actions without recurrence after reconciliation do not stop a run.
No timer or missing-progress request count decides this outcome.

Use `action: incomplete` to report a concrete missing obligation/evidence/setup;
this records BLOCKER_REPORTED for parent verification, not a final incomplete
verdict. Provider/check deadlines record OPERATION_INTERRUPTED; a source-access
violation records INVALID_REVIEW. A slow operation is not evidence that the whole
review stalled. Preserve state across compaction/restarts; a changed contract needs
a new run and explicit coverage reconciliation, not a reset.

## Parent recovery

On a diagnostic handoff, reported blocker, guard breach or interrupted operation,
cancel the owned T3 task with
`task_cancel` if still live, verify termination, collect partial usage and evidence,
then settle it. Follow delegation's completion contract; do not add status polling
or a second monitor. Blocking inference/aborting a provider request is not proof
that the T3 task or subprocess descendants have terminated. Retain incomplete
receipts honestly and preserve unrelated reviewers/resources.

### Confirm before classifying INCOMPLETE

The parent owns the final classification. Inspect the actual actions, results,
question/plan changes and remaining obligations. Require corroborating evidence:
a repeated unresolved investigation after reconciliation with no substantive
change in reasoning, evidence or tests, and no credible safe next step; or a
verified external blocker that prevents required coverage after feasible recovery.
A progress counter, output volume, elapsed time, repeated read or isolated error
alone satisfies none of this. When uncertain, continue or resume the relevant
review work; favour preserving productive work over declaring a stall.

Try a concrete recovery first: correct tool usage, reuse existing evidence,
supply missing setup, isolate the specific question, or choose an eligible unused
model when the cause is model-specific. Continue independent obligations. Diagnose
and recover autonomously; do not ask the user merely to confirm telemetry. Only
record INCOMPLETE when required coverage genuinely remains unobtainable after
these cause-specific options are exhausted or no justified safe recovery exists.
Record the supporting observations and attempted remedies. A diagnostic pause,
interrupted operation, unfinished obligation or remaining reasoning is not itself
an incomplete verdict. Never use a renamed diagnostic state to justify abandoning
productive work or publishing without complete coverage.

Classify the cause before deciding the next action:

| Cause | Recovery |
| --- | --- |
| Missing setup, evidence or safe check | Supply and verify it; review outstanding obligations. |
| Tool/provider failure | Verify that the operational cause is resolved before retrying. |
| Repeated investigation | Settle the concrete stuck question or restructure its remaining scope. |
| Source-access/guard violation | Invalidate that run's coverage and approval; repair the guard, then replace the full assignment. |
| Requirement ambiguity | Resolve from available context; ask the user only for a material missing decision. |
| Model-specific stall/failure | Replace the reviewer under the policy below when a different model is a justified remedy. |

Record the cause, changed condition, evidence for recovery and why it should help.
An unchanged retry is not recovery. Preserve trusted, explicitly assessed partial
coverage for the same committed snapshot; it is evidence, not an approval. Keep
unresolved findings and obligations visible. A replacement receives requirements,
verified evidence and the missing scope, without another reviewer's verdict or
unverified conclusions. Its own final verdict must reconcile inherited assessments.

### Model replacement

Operational replacement is explicitly authorized as well as concern escalation.
A replacement fulfils the original reviewer slot, including all its responsibilities;
carry forward trusted partial assessments without dropping those responsibilities.
Choose the next eligible unused model/effort from the slot's highest-risk category's
`escalationByCategory` chain (UI uses its appropriate concern branch). Focused
issue-only reviews remain ordinary concern escalations, not slot replacements.
Unused means not dispatched on this revision, including incomplete attempts.
An unsent registration does not consume a model; reconcile an ambiguous launch
before treating it as unsent. Retain provider, quota, protected-category and
two-distinct-reviewer requirements; record the slot the replacement fulfils.
If no applicable UI concern can be identified, report the policy gap rather than
choosing a model.

A replacement is a fresh `delegate_task` and run ID after its predecessor is
terminal. It stays in the same round for the same revision and retains all costs,
findings, attempts and coverage history. Repair shared setup first; switching
models cannot fix a broken tool. Proceed through the finite eligible chain only
while each attempt has a cause-specific justification. Exhausted models, unresolved
shared failures or no credible recovery block publication. Continue independent
work and report the exact gap and smallest next action; ask for user input only
when it is actually needed. Never waive missing coverage or silently cycle models.
