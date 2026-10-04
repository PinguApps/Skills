---
name: loop-work
description: Loop through a Linear team's project backlog, delegate independently actionable tickets to subagents in isolated worktrees using complete-work, merge verified PRs, and reassess until a stopping condition applies.
---

# Loop Work

Coordinate ticket delivery; delegate all implementation and PR repairs. Repeatedly select work that can be completed without user input, dispatch isolated workers, verify and merge their PRs, then reassess the backlog against the updated repository.

Invoking this workflow authorizes scoped Linear transitions to In Progress, worker commits/pushes/PRs and review replies through `complete-work`, and coordinator merges of verified PRs. Honour narrower instructions and repository restrictions. Deployment, releases, bypassing protections, and unrelated tracker mutations require separate authorization.

## 1. Resolve inputs and prerequisites

Recover inputs from the invocation and conversation. Ask once, in a bundled question, for missing or ambiguous required values before claiming tickets or starting workers. Accept natural-language equivalents of these parameter names.

| Parameter | Required value |
| --- | --- |
| `linear_team` | Unambiguous team name, ID, or URL. Resolve and retain its ID. |
| `linear_project` | Unambiguous project name, ID, or URL belonging to that team. Resolve and retain its ID. |
| `max_parallel_subagents` | Positive integer; maximum simultaneously live workers, including their nested subagents. The coordinator does not count. |
| `max_tickets` | Positive integer or explicitly `unlimited` / `no max`. Count distinct tickets completed by verified merges during this run, not starts, opened PRs, or failed attempts. |

Use the current repository unless another is explicitly supplied; ask if the team/project maps to multiple repositories or the intended checkout is unclear. Optional inputs are `ticket_filter` (issue IDs, labels, milestone, or cycle; default all open project issues) and `stop_at` (deadline with timezone; default none). Preserve any other explicit user constraints. Discover the default branch, remotes, workflow states, merge method, and repository checks; they are not mandatory user parameters. The branch prefix is fixed at `agent/`, never a parameter.

Read applicable `AGENTS.md` and repository requirements. Verify:

- Linear access can paginate the scope, read complete issues and dependency relations, and move selected issues to the team's In Progress state.
- The repository and base/head remotes are unambiguous; the default branch can be fetched; GitHub access supports PR inspection and permitted merges.
- `$complete-work` ([SKILL.md](../complete-work/SKILL.md)) and its required skills and tools are available to every worker.
- Delegation can actually run each worker in a distinct worktree and deliver completion/blocker events. Honour the host's orchestration rules; a shared-workspace child is insufficient. In T3, `delegate_task` inherits the caller's workspace; a prompt to change directory does not change its binding. Use a supported isolated-child mechanism or report this prerequisite missing. Do not substitute top-level conversations unless the user explicitly requested them.
- The project's GitHub–Linear integration links an issue to its PR and automatically moves it to In Review on PR creation and Done on merge. Verify configuration or recent correctly linked examples; naming alone is not proof. If this cannot be established, stop before dispatch and explain the missing workflow. Do not silently replace automation with extra status writes.

Before dispatch, give one concise intake summary: resolved scope, limits, eligible shortlist, first selections, and exclusions with reasons. Proceed within the resolved authorization without asking again.

## 2. Assess and prioritise the backlog

List every page of open issues using both resolved team and project IDs and the optional filter. Verify both IDs on results; exclude completed, cancelled, archived, and out-of-scope issues. Inspect dependencies, not just a blocked label or status. Read external dependency status only as needed to establish readiness; never claim or modify issues outside the selected scope.

For each plausible candidate, read the full description, acceptance criteria, comments, parent/sub-issue requirements, linked specifications, and requirement-bearing attachments. Inspect the relevant repository code, tests, configuration, and current fetched default branch. Record an assessment:

- **Eligible:** every requirement has an implementation and verification path using available code, tools, access, and settled decisions; no unresolved dependency remains.
- **Blocked:** a prerequisite is outstanding or unavailable. A cancelled dependency does not imply its requirement was fulfilled; confirm the dependency was satisfied or removed.
- **Needs input:** a material requirement, product/design choice, permission, secret, or required verification needs the user. Record the exact question; skip the issue rather than interviewing the user mid-loop.
- **Already covered / owned:** the work is already implemented, duplicated, or has an existing worker, branch, PR, or another person's active claim. Verify coverage instead of closing it manually; resume only work recorded as owned by this run, or explicitly handed over by the user.

Uncertain dependency status is a blocker. An open dependency implemented only in an unmerged PR is still outstanding. A ticket with subtasks is eligible only if its full scope is independently deliverable without duplicating those subtasks. A dependency cycle has no eligible starting point unless repository evidence shows an edge is already satisfied.

Maintain a compact run ledger in durable session state or a file outside the tracked repository: run ID, resolved inputs, completed issue IDs, assessments and reasons, and each reservation's issue ID, launch request ID, task ID, worktree, branch, base SHA, PR URL/head SHA, merge/queue intent, status, and attempt history. Persist dispatch and merge intent before the corresponding external action. On resume, reconcile it with live workers, GitHub, Linear, and worktrees before dispatching; a lost response is not a failed launch or merge.

Rank eligible tickets by explicit user ordering, then Linear priority and deadlines, then prerequisites that unlock useful work. Prefer independent coherent work over speculative foundations. Use stable issue order to break ties. Run overlapping files, shared migrations/contracts, or dependent changes serially when concurrent delivery would risk correctness or repeated conflicts; worktrees isolate filesystems, not integration.

## 3. Reserve and dispatch workers

For a finite ticket limit, enforce this invariant before every dispatch:

```text
completed tickets + outstanding ticket reservations <= max_tickets
```

A reservation remains outstanding through implementation, review, repair, and merge verification, even when its worker turn ends. Release it only after verified completion or a reconciled terminal blocker with no worker still mutating that ticket. `unlimited` removes this ticket-count gate, not concurrency or other stopping conditions. Use at most the requested concurrency and the environment's actual capacity; fewer workers are acceptable. Workers may delegate only with coordinator-allocated capacity that preserves the shared limit.

For each selection:

1. Re-fetch the issue and confirm scope, status, ownership, dependencies, and requirements still match its assessment. Check for an existing exact branch/PR and live task before creating anything. Skip another actor's claim; if a concurrent claim appears, halt this ticket's dispatch and reconcile it.
2. Fetch the current default branch. Derive the branch from Linear's branch suggestion: replace its leading owner namespace (for example `pingu/`) with `agent/`, preserve an existing `agent/` prefix, or prepend `agent/` to an unnamespaced suggestion. Preserve the issue-identifying suffix. If no suggestion exists, use `agent/<lowercase-issue-id>-<short-title-slug>`. Validate with `git check-ref-format --branch`. A collision requires ownership reconciliation, not an arbitrary new suffix or overwrite.
3. Reserve the ticket and a unique worktree based on the freshly fetched default-branch SHA. Arrange branch creation with the worker so `complete-work` uses this exact name and fresh base: a detached worktree can let the worker perform its own branch setup. Verify the worker's execution workspace and prevent writes in the coordinator's or another worker's checkout.
4. Persist the reservation and stable launch request ID before claiming or launching. Move only this issue to its resolved In Progress state and re-read it to verify the transition. Launch exactly one child with a self-contained brief using [the worker handoff](references/worker-handoff.md). Retain its task ID. Confirm launch acceptance; reconcile an uncertain response and reuse the same request ID for an idempotent retry when supported. Without idempotency, locate the original task or stop with an uncertain-launch blocker rather than creating a duplicate. If launch fails, record the issue left In Progress and the blocker; do not invent rollback transitions.

The coordinator owns selection, reservations, Linear state, and merging. Workers own implementation and PR readiness. Do not invoke `implement-task-linear` as a substitute: its tracker mutations exceed this workflow's status boundary.

## 4. Receive results and merge serially

A worker result must identify either a completed `complete-work` PR with evidence or a concrete blocker. A finished turn, opened PR, or queued CI job is not proof of readiness. Keep reservations for pending work; delegate repairs with the same issue, worktree, branch, and full accumulated context. Preserve `complete-work` / `finish-pr` convergence bounds across repair attempts rather than resetting them with a fresh worker. Retry a failed operation only after reconciling its outcome and identifying a recoverable cause; repeated unchanged failures become blockers.

Before each merge, independently re-fetch and verify:

- The issue still belongs to the selected scope and its requirements match the delivered work; the PR links the exact issue through the configured integration.
- The PR targets the intended repository/default branch and has the expected owned head, complete acceptance coverage, and recorded verification evidence.
- The PR is open, non-draft, conflict-free against the latest base, and permitted by branch protections. All applicable CI/checks on the exact current head are successful or legitimately skipped; none remain queued, pending, failed, cancelled, or unknown.
- `finish-pr`'s current-head review audit is satisfied, including applicable automated reviewer signals, submitted replies, and dispositions for all actionable feedback. Reviewers retain ownership of thread resolution. Unresolved threads are acceptable only when the audit and merge policy permit their recorded dispositions; never mark them resolved to force readiness.

Return stale or incomplete PRs to a worker. After another ticket merges, recompute readiness of remaining PRs against the new base; integrate and reverify when required. Merge one PR at a time using the repository's permitted method and an expected-head-SHA guard (for example `gh pr merge --match-head-commit <sha>`). Respect merge queues; queue admission or auto-merge configuration is pending work, not completion. Never use an admin bypass or merge a changed head without a new audit.

Verify GitHub reports the expected PR merged into the intended base before counting that issue once and releasing its reservation. Verify Linear's automated closure; allow bounded integration latency, then report a workflow blocker if it stays stale. Count the verified merge even when closure automation fails, and stop new dispatch rather than over-running the limit or manually closing the issue. Do not delete active or dirty worktrees; retain blocked work for handoff.

## 5. Reassess, wait, and stop

After each completion, blocker, meaningful scope change, or merge, refresh the scoped backlog and current default branch. Reconsider newly unblocked work and earlier exclusions whose evidence changed; do not blindly execute the initial shortlist or repeatedly retry unchanged blockers. Fill available capacity with the next eligible independent tickets.

When only active workers, CI, reviews, or queued merges can make progress, wait through the host's completion/event mechanism. Remain silent while waiting: no repeated status messages, busy polling, or duplicate watchers. For T3 asynchronous children, retain task IDs and yield the turn for completion delivery; use the host's PR watcher when applicable. A yielded turn is a wait, not a final stopping reason. Process the next real event and continue the run.

Stop new dispatch when:

- the finite completion limit is reached or all remaining ticket capacity is reserved;
- `stop_at` is reached or the user requests a stop;
- a shared prerequisite, integration, authorization, or ownership problem makes further work unsafe;
- no remaining candidate can be completed without user input.

Reserved capacity is a temporary dispatch gate: process its results and resume if failed reservations free capacity. With no eligible candidates but outstanding work, wait and reassess after it settles; the backlog may become actionable after a merge. For exhaustion or a shared blocker, finish and merge already accepted independent work only while its authorization and verification remain valid.

At a deadline or explicit user stop, stop new merge requests, withdraw this run's queued merges and disable its armed auto-merge requests where supported, and request workers and all live descendants to stop safely. Confirm cancellation and reconcile racing merges from GitHub; count any verified merge that won the race. Preserve commits, PRs, and worktrees. If a queue entry or task cannot be cancelled, report its live state and remaining effects explicitly. A terminal parent task with live descendants is still outstanding; never describe the loop as settled while any child or armed merge can still mutate it.

The run ends when its stopping reason is established and outstanding work is reconciled. Return a concise final ledger: stop reason, completed count versus limit, merged issue IDs/PR links, unmerged or interrupted work, blocked/skipped issues and exact missing inputs, and any Linear automation discrepancy. Ask only the questions necessary to unlock a subsequent run; this run does not wait indefinitely for new tickets or user decisions.
