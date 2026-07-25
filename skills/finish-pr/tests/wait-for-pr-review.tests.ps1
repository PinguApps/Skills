$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\scripts\wait-for-pr-review.ps1" `
    -Wait `
    -StatePath "unused-test-state.json" `
    -ExpectedHeadSha "unused-test-sha" `
    -ReviewRequestedAt ([DateTimeOffset]::MinValue)

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)

    if ($Expected -ne $Actual) {
        throw "$Message Expected '$Expected', got '$Actual'."
    }
}

function New-Snapshot {
    param(
        [string]$HeadSha = "new-sha",
        [string]$State = "OPEN",
        [array]$Reactions = @(),
        [array]$FeedbackItems = @()
    )

    return [pscustomobject]@{
        pullRequest = [pscustomobject]@{ headSha = $HeadSha; state = $State }
        reactions = $Reactions
        feedbackItems = $FeedbackItems
    }
}

$baseline = [pscustomobject]@{
    seenReactionIds = @("old-thumb")
    seenFeedbackIds = @("old-comment")
}
$reviewer = "example-codex-reviewer"
Assert-Equal "example-codex-reviewer" (Normalize-ReviewerLogin "Example-Codex-Reviewer[BOT]") "Reviewer normalization should strip bot suffixes case-insensitively."

$waiting = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewStartedObserved $false -ApprovalCandidateObserved $false
Assert-Equal "waiting" $waiting.status "A review without new signals should wait."

$reactionPages = '[[{"id":"page-one"}],[{"id":"page-two"}]]' | ConvertFrom-Json -Depth 10
$expandedReactions = @(Expand-PaginatedItems $reactionPages)
Assert-Equal 2 $expandedReactions.Count "Paginated reaction pages should flatten into one collection."
Assert-Equal "page-two" $expandedReactions[1].id "Paginated reactions should preserve later pages."

$eyes = [pscustomobject]@{ id = "new-eyes"; content = "eyes"; authorLogin = "example-codex-reviewer[bot]"; authorType = "Organization"; createdAt = "2026-01-01T00:00:00Z" }
$started = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -Reactions @($eyes)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewStartedObserved $false -ApprovalCandidateObserved $false
Assert-Equal "waiting" $started.status "Seeing eyes should keep waiting."
Assert-Equal $true $started.reviewStartedObserved "Seeing eyes should record that review started."
$bootstrapCandidates = @(Find-NewReviewerCandidates -Baseline $baseline -Snapshot (New-Snapshot -Reactions @($eyes)))
Assert-Equal 1 $bootstrapCandidates.Count "A unique fresh review-start reaction should bootstrap one reviewer."
Assert-Equal $reviewer $bootstrapCandidates[0] "Reviewer bootstrap should normalize the fresh reaction author."
$fallbackRequest = [pscustomobject]@{ id = "fallback-request"; kind = "issue_comment"; authorLogin = "example-agent"; body = "@codex review" }
$fallbackCandidates = @(Find-NewReviewerCandidates -Baseline $baseline -Snapshot (New-Snapshot -FeedbackItems @($fallbackRequest)) -ExcludedLogin "example-agent")
Assert-Equal 0 $fallbackCandidates.Count "Reviewer bootstrap should exclude the authenticated fallback requester."
$unlinkedCodexIssue = [pscustomobject]@{ id = "unlinked-codex-issue"; kind = "issue_comment"; authorLogin = $reviewer; authorType = "Bot"; body = "Please fix this."; createdAt = [DateTimeOffset]::UtcNow }
$unlinkedIssueCandidates = @(Find-NewReviewerCandidates -Baseline $baseline -Snapshot (New-Snapshot -FeedbackItems @($unlinkedCodexIssue)))
Assert-Equal 0 $unlinkedIssueCandidates.Count "Reviewer bootstrap should exclude SHA-less issue comments."
$humanFeedback = [pscustomobject]@{ id = "human-feedback"; kind = "issue_comment"; authorLogin = "example-human"; body = "Please fix this."; createdAt = [DateTimeOffset]::UtcNow }
$humanCandidates = @(Find-NewReviewerCandidates -Baseline $baseline -Snapshot (New-Snapshot -FeedbackItems @($humanFeedback)))
Assert-Equal 0 $humanCandidates.Count "Reviewer bootstrap should not promote an arbitrary human feedback author."
$bootstrapBoundary = [DateTimeOffset]::UtcNow
$earlyHumanComment = [pscustomobject]@{ id = "early-human-comment"; kind = "issue_comment"; authorLogin = "example-human"; body = "Please fix this."; createdAt = $bootstrapBoundary.AddSeconds(-1) }
$earlyCandidates = @(Find-NewReviewerCandidates -Baseline $baseline -Snapshot (New-Snapshot -FeedbackItems @($earlyHumanComment)) -NotBefore $bootstrapBoundary)
Assert-Equal 0 $earlyCandidates.Count "Reviewer bootstrap should exclude feedback created before the pushed-head boundary."
$propagatingCandidates = @(Find-NewReviewerCandidates -Baseline $baseline -Snapshot (New-Snapshot -HeadSha "old-sha" -Reactions @($eyes)) -ExpectedHeadSha "new-sha")
Assert-Equal 0 $propagatingCandidates.Count "Reviewer bootstrap should wait until the expected HEAD is visible."
Assert-Equal $false (Test-ReviewStartGraceExpired -GraceSeconds 30 -ReviewStartedObserved $false -SnapshotStartedAt $bootstrapBoundary.AddSeconds(-1) -ReviewStartDeadline $bootstrapBoundary -CurrentHeadSha "new-sha" -ExpectedHeadSha "new-sha") "A snapshot started before the grace deadline must not trigger fallback."
Assert-Equal $false (Test-ReviewStartGraceExpired -GraceSeconds 30 -ReviewStartedObserved $false -SnapshotStartedAt $bootstrapBoundary -ReviewStartDeadline $bootstrapBoundary -CurrentHeadSha "old-sha" -ExpectedHeadSha "new-sha") "The grace period must not expire while the baseline HEAD is still visible."
Assert-Equal $true (Test-ReviewStartGraceExpired -GraceSeconds 30 -ReviewStartedObserved $false -SnapshotStartedAt $bootstrapBoundary -ReviewStartDeadline $bootstrapBoundary -CurrentHeadSha "new-sha" -ExpectedHeadSha "new-sha") "A post-deadline expected-HEAD snapshot may trigger fallback."

$comment = [pscustomobject]@{ id = "new-comment"; kind = "thread_comment"; authorLogin = $reviewer; body = "Please fix this." }
$feedback = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -FeedbackItems @($comment)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewStartedObserved $true -ApprovalCandidateObserved $false
Assert-Equal "feedback" $feedback.status "A new reviewer comment should return feedback."
Assert-Equal 1 $feedback.newFeedback.Count "New feedback should be returned."

$editedFeedbackBaseline = [pscustomobject]@{
    seenReactionIds = @()
    seenFeedbackIds = @("edited-comment")
    seenFeedbackVersions = @(
        [pscustomobject]@{ id = "edited-comment"; updatedAt = "2026-01-01T00:00:00Z"; body = "Original feedback." }
    )
}
$editedComment = [pscustomobject]@{
    id = "edited-comment"
    kind = "thread_comment"
    authorLogin = $reviewer
    body = "Updated feedback."
    updatedAt = "2026-01-01T00:01:00Z"
}
$editedFeedback = Resolve-ReviewOutcome -Baseline $editedFeedbackBaseline -Snapshot (New-Snapshot -FeedbackItems @($editedComment)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewStartedObserved $true -ApprovalCandidateObserved $false
Assert-Equal "feedback" $editedFeedback.status "An edited baseline comment should return feedback."
Assert-Equal 1 $editedFeedback.newFeedback.Count "Edited feedback should be returned once."

$approvalSignalAt = [DateTimeOffset]"2026-01-01T00:00:01Z"
$thumb = [pscustomobject]@{ id = "new-thumb"; content = "+1"; authorLogin = "example-codex-reviewer[bot]"; createdAt = $approvalSignalAt }
$positiveReview = [pscustomobject]@{
    id = "positive-review"
    kind = "review"
    authorLogin = $reviewer
    body = ""
    reviewState = "APPROVED"
    headSha = "new-sha"
    createdAt = $approvalSignalAt
}
$positiveReviewCandidate = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -Reactions @($thumb) -FeedbackItems @($positiveReview)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewStartedObserved $false -ApprovalCandidateObserved $false
Assert-Equal "approval_candidate" $positiveReviewCandidate.status "A non-actionable positive review should not suppress a simultaneous thumbs-up."
$substantiveApprovedReview = [pscustomobject]@{
    id = "substantive-approved-review"
    kind = "review"
    authorLogin = $reviewer
    body = "Please still fix the hostname routing."
    reviewState = "APPROVED"
}
Assert-Equal $true (Test-ActionableFeedbackItem $substantiveApprovedReview) "A substantive approved-review body should remain actionable."
$acknowledgement = [pscustomobject]@{
    id = "acknowledgement"
    kind = "issue_comment"
    authorLogin = $reviewer
    body = "Looks good."
}
Assert-Equal $false (Test-ActionableFeedbackItem $acknowledgement) "A positive acknowledgement should not be actionable feedback."
$threadAcknowledgement = [pscustomobject]@{
    id = "thread-acknowledgement"
    kind = "thread_comment"
    authorLogin = $reviewer
    body = "LGTM"
}
Assert-Equal $false (Test-ActionableFeedbackItem $threadAcknowledgement) "A positive thread acknowledgement should not be actionable feedback."

$unlinkedCandidate = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -Reactions @($thumb)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewStartedObserved $false -ApprovalCandidateObserved $false
Assert-Equal "waiting" $unlinkedCandidate.status "A thumbs-up without a submitted expected-HEAD review must remain ineligible."
$candidate = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -Reactions @($thumb) -FeedbackItems @($positiveReview)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewStartedObserved $false -ApprovalCandidateObserved $false
Assert-Equal "approval_candidate" $candidate.status "A head-linked thumbs-up should become an approval candidate even when no eyes reaction was sampled."
$approved = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -Reactions @($thumb) -FeedbackItems @($positiveReview)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewStartedObserved $false -ApprovalCandidateObserved $true
Assert-Equal "approved" $approved.status "A stable head-linked thumbs-up should approve without requiring an eyes reaction."

$retainedEyesCandidate = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -Reactions @($eyes, $thumb) -FeedbackItems @($positiveReview)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewStartedObserved $true -ApprovalCandidateObserved $false
Assert-Equal "approval_candidate" $retainedEyesCandidate.status "A retained start reaction must not suppress approval."
$retainedEyesApproved = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -Reactions @($eyes, $thumb) -FeedbackItems @($positiveReview)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewStartedObserved $true -ApprovalCandidateObserved $true
Assert-Equal "approved" $retainedEyesApproved.status "A stable approval must complete while the start reaction remains."

$staleThumb = [pscustomobject]@{ id = "old-thumb"; content = "+1"; authorLogin = $reviewer }
$stale = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -Reactions @($staleThumb)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewStartedObserved $true -ApprovalCandidateObserved $true
Assert-Equal "waiting" $stale.status "A baseline thumbs-up must not approve a new push."

$race = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -Reactions @($thumb) -FeedbackItems @($comment)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewStartedObserved $true -ApprovalCandidateObserved $true
Assert-Equal "feedback" $race.status "Feedback should win an approval race."

$changed = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -HeadSha "other-sha") -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewStartedObserved $false -ApprovalCandidateObserved $false
Assert-Equal "head_changed" $changed.status "An unexpected head change should stop the watcher."
$prePushHead = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -HeadSha "old-sha") -ExpectedSha "new-sha" -Reviewer $reviewer -BaselineSha "old-sha" -ReviewStartedObserved $false -ApprovalCandidateObserved $false
Assert-Equal "waiting" $prePushHead.status "The watcher should wait while GitHub still reports the pre-push baseline head."
$expectedHeadObservedBaseline = [pscustomobject]@{
    seenReactionIds = @()
    seenFeedbackIds = @()
    expectedHeadReactionsCaptured = $true
}
$restoredBaselineHead = Resolve-ReviewOutcome -Baseline $expectedHeadObservedBaseline -Snapshot (New-Snapshot -HeadSha "old-sha") -ExpectedSha "new-sha" -Reviewer $reviewer -BaselineSha "old-sha" -ReviewStartedObserved $false -ApprovalCandidateObserved $false
Assert-Equal "head_changed" $restoredBaselineHead.status "Returning to the baseline head after the expected head was observed should stop the watcher."

$racedApprovalState = [pscustomobject]@{
    seenReactionIds = @("old-thumb")
    seenFeedbackIds = @("old-comment")
    reviewStartedObserved = $false
    approvalCandidateObserved = $false
}
$pushCompletedAt = [DateTimeOffset]::UtcNow
$earlyExpectedHeadThumb = [pscustomobject]@{ id = "early-expected-head-thumb"; content = "+1"; authorLogin = $reviewer; createdAt = $pushCompletedAt.AddSeconds(-1) }
$racedApprovalSnapshot = New-Snapshot -Reactions @($eyes, $earlyExpectedHeadThumb)
$initialized = Initialize-ExpectedHeadReactionBaseline -State $racedApprovalState -Snapshot $racedApprovalSnapshot -ExpectedSha "new-sha" -Reviewer $reviewer
Assert-Equal $true $initialized "The expected head should refresh the reaction baseline once."
Assert-Equal $true $racedApprovalState.reviewStartedObserved "The refreshed baseline should preserve a review start reaction."
Assert-Equal 1 $racedApprovalState.seenReactionIds.Count "Expected-head initialization should preserve only reactions observed on the baseline head."
$racedApproval = Resolve-ReviewOutcome -Baseline $racedApprovalState -Snapshot $racedApprovalSnapshot -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewRequestedAt $pushCompletedAt -ReviewStartedObserved $racedApprovalState.reviewStartedObserved -ApprovalCandidateObserved $false
Assert-Equal "waiting" $racedApproval.status "A thumbs-up predating the review request must not approve the expected head."
$sameSecondThumb = [pscustomobject]@{ id = "same-second-thumb"; content = "+1"; authorLogin = $reviewer; createdAt = $pushCompletedAt.AddTicks(-($pushCompletedAt.Ticks % [TimeSpan]::TicksPerSecond)) }
$sameSecondApproval = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -Reactions @($sameSecondThumb)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewRequestedAt $pushCompletedAt -ReviewStartedObserved $false -ApprovalCandidateObserved $false
Assert-Equal "waiting" $sameSecondApproval.status "A thumbs-up without fresh expected-HEAD review-start evidence must remain ineligible."
$expectedHeadReview = [pscustomobject]@{ id = "expected-head-review"; kind = "review"; authorLogin = $reviewer; body = ""; reviewState = "COMMENTED"; headSha = "new-sha"; createdAt = $sameSecondThumb.createdAt }
$missedEyesApproval = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -Reactions @($sameSecondThumb) -FeedbackItems @($expectedHeadReview)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewRequestedAt $pushCompletedAt -ReviewStartedObserved $false -ApprovalCandidateObserved $false
Assert-Equal "approval_candidate" $missedEyesApproval.status "A submitted expected-HEAD review should link approval when the eyes reaction was missed."
$missedEyesReviewStart = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -FeedbackItems @($expectedHeadReview)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewRequestedAt $pushCompletedAt -ReviewStartedObserved $false -ApprovalCandidateObserved $false
Assert-Equal $true $missedEyesReviewStart.reviewStartedObserved "A submitted expected-HEAD review should prove that review started when eyes was missed."
$missedEyesFeedbackItem = [pscustomobject]@{ id = "missed-eyes-feedback"; kind = "thread_comment"; authorLogin = $reviewer; body = "Please fix this."; headSha = "new-sha"; createdAt = $pushCompletedAt.AddSeconds(1) }
$missedEyesFeedback = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -FeedbackItems @($expectedHeadReview, $missedEyesFeedbackItem)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewRequestedAt $pushCompletedAt -ReviewStartedObserved $false -ApprovalCandidateObserved $false
Assert-Equal "feedback" $missedEyesFeedback.status "Expected-HEAD feedback should remain visible when the eyes reaction was missed."
$headLinkedApproval = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -Reactions @($sameSecondThumb) -FeedbackItems @($expectedHeadReview)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewRequestedAt $pushCompletedAt -ReviewHeadBoundary $pushCompletedAt -ReviewStartedObserved $true -ApprovalCandidateObserved $false
Assert-Equal "approval_candidate" $headLinkedApproval.status "A thumbs-up at the fresh expected-HEAD review boundary should remain eligible."
$preservedReviewBaseline = [pscustomobject]@{
    seenReactionIds = @("old-thumb")
    seenFeedbackIds = @("expected-head-review")
    preservedExpectedHeadReviewIds = @("expected-head-review")
}
$preservedReviewApproval = Resolve-ReviewOutcome -Baseline $preservedReviewBaseline -Snapshot (New-Snapshot -Reactions @($sameSecondThumb) -FeedbackItems @($expectedHeadReview)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewHeadBoundary $pushCompletedAt -ReviewStartedObserved $true -ApprovalCandidateObserved $false
Assert-Equal "approval_candidate" $preservedReviewApproval.status "A current-HEAD review captured during a no-push baseline must remain eligible to link a later thumbs-up."
$preservedApprovalBaseline = [pscustomobject]@{
    seenReactionIds = @("same-second-thumb")
    preservedApprovalReactionIds = @("same-second-thumb")
    seenFeedbackIds = @("expected-head-review")
    preservedExpectedHeadReviewIds = @("expected-head-review")
}
$preservedBaselineApproval = Resolve-ReviewOutcome -Baseline $preservedApprovalBaseline -Snapshot (New-Snapshot -Reactions @($sameSecondThumb) -FeedbackItems @($expectedHeadReview)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewHeadBoundary $pushCompletedAt -ReviewStartedObserved $true -ApprovalCandidateObserved $false
Assert-Equal "approval_candidate" $preservedBaselineApproval.status "A baseline thumbs-up already linked to a current-HEAD review must remain eligible."
$oldHeadReview = [pscustomobject]@{ id = "old-head-review"; kind = "review"; authorLogin = $reviewer; body = ""; reviewState = "COMMENTED"; headSha = "old-sha"; createdAt = $sameSecondThumb.createdAt }
$staleReactionApproval = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -Reactions @($sameSecondThumb) -FeedbackItems @($oldHeadReview)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewRequestedAt $pushCompletedAt -ReviewHeadBoundary $pushCompletedAt -ReviewStartedObserved $true -ApprovalCandidateObserved $false
Assert-Equal "waiting" $staleReactionApproval.status "A reaction without a submitted expected-HEAD review must not approve the pushed HEAD."
$dismissedHeadReview = [pscustomobject]@{ id = "dismissed-head-review"; kind = "review"; authorLogin = $reviewer; body = ""; reviewState = "DISMISSED"; headSha = "new-sha"; createdAt = $sameSecondThumb.createdAt }
$dismissedReviewApproval = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -Reactions @($sameSecondThumb) -FeedbackItems @($dismissedHeadReview)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewRequestedAt $pushCompletedAt -ReviewHeadBoundary $pushCompletedAt -ReviewStartedObserved $true -ApprovalCandidateObserved $false
Assert-Equal "waiting" $dismissedReviewApproval.status "A dismissed current-HEAD review must not authorize approval."
$staleReviewBody = [pscustomobject]@{ id = "stale-review-body"; kind = "review"; authorLogin = $reviewer; body = "Please fix this."; reviewState = "COMMENTED"; headSha = "old-sha"; createdAt = $pushCompletedAt.AddSeconds(1) }
$filteredStaleReviewBody = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -FeedbackItems @($staleReviewBody)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewRequestedAt $pushCompletedAt -ReviewHeadBoundary $pushCompletedAt -ReviewStartedObserved $true -ApprovalCandidateObserved $false
Assert-Equal "waiting" $filteredStaleReviewBody.status "A review body submitted for another HEAD must not become feedback for the pushed HEAD."
$preReviewIssueComment = [pscustomobject]@{ id = "pre-review-issue-comment"; kind = "issue_comment"; authorLogin = $reviewer; body = "Please fix this."; createdAt = $pushCompletedAt.AddSeconds(-1) }
$filteredPreReviewIssueComment = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -FeedbackItems @($expectedHeadReview, $preReviewIssueComment)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewHeadBoundary $pushCompletedAt.AddSeconds(-2) -ReviewStartedObserved $true -ApprovalCandidateObserved $false
Assert-Equal "waiting" $filteredPreReviewIssueComment.status "An issue comment predating the submitted expected-HEAD review must not become feedback for that HEAD."
$postReviewIssueComment = [pscustomobject]@{ id = "post-review-issue-comment"; kind = "issue_comment"; authorLogin = $reviewer; body = "Please fix this."; createdAt = $pushCompletedAt.AddSeconds(1) }
$linkedPostReviewIssueComment = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -FeedbackItems @($expectedHeadReview, $postReviewIssueComment)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewHeadBoundary $pushCompletedAt.AddSeconds(-2) -ReviewStartedObserved $true -ApprovalCandidateObserved $false
Assert-Equal "waiting" $linkedPostReviewIssueComment.status "A SHA-less issue comment must remain outside pushed-HEAD watcher feedback and be handled by the standalone audit."
$oldHeadFeedback = [pscustomobject]@{ id = "old-head-feedback"; kind = "thread_comment"; authorLogin = $reviewer; body = "Please fix this."; createdAt = $pushCompletedAt.AddSeconds(-1) }
$filteredOldHeadFeedback = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -FeedbackItems @($oldHeadFeedback)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewRequestedAt $pushCompletedAt -ReviewHeadBoundary $pushCompletedAt -ReviewStartedObserved $true -ApprovalCandidateObserved $false
Assert-Equal "waiting" $filteredOldHeadFeedback.status "Feedback predating the expected-HEAD review boundary must be ignored."
$offsetBoundary = [DateTimeOffset]"2026-07-25T22:21:04+01:00"
$utcFeedbackAfterBoundary = [pscustomobject]@{
    id = "utc-feedback-after-boundary"
    kind = "thread_comment"
    authorLogin = $reviewer
    body = "Please fix this."
    createdAt = [DateTime]"2026-07-25T21:28:15Z"
}
$offsetSafeFeedback = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -FeedbackItems @($utcFeedbackAfterBoundary)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewHeadBoundary $offsetBoundary -ReviewStartedObserved $true -ApprovalCandidateObserved $false
Assert-Equal "feedback" $offsetSafeFeedback.status "UTC feedback after an offset review boundary must not be shifted by locale formatting."
$positiveOffsetTimestamp = [DateTimeOffset]"2026-01-01T01:30:00+02:00"
Assert-Equal ([DateTimeOffset]"2025-12-31T23:30:00Z") ((ConvertTo-ReviewTimestamp $positiveOffsetTimestamp).ToUniversalTime()) "Review timestamps must preserve their explicit offset."
$initializedAgain = Initialize-ExpectedHeadReactionBaseline -State $racedApprovalState -Snapshot $racedApprovalSnapshot -ExpectedSha "new-sha" -Reviewer $reviewer
Assert-Equal $false $initializedAgain "The expected-head reaction baseline should initialize only once."

$propagationState = [pscustomobject]@{
    baselineHeadSha = "old-sha"
    seenReactionIds = @("old-thumb")
    seenFeedbackIds = @()
    reviewStartedObserved = $false
    approvalCandidateObserved = $false
    expectedHeadReactionsCaptured = $false
}
$propagationThumb = [pscustomobject]@{ id = "old-head-post-push-thumb"; content = "+1"; authorLogin = $reviewer; createdAt = $pushCompletedAt.AddSeconds(1) }
$propagationSnapshot = New-Snapshot -HeadSha "old-sha" -Reactions @($propagationThumb)
$propagationUpdated = Update-BaselineHeadReactionObservations -State $propagationState -Snapshot $propagationSnapshot
Assert-Equal $true $propagationUpdated "Reactions observed while the baseline head is current should update the baseline."
Assert-Equal 2 $propagationState.seenReactionIds.Count "The baseline should retain newly observed old-head reactions."
$newHeadAfterPropagation = New-Snapshot -HeadSha "new-sha" -Reactions @($propagationThumb)
$null = Initialize-ExpectedHeadReactionBaseline -State $propagationState -Snapshot $newHeadAfterPropagation -ExpectedSha "new-sha" -Reviewer $reviewer
$stalePropagationApproval = Resolve-ReviewOutcome -Baseline $propagationState -Snapshot $newHeadAfterPropagation -ExpectedSha "new-sha" -Reviewer $reviewer -BaselineSha "old-sha" -ReviewStartedObserved $false -ApprovalCandidateObserved $false
Assert-Equal "waiting" $stalePropagationApproval.status "A reaction first observed on the baseline head must not approve the expected head."

$unchangedHeadState = [pscustomobject]@{
    baselineHeadSha = "new-sha"
    seenReactionIds = @("old-thumb")
    seenFeedbackIds = @()
    reviewStartedObserved = $false
    approvalCandidateObserved = $false
    expectedHeadReactionsCaptured = $false
}
$unchangedHeadThumb = [pscustomobject]@{ id = "fresh-unchanged-head-thumb"; content = "+1"; authorLogin = $reviewer; createdAt = $approvalSignalAt }
$unchangedHeadSnapshot = New-Snapshot -HeadSha "new-sha" -Reactions @($unchangedHeadThumb)
$unchangedInitialized = Initialize-ExpectedHeadReactionBaseline -State $unchangedHeadState -Snapshot $unchangedHeadSnapshot -ExpectedSha "new-sha" -Reviewer $reviewer
Assert-Equal $true $unchangedInitialized "An unchanged expected head should initialize before baseline-head reaction updating."
$unchangedBaselineUpdated = Update-BaselineHeadReactionObservations -State $unchangedHeadState -Snapshot $unchangedHeadSnapshot
Assert-Equal $false $unchangedBaselineUpdated "Expected-head reactions must not be consumed as old-head baseline observations."
$unchangedApproval = Resolve-ReviewOutcome -Baseline $unchangedHeadState -Snapshot $unchangedHeadSnapshot -ExpectedSha "new-sha" -Reviewer $reviewer -BaselineSha "new-sha" -ReviewStartedObserved $false -ApprovalCandidateObserved $false
Assert-Equal "waiting" $unchangedApproval.status "A fresh unchanged-HEAD thumbs-up without a head-linked review must remain ineligible."
$linkedUnchangedApproval = Resolve-ReviewOutcome -Baseline $unchangedHeadState -Snapshot (New-Snapshot -HeadSha "new-sha" -Reactions @($unchangedHeadThumb) -FeedbackItems @($positiveReview)) -ExpectedSha "new-sha" -Reviewer $reviewer -BaselineSha "new-sha" -ReviewStartedObserved $false -ApprovalCandidateObserved $false
Assert-Equal "approval_candidate" $linkedUnchangedApproval.status "A fresh unchanged-HEAD thumbs-up should become eligible when a submitted review links it to that HEAD."

$lateEyesState = [pscustomobject]@{
    seenReactionIds = @()
    reviewStartedObserved = $false
    approvalCandidateObserved = $false
    expectedHeadReactionsCaptured = $false
    reviewHeadBoundary = $null
}
$null = Initialize-ExpectedHeadReactionBaseline -State $lateEyesState -Snapshot (New-Snapshot) -ExpectedSha "new-sha" -Reviewer $reviewer
$lateEyesInitialized = Initialize-ExpectedHeadReactionBaseline -State $lateEyesState -Snapshot (New-Snapshot -Reactions @($eyes)) -ExpectedSha "new-sha" -Reviewer $reviewer
Assert-Equal $true $lateEyesInitialized "A later poll should establish a missing expected-HEAD review boundary."
Assert-Equal "2026-01-01T00:00:00.0000000+00:00" $lateEyesState.reviewHeadBoundary "The later fresh eyes timestamp should become the review boundary."

$staleEyesState = [pscustomobject]@{
    seenReactionIds = @("old-eyes")
    reviewStartedObserved = $false
    approvalCandidateObserved = $false
    expectedHeadReactionsCaptured = $false
}
$staleEyesSnapshot = New-Snapshot -Reactions @([pscustomobject]@{ id = "old-eyes"; content = "eyes"; authorLogin = $reviewer; createdAt = $pushCompletedAt.AddMinutes(-1) })
$null = Initialize-ExpectedHeadReactionBaseline -State $staleEyesState -Snapshot $staleEyesSnapshot -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewRequestedAt $pushCompletedAt
Assert-Equal $false $staleEyesState.reviewStartedObserved "A baseline eyes reaction must not satisfy the automatic-review grace period."

$baselinePath = Join-Path ([IO.Path]::GetTempPath()) "finish-pr-wait-review-baseline-test.json"
function Invoke-GhJson {
    return [pscustomobject]@{
        owner = [pscustomobject]@{ login = "example-owner" }
        name = "example-repository"
        url = "https://github.example/example-owner/example-repository"
    }
}
function Get-PrReviewSnapshot {
    $capturedExpectedHeadReview = [pscustomobject]@{
        id = "captured-expected-head-review"
        kind = "review"
        authorLogin = $reviewer
        body = ""
        reviewState = "COMMENTED"
        headSha = "new-sha"
        createdAt = "2026-01-01T00:00:01Z"
    }
    $capturedApproval = [pscustomobject]@{
        id = "captured-approval"
        content = "+1"
        authorLogin = $reviewer
        createdAt = "2026-01-01T00:00:02Z"
    }
    return New-Snapshot -Reactions @($eyes, $capturedApproval) -FeedbackItems @($capturedExpectedHeadReview)
}

try {
    $CaptureBaseline = $true
    $StatePath = $baselinePath
    $PrNumber = 25
    $ReviewerLogin = $reviewer
    $PreserveExistingReviewStart = $false
    Invoke-PrReviewWatcher | Out-Null
    $capturedBaseline = Get-Content -Raw -LiteralPath $baselinePath | ConvertFrom-Json -Depth 100
    Assert-Equal $false $capturedBaseline.reviewStartedObserved "Baseline capture should not treat a pre-existing start reaction as evidence for the next HEAD."
    Assert-Equal "github.example" $capturedBaseline.hostname "Repository inference should preserve the URL authority."
}
finally {
    Remove-Item -LiteralPath $baselinePath -ErrorAction SilentlyContinue
}

try {
    $CaptureBaseline = $true
    $StatePath = $baselinePath
    $PrNumber = 25
    $ReviewerLogin = $reviewer
    $PreserveExistingReviewStart = $true
    Invoke-PrReviewWatcher | Out-Null
    $ongoingReviewBaseline = Get-Content -Raw -LiteralPath $baselinePath | ConvertFrom-Json -Depth 100
    Assert-Equal $true $ongoingReviewBaseline.reviewStartedObserved "No-push capture should preserve an existing review-start reaction when requested."
    Assert-Equal ([DateTimeOffset]"2026-01-01T00:00:00Z") ([DateTimeOffset]$ongoingReviewBaseline.reviewHeadBoundary) "No-push capture should preserve the ongoing review boundary."
    Assert-Equal "captured-expected-head-review" @($ongoingReviewBaseline.preservedExpectedHeadReviewIds)[0] "No-push capture should retain a current-HEAD review observed after the preserved start boundary."
    Assert-Equal "captured-approval" @($ongoingReviewBaseline.preservedApprovalReactionIds)[0] "No-push capture should retain an approval already linked to a current-HEAD review."
}
finally {
    Remove-Item -LiteralPath $baselinePath -ErrorAction SilentlyContinue
}

$script:CapturedGhCalls = @()
function Invoke-GhJson {
    param([string[]]$GhArgs)
    $script:CapturedGhCalls += ,@($GhArgs)
    if ($GhArgs[0] -eq "pr") {
        return [pscustomobject]@{ number = 25 }
    }
    return [pscustomobject]@{ login = "example-agent" }
}

try {
    $CaptureBaseline = $true
    $StatePath = $baselinePath
    $PrNumber = 0
    $Repository = "example-owner/example-repository"
    $Hostname = "ghe.example"
    $ReviewerLogin = $reviewer
    Invoke-PrReviewWatcher | Out-Null
    $prDiscoveryCall = @($script:CapturedGhCalls | Where-Object { $_[0] -eq "pr" })[0]
    Assert-Equal "pr view --repo ghe.example/example-owner/example-repository --json number" ($prDiscoveryCall -join " ") "PR discovery should retain the supplied hostname."
}
finally {
    Remove-Item -LiteralPath $baselinePath -ErrorAction SilentlyContinue
}

$hostQualifiedRouting = Resolve-RepositoryRouting -Repository "ghe.example/example-owner/example-repository"
Assert-Equal "ghe.example" $hostQualifiedRouting.hostname "A host-qualified repository should supply the API hostname."
Assert-Equal "example-owner/example-repository" $hostQualifiedRouting.apiRepository "API routing should strip the hostname from the repository path."
Assert-Equal "ghe.example/example-owner/example-repository" $hostQualifiedRouting.selector "The CLI selector should retain the hostname."
Assert-Equal $true (Test-CodexReviewerEvidence -Login "chatgpt-codex-connector" -AuthorType "Organization") "A recognizable non-user Codex service identity should establish evidence."
Assert-Equal $false (Test-CodexReviewerEvidence -Login "human-codex-reviewer" -AuthorType "User") "A user-controlled Codex-like login should not establish identity evidence."

Write-Output "All wait-for-pr-review tests passed."
