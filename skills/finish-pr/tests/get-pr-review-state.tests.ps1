$ErrorActionPreference = 'Stop'
. "$PSScriptRoot/../scripts/get-pr-review-state.ps1" -Library
function Assert-True($Condition, $Message) { if (-not $Condition) { throw $Message } }
function New-Review($Body, $State = 'COMMENTED', $Sha = 'head', $Time = '2026-10-27T12:00:00Z') {
    return [pscustomobject]@{ user = @{login = 'copilot-pull-request-reviewer[bot]'}; body = $Body; state = $State; commit_id = $Sha; submitted_at = $Time }
}
$quotaText = 'Copilot was unable to review this pull request because the user who requested the review has insufficient remaining quota.'
$quota = Get-CopilotReviewState @((New-Review $quotaText)) 'head'
Assert-True ($quota.state -eq 'quota-pass') 'Real Copilot quota exhaustion must satisfy its completion gate.'
Assert-True (-not $quota.clean) 'Quota is not evidence that a fix received a clean re-review.'
Assert-True (-not (Test-CopilotQuota 'human' $quotaText)) 'A human mentioning quota must not bypass review.'
Assert-True (-not (Test-CopilotQuota 'copilot' 'Quota remains available.')) 'Quota words alone are not an exemption.'
$stale = Get-CopilotReviewState @((New-Review 'Approved' 'APPROVED' 'old-head')) 'head'
Assert-True ($stale.state -eq 'absent' -and -not $stale.clean) 'Old-head approval cannot approve current fixes.'
$failed = Get-CopilotReviewState @((New-Review 'Authentication failed; unable to review.' 'COMMENTED')) 'head'
Assert-True (-not $failed.clean) 'Service failures cannot provide clean-review evidence.'
Assert-True ($failed.state -eq 'incomplete') 'A non-quota review failure remains incomplete.'
$clean = Get-CopilotReviewState @((New-Review 'Copilot reviewed 8 files and generated no new comments.')) 'head'
Assert-True $clean.clean 'A current-head explicit no-new-comments review is clean.'
$thread = [pscustomobject]@{id='thread';isResolved=$false;comments=@{nodes=@(
    [pscustomobject]@{author=@{login='copilot-pull-request-reviewer[bot]'};createdAt='2026-10-27T10:00:00Z'},
    [pscustomobject]@{author=@{login='agent'};createdAt='2026-10-27T11:00:00Z';pullRequestReview=@{state='COMMENTED';submittedAt='2026-10-27T11:00:00Z'}}
)}}
Assert-True (Test-CopilotSettlement $thread $clean 'agent') 'Submitted reply followed by a clean current-head review permits settlement assessment.'
Assert-True (-not (Test-CopilotSettlement $thread $quota 'agent')) 'Quota must not silently erase an earlier finding.'
$thread.comments.nodes += [pscustomobject]@{author=@{login='human'};createdAt='2026-10-27T12:30:00Z'}
Assert-True (-not (Test-CopilotSettlement $thread $clean 'agent')) 'Later human feedback prevents automatic settlement.'
$thread.comments.nodes = $thread.comments.nodes[0..1]
$thread.comments.nodes[0].author.login = 'human'
Assert-True (-not (Test-CopilotSettlement $thread $clean 'agent')) 'Human-originated threads remain human-owned.'
Write-Output 'PASS: Copilot quota and evidence-based settlement tests'
