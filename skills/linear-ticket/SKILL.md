---
name: linear-ticket
description: Create or update a Linear ticket, including its description, metadata, estimate, native relations, and saved-field verification. Use for ticket writes within other Linear workflows too.
---

# Linear Ticket

Own the rules for creating and updating individual Linear tickets. Use the Linear MCP server. A calling workflow owns its scope, authorization, scheduling and execution order; this skill supplies ticket drafting, metadata, mutation and verification. Read it before drafting or writing tickets. If unavailable, resolve that prerequisite before writing.

## Destination, scope and authorization

For a standalone creation, list available teams, ask the user to choose one, list that team's projects, ask them to choose one, then repeat both names and obtain explicit confirmation before analysing or drafting. Reuse an explicitly confirmed destination passed by a calling workflow. For an update, resolve the supplied issue identifier or URL and verify its account/workspace, team and project. Ask for missing or ambiguous choices; a projectless issue requires assignment or authorization to assign a named project before inspecting surrounding work.

Retain exact team/project IDs and verify both on related issues before reuse or mutation. Honour the caller's stricter read boundary. For standalone creation and backlog planning, list the destination's milestones and all matching issues, following pagination and including completed/archived items where available. Compare full descriptions, criteria and state; reuse covered work, narrow partial overlaps and disclose omissions. Same-team issues in other projects may reveal overlap but cannot be reused or mutated in this scope. Refresh overlaps immediately before creation.

Read the full requirements, comments, requirement-bearing attachments and relevant repository context. Resolve a primary source from an explicit source, otherwise the settled conversation plan/spec, otherwise root `PLAN.md`; ask when none exists or source selection materially affects scope. Supporting context constrains language and decisions without expanding the requested work. Preserve a stable source through an approved native parent when it is an issue in the same team/project; otherwise use the description's optional `Source` section. Leave the source issue unchanged unless its mutation is explicitly approved.

For standalone creation or substantive edits, show the proposed ticket and intended changes for approval before publication. A request explicitly authorizing a concrete edit, or a calling workflow's approved proposal or scoped mutation authority, supplies that approval; carry it forward without another confirmation. A request for research, suggestions or review stays read-only. Existing-issue reuse alone authorizes no edits. Renaming, moving or renumbering existing items must be specifically included in the approved changes. Do not assign, delegate, add to a cycle, or close an issue without authorization for that action.

## Draft the ticket

Deliver a narrow, complete, independently verifiable outcome, normally one PR boundary. Prefer a vertical slice across necessary layers. Size agent work for one fresh context window and human work as one focused action. Human judgement, credentials, physical action and approvals are Human work. Prefactoring needs a concrete independent outcome required by later work; unrelated cleanup is outside scope.

Every new ticket, including Human and prefactoring work, and every authorized description rewrite uses this format:

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

Start with who needs what and why, in one or two short sentences understandable without a technical background. Use `As a <person>, I want <outcome> so that <benefit>` when natural; depart from it when clearer. Use familiar words and explain essential specialist terms. Put implementation details below the story. Avoid brittle paths and snippets. Leave an existing description untouched when its edit is not authorized; surface a missing or unclear story for approval instead of silently rewriting it.

Show the title, existing/new status, opening story, delivered outcome, criteria, executor (`Agent` or `Human`), labels, provenance, native relations, cycle choice, estimate and brief sizing rationale. Identify changed estimates and provisional scale assumptions. For an update, distinguish each intended mutation from fields to preserve.

## Cycle choice

Before creating any ticket, establish an explicit choice of **No cycle**, **Upcoming cycle** or **Current cycle**. Reuse a choice already authorized by the user or a calling workflow's approved proposal; otherwise ask which bucket to use before publication. No cycle is a deliberate choice, never a silent default. One choice may cover a whole batch when its scope is explicit; mixed batches need a choice for every ticket. Include the choice in the proposal so it is visible before writing.

For Current or Upcoming, resolve the team's actual native cycle through the Linear MCP, using its dates and the team's timezone: Upcoming means the next cycle after Current. Retain the exact cycle ID, name/number and dates with the choice. If the requested cycle is missing or ambiguous, resolve that gap before creating the affected tickets; creating cycles or changing cadence requires separate authorization. For No cycle, leave the native cycle unset. Backlog status and milestone placement do not establish a cycle choice.

Refresh the target cycle immediately before creation. If rollover or concurrent changes mean the approved ID no longer represents the chosen bucket, reconcile the choice before writing rather than silently assigning a different cycle. Apply the authorized native cycle assignment and verify the saved cycle ID, or verify that no cycle is assigned, before reporting success. Include each ticket's verified bucket and, when assigned, cycle name/number and dates in the result. For existing-ticket updates, preserve cycle membership unless its change is authorized; the mandatory three-bucket decision applies to creation.

## Metadata and relations

Before naming or creating a ticket, read [Linear milestone and issue numbering](references/issue-numbering.md). Every new ticket belongs to exactly one native project milestone chosen by its outcome, including single-ticket changes and follow-ups. Reuse a matching milestone or propose a new one. Apply the reference's numbering allocation, insertion approval and read-back rules; routine status, estimate and cycle changes preserve names and milestone placement.

Resolve the team's unambiguous native workflow state by ID. New tickets normally start in Backlog; a caller may specify another authorized state. Reuse durable type/domain labels and create missing durable labels only when useful. Use two or three labels where useful: agent tickets normally have `Agent`, one type and optionally one domain. Ensure `Agent` exists when needed. Human tickets never receive `Agent`; create a `Human` label only if requested. Avoid status, project, team, redundant and one-off labels.

Use native parent, related-issue and `blockedBy` fields when available, rather than prose substitutes. Derive blockers from actual prerequisites, with the minimal direct edges that represent them. Each blocker must be earlier in the total milestone/issue order; numbers alone create no dependency. Independent issues remain unblocked. A relation to a source or follow-up does not determine its milestone. Surface ordering conflicts before approved moves or renumbering; earlier milestones are never blanket gates.

For related follow-ups, establish concrete, independently actionable work outside the supplied implementation targets and check scoped overlap first. Relate the follow-up natively to its originating target when supported. A prerequisite that prevents completion remains a reported blocker. Edit an existing related issue only when repository evidence establishes stale content, relations or status. Read and verify every acceptance criterion before treating it as satisfied; partial or title-only overlap is insufficient.

## Estimate

Read and apply [Native estimates](references/estimates.md) before drafting estimates or making ticket writes. It owns scale discovery, sizing, saved native values and estimate-error recovery. Unless the caller restricts reassessment, assess every new or edited ticket, including status and relation changes; leave reused issues with no authorized edits untouched. A cycle-planning caller may preserve existing estimates and authorize only missing estimates or explicitly requested reassessments.

## Write and verify

Immediately before writing, refresh the issue or creation overlap, destination, relevant metadata and allocated numbers. Reconcile concurrent changes against the authorized proposal. Create any approved missing milestone before its ticket, using the approved name and order. Write only approved fields, including confirmed team/project, milestone, state and labels for a new issue. Preserve other fields on existing issues. Status transitions during implementation preserve completed, cancelled, archived and further-along states; leave post-merge closure to configured automation unless explicitly instructed otherwise.

Apply approved native estimates and the reference's combined-write recovery procedure. Report operation failures and partial results explicitly.

When publishing multiple tickets, create all issues first in the caller's approved order, then apply relations once every referenced identifier exists. For a single ticket, resolve all relation identifiers before writing. In either case, verify every approved dependency edge on the blocked issue against the complete approved graph, including cross-milestone edges, with no invented blockers.

Re-read saved fields. For new issues verify identifier/URL, team/project, title, milestone and prefix, state, labels, estimate, provenance and relations. Confirm agent/Human classification matches labels. For existing issues verify identity, every authorized mutation and preserved metadata without normalizing unrelated fields. For new or explicitly edited descriptions, verify the approved opening story and description format. Account for pagination and relation-list truncation: a partial view cannot establish an empty blocker set. Record service-side changes such as Backlog becoming Todo during cycle assignment. Correct in-scope mismatches before reporting success.

Return the identifier, URL, verified changes and state, saved estimate and rationale, provisional assumptions, and any disabled-estimation result, unresolved error or partial write. A caller may incorporate this into its own ordered report.
