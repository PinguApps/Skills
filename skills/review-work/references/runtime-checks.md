# Reviewer runtime checks

Read when preparing reviewer briefs and execution permissions. Source remains
read-only; reviewers may build, run tests, start the app, inspect its output and
interact with its UI using non-destructive test resources. Ordinary build outputs,
caches and disposable test data are allowed. Reviewers leave fixes to the parent.
Keep tracked/source files unchanged; use separate output directories when a
build would regenerate them, or return that check to the parent.

## Parent handoff

Give each reviewer a quick rundown of the verification that will appear in the
PR's `## Proof`, rather than making it rediscover how to run the work:

- Commands/actions already performed, expected and observed results, revision,
  evidence locations and known gaps. Separate executed proof from future tests.
- Exact working directory, absolute executables, startup/test commands, required
  configuration and safe credential access, dependencies, test-data setup,
  URLs/ports and the changed paths or states to exercise.
- Which resources are disposable, which are shared, forbidden actions and any
  startup side effects. Inspect startup scripts/configuration for automatic
  migrations, resets, seeders, background jobs and external writes before launch.
- Resource ownership and cleanup: identify existing services to reuse, give
  concurrent reviewers distinct ports/output directories/test resources, or
  serialize conflicting execution. Stop only processes the reviewer started.

Use exact available execution and browser tool IDs in the run's `executionTools`
array and name them in the brief. Expose only the tools needed for those checks;
omit raw source readers, editors, delegation and PR/tracker tools. Verify the
runtime exposes the assigned tools before accepting the review. An empty array
retains source-only access when execution is irrelevant or unsafe; record why and
any resulting verification gap. Tool availability is not a safety sandbox: the
brief must still constrain commands, destinations and side effects.

## Reviewer execution

For a full review, independently exercise the relevant changed behaviour where it
can safely run. Use the parent's proof as a starting point, then choose focused
checks that could reveal regressions or unmet requirements. For a web app, run or
reuse the supplied test instance, inspect the actual UI and exercise the relevant
states. For an incremental review, rerun only checks affected by the new changes
or needed to settle an open finding; another full app exercise is unnecessary
unless the fix warrants it.

Keep commands and interactions within the supplied safe environment. Do not wipe
or reset databases, destroy resources, modify shared/production data, deploy,
send real messages, or run startup/migration/cleanup paths with those effects.
Use isolated disposable resources or a safe mode supplied by the parent. If safety
cannot be established, stop that action and report the exact missing setup; keep
reviewing independently where possible. A source-only approval does not close a
required runtime-verification gap.

Read source only through `pingu_review_source`; shell/browser tools and runtime
output must not be used to inspect excluded source. Keep secrets out of output.
Preserve PATH, shell profiles and persistent environment settings, including child
process side effects. For isolated .NET CLI homes, set
`DOTNET_ADD_GLOBAL_TOOLS_TO_PATH=0` in each child environment.

Return commands/actions actually performed, observed results, evidence locations,
verification gaps and cleanup status. The parent inspects that evidence before
adding reviewer observations to the proof record; a verdict alone is not proof.
