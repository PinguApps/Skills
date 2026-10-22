---
name: implement-task-linear
description: Implement one or more supplied Linear issues together in a single PR through complete-work, with per-issue state management and closing references.
disable-model-invocation: true
---

# Implement Task from Linear

Implement every supplied Linear issue together on one branch and in one PR. The supplied issues are the required input and combined scope boundary; each issue's provenance chain and repository context refine how to implement it without silently adding work. Complete all supplied issues before publishing the PR; a blocker on any target blocks publication of the combined change.

Use this skill as a Linear-specific wrapper around [$complete-work](../complete-work/SKILL.md). Read that skill before planning delivery; it owns branch setup, incremental commits, verification, push, PR creation through `create-pr`, and review/CI convergence through `finish-pr`. If it or a required dependency is unavailable, report the missing prerequisite and resolve it before implementation rather than substituting a partial workflow. Invoking this skill authorizes that full workflow; leave merging, deployment, and release to a separate user request.

Read and apply [$linear-ticket](../linear-ticket/SKILL.md) before any ticket draft or mutation. Pass each target's verified team/project boundary and this workflow's scoped authorization; it owns ticket content, numbering, metadata, estimates, native writes and read-back verification.

Begin with a few short, precise bullets explaining the intended discovery and delivery before taking action. Steps 1–3 are read-only discovery and clarification: use them to produce an informed plan before branch creation, repository edits, or Linear mutations.

## 1. Resolve the target and Linear boundary

Accept one or more unambiguous Linear issue identifiers or URLs. Ask for them when absent, resolve every supplied reference, and deduplicate references to the same issue. Keep a target ledger with each issue's identifier, URL, acceptance criteria, team/project IDs, workflow state IDs, estimate, implementation and verification coverage, and saved status. In the steps below, apply target-specific discovery and reconciliation to every issue in this ledger.

Fetch each target's full description, status, labels, team, project, relation identifiers, comments, and requirement-bearing attachments. Record its exact team ID and project ID. If it has no project, ask the user to assign it or authorize assignment to a named project before inspecting surrounding Linear work.

Explicitly supplied targets may have different teams or projects; keep their boundaries separate. For each target, apply its own boundary to every related Linear issue read or mutation:

- query with both recorded IDs, then verify both IDs on every result;
- discover parents, sub-issues, blockers, duplicates, and related issues through scoped queries rather than directly fetching an unverified identifier;
- treat a cross-scope relation as unavailable context and report only its existence;
- pass both recorded IDs to `linear-ticket` for authorized writes.

Resolve each target team's relevant workflow states, especially In Progress, In Review, Backlog, and any blocked state, by ID. Report ambiguity instead of guessing.

Use `linear-ticket`'s estimate discovery during this read-only phase. Carry the assessed estimates and rationale into every authorized target or related-issue update, including status changes.

This step is complete when every supplied target is recorded with its acceptance criteria, team/project IDs, and usable workflow states.

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

- the supplied target issues together define the deliverable and acceptance criteria;
- the originating spec and `PLAN.md` explain intent, sequencing, and exclusions without expanding the target;
- context files and ADRs constrain vocabulary, boundaries, and durable decisions;
- the repository defines current implementation truth.

Surface material conflicts or stale evidence. Ask only when a conflict changes the intended behaviour, public interface, compatibility, or scope.

This step is complete when every explicit provenance pointer for every target is resolved or reported unavailable, every applicable context artifact is read, and every target requirement is classified as implemented, partial, missing, contradicted, or blocked.

## 3. Clarify and plan the delivery

Before implementation, give the user a very short overview in plain-language bullets covering:

- the concrete outcome and surfaces that will change;
- the small delivery steps and how each will be checked, including the agreed public testing seams or highest existing seams that fit;
- material assumptions, tradeoffs, context gaps, or drift found during discovery;
- anything needed from the user, followed by the planned commits, PR, and CI/review completion through `complete-work`.

Keep the overview quick to scan; name consulted sources briefly and expand only where a decision needs explanation. Resolve material uncertainty about requirements, behaviour, scope, compatibility, or public interfaces with the user before branch creation or implementation. Use `complete-work`'s conditional `$grilling` interview when such decisions require it, carrying forward answers already given. A clear, executable task needs the overview but no redundant approval pause.

Map every acceptance criterion and durable constraint for every target to an implementation change or concrete verification. Plan dependencies and overlapping requirements across the supplied targets as one delivery. Confirm that the combined work can be delivered in one repository and PR; if it cannot, resolve that conflict with the user before implementation. Existing behaviour counts only after verification. If choosing a seam would create or materially change a public interface, confirm it with the user when the upstream artifacts did not already settle it.

Prepare the concise [review context](../create-pr/references/review-context.md) for that combined delivery. Carry every target's criterion coverage, settled tradeoffs and exclusions into `complete-work` and the PR, with short source links and enough meaning for PR Agent to assess intent without Linear access. Preserve the full target ledger separately; the PR brief should expose material constraints without copying all discovery notes.

This step is complete when the user has received the overview, every acceptance criterion has a delivery and verification path, and every material question has been answered.

## 4. Deliver through complete-work

Invoke `$complete-work` once for the combined scope, carrying every target's full requirements, original user story when available, acceptance criteria, provenance, durable constraints, agreed plan, testing seams, and user decisions. Follow its complete workflow, including [create-pr's user story rules](../create-pr/SKILL.md): require a brief story in everyday language that readers without a technical background can understand, adapting the original wording as needed. Keep Git and PR procedures in `complete-work`. Its branch setup follows the read-only discovery and clarification above; reconcile the plan against the freshly fetched base before editing, and resolve any new material uncertainty with the user.

When implementation of the combined work starts, move every target to its team's resolved In Progress state, unless it is already further along or the user asked to preserve its status. Do this for all targets at the start, including those scheduled for later slices. Perform this and every later ticket write through `linear-ticket`, then record its verified result or failure in the ledger.

Within `complete-work`, implement in verified vertical slices, working red then green at the agreed public seams for testable behaviour. Include required documentation, schemas, migrations, generated artifacts, and configuration. Before its PR-publication gate, audit the complete diff against repository standards, applicable ADRs, every criterion of every supplied target, and originating-spec constraints; fix findings and rerun affected checks. Required target work stays in this single change.

### Link every target and update review states at PR creation

Pass all target identifiers to `create-pr` and require a closing line in the PR description that mentions every supplied target, for example:

```text
Fixes ENG-123, ENG-124, ENG-125, ENG-126, and ENG-127
```

Use the actual identifiers from the ledger, including a single identifier for a single target. The existing GitHub–Linear integration uses these closing references to link the PR and close the tickets automatically when it merges; leave that integration configuration unchanged and leave tickets open until merge.

Immediately after the complete PR is created or reused, read back its saved description and verify that the closing references include every supplied target. Correct any omission, then run step 5's PR comment and In Review transitions for every target before continuing to `finish-pr`. Review or CI may still be pending at this point; their completion is not a prerequisite for these transitions.

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

Run this reconciliation at PR creation as directed above, and again after `complete-work` reaches its final audit or stopping condition. Re-fetch every target and every mutated related issue, then reconfirm each issue's team/project boundary. Reuse existing handoff comments and update them when evidence changes rather than duplicating them on the final pass.

When every required outcome across all supplied targets is implemented and verified and the shared PR exists, for each target:

1. Add or update a concise target comment linking the shared PR and mapping that target's acceptance criteria to implementation and verification evidence, including current CI/review status and any blocker reported by `finish-pr`.
2. Through `linear-ticket`, move the target to its team's resolved In Review state only when its current state is earlier, then record the verified result in the ledger.

Preserve completed, cancelled, archived, In Review, and other terminal or further-along states. When implementation or required verification is blocked for any target, keep the combined PR unpublished, leave started targets In Progress or use the resolved blocked state where applicable, and record the unmet criterion, evidence, and dependency. Distinguish implementation readiness from incomplete PR review or CI; report full workflow completion only when `finish-pr`'s definition of done is met. Leave completion transitions after merge to the configured GitHub–Linear automation.

## Related Linear work

The user authorizes minimal related-issue mutations inside the relevant target's recorded team/project boundary when implementation evidence justifies them.

Use `linear-ticket` for justified follow-up creation and evidence-backed related-issue updates, passing the originating target and its boundary. Its overlap, criteria-coverage, provenance, milestone/numbering, estimate and verification rules apply. This workflow authorizes minimal related edits and follow-ups outside all supplied targets; milestone creation and existing-name/title changes still require explicit approval. Required target work remains in the combined implementation, and unmet prerequisites remain blockers. Related issues verified as fully covered may move to In Review from an earlier state through the same ticket procedure.

## Handoff

Report:

- every supplied target's identifier, URL, and verified final status;
- the shared PR URL, verified closing references for all supplied targets, and `finish-pr`'s final audit, or the specific prerequisite blocking PR creation or workflow completion;
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
