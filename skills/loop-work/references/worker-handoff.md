# Worker handoff

Read when launching or repairing a ticket. Supply actual values and requirement text, not an unresolved template or just a ticket title. A top-level T3 worker does not inherit the coordinator's conversation, so include everything it needs to establish scope and act independently. Select its isolated workspace in the launch call using [T3 thread control](t3-threads.md).

```text
Complete this one ticket using $complete-work at <resolved skill path>.
Follow its required skills through verified implementation, PR creation, CI,
and finish-pr review convergence. You own the protected merge unless the supplied
merge policy is manual. The coordinator verifies outcomes and never merges for you.
Follow create-pr's Linear ticket title-prefix rule, carrying the supplied issue
identifier and any other qualifying tickets into PR creation or reuse.
Follow create-pr's user story rules for the PR description: require a brief story
in everyday language that readers without a technical background can understand,
adapting any original wording as needed.

Execution:
- Run/issue: <run ID; issue ID and URL; exact team/project IDs>.
- Coordinator: <exact T3 thread ID; project ID; attempt/result identifiers>.
- Repository/worktree: <repository identity; T3-created worktree to resolve and
  verify through t3_worktree_status, or exact owned path on resume>.
- Base: <base repository, remote, default branch, freshly fetched SHA>.
- Head: <head repository, push remote, exact agent/... branch>.
- Branch setup: T3 has created the supplied branch from the supplied fresh SHA.
  Verify this satisfies complete-work's local branch/base setup, then finish its
  same-name remote publication and upstream checks. Continue the owned branch
  and PR on repair. If the default branch advanced, refresh only a still-clean
  initial checkout before implementation; report both base SHAs in STARTED so
  the coordinator can verify and update its ledger. Preserve unexpected work.
- Applicable instructions: <AGENTS.md paths and material repository rules>.
- Merge policy: <automatic, or explicit manual/human-review hold>.
- Nested-reviewer capacity: <explicit allocated slots and request/release protocol;
  mandatory reviews may run serially, but must never be skipped for capacity>.
  Report every task/thread handle before yielding. Own, record and settle them.
- Stop constraint: <deadline/timezone or none; how stop events arrive>.

Ticket scope:
<Full description, original user story when available, and every acceptance
criterion. Include comments or changes that refine the requirements, referenced
specifications/designs, parent/subtask scope, attachments, and material exclusions. Provide accessible references and
the requirement-bearing content already recovered from them.>

Readiness and implementation context:
<Why dependencies are satisfied on the merged base; relevant code/test/config
paths; settled decisions; existing verification commands; suggested approach
and risks; known parallel work and interfaces/files it affects. Distinguish
suggestions from mandatory ticket requirements.>

Ownership and integration:
- Work only on this ticket and inside the supplied worktree. Verify the execution
  workspace and exact base/head before editing. Send STARTED to the coordinator
  with your thread/run IDs, actual path, branch and initial SHA. Stop on a binding
  mismatch. Preserve unrelated work.
- Use the exact supplied branch and issue linkage required by the repository's
  GitHub–Linear integration. Keep local/remote branch identity and tracking
  consistent with complete-work. Do not create a second PR on resume.
- The coordinator manages Linear. Make no tracker transitions, comments,
  follow-up tickets, assignment changes, or dependency edits.
- Commit coherent chunks regularly, then run complete-work's pre-PR reviews in
  this exact worktree using its ignore policy, routing and usage ledger. Name
  reviewers `Subagent <issue-ID> R<n> <model>`. No delegated post-PR reviews.
- Merge only through finish-pr's current-head gate and only when policy permits.
  Handle Copilot quota and narrow evidence-backed thread settlement under that
  skill; never resolve human-owned threads to force a merge.
- Register the PR in your worker thread. Use its PR watcher for finish-pr waits;
  before yielding, report WAITING with PR/head, pending condition and live handles.
  Stop worker PR watches and mutating follow-ups before reporting MERGED or READY.
- Read the full source issue and required references; the brief does not excuse
  skipping complete-work's scope checks. If source requirements drift, report it.
- Routine implementation choices are yours. If completion needs a material user
  decision, permission, unavailable prerequisite, or impossible verification,
  stop safely and return the precise blocker to the coordinator. Do not interview
  the user or invent an answer; defer complete-work's grilling path to a later run.
- Preserve convergence limits and prior attempt history on repair. Honour a
  coordinator stop and check any deadline before external mutations; do not leave
  unreported background mutators running. Launch no extra top-level threads and
  delegate only within the explicit nested-agent allocation.

Reporting:
- Top-level threads have no automatic completion delivery to the coordinator.
- Send STARTED, WAITING, MERGED, READY or BLOCKED via t3_thread_send to the supplied
  coordinator thread ID, mode queue, using a stable clientRequestId per report.
  Include the run/issue/attempt/result IDs. Reuse that ID on uncertain retries.
- For reviewer capacity, send WAITING with requested slots and pending model
  assignments. Wait for the coordinator's explicit grant; release slots after
  recorded completion/cleanup and request again for fresh review tasks.
- MERGED means GitHub confirms the actual merge, with final head, merge commit
  and method. READY means the audit passed but an explicit manual hold prevents
  merging. Both require no live nested work, worker watcher or queued mutator.
  BLOCKED preserves the exact gap; a queued merge is WAITING, not MERGED.
- Keep the complete result below in your final answer even if notification fails.

Return:
- Issue ID; PR URL; exact branch and head SHA; worktree path.
- Acceptance-criteria coverage and verification commands/results.
- Merge policy; pre-PR receipt and per-round accounting; reviewer cleanup;
  finish-pr's fresh conflict, checks, reviews, and reply-submission audit;
  any pending check, reviewer response, or blocker. Do not claim readiness early.
- Outstanding changes or nested tasks, if any; enough state to resume safely.
```

For repairs, send the original brief, PR metadata, prior worker results, attempted fixes, review dispositions/replies, remaining findings, consumed convergence budget, and the reason readiness was rejected to the same owned T3 thread with `t3_thread_send` and a new stable request ID. Reconcile existing runs and queued messages first; retain the exact worktree, branch and PR. Use a replacement thread bound to that existing worktree only after proving the previous worker cannot resume mutation.
