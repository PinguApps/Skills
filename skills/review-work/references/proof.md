# Proof

Proof is evidence the implementation parent observed during this task: command
output, a reproduction, a running consumer, a screenshot or a verified external
result. A reviewer's approval and instructions for future testing are not proof
that the changed behaviour ran successfully.

Use the most direct evidence the change permits:

- For a bug, reproduce the failure before the fix and repeat the same check after
  it. If the original state cannot be exercised, state that gap rather than
  inventing a failing result. Add a focused regression test when the behaviour
  lacks coverage and the repository has a suitable test setup.
- Run the relevant checks used by the repository's CI. Distinguish checks that
  actually ran from proposed commands, and explain any unavailable required check.
- For .NET, package, deployment or generated-output changes, exercise the real
  affected consumer with the actual artifacts/dependencies. Mocks alone do not
  establish compatibility, startup or deployment behaviour.
- For UI/Blazor and runtime behaviour, run the app and inspect the changed path
  and relevant states. Attach useful screenshots when an authorized upload path
  exists; otherwise record what was observed and the attachment limitation.
- For documentation, skills and configuration, verify the affected procedure or
  real consumer where practical: resolve references, exercise changed helpers,
  and check realistic inputs and outputs. A wording match does not establish
  that an agent can complete the workflow.

Keep a concise proof record in the external run directory. For each material
behaviour, record the action/command, expected result, observed result, relevant
revision and evidence location/link. Label mock-only evidence and prior-revision
results accurately. Refresh affected proof after fixes; preserve useful before/after
evidence. Keep secrets and excluded source out of reviewer briefs and attachments.

When no meaningful proof is available, confidence is incomplete. Do independent
work first, then ask for the specific decision, access or environment needed to
prove the change. Do not publish a completed PR while that required proof is missing.

Carry this record into a literal `## Proof` section in the PR: state what changed,
how it was exercised and what actually happened, linking evidence where available.
Use short linked commit hashes. Keep future manual verification in `## Test changes`;
do not present those instructions as executed proof. After publication, refresh
proof for scoped fixes without launching new paid review sessions.
