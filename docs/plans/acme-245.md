# Plan — #245: `fable` as an override-only model tier + closing the unknown-token hole

## Context / problem framing

Two coupled defects in the same surface — the model-tier expressibility contract.

**1. The config surface cannot express Fable.** `reviewers.modelOverrides` values are enum-locked
to `haiku|sonnet|opus` in two places that are declared mirrors of each other:
`schema/second-shift.config.schema.json:173` (`modelOverrides.additionalProperties.enum`) and
`plugins/dev-pipeline/skills/run/tools/config-lint.sh:133`
(`IN("haiku","sonnet","opus")`). A repo whose subscription includes Fable-class models cannot
elevate its judgment-dense reviewers, even though the dispatch path already supports it —
`agent({model:'fable'})` resolves to `claude-fable-5` in-session, and every validated `.mjs`
already applies `modelOverrides[...]` ahead of its shipped table, so no dispatch code needs to
change.

**2. `check-model-tiers.sh` silently skips unknown tokens.** Its MAP-table extractor at
`plugins/review-toolkit/scripts/check-model-tiers.sh:253` greps
`'[a-z0-9:-]+': '(opus|sonnet|haiku)'` — the enum is baked into the *extraction* regex, so an
entry whose model token is anything else is never iterated at all. Not mismatched: invisible.
The inline-literal path at `:292` has the sibling defect in a different shape — when
`model: '(opus|sonnet|haiku)'` fails to match, `:295` falls through to `m="$scalar_model"`
rather than erroring, so an out-of-enum inline literal is silently attributed to the file's
scalar. The scalar constants themselves already fail closed (`PARSE:` errors at `:269` and
`:316`); the map and inline paths do not.

These are one change, not two: adding `fable` to the config enum without the guard would make
`fable` config-legal while nothing stops it landing in a *shipped* table, which is exactly the
override-only posture the design requires be mechanically enforced (D-4).

## Assumptions

1. **The pipeline runs on a subscription with Fable access.** Not load-bearing for this change —
   nothing here dispatches a model. It only matters to a consumer who sets the override.
2. **`fable` is the tier token the harness accepts** (alongside `opus`/`sonnet`/`haiku`).
   Grounded in the issue's empirical verification, restated in the ledger's context line; this
   change introduces no new dispatch call, so a wrong token would surface at the consumer's
   first override, not here.
3. **The unrestricted MAP entry shape matches only genuine table entries today.** Verified by
   running `grep -oE "'[a-z0-9:_-]+': '[a-zA-Z0-9:._-]+'"` over all three real MAP files
   (`code-review.mjs`, `intake-review.mjs`, `design-sync.mjs`): 18 matches, all of them
   `REVIEWER_MODEL`/`INTAKE_MODEL`/`DESIGN_MODEL` entries, zero false positives. D-5 accepts a
   future non-tier string map tripping it as a loud failure rather than a silent one.
4. **`SKIP_STRESS=1` is the sweep mode**, per `CLAUDE.md` Verification.

## Decision Ledger

Hydrated verbatim from the pre-flight ledger at `.claude/pipeline-state/245-ledger.md`.

| ID  | Decision | Resolution | Provenance |
| --- | -------- | ---------- | ---------- |
| D-1 | Mechanism for Fable in spawned dispatches | `reviewers.modelOverrides` value enum gains `fable`; precedence is already override > table > sonnet at every dispatch site, so no `.mjs` changes | codebase-derived |
| D-2 | Shipped defaults | Unchanged everywhere (tables, frontmatter, docs defaults); `fable` is opt-in per repo, so consumers without Fable access see zero change — operator-locked marketplace constraint | user-answered |
| D-3 | No-access failure mode | Rely on existing dead-dispatch handling — the reviewer surfaces dead and synthesis fails closed (`code-review.mjs` dead-shape handling + stage 8's dark-entry rule); document the outcome, not internal retry mechanics; build nothing new | codebase-derived |
| D-4 | check-model-tiers enum scope for `fable` | Shipped-code enums stay `opus\|sonnet\|haiku`; the new `UNKNOWN-MODEL` path flags `fable` in shipped tables/inline literals as an error, mechanically enforcing the override-only posture; alternations extend only if that policy is ever lifted. The override path itself needs zero script change (override values are never enum-checked; table==frontmatter passes) | codebase-derived |
| D-5 | UNKNOWN-MODEL scan shape | Whole-file grep over the three MAP files, consistent with the existing MAP grep — no region-extraction machinery; the unrestricted entry shape matches only genuine table entries today, and a future non-tier string map tripping it fails loud (the script's stated safe direction) | codebase-derived |
| D-6 | Selftest scope | Behavioral fixture cases per the issue's AC-4, each red-on-mutation demonstrated against a fixture where the pre-fix script exits 0 (truly silent); no prose-presence guards, no scenario extension (check-model-tiers is a standalone per-tool lint — nothing composes against it) | user-answered |
| D-7 | Commit/bump structure | One PR, one squashed `feat` commit; both touched plugins minor-bump (release derivation attributes plugins by path, level by verb) — intended, the `UNKNOWN-MODEL` enforcement is new review-toolkit capability | codebase-derived |
| D-8 | Out-of-scope surfaces | `figma.mjs` (`FIGMA_MODEL` literal, no override path) and `stall-probe.mjs` (arg-parameterized instrument) stay untouched — pre-existing gaps outside this issue; eval harnesses untouched; no lockstep-manifest row owed (model tiers excluded there by design) | user-delegated |
| D-9 | Docs touch | Minimal: SKILL.md Model Tier Mapping paragraph, one added sentence each in the extension-points and config-schema docs (neither currently lists the value enum — add, not extend), review-lead caller-model guidance mentions Fable alongside Opus | user-delegated |

Three further decisions were taken at Stage-1 intake, on spec-reviewer findings the pre-flight
ledger did not reach. They refine D-4/D-5/D-9 rather than contradicting them, and their
provenance is `codebase-derived`:

- **The inline out-of-enum scan covers all five parsed workflow files, not the two scalar ones.**
  D-5 fixes the *MAP-entry* scan at three files; the *inline* scan's file set was left unstated
  by both the issue and the ledger. Today the inline handling lives inside the
  `for spec in "unit-tests.mjs:…" "plan-review.mjs:…"` loop (`:258`–`:305`), so the inline
  literals at `code-review.mjs:235`, `intake-review.mjs:234` and `design-sync.mjs:168` are
  reached by **neither** loop — the MAP grep cannot match them because `model:` is an unquoted
  key. Scoping the new scan to the two scalar files would leave the hole open in 3 of the 5
  files and make D-4's "mechanically enforcing" claim false. The scan therefore runs over all
  five files the script already parses.
- **Agent frontmatter is deliberately not enum-guarded.** `frontmatter_model` (`:188`–`:192`)
  reads from the plugin root *and* the consumer root (`.claude/agents`, backing
  `reviewers.add`), so a consumer-owned agent may legitimately declare `fable` under precisely
  the feature D-1 adds — guarding it would reject the expressibility being introduced. A
  *shipped* agent with an out-of-enum tier that is named in a table still surfaces red (as
  `MISMATCH`), so the failure direction stays safe. Documented as a limitation.
- **The script's own header block joins the D-9 doc list.** `check-model-tiers.sh:1`–`:56` is
  the script's in-file contract spec (repo idiom — the inline-literal fix's reasoning sits
  in-file at `:271`–`:288`). It is the same file the code change edits, so this adds no new
  file to the touch list.
- **Override-value validation stays owned by `config-lint.sh` — deliberately not duplicated
  here.** `override_model()` (`:195`–`:199`) reads `reviewers.modelOverrides[$a]` with no enum
  check, and `check_pair`'s override branch (`:233`–`:238`) only string-compares it, so a typo'd
  override (`"opuss"`) is still accepted silently by this script whenever the table and
  frontmatter agree. That is the correct boundary, not an oversight: `config-lint.sh` validates
  the config surface at pre-flight, and a second copy of the enum inside `check-model-tiers.sh`
  would be the duplicate machinery the lockstep manifest's own header warns against. Stated so
  a reader does not take the Problem's "dark hole in the same surface" as closed end to end.
- **The four doc touches carry an explicit completion signal, but no test.** Change 6 maps to no
  acceptance criterion, and the repo's no-prose-presence rule forbids inventing a grep-based one
  (`CLAUDE.md`: grepping a literal out of a markdown file "cannot fail for a reason a reader of
  the diff would not already see"). The signal is therefore the plan's Affected-files list plus
  this sentence, checked by review rather than by a suite — which is the correct tier for prose.

## Affected files/modules

**Config expressibility (dev-pipeline + schema)**

- `schema/second-shift.config.schema.json` — `modelOverrides` block at `:173`
- `plugins/dev-pipeline/skills/run/tools/config-lint.sh` — `:133`
- `plugins/dev-pipeline/skills/run/tools/config-lint-selftest.sh` — `:35`
- `plugins/dev-pipeline/skills/run/tools/config-lint-fixtures/valid-fable-override.json` **`[NEW]`**

**Model-tier gate (review-toolkit)**

- `plugins/review-toolkit/scripts/check-model-tiers.sh` — header `:1`–`:56`, MAP loop `:245`–`:254`, inline block `:289`–`:299`
- `plugins/review-toolkit/scripts/check-model-tiers-selftest.sh` — new cases + one new fixture helper

No new files under `plugins/review-toolkit/scripts/fixtures/model-tiers/`: every new case is
generated at runtime by the existing `make_dp_variant` / `make_override_config` helpers or by one
new sibling helper, following the harness's mktemp'd-variant convention (`:62`, `:76`, `:143`).

**Docs**

- `plugins/dev-pipeline/skills/run/SKILL.md` — `## Model Tier Mapping` (`:370`)
- `docs/extension-points.md` — `### check-model-tiers.sh (config-aware)` (`:173`)
- `docs/config-schema.md` — the `reviewers` row (`:10`)
- `plugins/review-toolkit/skills/review-lead/SKILL.md` — `## Caller model guidance` (`:38`–`:40`)

## Reuse inventory

Every new selftest case reuses the harness that already exists — nothing new is introduced
beyond one fixture helper the issue's AC-4(d) explicitly requires.

- `run_cli()` (`check-model-tiers-selftest.sh:49`) — the env-override CLI runner; all new cases use it unchanged.
- `make_dp_variant()` (`:62`) — rewrites the fixture `code-review.mjs` MAP with a given key/model. Covers AC-4(b) (`fable`) and AC-4(c) (`gpt-4`) with **no** modification.
- `make_override_config()` (`:76`) — writes a config with one `modelOverrides` entry. Covers AC-4(a) with `"fable"` as the value, unchanged.
- `make_dp_inline_variant()` (`:143`) — the existing inline helper. Left untouched and still driving the two pre-existing inline cases, but **not reusable for either new inline case**: it hardcodes the file it writes (`unit-tests.mjs`) *and* its contents (`const UNIT_TEST_MODEL = 'sonnet'` plus a sibling `unit-test-plan-reviewer` dispatch). An earlier revision of this section claimed it could be reused as-is for AC-4(e); the Stage-4 plan review caught that, and it is wrong twice over — wrong file for (e), and wrong scalar for (d).
- `ok()` / `fail()` (`:36`–`:37`), `expect_violation()` (`config-lint-selftest.sh:35`) — assertion primitives, unchanged.
- New helper: `make_dp_inline_scalar_variant()` **`[NEW]`** — confirmed no existing equivalent. With an out-of-enum inline token, `make_dp_inline_variant`'s hardcoded `sonnet` scalar is what the pre-fix script falls through to, and it compares that against `structured-emitter`'s `haiku` frontmatter → `MISMATCH`, exit 1. That breaks AC-4(d)'s required "pre-fix exits 0" precondition, exactly as the issue predicts. The new helper parameterizes the scalar so it can equal the dispatched agent's frontmatter tier (`haiku`) and writes **only** the inline dispatch, so pre-fix the file is genuinely silent.
- New helper: `make_dp_map_inline_variant()` **`[NEW]`** — confirmed no existing equivalent. AC-4(e) needs the inline dispatch inside a **MAP** file (`code-review.mjs`); `make_dp_variant` writes a MAP table with no inline dispatch, and `make_dp_inline_variant` writes a scalar file. Neither shape exists.

## Implementation steps

1. **Schema enum** — add `"fable"` to `modelOverrides.additionalProperties.enum` in
   `schema/second-shift.config.schema.json`, and extend that block's `description` with one
   sentence: values must be tiers the consumer's subscription can dispatch; an inaccessible tier
   surfaces as a dead reviewer and the gate fails closed.
2. **config-lint** — `config-lint.sh:133`: `IN("haiku","sonnet","opus")` →
   `IN("haiku","sonnet","opus","fable")`, message → `must be haiku|sonnet|opus|fable`. This is
   the declared mirror of step 1 (file header: "Keep the two in lockstep").
3. **config-lint selftest** — update the `expect_violation` substring at
   `config-lint-selftest.sh:35` to the **full** new message, and add a valid fixture
   `config-lint-fixtures/valid-fable-override.json` carrying
   `"reviewers": {"modelOverrides": {"plan-reviewer": "fable"}}`, asserted to pass. The substring
   update is load-bearing: the old text is a strict prefix of the new one, so without it the
   assertion pins nothing and stays green regardless.
4. **`check-model-tiers.sh` — MAP unknown-token scan.** In the existing
   `for tbl in code-review.mjs intake-review.mjs design-sync.mjs` loop (`:245`), add a second
   whole-file pass alongside the enum-anchored extraction: grep the unrestricted entry shape,
   and for any entry whose model token is outside `opus|sonnet|haiku`, append an
   `UNKNOWN-MODEL:` error naming the table, the agent and the token. The existing enum-anchored
   grep and `check_pair` lockstep logic are untouched (D-4: tri-value enums stay).
5. **`check-model-tiers.sh` — inline unknown-token scan.** A scan over `agentType: '<name>'`
   lines carrying an inline `model: '<token>'` literal whose token is outside the enum → the
   same `UNKNOWN-MODEL:` error. Per the intake decision above, this runs over **all five**
   parsed workflow files (the three MAP files plus `unit-tests.mjs` and `plan-review.mjs`), not
   just the scalar pair. **The scan fires only on a quote-delimited `model: '<token>'`.** Lines
   whose `model:` is an expression (`modelOverrides[...] || SCALAR`) carry no literal, do not
   match, and keep falling through to the scalar exactly as before — so the `:292`–`:295`
   behavior changes only for out-of-enum *literals*. This discriminator is load-bearing rather
   than incidental: the naive reading, treating any non-enum text after `model:` as an unknown
   token, flags every expression-valued dispatch and denies every commit in the repo. AC-3's
   "still exits 0 on the real repo" is what catches that, so the failure would be loud — but it
   is stated here so the rule is read rather than discovered by breaking the build.
6. **`check-model-tiers.sh` — header.** Update the contract narrative (`:1`–`:56`) to name the
   `UNKNOWN-MODEL` error class and the surfaces the two new scans cover, and to state that agent
   frontmatter tokens are *not* enum-guarded and why.
7. **`check-model-tiers-selftest.sh` — new cases.** Add the five AC-4 cases (a–e) using the
   reuse inventory above, plus `make_dp_inline_scalar_variant()`. Extend the file's case-list
   header comment to match.
8. **Docs (D-9 + the header addition already covered in step 6).** One paragraph in the
   dev-pipeline `SKILL.md` Model Tier Mapping section (dispatched reasoning default stays
   `opus`; repos with Fable access may elevate individual judgment-dense agents via
   `reviewers.modelOverrides`; an inaccessible tier fails the dispatch closed; `fable` in a
   shipped table is a lint error by design). One added sentence each in `docs/extension-points.md`
   (`:173` section) and `docs/config-schema.md` (`:10` row). One clause in review-lead's
   `## Caller model guidance` naming Fable alongside Opus.

## Test strategy

Verify-after for the config-enum half (a two-token widening of a declarative check), test-first
for the `UNKNOWN-MODEL` half (a new behavior, and one whose whole point is that the pre-fix code
is silent — so each guard's fixture is written and observed **red on the fixed script / green on
the pre-fix script** before the guard is trusted).

**Unit test surface:** `commands.second-shift.unitTestScope` is `null`, so this repo has no
mutation-gate surface and the Stage-4/5 unit-test gate does not apply. Coverage here is the
per-tool behavioral selftests below, per the `CLAUDE.md` tier map ("one script's behavior against
fixtures → a per-tool behavioral selftest → `*-selftest.sh` next to the tool").

**No scenario extension.** Per D-6 and the `CLAUDE.md` scenario-first rule: the invariant guarded
is a standalone per-tool lint's own exit behavior — `check-model-tiers.sh` is invoked as a
pre-commit hook and a CLI, and no verdict path in `scenario-liveness-selftest.sh` composes
against it, so there is no composed path for a scenario to cover. Likewise no
`scripts/lockstep-manifest.tsv` row: the schema ↔ `config-lint.sh` enum coupling is real, but
model tiers are excluded from that manifest by design and enforced by `check-model-tiers.sh`
itself (D-8).

**New cases in `check-model-tiers-selftest.sh`:**

| Case | Fixture | Pre-fix | Post-fix |
| --- | --- | --- | --- |
| (a) `fable` override, clean table | `make_override_config "security-reviewer" "fable"` over clean `$DP` | exit 0 | exit 0 — pins that override values are never enum-checked |
| (b) `fable` in a shipped MAP entry | `make_dp_variant fablemap "security-reviewer" "fable"` | exit 0 (silent) | exit 1 + `UNKNOWN-MODEL` |
| (c) `gpt-4` in a shipped MAP entry | `make_dp_variant unknownmap "security-reviewer" "gpt-4"` | exit 0 (silent) | exit 1 + `UNKNOWN-MODEL` |
| (d) out-of-enum inline literal, scalar file | `make_dp_inline_scalar_variant` **`[NEW]`** — scalar `haiku`, only the `structured-emitter` dispatch, `model: 'gpt-4'` | exit 0 (silent) | exit 1 + `UNKNOWN-MODEL` |
| (e) out-of-enum inline literal, MAP file | a `code-review.mjs` variant carrying a `structured-emitter` dispatch with `model: 'gpt-4'` | exit 0 (silent) | exit 1 + `UNKNOWN-MODEL` |

Case (d)'s fixture shape is not incidental — with the existing `make_dp_inline_variant` the
pre-fix run exits **1** (`MISMATCH`, scalar `sonnet` vs `structured-emitter` frontmatter
`haiku`), which would make the red-on-mutation demo vacuous. The `haiku`-scalar,
single-dispatch shape is what makes the pre-fix silence real.

Existing cases stay green unchanged — in particular `inline-ok` (inline `haiku` honored over a
`sonnet` scalar) and `inline-drift` (inline `opus` vs `haiku` frontmatter → `MISMATCH`), which
together pin that the new scan did not disturb in-enum inline handling.

**In `config-lint-selftest.sh`:** the updated `invalid-unknown-repo-and-tier.json` assertion
(full message) plus the new `valid-fable-override.json` fixture asserted valid — and, folded in
from the Stage-4 plan review, an executable **schema ↔ config-lint enum mirror** check. Step 1's
schema edit otherwise had no assertion behind it beyond `jq empty` (syntax only) and a mirror
implemented separately in `config-lint.sh`, so a one-sided widening was silent. The check drives
both artifacts rather than grepping either: forward, every tier the schema declares must be
accepted by `config-lint`; backward, `config-lint`'s rejection message must name **exactly** the
schema's enum, compared with `=` rather than a substring grep (a prefix match would go green in
precisely the direction the check exists to catch — the same false-green shape AC-1 fixes).

**AC-5 red-on-mutation demos** are recorded in the commit body: for each new guard, revert the
guard, observe the case go green (i.e. the hole reopens), restore.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | `config-lint.sh` accepts `fable`, rejects unknown with the full new message; selftest asserts full text | 2, 3 | `config-lint-selftest.sh` — updated `expect_violation` (full message) + new `valid-fable-override.json` valid case |
| AC-2 | schema enum in lockstep; `jq empty` + existing config-lint suite green | 1, 2 | `config-lint-selftest.sh` — the schema↔config-lint enum mirror check (forward per-tier acceptance + exact backward message comparison) plus the full suite; `jq empty` sweep |
| AC-3 | `UNKNOWN-MODEL` + exit 1 for out-of-enum MAP entry and inline literal; exit 0 on the real repo | 4, 5 | `check-model-tiers-selftest.sh` cases (b)–(e); real-repo run in the verification sweep |
| AC-4 | new behavioral fixture cases (a)–(e) | 7 | `check-model-tiers-selftest.sh` cases (a)–(e), incl. the two new helpers `make_dp_inline_scalar_variant` and `make_dp_map_inline_variant` |
| AC-5 | red-on-mutation demos recorded in the commit body | 4, 5, 7 | — no test (non-functional) |
| AC-6 | verification sweeps green | 1–8 | — no test (infra-only) |

## Verification commands

```bash
# the repo's three sweeps (CLAUDE.md Verification)
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}

# the two directly-changed suites, run alone for a readable signal
bash plugins/dev-pipeline/skills/run/tools/config-lint-selftest.sh
bash plugins/review-toolkit/scripts/check-model-tiers-selftest.sh

# AC-3's real-repo assertion: the gate must still pass on this repo unchanged
bash plugins/review-toolkit/scripts/check-model-tiers.sh </dev/null; echo "exit=$?"

# AC-1/AC-2 spot check against this repo's own config
bash plugins/dev-pipeline/skills/run/tools/config-lint.sh .claude/second-shift.config.json
```

## Risks / rollback notes

- **The unrestricted MAP shape over-matching.** A future non-tier `'key': 'value'` string map in
  one of the three MAP files would be scanned and, if its value is outside the enum, raise
  `UNKNOWN-MODEL`. D-5 accepts this: it fails loud, in the script's stated safe direction, and
  today it matches zero non-entries (assumption 3, verified). Rollback is a one-line regex
  narrowing.
- **Inline scan reaching the three MAP files (the intake refinement).** All three carry a
  `structured-emitter` dispatch with `model: 'haiku'` — in-enum, so the real repo stays green;
  case (e) is what proves the scan actually reaches those lines rather than passing vacuously.
- **Widening a config enum is one-way in practice.** A consumer who adopts `fable` and later
  downgrades the plugin hits a lint rejection. Consistent with D-2's opt-in posture; nothing
  ships enabled.
- **Rollback:** every change is additive and independently revertible — the enum widenings
  (steps 1–3) and the guard (steps 4–7) are separate hunks in one commit, and reverting the
  commit restores exact prior behavior. No migration, no state, no config-version bump.

## Out-of-scope

- **In-enum lockstep drift on MAP-file inline literals.** `code-review.mjs:235`,
  `intake-review.mjs:234` and `design-sync.mjs:168` are validated by neither loop today, and this
  change adds only the *out-of-enum* error path for them — flipping one to `model: 'opus'`
  against `structured-emitter`'s `haiku` frontmatter stays silent. Declared at intake, wider
  than this issue's unknown-token scope, and **filed as its own tracked issue** (#247) rather
  than left as an unnamed intention.
- **Agent frontmatter enum-guarding** — deliberately not done; see the Decision Ledger prose.
- **`figma.mjs` and `stall-probe.mjs`** (D-8) — the former has no `modelOverrides` path and is
  not parsed by `check-model-tiers.sh` at all; the latter is an arg-parameterized instrument.
- **All shipped `.mjs` dispatch tables, agent frontmatter, and defaults** (D-2) — unchanged.
- **Version bumps and `CHANGELOG.md`** — derived at release time; a feature PR touching them is
  rejected by CI (`scripts/check-frozen-files.sh`).
- **Dogfood adoption** (config overrides + session-model choice) — operator-side after release.

Unverified references: none. Every path, function and line reference above was confirmed against
the branch base (`origin/main` @ `cfd6764`), except the two items tagged `[NEW]`.
