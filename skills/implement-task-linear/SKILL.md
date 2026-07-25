---
name: implement-task-linear
description: >-
  Implement a Linear issue end to end in the current repository: load the issue,
  inspect same-team-and-project context, reconcile Linear with the codebase, make
  and verify the required changes, and update or create tightly related Linear
  issues when justified.
compatibility: Requires a connected Linear MCP server and repository read/write tools.
disable-model-invocation: true
---

# Implement Task from Linear

Implement one Linear issue completely. Treat the issue as the source of its requested outcome, root project context as the larger product picture, and the repository as the source of current implementation truth.

## Non-negotiable scope boundary

The target issue defines the only permitted Linear scope:

- Read the explicitly supplied target issue to discover its team and project.
- Record the target's exact team ID and project ID.
- After that initial lookup, read or mutate an issue only after confirming that **both** IDs match.
- Discover every non-target issue through a Linear query constrained by both recorded IDs. Do not directly fetch an unverified related identifier.
- Apply the same check to search results, parent/sub-issues, blockers, duplicates, related issues, and newly created issues.
- Prefer server-side team and project filters, then verify every returned issue before using it.
- Do not follow an out-of-scope issue even when the target links to it. Mention only that an inaccessible cross-scope relation exists, without reading it.
- Do not list, inspect, search, create, or modify issues in another team or project.

If the target has no project, stop and ask the user to assign it to a project or authorize assigning it to a named project. Do not inspect surrounding issues until the scope has both IDs.

The repository is not restricted by this Linear boundary; inspect and change the current repository as required by the target issue.

## 1. Resolve the issue

Accept an issue identifier supplied with the invocation or in the conversation, such as `ABC-123`. If there is no unambiguous identifier, ask for it and wait.

Use the Linear MCP server in the same style as `to-linear`:

1. Fetch the target issue, including its full description, status, labels, project, team, parent, sub-issues, and native relations when available.
2. Establish the exact team/project scope described above.
3. Fetch comments or attachments on the target only when they may contain requirements or decisions.
4. Resolve the team's relevant workflow states, especially In Progress, In Review, and Backlog, by ID. If a required state is ambiguous or missing, report that rather than guessing.

Do not begin repository changes until the target and its acceptance criteria are understood.

## 2. Establish repository truth

Determine the repository root and read the applicable `AGENTS.md` files first.

Then check for `PLAN.md` and `CONTEXT.md` in the repository root. If either exists, read it **fully** before analysing or changing code:

- Treat `CONTEXT.md` as authoritative for domain language, boundaries, constraints, and durable decisions.
- Use `PLAN.md` to understand the target's larger outcome, intended sequencing, dependencies, and relationship to surrounding work.
- Trace the target issue against both documents. Surface material omissions, contradictions, or signs that Linear or the documents are stale.
- Do not silently choose between conflicting issue, plan, context, and repository evidence. Ask the user when the conflict changes the implementation or intended outcome.
- Do not automatically implement all work described in `PLAN.md`. Use it to implement the target coherently and to identify scoped related issues or follow-up work.

The presence of either file is significant; never skip it because the Linear issue appears self-contained.

Inspect the repository narrowly but deeply enough to understand:

- existing architecture and conventions;
- code, tests, documentation, migrations, and configuration implicated by the issue;
- current git status, preserving unrelated user changes;
- existing behaviour corresponding to every requirement and acceptance criterion.

Potentially inspect surrounding Linear issues when they can clarify intent, prevent duplicate work, reveal dependencies, or explain apparent drift. Search only within the recorded team and project. Useful context includes nearby milestone/cycle work, parent/sub-issues, blockers, blocked issues, and issues with overlapping domain terms.

Do not assume Linear or the repository is current. Compare them explicitly and classify relevant requirements as:

- already implemented and verified;
- partially implemented;
- missing;
- contradicted by repository evidence;
- blocked by a decision or dependency.

Ask the user only when a material ambiguity cannot be resolved from scoped Linear context or repository evidence.

## 3. Plan for complete delivery

Before editing, give the user:

- assumptions and any drift between Linear, `PLAN.md`, `CONTEXT.md`, and the repository;
- a short implementation plan with a verification check for each step;
- any material scope or compatibility tradeoff.

Map every acceptance criterion and durable requirement to an implementation change or a concrete verification. Existing implementation counts only after verification.

Move the target to the resolved In Progress state when work actually starts, unless it is already further along or the user asked not to change statuses. Report the transition.

## 4. Implement

Implement the minimum coherent change that satisfies the entire target issue:

- follow repository conventions and keep edits surgical;
- include tests that reproduce changed behaviour where practical;
- update required documentation, schemas, migrations, generated artifacts, or configuration;
- do not turn required current-task work into a follow-up merely to reduce scope;
- preserve unrelated work and do not commit, push, open a PR, deploy, or release unless the user asks.

Loop through implementation and verification until all acceptance criteria pass or a genuine blocker remains. Run the smallest relevant checks first, then the broader checks justified by risk.

## 5. Manage related Linear work when justified

The user authorizes necessary related-issue mutations without a separate approval step, but only inside the recorded team/project scope. Keep them minimal, evidence-based, and visible in the final report.

### Create a follow-up issue

Create a scoped follow-up when repository work reveals a concrete, actionable problem that:

- is genuinely separate from the target's required outcome;
- should be deferred rather than silently expanded into the current change; and
- is not already covered by a scoped issue after an overlap search.

Create it in the same team and project, normally in the resolved Backlog state. Give it a focused title, description, observable acceptance criteria, relevant context, and native relation to the target when supported. Do not create speculative cleanup, vague ideas, or tasks required to claim the target is complete.

If an unavoidable prerequisite blocks the target and cannot responsibly be implemented now, create or update the scoped prerequisite issue, relate it natively, and report the target as blocked rather than complete.

### Update an existing related issue

Modify a scoped related issue when the implementation produces reliable evidence that its description, relations, or status is now stale. Keep the change limited to that evidence; do not rewrite unrelated scope.

When the current implementation also satisfies another scoped issue:

1. Read that issue fully and verify every acceptance criterion against the repository.
2. Confirm its team and project IDs still match the target.
3. Add a concise cross-reference or relation to the implemented target when supported.
4. Move it to the resolved In Review state, never directly to Done.
5. Record the issue identifier, evidence, and transition in the final response.

Do not transition an issue merely because its title appears similar. Partial coverage should be documented or narrowed only when evidence supports the edit; otherwise leave its status unchanged.

## 6. Reconcile and report

Before declaring completion:

1. Re-fetch the target and every mutated related issue.
2. Reconfirm the team/project boundary.
3. Verify repository changes and test results against each target acceptance criterion.
4. Move the target to In Review only when all required work is implemented and verified. Otherwise leave it In Progress, or use a resolved blocked state if appropriate, and explain why.
5. Correct any Linear mutation mismatch before reporting.

End with a concise handoff containing:

- target issue identifier, final status, and URL;
- implemented outcome;
- verification commands and results;
- acceptance-criteria coverage;
- drift discovered between Linear, `PLAN.md`, `CONTEXT.md`, and the repository;
- every related issue read that materially changed the implementation decision;
- every issue created or modified, with reason, status, and URL;
- remaining blockers or follow-up work.

Say explicitly when no related Linear issues were changed.
