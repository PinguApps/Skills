---
name: create-pr
description: Create a GitHub pull request using the repository's PR template or the standard categorisation and summary template. Use when opening a PR or preparing its title and description.
---

# Create PR

Create a pull request for the completed work, with a description that preserves repository conventions and gives reviewers the evidence they need.

## 1. Establish the target and template

Read applicable `AGENTS.md` and contribution requirements. Confirm the intended base repository, base branch, head repository, and published head branch from the caller or GitHub metadata. Check for an existing PR for that exact head and base before creating one; reuse it on resumed runs. This skill does not authorize implementation, commits, pushes, merging, or review requests beyond the caller's scope.

Find and read the base repository's PR templates on its default branch, including case variants of `PULL_REQUEST_TEMPLATE.md` in `.github/`, the repository root, or `docs/`, and files in their `PULL_REQUEST_TEMPLATE/` subdirectories. Honour an explicitly selected template; otherwise use the default or the single clearly applicable template. Ask when multiple applicable templates remain ambiguous.

If the repository has no template, check for an inherited template in its owner's public `.github` repository, using the same locations. A template lookup failure caused by authentication or API errors is not proof that no template exists; report the blocker rather than silently using the fallback. Use the fallback below only when no applicable repository or inherited template exists.

## 2. Write the title and description

Use the selected template as the body: preserve its headings, order, comments, and checkbox labels while filling its sections. Append any extra sections needed at the bottom; the template is a starting structure, not a limit on content.

When no template exists, start with this exact structure:

```markdown
# Categorise the PR
<!-- Select at least one category from below that best describes this PR and what it does -->
- [ ] `feature`
- [ ] `bug`
- [ ] `docs`
- [ ] `security`
- [ ] `meta`
- [ ] `patch`
- [ ] `minor`
- [ ] `major`

# Summary

```

For this categorisation block, whether provided by the repository or the fallback, mark exactly one of `feature`, `bug`, `docs`, `security`, or `meta`, and exactly one of `patch`, `minor`, or `major` with `[x]`. Leave the other six unchecked and preserve the backticked labels: repository automation uses them to assign PR labels and draft releases. Choose the category that best describes the main change; choose the release level using repository release conventions and compatibility impact (`patch` for compatible fixes, `minor` for compatible additions, `major` for breaking changes). Follow any different checkbox scheme in a repository template without replacing it with this block.

Write a concise title and summary around the concrete problem and resulting behaviour. Include verification commands and actual results, and any material limitations or review decisions. Use existing template sections where they fit; otherwise append sections such as `## Verification` and `## Review notes`. Carry forward any caller-required content, including a manual test handoff, in the relevant section or an appended section. Keep the description aligned with the final diff rather than the conversation's chronology.

## 3. Create and verify the PR

Review the title and completed body against the final diff, template, checkbox selections, and caller requirements. Write the body to a UTF-8 temporary file outside the worktree and pass it to `gh pr create` with `--body-file`, an explicit `--repo`, `--base`, and `--head` (including the owner for a fork). This preserves literal backticks and newlines. Do not rely on automatic template insertion when passing a body. For an existing PR, update its description only when needed for the authorized task, using its already-discovered URL: `gh pr edit <pr-url> --body-file <body-file>`.

Register the PR with the host's pull-request linking tool when available, including an existing PR reused by this run. Fetch its saved title, body, base, and head to verify the submitted content and target. Remove the temporary body file after verification. Return the PR URL and any verification limitation to the caller; continue into review only when the caller's workflow requires it.
