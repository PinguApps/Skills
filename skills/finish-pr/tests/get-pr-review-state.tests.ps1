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
$requested = Get-CopilotReviewState @() 'head' @(@{login='copilot-pull-request-reviewer[bot]'})
Assert-True ($requested.state -eq 'running' -and -not $requested.clean) 'A requested review is in flight even before REST contains a submitted review.'
$expected = Get-CopilotReviewState @() 'head' -AwaitingRereview
Assert-True ($expected.state -eq 'running') 'A known accepted re-request cannot be mistaken for an absent reviewer.'
$failed = Get-CopilotReviewState @((New-Review 'Authentication failed; unable to review.' 'COMMENTED')) 'head'
Assert-True (-not $failed.clean) 'Service failures cannot provide clean-review evidence.'
Assert-True ($failed.state -eq 'incomplete') 'A non-quota review failure remains incomplete.'
$clean = Get-CopilotReviewState @((New-Review 'Copilot reviewed 8 files and generated no new comments.')) 'head'
Assert-True $clean.clean 'A current-head explicit no-new-comments review is clean.'
$noComments = Get-CopilotReviewState @((New-Review 'Copilot reviewed 8 files and generated no comments.')) 'head'
Assert-True $noComments.clean 'The regular Copilot no-comments summary is clean.'
$thread = [pscustomobject]@{id='thread';isResolved=$false;comments=@{nodes=@(
    [pscustomobject]@{author=@{login='copilot-pull-request-reviewer[bot]'};createdAt='2026-10-27T10:00:00Z'},
    [pscustomobject]@{author=@{login='agent'};createdAt='2026-10-27T11:00:00Z';pullRequestReview=@{state='COMMENTED';submittedAt='2026-10-27T11:00:00Z'}}
)}}
Assert-True (Test-CopilotSettlement $thread $clean 'agent') 'Submitted reply followed by a clean current-head review permits settlement assessment.'
Assert-True (-not (Test-CopilotSettlement $thread $quota 'agent')) 'Quota must not silently erase an earlier finding.'
$thread.comments.nodes += [pscustomobject]@{author=@{login='human'};createdAt='2026-10-27T12:30:00Z'}
Assert-True (-not (Test-CopilotSettlement $thread $clean 'agent')) 'Later human feedback prevents automatic settlement.'
$thread.comments.nodes = $thread.comments.nodes[0..1]
$thread.comments.nodes[1].pullRequestReview.submittedAt = '2026-10-27T13:00:00Z'
Assert-True (-not (Test-CopilotSettlement $thread $clean 'agent')) 'A draft created before the clean review but submitted afterwards cannot be settled.'
$thread.comments.nodes[1].pullRequestReview.submittedAt = '2026-10-27T11:00:00Z'
$thread.comments.nodes[0].author.login = 'human'
Assert-True (-not (Test-CopilotSettlement $thread $clean 'agent')) 'Human-originated threads remain human-owned.'
$botRequest = @(@{login='Copilot';type='Bot'})
$staleRequest = Get-CopilotReviewState @((New-Review 'No new comments')) 'head' $botRequest -ReviewRequestedAt '2026-10-27T11:30:00Z'
Assert-True ($staleRequest.state -eq 'completed') 'A submitted current-head result satisfies an earlier request even if the request list is stale.'
$newRequest = Get-CopilotReviewState @((New-Review $quotaText)) 'head' $botRequest -ReviewRequestedAt '2026-10-27T12:30:00Z'
Assert-True ($newRequest.state -eq 'running') 'A new request after quota must finish; stale quota is not a completion exemption.'
$pending = Get-CopilotReviewState @((New-Review $quotaText), (New-Review '' 'PENDING')) 'head'
Assert-True ($pending.state -eq 'running') 'A pending same-head review takes precedence over quota.'
$ambiguous = Get-CopilotReviewState @((New-Review 'No new comments')) 'head' $botRequest
Assert-True ($ambiguous.state -eq 'incomplete') 'Unknown request/result ordering must not permit a merge.'
Assert-True (-not (Test-CopilotQuota 'Copilot' $quotaText 'User')) 'A human account named Copilot is not trusted.'
$time = Get-CopilotRequestTime @(@{event='review_requested';requested_reviewer=@{login='Copilot';type='Bot'};created_at='2026-10-27T11:00:00Z'})
Assert-True ($time -eq [DateTimeOffset]'2026-10-27T11:00:00Z') 'GitHub timeline bot identity and request timestamp must be recognized.'
$message = @{headSha='head';user=@{login='Copilot';type='Bot'};body=$quotaText;createdAt='2026-10-27T12:00:00Z';url='https://github.com/example/quota'}
$messageQuota = Get-CopilotReviewState @() 'head' -QuotaEvidence @($message)
Assert-True ($messageQuota.state -eq 'quota-pass' -and -not $messageQuota.clean) 'Verified current-head quota-message evidence is a completion exemption, not a clean review.'
$oldRequest = Get-CopilotReviewState @((New-Review 'No new comments' 'COMMENTED' 'old-head')) 'head' -ReviewRequestedAt '2026-10-27T11:00:00Z'
Assert-True ($oldRequest.state -eq 'absent') 'A completed old-head request must not turn every future push into an in-flight review.'
Write-Output 'PASS: Copilot quota and evidence-based settlement tests'
