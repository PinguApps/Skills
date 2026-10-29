---
name: loop-work
description: Coordinate a Linear backlog through isolated T3 workers using complete-work; workers review and merge their PRs, and the coordinator verifies outcomes and reassesses the backlog.
---

# Loop Work

Coordinate ticket delivery through T3 app-owned subagents: level 1 is this coordinator, level 2 is an isolated implementation worker, and level 3 is that worker's review-work reviewers. Use `delegate_task` for workers and reviewers so the hierarchy is visible inside the coordinator's thread. Select independently actionable work, verify worker-owned merges, then reassess the backlog against the updated repository. Workers own merging through `finish-pr`; the coordinator never submits merges.

Run this workflow only when the user has requested autonomous ticket delivery through verified PR merges using coordinator-controlled T3 subagents. An explicit invocation authorizes worker delegation, follow-up and cancellation, a run-scoped deadline wake-up when requested, scoped Linear In Progress/estimate writes, and worker commits, reviews, PRs and protected merges through `complete-work`. Loading this skill does not supply authorization; a request to inspect or plan a backlog is insufficient. Honour narrower instructions and repository restrictions. Propagate any human-review or no-merge hold to every worker; held PRs remain open. Deployment, releases, bypassing protections and unrelated tracker mutations require separate authorization.

Read and apply [$linear-ticket](../linear-ticket/SKILL.md) for estimate discovery and every authorized ticket update. Pass the verified team/project and this workflow's In Progress/estimate-only authority; the coordinator remains the sole tracker writer.

## 1. Resolve inputs and prerequisites

Recover inputs from the invocation and conversation. Ask once, in a bundled question, for missing or ambiguous required values before claiming tickets or starting workers. Accept natural-language equivalents of these parameter names.

| Parameter | Required value |
| --- | --- |
| `linear_team` | Unambiguous team name, ID, or URL. Resolve and retain its ID. |
| `linear_project` | Unambiguous project name, ID, or URL belonging to that team. Resolve and retain its ID. |
| `max_parallel_subagents` | Positive integer; maximum outstanding implementation workers, including preparation and review/CI waits. Nested reviewers are managed by each worker separately. |
| `max_tickets` | Positive integer or explicitly `unlimited` / `no max`. Count distinct tickets completed by verified merges during this run, not starts, opened PRs, or failed attempts. |

Accept `max_parallel_threads` as a compatibility alias for `max_parallel_subagents`, with the same implementation-worker limit; resolve conflicting values before dispatch. Use the current repository unless another is explicitly supplied; ask if the team/project maps to multiple repositories or the intended checkout is unclear. Optional inputs are `ticket_filter` (issue IDs, labels, milestone, or cycle; default all open project issues) and `stop_at` (deadline with timezone; default none). Preserve any other explicit user constraints. Discover the default branch, remotes, workflow states, merge method, and repository checks; they are not mandatory user parameters. The branch prefix is fixed at `agent/`, never a parameter.

Before dispatch, read [T3 subagent control](references/t3-threads.md) and discover the live tool schemas and capabilities. It defines worktree binding, result delivery, repair, recovery and shutdown. Require app-owned delegation with worktree isolation and nested delegation; report a missing prerequisite rather than substituting top-level threads or native agents. Inherit the coordinator's provider/model/options and modes unless the user chose others; resolve explicit selections through `orchestrator_capabilities`.

Read applicable `AGENTS.md` and repository requirements. Verify:

- Linear access can paginate the scope, read complete issues and dependency relations, and move selected issues to the team's In Progress state.
- The Linear connector exposes native issue estimate writes and read-back. Team-settings access and a complete scale are not prerequisites; use `linear-ticket`'s estimate procedure.
- The repository and base/head remotes are unambiguous; the default branch can be fetched; GitHub access supports PR inspection and permitted merges.
- `$complete-work` ([SKILL.md](../complete-work/SKILL.md)) and its required skills and tools are available to every worker.
- T3 can delegate each worker into a distinct worktree, deliver its completion, read and resume it, and cancel its task and descendants. Each worker can delegate review-work reviewers in its own checkout. Verify the T3 project matches the repository and inspect its worktree setup scripts before launching.
- The project's GitHub–Linear integration links an issue to its PR and automatically moves it to In Review on PR creation and Done on merge. Verify configuration or recent correctly linked examples; naming alone is not proof. If this cannot be established, stop before dispatch and explain the missing workflow. Do not silently replace automation with extra status writes.

When `stop_at` is supplied, resolve it to an absolute instant and arm a reliable host deadline wake-up before dispatch. Persist its handle in the run ledger and reconcile it on resume. If the host cannot enforce this wake-up, report a prerequisite blocker before starting workers. A deadline already reached enters the stop path immediately.

Before dispatch, give one concise intake summary: resolved scope, limits, eligible shortlist, first selections, and exclusions with reasons. Proceed within the resolved authorization without asking again.

## 2. Assess and prioritise the backlog

List every page of open issues using both resolved team and project IDs and the optional filter. Verify both IDs on results; exclude completed, cancelled, archived, and out-of-scope issues. Inspect dependencies, not just a blocked label or status. Read external dependency status only as needed to establish readiness; never claim or modify issues outside the selected scope.

For each plausible candidate, read the full description, acceptance criteria, comments, parent/sub-issue requirements, linked specifications, and requirement-bearing attachments. Inspect the relevant repository code, tests, configuration, and current fetched default branch. Record an assessment:

- **Eligible:** every requirement has an implementation and verification path using available code, tools, access, and settled decisions; no unresolved dependency remains.
- **Blocked:** a prerequisite is outstanding or unavailable. A cancelled dependency does not imply its requirement was fulfilled; confirm the dependency was satisfied or removed.
- **Needs input:** a material requirement, product/design choice, permission, secret, or required verification needs the user. Record the exact question; skip the issue rather than interviewing the user mid-loop.
- **Already covered / owned:** the work is already implemented, duplicated, or has an existing worker, branch, PR, or another person's active claim. Verify coverage instead of closing it manually; resume only work recorded as owned by this run, or explicitly handed over by the user.

Uncertain dependency status is a blocker. An open dependency implemented only in an unmerged PR is still outstanding. A ticket with subtasks is eligible only if its full scope is independently deliverable without duplicating those subtasks. A dependency cycle has no eligible starting point unless repository evidence shows an edge is already satisfied.

Maintain a compact run ledger in durable session state or a file outside the tracked repository: run ID, coordinator thread/project IDs, resolved inputs, completed issue IDs, assessments and reasons, and each reservation's issue ID, unique launch marker/title, delegate request/task ID, child thread/run IDs, follow-up task IDs, read cursor, worktree, branch, base SHA, PR URL/head SHA, merge/queue intent, status, nested-task handles and attempt history. Persist dispatch and merge intent before the corresponding external action. On resume, reconcile it with live tasks, GitHub, Linear, and worktrees before dispatching; a lost response is not a failed launch or merge.

Rank eligible tickets by explicit user ordering, then Linear priority and deadlines, then prerequisites that unlock useful work. Prefer independent coherent work over speculative foundations. Use stable issue order to break ties; when titles are numbered, interpret them using [Linear milestone and issue numbering](../linear-ticket/references/issue-numbering.md), comparing milestone number before issue number. Preserve names and titles during delivery; numbering does not create dependencies or milestone gates. Run overlapping files, shared migrations/contracts, or dependent changes serially when concurrent delivery would risk correctness or repeated conflicts; worktrees isolate filesystems, not integration.

## 3. Reserve and dispatch workers

For a finite ticket limit, enforce this invariant before every dispatch:

```text
completed tickets + outstanding ticket reservations <= max_tickets
```

A reservation remains outstanding through implementation, review, repair and merge verification, even when its worker turn ends. Release it only after verified completion or a reconciled terminal blocker with no worker still mutating that ticket. `unlimited` removes the ticket-count gate, not concurrency limits. Reserve a worker place before launch; uncertain acceptance still occupies it. Count preparation and CI/review waits until verified handoff. Keep the ticket reservation for a manual-hold PR. Use at most `max_parallel_subagents` implementation workers and respect actual provider/machine limits. Each worker independently runs the mandatory review-work reviewers as its children; a worker limit of one supports that full hierarchy.

Use `linear-ticket`'s full-scope estimate assessment and native write procedure for each selected ticket, including its fallback scale and error handling. Record its estimate, rationale, assumptions or specific failure in the run ledger. Insufficient scope for honest sizing makes the ticket Needs input; skip it.

For each selection:

1. Re-fetch the issue and confirm scope, status, ownership, dependencies, and requirements still match its assessment. Check for an existing exact branch/PR and live worker thread before creating anything. Skip another actor's claim; if a concurrent claim appears, halt this ticket's dispatch and reconcile it.
2. Fetch the current default branch. Derive the branch from Linear's branch suggestion: replace its leading owner namespace (for example `pingu/`) with `agent/`, preserve an existing `agent/` prefix, or prepend `agent/` to an unnamespaced suggestion. Preserve the issue-identifying suffix. If no suggestion exists, use `agent/<lowercase-issue-id>-<short-title-slug>`. Validate with `git check-ref-format --branch`. A collision requires ownership reconciliation, not an arbitrary new suffix or overwrite.
3. Reserve the ticket and exact branch for an isolated T3 child using `delegate_task`, role `implementation`, `isolation:"worktree"`, following [T3 subagent control](references/t3-threads.md). T3 starts from the coordinator's committed HEAD; supply the freshly fetched default-branch SHA and desired branch so the worker can align its clean T3-created branch before implementation. It continues in that assigned checkout under `complete-work`, verifies the fresh base and completes remote publication/tracking. Preserve the coordinator's and other workers' checkouts.
4. Persist the reservation, stable delegate request ID and unique marker before claiming or launching. Through `linear-ticket`, move only this issue to its resolved In Progress state and apply the assessed native estimate. Verify the claim before dispatch; record any separate estimate failure using its recovery rules. Delegate exactly one child with a self-contained [worker handoff](references/worker-handoff.md). Retain its task, child thread and run IDs. Reconcile uncertain acceptance using the same request ID and owned child metadata before retrying; a lost response never authorizes a duplicate. If launch fails, record the issue left In Progress and the blocker; do not invent rollback transitions.

The coordinator owns selection, reservations, Linear state, estimates and capacity. Workers own implementation, reviewer cleanup, PR readiness and permitted merges. Do not invoke `implement-task-linear` as a substitute: its tracker mutations exceed this workflow's status and estimate boundary.

## 4. Receive results and verify worker-owned merges

A worker result must identify either a completed `complete-work` PR with evidence, a pending CI/review condition, or a concrete blocker. On completion delivery, read the full result and task state; a notification is a wake-up, not a readiness verdict. Verify its description follows [create-pr's user story rules](../create-pr/SKILL.md), including a brief story in everyday language that readers without a technical background can understand. A finished turn, opened PR, or queued CI job is not proof of readiness. Keep reservations for pending work; resume the same child for implementation/PR repairs with the issue, worktree, branch and accumulated context. Preserve convergence bounds across attempts. Retry only after reconciling the outcome and finding a recoverable cause; unchanged repeated failures become blockers.

For a `MERGED` result, independently re-fetch and verify:

- The issue still belongs to the selected scope and its requirements match the delivered work; the PR links the exact issue through the configured integration and its saved title follows [create-pr's Linear ticket title-prefix rule](../create-pr/SKILL.md).
- The PR targets the intended repository/default branch and has the expected owned head, complete acceptance coverage, and recorded verification evidence.
- The worker supplied its `finish-pr` current-head audit, merge method, final head and merged commit; GitHub reports `MERGED` into the intended base. Queue admission is not a merge.
- The pre-PR coverage receipt and per-round usage are in the PR; CI, feedback, quota exemptions and any narrowly permitted Copilot thread settlements are documented. Never require retired PR Agent approval.
- No live reviewer or queued repair remains. Register the PR in the coordinator thread as well as the worker thread when host linking is available; remove the coordinator's completed PR watch.

Return stale or incomplete PRs to their worker; never merge them from the coordinator. Workers fetch the latest base and obey `finish-pr`'s protected expected-head merge gate. Serialize overlapping work and use repository merge queues where required. A `READY` report is valid only for a propagated manual hold and means open, verified, unmerged work; do not count it as completed or ask a worker to override the hold. An unexplained ready-but-unmerged handoff needs worker follow-up. After a verified merge, reassess remaining work against the new base.

Verify GitHub reports the expected PR merged into the intended base before counting that issue once and releasing its reservation. Verify Linear's automated closure; allow bounded integration latency, then report a workflow blocker if it stays stale. Count the verified merge even when closure automation fails, and stop new dispatch rather than over-running the limit or manually closing the issue. Do not delete active or dirty worktrees; retain blocked work for handoff.

## 5. Reassess, wait, and stop

After each completion, blocker, meaningful scope change, or merge, refresh the scoped backlog and current default branch. Reconsider newly unblocked work and earlier exclusions whose evidence changed; do not blindly execute the initial shortlist or repeatedly retry unchanged blockers. Fill available capacity with the next eligible independent tickets.

When only active workers, CI, reviews, or queued merges can make progress, follow the delegate's returned `next` and [T3's event procedure](references/t3-threads.md#receive-and-resume). Completion wakes the parent; do not poll running tasks or add recurring recovery schedules. For a worker's CI/review wait, the coordinator follows finish-pr's [watch handoff](../finish-pr/references/watch-handoff.md); delegated workers never watch PRs. With `stop_at`, keep the reliable deadline wake-up armed across yielded turns. Worker/PR events alone cannot enforce a deadline. Check the deadline on every wake and before dispatch or merge. A yielded turn is a wait; process the next real event and continue the run.

Stop new dispatch when:

- the finite completion limit is reached or all remaining ticket capacity is reserved;
- `stop_at` is reached or the user requests a stop;
- a shared prerequisite, integration, authorization, or ownership problem makes further work unsafe;
- no remaining candidate can be completed without user input.

Reserved capacity is a temporary dispatch gate: process results and resume if failed reservations free capacity. With no eligible candidates but outstanding work, wait and reassess after it settles. For exhaustion or a shared blocker, let accepted independent workers finish only while their authorization and verification remain valid. Manual-hold PRs require a handoff rather than an indefinite wait for a human merge.

At a deadline or explicit user stop, mark the loop stopping, cancel owned worker tasks and descendants through [T3's shutdown procedure](references/t3-threads.md#stop-and-handoff), withdraw queued/auto-merges where supported, and remove coordinator PR watches. Reconcile racing merges from GitHub; count any verified merge that won the race. Preserve commits, PRs, and worktrees. If a task, process or queue entry cannot be stopped, report its live state and remaining effects explicitly. A terminal worker turn with live descendants or armed follow-ups is still outstanding; never describe the loop as settled while any worker or armed merge can still mutate it.

The run ends when its stopping reason is established and outstanding work is reconciled; remove this run's remaining wake-ups then. Return a concise final ledger: stop reason, completed count versus limit, merged issue IDs/PR links, unmerged or interrupted work with worker thread links, blocked/skipped issues and exact missing inputs, and any Linear automation discrepancy. Ask only the questions necessary to unlock a subsequent run; this run does not wait indefinitely for new tickets or user decisions.
