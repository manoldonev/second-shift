# Plan — #77: pass only the config keys each Workflow script reads

## Context / problem framing

Five dispatch sites across the dev-pipeline stage files instruct the caller to pass
`args.config = the parsed second-shift.config.json`. That payload carries
`commands.<host>.{lint,test}` shell-command strings and a top-level `$schema`, and on the
#33 run the first `plan-review.mjs` dispatch died in 5 ms with `JSON Parse error: Unable to
parse JSON string`. The practiced recovery — passing `{ reviewers: {} }` — serializes fine
but is an *empty* reviewers object, so
`(config && config.reviewers && config.reviewers.modelOverrides) || {}` resolves `{}` at
every call site. A caller today either risks a dead dispatch or silently disables every
model override. The `fable` tier shipped in #245 is inert for exactly this reason.

The fix is to send each script only the config keys it actually reads.

## Assumptions

- The serialization trigger is **inferred, not measured**. The issue names two candidates
  (shell-command strings, the `$schema` key) and discriminates neither. This plan does not
  claim to remove a mechanism nobody isolated — it removes keys no script reads, which is
  correct on its own grounds and shrinks the payload that failed.
- The stage files and skill files are read by a model at dispatch time, so the args literal
  and the comment defining its tokens must agree; a mismatch between them re-introduces the
  ambiguity this change exists to remove.
- CI is model-free by design, so no lane can perform a live Workflow dispatch.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Is the literal shape `{ reviewers: config.reviewers }` correct for every script? | No. `plugins/dev-pipeline/skills/run/workflows/code-review.mjs:330` also reads `config.tracker.type` and defaults silently to `'github'`, which branches the `scope-completeness-reviewer` prompt between the Atlassian MCP fetch and `gh issue view`. Implement AC-1 as the rule its wording implies — *pass exactly the keys the target script reads* — giving `{ reviewers }` for `plan-review.mjs` / `intake-review.mjs` / `mutation-gate.mjs` / `design-sync.mjs`, and `{ reviewers, tracker }` for `code-review.mjs`. | codebase-derived |
| D-2 | Does the fix reach the intake dispatch, which is outside the issue's Affected-files list? | Yes. The gating comment enumerates three broken call sites — `code-review.mjs:116`, `intake-review.mjs:133`, `plan-review.mjs:219` — and the documented intake args carry no `config` key at all, so fixing two and leaving the third reproduces the silent-by-construction failure this issue exists to kill. Adds `config` to the two documented intake arg contracts. Cited: https://github.com/manoldonev/second-shift/issues/77#issuecomment-5142324479 | ticket-sourced |
| D-3 | How is this guarded, given the repo bans prose-presence guards? | Guard the *delivery path*, not the prose. `runtime-shim-lib.mjs` executes real production `.mjs` bodies with injected fakes and already captures each dispatch's `opts`, so a shim case can assert that a `modelOverrides` value reaches the dispatched `model` and that `tracker.type` still routes the scope reviewer — both under the documented subset alone. The prose↔script coupling itself is not byte-anchorable; recorded as a manifest DROPPED entry rather than forgotten. | codebase-derived |
| D-4 | Is the Workflow arg-serialization hardening in scope? | No. The issue marks it optional and lower-priority, and the trigger was never isolated, so hardening would target a hypothesis. Left out of scope with an explicit handoff line instead of an unowned deferral. | deferred |
| D-5 | Does the `config: CONFIG` args token change too, or only the comment above it? | Both, uniformly. `CONFIG` is never assigned anywhere in the stage prose — the comment being rewritten is the token's only definition — so editing the comment alone would leave the args literal meaning whatever a reader assumes. Each site gets an explicit `config: { reviewers: CONFIG.reviewers }` literal plus a comment that defines `CONFIG` as the parsed config. | codebase-derived |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/stages/3-write-plan.md` — `design-sync.mjs` dispatch (1 site)
- `plugins/dev-pipeline/skills/run/stages/4-plan-review.md` — `plan-review.mjs` dispatch (1 site)
- `plugins/dev-pipeline/skills/run/stages/5-implement.md` — `mutation-gate.mjs` + `design-sync.mjs` dispatches (2 sites)
- `plugins/dev-pipeline/skills/run/stages/8-code-review.md` — `code-review.mjs` dispatch (1 site, the `{ reviewers, tracker }` case)
- `plugins/intake-toolkit/skills/intake-orchestrator/SKILL.md` — documented intake arg contract
- `plugins/intake-toolkit/skills/decomposition-reviewer/SKILL.md` — documented intake arg contract
- `plugins/dev-pipeline/skills/run/workflows/runtime-shim-selftest.mjs` — new delivery-path cases
- `scripts/lockstep-manifest.tsv` — DROPPED entry recording the unanchorable prose↔script coupling

## Reuse inventory

- `runtime-shim-lib.mjs` — `makeRunner`, `makeFakeAgent`, `reviewBlock`, `parallel`, `pipeline`, `noop` (existing exports; reused verbatim).
- `runtime-shim-selftest.mjs` — the existing `runCodeReview(behaviors, argsOverride)` helper already threads an args override and returns `f.calls`, each entry `{ prompt, opts }`. The new cases reuse it as-is; no new helper is introduced.
- `findingsBlock()` — existing local helper for a well-formed `code-review.mjs` payload; reused.

No new helpers introduced.

## Implementation steps

1. **`8-code-review.md`** — rewrite the comment above the `code-review.mjs` dispatch to state that `args.config` carries only the keys this script reads (`reviewers` for model overrides, `tracker` for the scope-reviewer fetch branch), define `CONFIG` as the parsed config, and cite why the whole config is not passed. Change the args literal to `config: { reviewers: CONFIG.reviewers, tracker: CONFIG.tracker }`.
2. **`4-plan-review.md`** — same comment rewrite; args literal becomes `config: { reviewers: CONFIG.reviewers }`. Keep the existing second comment line about bare vs qualified reviewer names.
3. **`5-implement.md`** — both sites (`mutation-gate.mjs`, `design-sync.mjs`): same rewrite, `config: { reviewers: CONFIG.reviewers }`. Preserve the existing `worktree`-anchoring comment at the `design-sync.mjs` site.
4. **`3-write-plan.md`** — `design-sync.mjs` site: same rewrite, `config: { reviewers: CONFIG.reviewers }`.
5. **`intake-orchestrator/SKILL.md`** — extend the documented production arg list to `{ issue, issueBody, referencedDocs, agents, readRoot, config }` and note that `config` carries the `reviewers` subset only, so `intake-review.mjs`'s per-agent overrides are reachable.
6. **`decomposition-reviewer/SKILL.md`** — add `config: { reviewers: CONFIG.reviewers }` to the shown `Workflow({...})` args and a one-line note.
7. **`runtime-shim-selftest.mjs`** — add a `[NEW]` delivery-path case block driving `code-review.mjs` through the existing `runCodeReview` helper: (a) a `modelOverrides` entry reaches the dispatched `opts.model`; (b) with the documented subset only, `tracker: { type: 'jira' }` still routes the `scope-completeness-reviewer` prompt to the Atlassian MCP; (c) with `tracker` absent, the prompt falls back to `gh issue view` — pinning that the key is load-bearing, so a future subset that drops it fails here.
8. **`scripts/lockstep-manifest.tsv`** — append a `[NEW]` DROPPED comment block: the five stage-file dispatch comments and the scripts' config reads are one contract, but neither side carries a byte-anchorable identical block; the delivery path is guarded behaviorally by step 7 instead.

## Test strategy

Verify-after (infra/prose change, no runtime behavior added). The substantive contract —
which config keys each script needs — is guarded behaviorally by new cases in
`runtime-shim-selftest.mjs`, which execute the **real** `code-review.mjs` body. Those cases
fail if the delivery path breaks or if `tracker` is dropped from the Stage-8 subset.

The prose edits themselves are deliberately unguarded: `CLAUDE.md` bans prose-presence
guards, and the tier map routes "prose in a markdown file" to *nothing*. The decision is
recorded in the manifest rather than left implicit.

`commands.second-shift.unitTestScope` is `null`, so there is no mutation surface and the
Stage-5 mutation gate does not apply.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Dispatch prose instructs passing only the `reviewers` subset needed by the scripts | 1–6 | `runtime-shim-selftest.mjs` delivery-path case (a)+(c) — overrides reach `opts.model`; a dropped key fails |
| AC-2 | A config carrying shell-command strings under `commands.<host>` dispatches plan-review/code-review without a serialization failure | 1–4 | — no test (infra-only) |

AC-2 needs a live Workflow dispatch and CI is model-free by design, hence the escape hatch.
Its evidence is this run's own Stage-4 and Stage-8 dispatches, which exercise the new subset
shape end to end.

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
node plugins/dev-pipeline/skills/run/workflows/runtime-shim-selftest.mjs
bash scripts/check-lockstep-pairs.sh
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -P 4 -n1 -I{} env SKIP_STRESS=1 bash {}
```

## Risks / rollback notes

- **Under-inclusive subset.** The per-script key sets are a snapshot of today's reads. A
  script that later starts reading a new config key would silently get `undefined`. Step 7's
  case (c) makes the failure mode visible for `tracker`; the comments state the rule
  ("only the keys this script reads") so the obligation travels with the next edit.
- **Cross-plugin blast radius.** Steps 5–6 touch `intake-toolkit`, outside the issue's
  Affected-files list. Recorded as D-2 and surfaced at intake; dropping those two steps is a
  clean partial rollback that still satisfies both ACs.
- **The trigger stays unmeasured.** If the #33 parse error was payload size or an escaping
  bug rather than the command strings, this reduces exposure without removing the mechanism.
  A recurrence looks the same: a dispatch dying in ~ms with 0 agents.
- Rollback is `git revert` of a docs/prose commit plus the selftest case block; no runtime
  code changes.

## Out-of-scope

- **Hardening the Workflow arg-serialization path.** The issue marks it optional and
  lower-priority, and the trigger was never isolated. **Handoff:** not tracked as a separate
  issue — reopen #77 if a dispatch dies in ~ms with 0 agents after this lands.
- Changing `reviewers.modelOverrides` semantics, the shipped model tiers, or the `fable`
  tier itself (#245).
- The `commands.<host>` config shape — no config schema change is made.

Unverified references: none. No `docs/plans` sibling introduces new helpers.
