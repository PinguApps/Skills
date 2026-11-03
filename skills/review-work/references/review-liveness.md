# Progress, incomplete reviews and recovery

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

Source results and named checks return durable evidence IDs. Use
`pingu_review_checkpoint` with `action: assess`, `obligation`, a concrete `reason`
and observed `evidence` IDs to record an assessment. Resolve outstanding questions
first. Assess means examined, not necessarily correct: preserve actionable findings
and return CHANGES when appropriate. Required checks must succeed before assessment.

Before context reads/searches, register `action: question` with its `obligation`,
unique `question` ID, concrete failure concern in `reason`, existing `evidence`
and a `settleWhen` criterion. Pass that question ID to source reads/searches.
Use `action: resolve` with evidence and reasoning when settled. Initial diff paging
requires no question. Further exploration must address an outstanding obligation.
Once all obligations are assessed, return the final verdict.

The runtime persists evidence identities, assessments, questions and the last
primary-request progress version. Identical evidence, repeated assessments,
opening/renaming questions, resolution alone, compaction and reasoning tokens do
not advance it. Another primary inference requires new evidence or a newly assessed
obligation. A stalled request boundary records INCOMPLETE and blocks further
inference. This permits large progressing reviews without a size-based cutoff.
It is a mechanical cycle detector, not a proof that every novel read is useful;
the parent still validates relevance and assessment quality.

Use `action: incomplete` with an obligation and exact reason when required evidence,
execution or setup is missing. Return INCOMPLETE with findings, assessed obligations,
remaining work, gaps and cleanup status. Runtime halts may prevent a final model
message: the durable progress/transport records are then the incomplete result.
They never imply approval. Preserve state across compaction/restarts; a changed
contract needs a new run and explicit coverage reconciliation, not a reset.

## Parent recovery

On INCOMPLETE, a guard breach or provider deadline, cancel the owned T3 task with
`task_cancel` if still live, verify termination, collect partial usage and evidence,
then settle it. Follow delegation's completion contract; do not add status polling
or a second monitor. Blocking inference/aborting a provider request is not proof
that the T3 task or subprocess descendants have terminated. Retain incomplete
receipts honestly and preserve unrelated reviewers/resources.

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
Choose the next eligible unused model/effort from the affected category's existing
`escalationByCategory` chain (UI uses its appropriate concern branch). Unused means
not dispatched on this revision, including incomplete attempts. Retain provider,
quota, protected-category and two-distinct-reviewer requirements; record which
reviewer slot the replacement fulfils. For a full-slot replacement carry every
original responsibility and use the highest-risk category's chain. If no applicable
UI concern can be identified, report the policy gap rather than choosing a model.

A replacement is a fresh `delegate_task` and run ID after its predecessor is
terminal. It stays in the same round for the same revision and retains all costs,
findings, attempts and coverage history. Repair shared setup first; switching
models cannot fix a broken tool. Proceed through the finite eligible chain only
while each attempt has a cause-specific justification. Exhausted models, unresolved
shared failures or no credible recovery block publication. Continue independent
work and report the exact gap and smallest next action; ask for user input only
when it is actually needed. Never waive missing coverage or silently cycle models.
