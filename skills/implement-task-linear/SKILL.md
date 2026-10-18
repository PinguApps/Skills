---
name: implement-task-linear
description: Implement one Linear issue through complete-work's branch-to-PR workflow, with upfront clarification, collaborative delivery, and its originating repository context.
disable-model-invocation: true
---

# Implement Task from Linear

Implement exactly one Linear issue. The issue is the required input and scope boundary; its provenance chain and repository context refine how to implement it without silently adding work.

Use this skill as a Linear-specific wrapper around [$complete-work](../complete-work/SKILL.md). Read that skill before planning delivery; it owns branch setup, incremental commits, verification, push, PR creation through `create-pr`, and review/CI convergence through `finish-pr`. If it or a required dependency is unavailable, report the missing prerequisite and resolve it before implementation rather than substituting a partial workflow. Invoking this skill authorizes that full workflow; leave merging, deployment, and release to a separate user request.

Begin with a few short, precise bullets explaining the intended discovery and delivery before taking action. Steps 1–3 are read-only discovery and clarification: use them to produce an informed plan before branch creation, repository edits, or Linear mutations.

## 1. Resolve the target and Linear boundary

Require an unambiguous Linear issue identifier or URL. Ask for one when absent.

Fetch the target's full description, status, labels, team, project, relation identifiers, comments, and requirement-bearing attachments. Record its exact team ID and project ID. If it has no project, ask the user to assign it or authorize assignment to a named project before inspecting surrounding Linear work.

After resolving the target, apply this boundary to every other Linear issue read or mutation:

- query with both recorded IDs, then verify both IDs on every result;
- discover parents, sub-issues, blockers, duplicates, and related issues through scoped queries rather than directly fetching an unverified identifier;
- treat a cross-scope relation as unavailable context and report only its existence;
- create issues only with both recorded IDs.

Resolve the team's relevant workflow states, especially In Progress, In Review, Backlog, and any blocked state, by ID. Report ambiguity instead of guessing.

Use the Linear connector for estimate discovery and writes; do not use browser automation or require team-settings access. Infer the team's convention from available settings, the target's estimate value/label, and comparable issues within the recorded team/project boundary. Enough evidence to choose an appropriate value is sufficient; a complete scale or inherited-settings audit is unnecessary. Missing estimates do not mean estimation is disabled.

Before creating or editing a ticket, including status changes and related follow-ups, assess its full scope: implementation, verification, complexity and uncertainty. Retain an existing estimate only when defensible. Save the assessed estimate in the native field on each ticket authorized for mutation and re-read it to verify. If the project has no estimate examples or exposed scale, provisionally size the actual work on Fibonacci values (1, 2, 3, 5, 8), disclose that assumption and still attempt the write. Use the returned value/label to infer the team's scale, adjust if needed and apply that convention to subsequent work. A successful read-back establishes the saved value, not the team's entire allowed range; a comment alone is insufficient.

If Linear explicitly rejects estimation as disabled, record that result for the team and continue without estimate writes; do not enable it. An invalid-value error instead informs scale correction. Permission, transport or unrelated validation failures are access/operation problems, not evidence that estimates are off. Re-read after an uncertain write before retrying. Missing settings alone must not block implementation or routine status changes; report any unresolved estimate-write problem separately.

This step is complete when the target, acceptance criteria, team/project IDs, and usable workflow states are known.

## 2. Follow the provenance chain

Determine the repository root and read every applicable `AGENTS.md` before other repository work.

Then resolve context in this order. Each source is optional unless the target explicitly depends on it:

1. **Originating spec** — follow every explicit `Source` path or URL, spec link, design link, or requirement-bearing attachment in the target. When `to-linear` represented the spec as a native parent, find that parent through a team-and-project-scoped query, verify both IDs, then read its full description and comments. If no provenance is recorded, search `docs/`, `specs/`, and `.scratch/` for a single clear match to the target title, source name, or feature slug; ask before choosing among plausible matches. Inspect in-scope parents, blockers, milestone or cycle neighbours, and overlapping issues when they can clarify intent, dependencies, or drift.
2. **Plan** — read root `PLAN.md` fully when it exists. Use it for the larger outcome, sequencing, dependencies, and the target's place in the plan.
3. **Domain context** — read root `CONTEXT.md` fully when it exists. Also read root `CONTEXT-MAP.md` fully when it exists and follow every context entry applicable to the target. Context files define project language and domain boundaries, not implementation scope.
4. **Decisions** — read applicable ADRs under root `docs/adr/` and any context-specific `docs/adr/`. Follow pertinent artifact pointers from the selected spec, plan, context files, ADRs, and current conversation.
5. **Repository truth** — inspect the implicated code, tests, documentation, schemas, migrations, generated artifacts, configuration, and git status. Preserve unrelated user changes.

The prerequisite skills may leave different parts of this chain:

- `grill-with-docs` may leave `CONTEXT.md`, `CONTEXT-MAP.md`, and ADRs;
- `to-spec` publishes implementation decisions, agreed testing seams, and out-of-scope boundaries in an originating tracker issue;
- `to-linear` carries that origin into the target through a native parent or `Source` reference and may copy durable constraints into `Context`.

Missing optional artifacts do not block implementation. Explicit pointers do require resolution: read them, or report why they are unavailable.

Use this evidence hierarchy:

- the target issue defines the deliverable and acceptance criteria;
- the originating spec and `PLAN.md` explain intent, sequencing, and exclusions without expanding the target;
- context files and ADRs constrain vocabulary, boundaries, and durable decisions;
- the repository defines current implementation truth.

Surface material conflicts or stale evidence. Ask only when a conflict changes the intended behaviour, public interface, compatibility, or scope.

This step is complete when every explicit provenance pointer is resolved or reported unavailable, every applicable context artifact is read, and every target requirement is classified as implemented, partial, missing, contradicted, or blocked.

## 3. Clarify and plan the delivery

Before implementation, give the user a very short overview in plain-language bullets covering:

- the concrete outcome and surfaces that will change;
- the small delivery steps and how each will be checked, including the agreed public testing seams or highest existing seams that fit;
- material assumptions, tradeoffs, context gaps, or drift found during discovery;
- anything needed from the user, followed by the planned commits, PR, and CI/review completion through `complete-work`.

Keep the overview quick to scan; name consulted sources briefly and expand only where a decision needs explanation. Resolve material uncertainty about requirements, behaviour, scope, compatibility, or public interfaces with the user before branch creation or implementation. Use `complete-work`'s conditional `$grilling` interview when such decisions require it, carrying forward answers already given. A clear, executable task needs the overview but no redundant approval pause.

Map every acceptance criterion and durable constraint to an implementation change or concrete verification. Existing behaviour counts only after verification. If choosing a seam would create or materially change a public interface, confirm it with the user when the upstream artifacts did not already settle it.

This step is complete when the user has received the overview, every acceptance criterion has a delivery and verification path, and every material question has been answered.

## 4. Deliver through complete-work

Invoke `$complete-work` with the target's full requirements, original user story when available, acceptance criteria, provenance, durable constraints, agreed plan, testing seams, and user decisions. Follow its complete workflow, including `create-pr`'s user story requirement, rather than maintaining a separate Git or PR procedure here. Its branch setup follows the read-only discovery and clarification above; reconcile the plan against the freshly fetched base before editing, and resolve any new material uncertainty with the user.

Move the target to the resolved In Progress state when implementation starts, unless it is already further along or the user asked to preserve its status. Apply the estimate and team/project rules to this and every later Linear mutation.

Within `complete-work`, implement in verified vertical slices, working red then green at the agreed public seams for testable behaviour. Include required documentation, schemas, migrations, generated artifacts, and configuration. Before its PR-publication gate, audit the complete diff against repository standards, applicable ADRs, every target criterion, and originating-spec constraints; fix findings and rerun affected checks. Required target work stays in this change.

### Collaborate when user input is needed

Continue autonomously whenever available tools, access, and settled requirements allow it. When progress needs a user decision, credential, permission, account setup, or other prerequisite, ask promptly and explain:

- what is implemented and verified so far, with an inspectable artifact, screenshot, or preview when useful;
- exactly what is missing and which remaining behaviour or check it blocks;
- how to supply or obtain it; for setup or access, include a direct service/account link, the relevant settings location, and the minimum necessary steps;
- where to configure it, including the exact environment-variable or secret name and target environment when applicable;
- what the user should confirm when done and what work will resume afterward.

Check available authenticated tools and existing configuration before asking the user to do manual setup. Verify current setup instructions against the relevant service's documentation rather than inventing account navigation. Have credentials configured through the appropriate secret store or local environment instead of asking for secret values in chat or committing them.

For example, a working UI may be ready to inspect while live data remains blocked on an API key. Show the UI, identify the unverified integration, and give the service link and configuration steps. Continue independent work while awaiting the user; pause dependent work until the input arrives, then verify the prerequisite and resume. An elapsed wait is not an answer. `complete-work`'s completeness gate still applies: partial implementation or mock data cannot justify publishing a PR for an incomplete target.

## 5. Reconcile Linear and hand off

After `complete-work` reaches its final audit or stopping condition, re-fetch the target and every mutated related issue, then reconfirm the team/project boundary.

When every required outcome is implemented and verified and the PR exists:

1. Add a concise target comment linking the PR and mapping each acceptance criterion to implementation and verification evidence, including any pending CI or review blocker reported by `finish-pr`.
2. Move the target to In Review only when its current state is earlier.

Preserve completed, cancelled, archived, In Review, and other terminal or further-along states. When implementation or required verification is blocked, leave the target In Progress or use the resolved blocked state and record the unmet criterion, evidence, and dependency. Distinguish implementation readiness from incomplete PR review or CI; report full workflow completion only when `finish-pr`'s definition of done is met.

## Related Linear work

The user authorizes minimal related-issue mutations inside the recorded team/project boundary when implementation evidence justifies them.

Create a follow-up only when it is concrete, independently actionable, genuinely outside the target, and absent after a scoped overlap search. Create it in the same team/project, normally in Backlog, with observable acceptance criteria and a native relation to the target when supported. A prerequisite that blocks completion must be related and reported as a blocker rather than used to declare the target complete.

Before naming or creating a follow-up, read and apply [Linear milestone and issue numbering](../to-linear/references/issue-numbering.md). Assign its native milestone and matching `MM-DDD - Issue title`, accounting for existing numbers. Obtain approval for any required milestone creation or existing-name/title changes; preserve the target's and related issues' titles during routine implementation, status and estimate updates. Re-read the saved follow-up title and milestone assignment to verify the prefix.

Update an existing related issue only when repository evidence makes its description, relations, or status stale. Before treating it as satisfied, read every acceptance criterion and verify complete coverage. Move it to In Review only from an earlier state; preserve terminal and further-along states. Partial or title-only overlap does not justify a transition.

## Handoff

Report:

- target identifier, URL, and final status;
- PR URL and `finish-pr`'s final audit, or the specific prerequisite blocking PR creation or workflow completion;
- implemented outcome and changed surfaces;
- verification commands and results;
- acceptance-criteria coverage;
- context sources used and unavailable explicit pointers;
- material drift or conflicts found;
- every related issue read that changed an implementation decision;
- every issue created or modified, with reason, status, and URL;
- the saved estimate and brief rationale for each created or modified issue, any provisional scale assumption, or the specific disabled/error result;
- blockers, limitations, and follow-up work.

Say explicitly when no related Linear issues changed.
