---
name: plan-cycle
description: Fill the next Linear cycle or top up the current cycle with a realistic, dependency-aware workload from an existing project backlog.
---

# Plan Cycle

Select existing Linear issues for a manageable cycle outcome, accounting for AI-assisted implementation, human review and verification. Support two modes:

- **Fill next:** plan the next cycle within the requested work budget, retaining existing commitments.
- **Top up current:** add work for the time remaining in the current cycle after accounting for unfinished commitments. Finishing early does not reset the time budget.

## Resolve the destination and budget

1. Resolve the Linear account/workspace, team and authorized project scope from explicit instructions, then unambiguous conversation context. Verify those identities through the Linear MCP. Repository metadata can help disambiguate; it does not authorize a different project. Reuse a destination already established in the conversation. Ask only for missing or ambiguous choices, including the account when several connections could match.
2. Resolve the requested mode and actual native cycle. Inspect its dates in the team's timezone and distinguish the current cycle from the next one. When no suitable cycle exists, report that gap; creating cycles or changing team cadence requires a separate instruction. A one-week workload does not authorize shortening a longer cycle.
3. Read the cycle's existing issues across the team, following pagination. Account for work from other projects and relevant assignees that consumes the requested person's or team's capacity; other people's work is not automatically the user's commitment. Preserve that work.
4. Use the requested availability and AI assistance, existing commitments, remaining working days, and comparable completed-cycle history to estimate available capacity. Without an established budget, state an initial assumption of one person working five days, roughly 35–40 hours per week with AI assistance, scaled to the actual remaining working time. Reserve room for review, CI and rework; parallel agents do not multiply human review capacity.
5. Infer each team's estimate convention from connector-exposed settings and issue estimate values/labels. Use defensible existing estimates alongside actual scope and observed throughput. Points are complexity measures, not hours; keep different teams' scales separate. With no useful history, disclose the initial capacity assumption rather than claiming calibrated velocity. Plan missing estimates from full scope, including implementation, verification and uncertainty; reassess existing estimates only when requested. Use connector data without browser automation or a complete settings/inheritance audit. No estimate examples does not mean estimates are off: with no exposed scale, provisionally size work on Fibonacci values (1, 2, 3, 5, 8), declaring that assumption until an authorized native write and read-back reveal the team's convention.

Completion: the destination, native cycle, mode, existing workload and remaining budget are known well enough to select work. Carry out independent reads while resolving any genuinely missing choice; do not guess a mutation target.

## Select a complete, achievable outcome

Read the authorized project's open backlog, following pagination, then the full requirements and relevant repository context for candidate issues. Inspect native blockers and their actual state; title numbers and milestone order are not dependencies.

Choose a coherent first outcome and enough complete PR-sized tasks to fit the remaining budget. Prefer the critical path and work that unlocks useful parallel progress. Independent research can accompany implementation when it advances that outcome. Account for implementation, verification, review and uncertainty, rather than filling the cycle with every unblocked ticket.

For every selected issue, establish that each incomplete prerequisite is:

- already committed to the chosen cycle; or
- selected within the same budget and authorized project scope.

Confirm that an apparently finished prerequisite actually satisfies the requirement; cancellation or duplication alone does not prove delivery. Read an out-of-project blocker when necessary, but obtain authorization before scheduling work outside the chosen scope. If a prerequisite cannot be satisfied within the cycle, choose a smaller complete outcome or explain the constraint.

Keep credential, physical-device, owner-approval and unavailable-environment dependencies visible. Include human prerequisites only when they are realistically achievable within the budget. Shared files and merge conflicts do not justify additional blockers or serializing independent tasks.

For **top up current**, select only the incremental work that fits after unfinished work and remaining review obligations. Keep completed work in its cycle for history. Do not remove or reshuffle existing commitments to make room without instruction. Optional stretch work stays outside the committed cycle unless requested.

Completion: every selected issue has a justified place in the budget and every unsatisfied blocker is covered. Identify what can start together and what becomes ready later, without adding artificial phase gates.

## Apply and verify

A request to fill or top up authorizes adding the selected existing issues and assigning their missing estimates. State the intended outcome, workload, proposed estimates and material capacity assumptions before writing; do not add another approval round when that action is already authorized. A request for suggestions or a proposal remains read-only, including estimate discovery: defer write attempts until application is authorized.

Immediately before writing, refresh cycle membership and selected issue state. Skip issues already in the cycle, completed, or otherwise no longer eligible; do not silently move an issue from another cycle. Reconcile changed commitments within the same budget or report why the plan can no longer be applied safely.

Use the native cycle field to add each selected issue. For missing estimates or explicitly requested reassessments, attempt the planned native estimate even when no project issue is estimated. Re-read the saved value/label, infer the team's convention and adjust if needed before estimating subsequent issues. A successful read-back establishes that value, not the full allowed range. If a correction materially changes the proposed workload, rebudget before adding more work.

Only an explicit disabled-estimation rejection means estimates are off: record it for that team and continue cycle planning without estimate writes. Invalid-value errors inform scale correction; permission, transport and unrelated failures are operation problems, not disabled estimates. Re-read uncertain writes before retrying. If an estimate error rejected a combined cycle write, verify membership and apply the authorized cycle change separately. Report unresolved estimate-write problems; missing settings alone must not block scheduling. Never enable estimates or change team settings.

Preserve existing estimates unless reassessment was requested, and preserve titles, descriptions, labels, assignees, delegates, milestones, priorities and blocker relationships. Scheduling does not authorize creating tickets, assigning workers or rewriting dependencies. Record automatic service-side changes, such as Backlog becoming Todo, rather than claiming all metadata stayed unchanged.

Re-read the cycle and every affected issue. Verify exact membership, destination, estimates and preserved metadata, including native prerequisites. Follow pagination and account for relation-list truncation; a partial relationship view does not establish an empty blocker set. If a write fails, inspect actual membership before retrying and report any partial result. Stop once the selected set is verified or a concrete capacity/access constraint prevents further safe additions.

## Report

Give the cycle name/number and local dates, fill/top-up mode, added issue links, estimate totals by team/scale when meaningful, capacity assumption and delivered-outcome goal. Report assigned/reassessed estimates and rationale, any provisional scale assumption or estimate error. Identify the initial parallel frontier and subsequent dependency order. State automatic status changes, any partial result or remaining constraint, and leave implementation to a separate request. Keep the report concise; do not create repository planning artifacts unless requested.
