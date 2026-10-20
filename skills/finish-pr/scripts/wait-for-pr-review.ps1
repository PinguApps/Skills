[CmdletBinding(DefaultParameterSetName = "Wait")]
param(
    [Parameter(Mandatory = $true, ParameterSetName = "Capture")]
    [switch]$CaptureBaseline,

    [Parameter(Mandatory = $true, ParameterSetName = "Wait")]
    [switch]$Wait,

    [Parameter(Mandatory = $true, ParameterSetName = "Inspect")]
    [switch]$Inspect,

    [Parameter(Mandatory = $true, ParameterSetName = "Capture")]
    [Parameter(Mandatory = $true, ParameterSetName = "Wait")]
    [string]$StatePath,

    [int]$PrNumber,

    [Parameter(ParameterSetName = "Capture")]
    [Parameter(Mandatory = $true, ParameterSetName = "Inspect")]
    [string]$Repository,

    [Parameter(ParameterSetName = "Capture")]
    [Parameter(ParameterSetName = "Inspect")]
    [string]$Hostname,

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
    [int]$ReviewStartGraceSeconds = 0,

    [Parameter(ParameterSetName = "Capture")]
    [Parameter(ParameterSetName = "Wait")]
    [Parameter(ParameterSetName = "Inspect")]
    [string]$PrAgentContext = "PR Agent"
)

$ErrorActionPreference = "Stop"

function Invoke-GhJson {
    param([Parameter(Mandatory = $true)][string[]]$GhArgs)

    $ghExecutable = (Get-Command gh -CommandType Application -ErrorAction Stop).Source
    $output = & $ghExecutable @GhArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ($output -join [Environment]::NewLine)
    }

    $json = $output -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($json)) {
        return $null
    }

    return $json | ConvertFrom-Json -Depth 100
}

function Normalize-Login {
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

function Test-PrAgentMarkerBody {
    param([AllowNull()][string]$Body)

    if ([string]::IsNullOrWhiteSpace($Body)) {
        return $false
    }

    return $Body -match '(?i)pr-agent:v\d+|\[!\[PR Agent\]'
}

function Get-CombinedStatusContexts {
    param(
        [Parameter(Mandatory = $true)][string[]]$ApiPrefix,
        [Parameter(Mandatory = $true)][string]$ApiRepository,
        [Parameter(Mandatory = $true)][string]$Sha
    )

    $pages = Invoke-GhJson ($ApiPrefix + @(
        "-H", "Accept: application/vnd.github+json",
        "repos/$ApiRepository/commits/$Sha/status?per_page=100", "--paginate", "--slurp"
    ))
    foreach ($page in @($pages)) { foreach ($status in @($page.statuses)) { if ($null -ne $status) { $status } } }
}

function Get-PrAgentChecks {
    param([string[]]$ApiPrefix, [string]$ApiRepository, [string]$Sha, [string]$Context)
    $pages = Invoke-GhJson ($ApiPrefix + @(
        "-H", "Accept: application/vnd.github+json",
        "repos/$ApiRepository/commits/$Sha/check-runs?filter=all&per_page=100", "--paginate", "--slurp"
    ))
    $checks = foreach ($page in @($pages)) { @($page.check_runs) | Where-Object { $null -ne $_ -and [string]$_.name -ieq $Context } }
    # A rerequest replaces the older run from the same App, not another App's run.
    @($checks | Group-Object { "$($_.app.id):$($_.name)" } | ForEach-Object { $_.Group | Sort-Object { [long]$_.id } -Descending | Select-Object -First 1 })
}

function Get-PrAgentSignal {
    param([array]$Checks = @(), [array]$Statuses = @(), [string]$Context = "PR Agent")
    $legacy = @($Statuses | Where-Object { [string]$_.context -ieq $Context } | Select-Object -First 1)
    $states = @($Checks | ForEach-Object {
        if ($_.status -ne "completed") { "pending" }
        elseif ($_.conclusion -in @("success", "failure")) { [string]$_.conclusion }
        else { "incomplete" }
    }) + @($legacy | ForEach-Object { if ($_.state -eq "error") { "incomplete" } else { [string]$_.state } })
    $state = if (!$states.Count) { "absent" } elseif ($states -contains "pending") { "pending" }
        elseif ($states -contains "incomplete") { "incomplete" } elseif ($states -contains "failure") { "failure" }
        elseif (@($states | Where-Object { $_ -ne "success" }).Count) { "incomplete" } else { "success" }
    [pscustomobject]@{ present = ($states.Count -gt 0); state = $state; checks = @($Checks); legacy = $legacy
        description = (@($Checks | ForEach-Object { $_.output.title }) + @($legacy | ForEach-Object { $_.description })) -join "; "
        url = (@($Checks | ForEach-Object { $_.html_url }) + @($legacy | ForEach-Object { $_.target_url }) | Select-Object -First 1) }
}

function Test-PrAgentContextPresent {
    param(
        [AllowNull()][array]$Statuses,
        [Parameter(Mandatory = $true)][string]$Context
    )

    foreach ($status in @($Statuses)) {
        if ([string]$status.context -ieq $Context) {
            return $true
        }
    }
    return $false
}

function Test-PrAgentSeenOnPull {
    param(
        [Parameter(Mandatory = $true)][string[]]$ApiPrefix,
        [Parameter(Mandatory = $true)][string]$ApiRepository,
        [Parameter(Mandatory = $true)][int]$Number,
        [Parameter(Mandatory = $true)][string]$Sha,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $headChecks = @(Get-PrAgentChecks -ApiPrefix $ApiPrefix -ApiRepository $ApiRepository -Sha $Sha -Context $Context)
    if ($headChecks.Count) { return $true }
    $headStatuses = Get-CombinedStatusContexts -ApiPrefix $ApiPrefix -ApiRepository $ApiRepository -Sha $Sha
    if (Test-PrAgentContextPresent -Statuses $headStatuses -Context $Context) {
        return $true
    }

    $commitPages = Invoke-GhJson ($ApiPrefix + @(
        "repos/$ApiRepository/pulls/$Number/commits?per_page=20", "--paginate", "--slurp"
    ))
    foreach ($commit in @(Expand-PaginatedItems $commitPages)) {
        if ([string]$commit.sha -eq $Sha) { continue }
        if (@(Get-PrAgentChecks -ApiPrefix $ApiPrefix -ApiRepository $ApiRepository -Sha ([string]$commit.sha) -Context $Context).Count) { return $true }
        $statuses = Get-CombinedStatusContexts -ApiPrefix $ApiPrefix -ApiRepository $ApiRepository -Sha ([string]$commit.sha)
        if (Test-PrAgentContextPresent -Statuses $statuses -Context $Context) {
            return $true
        }
    }

    return $false
}

function Test-ActionableFeedbackItem {
    param([Parameter(Mandatory = $true)]$Item)

    $body = [string]$Item.body
    if ([string]::IsNullOrWhiteSpace($body)) {
        return $false
    }
    if ($body -match '<!-- pr-agent:summary:v\d+ -->') { return $false }

    if ($Item.kind -eq "review") {
        if ($Item.reviewState -in @("DISMISSED", "PENDING")) {
            return $false
        }

        if ($body -match '(?i)reviewed\s+\d+\s+out\s+of\s+\d+\s+changed files.*generated no new comments') {
            return $false
        }
    }

    return $body.Trim() -notmatch '^(?:lgtm|looks good(?: to me)?|approved|acknowledged|thanks|thank you|done|👍)[.! ]*$'
}

function Get-PrReviewSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][int]$Number,
        [string]$Hostname,
        [ValidateRange(1, 3)][int]$Attempt = 1,
        [string]$PrAgentContext = "PR Agent"
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

    $commentPages = Invoke-GhJson ($apiPrefix + @(
        "repos/$($routing.apiRepository)/issues/$Number/comments", "--paginate", "--slurp"
    ))
    $comments = @(Expand-PaginatedItems $commentPages)

    $reviewPages = Invoke-GhJson ($apiPrefix + @(
        "repos/$($routing.apiRepository)/pulls/$Number/reviews", "--paginate", "--slurp"
    ))
    $reviews = @(Expand-PaginatedItems $reviewPages)

    $threadScript = Join-Path $PSScriptRoot "get-unresolved-pr-threads.ps1"
    $threadJson = & $threadScript `
        -PrNumber $Number `
        -Repository $routing.selector `
        -Hostname $routing.hostname `
        -All
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
                headSha = [string]$comment.pullRequestReview.commit.oid
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
            headSha = $null
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
            headSha = [string]$review.commit_id
        }
    }

    $prAgentStatuses = Get-CombinedStatusContexts -ApiPrefix $apiPrefix -ApiRepository $routing.apiRepository -Sha $pr.headRefOid
    $prAgentChecks = @(Get-PrAgentChecks -ApiPrefix $apiPrefix -ApiRepository $routing.apiRepository -Sha $pr.headRefOid -Context $PrAgentContext)
    $prAgentStatus = Get-PrAgentSignal -Checks $prAgentChecks -Statuses @($prAgentStatuses) -Context $PrAgentContext

    $verifiedPr = Invoke-GhJson @(
        "pr", "view", $Number.ToString(), "--repo", $routing.selector,
        "--json", "headRefOid"
    )
    if ($verifiedPr.headRefOid -ne $pr.headRefOid) {
        if ($Attempt -ge 3) {
            throw "Pull request HEAD changed repeatedly while collecting a review snapshot."
        }

        return Get-PrReviewSnapshot `
            -Repository $Repository `
            -Number $Number `
            -Hostname $Hostname `
            -Attempt ($Attempt + 1) `
            -PrAgentContext $PrAgentContext
    }

    return [pscustomobject]@{
        pullRequest = [pscustomobject]@{
            number = [int]$pr.number
            url = [string]$pr.url
            state = [string]$pr.state
            headSha = [string]$pr.headRefOid
        }
        feedbackItems = @($feedbackItems)
        prAgentStatus = $prAgentStatus
    }
}

function Get-NewFeedback {
    param(
        [Parameter(Mandatory = $true)]$Baseline,
        [Parameter(Mandatory = $true)]$Snapshot
    )

    $agentLogin = Normalize-Login ([string]$Baseline.agentLogin)
    $seenVersions = @($Baseline.seenFeedbackVersions)
    return @($Snapshot.feedbackItems | Where-Object {
        $isPrAgentFeedback = Test-PrAgentMarkerBody -Body ([string]$_.body)
        if (((Normalize-Login $_.authorLogin) -eq $agentLogin -and -not $isPrAgentFeedback) -or
            -not (Test-ActionableFeedbackItem $_)) {
            return $false
        }

        $seen = $seenVersions | Where-Object id -eq $_.id | Select-Object -First 1
        if ($null -eq $seen) {
            return $true
        }

        return [string]$_.updatedAt -ne [string]$seen.updatedAt -or
            [string]$_.body -ne [string]$seen.body
    })
}

function Resolve-ReviewOutcome {
    param(
        [Parameter(Mandatory = $true)]$Baseline,
        [Parameter(Mandatory = $true)]$Snapshot,
        [Parameter(Mandatory = $true)][string]$ExpectedSha
    )

    if ($Snapshot.pullRequest.state -ne "OPEN") {
        return [pscustomobject]@{ status = "pr_closed"; verdict = "unknown"; prAgentRelevant = $false; prAgentState = "absent"; newFeedback = @() }
    }

    if ($Snapshot.pullRequest.headSha -ne $ExpectedSha) {
        if ([string]$Snapshot.pullRequest.headSha -eq [string]$Baseline.baselineHeadSha) {
            return [pscustomobject]@{ status = "waiting"; verdict = "unknown"; prAgentRelevant = $false; prAgentState = "absent"; newFeedback = @() }
        }

        return [pscustomobject]@{ status = "head_changed"; verdict = "unknown"; prAgentRelevant = $false; prAgentState = "absent"; newFeedback = @() }
    }

    $prAgentStatus = $Snapshot.prAgentStatus
    $prAgentPresent = ($null -ne $prAgentStatus -and [bool]$prAgentStatus.present)
    $prAgentRelevant = $prAgentPresent -or [bool]$Baseline.prAgentSeenAtBaseline
    $newFeedback = @(Get-NewFeedback -Baseline $Baseline -Snapshot $Snapshot)
    if ($newFeedback.Count -gt 0) {
        return [pscustomobject]@{ status = "feedback"; verdict = "unknown"; prAgentRelevant = $prAgentRelevant; prAgentState = if ($prAgentStatus) { [string]$prAgentStatus.state } else { "absent" }; newFeedback = $newFeedback }
    }

    if ($prAgentRelevant) {
        if (-not $prAgentPresent) {
            return [pscustomobject]@{ status = "processing"; verdict = "unknown"; prAgentRelevant = $true; prAgentState = "pending"; newFeedback = @() }
        }

        if ($prAgentStatus.state -eq "pending") {
            return [pscustomobject]@{ status = "processing"; verdict = "unknown"; prAgentRelevant = $true; prAgentState = "pending"; newFeedback = @() }
        }

        if ($prAgentStatus.state -in @("incomplete", "error")) {
            return [pscustomobject]@{ status = "incomplete"; verdict = "unknown"; prAgentRelevant = $true; prAgentState = "incomplete"; newFeedback = @() }
        }

        if ($prAgentStatus.state -in @("failure", "error")) {
            if ($newFeedback.Count -eq 0) {
                $newFeedback = @([pscustomobject]@{
                    id = "pragent-status"
                    kind = "pragent_status"
                    authorLogin = "PR Agent"
                    authorType = "App"
                    body = "PR Agent reported $([string]$prAgentStatus.state) on this HEAD: $([string]$prAgentStatus.description)"
                    url = [string]$prAgentStatus.url
                    createdAt = [DateTimeOffset]::UtcNow.ToString("o")
                    updatedAt = [DateTimeOffset]::UtcNow.ToString("o")
                    threadId = $null
                    headSha = $ExpectedSha
                })
            }
            return [pscustomobject]@{ status = "feedback"; verdict = "unknown"; prAgentRelevant = $true; prAgentState = [string]$prAgentStatus.state; newFeedback = $newFeedback }
        }

        if ($prAgentStatus.state -ne "success") {
            return [pscustomobject]@{ status = "processing"; verdict = "unknown"; prAgentRelevant = $true; prAgentState = [string]$prAgentStatus.state; newFeedback = @() }
        }
    }

    if ($prAgentRelevant -and $prAgentPresent -and $prAgentStatus.state -eq "success") {
        return [pscustomobject]@{ status = "approved"; verdict = "pragent_approved"; prAgentRelevant = $true; prAgentState = "success"; newFeedback = @() }
    }
    return [pscustomobject]@{ status = "waiting"; verdict = "unknown"; prAgentRelevant = $false; prAgentState = "absent"; newFeedback = @() }
}

function Save-ReviewState {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $State | ConvertTo-Json -Depth 100 | Set-Content -Encoding utf8 -LiteralPath $Path
}

function Invoke-PrReviewWatcher {
    if ($Inspect) {
        if ($PrNumber -le 0) { throw "-Inspect requires -PrNumber." }
        $snapshot = Get-PrReviewSnapshot -Repository $Repository -Number $PrNumber -Hostname $Hostname -PrAgentContext $PrAgentContext
        $snapshot | ConvertTo-Json -Depth 100
        return
    }
    if ($CaptureBaseline) {
        if ([string]::IsNullOrWhiteSpace($Repository)) {
            $repo = Invoke-GhJson @("repo", "view", "--json", "owner,name,url")
            $Repository = "$($repo.owner.login)/$($repo.name)"
            if ([string]::IsNullOrWhiteSpace($Hostname)) {
                $Hostname = ([uri]$repo.url).Authority
            }
        }

        $routing = Resolve-RepositoryRouting -Repository $Repository -Hostname $Hostname
        if ($PrNumber -le 0) {
            $pr = Invoke-GhJson @(
                "pr", "view", "--repo", $routing.selector, "--json", "number"
            )
            $PrNumber = [int]$pr.number
        }

        $viewerArgs = @("api")
        if (-not [string]::IsNullOrWhiteSpace($routing.hostname)) {
            $viewerArgs += @("--hostname", $routing.hostname)
        }
        $viewerArgs += @("user")
        $viewer = Invoke-GhJson $viewerArgs
        $apiPrefix = @("api")
        if (-not [string]::IsNullOrWhiteSpace($routing.hostname)) {
            $apiPrefix += @("--hostname", $routing.hostname)
        }
        $snapshot = Get-PrReviewSnapshot `
            -Repository $routing.selector `
            -Number $PrNumber `
            -Hostname $routing.hostname `
            -PrAgentContext $PrAgentContext

        $prAgentSeenAtBaseline = $false
            $prAgentSeenAtBaseline = Test-PrAgentSeenOnPull `
                -ApiPrefix $apiPrefix `
                -ApiRepository $routing.apiRepository `
                -Number $PrNumber `
                -Sha ([string]$snapshot.pullRequest.headSha) `
                -Context $PrAgentContext
        $state = [pscustomobject]@{
            repository = $routing.selector
            hostname = $routing.hostname
            prNumber = $PrNumber
            agentLogin = Normalize-Login $viewer.login
            baselineHeadSha = [string]$snapshot.pullRequest.headSha
            capturedAt = [DateTimeOffset]::UtcNow
            seenFeedbackVersions = @($snapshot.feedbackItems | ForEach-Object {
                [pscustomobject]@{
                    id = [string]$_.id
                    body = [string]$_.body
                    updatedAt = $_.updatedAt
                }
            })
            prAgentContext = $PrAgentContext
            prAgentSeenAtBaseline = $prAgentSeenAtBaseline
        }
        Save-ReviewState -State $state -Path $StatePath

        [pscustomobject]@{
            status = "baseline_captured"
            statePath = $StatePath
            repository = $routing.selector
            prNumber = $PrNumber
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
        $start = if ($ReviewRequestedAt -eq [DateTimeOffset]::MinValue) {
            [DateTimeOffset]::UtcNow
        } else {
            $ReviewRequestedAt
        }
        $start.AddSeconds($ReviewStartGraceSeconds)
    } else {
        [DateTimeOffset]::MaxValue
    }

    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        $snapshot = Get-PrReviewSnapshot `
            -Repository $state.repository `
            -Number ([int]$state.prNumber) `
            -Hostname ([string]$state.hostname) `
            -PrAgentContext ([string]$state.prAgentContext)

        $outcome = Resolve-ReviewOutcome `
            -Baseline $state `
            -Snapshot $snapshot `
            -ExpectedSha $ExpectedHeadSha

        if ($outcome.status -in @("feedback", "approved", "incomplete", "head_changed", "pr_closed")) {
            [pscustomobject]@{
                status = $outcome.status
                repository = $state.repository
                prNumber = $state.prNumber
                expectedHeadSha = $ExpectedHeadSha
                actualHeadSha = $snapshot.pullRequest.headSha
                verdict = $outcome.verdict
                prAgentRelevant = [bool]$outcome.prAgentRelevant
                prAgentState = [string]$outcome.prAgentState
                newFeedback = @($outcome.newFeedback)
            } | ConvertTo-Json -Depth 100
            return
        }

        if ($ReviewStartGraceSeconds -gt 0 -and
            [DateTimeOffset]::UtcNow -ge $reviewStartDeadline -and
            $snapshot.pullRequest.headSha -eq $ExpectedHeadSha -and
            -not [bool]$outcome.prAgentRelevant) {
            [pscustomobject]@{
                status = "review_not_started"
                repository = $state.repository
                prNumber = $state.prNumber
                expectedHeadSha = $ExpectedHeadSha
                actualHeadSha = $snapshot.pullRequest.headSha
                verdict = "unknown"
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
        expectedHeadSha = $ExpectedHeadSha
        timeoutMinutes = $TimeoutMinutes
        newFeedback = @()
    } | ConvertTo-Json -Depth 20
}

if ($MyInvocation.InvocationName -ne ".") {
    Invoke-PrReviewWatcher
}
