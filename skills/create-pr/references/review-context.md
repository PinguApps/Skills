# Review context

Carry one concise review brief from task discovery through the PR and review fixes. Keep its meaning consistent rather than copying the conversation or full tracker history.

Use the PR's existing sections where they fit; otherwise append `## Review context`. Include:

- **Outcome and requirements:** the observable change and acceptance criteria, with issue identifiers when supplied. Group related criteria without losing coverage.
- **Decisions and exclusions:** deliberate tradeoffs, compatibility constraints and behaviour explicitly outside scope. Link an authoritative spec or ADR when useful; retain enough context for a reviewer without tracker access.
- **Evidence and gaps:** actual verification commands/results or artifact links, the commit verified, and material behaviour those checks do not establish. Distinguish executed checks from proposed manual tests.
- **Recovery:** how to undo material runtime, data or configuration changes, including any irreversible migration or recovery limitation. Omit this for changes without a meaningful recovery concern.

Describe requirements as claims the reviewer should check against source. A passing test or a stated intention does not prove the implementation is correct. Keep secrets and raw private conversations out of the brief.

After review fixes change behaviour, decisions, verification or recovery, refresh the saved PR brief before final handoff. Mark evidence that predates the final change and rerun checks affected by that change. A small PR should need only a few short bullets; reuse existing verification and manual-test sections instead of duplicating them.
