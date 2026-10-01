---
name: complete-work
description: Implement the work supplied alongside this skill on a new branch, commit incrementally, verify the result, push and open a GitHub PR, then use finish-pr to complete review and CI. Use for requests to take new work through the full branch-to-PR workflow.
---

# Complete Work

Take the task supplied with this invocation from a new branch through a verified implementation and a completed PR review cycle.

## 1. Establish scope and create a branch

Recover the requested work and acceptance criteria from the accompanying instructions and conversation. Read applicable `AGENTS.md` files and repository requirements. If no task was supplied, ask for it before creating a branch.

If an issue with performing the task requires decisions from the user—such as material ambiguity, conflicting requirements, unresolved tradeoffs, or implementation risk—invoke `$grilling` and complete its interview before creating the branch or beginning implementation. Proceed only after the user confirms the shared understanding. This is a conditional aid, not a mandatory phase: skip it when the request and acceptance criteria are clear and executable, and handle purely operational blockers through the normal workflow.

Inspect the worktree, current branch, and remotes. Preserve pre-existing changes and exclude unrelated commits from the new branch and PR. Identify the remote for the intended base repository and discover that repository's default branch from GitHub metadata or its remote HEAD (`git ls-remote --symref <base-remote> HEAD`). Fetch the default branch and create a new, descriptively named branch with `--no-track` directly from that freshly fetched commit before editing. The branch name must begin with `agent/`, for example `agent/add-login-validation`; follow repository naming conventions for the suffix and use the discovered default branch as the PR base. Verify that the new branch's initial HEAD matches the fetched default-branch commit; do not branch from a stale local copy of the default branch or the current feature branch. If the remote or default branch is ambiguous, the default branch is missing, or fetching fails, stop and report the blocker. Use an isolated worktree when needed to preserve existing work.

Confirm that the `create-pr` and `finish-pr` skills are available and GitHub CLI authentication supports the target repository. If a prerequisite is missing, report it explicitly rather than silently dropping a required phase.

Before editing, identify the push remote for the intended head repository (which may differ from the base repository for a fork), then create the same-named remote branch with `git push --set-upstream <head-remote> HEAD:refs/heads/<branch-name>`. Verify that `git rev-parse --abbrev-ref "@{upstream}"` resolves to `<head-remote>/<branch-name>` and compare the SHA returned by `git ls-remote --exit-code --heads <head-remote> refs/heads/<branch-name>` with `git rev-parse HEAD` to verify the remote branch matches local HEAD. Branch setup is complete only when both branches exist with the same name and the local branch tracks that remote branch. If publishing or verification fails, stop and report the blocker.

## 2. Implement and commit incrementally

Implement the supplied task, keeping changes within its scope. Commit at meaningful checkpoints as coherent pieces are completed and verified; do not defer all commits until the end of a multi-step task. A small task may need only one commit. Stage only the changes belonging to this task, inspect each staged diff, and use descriptive commit messages.

Before publishing implementation commits, review the complete diff against the intended base and verify every acceptance criterion. Run the relevant tests and repository-required checks, fix failures caused by the work, and inspect for accidental changes or omissions. Proceed when the implementation is complete, relevant verification passes, and all task changes are committed. Report any blocker or unavailable verification accurately.

## 3. Push and open the PR

Push the completed commits without force using the explicit destination `git push <head-remote> HEAD:refs/heads/<branch-name>`. Before writing the PR body, read and follow `test-changes` to produce the manual verification handoff for the completed work. Then load and follow `$create-pr` ([SKILL.md](../create-pr/SKILL.md)) to create or reuse the PR against the intended base, using its template selection, categorisation, and submission verification rules. Supply the task intent, final diff, verification results, base/head repositories and branches, and full handoff. Always include that handoff in a `## Test changes` section, appended after the template when it has no suitable section.

An invocation requesting this workflow authorizes its commits, push, PR creation, and review replies; carry those steps through without redundant confirmation.

## 4. Complete the PR with finish-pr

Load and follow `$finish-pr` for the newly created PR in the same run. Carry forward the task intent, decisions, verification, and known limitations. Continue through its conflict, CI, feedback, and review-convergence workflow until its definition of done is met or one of its stopping conditions applies. Creating the PR alone does not complete this workflow.

Leave the PR open for the user to merge unless merging was separately requested. Report the PR URL, a concise change and verification summary, and any remaining blocker or pending required check, using `finish-pr`'s final audit as the source of truth.
