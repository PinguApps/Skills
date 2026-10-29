# PR watch handoff

Read before yielding for any PR check, review or merge-queue event, including a
coordinator waiting for a delegated worker. This is the shared handoff contract.

## Prepare, refresh, decide, subscribe

1. Finish independent work and prepare the ledger, PR link, exact repository/head,
   merge policy, accepted review-request receipts and verified quota associations.
   Inspect the live host watch schema and its delivery guarantee before the final
   refresh. Require one of the supported mechanisms below; tool names alone do not
   prove support.
2. Immediately before subscription, run `scripts/get-pr-review-state.ps1` with the
   exact PR and any recorded `-ReviewRequestedAt`/`-ReviewRequestedHead` and
   `-QuotaEvidenceFile`. It fetches every page of reviews, requested reviewers,
   issue comments, inline threads/comments, check runs, commit statuses and review
   request history, and verifies the published head/request list again. Retain its
   complete output. Read/authentication failures or unexpected head movement block
   the handoff; they do not mean approval. Check required-check/protection policy
   separately as part of the normal merge audit.
3. Reclassify **every** pending condition from that fresh evidence, including new
   feedback. Discard earlier `running` verdicts, even those from a worker. Apply
   [Copilot's contract](copilot.md): trusted, correctly associated quota exhaustion
   ends its wait, including a submitted `COMMENTED` review containing the observed
   insufficient-quota message. Record quota-pass without claiming a source review.
   Issue-comment/check quota needs verified current-head association; words alone
   do not associate it. If association needs investigation, do that work and then
   refresh again. Other started reviews, failing/pending checks, actionable feedback
   and protected threads retain their own requirements.
4. If the condition cleared or needs action, continue the implementation owner's
   normal audit/repair/handoff now. A coordinator resumes the same worker with the
   new evidence and remaining requirements, even without a new watcher event; it
   never merges for the worker. A manual hold produces a ready handoff once the
   audit passes. Neither quota nor a watch result overrides that hold, thread
   protections, head verification or normal protected merging.
5. If only external events remain, register the supported watcher as the **next
   external action** after refresh/classification. Perform no unrelated work in
   between. Pass only inputs the live tool supports. End the turn immediately
   after registration when required; agent-side reads after that call cannot be
   the reconciliation mechanism. Delegated workers/reviewers never watch: the
   top-level PR owner or coordinator owns subscription and cleanup.

On a wake, keep the existing watch, refresh all evidence and resume the normal
audit or the same worker. A wake is not a merge decision. Do not duplicate a
surviving watch. For several worker PRs, prepare them first and register only as
the host's turn-ending rules permit; do not promise coverage for unregistered PRs.
Before terminal handoff remove owned watches; retain a supported needed watch only
when yielding for its events. Preserve convergence budgets across wakes.

## Required host guarantee

- **Atomic subscription with reconciliation:** the host durably subscribes first,
  then reads complete current state and queues a reconciliation wake as part of
  registration. Events racing that read remain covered. The wake must survive the
  current active turn and be delivered after it ends, even if no later GitHub
  event occurs. This includes already-terminal reviews/checks and merge/closure.
- **Cursor replay:** the host supplies an opaque durable cursor **before** the
  final read and accepts it at subscription, replaying all relevant events from
  that boundary. No silent cursor expiry/truncation; reject an invalid cursor.
  A client timestamp or `readStartedAt` is not such a cursor. Replay plus live
  delivery must cover submitted reviews, issue/inline feedback, reviewer requests,
  checks, head changes and merge/closure without a gap.

Both mechanisms must retain delivery across registration/turn completion and
restarts, and allow deduplication without losing actionable state. Head changes
invalidate the old audit and require fresh classification. Neither a second
pre-watch read nor registering twice supplies either guarantee.

## Unsupported host and upstream repair

The inspected T3 `watch_pull_request` contract says: **"Handle old comments first.
Only later ones wake you. After this call, end your turn."** Its schema accepts
PR identity/thread only: no cursor, preceding-state receipt or reconciliation
option. That exposed contract cannot guarantee this handoff. Do not invent
parameters, poll, sleep, schedule recovery or perform a forbidden post-watch read.
Report `BLOCKED: host lacks atomic subscribe/reconcile or replay covering the final
read`, with exact PR/head, refreshed pending evidence, owner and merge policy.
Finish independent authorized work; preserve resumable state rather than waiting
indefinitely. Recheck the live contract on future runs before declaring it fixed.

Read-only inspection of the installed server bundle confirms the boundary:
`thread.pull-request.watch` initializes `remarksThrough: startedAt`, and
`evaluatePullRequestWatch` discards remarks whose activity timestamp precedes
that boundary. PR #37's 14:00:59 submitted review is therefore invisible to a
14:01:29 subscription even when the reactor fetches it. Packaged application
bundles are inspection evidence, not an authored host repository to patch.

If the authorized host source repository is available, repair and test it there.
Otherwise hand this concrete repair to the T3 host maintainer:

- Registration must durably activate the watch before establishing its baseline;
  reconcile all current GitHub state, including **submitted reviews**, not just
  issue comments. Queue one durable reconciliation wake for the owning thread.
- Buffer/deliver changes during baseline collection, registration and active-turn
  shutdown. A wake arriving while the owner is busy must not be consumed and lost.
  Re-registering must not reset an existing delivery cursor or suppress a wake.
- Alternatively expose cursor acquisition plus replay subscription with the
  semantics above. Document the inputs, persisted boundary, delivery acknowledgement,
  deduplication, restart behaviour and how an active-turn wake is queued.
- Run deterministic barrier tests for the PR #37 schedule: last read 14:00:40,
  quota review 14:00:59, watch registration 14:01:29 UTC. Cover results before the
  read, between read/registration, during registration/reconciliation and after
  registration; include ordinary pending reviews resuming, head movement, failed
  reads and restart/active-turn delivery. No destructive or unrelated merges.

The helper tests exercise real classification and collection with simulated
GitHub transport; handoff tests model host interleavings. They are not evidence
that the installed T3 watcher implements either guarantee. Keep that limitation
in proof and delivery reports until the actual host integration passes.
