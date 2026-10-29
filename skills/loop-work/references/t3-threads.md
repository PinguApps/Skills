# T3 subagent control

Read before launching loop-work workers and when recovering or stopping a run.
Use live tool schemas; prefixes may vary. Workers are app-owned child agents of
this coordinator, and their review-work reviewers are children of those workers.

## Discover and bind

Call `orchestrator_capabilities` once before the first delegation. Require
app-owned subagents, worktree isolation, nested delegation, task cancellation and
completion delivery. Discover `delegate_task`, `task_status`, `task_cancel`,
thread read/list/send/organize, pending-request and PR link/watch/unwatch tools.
If T3 is missing from the catalog, try capabilities once before reporting it
unavailable. Verify the current project/repository and inspect worktree setup
scripts. Inherit provider/model/options and modes unless the user selected others.

Use one `delegate_task` per new ticket worker:

```json
{
  "clientRequestId": "<stable-run-issue-attempt-request-id>",
  "title": "Implement <issue-id>: <short-title> loop:<run-id> A1",
  "role": "implementation",
  "isolation": "worktree",
  "mode": "async",
  "task": "<complete self-contained worker handoff>"
}
```

T3 creates and binds a separate checkout before the child starts. Do not create
its worktree in a shell or use top-level thread launch/batch tools. The child gets
committed files at the coordinator's HEAD, not uncommitted edits or conversation
history. `delegate_task` has no base/branch parameters: pass the fetched default
branch SHA and desired `agent/...` branch in the brief. Inside that T3-created
checkout, the worker verifies ownership and a clean initial state, aligns only
its new branch/name with the freshly fetched default branch, and verifies HEAD
before editing. It must preserve unexpected work and stop on a mismatch. This
satisfies complete-work's local branch/base setup without making another checkout;
then the worker completes remote publication and upstream checks.

Persist dispatch intent and `clientRequestId` before launch, then retain returned
`taskId`, `childThreadId`, `childRunId` and link. Verify thread metadata shows
`relationshipToParent:"subagent"`, the expected coordinator parent and a distinct
worktree; the worker verifies the actual shell path, branch and base too. Its
reviewers use `delegate_task`, role `review`, shared isolation in that same worker
checkout, with review-work's model assignments and independent briefs. A worker
limit of one can run the full coordinator → worker → reviewers hierarchy.

## Acceptance and recovery

Follow the returned `next`. Async completion wakes the coordinator; end the turn
when no independent work remains. Never poll running tasks with status calls,
thread waits, sleeps, monitor jobs or recurring schedules. Once completion or a
question wakes the parent, read `task_status` and the complete child result,
paginating thread reads when necessary. A finished turn with pending child work
is still outstanding.

After an uncertain dispatch response, reconcile the stable request ID and owned
children using thread metadata, title/brief marker, repository and worktree.
Retry only with the same request identity after establishing what was accepted;
never create a duplicate ticket worker. Preparation failures may leave a worktree
or branch: preserve and reconcile them before retrying. Unsupported provider or
nested-delegation settings are blockers, not permission to substitute top-level
threads or another provider.

## Receive and resume

Workers return STARTED/workspace details with their result, then one of MERGED,
READY under a manual hold, WAITING with the exact PR/head and pending condition,
or BLOCKED with the specific gap. Completion is delivered automatically; no
separate report message is required. Deduplicate by run/issue/attempt/task ID and
verify GitHub and worker liveness independently before updating the ledger.

Delegated workers never watch PRs. When a worker yields WAITING for CI, incoming
reviews or a queued merge, first finish any actionable coordinator work. Then
link/watch the PR from the coordinator and end the turn. On the host's next PR
event, inspect readiness and resume the same implementation child using
`t3_thread_send` with a stable request ID and full remaining context. Retain the
new task ID returned for that child continuation. Keep any needed watch across
wakes; remove it when the PR is done or before final handoff. The worker still
owns finish-pr fixes, replies and the protected merge; the coordinator never
merges on its behalf.

For implementation/PR repair, reconcile the child's tasks and queue before
sending another turn to that same child. Include original requirements, exact
worktree/branch/PR/head, evidence, findings, attempts and consumed convergence
budget. A continuation does not reset review caps or finish-pr limits. Review
rechecks always use a fresh `delegate_task` under review-work; never send a review
recheck to an old reviewer. If an implementation child cannot resume, cancel its
tasks/descendants and verify it cannot mutate before handing off the preserved
checkout. Do not start a fresh worktree or second PR as an implicit recovery.

For questions, inspect the child's pending request. Answer only from settled
requirements and existing authorization; permission requests are not ordinary
questions. Material user decisions become ticket blockers. Preserve the reservation
while descendants, pending repairs or merge intents remain live.

With `stop_at`, establish a reliable host deadline wake-up before dispatch and
retain its handle. Completion events do not enforce a deadline. On every wake,
check the deadline before more work; remove the owned deadline wake-up when the
run ends. No deadline mechanism means a prerequisite blocker for a timed run.

## Stop and handoff

Mark the loop stopping before cancellation or other shutdown actions. Use
`task_cancel` on every owned worker task and continuation task ID; it cancels the
child's running/queued turns and descendants. Do not use `t3_thread_interrupt`
on a delegated child. Reconcile terminal state and descendant/queue metadata;
cancellation acceptance alone is not proof that background processes stopped.
Remove this run's coordinator PR watches, withdraw owned queued/auto-merges and
reconcile racing merges from GitHub. Preserve commits, dirty files and worktrees.
Report any remaining process, resource or mutation path that cannot be stopped.

Read and save final results before settling completed owned children through
`t3_thread_organize`. Settling is not cancellation. Scope all cleanup to the
ledger's task/thread/PR/deadline handles and leave unrelated work alone. Final
handoff includes returned worker links verbatim (or the exact thread ID in a
`t3-thread://v1/` link), PRs, verification evidence and resumable blockers.
