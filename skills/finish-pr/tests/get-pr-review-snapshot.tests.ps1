$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../scripts/get-pr-review-state.ps1" -Library
function Assert-True($Condition, $Message) { if (-not $Condition) { throw $Message } }
$quotaText = 'Copilot was unable to review this pull request because the user who requested the review has insufficient remaining quota.'
$script:reviews = @(@{id=5698955850;state='COMMENTED';commit_id='head';submitted_at='2026-10-29T14:00:59Z';body=$quotaText;user=@{login='copilot-pull-request-reviewer[bot]';type='Bot'}})
$script:prReads = 0
$script:changedHead = $false
$script:changedRequest = $false
$script:failComments = $false
$script:calls = @()
function Invoke-ReviewGhJson {
    param([string[]]$Arguments)
    $script:calls += ,$Arguments
    $endpoint = $Arguments | Where-Object { $_ -like 'repos/*' } | Select-Object -First 1
    switch -Wildcard ($endpoint) {
        '*/pulls/37' {
            $script:prReads++
            return @{head=@{sha=$(if ($script:changedHead -and $script:prReads -gt 1) {'other'} else {'head'})};
                html_url='https://github.com/example/repo/pull/37';state='open';merged=$false;
                requested_reviewers=@(@{login='Copilot';type='Bot'});
                requested_teams=@(@{id=$(if ($script:changedRequest -and $script:prReads -gt 1) {2} else {1})})}
        }
        '*/reviews?*' { return ,@(@($script:reviews), @(@{id='human-review';state='PENDING';commit_id='head'})) }
        '*/comments?*' {
            if ($script:failComments) { throw 'Simulated comment read failure' }
            return ,@(@(@{id='comment-page-1'}), @(@{id='comment-page-2'}))
        }
        '*/check-runs?*' { return ,@(@{check_runs=@(@{id='check-1';head_sha='head';output=@{summary=$quotaText}})}, @{check_runs=@(@{id='check-2';status='in_progress'})}) }
        '*/statuses?*' { return ,@(@(@{id='status-1';state='pending'}), @(@{id='status-2';state='success'})) }
        '*/timeline?*' { return ,@(@(@{event='review_requested';requested_reviewer=@{login='Copilot';type='Bot'};created_at='2026-10-29T14:00:00Z'}), @()) }
        default { if ($Arguments[-1] -eq 'user') { return @{login='owner'} }; throw "Unexpected call: $Arguments" }
    }
}
function Invoke-ReviewThreads {
    param([hashtable]$Arguments)
    Assert-True ($Arguments.All -and $Arguments.PrNumber -eq 37) 'The snapshot must request all inline threads, including resolved/outdated ones.'
    return @{threads=@(@{id='protected-thread';isResolved=$false;comments=@{nodes=@(@{body='Human concern';author=@{login='human';__typename='User'}})}})}
}

$snapshot = Get-PrReviewSnapshot -PrNumber 37 -Repository example/repo
Assert-True ($snapshot.copilot.state -eq 'quota-pass' -and -not $snapshot.copilot.clean) 'Quota already present at the final refresh must end only the Copilot wait.'
Assert-True ($snapshot.reviews.Count -eq 2 -and $snapshot.issueComments.Count -eq 2 -and $snapshot.checkRuns.Count -eq 2 -and $snapshot.commitStatuses.Count -eq 2) 'Every paginated evidence surface must survive collection.'
Assert-True ($snapshot.requestedReviewers.Count -eq 1 -and $snapshot.requestedTeams.Count -eq 1) 'Requested reviewers and teams must be retained.'
Assert-True ($snapshot.threads[0].id -eq 'protected-thread' -and -not $snapshot.threads[0].isResolved -and $snapshot.settlementCandidates.Count -eq 0) 'Quota must preserve protected human feedback.'
Assert-True ($snapshot.readCompletedAt -ge $snapshot.readStartedAt -and $script:prReads -eq 2) 'The snapshot must bracket reads and reverify the head.'
foreach ($call in $script:calls | Where-Object { $_ -match 'per_page=' }) {
    Assert-True ($call -contains '--paginate' -and $call -contains '--slurp') 'Collection must request all pages.'
}

# Issue comments and check output remain raw evidence until the owner verifies
# identity and association. A check name or quota wording cannot create trust.
$script:reviews = @()
$script:prReads = 0
$pending = Get-PrReviewSnapshot -PrNumber 37 -Repository example/repo
Assert-True ($pending.copilot.state -eq 'running') 'Raw quota check output without verified association cannot end a requested review.'
foreach ($source in @('issue-comment', 'check-output')) {
    $evidence = @{headSha='head';user=@{login='Copilot';type='Bot'};body=$quotaText;createdAt='2026-10-29T14:00:59Z';url="https://example.test/$source"}
    $script:prReads = 0
    $verified = Get-PrReviewSnapshot -PrNumber 37 -Repository example/repo -QuotaEvidence @($evidence)
    Assert-True ($verified.copilot.state -eq 'quota-pass' -and -not $verified.copilot.clean) "Verified $source quota ends the wait without a clean-review claim."
    foreach ($invalid in @('old-head', 'untrusted')) {
        $bad = $evidence.Clone()
        if ($invalid -eq 'old-head') { $bad.headSha='old-head' } else { $bad.user=@{login='Copilot';type='User'} }
        $script:prReads = 0
        $rejected = Get-PrReviewSnapshot -PrNumber 37 -Repository example/repo -QuotaEvidence @($bad)
        Assert-True ($rejected.copilot.state -eq 'running') "$invalid $source evidence must be rejected."
    }
}
foreach ($failure in @('head', 'reviewer', 'comments')) {
    $script:prReads = 0
    $script:changedHead = $failure -eq 'head'
    $script:changedRequest = $failure -eq 'reviewer'
    $script:failComments = $failure -eq 'comments'
    $caught = $false
    try { $null = Get-PrReviewSnapshot -PrNumber 37 -Repository example/repo } catch { $caught = $true }
    Assert-True $caught "A $failure read inconsistency must block the handoff."
}
Write-Output 'PASS: complete snapshot collection and quota association (simulated GitHub transport; real helper)'
