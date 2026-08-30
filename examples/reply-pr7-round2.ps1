$ErrorActionPreference = "Stop"
$repo = "PinguApps/Skills"
$sha = "e5aa3c6"

$threadsJson = gh api graphql -f owner='PinguApps' -f name='Skills' -F number=7 -f query='query($owner:String!,$name:String!,$number:Int!){ repository(owner:$owner,name:$name){ pullRequest(number:$number) { reviewThreads(first: 50) { nodes { id isResolved comments(first: 1) { nodes { databaseId author{login} } } } } } } }'
$j = $threadsJson | ConvertFrom-Json
$open = @($j.data.repository.pullRequest.reviewThreads.nodes | Where-Object { -not $_.isResolved })

$replies = @{
    "3890235707" = "Fixed in 78ffb3b (fail-fast) and hardened by the follow-up commits - Get-CombinedStatusContexts and Test-PrAgentSeenOnPull no longer swallow API errors; a transient gh failure now aborts baseline capture entirely so the run can be retried, instead of silently recording PR Agent as not running."
    "3890240251" = "Fixed in 78ffb3b - Get-CombinedStatusContexts no longer swallows errors; status-fetch failures now fail fast and surface to the caller."
    "3890240262" = "Fixed in 78ffb3b - Resolve-ReviewOutcome now tracks gitarSeenAtBaseline (captured at baseline and latched the moment a Gitar check or dashboard appears during the watch). PR Agent success alone only approves when Gitar has never been seen on the PR; otherwise it returns processing until Gitar reports on the exact HEAD."
    "3890240275" = "Fixed in 78ffb3b - the definition-of-done bullet is now conditional on Gitar running, using the same detection rule as the PR Agent section."
    "3890333507" = "Fixed in the latest commit - the thumbs-up alternative is restored, built from surrogate-pair code units so the source stays ASCII-safe against encoding round-trips."
    "3890335041" = "Fixed in the latest commit - the thumbs-up alternative is restored via surrogate-pair construction (encoding-safe against the corruption this PR briefly introduced), with a test assertion covering it."
}

foreach ($t in $open) {
    $rootDb = [string]$t.comments.nodes[0].databaseId
    $reply = $replies[$rootDb]
    if (-not $reply) { Write-Output "No reply mapped for root $rootDb - skipping"; continue }
    Write-Output "Replying to root $rootDb"
    gh api "repos/$repo/pulls/7/comments/$rootDb/replies" -f body="$reply" --jq ".id" | Out-Null
    if ($rootDb -ne "3890333507" -and $rootDb -ne "3890335041") {
        gh api graphql -f id="$($t.id)" -f query='mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread { isResolved } } }' --jq ".data.resolveReviewThread.thread.isResolved" | Out-Null
    }
}
Write-Output "done - PR Agent threads left open for its own verification"
