# Copilot review completion and settlement

Treat Copilot review as a one-time review. Once we have fixed a finding or
explained why we cannot or should not fix it, submit our response and resolve
the Copilot thread ourselves immediately. Assume Copilot will not reply,
re-review or check our changes. Do not request a follow-up or wait for one that
has not started. An actually requested or pending review remains a separate
completion gate until its result arrives.
This policy applies whenever an authorized PR workflow responds to Copilot;
it does not grant a planning or read-only workflow permission to write to GitHub.

## Review completion

Recognize Copilot by trusted bot identity/type, including GraphQL's `Bot`
typename, rather than arbitrary comment text or a human with the same login.
Fetch all review pages and all thread comments. Keep these ledger states:

- **quota-pass:** Copilot explicitly cannot review because quota is exhausted.
  A real observed message is: "Copilot was unable to review this pull request
  because the user who requested the review has insufficient remaining quota."
  This ends its completion wait without supplying a source-review verdict or
  erasing earlier actionable findings.
- **running:** an actually started review is pending, including a requested
  review not yet present in REST. Follow the [watch handoff](watch-handoff.md)
  before yielding. Publishing a fix alone never starts another review wait.
- **completed:** a submitted review supplies findings or a clean result. The
  one-time review remains complete after subsequent commits; retain its original
  SHA and do not describe it as approval of fixes it has not seen.
- **changes-requested:** a submitted review has findings requiring disposition.
  After verifying fixes or explanations and settling its threads below, record
  it as addressed in the ledger without waiting for another Copilot verdict.
  If GitHub protection still requires dismissal or human approval, report that
  precise human-owned blocker; thread resolution does not bypass protection.
- **incomplete:** non-quota failure or insufficient evidence. Investigate available
  evidence, then report any remaining gap as a blocker requiring user input.
  Do not wait for or request a retry, or invent approval.
- **absent:** no review or pending request is known. Optional unstarted reviews
  are not required. Inspect requested reviewers/checks before declaring absence.

The helper reads paginated timeline `review_requested` events. A genuinely newer
request or pending review still needs its actual result; an earlier review cannot
satisfy a known request for a different SHA. Preserve an already accepted request's
timestamp and target via `-ReviewRequestedAt` and `-ReviewRequestedHead` while
it has not appeared in the timeline. Unknown request/result ordering remains
incomplete. These receipts track existing reviews, not permission to request more.

Quota can also arrive in a trusted issue comment or check output. Record its
link, identity, body and verified current-head association: an issue comment has
no SHA by itself. Pass verified associations in `-QuotaEvidenceFile` records
containing `headSha`, `user.login`/`user.type`, `body`, `createdAt` and `url`.
Only matching-head trusted records count. Quota never proves a finding was fixed.
Checks, human change requests and other started reviews retain their own gates.

## Resolve after our response

For each Copilot-originated thread:

1. Read its full conversation, including outdated comments. Address every concern;
   later unaddressed human/reviewer feedback blocks settlement. Use the authenticated
   viewer and this run's recorded reply IDs to identify our submitted responses.
2. For a fix, verify it, publish the commit and retain its SHA, current-head ancestry
   and verification result. For a finding we cannot or should not fix, retain the
   concrete reason and evidence, such as a false positive, scope boundary or missing
   prerequisite. Closing the thread does not satisfy an unmet requirement or remove
   an independent merge blocker.
3. Submit one direct reply with the fix and verification, or the explanation and
   evidence. A draft pending review is insufficient. Reuse an existing adequate
   submitted reply; do not add a second settlement comment just to close the thread.
4. Re-fetch the thread/head and check for new concerns or changed evidence. Resolve
   that specific thread immediately through GitHub's `resolveReviewThread` mutation
   or an authenticated connector. Read back `isResolved: true` and record the
   disposition, evidence, reply ID and resolution. No Copilot acknowledgement or
   clean re-review is required.

The read-only helper's `settlementCandidates` identify Copilot threads whose latest
reply is submitted by the viewer. The parent must still verify reply ownership,
all concerns and the fix/explanation evidence above; candidates are not a bulk
resolution command. A resumed run may resolve an already-addressed thread without
waiting for Copilot or repeating its response.

Human-originated threads remain human-owned. Never blanket-resolve threads or
unresolve someone else's threads. If branch protection requires a human thread to
be resolved, report that precise blocker. Missing resolution access is a tooling
blocker; report it without claiming the thread was closed.
