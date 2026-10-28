# Review before PR publication

Read after implementation and relevant verification, before creating a PR. This
procedure is shared by `complete-work` and `create-pr`. It is not a new skill.
It runs only before initial PR publication: `finish-pr` never launches these AI
reviewers for subsequent CI or GitHub feedback fixes.

## Scope, policy and state

Use the implementation thread's **current worktree root**, not the project's main
checkout or Git common directory. Verify the absolute directory, branch, base SHA
and HEAD. Commit coherent verified chunks during implementation; a small task may
need one commit. Commit the completed change before dispatch and pause edits while
reviewers inspect that snapshot. Preserve unrelated work and stop if it cannot be
separated. Any uncommitted task work prevents publication.

Apply `pragent-ignore` when assessing generated outputs, media and binaries.
It is an externally installed skill, not authored in this repository; find it in
the runtime's skill catalogue. These shared instructions define source filtering.
Retain `.pragentignore`: root and nested policies at reviewed HEAD are the sole
source of exclusions. Assess candidates from metadata before loading content;
commit justified narrow rules with the artifacts. Do not silently exclude by
extension or copy `.gitignore` rules. Policies themselves always remain reviewable.

The [scope helper](../scripts/review_scope.py) uses Git's ignore parser in a
disposable policy-only repository. It handles case-sensitive matching, nested
precedence, `!` exceptions and excluded-parent semantics independently of personal
Git settings. Exclusions apply to both rename sides independently and to content
at every historical ref. Excluded reads are complete, not missing evidence.
Never read/search/diff ignored content through another tool. Existing findings
remain unresolved until there is evidence for their disposition.

Use an absolute Python 3 executable and helper path; resolve Git/OpenCode/gh to
absolute executables. Keep PATH and persistent environment settings unchanged.
Store manifests, briefs, findings, receipts and the usage ledger in one durable
run directory outside tracked files. Resume that state instead of resetting caps,
findings or costs. Keep merge policy there and in the PR body: `automatic` by
default; `manual` whenever the user requests human review, no merge, or a handoff.
Honour a repository restriction or narrower user grant.

```powershell
& <absolute-python> <absolute-skill>/scripts/review_scope.py `
  --repo <actual-worktree-root> --head <committed-head> scope `
  --base <task-merge-base> --category <category> --output <run-directory>/scope.json
```

Repeat `--category` for all applicable checklists. Select categories from actual
changed behaviour and requirements, not extension or title alone. JSON remains in
the documentation size bucket even when its contents change auth or deployment.
Code and JSON require explicit classification; the helper cannot infer behavioural
risk from size. Use repeatable `--path-prefix` values on `scope` for coherent
batches. Preserve the complete manifest and prove their union covers every selected
path; policy changes appear in every batch. Both assigned reviewers cover each batch.
For substantial independent areas, add repeatable `--area <category>=<path-prefix>`
arguments, for example `--area ui=src/Client --area documentation=docs`.
Use explicit file paths when a directory contains different behaviours. The longest
matching prefix wins; conflicting equally specific assignments fail. Unmapped
paths inherit the primary category. Area labels describe behaviour: a functional
skill or auth JSON is not ordinary documentation. Every selected path is counted
once, and excluded paths never contribute to a mixture.
Other text belongs to code. Media/binaries must be explicitly covered by ignore
rules before review; `needsExclusionAssessment` must be empty.

Use the policy in [review-policy.json](review-policy.json) as the single source
for models, effort variants, priority, size bands and caps. The helper selects the
first applicable risk category, with every applicable category retained as a
checklist and its own escalation chain. It may combine two substantial areas:

1. `security`: auth, permissions, tenancy, secrets and sensitive data.
2. `state`: persistence, schema/data migrations, transactions, concurrency,
   retries, idempotency and distributed state.
3. `compatibility`: public contracts, package/framework updates, managed skill
   refreshes, builds, CI and deployment.
4. `agent-policy`: skills, agent instructions, tool permissions and review rules.
5. `ui`: Blazor/components, lifecycle, navigation, forms, styling/accessibility.
6. `general`: remaining code changes.
7. `documentation`: documentation-only without a higher-risk category.

Code bands require both limits: small 500 lines/10 files, standard 4,000/60,
large 10,000/120, very large above either large limit. Documentation uses small
2,000/30, standard 20,000/150, then large. Count additions plus deletions after
exclusions. Never add documentation volume to code thresholds. Batch large scopes
by coherent areas. Only the policy's explicit size variants change the pair. Keep generated or
vendored text counted, but review provenance and real consumer compatibility when
those are its meaningful risks. No meaningful source is excluded merely for size.

Add `--cross-boundary-contract` only when the change alters a runtime/public
contract across services or packages. With a large/very-large code band, this adds
integration checks to the same two initial reviewers' briefs. Step medium is a
focused escalation for an unresolved cross-boundary concern, not an automatic third
initial reviewer. Pure documentation growth does not trigger it.

### Mixed categories

Exactly two distinct models initially review all included content. For a mixture,
each leads one selected category while both remain responsible for the complete
diff, all checklists and interactions. A UI/documentation mixture therefore uses
MiniMax medium and Haiku medium, not four reviewers or two disjoint partial reviews.

The helper requires explicit area mappings to prove a mixture. Each selected area
must represent at least 20% of review work and contain at least 100 changed code
lines, 250 changed documentation lines, or five files. Review work is code lines
plus half the documentation lines plus 20 per file. This weighting selects a
mixture only; code/documentation size bands remain independent and unweighted.
Choose the two largest qualifying areas, breaking ties by category priority.
Smaller areas retain their checklists and escalation chains. The policy specifies
each category's lead; if both leads use the same model, take the second category's
other assigned model so two distinct reviewers remain.

Any security or state checklist retains its full highest-priority protected pair,
regardless of documentation/UI volume. Both still cover other categories. Without
two substantial areas, use the primary category's complete pair. Variants use the
selected area's volume when mixed and the complete task volume otherwise.
Routing uses the full task range even for batches and incremental fix scopes;
a small recheck must not erase original responsibilities. Record area mappings,
shares, selected leads and exceptions in the receipt.

## Dispatch and own the reviewers

Before dispatch, read [the OpenCode runtime setup](review-runtime.md). Prepare its
worktree-local loader and verify it is loaded in that exact OpenCode location.
It supplies `pingu_review_source`, restricts owned review sessions to that reader,
removes ambient repository instruction text/attachments from model context, and
captures OpenRouter response usage without saving headers or response prose.
This is an application guard, not an operating-system sandbox; configuration and
other installed plugins remain trusted. Review metadata and transcripts before
accepting coverage. A failed guard or unavailable plugin is an operational blocker.

Discover T3 capabilities once before first delegation. Use `delegate_task`, role
`review`, shared isolation (the parent worktree), with OpenCode as the runner and
the exact policy `openrouter/...` model. Set `target.options.variant` explicitly.
MiMo uses `thinking`; all other assignments use only `medium` or `high`.
Never substitute GPT, free aliases, higher effort, or a different model silently.
OpenRouter chooses its hosting provider; do not pin/order upstream hosts. Verify
the effective variant/settings and no unexpected auxiliary model calls. Unsupported
settings or an unavailable assigned model are operational blockers, not approval.

Name every reviewer `R<n>: <model-short-name>`, for example `R1: Haiku`.
Keep model labels distinguishable. Task ownership belongs in the brief and ledger,
not the title. Titles never determine session correlation: each brief carries a
unique opaque `Review-Run-ID` marker.

Record launch intent/run ID before dispatch and retain task ID, child thread ID,
model, variant, round, scope/batch, reviewed range and returned link. Use a new
`delegate_task` for every review/re-check, never send follow-up review instructions
to an old child. Initial reviewers are independent and do not see each other's
findings. Supply the complete brief; children do not inherit the conversation.
Follow the task's returned `next`; async completion wakes the parent. Do not poll
running tasks. Under `loop-work`, acquire coordinator-allocated reviewer capacity;
queue reviews when capacity is occupied instead of exceeding the shared limit.
Before each new batch, re-prepare/reverify registration as required by the runtime
setup. Record completed task status, usage and child cleanup before refreshing.

The reviewer brief must contain:

```text
Review only. Do not edit, commit, push, comment on GitHub, start agents or watch PRs.
Review-Run-ID: <unique-marker>
Worktree: <absolute-current-worktree> Branch: <branch>
Task base: <base> Review range: <from>..<head> Head ignore policy: <head>
Intent/acceptance criteria: <complete concise review context>
Checklists: <primary and other applicable responsibilities>
Focus category: <assignment category>; both reviewers cover the full included diff.
Area map/escalations: <scope route areas and escalationByCategory>
Checks actually run: <evidence and limitations>
Allowed source access: use only pingu_review_source (diff/read/search).
Do not bypass exclusions using raw git diff/show, shell searches or file tools.
The runtime fixes the actual worktree, manifest, head and historical refs.
Review only this range, with unchanged context needed to understand its effects.
Find concrete scoped failures, broken callers and unmet requirements; avoid scope
creep and style-only churn. Do not inspect unrelated earlier reviewed changes.
Return APPROVE or CHANGES, and stable finding IDs with severity
(blocker/actionable/advisory), file:line, failure scenario, evidence and suggested
minimal fix. An excluded read is complete; omit claims needing excluded evidence.
```

The parent owns every child until cleanup. Collect results and usage, persist
their IDs and dispositions, ensure no live/queued work remains, then settle that
owned child with `t3_thread_organize`. Cancel obsolete/running tasks with
`task_cancel` and verify termination before settling. Settling is not cancellation.
Never touch unrelated threads. Reviewers never own fixes or PR lifecycle actions.
Read the complete tool transcript; a direct source-access bypass invalidates the
review and must be investigated. Retain guard/session/transport evidence. Review
changed ignore rules and their excluded path inventory before accepting any newly
hidden source; record the narrow artifact justification without opening it.
The manifest's `newExclusionsRequiringJustification` includes newly hidden paths,
including unchanged context files. Account for each rule/path group in the receipt;
an ignore edit cannot silently erase relevant source or an outstanding finding.

## Findings and incremental rounds

One clean round is enough. Caps are **three maximum**, or **five maximum** for
security/auth/permissions/data-loss/state/concurrency risks. Caps survive resumes;
exhaustion or a timeout never supplies approval. A round is one committed revision;
two reviewers on that revision are two runs, not two rounds. Integration and
escalation calls on the same revision belong to that round.

Validate findings against source and requirements. Fix confirmed scoped issues,
run appropriate checks, and commit coherent fixes. Record evidence-backed declines
and advisory dispositions; do not appease reviewers by expanding the task.
Escalate for a suspected serious failure, a
dispute remaining after one focused evidence check, or unresolved uncertainty.
Escalation gets the specific issue/range and evidence, not an automatic full rerun.
Classify the finding by affected behaviour, then use that category's ordered
`escalationByCategory` chain, skipping models already called on this revision.
For example, a documentation issue in a UI/documentation mixture goes to GLM;
a Blazor lifecycle issue goes to the UI chain (Kimi when Haiku already reviewed).
If one issue crosses categories, use the highest-risk applicable category's chain
and include the interaction evidence. Record the category and skipped models.
An exhausted chain/cap is a blocker, not approval; do not substitute another model.

For each returning reviewer, use its last covered SHA as `--previous` and the
original task base as `--base`. The next scope is previous SHA to current HEAD,
including just the new fix commits plus context/open findings needed to verify
them. Carry forward unchanged coverage; do not rediscover unrelated findings in
already-reviewed code. New reviewer assignments cover their assigned scope.
Policy inventory/content changes reset to the full task diff; rewritten ancestry
requires explicit coverage reconciliation, not an invented incremental baseline.

The parent may verify a small obvious fix directly (for example a typo) without
another model round. Judge by behaviour, risk and certainty, not line count alone;
small auth/config changes can be consequential. Record the minor delta's SHAs,
verification and why re-review adds no meaningful assurance. Substantial or
uncertain fixes need another affected review within the cap. Do not claim a model
approved a revision it did not see.

The final coverage receipt records base/head/policy digest, primary route and all
checklists, selected reviewers and covered ranges, parent-verified minor deltas,
finding dispositions, verification evidence, child cleanup and ledger location.
Publication requires complete scope coverage and no unresolved actionable finding.
If all changed content is explicitly excluded and no finding is outstanding, make
no model calls and record that result; policy files themselves still get reviewed.
Write this as `<run-directory>/coverage-receipt.json`. Include explicit per-run
IDs, model ranges, finding dispositions, verification and child cleanup. This is
the parent's evidence document, not a model-generated approval or a ledger reset.

## Usage and PR handoff

Use [review_usage.py](../scripts/review_usage.py) to maintain one run ledger:

```powershell
& <absolute-python> <absolute-skill>/scripts/review_usage.py --ledger <ledger> init `
  --repo <actual-worktree-root> --merge-policy automatic --scope <scope-json>
# The classified scope supplies its round cap; manual preserves a human hold.
& <absolute-python> <absolute-skill>/scripts/review_usage.py --ledger <ledger> record --run-file <run-json>
& <absolute-python> <absolute-skill>/scripts/review_usage.py --ledger <ledger> collect `
  --run-id <run-id> --opencode <absolute-opencode-executable> --task-state <saved-terminal-task-status-json>
& <absolute-python> <absolute-skill>/scripts/review_usage.py --ledger <ledger> render --output <summary-md>
```

Run JSON requires `id`, integer `round`, unique `marker`, exact policy `model`,
`effort`, `from` and `head`; runtime setup also needs `base`, absolute `scope`, a
durable external `briefFile` containing the complete review contract and
`title`. Add returned `taskId`/`threadId`, verdict and finding
evidence on completion. Session correlation requires the exact unique marker in
the first saved user message, never guessed titles/timestamps or a T3 thread ID used as
an OpenCode session ID. The helper reads session/message metadata without making
inference requests. For an ambiguous match, set `sessionID` only after verifying
the exact marker, transport binding and owned terminal child. Each retried launch
gets a fresh run ID/marker. Route/model/effort validation prevents substitutions;
an intentional benchmark requires a recorded `benchmarkAuthorization` reason and
explicit model-key/effort assignments. Preserve that exceptional grant in the PR.
Capture every charged step/retry/compaction, deduplicate IDs,
and detect unexpected auxiliary models. Do not double-count session totals and
message totals. OpenCode 2 stores visible output separately from reasoning; add
them once for its output total. OpenRouter completion tokens already include
reasoning. Input totals include cache tokens, which are also shown separately.

Use the runtime journal's OpenRouter `usage.cost` and generation IDs for actual
billed totals. The collector requires a saved owned terminal T3 task and a terminal
OpenCode session, so collection cannot silently cut off ongoing work. Serialize
all ledger writes in the parent. OpenCode's catalogue estimate is separate and
is never labelled billed spend. `--allow-estimate` can retain failed-run evidence
when transport usage is unavailable; disclose that limitation in the PR. Missing
usage is unavailable, never zero. Keep cost precision internally and round displayed
model/round/grand totals to cents. Exclude implementation-agent and CI costs.
When any run has only estimated or incomplete accounting, keep billed and estimate
subtotals separate and omit a mixed grand total. Partial provider records remain
evidence, never a complete billed total. Guard breaches still block coverage.

Append `## AI review` after `## Test changes`: one subsection per actual round,
reviewed range/outcome, model/effort, input, cache reads/writes, output, costs and
round subtotal, then a grand total. No expected/unused rounds or post-PR rounds.
Keep merge policy visible. Preserve this pre-publication history after subsequent
GitHub fixes; their tests/commits/replies must not pretend those fixes were AI
reviewed. Hand the receipt, ledger and final review context to `create-pr`.
