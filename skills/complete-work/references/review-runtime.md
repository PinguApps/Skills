# OpenCode review runtime

Read before the first reviewer launch. Requires OpenCode 2's plugin hooks and local
API (validated with 2.1.4), Python 3 and T3 OpenCode delegation. Do not switch to a
CLI inference request or another model when those prerequisites are unavailable.

Create the scope and usage ledger first. Record each unique run before dispatch:
`id` (opaque filename-safe ID), integer `round`, `Review-Run-ID: <opaque>` marker,
exact `model`/`effort`, `base`, `from`, `head`, absolute `scope` manifest and succinct
`R<n>: <model>` title. Do not quote another run marker as its own
dedicated line in a later brief.

With no live reviewer, prepare the run-local runtime:

```powershell
& <absolute-python> <skill>/scripts/review_runtime.py --ledger <ledger> prepare
& <absolute-opencode> api plugin.list --param 'location[directory]=<actual-worktree>'
```

The helper freezes the trusted reader/policy/runtime in the external run directory
and adds one uniquely named loader under the worktree's `.opencode/plugins/`.
It does not edit existing configuration or global settings. Retain its ownership
receipt. Never stage this temporary loader; it is operational state, not task
source. Verify the API reports `pingu.pre-pr-review` loaded for the actual location
and the external `runtime-ready.json` records the running version before launch.
A first location lookup may return while plugins load; make one follow-up lookup
after setup and require `state.status: active` for this loader. Verify the ready
file's runtime digest matches `runtime.json` and its location matches this worktree.
A stale file alone is not proof. Preserve and investigate existing loaders/config;
never overwrite a file owned by another run. Do not refresh helper copies while
reviewers are live. After implementation changes to the runtime itself, remove the
owned loader, prepare again and reverify the loaded plugin.

The plugin recognises only registered exact markers, binds their OpenCode sessions
durably, and leaves unrelated sessions unchanged. It exposes only
`pingu_review_source` to owned review requests and rejects other tool execution.
The source tool calls the frozen reader without a shell and fixes the worktree,
head and manifest. The model can choose `diff`, `read`, `search`, allowed historical
ref and pagination. Give repository conventions explicitly in the brief or through
that reader; ambient file instructions and prompt attachments are not review input.

The HTTP hook leaves response bytes unchanged while recording only generation ID,
numeric usage, model/effort, request kind, session ID and completion metadata in
`<run-id>.transport.jsonl`. It never saves request headers, keys or response prose.
Title generation uses the assigned title without an inference call. Other charged
flows must use the assigned model/variant; an unexpected auxiliary model blocks.
OpenRouter selects its hosting endpoint; the hook rejects hosting-provider pins.

## Automatic compaction below pricing tiers

Keep OpenCode `compaction.auto` enabled (the default), with no alternate summary
model and no experimental background summaries. Verify the actual worktree's
applicable configuration before dispatch; incompatible overrides are a prerequisite
to resolve, never silently accept costly requests. The runtime examines selected
models' current catalogue context-price tiers. For the first increase, it lowers
the effective input limit to 80% of that tier boundary using a temporary location
model transform. Flat-price models retain their full input window. Nothing is
written to global configuration, and unloading the runtime removes the transform.

For Haiku's 100,000-token tier, this sets an 80,000-token effective input limit.
OpenCode's default 16,000-token reserve starts its own automatic summary near
64,000 estimated tokens. Source-tool pages are capped at 12,000 characters to
limit sudden growth. The harness writes/stores the summary itself; the parent
does not call `compact`, fabricate summaries or launch another summarizer. Summary
inference is charged and included in that model's review cost.

These thresholds use the harness's estimates, not an exact provider tokenizer.
Do not promise a hard token ceiling: record actual prompt-token peaks from transport
usage, flag any pricing-tier crossing and adjust the safety margin/page size before
reusing that policy. Compaction is lossy, so preserve covered paths/ranges, findings
and next checks. Do not enable speculative background compaction: unused summaries
would still cost money. Catalogue tiers can change; inspect live metadata each run.

On T3 completion, save `task_status`'s structured result outside the repo, collect
usage serially with `review_usage.py collect --task-state <file>`, and audit the
guard/source transcript plus journal. Missing/unfinished transport evidence is
explicitly unavailable; retain it rather than manufacturing a zero or using an
estimate as billed spend. The collector separately preserves OpenCode's estimate.

After all reviewer tasks are terminal, results/accounting are saved and children
are settled, remove only this run's loader:

```powershell
& <absolute-python> <skill>/scripts/review_runtime.py --ledger <ledger> remove
```

Verify that loader disappeared and the worktree contains only intended task work.
Retain the external ledger, journals, findings and coverage receipt for PR updates
and resume. Never delete or disable another run's plugin or reviewer state.

References: [OpenCode plugin hooks](https://dev.opencode.ai/v2/docs/build/plugins/server),
[OpenCode 2.1.4 token and cost normalization](https://github.com/anomalyco/opencode/blob/v2.1.4/packages/core/src/session/usage.ts),
[OpenRouter usage accounting](https://openrouter.ai/docs/cookbook/administration/usage-accounting).
