---
name: to-spec-local
description: Wrap the installed to-spec skill to synthesize an in-repository Markdown specification that can be used as the primary source for to-linear.
---

# To Spec Local

Apply the separately installed `to-spec` skill to the settled conversation, with repository Markdown as the deliverable. This is a wrapper: the upstream skill remains the source of its synthesis process and spec template.

## Load the external skill

Resolve `to-spec` through the environment's installed-skill catalog or configured skill roots and read its complete `SKILL.md`. Its source is an external runtime dependency, intentionally not vendored in this repository; absence from this repository is not evidence that it is unavailable. Do not assume a sibling directory or a machine-specific installation path.

If discovery cannot find the installed skill, report that `to-spec` must be made available before this wrapper can run. Do not silently substitute a copied template or infer its current instructions from memory. Read `to-linear`'s source-selection and provenance requirements when available; preparing a local spec does not require publishing a backlog or configuring a tracker.

## Apply these delivery overrides

Run the upstream synthesis process with these explicit changes:

- Keep every deliverable in the current repository. Write Markdown instead of publishing an issue.
- Replace upstream tracker setup, tracker/triage-vocabulary prerequisites, issue publication and `ready-for-agent` labelling with local-file delivery. Missing tracker configuration is not a blocker and does not require a setup command.
- Reuse testing seams already explicitly agreed in the conversation. If a genuinely new seam needs the upstream confirmation, confirm that seam before finalizing; do not repeat an accepted discussion or reopen the requirements interview.
- Leave issue creation, Linear destination selection, labels, milestones, estimates and cycles to a later `to-linear` invocation. This wrapper does not invoke it.

Retain upstream requirements for repository exploration, domain vocabulary, relevant ADRs, user-focused synthesis, extensive numbered user stories, implementation/testing decisions and scope boundaries. Apply its actual spec template rather than maintaining another copy here. Commit, push or open a PR only when separately authorized by the surrounding task.

## Produce one authoritative local source

Read the settled conversation and referenced material needed to account for its requirements, including attached threads when available. Preserve accepted decisions, additions, rejected alternatives and unresolved facts; later confirmed decisions supersede earlier proposals. Supporting research and repository context clarify the agreed scope without silently expanding it. Do not claim a referenced source was read when access is missing.

Use the user's destination when supplied. Otherwise follow the repository's spec convention, updating an existing matching spec when appropriate. With no convention, use root `SPEC.md` if it is available for this scope; preserve an unrelated existing spec and choose a descriptive file under `docs/specs/` instead. All generated supporting documents also remain in-repo.

The result must be directly usable by `to-linear`:

- Keep the complete agreed scope in one primary Markdown specification. Supporting links may explain evidence or terminology but must not introduce hidden requirements.
- Retain the upstream template and sequentially numbered user stories covering the accepted behavior, constraints, failure handling and out-of-scope boundaries. Do not invent ticket IDs, mandatory ticket counts or implementation ordering.
- Make application/runtime/platform/release prerequisites and human-owned access or approval actions explicit where relevant, so later ticket slicing can distinguish Agent and Human work.
- Record accepted behavior-level testing seams and relevant prior art. Distinguish decisions and planned verification from compilation or execution that actually occurred.
- Preserve source provenance and useful repository-relative links. Respect upstream guidance against brittle implementation paths and code dumps; provenance links and the specification's own destination are not implementation prescriptions.
- In Further Notes, explicitly designate this file as the primary scope source for a later `to-linear` run. Identify supporting context as explanatory and retain factual gaps as visible follow-up work rather than fabricated decisions.

Before finishing, re-read the written file against the settled requirements and upstream template. Account for every accepted requirement and relevant qualification, preserve existing unrelated documentation, and check local links. Report the saved path, a short scope summary and any unresolved material gaps. A later `to-linear` invocation should be able to select this artifact explicitly without repeating the interview or relying on the chat for essential scope.
