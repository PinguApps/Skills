---
name: to-linear
description: Turns PLAN.md and project context into ordered, non-overlapping Linear milestones and tickets for agent and human work, with native dependencies, Backlog status, and focused labels. Use when the user asks to create a Linear implementation backlog from a project plan.
disable-model-invocation: true
---

# To Linear

Create narrow, end-to-end Linear tickets. Mark only agent-suitable work with `Agent`.

## Process

### 1. Confirm the destination

Before analysing or drafting tickets:

1. List all available teams with the Linear MCP server and ask the user to choose one.
2. List that team's projects and ask the user to choose one.
3. Repeat both names and obtain explicit confirmation.

Never infer the destination. Every ticket in the run uses the confirmed team and project unless the user restarts selection.

### 2. Read the plan, context, and existing tickets

`PLAN.md` should exist and is the primary source of planned scope and outcomes. Find and read it fully; if absent, stop and ask the user to provide or create it.

`CONTEXT.md` may exist. If present, read it fully and treat its domain language, boundaries, and decisions as authoritative while interpreting `PLAN.md`. Plan only work supported by `PLAN.md`, interpreted through `CONTEXT.md`; do not invent scope. Also read applicable `AGENTS.md`, referenced sources, relevant ADRs, designs, code, and tests when they affect ticket accuracy. Ask about material contradictions rather than choosing silently.

After destination confirmation and before drafting, list the project's milestones and all its team issues, following pagination and including completed or archived issues where available. Compare milestone scope and issue titles, descriptions, acceptance criteria, and status with the plan:

- Reuse existing milestones that match a planned phase.
- Reuse existing issues that already cover planned work; do not duplicate them.
- Narrow or omit proposed work that partially overlaps, and explain the overlap during review.
- Do not modify, rename, or close existing issues unless the user explicitly approves it.

Recheck for newly created overlaps immediately before publishing.

### 3. Draft milestones and tracer-bullet tickets

Each ticket must deliver a narrow, complete, independently verifiable outcome. Prefer vertical slices across necessary layers over layer-by-layer tasks. Size agent work for one fresh context window and human work as one focused action. Include human judgement, credentials, physical action, or approval as **Human** tickets; publish them normally without `Agent`.

Group related tickets into native Linear project milestones. Milestone names describe outcomes or phases and have no numeric prefix. Order milestones chronologically and topologically: every prerequisite milestone must appear earlier.

Within each milestone, name every issue:

```text
III - Title
```

`III` is zero-padded to three digits. Start each milestone at `000`, increment in execution order (`001`, `002`), and reset to `000` for the next milestone. Avoid numbers already used in that milestone.

Topologically order all tickets. Every blocker must be earlier in the total milestone/task order:

- A ticket may depend on a lower issue number in its milestone.
- A ticket may depend on any ticket in an earlier milestone.
- A ticket must never depend on a later issue in its milestone or any future milestone.

If an existing milestone or issue conflicts with this order, surface it and ask before renaming, moving, or renumbering it. For wide mechanical refactors that cannot land green as vertical slices, use ordered expand–migrate–contract tickets.

### 4. Review with the user

Present the complete proposal in milestone order. For each milestone show existing/new status; for each ticket show title, existing/new status, blockers, delivered outcome, acceptance criteria, executor (`Agent` or `Human`), and labels. Explicitly show omitted or narrowed overlaps.

Ask the user to approve milestone names/order, ticket order, granularity, dependencies, overlap decisions, criteria, and labels. Do not publish until explicitly approved.

### 5. Prepare Linear metadata

Use the Linear MCP server to:

1. Resolve the confirmed team's unambiguous `Backlog` state.
2. List existing labels; reuse durable type/domain labels.
3. Create missing durable labels only when useful.
4. Ensure `Agent` exists if any ticket is agent-suitable.

Use two or three labels where useful. Agent tickets normally use `Agent`, one type, and optionally one domain label. Human tickets use type/domain labels but never `Agent`; do not invent `Human` unless asked. Avoid status, project, team, redundant, or one-off labels.

### 6. Publish and verify

After the final overlap recheck, create missing milestones in approved chronological order, then create issues milestone-by-milestone and ascending by title number. Assign every issue to its milestone and the confirmed `team`, `project`, resolved Backlog `state`, and approved `labels`. Add native `blockedBy` relationships using existing or already-created identifiers. Never use prose instead of native relations.

Use Linear's native milestone/issue reordering capability when available. Otherwise creation order plus numeric titles is the source of truth; verify the returned order and clearly report any manual Linear reorder still required. Never invent milestone target dates merely to force ordering.

Do not assign, delegate, or add issues to a cycle unless asked. Verify milestone assignment and every issue's title, team, project, Backlog state, labels, and blockers. Confirm agent tickets have `Agent`, human tickets do not, and every blocker is earlier. Correct mismatches before reporting identifiers and URLs.

End with plain text `Milestone order: <first> → <second> → <third>` followed by issue identifiers/URLs in that same milestone and ascending-number order.

## Issue description

```md
## What to build
<End-to-end outcome from the user's perspective.>
## Acceptance criteria
- [ ] <Observable, verifiable outcome>
## Context
<Durable decisions and constraints only; omit if unnecessary.>
```

Avoid brittle paths and snippets. Example: milestone `Quote flow` contains `000 - Create quote form`, then `001 - Validate requests`; milestone `Launch` starts again at `000 - Approve production wording`.
