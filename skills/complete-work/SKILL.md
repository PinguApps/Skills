---
name: complete-work
description: Implement supplied work in an isolated branch/worktree, commit coherent chunks, verify and review it through OpenRouter before opening a PR, then finish CI/feedback and merge unless human review or a manual handoff was requested.
---

# Complete Work

Take the supplied task through implementation, pre-PR review, PR completion and permitted merge. Capture `merge policy: automatic` by default, or `manual` for any user-requested human review/no-merge handoff. Preserve that choice across child tasks, resumes and the PR body; a manual hold never expires merely because checks pass.

## 1. Establish scope and create a branch

Recover the requested work and acceptance criteria from the accompanying instructions and conversation. When the supplied work is a Linear issue or ticket, read its full requirements and acceptance criteria, including referenced material needed to establish scope; a title or summary alone is insufficient. Without a Linear ticket, use the complete user request and conversation as the scope. Read applicable `AGENTS.md` files and repository requirements. If no task was supplied, ask for it before creating a branch.

If an issue with performing the task requires decisions from the user—such as material ambiguity, conflicting requirements, unresolved tradeoffs, or implementation risk—invoke `$grilling` and complete its interview before creating the branch or beginning implementation. Proceed only after the user confirms the shared understanding. This is a conditional aid, not a mandatory phase: skip it when the request and acceptance criteria are clear and executable, and handle purely operational blockers through the normal workflow.

Inspect the current worktree, branch and remotes. Continue an explicitly assigned task worktree/branch after verifying its ownership and base; do not create another checkout or branch. Otherwise create an isolated worktree and descriptive `agent/` branch directly from the freshly fetched intended default branch, using `--no-track`. Discover the base repository/default branch from metadata rather than assuming origin/main. Preserve unrelated changes/commits and verify a newly created branch starts at the fetched base. An ambiguous repository, base, ownership or failed fetch is a blocker.

Confirm that the `create-pr` and `finish-pr` skills are available and GitHub CLI authentication supports the target repository. If a prerequisite is missing, report it explicitly rather than silently dropping a required phase.

Before editing, identify the push remote for the intended head repository (which may differ from the base repository for a fork), then create the same-named remote branch with `git push --set-upstream <head-remote> HEAD:refs/heads/<branch-name>`. Verify that `git rev-parse --abbrev-ref "@{upstream}"` resolves to `<head-remote>/<branch-name>` and compare the SHA returned by `git ls-remote --exit-code --heads <head-remote> refs/heads/<branch-name>` with `git rev-parse HEAD` to verify the remote branch matches local HEAD. Branch setup is complete only when both branches exist with the same name and the local branch tracks that remote branch. If publishing or verification fails, stop and report the blocker.

## 2. Implement and commit incrementally

Implement the supplied task, keeping changes within its scope. Commit at meaningful checkpoints as coherent pieces are completed and verified; do not defer all commits until the end of a multi-step task. A small task may need only one commit. Stage only the changes belonging to this task, inspect each staged diff, and use descriptive commit messages.

Maintain the concise [review context](../create-pr/references/review-context.md) from the settled task: requirements, decisions, exclusions and verification evidence. Carry it through PR creation and `finish-pr`; use it to expose requirement gaps rather than restating the whole conversation.

Choose actual verification using [review-work's proof requirements](../review-work/references/proof.md), including real consumer/deployment paths and browser exercises where applicable. Keep the observed evidence for the PR handoff. The implementation agent owns execution in its authorized test environment; source-only reviewers do not execute reviewed code. Passing AI review does not replace tests or real integration evidence.

Before publishing implementation commits, review the complete diff against the intended base. Account for every requirement and acceptance criterion in the supplied Linear ticket, or every part of the user request when no Linear ticket was supplied, with the implementation and verification evidence that satisfies it. Run the relevant tests and repository-required checks, fix failures caused by the work, and inspect for accidental changes or omissions.

Advance to step 3 only when the work fully satisfies that scope, relevant verification passes, and all task changes are committed. Complete any remaining work within scope before proceeding. If required information, access, decisions, or verification are missing, explain the specific gap and ask the user for what is needed; wait for it before advancing. Reporting a blocker or limitation does not satisfy this gate. Do not create or reuse a PR for partial work, including a draft PR: proceeding to PR creation is your assertion that everything requested is accounted for and complete.

## 3. Complete pre-PR review

Invoke [$review-work](../review-work/SKILL.md) once with the completed task, actual worktree, committed range, requirements and verification. It is the source of truth for observed proof, pre-PR reviewers, routing, incremental fixes, accounting and child cleanup. Return to this workflow only with its complete coverage receipt, proof record and rendered report; do not duplicate its review loop here.

Do not publish a PR until that handoff satisfies the task. Preserve proof, round-by-round accounting, final reviewed scope, evidence-backed dispositions and merge policy for the next steps.

## 4. Push and open the PR

Push the completed commits without force using the explicit destination `git push <head-remote> HEAD:refs/heads/<branch-name>`. Before writing the PR body, read and follow `test-changes` to produce the manual verification handoff for the completed work. Then load and follow `$create-pr` ([SKILL.md](../create-pr/SKILL.md)) to create or reuse the PR against the intended base, using its Linear ticket title-prefix, template selection, categorisation, brief plain-language user story, and submission verification rules. Ensure the story is understandable to readers without a technical background, including when adapting an original story. Supply the task intent, original user story when available, identifiers of Linear tickets that informed the task and which the PR fully completes, final diff, verification results, base/head repositories and branches, and full handoff. Always include that handoff in a literal `## Test changes` section: use that section when the template already contains it, otherwise append it after the template even if another testing section exists.

An invocation requesting this workflow authorizes its scoped commits, pre-PR review calls, push, PR creation, feedback replies and normal protected merge, unless the user requested a manual/human-review handoff or a narrower restriction applies. Carry authorized steps through without redundant confirmation.

## 5. Complete the PR with finish-pr

Load and follow `$finish-pr` for the newly created PR in the same run. Carry forward the task intent, decisions, verification, and known limitations. Continue through its conflict, CI, feedback, and review-convergence workflow until its definition of done is met or one of its stopping conditions applies. Creating the PR alone does not complete this workflow.

Pass the merge policy explicitly. `finish-pr` handles post-publication fixes without additional delegated AI review rounds. Under automatic policy it merges only after its complete current-head gate passes, respecting protections/queues and verifying the merge. Under manual policy it leaves the ready PR unmerged. Report the verified outcome, PR URL, proof, review costs and any blocker; never count queue admission as a completed merge.
