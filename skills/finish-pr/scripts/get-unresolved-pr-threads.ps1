[CmdletBinding()]
param(
    [int]$PrNumber,
    [switch]$All
)

$ErrorActionPreference = "Stop"

function Invoke-GhJson {
    param([Parameter(Mandatory = $true)][string[]]$GhArgs)

    $output = & gh @GhArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ($output -join [Environment]::NewLine)
    }

    $json = $output -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($json)) {
        return $null
    }

    return $json | ConvertFrom-Json -Depth 100
}

$repo = Invoke-GhJson @("repo", "view", "--json", "owner,name")
$owner = $repo.owner.login
$name = $repo.name

if ($PrNumber -gt 0) {
    $pr = Invoke-GhJson @("pr", "view", $PrNumber.ToString(), "--json", "number,title,url,headRefName,baseRefName")
} else {
    $pr = Invoke-GhJson @("pr", "view", "--json", "number,title,url,headRefName,baseRefName")
    $PrNumber = [int]$pr.number
}

$query = @'
query($owner:String!, $name:String!, $number:Int!, $after:String) {
  repository(owner:$owner, name:$name) {
    pullRequest(number:$number) {
      reviewThreads(first:100, after:$after) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          startLine
          originalLine
          originalStartLine
          diffSide
          comments(first:100) {
            pageInfo {
              hasNextPage
              endCursor
            }
            nodes {
              id
              databaseId
              body
              author {
                login
              }
              createdAt
              updatedAt
              url
              path
              diffHunk
              outdated
              pullRequestReview {
                id
                state
                submittedAt
              }
            }
          }
        }
      }
    }
  }
}
'@

$threads = @()
$after = $null

do {
    $ghArgs = @(
        "api", "graphql",
        "-f", "owner=$owner",
        "-f", "name=$name",
        "-F", "number=$PrNumber",
        "-f", "query=$query"
    )

    if ($after) {
        $ghArgs += @("-f", "after=$after")
    }

    $result = Invoke-GhJson $ghArgs
    $page = $result.data.repository.pullRequest.reviewThreads
    if ($page.nodes) {
        $threads += $page.nodes
    }

    $after = $page.pageInfo.endCursor
} while ($page.pageInfo.hasNextPage)

$commentQuery = @'
query($threadId:ID!, $after:String) {
  node(id:$threadId) {
    ... on PullRequestReviewThread {
      comments(first:100, after:$after) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          id
          databaseId
          body
          author {
            login
          }
          createdAt
          updatedAt
          url
          path
          diffHunk
          outdated
          pullRequestReview {
            id
            state
            submittedAt
          }
        }
      }
    }
  }
}
'@

foreach ($thread in $threads) {
    $commentAfter = $thread.comments.pageInfo.endCursor
    while ($thread.comments.pageInfo.hasNextPage) {
        $commentArgs = @(
            "api", "graphql",
            "-f", "threadId=$($thread.id)",
            "-f", "query=$commentQuery"
        )
        if ($commentAfter) {
            $commentArgs += @("-f", "after=$commentAfter")
        }

        $commentResult = Invoke-GhJson $commentArgs
        $commentPage = $commentResult.data.node.comments
        if ($commentPage.nodes) {
            $thread.comments.nodes = @($thread.comments.nodes) + @($commentPage.nodes)
        }

        $thread.comments.pageInfo = $commentPage.pageInfo
        $commentAfter = $commentPage.pageInfo.endCursor
    }
}

if ($All) {
    $selectedThreads = @($threads)
} else {
    $selectedThreads = @($threads | Where-Object { -not $_.isResolved })
}

[pscustomobject]@{
    repository = "$owner/$name"
    pullRequest = $pr
    unresolvedCount = $selectedThreads.Count
    threads = $selectedThreads
} | ConvertTo-Json -Depth 100
