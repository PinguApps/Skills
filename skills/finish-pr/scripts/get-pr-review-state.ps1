[CmdletBinding()]
param(
    [int]$PrNumber,
    [string]$Repository,
    [string]$Hostname,
    [string]$ReviewRequestedAt,
    [string]$ReviewRequestedHead,
    [string]$QuotaEvidenceFile,
    [switch]$Library
)

$ErrorActionPreference = 'Stop'

function Normalize-Login {
    param([string]$Login)
    if (-not $Login) { return '' }
    return $Login.ToLowerInvariant() -replace '\[bot\]$', ''
}

function Test-CopilotLogin {
    param([string]$Login, [string]$Type)
    return (Normalize-Login $Login) -in @('copilot-pull-request-reviewer', 'copilot', 'github-copilot') -and
        ($Type -eq 'Bot' -or (-not $Type -and $Login -match '\[bot\]$'))
}

function Get-ReviewSha {
    param($Review)
    if ($Review.commit_id) { return [string]$Review.commit_id }
    if ($Review.headSha) { return [string]$Review.headSha }
    return [string]$Review.commit.oid
}

function Get-ReviewLogin {
    param($Review)
    if ($Review.user.login) { return [string]$Review.user.login }
    return [string]$Review.author.login
}

function Get-ReviewTime {
    param($Review)
    $value = if ($Review.submitted_at) { $Review.submitted_at } elseif ($Review.submittedAt) { $Review.submittedAt }
        elseif ($Review.created_at) { $Review.created_at } else { $Review.createdAt }
    if ($value -is [DateTime] -or $value -is [DateTimeOffset]) { return [DateTimeOffset]$value }
    if ($value) { return [DateTimeOffset]::Parse([string]$value, [Globalization.CultureInfo]::InvariantCulture) }
    return [DateTimeOffset]::MinValue
}

function Test-CopilotQuota {
    param([string]$Login, [string]$Body, [string]$Type)
    return (Test-CopilotLogin $Login $Type) -and
        $Body -match '(?is)(unable to review.*(?:insufficient|exhausted|exceeded|reached).*quota|(?:review|premium request) (?:quota|limit).*(?:exhausted|exceeded|reached)|quota.*unable to review)'
}

function Get-CopilotRequestTime {
    param([array]$Timeline)
    $requests = @($Timeline | Where-Object {
        $_.event -eq 'review_requested' -and (Test-CopilotLogin $_.requested_reviewer.login $_.requested_reviewer.type)
    } | Sort-Object { Get-ReviewTime $_ } -Descending)
    if ($requests.Count) { return Get-ReviewTime $requests[0] }
    return [DateTimeOffset]::MinValue
}

function Get-CopilotReviewState {
    param([array]$Reviews, [string]$HeadSha, [array]$RequestedReviewers = @(), [switch]$AwaitingRereview,
        [DateTimeOffset]$ReviewRequestedAt = [DateTimeOffset]::MinValue, [array]$QuotaEvidence = @(),
        [string]$ReviewRequestedHead)
    $quotaCurrent = @($QuotaEvidence | Where-Object {
        $type = if ($_.user.type) { $_.user.type } else { $_.author.__typename }
        (Get-ReviewSha $_) -eq $HeadSha -and (Test-CopilotQuota (Get-ReviewLogin $_) $_.body $type)
    })
    $current = @((@($Reviews) + $quotaCurrent) | Where-Object {
        $type = if ($_.user.type) { $_.user.type } else { $_.author.__typename }
        (Test-CopilotLogin (Get-ReviewLogin $_) $type) -and (Get-ReviewSha $_) -eq $HeadSha
    } | Sort-Object { Get-ReviewTime $_ } -Descending)
    $requested = @($RequestedReviewers | Where-Object { Test-CopilotLogin $_.login $_.type }).Count -gt 0
    if (-not $current.Count) {
        $fulfilled = @($Reviews | Where-Object {
            $type = if ($_.user.type) { $_.user.type } else { $_.author.__typename }
            (Test-CopilotLogin (Get-ReviewLogin $_) $type) -and $_.state -ne 'PENDING' -and
                (-not $ReviewRequestedHead -or (Get-ReviewSha $_) -eq $ReviewRequestedHead) -and
                (Get-ReviewTime $_) -ge $ReviewRequestedAt
        }).Count -gt 0
        $unfinished = $ReviewRequestedAt -gt [DateTimeOffset]::MinValue -and -not $fulfilled
        $state = if ($requested -or $AwaitingRereview -or $unfinished) { 'running' } else { 'absent' }
        return [pscustomobject]@{ state = $state; clean = $false; review = $null }
    }
    if (@($current | Where-Object state -eq 'PENDING').Count) {
        return [pscustomobject]@{ state = 'running'; clean = $false; review = $null }
    }
    $latest = $current[0]
    if ($ReviewRequestedAt -gt (Get-ReviewTime $latest)) {
        return [pscustomobject]@{ state = 'running'; clean = $false; review = $latest }
    }
    if (($requested -or $AwaitingRereview) -and $ReviewRequestedAt -eq [DateTimeOffset]::MinValue) {
        return [pscustomobject]@{ state = 'incomplete'; clean = $false; review = $latest; reason = 'Request/result ordering unavailable' }
    }
    $latestType = if ($latest.user.type) { $latest.user.type } else { $latest.author.__typename }
    if (Test-CopilotQuota (Get-ReviewLogin $latest) $latest.body $latestType) {
        return [pscustomobject]@{ state = 'quota-pass'; clean = $false; review = $latest }
    }
    if ($latest.body -match '(?is)(unable to review|could not review|review failed)') { $state = 'incomplete' }
    elseif ($latest.state -eq 'CHANGES_REQUESTED') { $state = 'changes-requested' }
    else { $state = 'completed' }
    $clean = $state -eq 'completed' -and ($latest.state -eq 'APPROVED' -or
        ($latest.state -eq 'COMMENTED' -and $latest.body -match '(?is)(generated no (?:new )?comments|did not generate any comments|(?:found no|no (?:new |additional )?)(?:issues|findings)|no new comments)'))
    return [pscustomobject]@{ state = $state; clean = $clean; review = $latest }
}

function Test-CopilotSettlement {
    param($Thread, $CopilotState, [string]$AgentLogin)
    $comments = @($Thread.comments.nodes | Sort-Object createdAt)
    if ($Thread.isResolved -or -not $comments.Count -or
        -not (Test-CopilotLogin $comments[0].author.login $comments[0].author.__typename)) { return $false }
    $latest = $comments[-1]
    if ((Normalize-Login $latest.author.login) -ne (Normalize-Login $AgentLogin)) { return $false }
    if ($latest.pullRequestReview.state -eq 'PENDING' -or -not $latest.pullRequestReview.submittedAt) { return $false }
    if (-not $CopilotState.clean -or -not $CopilotState.review) { return $false }
    # The clean current-head re-review must follow the agent's submitted response.
    $submitted = Get-ReviewTime $latest.pullRequestReview
    $replyTime = @($submitted, (Get-ReviewTime $latest)) | Sort-Object -Descending | Select-Object -First 1
    return (Get-ReviewTime $CopilotState.review) -gt $replyTime
}

if ($Library) { return }
if (-not $Repository -or $PrNumber -le 0) { throw 'Supply -Repository owner/name and -PrNumber.' }
$parts = $Repository.Split('/')
if ($parts.Count -eq 3) {
    if ($Hostname -and $Hostname -ne $parts[0]) { throw 'Repository hostname mismatch.' }
    $Hostname = $parts[0]
    $Repository = "$($parts[1])/$($parts[2])"
} elseif ($parts.Count -ne 2) { throw 'Repository must be owner/name or host/owner/name.' }
$ghExecutable = (Get-Command gh -CommandType Application -ErrorAction Stop).Source
[string[]]$prefix = @(if ($Hostname) { 'api'; '--hostname'; $Hostname } else { 'api' })
function Invoke-ReviewGhJson {
    param([string[]]$Arguments)
    $text = & $ghExecutable @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw ($text -join [Environment]::NewLine) }
    return ($text -join [Environment]::NewLine) | ConvertFrom-Json -Depth 100
}
$pr = Invoke-ReviewGhJson ($prefix + @("repos/$Repository/pulls/$PrNumber"))
$pages = Invoke-ReviewGhJson ($prefix + @("repos/$Repository/pulls/$PrNumber/reviews?per_page=100", '--paginate', '--slurp'))
$reviews = @($pages | ForEach-Object { foreach ($item in $_) { $item } })
$threadArgs = @{ PrNumber = $PrNumber; Repository = $Repository; All = $true }
if ($Hostname) { $threadArgs.Hostname = $Hostname }
$threads = & "$PSScriptRoot/get-unresolved-pr-threads.ps1" @threadArgs | ConvertFrom-Json -Depth 100
$viewer = Invoke-ReviewGhJson ($prefix + @('user'))
$timelinePages = Invoke-ReviewGhJson ($prefix + @("repos/$Repository/issues/$PrNumber/timeline?per_page=100", '--paginate', '--slurp'))
$timeline = @($timelinePages | ForEach-Object { foreach ($item in $_) { $item } })
$requestedAt = Get-CopilotRequestTime $timeline
$requestHead = ''
if ($ReviewRequestedAt) {
    if (-not $ReviewRequestedHead) { throw 'An accepted request timestamp requires its recorded target head SHA.' }
    $recordedAt = [DateTimeOffset]::Parse($ReviewRequestedAt, [Globalization.CultureInfo]::InvariantCulture)
    if ($recordedAt -ge $requestedAt) { $requestedAt = $recordedAt; $requestHead = $ReviewRequestedHead }
}
$quotaEvidence = if ($QuotaEvidenceFile) { @(Get-Content -LiteralPath $QuotaEvidenceFile -Raw | ConvertFrom-Json -Depth 100) } else { @() }
$state = Get-CopilotReviewState -Reviews $reviews -HeadSha $pr.head.sha -RequestedReviewers @($pr.requested_reviewers) -ReviewRequestedAt $requestedAt -QuotaEvidence $quotaEvidence -ReviewRequestedHead $requestHead
$fresh = Invoke-ReviewGhJson ($prefix + @("repos/$Repository/pulls/$PrNumber"))
if ($fresh.head.sha -ne $pr.head.sha) { throw 'PR head changed while reading review state.' }
if ((@($fresh.requested_reviewers.login | Sort-Object) -join ',') -ne (@($pr.requested_reviewers.login | Sort-Object) -join ',')) {
    throw 'Requested reviewers changed while reading review state; re-fetch before deciding completion.'
}
[pscustomobject]@{
    head = $pr.head.sha
    pullRequest = $pr.html_url
    viewer = $viewer.login
    copilotRequestedAt = $requestedAt
    copilotRequestedHead = $requestHead
    copilot = $state
    reviews = $reviews
    threads = $threads.threads
    settlementCandidates = @($threads.threads | Where-Object {
        Test-CopilotSettlement $_ $state $viewer.login
    } | ForEach-Object { $_.id })
} | ConvertTo-Json -Depth 100
