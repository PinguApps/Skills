# Skills

Opinionated skills I use in my setup each day.

## Skills

### [complete-work](skills/complete-work/)

Takes supplied work from a new branch through PR review completion.

The skill:

- Discovers and fetches the repository's default branch, then creates an `agent/` branch from that commit.
- Implements the task with incremental commits and relevant verification.
- Pushes the branch and uses `create-pr` to open a PR against the default branch.
- Runs `finish-pr` to complete review and CI.

### [loop-work](skills/loop-work/)

Loops through a Linear team's project backlog using isolated T3 worker threads and
`complete-work`, merging verified PRs and reassessing newly unblocked work.

The skill:

- Requires the Linear team/project, parallel thread limit, and ticket limit (or no max).
- Controls each worker's worktree, result delivery, repair and shutdown through T3.
- Supports concurrency beyond native subagent slots; accepts the old limit parameter as an alias.
- Selects independently actionable tickets that need no user input.
- Uses fixed `agent/` branches derived from Linear and limits outstanding reservations.
- Leaves In Review and Done transitions to verified GitHub–Linear automation.
- Reassesses after merges and stops with a concise completion and blocker ledger.

### [create-pr](skills/create-pr/)

Creates a GitHub PR using the repository's template, including inherited templates,
or the standard categorisation and summary fallback.

The skill:

- Selects one change category and one release level in the standard checkbox block.
- Preserves template structure and appends additional verification or review sections.
- Reuses an existing PR and verifies the saved description and target.

### [finish-pr](skills/finish-pr/)

Finishes the GitHub pull request attached to the current branch.

The skill:

- Resolves merge conflicts before diagnosing and fixing failed CI.
- Uses the current conversation and repository-native context to judge feedback.
- Actions unresolved review comments without duplicating an agent response that is
  awaiting reviewer follow-up.
- Preserves human-owned thread resolution state and verifies replies are submitted.
- Pushes focused commits and continues through review until current-head CI and
  any running PR Agent review succeed, with all actionable feedback addressed.

### [implement-task-linear](skills/implement-task-linear/)

Wraps `complete-work` to deliver one or more supplied Linear issues together in a
single PR through review and CI.

The skill:

- Accepts Linear issue identifiers or URLs, or asks for them.
- Gives a short bullet plan and resolves material questions before implementation.
- Follows the originating spec and reads optional `PLAN.md`, `CONTEXT.md`,
  `CONTEXT-MAP.md`, and applicable ADRs when present.
- Reconciles the issue, surrounding work, and repository state.
- Implements and verifies every requirement and acceptance criterion.
- Uses `complete-work` for branch setup, commits, PR creation, and review completion.
- Requests user help only when needed, with precise setup and resumption steps.
- Moves every supplied issue to In Progress when implementation starts and In Review
  when the complete PR is created, preserving terminal and further-along states.
- Includes every supplied issue in PR closing references for automatic linking and
  closure on merge through the existing GitHub–Linear integration.
- Restricts related Linear access and mutations to each issue's exact team and project.
- Creates or updates related issues when justified, including moving fully covered
  issues to In Review.
- Reports repository drift, verification results, and every Linear mutation.

### [linear-ticket](skills/linear-ticket/)

Creates or updates one Linear ticket, with shared rules used by the other Linear
workflows.

The skill:

- Owns ticket descriptions, milestone numbering, labels and native relations.
- Sizes work and verifies native estimates, including safe recovery from failed writes.
- Preserves each calling workflow's scope and authorization.
- Re-reads saved fields before reporting success.

### [plan-cycle](skills/plan-cycle/)

Fills the next Linear cycle or tops up the current cycle from an existing backlog.

The skill:

- Uses an explicit destination or derives an unambiguous one from the conversation.
- Includes Pingu's weekends and budgets AI-assisted work from recent cycles, current-cycle delivery over elapsed time, and unfinished commitments.
- Selects complete outcomes with real native dependencies and useful parallel work.
- Adds issues through the native cycle field and verifies membership and preserved metadata.

### [test-changes](skills/test-changes/)

Explains how to manually inspect and test the work just completed in the current
conversation.

The skill:

- Starts with what is already visible before asking you to run anything.
- Gives copyable PowerShell commands for any required setup or server.
- Maps every changed surface to exact actions, expected results, and failure signs.
- Separates confirmed state from inferred expectations and testing limitations.

### [to-linear](skills/to-linear/)

Turns a project's `PLAN.md` and supporting context into an ordered Linear
implementation backlog.

It is intended to be run after `grill-me` or `grill-with-docs` from Matt Pocock's
[skills](https://github.com/mattpocock/skills).

The skill:

- Confirms the target Linear team and project before planning.
- Reuses existing milestones and issues to avoid duplicate work.
- Drafts narrow, non-overlapping tickets grouped into ordered milestones.
- Names milestones `00 - Name`, `01 - Name` and issues `00-000 - Title`, `01-000 - Title`.
- Captures acceptance criteria, executor, labels, and native dependencies.
- Requires review and explicit approval before publishing.
- Uses `linear-ticket` to publish and verify individual tickets, then checks the full backlog order.

Based on Matt Pocock's [to-tickets](https://github.com/mattpocock/skills/tree/main/skills/engineering/to-tickets) skill.

### [to-spec-local](skills/to-spec-local/)

Wraps a separately installed `to-spec` skill to save a complete Markdown
specification in the current repository, ready to use as the primary source for
`to-linear`.

The skill:

- Reads the installed upstream skill; its source is intentionally not hosted here.
- Replaces tracker setup, issue publication and labels with in-repo file delivery.
- Reuses accepted testing seams and preserves the upstream specification template.
- Records complete scope and provenance without creating Linear issues.
