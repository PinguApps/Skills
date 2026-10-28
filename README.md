# Skills

Opinionated skills I use in my setup each day.

## Review model decision — 2026-10-28

This dated decision records the review mix, reasons and cost baseline for future
reassessment. The executable source of truth is
[review-policy.json](skills/complete-work/references/review-policy.json); the
[shared review procedure](skills/complete-work/references/pre-pr-review.md)
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

## Skills

### [complete-work](skills/complete-work/)

Takes supplied work through committed implementation, pre-PR review and protected
PR completion. An explicit human-review or no-merge hold leaves the PR open.

The skill:

- Discovers and fetches the repository's default branch, then creates an `agent/` branch from that commit.
- Implements the task with incremental commits and relevant verification.
- Uses root and nested `.pragentignore` rules before reading review content.
- Counts documentation (including JSON) separately from code and assigns the
  deterministic OpenRouter reviewer pair in its shared review policy.
- Owns fresh T3/OpenCode reviewer children, incremental rechecks and cleanup.
- Records tokens and costs per review round in the PR body.
- Opens the PR only after review coverage is satisfied, then uses `finish-pr`
  for CI and incoming comments, merging by default when permitted.

### [loop-work](skills/loop-work/)

Loops through a Linear team's project backlog using isolated T3 worker threads and
`complete-work`, merging verified PRs and reassessing newly unblocked work.

The skill:

- Requires the Linear team/project, parallel thread limit, and ticket limit (or no max).
- Controls each worker's worktree, result delivery, repair and shutdown through T3.
- Supports concurrency beyond native subagent slots; accepts the old limit parameter as an alias.
- Selects independently actionable tickets that need no user input.
- Uses fixed `agent/` branches derived from Linear and limits outstanding reservations.
- Leaves In Review and Done transitions to verified GitHub–Linear automation.
- Allocates reviewer capacity and verifies worker-owned merges; the coordinator
  does not merge PRs itself. Human-review holds propagate to workers.
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
  Copilot threads after a clean current-head re-review with recorded evidence.
- Treats an explicit Copilot quota response as review completion; it does not
  pretend the code was reviewed or erase earlier findings.
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
- Moves every supplied issue to In Progress when implementation starts and In Review
  when the complete PR is created, preserving terminal and further-along states.
- Includes every supplied issue in PR closing references for automatic linking and
  closure on merge through the existing GitHub–Linear integration.
- Restricts related Linear access and mutations to each issue's exact team and project.
- Creates or updates related issues when justified, including moving fully covered
  issues to In Review.
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
