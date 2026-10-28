[CmdletBinding()]
param(
    [int]$PrNumber,
    [string]$Repository,
    [string]$Hostname,
    [switch]$Library
)

$ErrorActionPreference = 'Stop'

function Normalize-Login {
    param([string]$Login)
    if (-not $Login) { return '' }
    return $Login.ToLowerInvariant() -replace '\[bot\]$', ''
}

function Test-CopilotLogin {
    param([string]$Login)
    return (Normalize-Login $Login) -in @('copilot-pull-request-reviewer', 'copilot', 'github-copilot')
}

function Get-ReviewSha {
    param($Review)
    if ($Review.commit_id) { return [string]$Review.commit_id }
    return [string]$Review.commit.oid
}

function Get-ReviewLogin {
    param($Review)
    if ($Review.user.login) { return [string]$Review.user.login }
    return [string]$Review.author.login
}

function Get-ReviewTime {
    param($Review)
    $value = if ($Review.submitted_at) { $Review.submitted_at } else { $Review.submittedAt }
    if ($value -is [DateTime] -or $value -is [DateTimeOffset]) { return [DateTimeOffset]$value }
    if ($value) { return [DateTimeOffset]::Parse([string]$value, [Globalization.CultureInfo]::InvariantCulture) }
    return [DateTimeOffset]::MinValue
}

function Test-CopilotQuota {
    param([string]$Login, [string]$Body)
    return (Test-CopilotLogin $Login) -and
        $Body -match '(?is)(unable to review.*(?:insufficient|exhausted|exceeded|reached).*quota|(?:review|premium request) (?:quota|limit).*(?:exhausted|exceeded|reached)|quota.*unable to review)'
}

function Get-CopilotReviewState {
    param([array]$Reviews, [string]$HeadSha, [array]$RequestedReviewers = @(), [switch]$AwaitingRereview)
    $current = @($Reviews | Where-Object {
        (Test-CopilotLogin (Get-ReviewLogin $_)) -and (Get-ReviewSha $_) -eq $HeadSha
    } | Sort-Object { Get-ReviewTime $_ } -Descending)
    $requested = @($RequestedReviewers | Where-Object { Test-CopilotLogin $_.login }).Count -gt 0
    if (-not $current.Count) {
        $state = if ($requested -or $AwaitingRereview) { 'running' } else { 'absent' }
        return [pscustomobject]@{ state = $state; clean = $false; review = $null }
    }
    $latest = $current[0]
    if (Test-CopilotQuota (Get-ReviewLogin $latest) $latest.body) {
        return [pscustomobject]@{ state = 'quota-pass'; clean = $false; review = $latest }
    }
    if ($requested -or @($current | Where-Object state -eq 'PENDING').Count) { $state = 'running' }
    elseif ($latest.body -match '(?is)(unable to review|could not review|review failed)') { $state = 'incomplete' }
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
        -not (Test-CopilotLogin $comments[0].author.login)) { return $false }
    $latest = $comments[-1]
    if ((Normalize-Login $latest.author.login) -ne (Normalize-Login $AgentLogin)) { return $false }
    if ($latest.pullRequestReview.state -eq 'PENDING' -or -not $latest.pullRequestReview.submittedAt) { return $false }
    if (-not $CopilotState.clean -or -not $CopilotState.review) { return $false }
    # The clean current-head re-review must follow the agent's submitted response.
    $replyTime = if ($latest.createdAt -is [DateTime] -or $latest.createdAt -is [DateTimeOffset]) {
        [DateTimeOffset]$latest.createdAt
    } else { [DateTimeOffset]::Parse([string]$latest.createdAt, [Globalization.CultureInfo]::InvariantCulture) }
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
$state = Get-CopilotReviewState -Reviews $reviews -HeadSha $pr.head.sha -RequestedReviewers @($pr.requested_reviewers)
$fresh = Invoke-ReviewGhJson ($prefix + @("repos/$Repository/pulls/$PrNumber"))
if ($fresh.head.sha -ne $pr.head.sha) { throw 'PR head changed while reading review state.' }
[pscustomobject]@{
    head = $pr.head.sha
    pullRequest = $pr.html_url
    copilot = $state
    reviews = $reviews
    threads = $threads.threads
    settlementCandidates = @($threads.threads | Where-Object {
        Test-CopilotSettlement $_ $state $viewer.login
    } | ForEach-Object { $_.id })
} | ConvertTo-Json -Depth 100
