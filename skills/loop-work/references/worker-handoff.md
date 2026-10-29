# Worker handoff

Read when delegating or repairing a ticket. Supply actual requirements and values,
not an unresolved template. A child has no coordinator conversation history.
Use `delegate_task` with worktree isolation as described in
[T3 subagent control](t3-threads.md).

```text
Complete this one ticket using $complete-work at <accessible skill path>.
Follow its required skills through verified implementation, PR creation, CI,
and finish-pr review convergence. You own the protected merge unless the supplied
merge policy is manual. The coordinator verifies outcomes and never merges for you.
Follow create-pr's Linear ticket title-prefix and plain-language user story rules.

Execution:
- Run/issue: <run ID; issue ID and URL; exact team/project IDs; attempt ID>.
- Coordinator: <exact T3 parent thread/project IDs>.
- Repository/worktree: <repository identity; verify the T3-created isolated
  checkout through t3_worktree_status and actual shell path>.
- Base: <base repository, remote, default branch, freshly fetched SHA>.
- Head: <head repository, push remote, desired agent/... branch>.
- Branch setup: T3 supplied a new checkout from the coordinator's committed HEAD.
  Verify ownership and cleanliness, then align this new branch/name with the
  freshly fetched default branch before implementation. Record initial and final
  base SHAs. Stop and preserve unexpected work. Continue this assigned checkout
  under complete-work; finish its remote publication and upstream checks.
  On repair, retain the exact existing worktree, branch and PR.
- Applicable instructions: <AGENTS.md paths and material repository rules>.
- Merge policy: <automatic, or explicit manual/human-review hold>.
- Delegation: you are a level-2 implementation child. Invoke review-work to launch
  its reviewers as your own level-3 delegate_task children, shared isolation in
  this checkout. Own their handles, accounting, results and cleanup. The worker
  concurrency limit does not count your nested reviewers; respect host limits.
- Stop constraint: <deadline/timezone or none>.

Ticket scope:
<Full description, original user story, every acceptance criterion, comments that
refine requirements, specifications/designs, attachments, parent/subtask scope,
and exclusions. Provide accessible references and recovered requirement text.>

Readiness and implementation context:
<Why dependencies are satisfied on the merged base; relevant code/test/config
paths; settled decisions; existing verification commands; suggested approach,
risks and concurrent work. Distinguish suggestions from mandatory requirements.>

Ownership and integration:
- Work only on this ticket inside the T3-created checkout. Verify actual path,
  branch and base before editing; include this workspace acknowledgement in your
  result. Preserve unrelated work and stop on a binding mismatch.
- Use the supplied branch and required GitHub–Linear linkage. Keep local/remote
  identity and tracking consistent with complete-work. Reuse the PR on repair.
- The coordinator manages Linear. Make no tracker transitions, comments,
  follow-up tickets, assignment changes or dependency edits.
- Commit coherent chunks. complete-work invokes review-work once for proof,
  filtering, reviewers, accounting and cleanup. Provide its concise verification
  and runtime-check handoff so reviewers can run safe checks themselves.
  No delegated post-PR reviews.
- Merge only through finish-pr's current-head gate and when policy permits.
  Handle Copilot quota and evidence-backed thread settlement under that skill;
  never resolve human-owned threads to force a merge.
- Link each created/taken-over/pushed PR as the next tool call. As a delegated
  child, never call watch_pull_request. When checks/reviews/queue prevent immediate
  completion, return WAITING with exact PR/head and pending condition. The parent
  owns the [watch handoff](../../finish-pr/references/watch-handoff.md) and resumes
  you from fresh evidence. An unsupported host blocks the coordinator; retain
  finish-pr state so this child remains resumable.
- Read the full source issue and references; report requirement drift.
- Make routine implementation choices. For a material user decision, permission,
  missing prerequisite or impossible verification, stop safely and return BLOCKED
  with the precise gap. Defer complete-work's grilling path to a later run.
- Preserve convergence limits and prior attempts on repair. Check any deadline
  before external mutations. Honour cancellation, stop your owned test processes
  and report outstanding background work. Launch only the nested agents required
  by the supplied workflow; do not create top-level threads.

Reporting:
- Delegate completion delivers your result to the parent automatically. Return
  MERGED, READY, WAITING or BLOCKED with run/issue/attempt IDs; no extra message
  to the coordinator is necessary.
- MERGED means GitHub confirms the actual merge, with final head, merge commit
  and method. READY means the audit passed but an explicit manual hold prevents
  merging. Both require no live nested work or queued mutator.
- A queued merge is WAITING, not MERGED. Include any nested-task handles and exact
  remaining conditions; a final turn with live children is not completed delivery.

Return:
- Issue ID; PR URL; exact branch/head; worktree path and initial/final base SHAs.
- Acceptance-criteria coverage and verification commands/results.
- Merge policy; pre-PR receipt/accounting; reviewer cleanup; finish-pr's fresh
  conflict/checks/reviews/reply audit; any pending condition or blocker.
- Outstanding changes/processes/tasks and enough state to resume safely.
- Last line: PR <full URL>, head <SHA>, checks and reviews <state>.
```

For implementation/PR repairs, resume the same child using `t3_thread_send` with
a new stable request ID after reconciling its existing tasks/queue. Retain the
returned continuation task ID and the exact worktree/branch/PR, original brief,
findings/dispositions, proof and consumed convergence budget. Reviewer rechecks
use fresh review-work delegates, never repair messages to an old reviewer.
