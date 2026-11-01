# Skills

Opinionated skills I use in my setup each day.

Use [review-work](skills/review-work/SKILL.md) to review completed work even when
the conversation did not start with a delivery skill. It owns observed proof,
pre-PR model reviews and accounting; delivery skills call the same process.
PRs keep proof separate from manual tests, with collapsed round details and
visible per-model totals. Standalone review stops before push/PR/merge.

## Review model decision — 2026-11-01

Use OpenCode through T3 for every review. **Haiku uses OpenRouter; every other
accepted reviewer uses OpenCode Go.** The executable source of truth is
[review-policy.json](skills/review-work/references/review-policy.json).
Keep exactly two distinct initial reviewers covering the complete included diff;
use additional models only for a concrete unresolved concern. No GLM-5.2,
Google/Gemini model, Sonnet, Step, GPT or free alias has an assignment or fallback.

Names below are abbreviated: DeepSeek is V4.1 Flash, MiMo is V2.6 Flash, GLM is
5.3 Flash, MiniMax is M3.1 Flash, Haiku is 5.5, Kimi Code is K2.7 Code, Kimi Pro is
K3.1 Pro and Qwen is 3.8 Max. Go uses its published DeepSeek ID without OpenRouter's
`1017` suffix; verify the live catalogue rather than assuming identical revisions.

| Category | Scope | Initial reviewers | Conditional escalation sequence |
| --- | --- | --- | --- |
| Agent policy/skills/tool permissions | Every size | Haiku high + GLM high | Kimi Code default, then Qwen medium |
| Compatibility/APIs/dependencies/builds/CI/deployment | Small/standard code | DeepSeek high + MiMo default | GLM high, then Qwen medium |
| Compatibility/APIs/dependencies/builds/CI/deployment | Large/very large code | MiMo default + GLM high | Kimi Code default, then Qwen medium |
| Documentation | Small/standard | DeepSeek high + Haiku medium | GLM high, then MiMo default |
| Documentation | Large | Haiku medium + GLM high | MiMo default |
| General implementation | Small/standard code | DeepSeek high + MiMo default | Kimi Code default, then Qwen medium |
| General implementation | Large/very large code | DeepSeek high + GLM high | Kimi Code default, then Qwen medium |
| Security/auth/permissions/secrets | Small/standard code | Haiku high + MiMo default | GLM high, then Qwen medium |
| Security/auth/permissions/secrets | Large/very large code | Haiku high + MiniMax high | GLM high, then Qwen medium |
| State/persistence/migrations/concurrency/retries | Every size | DeepSeek high + MiniMax high | Kimi Code default, then Kimi Pro high |
| UI/Blazor/navigation/forms/accessibility | Every size | MiMo default + MiniMax medium | Visual: Kimi Code default; logic: Kimi Pro high |

MiMo and Kimi Code expose no selectable Go variant: `default` means clear inherited
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
leads remain Haiku for security/documentation, DeepSeek for state/general, MiMo
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

The 30–31 October sample had 48 reviewed PRs and 117 reviewer runs. Replaying its
tokens/caching across 30 active days projects $10 Go + $18.90 Haiku + $1.04
OpenRouter credit-purchase fee, **about $29.94/month before tax**, versus $59.82
for all-OpenRouter usage. Routine Go use projects to 75–88% of its monthly pool,
depending on DeepSeek peak pricing. At 20 active days the hybrid estimate is $23.29.
These are forecasts from partial published accounting, not a spending guarantee
or evidence of equivalent behaviour across providers. They include the full monthly
fee; per-review attribution leaves the unused share of that fee unreported.

Reserve at most eight additional percentage points of shared monthly Go allowance
for new-specialist trials/escalations, not eight points per model. Consult actual
usage/headroom and all three quota windows before dispatch. Never enable Extra
Usage or silently fall back to non-Haiku OpenRouter calls. Unavailable quota blocks
an unsettled review; it never supplies approval. Future runs reassess actual token
consumption, valid findings, false positives, guard compliance and latency before
promoting new defaults. The original measured decision is retained below.

<details>
<summary>Historical review model decision — 2026-10-28 (superseded)</summary>

## Review model decision — 2026-10-28

This dated decision records the review mix, reasons and cost baseline for future
reassessment. The executable source of truth is
[review-policy.json](skills/review-work/references/review-policy.json); the
[shared review procedure](skills/review-work/references/pre-pr-review.md)
defines classification, mixed areas, review rounds and accounting. Update this
snapshot when changing that policy, and preserve dated decisions below it.

Use exactly **two distinct initial reviewers**, independently reviewing the full
included diff. Default to inexpensive pairs; use GLM and MiniMax where their
capabilities add a useful angle. Expensive models handle focused escalations.
All calls use OpenCode through OpenRouter without a hosting-provider pin. No GPT
models. Ling was removed because its measured review took about 24 minutes while
the other models finished within 10 minutes.

Names are shortened in the table. MiMo means MiMo V2.6 Flash, DeepSeek means
DeepSeek V4.1 Flash 1017, GLM means GLM 5.3 Flash, MiniMax means MiniMax M3.1 Flash,
Haiku/Sonnet mean version 5.5, Kimi means K3.1 Pro and Step means Step 5 Preview.
MiMo uses its thinking setting; other efforts are medium or high as shown.

| Category | Scope | Initial reviewers | Review angles | Escalation sequence |
| --- | --- | --- | --- | --- |
| Documentation | Small/standard | DeepSeek high and Haiku medium | Technical accuracy; clear, consistent explanations | GLM high, then MiMo thinking |
| Documentation | Large | Haiku medium and GLM high | Clarity; consistency across a large document set | MiMo thinking |
| General code | Small/standard | DeepSeek high and MiMo thinking | Correctness; execution paths and regressions | Haiku high, then Sonnet high |
| General code | Large/very large | DeepSeek high and GLM high | Correctness; long-context dependencies | Haiku high, then Sonnet high |
| Compatibility/dependencies | Small/standard | DeepSeek high and MiMo thinking | Consumer behaviour; contract and deployment regressions | Haiku high, then Sonnet high |
| Compatibility/dependencies | Large/very large | MiMo thinking and GLM high | Multi-step behaviour; cross-file contract consistency | Haiku high, then Sonnet high |
| Security/auth/permissions | Small/standard code | Haiku high and MiMo thinking | Intended permission boundaries; adversarial execution paths | MiniMax high, then Sonnet high |
| Security/auth/permissions | Large/very large code | Haiku high and MiniMax high | Permission boundaries; cybersecurity and failure paths | MiMo thinking, then Sonnet high |
| State/persistence/concurrency | Every size | DeepSeek high and MiniMax high | State invariants; failure, recovery and concurrency | Haiku high, then Kimi high |
| Agent instructions/skills/workflow policy | Functional changes, every size | Haiku high and GLM high | Instruction clarity; multi-step workflow consistency | MiMo thinking, then Sonnet high |
| UI/Blazor | Every size | MiMo thinking and MiniMax medium | Component/interaction state; frontend and accessibility semantics | Haiku high, then Kimi high |

Integration checks belong to the same initial pair. Large/very-large code changes
that alter runtime/public contracts across services or packages can escalate an
unresolved integration concern to Step medium. It is not a third automatic initial
reviewer. Escalation chains are conditional: use the finding's category, skip
models already called on that revision, and stop when the concern is settled.

Code bands require both limits: small 500 changed lines/10 files, standard
4,000/60, large 10,000/120, then very large. Documentation bands are small
2,000/30, standard 20,000/150, then large. Additions plus deletions count. Markdown
and JSON are documentation for size only: functional agent instructions and auth
JSON still receive their behavioural risk categories. Apply root and nested
`.pragentignore` before reading or counting review content; assess media/binaries
and add justified exclusions there. One clean round is enough; caps remain three,
or five for security/state, with incremental rechecks and parent-verified minor fixes.

### Mixed-category selection

Map independent areas explicitly using repeatable `--area category=path-prefix`
arguments to the scope helper. Choose the two largest substantial categories and
one lead from each: **Haiku for documentation, DeepSeek for general code, MiMo for
compatibility, GLM for agent policy, MiniMax for UI**. Both reviewers still cover
the full diff, all checklists and interactions. Other areas retain their
checklists/escalation chains. Duplicate leads use the second category's other
assigned model, keeping exactly two distinct models.

Each selected area must represent at least 20% of review work and contain at least
100 changed code lines, 250 documentation lines, or five files. Review work is
code lines + 0.5 × documentation lines + 20 × files. These weights select mixtures
only; code/documentation size bands remain separate. Without two substantial
areas, use the primary category's full pair. Security or state anywhere retains
the highest-priority protected category's full pair, regardless of area shares.

For example, substantial UI and documentation uses **MiniMax medium and Haiku
medium**. Documentation findings escalate to GLM high; UI findings escalate to
Kimi high because Haiku already reviewed. Cross-category findings use the
highest-risk affected category's chain. Classification and area shares come from
the full task range, even when a later review reads only incremental fixes.

### Evidence and cost baseline

The assignments are informed by OpenRouter's descriptions, not proven category
winners. [GLM](https://openrouter.ai/z-ai/glm-5.3-flash) highlights efficient
coding, long-context behaviour and long-horizon agent tasks.
[MiniMax](https://openrouter.ai/minimax/minimax-m3.1-flash) highlights cybersecurity,
real codebases and frontend work. [MiMo](https://openrouter.ai/xiaomi/mimo-v2.6-flash)
emphasizes coding and agentic workflows. The other models' details are linked in
the measured-cost table.

R1B measured each model against the same committed PR: 2,292 changed code lines
in 13 files plus 1,134 documentation/JSON lines in 13 files. Costs below are actual
captured OpenRouter usage totals for that review, including charged tool-loop
steps and compaction; they are not token list prices or average costs per PR.

Runtime calibration on the same date found that an 80% input ceiling alone was
insufficient: a long Haiku answer pushed its next native summary to 104,926 input
tokens. Current tier-priced calls use a 70% input ceiling, an 8,192-token output
cap and 12,000 source characters per step, retaining the original contract across
native summaries. Effort is unchanged. The R1B measurements below predate those
reserves; use the current runtime when benchmarking future replacements. These
remain estimated safety margins, not an exact tokenizer guarantee.

| Model | Measured effort | Measured review cost (USD) | Intended role |
| --- | --- | ---: | --- |
| [DeepSeek V4.1 Flash 1017](https://openrouter.ai/deepseek/deepseek-v4.1-flash-1017) | high | $0.029357 | Inexpensive correctness and regression coverage |
| MiMo V2.6 Flash | thinking | $0.038312 | Inexpensive independent execution-path review |
| [Haiku 5.5](https://openrouter.ai/anthropic/claude-haiku-5.5) | high | $0.059794 | Instructions, documentation and focused escalation |
| GLM 5.3 Flash | high | $0.069755 | Agent workflow and larger cross-file consistency reviews |
| MiniMax M3.1 Flash | high | $0.071041 | UI, state and focused security reviews |
| [Step 5 Preview](https://openrouter.ai/stepfun/step-5-preview) | medium | $0.325351 | Unresolved cross-component integration |
| [Kimi K3.1 Pro](https://openrouter.ai/moonshotai/kimi-k3.1-pro) | high | $0.628453 | Difficult state and UI escalations |
| [Sonnet 5.5](https://openrouter.ai/anthropic/claude-sonnet-5.5) | high | $0.649372 | Persistent correctness, security and workflow disputes |

The same 372 authored PRs across 27 repositories, created 2026-09-28 through
2026-10-27, project to **$26.03/month** with this policy, versus $28.66 for the
previous broader-pair proposal and $38.00 for the original routing. Cheaper pairs
without mixtures project to $25.58; mixtures add about $0.45 and occur in 33
metadata-classified candidate PRs. Initial assignments are DeepSeek 238, MiMo 270,
Haiku 145, GLM 61 and MiniMax 30: 744 assignments, two per PR. Previously GLM had
162 and MiniMax 64 assignments.

Forecast components are $20.66 initial reviews, $3.29 incremental rechecks,
$1.63 category escalations and $0.44 integration escalations (independent rounding
can differ from the unrounded total). The higher-use case is $30.02; broad workload
sensitivity gives $14.53–$68.07, not a confidence interval or spending cap.
The forecast excludes implementation/CI costs and historical bootstrap/benchmark
spend. It is not a promise of equal review quality or exact future billing.

Forecasting retained the previous per-category/size approval assumptions and
priced workload as code lines + half documentation lines + 20 per file, against
the measured PR's 3,379 work units with a 10% minimum per-call overhead. Rechecks
use 15%, 8%, 5%, then 3% of original variable work; escalations use 20%, integration
35%. Ten percent of first escalations need the next model; ten percent of eligible
integration cases need Step. Mixed escalation cost is distributed by selected
area shares. The higher-use case adds 25% more rechecks, 50% more first escalations
and 25% follow-through. Medium assignments conservatively retain measured high
cost where no separate medium measurement exists. Historical area classification
uses paths/metadata, not a retrospective source review; real tasks classify actual
behaviour. One measured PR per model cannot establish cost distributions or
category-specific detection rates.

### Reassessing this decision later

Start from this decision date and the current policy. Check
[OpenRouter's model catalogue](https://openrouter.ai/models) for releases since
that date, including successors to every retained model and promising models from
other labs. Recency alone does not justify a swap: compare code-review suitability,
supported effort/tool settings, context-price tiers, caching, observed latency and
actual review cost. Benchmark shortlisted replacements on a comparable filtered,
committed snapshot within the requested budget before adopting them. Retain native
harness compaction below pricing increases; do not assume old tiers still apply.
Update the policy, routing tests and README together after the new mix is agreed.
Preserve this dated matrix, measurements and rationale as a historical decision
when documenting its replacement; do not erase the comparison baseline.

</details>

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
