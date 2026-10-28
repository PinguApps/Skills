# Copilot review completion and settlement

Recognize Copilot by its trusted GitHub identity, not arbitrary comment text.
Fetch all review pages and all thread comments. Match a clean review to the exact
current published SHA. Keep these distinctions in the ledger:
Use trusted bot identity/type, including GraphQL's `Bot` typename, rather than a
human account with the same display/login spelling. The state helper returns the
authenticated viewer login for reply ownership checks.

- **quota-pass:** Copilot explicitly cannot review because quota is exhausted.
  A real observed message is: "Copilot was unable to review this pull request
  because the user who requested the review has insufficient remaining quota."
  This satisfies the workflow's Copilot completion requirement. It is not a
  reviewed-source verdict, does not excuse other failing checks or human change
  requests, and cannot erase previously actionable findings.
- **running:** a started current-head review remains pending. Wait for its event.
  Inspect requested reviewers as well as submitted reviews: REST can contain no
  review yet while Copilot is processing. Preserve an accepted re-request in the
  ledger until its current-head result arrives; absence alone cannot end that wait.
- **completed:** a submitted review supplies actual findings or a clean result.
- **incomplete:** non-quota failure or insufficient evidence; do not invent approval.
- **absent:** no current-head review is known; do not require an optional review
  that never started. Inspect requested reviewers/checks before declaring absence.

For Copilot findings, fix and verify the actual issue, push the commit and submit
the thread reply. Wait for configured automatic re-review; if it does not start,
use the available supported GitHub re-request mechanism once for that new head.
Verify the request's outcome and do not repeatedly ping it. A quota response ends
that review wait; report any remaining unresolved requirement separately.
This workflow explicitly permits one supported re-request per newly fixed head;
it replaces the retired policy that relied on PR Agent to verify Copilot fixes.
Preserve the accepted request timestamp. The helper reads paginated GitHub timeline
`review_requested` events and compares the latest trusted Copilot request with the
current-head result. A newer request or pending review takes precedence over an
older quota/clean result. A later submitted result satisfies an older request even
if GitHub's requested-reviewer list is stale. Unknown request/result ordering is
incomplete, not a merge pass. Pass a verified ledger timestamp with
`-ReviewRequestedAt` while a just-accepted request has not appeared in the timeline.

Quota can also arrive in a trusted issue comment or check output. Record its link,
identity, body and verified current-head association. An issue comment has no SHA
by itself: do not infer one from quota words or an old message. Once the parent
establishes the association to the accepted current-head request, it can pass
`-QuotaEvidenceFile` with records containing `headSha`, `user.login`/`user.type`,
`body`, `createdAt` and `url`. The helper accepts only matching-head trusted quota
records; they never supply a clean re-review. Retain the supporting evidence.

The parent can settle a remaining Copilot thread only with all this evidence:

1. Copilot originated the thread. Its full conversation has no later unaddressed
   human/reviewer concern and the parent's last response was submitted.
2. The parent verified the fix against source/tests, and the fixing commit is
   published and an ancestor of current HEAD. Retain SHA and verification result.
3. A subsequent **clean Copilot re-review on that HEAD** completed after the
   parent's response was submitted (use the later of comment creation and review
   submission timestamps, never a draft's creation time alone). Require an approval or explicit no-new-findings/comments
   result. Older-head approval, an unstarted review, mere silence, error, or quota
   alone does not establish this clean re-review.
4. Re-fetch the thread/head just before acting. Post a direct submitted reply:
   `Settled: fixed in <sha>; <verification>. Copilot completed a clean re-review
   of <head> at <review link/time>, with no subsequent concern on this thread.`
5. Resolve only that thread with GitHub's `resolveReviewThread` mutation or the
   authenticated connector, then read back `isResolved: true`. Record the reason,
   reply ID and resolution. The helper's `settlementCandidates` still require the
   parent's fix/ancestry/evidence checks; they are not a bulk-resolution command.

Do not resolve human-originated threads. If branch protection requires a remaining
human thread to be resolved, hand back that precise blocker. A missing ability to
request review or resolve a thread is a tooling blocker; do not fake the action.
