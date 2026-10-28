# T3 thread control

Read before launching loop-work workers and again when recovering or stopping a run. Use the live T3 tool descriptions for argument schemas; harness prefixes may vary. These workers are ordinary top-level conversations, explicitly requested by this workflow, rather than native or app-owned subagents.

## Discover and bind

Read `orchestrator_capabilities`, `t3_thread_configuration`, `t3_project_read` and `t3_worktree_status`. If the initial tool catalog omits T3, make one bounded direct capabilities call before reporting it unavailable; servers may attach lazily. Retain the coordinator thread/project IDs; confirm the project's repository and setup scripts. Discover thread launch/list/read/send/wait/interrupt, queue list/cancel, pending-question and PR watch/unwatch tools. Use inherited provider/model/options and permission modes unless the user supplied a selection; no hardcoded model or assumed concurrency of three.

Launch one ticket per `t3_thread_launch`, with a unique title containing the loop run ID, issue ID and attempt marker. Put the complete [worker handoff](worker-handoff.md) in `message`. Select the workspace in the call:

```json
{
  "title": "Subagent <issue-id> loop:<run-id> A1",
  "projectId": "<verified-project-id>",
  "workspaceStrategy": {
    "type": "worktree",
    "baseRef": "<freshly-fetched-default-branch-sha>",
    "branch": "agent/<linear-branch-suffix>",
    "startFromOrigin": false
  },
  "message": "<self-contained ticket brief and reporting protocol>"
}
```

Fetch and resolve the SHA before this call. `startFromOrigin:false` uses that exact fetched local commit rather than another branch or an implicit origin fetch. A worker receives committed files at that base; coordinator edits and conversation history are not copied. An absolute skill path outside its checkout is usable only when the worker can access it.

T3 creates the branch/worktree and runs project setup before the agent starts. `preparing` is acceptance, not readiness. Persist the returned `threadId` and any `runId` immediately, then read the thread to verify project, branch and worktree binding. The worker verifies its actual directory, branch and initial HEAD before implementation and sends a workspace acknowledgement. Stop on a mismatch. Treat T3's branch creation as the branch-creation portion of `complete-work`: verify the fresh base, then complete its same-name remote publication and upstream checks. If the default branch advanced during preparation, refresh the still-clean branch to the new fetched base before implementation and include both original and updated SHAs in `STARTED`. The coordinator independently verifies the new default-branch SHA before updating its ledger. Preserve any unexpected changes and report a blocker instead of resetting them.

`create_threads` shares the caller's checkout; it cannot supply isolated workers. Omitting `workspaceStrategy` selects the project root, not the coordinator's current worktree. A shell `cd` or `git worktree add` in a prompt does not update T3's binding. `t3_worktree_handoff` moves the calling thread, not another thread. `delegate_task` can create isolated child tasks, but is not this workflow's ticket-worker launcher.

## Recover acceptance and preparation

`t3_thread_launch` has no idempotency key. Persist launch intent and its unique marker before calling it. After an error or lost response, paginate `t3_thread_list` in the verified project and inspect candidates with `t3_thread_read`: match the marker, issue, project and worktree/branch, not just a similar title. Adopt exactly one verified match and retain its IDs; reconcile multiple matches before further mutation. Retry only after establishing that no accepted launch exists. If that cannot be established, keep the reservation and report uncertain launch instead of duplicating work.

Follow preparation with bounded waits and reads. A preparation failure may leave a branch/worktree; reconcile these before another launch. Rate limits and setup failures reduce usable capacity; they do not justify filling native subagent slots or repeatedly relaunching. Retain failed work for handoff.

## Report and receive

Top-level worker completion does **not** automatically notify this coordinator as a delegated task would. Include the coordinator's exact thread ID and run/issue/attempt IDs in every brief. Require workers to:

- Send `STARTED` after workspace verification, including their thread/run IDs, worktree, branch and initial SHA.
- Before yielding for CI/review, send `WAITING` with the PR/head, pending condition, watcher and nested-task handles. Waiting retains the worker slot.
- Send `MERGED` only after GitHub confirms the worker-owned protected merge, and `READY` only for a completed audit under an explicit manual hold. Disarm worker PR watches, settle completed reviewers and remove mutating follow-ups before either report. Otherwise send `WAITING` or `BLOCKED` with the precise remaining condition.
- Use `t3_thread_send` to the coordinator with `mode:"queue"`, a stable `clientRequestId` for that report, and the run/issue/attempt IDs and result kind. Reuse the request ID on an uncertain retry. Keep the complete evidence in the worker's final answer too, so a failed notification can be recovered by reading its thread. A report-send failure must not discard completed work or cause a second PR.

On notification, match the report to the ledger's owned worker/attempt. Read the complete result, paginating and recovering truncated text. Deduplicate reports by run/issue/attempt/result ID. Late reports cannot restart stopped work. Verify GitHub merge state, current head and worker liveness independently. `READY` preserves a human hold; the coordinator never converts it into a merge. Record the durable outcome, then settle completed owned workers with no live/queued work.

For a worker question, inspect `t3_pending_request_list` and `t3_pending_request_read` in that worker thread. Answer through `t3_pending_request_respond` only from settled requirements and existing authorization. A material user decision becomes a ticket blocker; do not invent an answer or approve a permission request through the question API.

## Wait without losing the loop

When no coordinator work is actionable, use `t3_thread_wait` on the recorded active run IDs with bounded waits (at most 60 seconds, capped by `stop_at`). Independent waits can run together. A timeout leaves the worker running; a terminal status requires a result read. Reconcile other owned threads on each wake rather than waiting indefinitely on one slow ticket. Do not repeatedly wait on an already terminal run: a worker may have yielded while its PR watcher or nested task remains live.

Workers use T3's PR watcher for their own `finish-pr` waits and resume in their own threads. The coordinator does not add a duplicate watcher for the same wait. If yielding the coordinator turn, first ensure a durable wake-up covers both missed reports and crashed workers: a single run-scoped `schedule_task` interval bound to the coordinator can reconcile the ledger, with a structured `schedule` object and a stable creation request ID. Keep it limited to this run, report the returned cadence/next run, retain its handle and remove it when the run ends. Each wake reconciles existing work before dispatch; it does not start a new loop. Without a recovery wake-up, continue bounded waits instead of assuming top-level completion will resume the coordinator.

A recurring reconciliation interval is not an exact deadline timer. With `stop_at`, retain the main skill's deadline guarantee: cap active waits by the remaining time and use a reliable deadline wake-up before yielding across it. If no supported mechanism can enforce that, report the prerequisite blocker before dispatch. Check the deadline again on every notification and before dispatch/merge. A timer or worker event after the run has stopped is inert.

## Repair and resume

Keep one owned thread per ticket while usable. After reconciling its active run, queue and watch state, reserve worker capacity again if a prior ready handoff released it, then send a repair through `t3_thread_send` with a new stable `clientRequestId`. Use `mode:"auto"` to start an idle worker or steer an active one; use `queue` when a separate turn must follow current work. Record the returned run/message IDs. An accepted or steered message is not a completed repair. Preserve the original brief, accumulated findings and dispositions, exact PR/head and worktree, consumed review rounds and overall elapsed convergence budget.

If the thread cannot resume, first prove its original run, queued messages, nested tasks and watches cannot continue mutating the ticket. Launch a replacement with the same context and `workspaceStrategy:{"type":"existing_worktree","worktreePath":"<verified-absolute-path>","branch":"<owned-branch>"}`. Verify ownership and binding again; preserve uncommitted work. Never run two agents in that checkout or create a second PR for the same ticket. A new thread does not reset `finish-pr` limits. Independent delegated review rounds, if explicitly allocated, still use a fresh `delegate_task` per round under the host's rules; ticket repairs remain follow-ups in the owned worker thread.

## Stop and handoff

Top-level threads are not cancelled by stopping their coordinator. Mark the loop stopping in the ledger before external shutdown actions, and prevent further dispatch or merge requests.

For every owned worker, reconcile its latest run and queue, cancel this run's queued messages with `t3_queue_cancel`, and call `t3_thread_interrupt` for an active run using a stable request ID. Repeat reconciliation after interruption to catch a queued turn that began during shutdown. Remove this run's PR watches in both coordinator and worker threads with `unwatch_pull_request`, and withdraw queued/auto-merges as the main skill requires. For allocated nested tasks, reconcile the reported handles with thread activity and `t3_thread_list` including subagents; recover any descendant launched before its handle was reported. Parent-scoped `task_cancel` must run in the worker that owns that task: if needed, send that worker a cleanup-only turn to cancel its tasks and report state, with implementation and PR mutations explicitly forbidden. Reconcile that turn and descendants before declaring shutdown complete. Interrupt acceptance is not proof of termination; use waits/reads and verify no active/queued run, live nested work or armed watch can restart mutation. Preserve commits, dirty files and worktrees; report any uncancellable process or background operation.

Scope every action to the ledger's thread IDs and handles. Leave unrelated conversations, watches and schedules alone. Remove this run's reconciliation/deadline wake-ups once shutdown is reconciled. Settle only owned threads with no live work after their result is durably recorded; settling or archiving is not cancellation. Include `[worker title](t3-thread://v1/<exact-threadId>)` links in the final ledger for blocked or interrupted work, preserving the returned ID without URL encoding.
