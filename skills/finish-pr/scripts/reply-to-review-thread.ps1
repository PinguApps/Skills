[CmdletBinding(DefaultParameterSetName = "Body")]
param(
    [Parameter(Mandatory = $true)]
    [string]$ThreadId,

    [string]$Hostname,

    [Parameter(Mandatory = $true, ParameterSetName = "Body")]
    [string]$Body,

    [Parameter(Mandatory = $true, ParameterSetName = "File")]
    [string]$BodyFile
)

$ErrorActionPreference = "Stop"

if ($PSCmdlet.ParameterSetName -eq "File") {
    $Body = Get-Content -Raw -LiteralPath $BodyFile
}

function Invoke-GhGraphQl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Query,

        [Parameter(Mandatory = $true)]
        [hashtable]$Variables
    )

    $ghArgs = @("api")
    if (-not [string]::IsNullOrWhiteSpace($Hostname)) {
        $ghArgs += @("--hostname", $Hostname)
    }
    $ghArgs += @("graphql", "-f", "query=$Query")
    foreach ($entry in $Variables.GetEnumerator()) {
        $ghArgs += @("-f", "$($entry.Key)=$($entry.Value)")
    }

    $output = & gh @ghArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ($output -join [Environment]::NewLine)
    }

    $json = $output -join [Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($json)) {
        throw "GitHub returned an empty GraphQL response."
    }

    return $json | ConvertFrom-Json -Depth 100
}

$pendingReviewQuery = @'
query($threadId:ID!) {
  viewer {
    login
  }
  node(id:$threadId) {
    ... on PullRequestReviewThread {
      pullRequest {
        id
        reviews(first:100, states:PENDING) {
          pageInfo {
            hasNextPage
            endCursor
          }
          nodes {
            id
            state
            author {
              login
            }
          }
        }
      }
    }
  }
}
'@

$pendingReviewResult = Invoke-GhGraphQl -Query $pendingReviewQuery -Variables @{
    threadId = $ThreadId
}
$viewerLogin = $pendingReviewResult.data.viewer.login
$pullRequest = $pendingReviewResult.data.node.pullRequest

if ([string]::IsNullOrWhiteSpace($viewerLogin) -or $null -eq $pullRequest) {
    throw "GitHub returned no verifiable pull request context for review thread $ThreadId."
}

$pendingReviews = @($pullRequest.reviews.nodes)
$pendingReviewAfter = $pullRequest.reviews.pageInfo.endCursor
$pendingReviewPageQuery = @'
query($pullRequestId:ID!, $after:String) {
  node(id:$pullRequestId) {
    ... on PullRequest {
      reviews(first:100, after:$after, states:PENDING) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          id
          state
          author {
            login
          }
        }
      }
    }
  }
}
'@

while ($pullRequest.reviews.pageInfo.hasNextPage) {
    $pendingReviewPageResult = Invoke-GhGraphQl -Query $pendingReviewPageQuery -Variables @{
        pullRequestId = $pullRequest.id
        after = $pendingReviewAfter
    }
    $pendingReviewPage = $pendingReviewPageResult.data.node.reviews
    $pendingReviews += @($pendingReviewPage.nodes)
    $pullRequest.reviews.pageInfo = $pendingReviewPage.pageInfo
    $pendingReviewAfter = $pendingReviewPage.pageInfo.endCursor
}

$existingPendingReviews = @($pendingReviews | Where-Object { $_.author.login -eq $viewerLogin })
if ($existingPendingReviews.Count -gt 0) {
    $reviewIds = $existingPendingReviews.id -join ", "
    throw "Refusing to reply while an existing pending review belongs to $viewerLogin ($reviewIds). Submit or discard it first."
}

$query = @'
mutation($threadId:ID!, $body:String!) {
  addPullRequestReviewThreadReply(input:{pullRequestReviewThreadId:$threadId, body:$body}) {
    comment {
      id
      url
      pullRequestReview {
        id
        state
        submittedAt
      }
    }
  }
}
'@

$result = Invoke-GhGraphQl -Query $query -Variables @{
    threadId = $ThreadId
    body = $Body
}
$comment = $result.data.addPullRequestReviewThreadReply.comment

if ($null -eq $comment -or $null -eq $comment.pullRequestReview) {
    throw "GitHub created no verifiable pull request review comment."
}

$submittedPendingReview = $false
if ($comment.pullRequestReview.state -eq "PENDING") {
    $submitQuery = @'
mutation($reviewId:ID!) {
  submitPullRequestReview(input:{pullRequestReviewId:$reviewId, event:COMMENT}) {
    pullRequestReview {
      id
      state
      submittedAt
    }
  }
}
'@

    $null = Invoke-GhGraphQl -Query $submitQuery -Variables @{
        reviewId = $comment.pullRequestReview.id
    }
    $submittedPendingReview = $true
}

$verifyQuery = @'
query($commentId:ID!) {
  node(id:$commentId) {
    ... on PullRequestReviewComment {
      id
      url
      pullRequestReview {
        id
        state
        submittedAt
      }
    }
  }
}
'@

$verification = Invoke-GhGraphQl -Query $verifyQuery -Variables @{
    commentId = $comment.id
}
$verifiedComment = $verification.data.node

if ($null -eq $verifiedComment -or
    $null -eq $verifiedComment.pullRequestReview -or
    $verifiedComment.pullRequestReview.state -eq "PENDING" -or
    $null -eq $verifiedComment.pullRequestReview.submittedAt) {
    throw "Review reply $($comment.id) is still pending or could not be verified as submitted."
}

[pscustomobject]@{
    comment = [pscustomobject]@{
        id = $verifiedComment.id
        url = $verifiedComment.url
    }
    review = $verifiedComment.pullRequestReview
    submittedPendingReview = $submittedPendingReview
    verifiedSubmitted = $true
} | ConvertTo-Json -Depth 10
