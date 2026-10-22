---
name: to-linear
description: Break a plan, spec, referenced issue, or current conversation into approved Linear milestones and tracer-bullet tickets in a confirmed project, with native dependencies, Backlog status, and focused labels.
disable-model-invocation: true
---

# To Linear

Turn the primary source into an approved, ordered backlog. Read and apply [$linear-ticket](../linear-ticket/SKILL.md) before drafting: it owns all individual-ticket content, metadata, estimates, mutations and verification. This workflow owns destination selection, source resolution, slicing, whole-graph review and publication order. Pass its confirmed destination and approved proposal to `linear-ticket`.

## Process

### 1. Confirm the destination

Use `linear-ticket`'s explicit team/project selection and confirmation procedure before analysing or drafting. Never infer the destination for this workflow. Every ticket in the run uses that confirmed destination unless the user restarts selection.

### 2. Resolve the source, context, and existing tickets

Resolve exactly one **primary source** for scope, in this order:

1. An explicit source supplied with the invocation or explicitly designated by the user for this run: a file, issue identifier or URL, or pasted plan/spec. Fetch and read the full body and comments of a referenced issue.
2. Otherwise, the most recent settled plan or spec in the current conversation. If it points to an artifact, fetch and read that artifact fully.
3. Otherwise, root `PLAN.md`, when present; read it fully.
4. Otherwise, stop and ask the user for the source.

An explicit source wins even when `PLAN.md` exists. State which source was selected. Do not merge multiple plausible sources into new scope; ask when source selection is ambiguous or when a contradiction materially changes the intended outcome.

Treat `CONTEXT.md`, applicable `AGENTS.md`, referenced sources, relevant ADRs, designs, code, and tests as supporting context. Read them when they affect ticket accuracy. `CONTEXT.md` is authoritative for domain language, boundaries, and durable decisions, but supporting context never silently expands the primary source.

Pass the primary source and stable reference to `linear-ticket` for provenance handling.

For broad work, use subagents for bounded, independent, read-only exploration such as separate module investigations, prior-art searches, or overlap checks. Continue other independent analysis while they work, then reconcile every result before drafting. The primary agent owns source selection, the complete proposal, user approval, and every Linear mutation; never create or edit Linear items concurrently through subagents.

After destination confirmation, apply `linear-ticket`'s scoped inventory and overlap review across the entire source before slicing. Reuse matching milestones and covered issues; present narrowed or omitted overlaps in the complete proposal. Apply its estimate discovery while drafting, keeping writes deferred until publication approval.

### 3. Draft milestones and tracer-bullet tickets

Draft each slice through `linear-ticket`, including Human and prefactoring work.

Look for necessary prefactoring before slicing and place qualifying outcomes before the slices they enable, using `linear-ticket`'s scope rules.

Plan milestone membership and numbering through `linear-ticket` and its [numbering reference](../linear-ticket/references/issue-numbering.md). Order the complete milestone set chronologically and topologically, with prerequisite milestones earlier. Apply the numbering rules to existing items included in an approved insertion or renumbering too.

Topologically order the complete proposal using `linear-ticket`'s prerequisite rules. Treat all milestones as one graph: a ticket becomes actionable when its own blockers finish, even while earlier milestones have open work. Identify the unblocked execution **frontier** for concurrent agents. For wide mechanical refactors that cannot land green as vertical slices, use ordered expand–migrate–contract tickets.

### 4. Review with the user

Present the selected primary source and the complete proposal in milestone order. For each milestone show existing/new status; for each ticket show title, existing/new status, blockers, opening user story, delivered outcome, acceptance criteria, executor (`Agent` or `Human`), labels, and source provenance. Include the proposed estimate and brief rationale for every new or edited ticket, explicitly identifying changes to existing estimates and any provisional scale assumption. Explicitly show omitted or narrowed overlaps and the initial frontier of independent agent tickets.

Ask the user to approve milestone names/order, ticket order, granularity, user stories, dependencies, overlap decisions, criteria, labels, applicable estimates, provenance, and parallel frontier. Do not publish until explicitly approved.

### 5. Publish and verify

Immediately before publication, refresh the complete scoped inventory and reconcile new overlaps and occupied numbers through `linear-ticket`. Create missing milestones in approved chronological order, preserving reused milestone names unless their changes were approved. Publish missing tickets through `linear-ticket`, milestone-by-milestone and ascending by title number, passing Backlog as the required initial state, all approved fields and per-issue mutations. Leave reused issues without approved edits untouched.

After every issue exists, perform `linear-ticket`'s separate native relation pass across the complete approved graph. Include every new issue and every reused issue with approved relation changes. Reconcile and verify all direct edges, including cross-milestone dependencies, against the full proposal.

Use Linear's native milestone/issue reordering capability when available. Otherwise creation order plus numeric titles is the source of truth; verify the returned order and clearly report any manual Linear reorder still required. Never invent milestone target dates merely to force ordering.

Apply `linear-ticket`'s saved-field, estimate, description and numbering verification to every new or approved edited issue. Re-read saved milestone names and verify the complete order against the approved proposal; surface unapproved legacy conflicts. Correct in-scope mismatches before reporting publication results and unresolved failures.

End with plain text `Milestone order: <first> → <second> → <third>` followed by issue identifiers/URLs in that same milestone and ascending-number order. Then write `Parallel frontier: <issues>` listing unblocked `Agent` tickets that separate agents can implement concurrently, or `Parallel frontier: none`.
