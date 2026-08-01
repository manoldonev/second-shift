# Lean spec — #306: `intake-review.mjs` disclaims `referencedDocs` content it never injects

## Context

`workflows/intake-review.mjs` accepts `referencedDocs: [{path, content}]` (its own header
comment, line 113, documents the `content` field), tells both intake sub-agents those docs
are "already read — do not re-fetch" (`docsNote`, built from `d.path` only), and never
places `d.content` anywhere in the dispatch prompt. `intake-orchestrator` SKILL.md's
"Finding referenced docs" step already resolves each doc with `Read` before calling the
Workflow — the caller does the work of reading the file, and the callee throws the content
away while still telling the sub-agent not to re-read it.

Under the Stage-1 `readRoot` pin (every pipeline run since its introduction), the
sub-agent COULD read the doc itself from the pinned worktree — but `docsNote` has just told
it not to. Without `readRoot`, the doc is unreachable and disclaimed. Either way the
sub-agent reasons about a spec whose referenced docs it was never given and is not allowed
to fetch, with nothing in the prompt revealing the gap.

Issue #306 lays out three options; (1) inject the content or (3) drop the arg entirely.
Dropping the arg (3) would also require changing the caller contract documented in
`intake-orchestrator` SKILL.md's Step 2 ("Pass the resolved docs to the fan-out as
`referencedDocs`") and its required-args list — a cross-plugin edit for a problem the
callee alone caused. Injecting the content (1) is a same-file fix that makes the existing
documented contract (line 113) true.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Which option | Inject `d.content` into the dispatch prompts (issue option 1), not drop the arg (option 3) — the caller-side contract in `intake-orchestrator` SKILL.md already expects `referencedDocs` to carry the docs; dropping it needs a separate cross-plugin change. | codebase-derived |
| D-2 | Delimiting | Each doc rendered under its own header line naming the path, so the sub-agent can distinguish doc boundaries and still cite `file:line` per its existing rationale contract. | codebase-derived |
| D-3 | Empty-array behavior | `referencedDocs: []` (the default, and every pre-existing call site) must produce byte-identical prompts to today — no doc block, no wording change. | codebase-derived |
| D-4 | Test tier | Per `docs/testing.md`'s tier map, a production Workflow `.mjs` dispatch ladder is pinned via `workflows/runtime-shim-selftest.mjs`, not a new prose/grep guard. | project convention |

## Acceptance Criteria

- AC-1: When `referencedDocs` is non-empty, the full `content` of each entry is injected
  into both the `spec-reviewer` and `codebase-explorer` dispatch prompts (not just the
  `path`), rendered under a per-doc header naming the path so doc boundaries are
  distinguishable.
- AC-2: The "do not re-fetch" note's wording stays accurate to what's actually supplied —
  it names the paths as before, only alongside content that is genuinely present in the
  same prompt.
- AC-3: `referencedDocs: []` (the default) produces prompts identical to pre-fix behavior —
  no doc block, no note change.
- AC-4: A `workflows/runtime-shim-selftest.mjs` case executes the real `intake-review.mjs`
  body via the shim with a `referencedDocs` fixture and asserts the dispatched prompt
  contains both the doc's path and its content — pinning the seam the issue found
  unguarded ("No selftest pins this seam").
- AC-5: The shellcheck, jq, and full `*-selftest.sh` sweeps stay green.

## Out of scope

- #283 (the same file's missing emit-deadline/ceiling) — independent defect, already
  landed separately per the issue's own "Related" note.
- Changing the `intake-orchestrator` caller contract or dropping the `referencedDocs` arg
  (issue option 3).
