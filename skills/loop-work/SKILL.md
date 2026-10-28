---
name: loop-work
description: Coordinate a Linear backlog through isolated T3 workers using complete-work; workers review and merge their PRs, and the coordinator verifies outcomes and reassesses the backlog.
---

# Loop Work

Coordinate ticket delivery; run implementation, pre-PR reviews and PR completion in separate T3 worker threads. Select independently actionable work, launch isolated workers, verify their completed merges, then reassess the backlog against the updated repository. Workers own merging through `finish-pr`; the coordinator never submits merges. Worker concurrency is controlled by this loop rather than Codex's native subagent slots.

Run this workflow only when the user has requested autonomous ticket delivery through verified PR merges using coordinator-controlled T3 threads. An explicit invocation selects that execution mode and authorizes worker launch, follow-up and interruption, temporary run-scoped recovery wake-ups, scoped Linear In Progress/estimate writes, and worker commits, reviews, PRs and protected merges through `complete-work`. Loading this skill does not supply authorization; a request to inspect or plan a backlog is insufficient. Honour narrower instructions and repository restrictions. Propagate any human-review or no-merge hold to every worker; held PRs remain open. Deployment, releases, bypassing protections and unrelated tracker mutations require separate authorization.

Read and apply [$linear-ticket](../linear-ticket/SKILL.md) for estimate discovery and every authorized ticket update. Pass the verified team/project and this workflow's In Progress/estimate-only authority; the coordinator remains the sole tracker writer.

## 1. Resolve inputs and prerequisites

Recover inputs from the invocation and conversation. Ask once, in a bundled question, for missing or ambiguous required values before claiming tickets or starting workers. Accept natural-language equivalents of these parameter names.

| Parameter | Required value |
| --- | --- |
| `linear_team` | Unambiguous team name, ID, or URL. Resolve and retain its ID. |
| `linear_project` | Unambiguous project name, ID, or URL belonging to that team. Resolve and retain its ID. |
| `max_parallel_threads` | Positive integer; maximum simultaneously live worker threads plus any allocated nested agents. The coordinator does not count. |
| `max_tickets` | Positive integer or explicitly `unlimited` / `no max`. Count distinct tickets completed by verified merges during this run, not starts, opened PRs, or failed attempts. |

Accept `max_parallel_subagents` as a legacy alias for `max_parallel_threads` with the same shared worker/nested-agent budget; resolve conflicting values before dispatch. Use the current repository unless another is explicitly supplied; ask if the team/project maps to multiple repositories or the intended checkout is unclear. Optional inputs are `ticket_filter` (issue IDs, labels, milestone, or cycle; default all open project issues) and `stop_at` (deadline with timezone; default none). Preserve any other explicit user constraints. Discover the default branch, remotes, workflow states, merge method, and repository checks; they are not mandatory user parameters. The branch prefix is fixed at `agent/`, never a parameter.

Before dispatch, read [T3 thread control](references/t3-threads.md) and discover the live tool schemas and capabilities. It defines worktree binding, result delivery, repair, recovery and shutdown for this workflow. Require T3's thread lifecycle tools; report a missing prerequisite rather than falling back to native subagents or shared-checkout thread batches. Inherit the coordinator's provider/model/options and modes unless the user chose others; resolve explicit selections through `orchestrator_capabilities`.

Read applicable `AGENTS.md` and repository requirements. Verify:

- Linear access can paginate the scope, read complete issues and dependency relations, and move selected issues to the team's In Progress state.
- The Linear connector exposes native issue estimate writes and read-back. Team-settings access and a complete scale are not prerequisites; use `linear-ticket`'s estimate procedure.
- The repository and base/head remotes are unambiguous; the default branch can be fetched; GitHub access supports PR inspection and permitted merges.
- `$complete-work` ([SKILL.md](../complete-work/SKILL.md)) and its required skills and tools are available to every worker.
- T3 can launch each worker already bound to a distinct worktree, read and message it, wait for its runs, and interrupt it. Workers can report to the coordinator through `t3_thread_send`; run failures can be recovered through bounded waits and reads. Verify the T3 project matches the repository and inspect its worktree setup scripts before launching.
- The project's GitHub–Linear integration links an issue to its PR and automatically moves it to In Review on PR creation and Done on merge. Verify configuration or recent correctly linked examples; naming alone is not proof. If this cannot be established, stop before dispatch and explain the missing workflow. Do not silently replace automation with extra status writes.

When `stop_at` is supplied, resolve it to an absolute instant and arm a reliable host deadline wake-up before dispatch, or use an event wait whose timeout expires no later than that instant. Persist any wake-up handle in the run ledger and reconcile it on resume. If the host cannot enforce this wake-up, report a prerequisite blocker before starting workers. A deadline already reached enters the stop path immediately.

Before dispatch, give one concise intake summary: resolved scope, limits, eligible shortlist, first selections, and exclusions with reasons. Proceed within the resolved authorization without asking again.

## 2. Assess and prioritise the backlog

List every page of open issues using both resolved team and project IDs and the optional filter. Verify both IDs on results; exclude completed, cancelled, archived, and out-of-scope issues. Inspect dependencies, not just a blocked label or status. Read external dependency status only as needed to establish readiness; never claim or modify issues outside the selected scope.

For each plausible candidate, read the full description, acceptance criteria, comments, parent/sub-issue requirements, linked specifications, and requirement-bearing attachments. Inspect the relevant repository code, tests, configuration, and current fetched default branch. Record an assessment:

- **Eligible:** every requirement has an implementation and verification path using available code, tools, access, and settled decisions; no unresolved dependency remains.
- **Blocked:** a prerequisite is outstanding or unavailable. A cancelled dependency does not imply its requirement was fulfilled; confirm the dependency was satisfied or removed.
- **Needs input:** a material requirement, product/design choice, permission, secret, or required verification needs the user. Record the exact question; skip the issue rather than interviewing the user mid-loop.
- **Already covered / owned:** the work is already implemented, duplicated, or has an existing worker, branch, PR, or another person's active claim. Verify coverage instead of closing it manually; resume only work recorded as owned by this run, or explicitly handed over by the user.

Uncertain dependency status is a blocker. An open dependency implemented only in an unmerged PR is still outstanding. A ticket with subtasks is eligible only if its full scope is independently deliverable without duplicating those subtasks. A dependency cycle has no eligible starting point unless repository evidence shows an edge is already satisfied.

Maintain a compact run ledger in durable session state or a file outside the tracked repository: run ID, coordinator thread/project IDs, resolved inputs, completed issue IDs, assessments and reasons, and each reservation's issue ID, unique launch marker/title, worker thread ID, run IDs, message request IDs, read cursor, worktree, branch, base SHA, PR URL/head SHA, merge/queue intent, status, nested-task handles and attempt history. Persist dispatch and merge intent before the corresponding external action. On resume, reconcile it with live threads, GitHub, Linear, and worktrees before dispatching; a lost response is not a failed launch or merge.

Rank eligible tickets by explicit user ordering, then Linear priority and deadlines, then prerequisites that unlock useful work. Prefer independent coherent work over speculative foundations. Use stable issue order to break ties; when titles are numbered, interpret them using [Linear milestone and issue numbering](../linear-ticket/references/issue-numbering.md), comparing milestone number before issue number. Preserve names and titles during delivery; numbering does not create dependencies or milestone gates. Run overlapping files, shared migrations/contracts, or dependent changes serially when concurrent delivery would risk correctness or repeated conflicts; worktrees isolate filesystems, not integration.

## 3. Reserve and dispatch workers

For a finite ticket limit, enforce this invariant before every dispatch:

```text
completed tickets + outstanding ticket reservations <= max_tickets
```

A reservation remains outstanding through implementation, review, repair and merge verification, even when its worker turn ends. Release it only after verified completion or a reconciled terminal blocker with no worker still mutating that ticket. `unlimited` removes the ticket-count gate, not concurrency limits. Reserve a worker slot before launch; uncertain acceptance still occupies it. Count preparation and CI/review waits until verified handoff. Keep the ticket reservation for a manual-hold PR. Use at most `max_parallel_threads` and actual provider/machine capacity. Workers may delegate only within coordinator-allocated capacity. Reserve capacity for the mandatory pre-PR reviewer pair: serialize reviews if needed, or pause other workers while granting slots. A limit of one cannot run a worker and its reviewer concurrently; report that prerequisite before dispatch rather than skipping review or silently exceeding the limit. Workers request additional capacity before escalating; grants and releases are recorded in the ledger.

Use `linear-ticket`'s full-scope estimate assessment and native write procedure for each selected ticket, including its fallback scale and error handling. Record its estimate, rationale, assumptions or specific failure in the run ledger. Insufficient scope for honest sizing makes the ticket Needs input; skip it.

For each selection:

Keep at least one slot free from ticket workers while an accepted ticket still
needs pre-PR review. Before each launch, check projected worker plus allocated
reviewer capacity against the limit. Use that reserved slot for serial independent
reviews, granting a second reviewer slot only when capacity permits. Do not fill
all slots with workers and then wait for review capacity that cannot become free.

1. Re-fetch the issue and confirm scope, status, ownership, dependencies, and requirements still match its assessment. Check for an existing exact branch/PR and live worker thread before creating anything. Skip another actor's claim; if a concurrent claim appears, halt this ticket's dispatch and reconcile it.
2. Fetch the current default branch. Derive the branch from Linear's branch suggestion: replace its leading owner namespace (for example `pingu/`) with `agent/`, preserve an existing `agent/` prefix, or prepend `agent/` to an unnamespaced suggestion. Preserve the issue-identifying suffix. If no suggestion exists, use `agent/<lowercase-issue-id>-<short-title-slug>`. Validate with `git check-ref-format --branch`. A collision requires ownership reconciliation, not an arbitrary new suffix or overwrite.
3. Reserve the ticket and exact branch for a new T3 worktree based on the freshly fetched default-branch SHA. Have `t3_thread_launch` create and bind the worktree before execution, following [T3 thread control](references/t3-threads.md). Supply the precreated branch to `complete-work`; the worker verifies its fresh base and completes remote publication/tracking without creating another branch. Confirm the T3 workspace binding and require the worker to verify its checkout before implementation; preserve the coordinator's and other workers' checkouts.
4. Persist the reservation and unique launch marker before claiming or launching. Through `linear-ticket`, move only this issue to its resolved In Progress state and apply the assessed native estimate. Verify the claim before dispatch; record any separate estimate failure using its recovery rules. Launch exactly one T3 thread with a self-contained brief using [the worker handoff](references/worker-handoff.md). Retain its thread ID and run ID, and follow preparation through the first workspace acknowledgement. `t3_thread_launch` has no idempotency key: reconcile uncertain acceptance by listing and reading matching threads before any retry. If launch fails, record the issue left In Progress and the blocker; do not invent rollback transitions.

The coordinator owns selection, reservations, Linear state, estimates and capacity. Workers own implementation, reviewer cleanup, PR readiness and permitted merges. Do not invoke `implement-task-linear` as a substitute: its tracker mutations exceed this workflow's status and estimate boundary.

## 4. Receive results and verify worker-owned merges

A worker result must identify either a completed `complete-work` PR with evidence or a concrete blocker. Read the full result from its thread; a notification is a wake-up, not a readiness verdict. Verify its description follows [create-pr's user story rules](../create-pr/SKILL.md), including a brief story in everyday language that readers without a technical background can understand. A finished turn, opened PR, or queued CI job is not proof of readiness. For WAITING capacity requests, reconcile live worker/reviewer handles, grant only genuinely free slots and retain the grant until cleanup is confirmed; prioritize review completion over new dispatch to avoid capacity deadlock. Keep reservations for pending work; send repair follow-ups to the same owned worker with the issue, worktree, branch and accumulated context. Preserve convergence bounds across attempts. Retry only after reconciling the outcome and finding a recoverable cause; unchanged repeated failures become blockers.

For a `MERGED` result, independently re-fetch and verify:

- The issue still belongs to the selected scope and its requirements match the delivered work; the PR links the exact issue through the configured integration and its saved title follows [create-pr's Linear ticket title-prefix rule](../create-pr/SKILL.md).
- The PR targets the intended repository/default branch and has the expected owned head, complete acceptance coverage, and recorded verification evidence.
- The worker supplied its `finish-pr` current-head audit, merge method, final head and merged commit; GitHub reports `MERGED` into the intended base. Queue admission is not a merge.
- The pre-PR coverage receipt and per-round usage are in the PR; CI, feedback, quota exemptions and any narrowly permitted Copilot thread settlements are documented. Never require retired PR Agent approval.
- No live reviewer, queued repair or worker watch remains. Register the PR in the coordinator thread as well as the worker thread when host linking is available.

Return stale or incomplete PRs to their worker; never merge them from the coordinator. Workers fetch the latest base and obey `finish-pr`'s protected expected-head merge gate. Serialize overlapping work and use repository merge queues where required. A `READY` report is valid only for a propagated manual hold and means open, verified, unmerged work; do not count it as completed or ask a worker to override the hold. An unexplained ready-but-unmerged handoff needs worker follow-up. After a verified merge, reassess remaining work against the new base.

Verify GitHub reports the expected PR merged into the intended base before counting that issue once and releasing its reservation. Verify Linear's automated closure; allow bounded integration latency, then report a workflow blocker if it stays stale. Count the verified merge even when closure automation fails, and stop new dispatch rather than over-running the limit or manually closing the issue. Do not delete active or dirty worktrees; retain blocked work for handoff.

## 5. Reassess, wait, and stop

After each completion, blocker, meaningful scope change, or merge, refresh the scoped backlog and current default branch. Reconsider newly unblocked work and earlier exclusions whose evidence changed; do not blindly execute the initial shortlist or repeatedly retry unchanged blockers. Fill available capacity with the next eligible independent tickets.

When only active workers, CI, reviews, or queued merges can make progress, use the bounded wait and notification procedure in [T3 thread control](references/t3-threads.md). Top-level threads have no automatic child-task completion delivery; retain their run IDs and recover failures or missed reports through thread reads. Remain silent during waits: no repeated status messages, busy polling, or duplicate PR watchers. With `stop_at`, keep the deadline wake-up armed across yielded turns or cap every event wait by the remaining time; worker/PR events alone cannot enforce a deadline. Treat expiry as a stop event even when no worker finishes or check changes. Check the clock before every dispatch and merge request. A yielded turn is a wait, not a final stopping reason. Process the next real event and continue the run.

Stop new dispatch when:

- the finite completion limit is reached or all remaining ticket capacity is reserved;
- `stop_at` is reached or the user requests a stop;
- a shared prerequisite, integration, authorization, or ownership problem makes further work unsafe;
- no remaining candidate can be completed without user input.

Reserved capacity is a temporary dispatch gate: process results and resume if failed reservations free capacity. With no eligible candidates but outstanding work, wait and reassess after it settles. For exhaustion or a shared blocker, let accepted independent workers finish only while their authorization and verification remain valid. Manual-hold PRs require a handoff rather than an indefinite wait for a human merge.

At a deadline or explicit user stop, direct each owned worker to stop new merge requests, withdraw its queued merges and disable its armed auto-merge requests where supported, then stop that worker through [T3's shutdown procedure](references/t3-threads.md#stop-and-handoff). Top-level worker threads are independent: interrupting the coordinator does not cancel them. Confirm interruption, cancel queued follow-ups and nested tasks, remove PR watches, and reconcile racing merges from GitHub; count any verified merge that won the race. Preserve commits, PRs, and worktrees. If a queue entry, thread or task cannot be stopped, report its live state and remaining effects explicitly. A terminal worker turn with live descendants or armed follow-ups is still outstanding; never describe the loop as settled while any worker or armed merge can still mutate it.

The run ends when its stopping reason is established and outstanding work is reconciled; remove this run's remaining wake-ups then. Return a concise final ledger: stop reason, completed count versus limit, merged issue IDs/PR links, unmerged or interrupted work with worker thread links, blocked/skipped issues and exact missing inputs, and any Linear automation discrepancy. Ask only the questions necessary to unlock a subsequent run; this run does not wait indefinitely for new tickets or user decisions.
