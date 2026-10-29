---
name: review-work
description: Review completed work before PR publication with two scoped OpenRouter reviewers, observed proof, incremental fixes and per-model accounting. Use after ad hoc implementation or from delivery skills; stop at the review handoff.
---

# Review Work

Review the work already completed in this conversation. This skill owns the
pre-PR review process; it does not create a branch, push, open a PR, monitor GitHub
or merge. Delivery skills call it once and resume their own workflow afterwards.
An explicitly read-only review returns findings without modifying source; it may
run non-destructive checks and inspect a running app within the supplied test environment.

## Establish the change and proof

Recover the task's requirements, decisions and verification from the conversation,
including work done without a delivery skill. Verify the actual assigned worktree,
branch, intended base and task diff; preserve unrelated changes. Resolve an
ambiguous base or task boundary before dispatch. Commit authorized task work in
coherent chunks before reviewing its snapshot; do not manufacture a new checkout
or one combined commit merely to run this skill.

Read [Proof](references/proof.md) and gather the most direct observed evidence for
the change. Keep proof separate from future manual-test instructions and source
review verdicts. Missing meaningful proof requires the specific user input or
access needed to obtain it, rather than an approval claim.

Prepare the [runtime-check handoff](references/runtime-checks.md): give reviewers
a short account of the verification destined for the PR, with commands, expected
results, environment/setup details and explicit safety restrictions. Full reviews
exercise relevant executable behaviour independently; incremental reviews rerun
only checks needed for the changed behaviour or an open finding.

## Run the review

Read and follow [the review procedure](references/pre-pr-review.md). It owns
ignore filtering, code/documentation sizing, deterministic/mixed categories,
model assignments, independent T3/OpenCode dispatch, incremental fixes, round
caps, usage and child cleanup. Read its linked runtime instructions before
dispatch. All scripts, tests and policy resources belong to this skill.

Use the actual worktree and a committed snapshot. Validate findings, fix confirmed
issues within the authorized task, commit coherent fixes and rerun affected
proof. Later rounds cover only the new changes plus necessary context. The parent
owns reviewer sessions, accounting and settling/cancelling children. One clean
round is sufficient; the procedure's caps and explicit blockers still apply.

## Hand off

Return the final coverage receipt, observed proof, finding dispositions and
rendered AI review report. Preserve full SHAs and model IDs in machine records;
human-facing reports use short linked commits and model names without routing
prefixes. Include per-round outcome/time and full/incremental scope, collapsed
round details, and visible per-model totals with honest accounting limitations.

Stop at this handoff when invoked alone. A caller may continue through `create-pr`
using these artifacts, with the proof in `## Proof`, manual instructions in
`## Test changes` and accounting in `## AI review`. Preserve any manual merge hold.
Post-publication fixes remain `finish-pr` work and do not restart paid reviews.
