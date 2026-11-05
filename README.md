# Skills

Opinionated skills I use in my setup each day.

Use [review-work](skills/review-work/SKILL.md) to review completed work even when
the conversation did not start with a delivery skill. It owns observed proof,
pre-PR model reviews and accounting; delivery skills call the same process.
PRs keep proof separate from manual tests, with collapsed round details and
visible per-model totals. Standalone review stops before push/PR/merge.

## Review model decision — 2026-11-05

Use OpenCode through T3 for every review. **Every accepted reviewer uses OpenCode Go,
including Haiku.** The executable source of truth is
[review-policy.json](skills/review-work/references/review-policy.json).
Keep exactly two distinct initial reviewers covering the complete included diff;
use additional models only for a concrete unresolved concern. No GLM-5.2,
Google/Gemini model, Sonnet, Step, GPT or free alias has an assignment or fallback.

Names below are abbreviated: DeepSeek is V4.1 Flash, GLM is
5.3 Flash, MiniMax is M3.1 Flash, Haiku is 5.5, Kimi Code is K2.7 Code, Kimi Pro is
K3.1 Pro and Qwen is 3.8 Max. Go uses its published DeepSeek ID without OpenRouter's
`1017` suffix; verify the live catalogue rather than assuming identical revisions.

| Category | Scope | Initial reviewers | Conditional escalation sequence |
| --- | --- | --- | --- |
| Agent policy/skills/tool permissions | Every size | Haiku high + GLM high | Kimi Code default, then Qwen medium |
| Compatibility/APIs/dependencies/builds/CI/deployment | Small/standard code | DeepSeek high + GLM high | GLM high, then Qwen medium |
| Compatibility/APIs/dependencies/builds/CI/deployment | Large/very large code | DeepSeek high + GLM high | Kimi Code default, then Qwen medium |
| Documentation | Small/standard | DeepSeek high + Haiku medium | GLM high, then MiniMax high |
| Documentation | Large | Haiku medium + GLM high | MiniMax high |
| General implementation | Small/standard code | DeepSeek high + GLM high | Kimi Code default, then Qwen medium |
| General implementation | Large/very large code | DeepSeek high + GLM high | Kimi Code default, then Qwen medium |
| Security/auth/permissions/secrets | Small/standard code | Haiku high + MiniMax high | GLM high, then Qwen medium |
| Security/auth/permissions/secrets | Large/very large code | Haiku high + MiniMax high | GLM high, then Qwen medium |
| State/persistence/migrations/concurrency/retries | Every size | DeepSeek high + MiniMax high | Kimi Code default, then Kimi Pro high |
| UI/Blazor/navigation/forms/accessibility | Every size | DeepSeek high + MiniMax medium | Visual: Kimi Code default; logic: Kimi Pro high |

Kimi Code exposes no selectable Go variant: `default` means clear inherited
options, not disable reasoning or invent a `thinking` variant. The other named
efforts above are explicit. Catalogue support was checked with OpenCode 2.2.0.
Kimi Code and Qwen are new specialist assignments: run a small guarded trial before
their first live escalation, including image handling for Kimi's visual branch.
Vendor descriptions and token-price comparisons do not prove review quality.

Escalations use the finding's affected category and skip models already used on
that revision. UI visual and logic are alternative branches, not two extra
reviewers. Cross-boundary contracts receive integration checks from the same
initial pair and use the relevant category's escalation chain. Existing separate
code/documentation size bands, area-weighted mixtures, protected security/state
pairs, incremental coverage and three/five-round caps remain in force. Category
leads remain Haiku for security/documentation, DeepSeek for state/general, GLM
for compatibility, GLM for agent policy and MiniMax for UI.

### Usage and reporting

Keep the PR report's round headings, closed details, timing, scope tables and
visible per-model token/cost totals. The main cost column combines API cash charges
with Go's proportional subscription cost: **allowance used / $60 × $10** for the
current Go plan. Thus 1% of the monthly allowance reports $0.10. Unused allowance
stays unallocated; using 90% reports $9, without spreading the remaining $1 over
reviews. Record the fee/pool basis in each ledger; verify it again after a plan or
quota change. Use the provider's weighted `opencode.allowance`, not list prices or
rounded console percentages. This is cost attribution, not an extra cash charge.
Go reports use six decimal places so small model contributions remain visible.
Raw cash/list-price/allowance receipts remain unchanged, with audit tables collapsed
below totals. Preserve separate estimates and unavailable evidence. Top-up fees and
tax stay outside review costs; PRInspector parses the same main cost column.

The earlier hybrid-plan forecast was based on the $10 plan and separate Haiku API
charges. It does not describe the current $40 subscription or all-Go routing.
Historical reports retain their recorded plan basis and provider model IDs.

Reserve at most eight additional percentage points of shared monthly Go allowance
for new-specialist trials/escalations, not eight points per model. Consult actual
usage/headroom and all three quota windows before dispatch. Never enable Extra
Usage or silently fall back to OpenRouter calls. Unavailable quota blocks
an unsettled review; it never supplies approval. Future runs reassess actual token
consumption, valid findings, false positives, guard compliance and latency before
promoting new defaults. The superseded routing matrix and its workload forecast have been removed.

## Skills

### [complete-work](skills/complete-work/)

Takes supplied work through committed implementation, pre-PR review and protected
PR completion. An explicit human-review or no-merge hold leaves the PR open.

The skill:

- Discovers and fetches the repository's default branch, then creates an `agent/` branch from that commit.
- Implements the task with incremental commits and relevant verification.
- Uses root and nested `.pragentignore` rules before reading review content.
- Counts documentation (including JSON) separately from code and assigns the
  deterministic reviewer pair and provider in its shared review policy.
- Owns fresh T3/OpenCode reviewer children, incremental rechecks and cleanup.
- Records tokens and costs per review round in the PR body.
- Opens the PR only after review coverage is satisfied, then uses `finish-pr`
  for CI and incoming comments, merging by default when permitted.

### [loop-work](skills/loop-work/)

Loops through a Linear team's project backlog using isolated T3 child agents and
`complete-work`, merging verified PRs and reassessing newly unblocked work.

The skill:

- Requires the Linear team/project, parallel worker limit, and ticket limit (or no max).
- Controls each worker's worktree, result delivery, repair and shutdown through T3.
- Uses app-owned delegation: coordinator → implementation workers → reviewers.
- Counts implementation workers independently of their nested reviewers; accepts the old limit parameter as an alias.
- Selects independently actionable tickets that need no user input.
- Uses fixed `agent/` branches derived from Linear and limits outstanding reservations.
- Leaves In Review and Done transitions to verified GitHub–Linear automation.
- Requires workers to move their ticket to Pre-PR Review when local review starts.
- Verifies worker-owned merges and handles their PR-event waits; human-review
  holds propagate to workers. The coordinator does not merge PRs itself.
- Reassesses after merges and stops with a concise completion and blocker ledger.

### [create-pr](skills/create-pr/)

Creates a GitHub PR using the repository's template, including inherited templates,
or the standard categorisation and summary fallback.

The skill:

- Selects one change category and one release level in the standard checkbox block.
- Preserves template structure and appends additional verification or review sections.
- Starts the PR title with the IDs of Linear tickets that informed the task and
  are fully completed by the PR.
- Reuses an existing PR and verifies the saved title, description and target.

### [finish-pr](skills/finish-pr/)

Finishes the GitHub pull request attached to the current branch.

The skill:

- Resolves merge conflicts before diagnosing and fixing failed CI.
- Uses the current conversation and repository-native context to judge feedback.
- Actions unresolved review comments without duplicating an agent response that is
  awaiting reviewer follow-up.
- Preserves human-owned threads, verifies submitted replies, and can settle
  Copilot threads immediately after a submitted fix or evidence-backed explanation.
  Copilot review is one-time; no reply or re-review is expected.
- Treats an explicit Copilot quota response as review completion; it does not
  pretend the code was reviewed or erase earlier findings.
- Shares a [watch handoff](skills/finish-pr/references/watch-handoff.md) with
  coordinators: refresh state and require a race-free host subscription, or report
  the missing capability explicitly.
- Pushes focused fixes and completes CI/feedback without delegated post-PR review
  rounds. Merges when the protected gate passes, unless a human hold applies.

### [implement-task-linear](skills/implement-task-linear/)

Wraps `complete-work` to deliver one or more supplied Linear issues together in a
single PR through review and CI.

The skill:

- Accepts Linear issue identifiers or URLs, or asks for them.
- Gives a short bullet plan and resolves material questions before implementation.
- Follows the originating spec and reads optional `PLAN.md`, `CONTEXT.md`,
  `CONTEXT-MAP.md`, and applicable ADRs when present.
- Reconciles the issue, surrounding work, and repository state.
- Implements and verifies every requirement and acceptance criterion.
- Uses `complete-work` for branch setup, commits, PR creation, and review completion.
- Requests user help only when needed, with precise setup and resumption steps.
- Moves every supplied issue to In Progress when implementation starts and Pre-PR
  Review when local review starts; verifies automated In Review on PR creation,
  preserving terminal and further-along states.
- Includes every supplied issue in PR closing references for automatic linking and
  closure on merge through the existing GitHub–Linear integration.
- Restricts related Linear access and mutations to each issue's exact team and project.
- Creates or updates related issues when justified and links fully covered issues
  for automated review-state and completion transitions.
- Reports repository drift, verification results, and every Linear mutation.

### [linear-ticket](skills/linear-ticket/)

Creates or updates one Linear ticket, with shared rules used by the other Linear
workflows.

The skill:

- Owns ticket descriptions, milestone numbering, labels and native relations.
- Sizes work and verifies native estimates, including safe recovery from failed writes.
- Preserves each calling workflow's scope and authorization.
- Re-reads saved fields before reporting success.

### [plan-cycle](skills/plan-cycle/)

Fills the next Linear cycle or tops up the current cycle from an existing backlog.

The skill:

- Uses an explicit destination or derives an unambiguous one from the conversation.
- Includes Pingu's weekends and budgets AI-assisted work from recent cycles, current-cycle delivery over elapsed time, and unfinished commitments.
- Selects complete outcomes with real native dependencies and useful parallel work.
- Adds issues through the native cycle field and verifies membership and preserved metadata.

### [review-work](skills/review-work/)

Reviews already completed work before PR creation, including ad hoc conversation
work. The delivery workflows reference this skill as their review source of truth.

The skill:

- Manually moves associated In Progress tickets to Pre-PR Review before review
  starts, including standalone and delegated delivery workflows.
- Captures observed proof and distinguishes it from future manual-test instructions.
- Applies ignore policies and deterministic/mixed-category routing to two independent reviewers.
- Gives reviewers a concise verification/safety handoff and tools to run
  non-destructive checks and inspect apps while keeping source read-only.
- Owns incremental fixes, round caps, per-model usage/time and reviewer cleanup.
- Hands off coverage, proof and collapsed-round reporting without creating or merging a PR.

### [test-changes](skills/test-changes/)

Explains how to manually inspect and test the work just completed in the current
conversation.

The skill:

- Starts with what is already visible before asking you to run anything.
- Gives copyable PowerShell commands for any required setup or server.
- Maps every changed surface to exact actions, expected results, and failure signs.
- Separates confirmed state from inferred expectations and testing limitations.

### [to-linear](skills/to-linear/)

Turns a project's `PLAN.md` and supporting context into an ordered Linear
implementation backlog.

It is intended to be run after `grill-me` or `grill-with-docs` from Matt Pocock's
[skills](https://github.com/mattpocock/skills).

The skill:

- Confirms the target Linear team and project before planning.
- Reuses existing milestones and issues to avoid duplicate work.
- Drafts narrow, non-overlapping tickets grouped into ordered milestones.
- Names milestones `00 - Name`, `01 - Name` and issues `00-000 - Title`, `01-000 - Title`.
- Captures acceptance criteria, executor, labels, and native dependencies.
- Requires review and explicit approval before publishing.
- Uses `linear-ticket` to publish and verify individual tickets, then checks the full backlog order.

Based on Matt Pocock's [to-tickets](https://github.com/mattpocock/skills/tree/main/skills/engineering/to-tickets) skill.

### [to-spec-local](skills/to-spec-local/)

Wraps a separately installed `to-spec` skill to save a complete Markdown
specification in the current repository, ready to use as the primary source for
`to-linear`.

The skill:

- Reads the installed upstream skill; its source is intentionally not hosted here.
- Replaces tracker setup, issue publication and labels with in-repo file delivery.
- Reuses accepted testing seams and preserves the upstream specification template.
- Records complete scope and provenance without creating Linear issues.
