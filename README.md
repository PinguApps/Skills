# Skills

Opinionated skills I use in my setup each day.

## Skills

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

### [to-linear](skills/to-linear/)

Turns a project's `PLAN.md` and supporting context into an ordered Linear
implementation backlog.

The skill:

- Confirms the target Linear team and project before planning.
- Reuses existing milestones and issues to avoid duplicate work.
- Drafts narrow, non-overlapping tickets grouped into ordered milestones.
- Captures acceptance criteria, executor, labels, and native dependencies.
- Requires review and explicit approval before publishing.
- Publishes tickets to the backlog and verifies their metadata and ordering.

Based on Matt Pocock's [to-tickets](https://github.com/mattpocock/skills/tree/main/skills/engineering/to-tickets) skill.
