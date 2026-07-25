$ErrorActionPreference = "Stop"

. "$PSScriptRoot\..\scripts\wait-for-pr-review.ps1" `
    -Wait `
    -StatePath "unused-test-state.json" `
    -ExpectedHeadSha "unused-test-sha" `
    -PushedAt ([DateTimeOffset]::UtcNow)

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

$eyes = [pscustomobject]@{ id = "new-eyes"; content = "eyes"; authorLogin = "example-codex-reviewer[bot]" }
$started = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -Reactions @($eyes)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewStartedObserved $false -ApprovalCandidateObserved $false
Assert-Equal "waiting" $started.status "Seeing eyes should keep waiting."
Assert-Equal $true $started.reviewStartedObserved "Seeing eyes should record that review started."

$comment = [pscustomobject]@{ id = "new-comment"; kind = "thread_comment"; authorLogin = $reviewer; body = "Please fix this." }
$feedback = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -FeedbackItems @($comment)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewStartedObserved $true -ApprovalCandidateObserved $false
Assert-Equal "feedback" $feedback.status "A new reviewer comment should return feedback."
Assert-Equal 1 $feedback.newFeedback.Count "New feedback should be returned."

$thumb = [pscustomobject]@{ id = "new-thumb"; content = "+1"; authorLogin = "example-codex-reviewer[bot]" }
$candidate = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -Reactions @($thumb)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewStartedObserved $false -ApprovalCandidateObserved $false
Assert-Equal "approval_candidate" $candidate.status "A thumbs-up should become an approval candidate even when no eyes reaction was sampled."
$approved = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -Reactions @($thumb)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewStartedObserved $false -ApprovalCandidateObserved $true
Assert-Equal "approved" $approved.status "A stable thumbs-up should approve without requiring an eyes reaction."

$retainedEyesCandidate = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -Reactions @($eyes, $thumb)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewStartedObserved $true -ApprovalCandidateObserved $false
Assert-Equal "approval_candidate" $retainedEyesCandidate.status "A retained start reaction must not suppress approval."
$retainedEyesApproved = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -Reactions @($eyes, $thumb)) -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewStartedObserved $true -ApprovalCandidateObserved $true
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

$racedApprovalState = [pscustomobject]@{
    seenReactionIds = @("old-thumb")
    seenFeedbackIds = @("old-comment")
    reviewStartedObserved = $false
    approvalCandidateObserved = $false
}
$racedApprovalSnapshot = New-Snapshot -Reactions @($eyes, $thumb)
$pushCompletedAt = [DateTimeOffset]::UtcNow
$initialized = Initialize-ExpectedHeadReactionBaseline -State $racedApprovalState -Snapshot $racedApprovalSnapshot -ExpectedSha "new-sha" -Reviewer $reviewer -PushCompletedAt $pushCompletedAt
Assert-Equal $true $initialized "The expected head should refresh the reaction baseline once."
Assert-Equal $true $racedApprovalState.reviewStartedObserved "The refreshed baseline should preserve a review start reaction."
Assert-Equal 3 $racedApprovalState.seenReactionIds.Count "The refreshed baseline should preserve old reactions and consume reactions that raced the push."
$racedApproval = Resolve-ReviewOutcome -Baseline $racedApprovalState -Snapshot $racedApprovalSnapshot -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewStartedObserved $racedApprovalState.reviewStartedObserved -ApprovalCandidateObserved $false
Assert-Equal "waiting" $racedApproval.status "An approval present before the pushed head was observed must not approve it."
$initializedAgain = Initialize-ExpectedHeadReactionBaseline -State $racedApprovalState -Snapshot $racedApprovalSnapshot -ExpectedSha "new-sha" -Reviewer $reviewer -PushCompletedAt $pushCompletedAt
Assert-Equal $false $initializedAgain "The expected-head reaction baseline should initialize only once."

$prePushEyes = [pscustomobject]@{ id = "pre-push-eyes"; content = "eyes"; authorLogin = $reviewer; createdAt = $pushCompletedAt.AddSeconds(-1) }
$postPushThumb = [pscustomobject]@{ id = "post-push-thumb"; content = "+1"; authorLogin = $reviewer; createdAt = $pushCompletedAt.AddSeconds(1) }
$postPushApprovalState = [pscustomobject]@{
    seenReactionIds = @()
    seenFeedbackIds = @()
    reviewStartedObserved = $false
    approvalCandidateObserved = $false
}
$postPushApprovalSnapshot = New-Snapshot -Reactions @($prePushEyes, $postPushThumb)
$null = Initialize-ExpectedHeadReactionBaseline -State $postPushApprovalState -Snapshot $postPushApprovalSnapshot -ExpectedSha "new-sha" -Reviewer $reviewer -PushCompletedAt $pushCompletedAt
Assert-Equal 1 $postPushApprovalState.seenReactionIds.Count "Expected-head initialization should consume only pre-push reactions."
$postPushApproval = Resolve-ReviewOutcome -Baseline $postPushApprovalState -Snapshot $postPushApprovalSnapshot -ExpectedSha "new-sha" -Reviewer $reviewer -ReviewStartedObserved $postPushApprovalState.reviewStartedObserved -ApprovalCandidateObserved $false
Assert-Equal "approval_candidate" $postPushApproval.status "A post-push approval should remain visible after expected-head initialization."

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
$null = Initialize-ExpectedHeadReactionBaseline -State $propagationState -Snapshot $newHeadAfterPropagation -ExpectedSha "new-sha" -Reviewer $reviewer -PushCompletedAt $pushCompletedAt
$stalePropagationApproval = Resolve-ReviewOutcome -Baseline $propagationState -Snapshot $newHeadAfterPropagation -ExpectedSha "new-sha" -Reviewer $reviewer -BaselineSha "old-sha" -ReviewStartedObserved $false -ApprovalCandidateObserved $false
Assert-Equal "waiting" $stalePropagationApproval.status "A reaction first observed on the baseline head must not approve the expected head."

$baselinePath = Join-Path ([IO.Path]::GetTempPath()) "finish-pr-wait-review-baseline-test.json"
function Invoke-GhJson {
    return [pscustomobject]@{
        owner = [pscustomobject]@{ login = "example-owner" }
        name = "example-repository"
    }
}
function Get-PrReviewSnapshot {
    return New-Snapshot -Reactions @($eyes)
}

try {
    $CaptureBaseline = $true
    $StatePath = $baselinePath
    $PrNumber = 25
    $ReviewerLogin = $reviewer
    Invoke-PrReviewWatcher | Out-Null
    $capturedBaseline = Get-Content -Raw -LiteralPath $baselinePath | ConvertFrom-Json -Depth 100
    Assert-Equal $true $capturedBaseline.reviewStartedObserved "Baseline capture should preserve an existing reviewer start reaction."
}
finally {
    Remove-Item -LiteralPath $baselinePath -ErrorAction SilentlyContinue
}

Write-Output "All wait-for-pr-review tests passed."
