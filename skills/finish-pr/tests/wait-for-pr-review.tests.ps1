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
        [array]$FeedbackItems = @(),
        [AllowNull()]$PrAgentStatus = $null
    )

    return [pscustomobject]@{
        pullRequest = [pscustomobject]@{ headSha = $HeadSha; state = $State }
        feedbackItems = $FeedbackItems
        prAgentStatus = $PrAgentStatus
    }
}

function New-PrAgentStatus {
    param(
        [string]$State = "success",
        [string]$Description = "Approved - no findings."
    )

    return [pscustomobject]@{
        present = $true
        state = $State
        description = $Description
        url = "https://example.test/pr-agent"
    }
}

$baseline = [pscustomobject]@{
    agentLogin = "example-agent"
    baselineHeadSha = "old-sha"
    seenFeedbackVersions = @(
        [pscustomobject]@{ id = "old-comment"; body = "Old"; updatedAt = "2026-08-12T11:00:00Z" }
    )
    prAgentSeenAtBaseline = $false
}

Assert-Equal "review-bot" (Normalize-Login "Review-Bot[BOT]") "Login normalization should strip bot suffixes."

$pages = '[[{"id":"one"}],[{"id":"two"}]]' | ConvertFrom-Json -Depth 10
$expanded = @(Expand-PaginatedItems $pages)
Assert-Equal 2 $expanded.Count "Paginated REST results should be flattened."
Assert-Equal "two" $expanded[1].id "Later REST pages should be preserved."

$notRunning = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot) -ExpectedSha "new-sha"
Assert-Equal "waiting" $notRunning.status "With no reviewer history the helper should wait for feedback; callers skip waiting when PR Agent is not running."
Assert-Equal $false $notRunning.prAgentRelevant "An absent integration must not become a completion requirement."

$approvedSnapshot = New-Snapshot -PrAgentStatus (New-PrAgentStatus)
$approved = Resolve-ReviewOutcome -Baseline $baseline -Snapshot $approvedSnapshot -ExpectedSha "new-sha"
Assert-Equal "approved" $approved.status "A successful current-HEAD PR Agent status should complete without another reviewer."
Assert-Equal "pragent_approved" $approved.verdict "The terminal result should expose the PR Agent approval path."

$humanFeedback = [pscustomobject]@{
    id = "human-comment"
    kind = "thread_comment"
    authorLogin = "reviewer"
    authorType = "User"
    body = "Please handle this edge case."
    updatedAt = "2026-08-12T12:00:10Z"
}
$feedbackBeforeApproval = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -PrAgentStatus (New-PrAgentStatus) -FeedbackItems @($humanFeedback)) -ExpectedSha "new-sha"
Assert-Equal "feedback" $feedbackBeforeApproval.status "New feedback from any source must take precedence over approval."
Assert-Equal "human-comment" $feedbackBeforeApproval.newFeedback[0].id "The exact new feedback ID should be returned."

$agentFeedback = [pscustomobject]@{
    id = "agent-comment"
    kind = "issue_comment"
    authorLogin = "example-agent"
    authorType = "User"
    body = "I fixed this."
    updatedAt = "2026-08-12T12:00:10Z"
}
$agentIgnored = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -PrAgentStatus (New-PrAgentStatus) -FeedbackItems @($agentFeedback)) -ExpectedSha "new-sha"
Assert-Equal "approved" $agentIgnored.status "The agent's own replies must not be treated as new review feedback."

$emptyCopilotReview = [pscustomobject]@{
    id = "copilot-clean"
    kind = "review"
    authorLogin = "copilot-pull-request-reviewer"
    authorType = "Bot"
    body = "## Pull request overview`n`nCopilot reviewed 26 out of 26 changed files in this pull request and generated no new comments."
    reviewState = "COMMENTED"
    updatedAt = "2026-08-12T12:00:10Z"
}
$cleanCopilotIgnored = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -PrAgentStatus (New-PrAgentStatus) -FeedbackItems @($emptyCopilotReview)) -ExpectedSha "new-sha"
Assert-Equal "approved" $cleanCopilotIgnored.status "A reviewer's explicit no-findings summary must not be treated as actionable feedback."

$editedFeedback = [pscustomobject]@{
    id = "old-comment"
    kind = "issue_comment"
    authorLogin = "reviewer"
    authorType = "User"
    body = "Edited feedback"
    updatedAt = "2026-08-12T12:00:10Z"
}
$edited = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -PrAgentStatus (New-PrAgentStatus) -FeedbackItems @($editedFeedback)) -ExpectedSha "new-sha"
Assert-Equal "feedback" $edited.status "Edited feedback should wake the audit even when its ID was in the baseline."

$oldHeadPropagating = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -HeadSha "old-sha" -PrAgentStatus (New-PrAgentStatus)) -ExpectedSha "new-sha"
Assert-Equal "waiting" $oldHeadPropagating.status "The pre-push HEAD may remain visible briefly while the push propagates."
$changedHead = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -HeadSha "other-sha" -PrAgentStatus (New-PrAgentStatus)) -ExpectedSha "new-sha"
Assert-Equal "head_changed" $changedHead.status "An unexpected HEAD must stop the watcher even if its status succeeded."
$closed = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -State "MERGED") -ExpectedSha "new-sha"
Assert-Equal "pr_closed" $closed.status "A closed PR must stop the watcher."

$unchangedHeadBaseline = [pscustomobject]@{
    agentLogin = "example-agent"
    baselineHeadSha = "new-sha"
    seenFeedbackVersions = @()
}
$existingCurrentApproval = Resolve-ReviewOutcome -Baseline $unchangedHeadBaseline -Snapshot $approvedSnapshot -ExpectedSha "new-sha"
Assert-Equal "approved" $existingCurrentApproval.status "A successful current-HEAD status should support the no-push path."

$prAgentBaseline = [pscustomobject]@{
    agentLogin = "example-agent"
    baselineHeadSha = "old-sha"
    seenFeedbackVersions = $baseline.seenFeedbackVersions
    prAgentSeenAtBaseline = $true
}
$prAgentPending = Resolve-ReviewOutcome -Baseline $prAgentBaseline -Snapshot (New-Snapshot -PrAgentStatus (New-PrAgentStatus -State "pending")) -ExpectedSha "new-sha"
Assert-Equal "processing" $prAgentPending.status "A pending PR Agent status should wait as processing."
Assert-Equal $true $prAgentPending.prAgentRelevant "PR Agent should be marked relevant once seen."

$prAgentFailed = Resolve-ReviewOutcome -Baseline $prAgentBaseline -Snapshot (New-Snapshot -PrAgentStatus (New-PrAgentStatus -State "failure" -Description "2 finding(s) on new-sha")) -ExpectedSha "new-sha"
Assert-Equal "feedback" $prAgentFailed.status "A failed PR Agent status must wake the feedback loop."
Assert-Equal "pragent_status" $prAgentFailed.newFeedback[0].kind "A failed status without captured comments should be surfaced as feedback."

$prAgentAbsentAfterSeen = Resolve-ReviewOutcome -Baseline $prAgentBaseline -Snapshot (New-Snapshot) -ExpectedSha "new-sha"
Assert-Equal "processing" $prAgentAbsentAfterSeen.status "A missing head status after prior PR Agent activity should wait as processing."

$prAgentMarkerFeedback = [pscustomobject]@{
    id = "pragent-comment"
    kind = "thread_comment"
    authorLogin = "example-agent"
    authorType = "User"
    body = "<!-- pr-agent:v1 -->`n**PR Agent**`n`n**high** - Null dereference."
    updatedAt = "2026-08-12T12:00:10Z"
}
$markerOutcome = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -PrAgentStatus (New-PrAgentStatus) -FeedbackItems @($prAgentMarkerFeedback)) -ExpectedSha "new-sha"
Assert-Equal "feedback" $markerOutcome.status "PR Agent comments authored through the owner login must count as reviewer feedback."
Assert-Equal "pragent-comment" $markerOutcome.newFeedback[0].id "The PR Agent feedback ID should be returned."

$thumbsUp = [string][char]0xD83D + [string][char]0xDC4D
$thumbsUpFeedback = [pscustomobject]@{
    id = "thumbsup-comment"
    kind = "thread_comment"
    authorLogin = "reviewer"
    authorType = "User"
    body = $thumbsUp
    updatedAt = "2026-08-12T12:00:10Z"
}
$thumbsUpIgnored = Resolve-ReviewOutcome -Baseline $baseline -Snapshot (New-Snapshot -PrAgentStatus (New-PrAgentStatus) -FeedbackItems @($thumbsUpFeedback)) -ExpectedSha "new-sha"
Assert-Equal "approved" $thumbsUpIgnored.status "A lone thumbs-up acknowledgement must not be treated as actionable feedback."

$prAgentErrorState = Resolve-ReviewOutcome -Baseline $prAgentBaseline -Snapshot (New-Snapshot -PrAgentStatus (New-PrAgentStatus -State "error" -Description "review failed to run")) -ExpectedSha "new-sha"
Assert-Equal "incomplete" $prAgentErrorState.status "A service error is incomplete, not findings or approval."

foreach ($conclusion in @("success", "failure", "neutral", "cancelled", "timed_out", "skipped", "action_required", $null)) {
    $signal = Get-PrAgentSignal -Checks @([pscustomobject]@{ status = "completed"; conclusion = $conclusion })
    $expected = if ($conclusion -in @("success", "failure")) { $conclusion } else { "incomplete" }
    Assert-Equal $expected $signal.state "A completed check must have a precise terminal disposition."
    $outcome = Resolve-ReviewOutcome -Baseline $prAgentBaseline -Snapshot (New-Snapshot -PrAgentStatus $signal) -ExpectedSha "new-sha"
    $terminal = if ($expected -eq 'success') { 'approved' } elseif ($expected -eq 'failure') { 'feedback' } else { 'incomplete' }
    Assert-Equal $terminal $outcome.status "A check-run-only PR must reach the correct outcome."
}
$activeChecks = @([pscustomobject]@{ status = "completed"; conclusion = "success" }, [pscustomobject]@{ status = "queued"; conclusion = $null })
Assert-Equal 'pending' (Get-PrAgentSignal -Checks $activeChecks).state 'An active provider must block despite another success.'
Assert-Equal 'pending' (Get-PrAgentSignal -Checks @([pscustomobject]@{ status = 'in_progress' })).state 'An in-progress check must block.'
Assert-Equal 'incomplete' (Get-PrAgentSignal -Checks @([pscustomobject]@{ status = 'completed'; conclusion = 'neutral' }) -Statuses @([pscustomobject]@{ context = 'PR Agent'; state = 'success' })).state 'Legacy success cannot override an incomplete check.'
Assert-Equal 'absent' (Get-PrAgentSignal).state 'No signals means absent, not approval.'
Assert-Equal $false (Test-ActionableFeedbackItem ([pscustomobject]@{ kind = 'issue_comment'; body = '<!-- pr-agent:v1 --><!-- pr-agent:summary:v1 --> Review in progress.' })) 'Status summary updates must not create feedback cycles.'
Assert-Equal $true (Test-PrAgentMarkerBody '[![PR Agent](badge)](link) A finding.') 'Legacy badges identify reviewer feedback too.'

function Invoke-GhJson {
    param([string[]]$GhArgs)
    if ($GhArgs -notcontains '--paginate' -or $GhArgs -notcontains '--slurp') { throw 'All pages must be read.' }
    if (($GhArgs -join ' ') -match '/check-runs\?') {
        return @(
            [pscustomobject]@{ check_runs = @([pscustomobject]@{ id = 1; name = 'PR Agent'; app = @{ id = 42 }; status = 'in_progress' }) },
            [pscustomobject]@{ check_runs = @([pscustomobject]@{ id = 2; name = 'PR Agent'; app = @{ id = 42 }; status = 'completed'; conclusion = 'success' }, [pscustomobject]@{ id = 3; name = 'PR Agent'; app = @{ id = 43 }; status = 'queued' }) }
        )
    }
    throw 'Forbidden status read: current check runs already establish presence.'
}
$checks = @(Get-PrAgentChecks -ApiPrefix @('api') -ApiRepository 'owner/repo' -Sha 'head' -Context 'PR Agent')
Assert-Equal 2 $checks.Count 'Latest check per App must survive across pages.'
Assert-Equal 'pending' (Get-PrAgentSignal -Checks $checks).state 'A different App still running cannot be ignored.'
Assert-Equal $true (Test-PrAgentSeenOnPull -ApiPrefix @('api') -ApiRepository 'owner/repo' -Number 1 -Sha 'head' -Context 'PR Agent') 'Check-run-only activity must be detected.'
function Invoke-GhJson { throw 'Read denied' }
try {
    Get-CombinedStatusContexts -ApiPrefix @('api') -ApiRepository 'owner/repo' -Sha 'head' | Out-Null
    throw 'An unavailable API was mistaken for absence.'
} catch { if ($_.Exception.Message -ne 'Read denied') { throw } }

$routing = Resolve-RepositoryRouting -Repository "ghe.example/owner/repository"
Assert-Equal "ghe.example" $routing.hostname "Host-qualified repositories should preserve their host."
Assert-Equal "owner/repository" $routing.apiRepository "API routing should strip the host."

$baselinePath = Join-Path ([IO.Path]::GetTempPath()) ("finish-pr-review-baseline-{0}.json" -f [guid]::NewGuid().ToString("N"))
function Invoke-GhJson {
    param([string[]]$GhArgs)

    $joined = $GhArgs -join " "
    if ($GhArgs[0] -eq "api" -and $GhArgs[-1] -eq "user") {
        return [pscustomobject]@{ login = "example-agent" }
    }
    if ($joined -match "/status\?per_page=100") {
        return [pscustomobject]@{ statuses = @() }
    }
    if ($joined -match "/check-runs\?") {
        return @([pscustomobject]@{ check_runs = @() })
    }
    if ($joined -match "/commits\?per_page=20") {
        return @([pscustomobject]@{ sha = "commit-sha" })
    }
    throw "Unexpected gh call: $joined"
}
function Get-PrReviewSnapshot {
    return New-Snapshot -FeedbackItems @($humanFeedback)
}

try {
    $CaptureBaseline = $true
    $StatePath = $baselinePath
    $PrNumber = 25
    $Repository = "owner/repository"
    $Hostname = "ghe.example"
    Invoke-PrReviewWatcher | Out-Null

    $captured = Get-Content -Raw -LiteralPath $baselinePath | ConvertFrom-Json -Depth 100
    Assert-Equal "ghe.example/owner/repository" $captured.repository "Baseline capture should retain repository routing."
    Assert-Equal "example-agent" $captured.agentLogin "Baseline capture should record the authenticated agent."
    Assert-Equal "human-comment" $captured.seenFeedbackVersions[0].id "Baseline capture should version feedback IDs."
    Assert-Equal $false $captured.prAgentSeenAtBaseline "Baseline capture should record PR Agent absence when no status exists."

    $CaptureBaseline = $false
    $ExpectedHeadSha = "new-sha"
    function Get-PrReviewSnapshot { return New-Snapshot -PrAgentStatus (New-PrAgentStatus) }
    $result = Invoke-PrReviewWatcher | ConvertFrom-Json -Depth 100
    Assert-Equal "approved" $result.status "The watcher should return approval without waiting for another integration."
    Assert-Equal "pragent_approved" $result.verdict "The watcher should expose the review outcome verdict."
    Assert-Equal "success" $result.prAgentState "The watcher should return the current-head status."
}
finally {
    Remove-Item -LiteralPath $baselinePath -ErrorAction SilentlyContinue
}

Write-Output "All wait-for-pr-review tests passed."
