---
name: to-linear
description: Break a plan, spec, referenced issue, or current conversation into approved Linear milestones and tracer-bullet tickets in a confirmed project, with native dependencies, Backlog status, and focused labels.
disable-model-invocation: true
---

# To Linear

Create narrow, end-to-end Linear tickets. Every ticket belongs to the confirmed project and a native milestone. Mark only agent-suitable work with `Agent`.

## Process

### 1. Confirm the destination

Before analysing or drafting tickets:

1. List all available teams with the Linear MCP server and ask the user to choose one.
2. List that team's projects and ask the user to choose one.
3. Repeat both names and obtain explicit confirmation.

Never infer the destination. Every ticket in the run uses the confirmed team and project unless the user restarts selection.

### 2. Resolve the source, context, and existing tickets

Resolve exactly one **primary source** for scope, in this order:

1. An explicit source supplied with the invocation or explicitly designated by the user for this run: a file, issue identifier or URL, or pasted plan/spec. Fetch and read the full body and comments of a referenced issue.
2. Otherwise, the most recent settled plan or spec in the current conversation. If it points to an artifact, fetch and read that artifact fully.
3. Otherwise, root `PLAN.md`, when present; read it fully.
4. Otherwise, stop and ask the user for the source.

An explicit source wins even when `PLAN.md` exists. State which source was selected. Do not merge multiple plausible sources into new scope; ask when source selection is ambiguous or when a contradiction materially changes the intended outcome.

Treat `CONTEXT.md`, applicable `AGENTS.md`, referenced sources, relevant ADRs, designs, code, and tests as supporting context. Read them when they affect ticket accuracy. `CONTEXT.md` is authoritative for domain language, boundaries, and durable decisions, but supporting context never silently expands the primary source.

Preserve provenance when the primary source has a stable reference. If it is a Linear issue in the confirmed team and project, propose a native parent relationship. Otherwise include the reference in each new ticket's optional `Source` section. Never modify or close the source issue unless the user explicitly approves it.

For broad work, use subagents for bounded, independent, read-only exploration such as separate module investigations, prior-art searches, or overlap checks. Continue other independent analysis while they work, then reconcile every result before drafting. The primary agent owns source selection, the complete proposal, user approval, and every Linear mutation; never create or edit Linear items concurrently through subagents.

After destination confirmation and before drafting, list the project's milestones and every issue whose team and project both match the confirmed destination, following pagination and including completed or archived issues where available. Search same-team issues in other projects only to surface possible cross-project overlap; never reuse them in this run. Compare in-project milestone scope and issue titles, descriptions, acceptance criteria, and status with the primary source:

- Reuse existing milestones that match a planned phase.
- Reuse existing issues that already cover planned work only when their team and project both match the confirmed destination; do not duplicate them.
- Narrow or omit proposed work that partially overlaps, and explain the overlap during review.
- Do not modify, rename, or close existing issues unless the user explicitly approves it.

Recheck for newly created overlaps immediately before publishing.

Infer the team's estimate convention from connector-exposed settings and values/labels on comparable issues within the confirmed team/project. Use enough evidence to size the work; do not use browser automation or require a complete scale/inherited-settings audit. Assess full scope, including implementation, verification, complexity and uncertainty; retain an existing estimate only when defensible. Missing estimates do not mean estimation is disabled. With no examples or exposed scale, provisionally size the actual work on Fibonacci values (1, 2, 3, 5, 8) and disclose that assumption in the proposal. Defer native write attempts until publication is approved; do not mutate an existing issue or create a probe ticket to discover settings.

### 3. Draft milestones and tracer-bullet tickets

Each ticket must deliver a narrow, complete, independently verifiable outcome. Prefer vertical slices across necessary layers over layer-by-layer tasks. Size agent work for one fresh context window and human work as one focused action. Include human judgement, credentials, physical action, or approval as **Human** tickets; publish them normally without `Agent`.

Draft every ticket description using the [Issue description](#issue-description) format, including Human and prefactoring tickets.

Before slicing, look for prefactoring that makes the requested change easier. Create prefactoring tickets first only when they have concrete, independently verifiable outcomes needed by later slices; never invent unrelated cleanup.

Assign every ticket to exactly one native Linear project milestone. Reuse an existing milestone that matches the outcome; otherwise propose a new one, including for a single-ticket change. Order milestones chronologically and topologically: every prerequisite milestone must appear earlier.

Before drafting names or allocating numbers, read [Linear milestone and issue numbering](references/issue-numbering.md). Apply its `MM - Milestone name` and `MM-DDD - Issue title` formats to the complete proposal, including existing items affected by an approved insertion or renumbering.

Topologically order all tickets without inventing dependencies. Every blocker must be earlier in the total milestone/task order:

- A ticket may depend on a lower issue number in its milestone.
- A ticket may depend on any ticket in an earlier milestone.
- A ticket must never depend on a later issue in its milestone or any future milestone.

A lower issue number does not itself create a dependency; only a native `blockedBy` relationship does. Keep independent tickets unblocked. They form the execution **frontier** and may be assigned to separate agents concurrently.

Treat the tickets as one dependency graph across all milestones, not as milestone gates. An issue is actionable as soon as its own blockers are complete, even when issues in earlier milestones remain open. Derive blockers from the work itself: if A must complete before B can complete, assign A as a native blocker of B. Prefer the minimal set of direct blockers that fully represents the graph; do not add an issue or an entire milestone merely because it appears earlier.

If an existing milestone or issue conflicts with this order, surface it and ask before renaming, moving, or renumbering it. For wide mechanical refactors that cannot land green as vertical slices, use ordered expand–migrate–contract tickets.

### 4. Review with the user

Present the selected primary source and the complete proposal in milestone order. For each milestone show existing/new status; for each ticket show title, existing/new status, blockers, opening user story, delivered outcome, acceptance criteria, executor (`Agent` or `Human`), labels, and source provenance. Include the proposed estimate and brief rationale for every new or edited ticket, explicitly identifying changes to existing estimates and any provisional scale assumption. Explicitly show omitted or narrowed overlaps and the initial frontier of independent agent tickets.

Ask the user to approve milestone names/order, ticket order, granularity, user stories, dependencies, overlap decisions, criteria, labels, applicable estimates, provenance, and parallel frontier. Do not publish until explicitly approved.

### 5. Prepare Linear metadata

Use the Linear MCP server to:

1. Resolve the confirmed team's unambiguous `Backlog` state.
2. List existing labels; reuse durable type/domain labels.
3. Create missing durable labels only when useful.
4. Ensure `Agent` exists if any ticket is agent-suitable.

Use two or three labels where useful. Agent tickets normally use `Agent`, one type, and optionally one domain label. Human tickets use type/domain labels but never `Agent`; do not invent `Human` unless asked. Avoid status, project, team, redundant, or one-off labels.

### 6. Publish and verify

After the final overlap recheck, recheck allocated prefixes against current milestones and issues, then create missing milestones in approved chronological order and every missing issue milestone-by-milestone and ascending by title number. Reconcile any newly occupied number before writing. Assign each newly created issue to its milestone and the confirmed `team`, `project`, resolved Backlog `state`, and approved `labels`. Preserve every reused milestone's name and every reused issue's title, state, milestone, project, labels, and relations unless the reviewed proposal explicitly listed each intended mutation and the user approved it. Add approved native parent relationships using existing or already-created identifiers. Never use prose instead of available native relations.

Attempt the approved native estimate for every new or edited ticket, including reused tickets with approved relation changes, even when the project has no estimated issues. Re-read each saved value/label to infer the team's convention and use it for subsequent tickets; a successful read-back verifies that value, not the full allowed range. Correct a provisional mapping when evidence supports it; obtain approval if this materially changes the agreed sizing. A description or comment alone does not save an estimate. Leave reused tickets with no approved edits untouched.

Only an explicit disabled-estimation rejection means estimates are off: record it once per team and continue approved publication without estimate writes. Invalid-value errors inform scale correction; permission, transport and unrelated errors remain operation problems. Reconcile issue existence and saved fields after any rejected or uncertain combined write before retrying, then apply approved non-estimate changes separately when safe; never duplicate an issue because its estimate failed. Report unresolved estimate failures separately from publication results. Missing settings alone must not block publication; never enable estimates or change team settings.

Only after every issue exists, make a separate blocker pass across the complete approved proposal. For every new issue, and every reused issue with approved relation changes, compare its actual prerequisites with the full issue set and add its approved native `blockedBy` relationships. This pass is exhaustive: verify each dependency edge is represented on the blocked issue, independent issues have no invented blockers, and cross-milestone edges capture the real prerequisite web without treating earlier milestones as blanket blockers.

Use Linear's native milestone/issue reordering capability when available. Otherwise creation order plus numeric titles is the source of truth; verify the returned order and clearly report any manual Linear reorder still required. Never invent milestone target dates merely to force ordering.

Do not assign, delegate, or add issues to a cycle unless asked. Re-read saved milestone names and issue titles against the shared numbering rules, including matching prefixes, uniqueness and approved order. For newly created issues, verify milestone assignment, title, team, project, Backlog state, labels, and blockers. For reused issues, verify identity and approved mutations without normalizing unapproved metadata. Confirm new agent tickets have `Agent`, new human tickets do not, and every newly created or explicitly approved blocker is earlier. Correct in-scope mismatches before reporting identifiers and URLs.

Re-read every newly created or explicitly approved edited description and verify it starts with the approved user story and meets the [Issue description](#issue-description) rules. Leave reused descriptions without approved edits untouched; surface any missing or unclear opening story for approval before changing it.

End with plain text `Milestone order: <first> → <second> → <third>` followed by issue identifiers/URLs in that same milestone and ascending-number order. Then write `Parallel frontier: <issues>` listing unblocked `Agent` tickets that separate agents can implement concurrently, or `Parallel frontier: none`.

## Issue description

Every ticket description must start with a user story explaining who needs what and why, in everyday language understandable to someone without a technical background. Keep it to one or two short sentences. Use `As a <person>, I want <outcome> so that <benefit>` when it reads naturally; use a second sentence or depart from that pattern when it makes the story clearer. Focus on the person's need and benefit, using familiar words and explaining any essential specialist term. Put implementation details in the sections below.

```md
<Brief, plain-language user story.>

## What to build
<End-to-end outcome from the user's perspective.>
## Acceptance criteria
- [ ] <Observable, verifiable outcome>
## Context
<Durable decisions and constraints only; omit if unnecessary.>
## Source
<Stable source reference; omit when represented by a native parent relation or no stable reference exists.>
```

Avoid brittle paths and snippets. Use the milestone and issue title examples in the shared numbering reference.
