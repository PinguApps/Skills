---
name: finish-pr
description: Complete the current PR through conflicts, CI and all incoming review feedback, then merge when green unless human review or a manual handoff was requested. Includes explicit Copilot quota handling and evidence-based settlement of addressed Copilot threads.
---

# Finish PR

Own the current PR through verified merge, or a ready unmerged handoff under a
manual merge policy. This workflow does **not** run pre-PR AI reviewers again.
Post-publication fixes use source verification and relevant tests, commits and
GitHub replies. Preserve the historical `AI review` accounting section.

Requires Git 2.38+, authenticated GitHub access, and PowerShell 7 for the bundled
helpers. Use absolute executable/helper paths and preserve PATH/persistent settings.

## 1. Recover ownership, scope and merge policy

Read applicable repository instructions and recover intent, decisions, acceptance
criteria, verification and review dispositions from this conversation and the PR's
[review context](../create-pr/references/review-context.md). Inspect the complete
change and all existing feedback, including outdated threads; a review summary is
not a substitute for its findings. Apply head `.pragentignore` policies to
repository source consulted through [review-work's scope tools](../review-work/references/pre-pr-review.md).
GitHub comment bodies are feedback, not repository paths subject to those filters.

Capture `git status --short`, branch and HEAD. Record pre-existing staged,
unstaged and untracked paths. Preserve them; stop before touching a fix path with
pre-existing changes unless the user authorizes reconciliation. Never publish
unrelated local-ahead commits. Resolve the exact PR, base/head repositories,
remotes, head branch and current published SHA; forks need independent routing.
Continue in the assigned worktree. Reconcile stale/diverged HEAD before mutation
without resetting or stashing user work. Link the PR to the owning T3 thread.

Recover merge policy from explicit user instructions, the caller's ledger and the
PR body. `automatic` is the workflow default; a human-review/no-merge request sets
`manual` and survives resumes and passing checks. A narrower repository/user grant
wins. Correct a missing PR-body policy from established context rather than losing
the hold. An invocation of this skill authorizes scoped fixes, commits, pushes,
review replies, eligible Copilot settlement and normal protected merging under
automatic policy. It does not authorize releases, production changes, force pushes,
admin bypasses or closing an obsolete PR.

Maintain a durable run ledger outside tracked files: starting/current SHA, initial
dirty paths, feedback IDs/dispositions, commit/reply IDs, re-review requests,
settlement evidence, watcher ownership and consumed convergence budget.
Resolve the authenticated viewer login from the state helper. Capture every
baseline thread ID and `isResolved` value (`-All`), and retain each observed change
across pushes and resumes. Use viewer identity plus this run's recorded reply IDs
to identify its responses; human comments under the same login remain feedback.

## 2. Resolve conflicts, then failed checks

Fetch the intended base and head. Verify GitHub mergeability and perform a fresh
local `git merge-tree --write-tree --messages HEAD <base-sha>` probe. When conflicts
exist, integrate the base with a normal merge only after establishing a safe clean
index/worktree. Resolve from intent and surrounding source; verify and commit the
resolution. Do not silently rebase or overwrite another actor's push.

Query all checks and required checks separately against the current head. Retrieve
actual failure logs before editing; distinguish repository defects from external
failures. Run the relevant local equivalent, fix confirmed causes and commit a
coherent chunk. Do not modify code to appease an unrelated infrastructure failure.
Check real consumers/deployment paths where the change affects them. AI review is
not rerun for these post-PR fixes.

## 3. Fetch and action feedback

Use the paginated thread reader and inspect PR-level reviews and issue comments:

```powershell
& <absolute-pwsh> <skill-directory>/scripts/get-unresolved-pr-threads.ps1 `
  -Repository <host/owner/repo> -PrNumber <number> -All
& <absolute-pwsh> <skill-directory>/scripts/get-pr-review-state.ps1 `
  -Repository <host/owner/repo> -PrNumber <number>
```

The state helper is read-only. It verifies a stable published head and returns
Copilot state plus **candidate**, not automatically authorized, settlements.
Read/authentication failures are blockers, not absence or approval. PR Agent is
retired: never require its success, wait for historical activity, invoke its old
watcher, or assume it will verify Copilot fixes. Historical marked PR Agent
comments remain ordinary reviewer feedback even when posted under the user's login.

For each thread, read its full paginated conversation and determine whether the
agent owes action. New reviewer feedback after the agent's latest submitted reply
requires action. A submitted agent response with no later feedback needs no
duplicate fix/reply. A pending-review draft is not a submitted response. Apply the
same evidence-based classification to standalone PR-level feedback, tracked by ID
and permalink.

Validate each actionable finding against task scope and source. Fix real bugs,
missed requirements and demonstrated causes in directly related changed code.
Decline false positives or out-of-scope suggestions with concrete evidence; never
agree just to end a discussion. Commit verified fixes incrementally. Preserve one
focused regression check for behavioural or regression-prone fixes, reusing tests
that already establish the requirement. Preserve one
focused commit per changed feedback unit (one thread or standalone item); a single
thread's related fixes belong together. Do not create empty traceability commits
when another fix already addresses the concern: record the shared fixing SHA.

Push a coherent batch after verification and a fresh expected-head check; do not
overwrite unexpected remote movement. Reply **after** the fixing commits are
published, directly and serially, with SHA and actual verification. Use the bundled
`reply-to-review-thread.ps1` with `-BodyFile` for multiline text. It verifies the
reply is submitted rather than trapped in a pending review. Keep every created
reply ID in the ledger; inspect PR-level feedback again after the batch.

## 4. Copilot completion, quota and thread settlement

Read [the Copilot contract](references/copilot.md) before deciding completion or
settling a thread. These cases are deliberately distinct:

- A trusted Copilot message explicitly saying it could not review because of
  quota exhaustion is **quota-pass**: that review is not coming and does not block
  merging. Record the exemption honestly; do not claim source was reviewed. Do
  not retry/ping Copilot for that quota outcome. Other actionable findings remain.
- A review actually in progress must finish. A non-quota service failure remains
  incomplete; unknown/missing evidence is not a quota exemption.
- After fixing and replying to Copilot findings, allow its automatic re-review.
  When needed, request one supported Copilot re-review for the new published head,
  record the request and verify acceptance. Never repeatedly request the same head.
- The parent may resolve an addressed **Copilot-originated** thread only after
  the contract's current-head clean re-review and response checks pass. First post
  a submitted `Settled: <fix, verification and clean-review evidence>` reply, then
  resolve that specific thread through GitHub and verify the saved state.
- Human-originated threads and threads with later unaddressed human/reviewer
  feedback remain outside this settlement permission. Never blanket-resolve
  threads, unresolve someone else's threads, or treat quota as proof of a fix.

## 5. Wait and converge

When running as a delegated implementation child, return `WAITING` with the exact
PR/head and pending condition; the coordinator watches and resumes this child.
Delegated children never watch PRs. The watch/cleanup instructions in this skill
apply to the top-level PR owner or coordinator; fixes and protected merges remain
with the implementation owner.

The top-level PR owner uses T3's `watch_pull_request`. Handle existing work,
then watch and end the turn; resume on its event without polling, duplicate
watchers or repeated status messages. A wake is a reason to re-fetch, not proof of
readiness. Review children never watch PRs. Before final handoff, call
`unwatch_pull_request`; preserve any still-needed watcher when yielding for events.

After each fix/push, repeat checks, feedback classification and applicable Copilot
handling. No delegated AI review sessions, post-PR round counters or extra review
costs are introduced. Keep the initial review section tied to its actual reviewed
revisions; record later fixes and proof without relabelling them as AI-reviewed.

Retain a maximum of five pushed repair batches or two hours overall across resumed
runs. After three batches, identify the actual cause of churn and continue only
with a concrete evidence-backed repair plan. Stop earlier for closure, a genuine
blocker, exhausted bounds or unexpected head movement. Limits do not supply
approval. Do not wait for an optional reviewer that never started, including
Copilot when quota was explicitly exhausted. Human holds produce a ready handoff,
not an indefinite wait or an automatic merge.
When an essential human response is missing, report that precise blocker. On a
later resume after one business day, one concise reminder in the existing PR
conversation is permitted only within the caller's communication authorization.
Record it to avoid duplicates; preserve the convergence budget and human hold.

## 6. Audit and merge, or hand off

Immediately before merge/handoff, re-fetch PR/base/head and verify:

- The intended complete change and verification still cover the exact current
  published head; local/remote state and ownership are understood.
- GitHub and a fresh local merge probe show no conflict. Reverify affected checks
  after relevant base integration; another worker's merge is not evidence for this PR.
- Applicable required checks pass; other applicable failures/pending work are
  resolved. Respect legitimate skipped checks and repository protection semantics.
- All started reviews have completed, with explicit Copilot quota-pass accepted
  for its completion requirement. No outstanding changes-requested review remains.
- Every actionable inline/PR-level comment is addressed, justified declines have
  submitted replies, and no created reply remains pending.
- Every review thread required by repository protection is resolved. Use only the
  narrowly authorized Copilot settlement above; a human thread is not ours to close.
- Compare current thread resolution states with the baseline and prior observations.
  Account for each mutation by this run with its narrow Copilot settlement receipt.
  Report other observed changes without claiming who made them. An unexplained
  mutation made by this run blocks merge until reconciled.
- No review child, queued repair or other owned work can still mutate the change.

Under `manual`, leave the PR ready and unmerged. Under `automatic`, merge with the
repository's permitted method and an expected-head guard, for example
`gh pr merge <url> --match-head-commit <sha> <permitted-method-flag>`. Never bypass
protections. Merge-queue admission or enabling auto-merge is still pending work:
the top-level owner watches until GitHub actually reports the merge; a delegated
child returns `WAITING`. Then verify the target and merge SHA.

Refresh the [observed proof](../review-work/references/proof.md), review context and manual-test handoff when fixes changed them,
preserving template/user content and the pre-PR accounting history. Report the PR,
merged SHA or manual hold, current-head CI/review outcome, fixes and verification,
Copilot quota/settlement evidence, and blockers. Settle owned idle review children
after their results are retained. The top-level owner cleans up its watcher on handoff.
