$ErrorActionPreference = "Stop"
$threadsJson = gh api graphql -f owner='PinguApps' -f name='Skills' -F number=7 -f query='query($owner:String!,$name:String!,$number:Int!){ repository(owner:$owner,name:$name){ pullRequest(number:$number) { reviewThreads(first: 50) { nodes { id isResolved comments(first: 2) { nodes { databaseId author{login} body path line } } } } } } }'
$j = $threadsJson | ConvertFrom-Json
$open = @($j.data.repository.pullRequest.reviewThreads.nodes | Where-Object { -not $_.isResolved })
foreach ($t in $open) {
    $root = $t.comments.nodes[0]
    Write-Output ("=== THREAD " + $t.id + " root=" + $root.databaseId + " [" + $root.author.login + "] " + $root.path + ":" + $root.line + " ===")
    $bodyLines = $root.body -split "`n" | Where-Object { $_ -notmatch 'img.shields|pr-agent:v1|^\s*$' } | Select-Object -First 6
    Write-Output ($bodyLines -join "`n")
}
