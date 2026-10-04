# Worker handoff

Read when dispatching or repairing a ticket. Supply actual values and requirement text, not an unresolved template or just a ticket title. The child may receive no parent conversation, so include everything it needs to establish scope and act independently.

```text
Complete this one ticket using $complete-work at <resolved skill path>.
Follow its required skills through verified implementation, PR creation, CI,
and finish-pr review convergence. Leave the PR open for the coordinator to merge.

Execution:
- Run/issue: <run ID; issue ID and URL; exact team/project IDs>.
- Repository/worktree: <absolute isolated execution path; repository identity>.
- Base: <base repository, remote, default branch, freshly fetched SHA>.
- Head: <head repository, push remote, exact agent/... branch>.
- Branch setup: <detached fresh-base checkout requiring complete-work setup,
  or verified existing run-owned branch and upstream when resuming>.
- Applicable instructions: <AGENTS.md paths and material repository rules>.
- Subagent capacity: <explicit allocation; zero unless coordinator granted slots>.
- Stop constraint: <deadline/timezone or none; how stop events arrive>.

Ticket scope:
<Full description and every acceptance criterion. Include comments or changes
that refine the requirements, referenced specifications/designs, parent/subtask
scope, attachments, and material exclusions. Provide accessible references and
the requirement-bearing content already recovered from them.>

Readiness and implementation context:
<Why dependencies are satisfied on the merged base; relevant code/test/config
paths; settled decisions; existing verification commands; suggested approach
and risks; known parallel work and interfaces/files it affects. Distinguish
suggestions from mandatory ticket requirements.>

Ownership and integration:
- Work only on this ticket and inside the supplied worktree. Verify the execution
  workspace and exact base/head before editing. Preserve unrelated work.
- Use the exact supplied branch and issue linkage required by the repository's
  GitHub–Linear integration. Keep local/remote branch identity and tracking
  consistent with complete-work. Do not create a second PR on resume.
- The coordinator manages Linear. Make no tracker transitions, comments,
  follow-up tickets, assignment changes, or dependency edits.
- Do not merge the PR. Keep reviewer-owned thread resolution unchanged.
- Read the full source issue and required references; the brief does not excuse
  skipping complete-work's scope checks. If source requirements drift, report it.
- Routine implementation choices are yours. If completion needs a material user
  decision, permission, unavailable prerequisite, or impossible verification,
  stop safely and return the precise blocker to the coordinator. Do not interview
  the user or invent an answer; defer complete-work's grilling path to a later run.
- Preserve convergence limits and prior attempt history on repair. Honour a
  coordinator stop; do not leave unreported background mutators running.

Return:
- Issue ID; PR URL; exact branch and head SHA; worktree path.
- Acceptance-criteria coverage and verification commands/results.
- finish-pr's fresh conflict, checks, reviews, and reply-submission audit;
  any pending check, reviewer response, or blocker. Do not claim readiness early.
- Outstanding changes or nested tasks, if any; enough state to resume safely.
```

For repair dispatches, also include the original brief, PR metadata, prior worker results, attempted fixes, review dispositions/replies, remaining findings, consumed convergence budget, and the reason the coordinator rejected readiness. In T3, create each delegated repair round with `delegate_task` and a new stable request ID; manage the returned task ID rather than using its backing child thread to simulate a new delegated round.
