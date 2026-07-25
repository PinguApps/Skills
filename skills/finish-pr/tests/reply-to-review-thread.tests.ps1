$ErrorActionPreference = "Stop"

$global:GhMockCalls = 0
function global:gh {
    $global:GhMockCalls++
    $global:LASTEXITCODE = 0

    if ($global:GhMockCalls -eq 1) {
        return '{"data":{"viewer":{"login":"example-agent"},"node":{"pullRequest":{"id":"pull-request-1","reviews":{"pageInfo":{"hasNextPage":true,"endCursor":"page-1"},"nodes":[{"id":"other-review","state":"PENDING","author":{"login":"someone-else"}}]}}}}}'
    }

    if ($global:GhMockCalls -eq 2) {
        return '{"data":{"node":{"reviews":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[{"id":"viewer-review","state":"PENDING","author":{"login":"example-agent"}}]}}}}'
    }

    throw "Reply mutation should not run when a later pending-review page belongs to the viewer."
}

try {
    & "$PSScriptRoot\..\scripts\reply-to-review-thread.ps1" -ThreadId "thread-1" -Body "test"
    throw "Expected the helper to reject the existing pending review."
}
catch {
    if ($_.Exception.Message -notlike "Refusing to reply while an existing pending review*") {
        throw
    }

    if ($global:GhMockCalls -ne 2) {
        throw "Expected two pending-review page calls, got $global:GhMockCalls."
    }
}
finally {
    Remove-Item Function:\global:gh -ErrorAction SilentlyContinue
    Remove-Variable GhMockCalls -Scope Global -ErrorAction SilentlyContinue
}

$global:GhMockCalls = 0
function global:gh {
    $global:GhMockCalls++
    $global:LASTEXITCODE = 0

    switch ($global:GhMockCalls) {
        1 {
            return '{"data":{"viewer":{"login":"example-agent"},"node":{"pullRequest":{"id":"pull-request-1","reviews":{"pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[]}}}}}'
        }
        2 {
            return '{"data":{"addPullRequestReviewThreadReply":{"comment":{"id":"reply-1","url":"https://example.test/reply-1","pullRequestReview":{"id":"viewer-review","state":"PENDING","submittedAt":null}}}}}'
        }
        3 {
            return '{"data":{"viewer":{"login":"example-agent"},"node":{"id":"viewer-review","state":"PENDING","body":"","author":{"login":"example-agent"},"comments":{"pageInfo":{"hasNextPage":false},"nodes":[{"id":"concurrent-comment"},{"id":"reply-1"}]}}}}'
        }
        default {
            throw "The helper must not submit a concurrent pending review."
        }
    }
}

try {
    & "$PSScriptRoot\..\scripts\reply-to-review-thread.ps1" -ThreadId "thread-1" -Body "test"
    throw "Expected the helper to reject the concurrent pending review."
}
catch {
    if ($_.Exception.Message -notlike "Refusing to submit review*because it contains content other than reply*") {
        throw
    }

    if ($global:GhMockCalls -ne 3) {
        throw "Expected the helper to stop after the pending-review safety query, got $global:GhMockCalls calls."
    }
}
finally {
    Remove-Item Function:\global:gh -ErrorAction SilentlyContinue
    Remove-Variable GhMockCalls -Scope Global -ErrorAction SilentlyContinue
}

Write-Output "All reply-to-review-thread tests passed."
