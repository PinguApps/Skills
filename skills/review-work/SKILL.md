---
name: review-work
description: Review completed work before PR publication with two scoped T3/OpenCode reviewers, observed proof, incremental fixes and per-model accounting. Route Haiku through OpenRouter and other policy models through OpenCode Go; return review artifacts to the caller, or hand off when invoked alone.
---

# Review Work

When called within implementation, read and apply complete-work's
[continuation and stopping contract](../complete-work/SKILL.md#continuation-and-stopping-contract).
Phase completion returns control to the caller for its next required action.

For any authorized PR feedback response, follow the shared
[Copilot policy](../finish-pr/references/copilot.md): submit the fix or an
evidence-backed explanation of why it cannot or should not be fixed, then resolve
the Copilot thread ourselves immediately. Treat its review as one-time; expect
no reply or re-review of our changes. This adds no GitHub write authority.

Review the work already completed in this conversation. This skill owns the
pre-PR review process; it does not create a branch, push, open a PR, monitor GitHub
or merge. Delivery skills call it once and resume their own workflow afterwards.
An explicitly read-only review returns findings without modifying source; it may
run non-destructive checks and inspect a running app within the supplied test environment.
Here read-only applies to source; the required Linear status transition still runs
unless the user explicitly forbids Linear changes or asks to preserve ticket status.

## Move implementation tickets to Pre-PR Review

Before ticket writes or review dispatch, check for an already published PR for
this task's exact head/base. If one exists, skip this pre-PR workflow and return
its URL and any Linear integration discrepancy to the delivery caller for
`finish-pr`, or report them when invoked alone. An open PR must never send a
ticket back to Pre-PR Review.

Associate only implementation tickets identified by the caller, conversation or
worker handoff; a search result alone does not authorize adding a ticket. At the
start of review, before gathering proof or dispatching reviewers, manually move
every associated implementation ticket from In Progress
to its team's Pre-PR Review state through the Linear MCP. Read and apply
[$linear-ticket](../linear-ticket/SKILL.md), verify each ticket's account/workspace,
team and project, and resolve the actual workflow state IDs. Refresh each ticket
before writing and read back the saved state before continuing. This authorizes
only that status transition; preserve estimates and other fields.

Apply this whether invoked alone, by a delivery skill or by a delegated worker.
The implementation/review parent owns the transition; reviewer children do not
write to Linear. Already Pre-PR Review is satisfied; preserve all other states,
including In Review, completed, cancelled and archived tickets. Report each ticket
skipped under explicit Linear read-only or status-preservation instructions and
the reason. With no associated ticket, continue without creating one. Missing or
ambiguous states, access or any unverified required write block this task's entire
pre-PR review; report the gap and retain saved states for a safe retry. Keep
transitioned tickets in Pre-PR Review through review fixes and rechecks. In Review
starts when the PR opens; leave that transition to the configured GitHub–Linear integration.

## Establish the change and proof

Recover the task's requirements, decisions and verification from the conversation,
including work done without a delivery skill. Verify the actual assigned worktree,
branch, intended base and task diff; preserve unrelated changes. Resolve an
ambiguous base or task boundary before dispatch. Commit authorized task work in
coherent chunks before reviewing its snapshot; do not manufacture a new checkout
or one combined commit merely to run this skill.

Read [Proof](references/proof.md) and gather the most direct observed evidence for
the change. Keep proof separate from future manual-test instructions and source
review verdicts. Gather missing proof through available checks/setup first; apply the continuation
contract when specific external input or access is still required.

Prepare the [runtime-check handoff](references/runtime-checks.md): give reviewers
a short account of the verification destined for the PR, with commands, expected
results, environment/setup details and explicit safety restrictions. Full reviews
exercise relevant executable behaviour independently; incremental reviews rerun
only checks needed for the changed behaviour or an open finding.

## Run the review

Read and follow [the review procedure](references/pre-pr-review.md). It owns
ignore filtering, code/documentation sizing, deterministic/mixed categories,
model assignments, independent T3/OpenCode dispatch, incremental fixes, round
caps, usage and child cleanup. Read its linked runtime instructions and [progress/recovery contract](references/review-liveness.md) before
dispatch. Cycle suspicions and interrupted operations require diagnosis and
cause-specific recovery, including eligible unused-model replacement. The parent
may classify INCOMPLETE only with verified evidence that required coverage remains
unobtainable after feasible recovery; telemetry alone never establishes a stall. All scripts, tests and policy resources belong to this skill.

Use the actual worktree and a committed snapshot. Validate findings, fix confirmed
issues within the authorized task, commit coherent fixes and rerun affected
proof. Later rounds cover only the new changes plus necessary context. The parent
owns reviewer sessions, accounting and settling/cancelling children. One clean
round is sufficient; the procedure's caps and explicit blockers still apply.

## Hand off

Return the final coverage receipt, observed proof, finding dispositions and
rendered AI review report. Preserve full SHAs and model IDs in machine records;
human-facing reports use short linked commits and model names without routing
prefixes. Preserve the cost/token table layout; combine API charges and proportional
Go subscription allocation using the recorded fee/monthly-allowance basis from
[the accounting procedure](references/pre-pr-review.md#usage-and-pr-handoff).
Retain raw receipts and distinguish allocation from extra cash charges.
Include per-round outcome/time and full/incremental scope, collapsed
round details, and visible per-model totals with honest accounting limitations.

Stop at this handoff when invoked alone. An implementation caller must consume
the receipt and continue through its next required action, including `create-pr`
using these artifacts, with the proof in `## Proof`, manual instructions in
`## Test changes` and accounting in `## AI review`. Preserve any manual merge hold.
Post-publication fixes remain `finish-pr` work and do not restart paid reviews.
