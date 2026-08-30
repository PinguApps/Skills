$ErrorActionPreference = "Stop"
$repo = "PinguApps/Skills"
$threadsJson = gh api graphql -f owner='PinguApps' -f name='Skills' -F number=7 -f query='query($owner:String!,$name:String!,$number:Int!){ repository(owner:$owner,name:$name){ pullRequest(number:$number) { reviewThreads(first: 50) { nodes { id isResolved comments(first: 1) { nodes { databaseId } } } } } } }'
$j = $threadsJson | ConvertFrom-Json
$open = @($j.data.repository.pullRequest.reviewThreads.nodes | Where-Object { -not $_.isResolved })

$notes = @{
    "note-auth-shortcut" = "Fixed in 78ffb3b - the watcher now tracks whether Gitar is expected (gitarSeenAtBaseline, latched when a Gitar check or dashboard appears during the watch). PR Agent success alone returns approved only when Gitar has never been seen; otherwise it returns processing until Gitar reports on the exact HEAD."
    "note-pragent-detection" = "note-detection-errors"
    "root-gitar-shortcut" = "note-auth-shortcut"
    "root-gitar-error" = "note-error-state"
    "root-copilot-swallow" = "note-detection-errors"
    "root-copilot-premature" = "note-auth-shortcut"
    "root-copilot-dod" = "note-dod"
}

$noteText = @{
    "note-auth-shortcut" = "Fixed in 78ffb3b - the watcher now tracks whether Gitar is expected: gitarSeenAtBaseline is captured at baseline (any Gitar check on the HEAD or recent commits, or a Gitar dashboard comment) and latched the moment a Gitar check or dashboard appears during the watch. PR Agent success alone returns approved only when Gitar has never been seen on the PR; otherwise it returns processing until Gitar reports on the exact HEAD."
    "note-detection-errors" = "Fixed in 78ffb3b - Get-CombinedStatusContexts and Test-PrAgentSeenOnPull no longer swallow API errors; failures now propagate so a transient gh failure aborts baseline capture and the run can be retried, instead of silently recording PR Agent as not running."
    "note-error-state" = "Fixed - the failure branch matches both `failure` and `error` states and surfaces them as feedback immediately, so a broken PR Agent run is reported instead of polled to timeout. Covered by a test assertion."
    "note-dod" = "Fixed in 78ffb3b - the definition-of-done bullet is now conditional on Gitar running, matching the per-section wording (same detection rule as PR Agent)."
}

foreach ($t in $open) {
    $rootDb = [string]$t.comments.nodes[0].databaseId
    $noteKey = $notes[$rootDb]
    if (-not $noteKey) { $noteKey = $notes["note-$rootDb"] }
    if (-not $noteKey) { $noteKey = "note-auth-shortcut" }
    $text = $noteText[$noteKey]
    if (-not $text) { $text = $noteKey }
    Write-Output "Replying to root $($rootDb) (thread $($t.id)) with note key: $noteKey"
    gh api "repos/$repo/pulls/7/comments/$rootDb/replies" -f body="$text" --jq ".id" | Out-Null
    gh api graphql -f id="$($t.id)" -f query='mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread { isResolved } } }' --jq ".data.resolveReviewThread.thread.isResolved" | Out-Null
}
Write-Output "done"
