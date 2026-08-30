. "V:\Skills\skills\finish-pr\scripts\wait-for-pr-review.ps1" -Wait -StatePath "$env:TEMP\wfr-debug.json" -ExpectedHeadSha "new-sha" -ReviewRequestedAt ([DateTimeOffset]::MinValue)

$baseline = [pscustomobject]@{
    agentLogin = "example-agent"
    baselineHeadSha = "old-sha"
    seenFeedbackVersions = @()
    gitarDashboard = $null
    prAgentSeenAtBaseline = $true
    gitarSeenAtBaseline = $true
}
$snapshot = [pscustomobject]@{
    pullRequest = [pscustomobject]@{ headSha = "new-sha"; state = "OPEN" }
    feedbackItems = @()
    gitarChecks = @()
    gitarDashboard = $null
    prAgentStatus = [pscustomobject]@{ present = $true; state = "success"; description = "x"; url = "" }
}
$o = Resolve-ReviewOutcome -Baseline $baseline -Snapshot $snapshot -ExpectedSha "new-sha"
$o | ConvertTo-Json -Depth 5
