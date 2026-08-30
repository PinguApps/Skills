$ErrorActionPreference = "Stop"
$repo = "PinguApps/Skills"

$threadsJson = gh api graphql -f owner='PinguApps' -f name='Skills' -F number=7 -f query='query($owner:String!,$name:String!,$number:Int!){ repository(owner:$owner,name:$name){ pullRequest(number:$number) { reviewThreads(first: 50) { nodes { id isResolved comments(first: 1) { nodes { databaseId path } } } } } } }'
$j = $threadsJson | ConvertFrom-Json
$open = @($j.data.repository.pullRequest.reviewThreads.nodes | Where-Object { -not $_.isResolved })

foreach ($t in $open) {
    $root = $t.comments.nodes[0]
    Write-Output ("OPEN THREAD " + $t.id + " root=" + $root.databaseId + " path=" + $root.path)
}
Write-Output ("open count: " + $open.Count)
