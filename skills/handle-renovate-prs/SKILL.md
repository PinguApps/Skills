---
name: handle-renovate-prs
description: Investigate, repair and finish one or more existing Renovate dependency-update PRs supplied for the current repository. Checks upgrade compatibility even when CI is green, uses finish-pr, and submits Pingu's requested approval only after the reviewed head passes CI.
---

# Handle Renovate PRs

Accept one or more PR numbers or URLs for the current repository and an optional
summary of merge concerns. Establish which concern applies to which PR. Treat the
summary as leads to verify against source and observed behaviour.

## Take ownership of the existing PRs

Verify each target's repository, open state, Renovate authorship, intended base,
head repository and branch, published SHA, dependency changes and reviewer
requests. Link the verified PRs to the T3 thread when supported. Use an isolated
worktree per PR, reusing an assigned clean checkout when it matches the intended
head. Fetch the base and exact head and verify where the head can be pushed,
including fork permissions. Keep each PR on its existing remote branch.
Check for existing auto-merge or queue enrollment before acting. If it can
merge outside this workflow's approval and final audit, reconcile it within the
user's authority or record the blocker before pushing or approving.

Work in dependency order where upgrades interact. Continue independent PRs when
one is blocked. After a related PR merges, refresh the affected bases and
reassess compatibility and checks for each remaining PR. Keep a resumable record
per PR with its current head, diagnosis, proof, merge policy and approval state.

## Diagnose and verify the upgrade

- Inspect the full diff, resolved versions and dependency graph, PR feedback
  and actual failing CI logs. Compare with the base when needed to distinguish
  upgrade regressions from pre-existing failures or infrastructure faults.
- Read upstream release notes and migration guidance across the effective
  version range. Trace affected APIs, configuration and defaults through their
  callers and deployment paths. Consider transitive constraints, target
  runtimes, build tools, persisted data and runtime behaviour where affected.
  A green suite still needs a focused check of material behaviour it misses.
- Reproduce reported or discovered problems when possible. Make the smallest
  compatible source, configuration, dependency or test changes on the existing
  head. Keep version changes within the intended upgrade. If the upgrade needs
  a separate rollout, an incompatible prerequisite or a product decision,
  record the evidence and surface the decision before widening the scope.
- Verify the actual resolved artifacts through affected builds, tests and real
  consumer or deployment paths in safe test resources. Update expectations only
  where the intended contract changed. Capture what ran, its result and the
  head it covers. If the upgrade is already sound, carry the evidence forward
  without creating a commit.

Commit verified fixes and push normally to the exact head branch after checking
its expected published SHA. If Renovate or another actor changes that head,
reconcile the new diff and reverify affected behaviour before publishing.
Use [complete-work's continuation contract](../complete-work/SKILL.md#continuation-and-stopping-contract)
for blockers and resumptions. These PRs are already published, so use
finish-pr's post-publication workflow for convergence.

## Finish and approve

Run [finish-pr](../finish-pr/SKILL.md) for each PR with its verification evidence,
merge policy and, under automatic policy, this section as its caller-supplied
approval step. The authorized reviewer for that step is Pingu's GitHub account
`pingu2k4` (user ID `11229848`). A personal-review request, no-merge instruction
or manual handoff retains the manual policy. Under manual policy, complete
authorized repairs and verification, leave the PR open without submitting
approval, and report any review still due from Pingu.

At the approval step, require completed upgrade verification covering the exact
published head and applicable base. If existing evidence is for a different
head or base, assess the changes, rerun affected checks and record the proof
for the current revisions. Then confirm all applicable CI for that head is
green. Check required and other applicable checks, with skips accepted only
under the repository's success semantics. Pending, failing or unverified CI
keeps the approval pending.

Verify that the submitting GitHub identity matches the authorized reviewer
above.
Verify its review request or effective current-head approval. If a prior
submission by this run fulfilled the request, retain the original request as
evidence of reviewer assignment while that assignment still applies. Reuse an
approval only if it remains effective and its commit equals the verified head.
Otherwise submit a new approval bound to the verified SHA. With the
GitHub connector, verify its authenticated profile and pass the SHA as
`commit_id` to the approval operation. Read back the submitted approval,
reviewer, commit and effective review state. If identity, authority, eligibility,
the review request or commit-bound submission cannot be verified, report the
exact approval blocker. Code-owner and latest-push requirements still apply.

After approval, resume finish-pr's final audit and protected merge. A changed
head invalidates this workflow's approval evidence. Reassess, recheck CI and
obtain an effective approval for the new head before merging. Use finish-pr's
expected-head guard with automatic merge on future pushes disabled. Report each
PR's verified outcome, proof, approval and merge SHA or specific remaining blocker.
