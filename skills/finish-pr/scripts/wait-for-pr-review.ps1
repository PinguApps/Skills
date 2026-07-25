[CmdletBinding(DefaultParameterSetName = "Wait")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Capture")]
    [switch]$CaptureBaseline,

    [Parameter(Mandatory = $true, ParameterSetName = "Wait")]
    [switch]$Wait,

    [Parameter(Mandatory = $true)]
    [string]$StatePath,

    [int]$PrNumber,

    [Parameter(ParameterSetName = "Capture")]
    [AllowEmptyString()]
    [string]$ReviewerLogin,

    [Parameter(ParameterSetName = "Capture")]
    [string]$Repository,

    [Parameter(ParameterSetName = "Capture")]
    [string]$Hostname,

    [Parameter(ParameterSetName = "Capture")]
    [switch]$PreserveExistingReviewStart,

    [Parameter(Mandatory = $true, ParameterSetName = "Wait")]
    [string]$ExpectedHeadSha,

    [Parameter(Mandatory = $true, ParameterSetName = "Wait")]
    [DateTimeOffset]$ReviewRequestedAt,

    [Parameter(ParameterSetName = "Wait")]
    [ValidateRange(1, 120)]
    [int]$TimeoutMinutes = 25,

    [Parameter(ParameterSetName = "Wait")]
    [ValidateRange(5, 300)]
    [int]$PollSeconds = 20,

    [Parameter(ParameterSetName = "Wait")]
    [ValidateRange(0, 300)]
    [int]$ReviewStartGraceSeconds = 0
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

function Test-CodexReviewerEvidence {
    param(
        [AllowNull()][string]$Login,
        [AllowNull()][string]$AuthorType
    )

    $normalizedLogin = Normalize-ReviewerLogin $Login
    return $normalizedLogin -match '(?i)(?:^|[-_])codex(?:$|[-_])' -and
        $AuthorType -in @("App", "Bot", "Organization")
}

function Find-NewReviewerCandidates {
    param(
        [Parameter(Mandatory = $true)]$Baseline,
        [Parameter(Mandatory = $true)]$Snapshot,
        [DateTimeOffset]$NotBefore = [DateTimeOffset]::MinValue,
        [string]$ExcludedLogin,
        [string]$ExpectedHeadSha
    )

    if (-not [string]::IsNullOrWhiteSpace($ExpectedHeadSha) -and
        $Snapshot.pullRequest.headSha -ne $ExpectedHeadSha) {
        return @()
    }

    $cutoff = if ($NotBefore -eq [DateTimeOffset]::MinValue) {
        [DateTimeOffset]::MinValue
    } else {
        $NotBefore.AddTicks(-($NotBefore.Ticks % [TimeSpan]::TicksPerSecond))
    }
    $candidateLogins = @(
        $Snapshot.reactions | Where-Object {
            $_.id -notin @($Baseline.seenReactionIds) -and
            $_.content -in @("eyes", "+1") -and
            (Test-CodexReviewerEvidence -Login $_.authorLogin -AuthorType $_.authorType) -and
            ($cutoff -eq [DateTimeOffset]::MinValue -or
                (-not [string]::IsNullOrWhiteSpace([string]$_.createdAt) -and
                    [DateTimeOffset]$_.createdAt -ge $cutoff))
        } | ForEach-Object { Normalize-ReviewerLogin $_.authorLogin }

        $Snapshot.feedbackItems | Where-Object {
            $_.id -notin @($Baseline.seenFeedbackIds) -and
            (Test-ActionableFeedbackItem $_) -and
            (Test-CodexReviewerEvidence -Login $_.authorLogin -AuthorType $_.authorType) -and
            ($cutoff -eq [DateTimeOffset]::MinValue -or
                (-not [string]::IsNullOrWhiteSpace([string]$_.createdAt) -and
                    [DateTimeOffset]$_.createdAt -ge $cutoff))
        } | ForEach-Object { Normalize-ReviewerLogin $_.authorLogin }
    )

    $normalizedExcludedLogin = Normalize-ReviewerLogin $ExcludedLogin
    return @($candidateLogins |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and
            $_ -ne $normalizedExcludedLogin
        } |
        Sort-Object -Unique)
}

function Test-ReviewStartGraceExpired {
    param(
        [int]$GraceSeconds,
        [bool]$ReviewStartedObserved,
        [DateTimeOffset]$SnapshotStartedAt,
        [DateTimeOffset]$ReviewStartDeadline,
        [string]$CurrentHeadSha,
        [string]$ExpectedHeadSha
    )

    return $GraceSeconds -gt 0 -and
        -not $ReviewStartedObserved -and
        $SnapshotStartedAt -ge $ReviewStartDeadline -and
        $CurrentHeadSha -eq $ExpectedHeadSha
}

function Test-ActionableFeedbackItem {
    param([Parameter(Mandatory = $true)]$Item)

    $body = [string]$Item.body
    if ([string]::IsNullOrWhiteSpace($body)) {
        return $false
    }

    $trimmedBody = $body.Trim()
    if ($Item.kind -eq "review") {
        if ($Item.reviewState -in @("DISMISSED", "PENDING")) {
            return $false
        }

        if ($trimmedBody -match '^###\s+💡\s+Codex Review\b') {
            return $false
        }
    }

    return $trimmedBody -notmatch '^(?:lgtm|looks good(?: to me)?|approved|acknowledged|thanks|thank you|done|👍)[.! ]*$'
}

function Expand-PaginatedItems {
    param([AllowNull()]$Pages)

    foreach ($page in @($Pages)) {
        foreach ($item in @($page)) {
            $item
        }
    }
}

function Resolve-RepositoryRouting {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [string]$Hostname
    )

    $parts = $Repository.Split("/")
    if ($parts.Count -eq 3) {
        if ([string]::IsNullOrWhiteSpace($Hostname)) {
            $Hostname = $parts[0]
        } elseif ($Hostname -ne $parts[0]) {
            throw "-Hostname does not match the hostname in -Repository."
        }
        $apiRepository = "$($parts[1])/$($parts[2])"
    } elseif ($parts.Count -eq 2) {
        $apiRepository = $Repository
    } else {
        throw "-Repository must use the owner/name or hostname/owner/name format."
    }

    $selector = if ([string]::IsNullOrWhiteSpace($Hostname)) {
        $apiRepository
    } else {
        "$Hostname/$apiRepository"
    }

    return [pscustomobject]@{
        hostname = $Hostname
        apiRepository = $apiRepository
        selector = $selector
    }
}

function Get-PrReviewSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][int]$Number,
        [string]$Hostname,
        [ValidateRange(1, 3)][int]$Attempt = 1
    )

    $routing = Resolve-RepositoryRouting -Repository $Repository -Hostname $Hostname
    $pr = Invoke-GhJson @(
        "pr", "view", $Number.ToString(), "--repo", $routing.selector,
        "--json", "number,url,state,headRefOid"
    )
    $apiPrefix = @("api")
    if (-not [string]::IsNullOrWhiteSpace($routing.hostname)) {
        $apiPrefix += @("--hostname", $routing.hostname)
    }
    $reactionArgs = $apiPrefix + @("repos/$($routing.apiRepository)/issues/$Number/reactions", "--paginate", "--slurp")
    $reactionPages = Invoke-GhJson $reactionArgs
    $reactions = @(Expand-PaginatedItems $reactionPages)
    $commentPages = Invoke-GhJson ($apiPrefix + @("repos/$($routing.apiRepository)/issues/$Number/comments", "--paginate", "--slurp"))
    $comments = @(Expand-PaginatedItems $commentPages)
    $reviewPages = Invoke-GhJson ($apiPrefix + @("repos/$($routing.apiRepository)/pulls/$Number/reviews", "--paginate", "--slurp"))
    $reviews = @(Expand-PaginatedItems $reviewPages)

    $threadScript = Join-Path $PSScriptRoot "get-unresolved-pr-threads.ps1"
    $threadJson = & $threadScript -PrNumber $Number -Repository $routing.selector -Hostname $routing.hostname -All
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to fetch pull request review threads."
    }
    $threadData = ($threadJson -join [Environment]::NewLine) | ConvertFrom-Json -Depth 100

    $feedbackItems = @()
    foreach ($thread in @($threadData.threads)) {
        if ([bool]$thread.isResolved) {
            continue
        }
        foreach ($comment in @($thread.comments.nodes)) {
            $feedbackItems += [pscustomobject]@{
                id = [string]$comment.id
                kind = "thread_comment"
                authorLogin = [string]$comment.author.login
                authorType = [string]$comment.author.__typename
                body = [string]$comment.body
                url = [string]$comment.url
                createdAt = $comment.createdAt
                updatedAt = $comment.updatedAt
                threadId = [string]$thread.id
            }
        }
    }

    foreach ($comment in $comments) {
        $feedbackItems += [pscustomobject]@{
            id = [string]$comment.node_id
            kind = "issue_comment"
            authorLogin = [string]$comment.user.login
            authorType = [string]$comment.user.type
            body = [string]$comment.body
            url = [string]$comment.html_url
            createdAt = $comment.created_at
            updatedAt = $comment.updated_at
            threadId = $null
        }
    }

    foreach ($review in $reviews) {
        $feedbackItems += [pscustomobject]@{
            id = [string]$review.node_id
            kind = "review"
            authorLogin = [string]$review.user.login
            authorType = [string]$review.user.type
            body = [string]$review.body
            url = [string]$review.html_url
            createdAt = $review.submitted_at
            updatedAt = $review.submitted_at
            reviewState = ([string]$review.state).ToUpperInvariant()
            threadId = $null
        }
    }

    $reactionItems = foreach ($reaction in @($reactions)) {
        [pscustomobject]@{
            id = [string]$reaction.id
            content = [string]$reaction.content
            authorLogin = [string]$reaction.user.login
            authorType = [string]$reaction.user.type
            createdAt = $reaction.created_at
        }
    }

    $verifiedPr = Invoke-GhJson @(
        "pr", "view", $Number.ToString(), "--repo", $routing.selector,
        "--json", "headRefOid"
    )
    if ($verifiedPr.headRefOid -ne $pr.headRefOid) {
        if ($Attempt -ge 3) {
            throw "Pull request HEAD changed repeatedly while collecting a review snapshot."
        }

        return Get-PrReviewSnapshot -Repository $Repository -Number $Number -Hostname $Hostname -Attempt ($Attempt + 1)
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
        [DateTimeOffset]$ReviewRequestedAt = [DateTimeOffset]::MinValue,
        [DateTimeOffset]$ReviewHeadBoundary = [DateTimeOffset]::MinValue,
        [bool]$ReviewStartedObserved,
        [bool]$ApprovalCandidateObserved
    )

    if ($Snapshot.pullRequest.state -ne "OPEN") {
        return [pscustomobject]@{ status = "pr_closed"; reviewStartedObserved = $ReviewStartedObserved; approvalCandidateObserved = $false; newFeedback = @() }
    }

    if ($Snapshot.pullRequest.headSha -ne $ExpectedSha) {
        $expectedHeadObserved = $Baseline.PSObject.Properties.Name -contains "expectedHeadReactionsCaptured" -and
            [bool]$Baseline.expectedHeadReactionsCaptured
        if (-not $expectedHeadObserved -and
            -not [string]::IsNullOrWhiteSpace($BaselineSha) -and
            $Snapshot.pullRequest.headSha -eq $BaselineSha) {
            return [pscustomobject]@{ status = "waiting"; reviewStartedObserved = $ReviewStartedObserved; approvalCandidateObserved = $false; newFeedback = @() }
        }

        return [pscustomobject]@{ status = "head_changed"; reviewStartedObserved = $ReviewStartedObserved; approvalCandidateObserved = $false; newFeedback = @() }
    }

    $normalizedReviewer = Normalize-ReviewerLogin $Reviewer
    $seenFeedbackIds = @($Baseline.seenFeedbackIds)
    $seenFeedbackVersions = if ($Baseline.PSObject.Properties.Name -contains "seenFeedbackVersions") {
        @($Baseline.seenFeedbackVersions)
    } else {
        @()
    }
    $seenReactionIds = @($Baseline.seenReactionIds)
    $feedbackCutoff = if ($ReviewHeadBoundary -ne [DateTimeOffset]::MinValue) {
        $ReviewHeadBoundary.AddTicks(-($ReviewHeadBoundary.Ticks % [TimeSpan]::TicksPerSecond))
    } elseif ($ReviewRequestedAt -eq [DateTimeOffset]::MinValue) {
        [DateTimeOffset]::MinValue
    } else {
        [DateTimeOffset]::MaxValue
    }
    $newFeedback = @($Snapshot.feedbackItems | Where-Object {
        if ((Normalize-ReviewerLogin $_.authorLogin) -ne $normalizedReviewer) {
            return $false
        }

        if (-not (Test-ActionableFeedbackItem $_)) {
            return $false
        }

        if ($feedbackCutoff -ne [DateTimeOffset]::MinValue) {
            $feedbackTimestampText = if (-not [string]::IsNullOrWhiteSpace([string]$_.updatedAt)) {
                [string]$_.updatedAt
            } else {
                [string]$_.createdAt
            }
            if ([string]::IsNullOrWhiteSpace($feedbackTimestampText) -or
                [DateTimeOffset]$feedbackTimestampText -lt $feedbackCutoff) {
                return $false
            }
        }

        if ($_.id -notin $seenFeedbackIds) {
            return $true
        }

        $seenVersion = $seenFeedbackVersions | Where-Object id -eq $_.id | Select-Object -First 1
        if ($null -eq $seenVersion) {
            return $false
        }

        return [string]$_.updatedAt -ne [string]$seenVersion.updatedAt -or
            [string]$_.body -ne [string]$seenVersion.body
    })

    if ($newFeedback.Count -gt 0) {
        return [pscustomobject]@{ status = "feedback"; reviewStartedObserved = $ReviewStartedObserved; approvalCandidateObserved = $false; newFeedback = $newFeedback }
    }

    $reviewRequestCutoff = if ($ReviewRequestedAt -eq [DateTimeOffset]::MinValue) {
        [DateTimeOffset]::MinValue
    } else {
        $ReviewRequestedAt.AddTicks(-($ReviewRequestedAt.Ticks % [TimeSpan]::TicksPerSecond))
    }
    $newReviewerReactions = @($Snapshot.reactions | Where-Object {
        (Normalize-ReviewerLogin $_.authorLogin) -eq $normalizedReviewer -and
        $_.id -notin $seenReactionIds -and
        ($reviewRequestCutoff -eq [DateTimeOffset]::MinValue -or
            (-not [string]::IsNullOrWhiteSpace([string]$_.createdAt) -and
                [DateTimeOffset]$_.createdAt -ge $reviewRequestCutoff))
    })
    $hasEyes = @($newReviewerReactions | Where-Object { $_.content -eq "eyes" }).Count -gt 0
    $approvalCutoff = if ($ReviewHeadBoundary -ne [DateTimeOffset]::MinValue) {
        $ReviewHeadBoundary.AddTicks(-($ReviewHeadBoundary.Ticks % [TimeSpan]::TicksPerSecond))
    } elseif ($ReviewRequestedAt -eq [DateTimeOffset]::MinValue) {
        [DateTimeOffset]::MinValue
    } else {
        [DateTimeOffset]::MaxValue
    }
    $hasThumbsUp = @($newReviewerReactions | Where-Object {
        $_.content -eq "+1" -and
        ($approvalCutoff -eq [DateTimeOffset]::MinValue -or
            (-not [string]::IsNullOrWhiteSpace([string]$_.createdAt) -and
                [DateTimeOffset]$_.createdAt -ge $approvalCutoff))
    }).Count -gt 0
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
        [DateTimeOffset]$ReviewRequestedAt = [DateTimeOffset]::MinValue
    )

    $alreadyInitialized = $State.PSObject.Properties.Name -contains "expectedHeadReactionsCaptured" -and
        [bool]$State.expectedHeadReactionsCaptured
    $reviewBoundaryCaptured = $State.PSObject.Properties.Name -contains "reviewHeadBoundary" -and
        -not [string]::IsNullOrWhiteSpace([string]$State.reviewHeadBoundary)
    if (($alreadyInitialized -and $reviewBoundaryCaptured) -or
        $Snapshot.pullRequest.headSha -ne $ExpectedSha) {
        return $false
    }

    $normalizedReviewer = Normalize-ReviewerLogin $Reviewer
    $reviewRequestCutoff = if ($ReviewRequestedAt -eq [DateTimeOffset]::MinValue) {
        [DateTimeOffset]::MinValue
    } else {
        $ReviewRequestedAt.AddTicks(-($ReviewRequestedAt.Ticks % [TimeSpan]::TicksPerSecond))
    }
    $freshEyes = @($Snapshot.reactions | Where-Object {
        (Normalize-ReviewerLogin $_.authorLogin) -eq $normalizedReviewer -and
        $_.content -eq "eyes" -and
        $_.id -notin @($State.seenReactionIds) -and
        ($reviewRequestCutoff -eq [DateTimeOffset]::MinValue -or
            (-not [string]::IsNullOrWhiteSpace([string]$_.createdAt) -and
                [DateTimeOffset]$_.createdAt -ge $reviewRequestCutoff))
    })
    $State.reviewStartedObserved = [bool]$State.reviewStartedObserved -or $freshEyes.Count -gt 0
    $timestampedFreshEyes = @($freshEyes | Where-Object {
        -not [string]::IsNullOrWhiteSpace([string]$_.createdAt)
    })
    if ($timestampedFreshEyes.Count -gt 0) {
        $reviewHeadBoundary = ($timestampedFreshEyes |
            ForEach-Object { [DateTimeOffset]$_.createdAt } |
            Sort-Object |
            Select-Object -First 1).ToString("o")
        if ($State.PSObject.Properties.Name -contains "reviewHeadBoundary") {
            $State.reviewHeadBoundary = $reviewHeadBoundary
        } else {
            $State | Add-Member -NotePropertyName reviewHeadBoundary -NotePropertyValue $reviewHeadBoundary
        }
    }
    $State.approvalCandidateObserved = $false

    if ($State.PSObject.Properties.Name -contains "expectedHeadReactionsCaptured") {
        $State.expectedHeadReactionsCaptured = $true
    } else {
        $State | Add-Member -NotePropertyName expectedHeadReactionsCaptured -NotePropertyValue $true
    }

    return -not $alreadyInitialized -or $timestampedFreshEyes.Count -gt 0
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
        if ([string]::IsNullOrWhiteSpace($Repository)) {
            $repo = Invoke-GhJson @("repo", "view", "--json", "owner,name,url")
            $script:Hostname = ([uri]$repo.url).Authority
            $script:Repository = "$Hostname/$($repo.owner.login)/$($repo.name)"
        }
        $routing = Resolve-RepositoryRouting -Repository $Repository -Hostname $Hostname
        $script:Repository = $routing.selector
        $script:Hostname = $routing.hostname
        if ($PrNumber -le 0) {
            $pr = Invoke-GhJson @("pr", "view", "--repo", $routing.selector, "--json", "number")
            $script:PrNumber = [int]$pr.number
        }

        $snapshot = Get-PrReviewSnapshot -Repository $Repository -Number $PrNumber -Hostname $Hostname
        $normalizedReviewer = Normalize-ReviewerLogin $ReviewerLogin
        $existingReviewStartReactions = @($snapshot.reactions | Where-Object {
            (Normalize-ReviewerLogin $_.authorLogin) -eq $normalizedReviewer -and
            $_.content -eq "eyes" -and
            -not [string]::IsNullOrWhiteSpace([string]$_.createdAt)
        })
        $existingReviewBoundary = if ($PreserveExistingReviewStart -and
            $existingReviewStartReactions.Count -gt 0) {
            $earliestExistingReviewStart = [DateTimeOffset]($existingReviewStartReactions |
                ForEach-Object { [DateTimeOffset]$_.createdAt } |
                Sort-Object |
                Select-Object -First 1)
            $earliestExistingReviewStart.ToString("o")
        } else {
            $null
        }
        $viewerArgs = @("api")
        if (-not [string]::IsNullOrWhiteSpace($routing.hostname)) {
            $viewerArgs += @("--hostname", $routing.hostname)
        }
        $viewerArgs += "user"
        $viewer = Invoke-GhJson $viewerArgs
        $state = [pscustomobject]@{
            version = 1
            repository = $Repository
            hostname = $Hostname
            prNumber = $PrNumber
            reviewerLogin = $normalizedReviewer
            agentLogin = Normalize-ReviewerLogin $viewer.login
            capturedAt = [DateTimeOffset]::UtcNow.ToString("o")
            baselineHeadSha = $snapshot.pullRequest.headSha
            seenReactionIds = @($snapshot.reactions | ForEach-Object { $_.id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            seenFeedbackIds = @($snapshot.feedbackItems | ForEach-Object { $_.id } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            seenFeedbackVersions = @($snapshot.feedbackItems | ForEach-Object {
                [pscustomobject]@{
                    id = [string]$_.id
                    updatedAt = $_.updatedAt
                    body = [string]$_.body
                }
            })
            reviewStartedObserved = [bool]$PreserveExistingReviewStart -and
                $existingReviewStartReactions.Count -gt 0
            approvalCandidateObserved = $false
            expectedHeadReactionsCaptured = $false
            reviewHeadBoundary = $existingReviewBoundary
        }
        Save-ReviewState -State $state -Path $StatePath

        [pscustomobject]@{
            status = "baseline_captured"
            statePath = $StatePath
            repository = $Repository
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
    $reviewStartDeadline = if ($ReviewStartGraceSeconds -gt 0) {
        [DateTimeOffset]::UtcNow.AddSeconds($ReviewStartGraceSeconds)
    } else {
        [DateTimeOffset]::MaxValue
    }

    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        $snapshotStartedAt = [DateTimeOffset]::UtcNow
        $snapshot = Get-PrReviewSnapshot -Repository $state.repository -Number ([int]$state.prNumber) -Hostname ([string]$state.hostname)
        if ([string]::IsNullOrWhiteSpace([string]$state.reviewerLogin)) {
            $candidates = @(Find-NewReviewerCandidates -Baseline $state -Snapshot $snapshot -NotBefore $ReviewRequestedAt -ExcludedLogin ([string]$state.agentLogin) -ExpectedHeadSha $ExpectedHeadSha)
            if ($candidates.Count -gt 1) {
                [pscustomobject]@{
                    status = "reviewer_ambiguous"
                    repository = $state.repository
                    prNumber = $state.prNumber
                    expectedHeadSha = $ExpectedHeadSha
                    actualHeadSha = $snapshot.pullRequest.headSha
                    reviewerCandidates = $candidates
                    newFeedback = @()
                } | ConvertTo-Json -Depth 20
                return
            }
            if ($candidates.Count -eq 1) {
                $state.reviewerLogin = $candidates[0]
                Save-ReviewState -State $state -Path $StatePath
            }
        }
        if (Initialize-ExpectedHeadReactionBaseline -State $state -Snapshot $snapshot -ExpectedSha $ExpectedHeadSha -Reviewer $state.reviewerLogin -ReviewRequestedAt $ReviewRequestedAt) {
            Save-ReviewState -State $state -Path $StatePath
        }
        if (Update-BaselineHeadReactionObservations -State $state -Snapshot $snapshot) {
            Save-ReviewState -State $state -Path $StatePath
        }
        $outcome = Resolve-ReviewOutcome `
            -Baseline $state `
            -Snapshot $snapshot `
            -ExpectedSha $ExpectedHeadSha `
            -Reviewer $state.reviewerLogin `
            -BaselineSha $state.baselineHeadSha `
            -ReviewRequestedAt $ReviewRequestedAt `
            -ReviewHeadBoundary $(if ([string]::IsNullOrWhiteSpace([string]$state.reviewHeadBoundary)) { [DateTimeOffset]::MinValue } else { [DateTimeOffset]$state.reviewHeadBoundary }) `
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

        if (Test-ReviewStartGraceExpired `
            -GraceSeconds $ReviewStartGraceSeconds `
            -ReviewStartedObserved $outcome.reviewStartedObserved `
            -SnapshotStartedAt $snapshotStartedAt `
            -ReviewStartDeadline $reviewStartDeadline `
            -CurrentHeadSha $snapshot.pullRequest.headSha `
            -ExpectedHeadSha $ExpectedHeadSha) {
            [pscustomobject]@{
                status = "review_not_started"
                repository = $state.repository
                prNumber = $state.prNumber
                reviewerLogin = $state.reviewerLogin
                expectedHeadSha = $ExpectedHeadSha
                actualHeadSha = $snapshot.pullRequest.headSha
                reviewStartedObserved = $false
                newFeedback = @()
            } | ConvertTo-Json -Depth 20
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
