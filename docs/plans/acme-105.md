# Plan — #105: Stage-8 a11y/design reviewer trigger is hardcoded to `apps/web/**/*.{tsx,jsx}`

## Context / problem framing

Stage-8 reviewer selection routes the a11y reviewer and the design-fidelity reviewer on a
single hardcoded literal — `apps/web/**/*.{tsx,jsx}` — stated as prose in
`plugins/dev-pipeline/skills/run/stages/8-code-review.md` (lines 73, 76, 78). There is no
config seam: `reviewers.add` carries only `{name, dimensions}`.

Consequence: on any consumer whose FE is not React-under-`apps/web`, the trigger never
matches and **an entire reviewer class silently does not run**. The change still gets
reviewed, so the run looks green — the accessibility/design dimension is simply absent,
with no signal. Reproduced on 3/3 synthetic FE consumers (Angular `.component.ts`/`.html`,
Vue `.vue` SFCs, React-Router-v7 `app/**/*.tsx`).

This is the same defect class `check-config-shadowing.sh` was built to prevent, inverted:
there, a published key nothing reads; here, a hardcoded literal with no key at all.

## Assumptions

- Stage-8 reviewer **selection** is in-session prose over `git diff --stat`; the fan-out
  script `workflows/code-review.mjs` is a dumb dispatcher over an already-selected
  `reviewers[]` array. Verified: it validates `reviewers` is a non-empty array and does no
  path matching. **No `.mjs` change is required.**
- An absent config key must reproduce today's behavior byte-for-byte (the repo's standing
  contract for every `stageParams` key).
- CI is model-free: correctness here is enforced by shell selftests + shellcheck + `jq`,
  not by a live pipeline run.

## Decision Ledger

| D-n | Decision | Provenance | Rationale |
| --- | --- | --- | --- |
| D-1 | New key `stageParams.webComponentGlobs`, not reuse of `stageParams.visualCapture.triggerGlobs` | codebase-derived | Stage-6 `triggerGlobs` means "what warrants a screenshot" — its default set includes `**/*.css` and `tailwind.config.{ts,js}`. Reusing it would route a11y/design reviewers on a tailwind-config-only diff, and would silently change Stage-8 routing for any consumer who already tuned `triggerGlobs` for capture. Two different questions, two keys. |
| D-2 | Default `["apps/web/**/*.{tsx,jsx}"]` | codebase-derived | Exactly today's Stage-8 literal. Explicitly NOT Stage-6's four-element set, which is neither a superset nor a subset. |
| D-3 | Matching stays model judgment over the configured patterns | codebase-derived | Stage-8 selection is prose over `--stat` output, not a mechanical pathspec match; Stage-6 (`6-verify.md:197`) sets the same precedent. Making it mechanical here would be a behavior change beyond this bug's scope. Stated explicitly so it reads as a decision, not an omission. |
| D-4 | Silent-skip signal is in scope | codebase-derived | The issue's Impact names "no signal that it was skipped" as part of the harm. Stage-8 synthesis already carries a dark-reviewer surfacing contract to hang one prose line on. |
| D-5 | `review-lead/SKILL.md:147` routing row is out of scope | codebase-derived | Different surface (standalone `/review-lead`, reads no consumer config) and already phrased generically. Deferring is a deliberate boundary, recorded in Out-of-scope. |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/stages/8-code-review.md` — the reader (trigger prose → config resolution + skip signal)
- `plugins/dev-pipeline/skills/run/tools/config-lint.sh` — `stageParams` allowlist + type check
- `plugins/dev-pipeline/skills/run/tools/check-config-shadowing.sh` — CHECKS registry row
- `schema/second-shift.config.schema.json` — publish the key
- `plugins/dev-pipeline/skills/run/tools/config-lint-selftest.sh` — assertions
- `plugins/dev-pipeline/skills/run/tools/config-lint-fixtures/valid-schema-key-standalone.json` — valid-shape coverage
- `plugins/dev-pipeline/skills/run/tools/config-lint-fixtures/invalid-type-gaps.json` — wrong-type coverage

All seven exist today. Unverified references: none. No new helpers are introduced — the
resolution reuses the established `jq -r '(.key // [<default>]) | .[]'` idiom from
`6-verify.md:179`.

## Reuse inventory

- `jq` config-with-default-fallback resolution idiom — `stages/6-verify.md:179`
  (`VC_TRIGGER_GLOBS`). Mirrored verbatim in shape; not re-invented.
- `check-config-shadowing.sh` CHECKS registry — existing `<file>|<key>|<label>` array;
  gains one row, no structural change.
- `config-lint.sh` `err(...)` combinator + the `keys - [...]` allowlist pattern — existing.
- `config-lint-selftest.sh` `expect_violation` helper and the `valid-*.json` glob loop
  (new valid fixtures are auto-discovered; no registration needed) — existing.

No `[NEW]` helpers.

## Implementation steps

1. **`schema/second-shift.config.schema.json`** — add `webComponentGlobs` to
   `stageParams.properties`: `array` of `string`, with a description stating the default
   and that it gates Stage-8 a11y + design-fidelity reviewer routing.
2. **`config-lint.sh`** — add `"webComponentGlobs"` to the `stageParams` allowlist
   (line ~202) and an `err((.webComponentGlobs? != null) and ((.webComponentGlobs | type) != "array"); "stageParams.webComponentGlobs: must be array")`
   type check, plus a per-entry string check mirroring `requiredLabels`.
3. **`stages/8-code-review.md`** — replace the hardcoded trigger clause with a resolution
   block mirroring `6-verify.md`:
   ```bash
   WEB_COMPONENT_GLOBS=$(jq -r '(.stageParams.webComponentGlobs // ["apps/web/**/*.{tsx,jsx}"]) | .[]' "$SECOND_SHIFT_CONFIG" 2>/dev/null || echo 'apps/web/**/*.{tsx,jsx}')
   ```
   Rewrite the trigger prose to key off `$WEB_COMPONENT_GLOBS` rather than the literal, and
   neutralize the two downstream `apps/web` mentions (lines 76, 78) so they describe "the
   repo's web-component surface". State D-3 (matching is model judgment) inline.
4. **`stages/8-code-review.md`** — add the D-4 skip signal: when no changed path matches
   `$WEB_COMPONENT_GLOBS`, synthesis notes that the a11y/design-fidelity dimension was not
   covered, so an absent dimension is visible rather than silent.
5. **`check-config-shadowing.sh`** — add
   `"stages/8-code-review.md|stageParams.webComponentGlobs|Stage-8 a11y/design trigger"`
   to `CHECKS`. This is the gate that makes step 3 non-optional: without a real reader in
   the stage file, the lint fails closed.
6. **Fixtures + selftest** — add `webComponentGlobs` (valid array) to
   `valid-schema-key-standalone.json`; add a wrong-type entry to `invalid-type-gaps.json`
   and a matching `expect_violation ... "stageParams.webComponentGlobs: must be array"`
   assertion in `config-lint-selftest.sh`.

## Test strategy

Verify-after (infra/prose change, no runtime code).

**What the shadowing lint does and does not prove.** `check-config-shadowing.sh` is a
`grep -qF` for the key string in the owning stage file. It proves the key is *mentioned*, not
that it is genuinely read — a stray comment naming the key would satisfy it. That is enough to
catch this issue's regression class (key published, reader never written / later deleted), and it
is the only mechanical guard available for a prose stage file, but it is a tripwire, not a proof
of behavior. Correctness of the reader itself rests on review, not on the lint.

- `check-config-shadowing.sh` — new CHECKS row must pass, and must go red if the reader is
  removed. Negative-verified by hand during implementation (strip the reader, confirm red,
  restore).
- `config-lint-selftest.sh` — valid fixture with the key passes; wrong-type fixture fails
  with the exact message.
- Full selftest sweep + shellcheck + `jq empty` per CLAUDE.md.

`unitTestScope` is `null` in this repo's config, so the mutation gate does not apply.

## Acceptance-criteria traceability

The issue body carries no `## Acceptance Criteria` heading, so the Stage-1 snapshot is
empty (`acceptanceCriteria: []`) per the positional fallback rule. Table header retained
with no rows, per the empty-snapshot case.

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
bash plugins/dev-pipeline/skills/run/tools/check-config-shadowing.sh plugins/dev-pipeline/skills/run
```

## Risks / rollback notes

- **Risk: the fix is prose, so it is only as good as the model reading it.** Mitigated by
  D-3 being explicit (the reader is told matching is judgment over configured patterns, not
  a hardcoded path) and by the shadowing lint proving the key is actually referenced.
- **Risk: a consumer sets an over-broad glob** (e.g. `**/*`) and routes a11y/design
  reviewers on every diff. Acceptable — it is opt-in, additive, and costs tokens rather
  than correctness.
- **Rollback:** revert the branch. An absent key reproduces today's behavior exactly, so
  no consumer config migration is needed in either direction.

## Out-of-scope

- `plugins/review-toolkit/skills/review-lead/SKILL.md:147` — the standalone `/review-lead`
  a11y routing row. Different surface, reads no consumer config, already phrased
  generically (D-5).
- The a11y-reviewer's own React/JSX/Tailwind-shaped prose. The issue defers this as a
  separate, softer follow-up; no follow-up issue filed yet.
- Making Stage-8 (or Stage-6) glob matching mechanical rather than model judgment (D-3).
- Any version bump or `CHANGELOG.md` entry — derived at release time per CLAUDE.md.
