# Linear milestone and issue numbering

Use these names throughout a project:

```text
MM - Milestone name
MM-DDD - Issue title
```

`MM` is the milestone's zero-padded two-digit number, starting at `00` in project order. `DDD` is the issue's zero-padded three-digit number, starting at `000` within that milestone. Increment milestones as `00`, `01`, `02`; restart only `DDD` for each milestone. Every issue's `MM` must match its assigned native milestone.

For a new backlog or an approved renumbering, number milestones and their issues contiguously in intended completion order, placing actual prerequisites first and using preferred sequence to break ties. These numbers express display order; native blocker relationships determine dependencies and readiness.

Before allocating numbers, inspect the authorized project's existing milestones and issues, following pagination and including completed and archived items where available. Reuse conforming prefixes. Append new milestones after the highest allocated `MM`, and new issues after the highest allocated `DDD` in their chosen milestone; account for existing items outside the current proposal so prefixes remain unique. Preserve existing names and titles unless their changes are authorized. If placement requires a new milestone, an insertion, a move, or renumbering existing items, include the affected milestone names and issue titles in the proposal and obtain approval before those mutations.

When creating a follow-up, choose its native milestone by the work's outcome, then allocate its issue number there; a relationship to the source issue does not determine milestone placement. If the intended milestone has no conforming prefix, propose the naming changes before creating the follow-up.

After saving, re-read affected milestone names, issue titles and native milestone assignments. Verify matching milestone prefixes, uniqueness and the approved order. Check contiguity for a new backlog or approved renumbering; report legacy gaps or naming conflicts without silently rewriting existing items. Linear's issue identifiers, such as `PIN-123`, remain unchanged.

Example: `00 - Quote flow` contains `00-000 - Create quote form` and `00-001 - Validate requests`; `01 - Launch` starts with `01-000 - Approve production wording`.
