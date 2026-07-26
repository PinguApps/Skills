# Skills

Opinionated skills I use in my setup each day.

## Skills

### [finish-pr](skills/finish-pr/)

Finishes the GitHub pull request attached to the current branch.

The skill:

- Resolves merge conflicts before diagnosing and fixing failed CI.
- Uses the current conversation and repository-native context to judge feedback.
- Actions unresolved review comments without duplicating an agent response that is
  awaiting reviewer follow-up.
- Preserves human-owned thread resolution state and verifies replies are submitted.
- Pushes focused commits and continues through Codex review until the current PR
  head receives a thumbs-up.

### [implement-task-linear](skills/implement-task-linear/)

Implements a Linear issue end to end in the current repository.

The skill:

- Accepts a Linear issue identifier or asks for one.
- Reads root `PLAN.md` and `CONTEXT.md` when present.
- Reconciles the issue, surrounding work, and repository state.
- Implements and verifies every requirement and acceptance criterion.
- Restricts all Linear access and mutations to the issue's exact team and project.
- Creates or updates related issues when justified, including moving fully covered
  issues to In Review.
- Reports repository drift, verification results, and every Linear mutation.

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
- Captures acceptance criteria, executor, labels, and native dependencies.
- Requires review and explicit approval before publishing.
- Publishes tickets to the backlog and verifies their metadata and ordering.

Based on Matt Pocock's [to-tickets](https://github.com/mattpocock/skills/tree/main/skills/engineering/to-tickets) skill.
