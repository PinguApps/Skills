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

When Linear tickets informed the task, start the PR title with the identifiers of every such ticket whose requirements this PR fully completes, deduplicated. Put them before the summary and any repository title prefix: `ENG-123: Add sign-in` or `ENG-123, ENG-124: Add sign-in`. Tickets used only as background or left partially complete do not qualify. When no tickets qualify, follow the repository's usual title convention. Apply this rule when creating a PR and when reusing one for the task.

Use the selected template as the body: preserve its headings, order, comments, and checkbox labels while filling its sections, except for the required user story placement below. Append any other extra sections needed at the bottom; the template is a starting structure, not a limit on content.

Every PR description must include a `User story` section immediately before the summary, after categorisation when present. Match the template's heading level and reuse or move an existing user story section rather than duplicating it. When there is no summary, place the user story after categorisation, or first if neither section exists.

The user story must explain who needs what and why in everyday language that most people, including readers without a technical background, can understand. Focus on the problem and benefit; keep technical implementation details in the summary. Use familiar words and explain any essential specialist term or abbreviation. Keep it to a brief paragraph of short sentences; use more than one sentence when that makes it clearer, without turning it into a wall of text. When an original user story is available and aligned with the delivered scope, preserve its meaning and rewrite it as needed to meet these language and brevity rules. Otherwise infer it from the final PR changes and task context, keeping it grounded in the problem the PR actually solves.

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

# User story

# Summary

```

For this categorisation block, whether provided by the repository or the fallback, mark exactly one of `feature`, `bug`, `docs`, `security`, or `meta`, and exactly one of `patch`, `minor`, or `major` with `[x]`. Leave the other six unchecked and preserve the backticked labels: repository automation uses them to assign PR labels and draft releases. Choose the category that best describes the main change; choose the release level using repository release conventions and compatibility impact (`patch` for compatible fixes, `minor` for compatible additions, `major` for breaking changes). Follow any different checkbox scheme in a repository template without replacing it with this block.

Write a concise title and summary around the concrete problem and resulting behaviour. Include verification commands and actual results, and any material limitations or review decisions. Use existing template sections where they fit; otherwise append sections such as `## Verification` and `## Review notes`. Carry forward any caller-required content, including a manual test handoff, in the relevant section or an appended section. Keep the description aligned with the final diff rather than the conversation's chronology.

Read and apply [review context](references/review-context.md) to preserve requirements, deliberate tradeoffs, exclusions, evidence gaps and recovery where relevant. Reuse the template's existing sections before appending `## Review context`. Verify that the submitted brief describes the final change and distinguishes completed verification from instructions for future manual testing.

## 3. Create and verify the PR

Review the title and completed body against the final diff, template, checkbox selections, and caller requirements, including the Linear ticket prefix and the user story's placement, brevity, clarity for readers without a technical background, and alignment with the delivered scope. Apply the same checks when adapting an original story. Write the body to a UTF-8 temporary file outside the worktree and pass it to `gh pr create` with `--title`, `--body-file`, an explicit `--repo`, `--base`, and `--head` (including the owner for a fork). This preserves literal backticks and newlines. Do not rely on automatic template insertion when passing a body. For an existing PR, update its title and description only as needed for the authorized task, using its already-discovered URL and the relevant flags: `gh pr edit <pr-url> --title <title> --body-file <body-file>`.

Register the PR with the host's pull-request linking tool when available, including an existing PR reused by this run. Fetch its saved title, body, base, and head to verify the submitted content and target, including every qualifying ticket identifier at the start of the title. Remove the temporary body file after verification. Return the PR URL and any verification limitation to the caller; continue into review only when the caller's workflow requires it.
