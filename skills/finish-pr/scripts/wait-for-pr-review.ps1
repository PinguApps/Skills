[CmdletBinding(DefaultParameterSetName = "Wait")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Capture")]
    [switch]$CaptureBaseline,

    [Parameter(Mandatory = $true, ParameterSetName = "Wait")]
    [switch]$Wait,

    [Parameter(Mandatory = $true)]
    [string]$StatePath,

    [int]$PrNumber,

    [Parameter(Mandatory = $true, ParameterSetName = "Capture")]
    [string]$ReviewerLogin,

    [Parameter(Mandatory = $true, ParameterSetName = "Wait")]
    [string]$ExpectedHeadSha,

    [Parameter(Mandatory = $true, ParameterSetName = "Wait")]
    [DateTimeOffset]$PushedAt,

    [Parameter(ParameterSetName = "Wait")]
    [ValidateRange(1, 120)]
    [int]$TimeoutMinutes = 25,

    [Parameter(ParameterSetName = "Wait")]
    [ValidateRange(5, 300)]
    [int]$PollSeconds = 20
)

$ErrorActionPreference = "Stop"

function Invoke-GhJson {
    param([Parameter(Mandatory = $true)][string[]]$GhArgs)

    $output = & gh @GhArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ($output -join [Environment]::NewLine)
    }

    $json = $output -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($json)) {
        return $null
    }

    return $json | ConvertFrom-Json -Depth 100
}

function Normalize-ReviewerLogin {
    param([AllowNull()][string]$Login)

    if ([string]::IsNullOrWhiteSpace($Login)) {
        return ""
    }

    return $Login.Trim().ToLowerInvariant() -replace '\[bot\]$', ''
}

function Expand-PaginatedItems {
    param([AllowNull()]$Pages)

    foreach ($page in @($Pages)) {
        foreach ($item in @($page)) {
            $item
        }
    }
}

function Test-ReactionPredatesPush {
    param(
        [Parameter(Mandatory = $true)]$Reaction,
        [Parameter(Mandatory = $true)][DateTimeOffset]$PushCompletedAt
    )

    if ($null -eq $Reaction.createdAt) {
        return $true
    }

    try {
        $createdAt = [DateTimeOffset]$Reaction.createdAt
    } catch {
        return $true
    }

    return $createdAt -le $PushCompletedAt
}

function Get-PrReviewSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][int]$Number
    )

    $pr = Invoke-GhJson @(
        "pr", "view", $Number.ToString(),
        "--json", "number,url,state,headRefOid,comments,reviews"
    )
    $reactionPages = Invoke-GhJson @(
        "api", "repos/$Repository/issues/$Number/reactions", "--paginate", "--slurp"
    )
    $reactions = @(Expand-PaginatedItems $reactionPages)

    $threadScript = Join-Path $PSScriptRoot "get-unresolved-pr-threads.ps1"
    $threadJson = & $threadScript -PrNumber $Number -All
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to fetch pull request review threads."
    }
    $threadData = ($threadJson -join [Environment]::NewLine) | ConvertFrom-Json -Depth 100

    $feedbackItems = @()
    foreach ($thread in @($threadData.threads)) {
        foreach ($comment in @($thread.comments.nodes)) {
            $feedbackItems += [pscustomobject]@{
                id = [string]$comment.id
                kind = "thread_comment"
                authorLogin = [string]$comment.author.login
                body = [string]$comment.body
                url = [string]$comment.url
                createdAt = $comment.createdAt
                threadId = [string]$thread.id
            }
        }
    }

    foreach ($comment in @($pr.comments)) {
        $feedbackItems += [pscustomobject]@{
            id = [string]$comment.id
            kind = "issue_comment"
            authorLogin = [string]$comment.author.login
            body = [string]$comment.body
            url = [string]$comment.url
            createdAt = $comment.createdAt
            threadId = $null
        }
    }

    foreach ($review in @($pr.reviews)) {
        $feedbackItems += [pscustomobject]@{
            id = [string]$review.id
            kind = "review"
            authorLogin = [string]$review.author.login
            body = [string]$review.body
            url = [string]$pr.url
            createdAt = $review.submittedAt
            threadId = $null
        }
    }

    $reactionItems = foreach ($reaction in @($reactions)) {
        [pscustomobject]@{
            id = [string]$reaction.id
            content = [string]$reaction.content
            authorLogin = [string]$reaction.user.login
            createdAt = $reaction.created_at
        }
    }

    return [pscustomobject]@{
        pullRequest = [pscustomobject]@{
            number = [int]$pr.number
            url = [string]$pr.url
            state = [string]$pr.state
            headSha = [string]$pr.headRefOid
        }
        reactions = @($reactionItems | Where-Object { $null -ne $_ })
        feedbackItems = @($feedbackItems | Where-Object { $null -ne $_ })
    }
}

function Resolve-ReviewOutcome {
    param(
        [Parameter(Mandatory = $true)]$Baseline,
        [Parameter(Mandatory = $true)]$Snapshot,
        [Parameter(Mandatory = $true)][string]$ExpectedSha,
        [Parameter(Mandatory = $true)][string]$Reviewer,
        [string]$BaselineSha = "",
        [bool]$ReviewStartedObserved,
        [bool]$ApprovalCandidateObserved
    )

    if ($Snapshot.pullRequest.state -ne "OPEN") {
        return [pscustomobject]@{ status = "pr_closed"; reviewStartedObserved = $ReviewStartedObserved; approvalCandidateObserved = $false; newFeedback = @() }
    }

    if ($Snapshot.pullRequest.headSha -ne $ExpectedSha) {
        if (-not [string]::IsNullOrWhiteSpace($BaselineSha) -and $Snapshot.pullRequest.headSha -eq $BaselineSha) {
            return [pscustomobject]@{ status = "waiting"; reviewStartedObserved = $ReviewStartedObserved; approvalCandidateObserved = $false; newFeedback = @() }
        }

        return [pscustomobject]@{ status = "head_changed"; reviewStartedObserved = $ReviewStartedObserved; approvalCandidateObserved = $false; newFeedback = @() }
    }

    $normalizedReviewer = Normalize-ReviewerLogin $Reviewer
    $seenFeedbackIds = @($Baseline.seenFeedbackIds)
    $seenReactionIds = @($Baseline.seenReactionIds)
    $newFeedback = @($Snapshot.feedbackItems | Where-Object {
        (Normalize-ReviewerLogin $_.authorLogin) -eq $normalizedReviewer -and
        $_.id -notin $seenFeedbackIds
    })

    if ($newFeedback.Count -gt 0) {
        return [pscustomobject]@{ status = "feedback"; reviewStartedObserved = $ReviewStartedObserved; approvalCandidateObserved = $false; newFeedback = $newFeedback }
    }

    $newReviewerReactions = @($Snapshot.reactions | Where-Object {
        (Normalize-ReviewerLogin $_.authorLogin) -eq $normalizedReviewer -and
        $_.id -notin $seenReactionIds
    })
    $hasEyes = @($newReviewerReactions | Where-Object { $_.content -eq "eyes" }).Count -gt 0
    $hasThumbsUp = @($newReviewerReactions | Where-Object { $_.content -eq "+1" }).Count -gt 0
    $started = $ReviewStartedObserved -or $hasEyes

    if ($hasThumbsUp) {
        if ($ApprovalCandidateObserved) {
            return [pscustomobject]@{ status = "approved"; reviewStartedObserved = $true; approvalCandidateObserved = $true; newFeedback = @() }
        }

        return [pscustomobject]@{ status = "approval_candidate"; reviewStartedObserved = $true; approvalCandidateObserved = $true; newFeedback = @() }
    }

    return [pscustomobject]@{ status = "waiting"; reviewStartedObserved = $started; approvalCandidateObserved = $false; newFeedback = @() }
}

function Initialize-ExpectedHeadReactionBaseline {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Snapshot,
        [Parameter(Mandatory = $true)][string]$ExpectedSha,
        [Parameter(Mandatory = $true)][string]$Reviewer,
        [Parameter(Mandatory = $true)][DateTimeOffset]$PushCompletedAt
    )

    $alreadyInitialized = $State.PSObject.Properties.Name -contains "expectedHeadReactionsCaptured" -and
        [bool]$State.expectedHeadReactionsCaptured
    if ($alreadyInitialized -or $Snapshot.pullRequest.headSha -ne $ExpectedSha) {
        return $false
    }

    $normalizedReviewer = Normalize-ReviewerLogin $Reviewer
    $prePushReactionIds = @($Snapshot.reactions |
        Where-Object { Test-ReactionPredatesPush -Reaction $_ -PushCompletedAt $PushCompletedAt } |
        ForEach-Object { $_.id } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $combinedReactionIds = @($State.seenReactionIds) + $prePushReactionIds
    $State.seenReactionIds = @($combinedReactionIds | Sort-Object -Unique)
    $State.reviewStartedObserved = [bool]$State.reviewStartedObserved -or @($Snapshot.reactions | Where-Object {
        (Normalize-ReviewerLogin $_.authorLogin) -eq $normalizedReviewer -and
        $_.content -eq "eyes"
    }).Count -gt 0
    $State.approvalCandidateObserved = $false

    if ($State.PSObject.Properties.Name -contains "expectedHeadReactionsCaptured") {
        $State.expectedHeadReactionsCaptured = $true
    } else {
        $State | Add-Member -NotePropertyName expectedHeadReactionsCaptured -NotePropertyValue $true
    }

    return $true
}

function Update-BaselineHeadReactionObservations {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Snapshot
    )

    $expectedHeadObserved = $State.PSObject.Properties.Name -contains "expectedHeadReactionsCaptured" -and
        [bool]$State.expectedHeadReactionsCaptured
    if ($expectedHeadObserved -or $Snapshot.pullRequest.headSha -ne $State.baselineHeadSha) {
        return $false
    }

    $observedIds = @($Snapshot.reactions |
        ForEach-Object { $_.id } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $combinedIds = @($State.seenReactionIds) + $observedIds
    $State.seenReactionIds = @($combinedIds | Sort-Object -Unique)

    return $true
}

function Save-ReviewState {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        $null = New-Item -ItemType Directory -Force -Path $parent
    }

    $State | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $Path
}

function Invoke-PrReviewWatcher {
    if ($CaptureBaseline) {
        $repo = Invoke-GhJson @("repo", "view", "--json", "owner,name")
        $repository = "$($repo.owner.login)/$($repo.name)"
        if ($PrNumber -le 0) {
            $pr = Invoke-GhJson @("pr", "view", "--json", "number")
            $script:PrNumber = [int]$pr.number
        }

        $snapshot = Get-PrReviewSnapshot -Repository $repository -Number $PrNumber
        $normalizedReviewer = Normalize-ReviewerLogin $ReviewerLogin
        $reviewStartedObserved = @($snapshot.reactions | Where-Object {
            (Normalize-ReviewerLogin $_.authorLogin) -eq $normalizedReviewer -and
            $_.content -eq "eyes"
        }).Count -gt 0
        $state = [pscustomobject]@{
            version = 1
            repository = $repository
            prNumber = $PrNumber
            reviewerLogin = $normalizedReviewer
            capturedAt = [DateTimeOffset]::UtcNow.ToString("o")
            baselineHeadSha = $snapshot.pullRequest.headSha
            seenReactionIds = @($snapshot.reactions | ForEach-Object { $_.id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            seenFeedbackIds = @($snapshot.feedbackItems | ForEach-Object { $_.id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            reviewStartedObserved = $reviewStartedObserved
            approvalCandidateObserved = $false
            expectedHeadReactionsCaptured = $false
        }
        Save-ReviewState -State $state -Path $StatePath

        [pscustomobject]@{
            status = "baseline_captured"
            statePath = $StatePath
            repository = $repository
            prNumber = $PrNumber
            reviewerLogin = $state.reviewerLogin
            headSha = $state.baselineHeadSha
        } | ConvertTo-Json -Depth 10
        return
    }

    if (-not (Test-Path -LiteralPath $StatePath)) {
        throw "Review baseline state does not exist: $StatePath"
    }

    $state = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json -Depth 100
    $deadline = [DateTimeOffset]::UtcNow.AddMinutes($TimeoutMinutes)

    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        $snapshot = Get-PrReviewSnapshot -Repository $state.repository -Number ([int]$state.prNumber)
        if (Update-BaselineHeadReactionObservations -State $state -Snapshot $snapshot) {
            Save-ReviewState -State $state -Path $StatePath
        }
        if (Initialize-ExpectedHeadReactionBaseline -State $state -Snapshot $snapshot -ExpectedSha $ExpectedHeadSha -Reviewer $state.reviewerLogin -PushCompletedAt $PushedAt) {
            Save-ReviewState -State $state -Path $StatePath
        }
        $outcome = Resolve-ReviewOutcome `
            -Baseline $state `
            -Snapshot $snapshot `
            -ExpectedSha $ExpectedHeadSha `
            -Reviewer $state.reviewerLogin `
            -BaselineSha $state.baselineHeadSha `
            -ReviewStartedObserved ([bool]$state.reviewStartedObserved) `
            -ApprovalCandidateObserved ([bool]$state.approvalCandidateObserved)

        $state.reviewStartedObserved = $outcome.reviewStartedObserved
        $state.approvalCandidateObserved = $outcome.approvalCandidateObserved
        Save-ReviewState -State $state -Path $StatePath

        if ($outcome.status -in @("feedback", "approved", "head_changed", "pr_closed")) {
            [pscustomobject]@{
                status = $outcome.status
                repository = $state.repository
                prNumber = $state.prNumber
                reviewerLogin = $state.reviewerLogin
                expectedHeadSha = $ExpectedHeadSha
                actualHeadSha = $snapshot.pullRequest.headSha
                reviewStartedObserved = $outcome.reviewStartedObserved
                newFeedback = @($outcome.newFeedback)
            } | ConvertTo-Json -Depth 100
            return
        }

        Start-Sleep -Seconds $PollSeconds
    }

    [pscustomobject]@{
        status = "timeout"
        repository = $state.repository
        prNumber = $state.prNumber
        reviewerLogin = $state.reviewerLogin
        expectedHeadSha = $ExpectedHeadSha
        reviewStartedObserved = [bool]$state.reviewStartedObserved
        timeoutMinutes = $TimeoutMinutes
        newFeedback = @()
    } | ConvertTo-Json -Depth 20
}

if ($MyInvocation.InvocationName -ne ".") {
    Invoke-PrReviewWatcher
}
