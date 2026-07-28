# acme-127 — make the Stage-6 INERT classifier overridable for non-JS/TS consumers

## Context / problem framing

`plugins/dev-pipeline/skills/run/tools/is-inert-diff.sh` classifies a diff INERT when every changed
path matches one hardcoded JS/TS-centric ERE (`INERT_RE`). `plugins/dev-pipeline/skills/run/verifyctl.sh`
then takes its INERT branch, runs at most a scoped `prettier --check`, and reports
`skipped (inert diff — no JS/TS surface)`.

For a consumer whose product surface *is* those extensions, that is a false green: the configured
`lint` and `test` lanes are read from config and never invoked. This repo is that consumer — nine
recurrence datapoints are recorded on the issue, each a `*.sh`/`*.md` branch whose real verification
came from the operator's hand-run and post-push CI rather than from Stage 6.

The maintainer decision on the issue is binding and picks **option (c)**: keep the JS/TS regex as the
**default**, add a config key that **overrides** it. Explicitly excluded: a per-lane `scope` glob, and
any `commands.<host>` schema expansion.

### ACs are read through that decision

AC-1 and AC-3 are worded in option-(b) vocabulary ("a repo whose config sets a non-null `lint`/`test`",
"derived from configured commands"). The decision comment
([#127 comment](https://github.com/manoldonev/second-shift/issues/127#issuecomment-5020574255))
supersedes that wording and post-dates the AC section. The effective reading this plan implements:

- **AC-1′** — a repo whose config sets the override to a pattern excluding `*.sh` runs its configured
  `lint`/`test` at Stage 6, and `verifySummary` reports their real result.
- **AC-3′** — the effective pattern set is the configured override when present and the shipped JS/TS
  default otherwise; the selftest covers override-absent, override-present, and malformed-override.
  AC-3's literal third case — "a repo with all lanes null" — is **not** expressible in the classifier's
  own selftest under this design, because the classifier takes no lane input at all: the pattern and the
  lane set are independent once the decision stops being derived from `commands.<host>.*`. It is covered
  where it becomes expressible, composed through config + verifyctl, by `verifyctl-selftest.sh` `(v31)`:
  an all-lanes-null repo under an override still re-derives SUITE and still emits the honest all-skipped
  summary the Stage-6 content gate refuses, so the override cannot manufacture a false green.

AC-2 and AC-4 stand as written. The issue body is not rewritten; the divergence is disclosed here, in
the intake comment, and in the PR body because the Stage-8 scope gate reads the body literally.

## Assumptions

1. The decision comment is binding and outranks the AC wording it contradicts.
2. `stageParams` is the correct home: `commands.<host>` is excluded by the decision, and a new
   top-level key would be a novel pattern where `stageParams.formatGlob` is an exact precedent.
3. Widening the inert set is the only dangerous direction (it skips verification). Narrowing merely
   over-runs the suite — waste, never a false green. Every fallback in this change therefore resolves
   toward SUITE.
4. `.claude/second-shift.config.json` is gitignored in this repo, so this PR cannot switch this repo's
   own behavior on. That is an operator step after merge, not a deliverable here.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Which of the three options in the issue's "Direction" section to build | Option (c) — JS/TS regex as an overridable default; no per-lane `scope` glob, no `commands.<host>` expansion | ticket-sourced — [#127 comment](https://github.com/manoldonev/second-shift/issues/127#issuecomment-5020574255) |
| D-2 | Config key path | `stageParams.inertPattern` | codebase-derived — `commands.<host>` is excluded by D-1; `stageParams.formatGlob` (`schema/second-shift.config.schema.json`, `config-lint.sh:202`, `verifyctl.sh` `FORMAT_GLOB`) is the exact structural precedent for a JS/TS-centric default a consumer overrides wholesale |
| D-3 | Value shape and semantics | A single ERE string that **replaces** the default outright; absent or `null` reproduces today's behavior byte-for-byte | codebase-derived — `formatGlob` is likewise a full replacement, and replace is the only semantics that can *remove* `\.sh$` from the set, which AC-1′ requires. A subtract-list (`nonInertPatterns: ["\\.sh$"]`) would be terser and drift-proof but is a design invention beyond "add a config key to override it"; rejected, with the hand-copy cost accepted |
| D-4 | How config reaches a script that has never read config | `verifyctl.sh` resolves the key and passes it as `argv[1]`; the script keeps its in-file default when the argument is absent or empty | codebase-derived — `verifyctl.sh:334` is the **only** runtime caller (`pre-commit-typecheck.sh` shares a textual sub-pattern but never executes the classifier), and verifyctl already resolves config through a `--git-common-dir`-anchored path that works from inside a worktree. Self-resolution would have to pick a root, and picking the worktree would make the override silently vanish — the same false-green class this issue exists to kill |
| D-5 | Behavior on an uncompilable override | Fail **closed** to SUITE with a stderr diagnostic | codebase-derived — measured: `grep -E` exits `2` on a bad pattern, and the existing `if grep -vE …; then suite; else inert; fi` reads any non-zero as "no non-inert path found" and reports **INERT**. Left alone, a typo'd override becomes a silent repo-wide verification skip |
| D-6 | Host and predicate for AC-4 | `preflight.sh`; WARN when a verifying lane is configured **and** every tracked file (`git ls-files`) classifies inert under the effective pattern | codebase-derived — `preflight.sh:311-319` already owns the sibling zero-lane WARN and has a real consequence (`UNVERIFIED=1` → "NOT pipeline-ready"), whereas `pipeline-doctor.sh`'s `warn()` is informational only. Feeding `git ls-files` through the real classifier is decidable and avoids reasoning about the regex |
| D-7 | Whether the format lane's INERT→SUITE side effects are in scope | Deferred — documented as a risk, not changed | deferred — flipping a diff to SUITE also enables setup `lanes[]`, `extraLanes`, and `prettier --write`. Inert for this repo (`format: null` → `FORMAT_MODE=skip`), and the issue's out-of-scope covers the format path. Real for a consumer that leaves `format` absent; recorded under Risks |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/tools/is-inert-diff.sh` — accept an optional override; fail closed on a bad pattern
- `plugins/dev-pipeline/skills/run/tools/is-inert-diff-selftest.sh` — override cases
- `plugins/dev-pipeline/skills/run/verifyctl.sh` — resolve `stageParams.inertPattern`, pass it at the one call site
- `plugins/dev-pipeline/skills/run/verifyctl-selftest.sh` — the composed AC-1′ proof
- `plugins/dev-pipeline/skills/run/tools/config-lint.sh` — accept and validate the key
- `plugins/dev-pipeline/skills/run/tools/config-lint-selftest.sh` — accept/reject assertions
- `plugins/dev-pipeline/skills/run/tools/config-lint-fixtures/invalid-bad-inertpattern.json` — `[NEW]` uncompilable pattern
- `plugins/dev-pipeline/skills/run/tools/config-lint-fixtures/invalid-empty-inertpattern.json` — `[NEW]` explicit empty value
- `plugins/dev-pipeline/skills/run/tools/config-lint-fixtures/valid-schema-key-standalone.json` — the accept path, via the selftest's `valid-*.json` auto-discovery loop
- `plugins/dev-pipeline/skills/run/tools/check-config-shadowing.sh` — register the new key's reader
- `schema/second-shift.config.schema.json` — the documented contract config-lint mirrors
- `plugins/dev-pipeline/skills/run/tools/preflight.sh` — the AC-4 unreachable-lane WARN
- `plugins/dev-pipeline/skills/run/tools/preflight-selftest.sh` — WARN fires / does not fire
- `plugins/dev-pipeline/skills/run/stages/6-verify.md` — the lane reference stops claiming a fixed set
- `docs/extending.md` — the `stageParams` example

## Reuse inventory

- `INERT_RE` in `is-inert-diff.sh` — the existing default literal. Kept under its current name and
  byte-identical, because `pre-commit-typecheck-selftest.sh:98-111` greps literal substrings out of it.
- `check()` / `run()` in `is-inert-diff-selftest.sh` — extended with an optional argument, not replaced.
- `reset_all()` / `vrun()` / the `$MARKERS` PATH-shim harness in `verifyctl-selftest.sh` — reused as-is
  for the new composed case.
- `expect_violation()` and the `valid-*.json` auto-discovery loop in `config-lint-selftest.sh` — reused;
  the new invalid fixture is picked up by adding one `expect_violation` line.
- `warn()` and the `UNVERIFIED` flag in `preflight.sh` — reused; the new check mirrors the sibling
  zero-lane WARN rather than inventing a second reporting shape.
- `FORMAT_GLOB` resolution in `verifyctl.sh` `load_config()` — the pattern the new `INERT_PATTERN`
  resolution copies.
- `pipeline-doctor.sh` section 5h already auto-discovers `is-inert-diff-selftest.sh`; no registration.

No new helpers introduced.

## Implementation steps

1. **(test-first)** Add three `check` rows to `is-inert-diff-selftest.sh` extending `check`/`run` with an
   optional pattern argument: override-absent `*.sh` → inert (regression); override-present (default
   minus `\.sh$`) `*.sh` → suite; override-present `*.md` → inert. Run and confirm the override rows
   FAIL — the script ignores `argv[1]` today, so this proves the cases are real.
2. **(test-first)** Add a fourth row: a malformed override (`(`) → **suite**, with a non-empty stderr.
   Confirm it FAILS today by temporarily observing that `grep -vE '('` exits 2 and the current
   `if/else` reports inert.
3. Edit `is-inert-diff.sh`: keep `INERT_RE='…'` verbatim as the default, resolve
   `PATTERN="${1:-$INERT_RE}"`, replace the trailing `if grep -vE …` with an explicit rc capture and a
   three-way `case` — `0`→suite, `1`→inert, `*`→stderr diagnostic + suite. Update the header contract
   comment to document `argv[1]`, the empty/absent fallback, and the fail-closed rule.
4. Re-run `is-inert-diff-selftest.sh`; all rows green, including the 28 pre-existing ones unchanged.
5. Edit `verifyctl.sh`: resolve `INERT_PATTERN` from `.stageParams.inertPattern // ""` in `load_config()`
   alongside `FORMAT_GLOB`, and pass it at the single call site (`bash "$IS_INERT" "$INERT_PATTERN" <<< "$changed"`).
6. **(test-first)** Add `(v29)` to `verifyctl-selftest.sh`: a config fixture carrying
   `stageParams.inertPattern` = the default minus `\.sh$`, a `*.sh`-only commit, and an assertion that
   `lane == "SUITE"`, that the `lint`/`test` markers fired, and that `verifySummary` is the real object
   rather than the `inert diff` string. Add `(v30)`: the same fixture with a `*.md`-only commit still
   yielding `lane == "INERT"`. This is AC-1′ and AC-2's composed proof.
7. Edit `config-lint.sh`: add `inertPattern` to the `stageParams` key allowlist, plus a string type check
   and a non-empty check. Add a bash-side compile check after the jq pass (`grep -E` against empty input;
   rc ≥ 2 ⇒ violation) so an uncompilable pattern is rejected at config time, not discovered at Stage 6.
8. Add **two** invalid fixtures — `invalid-empty-inertpattern.json` and
   `invalid-bad-inertpattern.json` — plus the matching `expect_violation` lines in
   `config-lint-selftest.sh`. Two files, not one: a fixture may carry several violations, but a
   single `stageParams.inertPattern` cannot be both empty and uncompilable, so the two rejection
   classes cannot share a file. Add `inertPattern` to `valid-schema-key-standalone.json` so the
   accept path is covered by the auto-discovery loop.
9. Add `stageParams.inertPattern` to `schema/second-shift.config.schema.json` (`type: string`,
   `minLength: 1`, description). Additive and optional — no `configVersion` bump, no migration doc
   (`check-configversion-migration-doc.sh` only fires on a `configVersion.const` change).
10. Edit `preflight.sh`: after the existing zero-lane block, when `VERIFYING > 0`, feed `git ls-files`
    through `is-inert-diff.sh` with the effective pattern; on inert set `UNVERIFIED=1` and `warn` naming
    the condition and the remedy (`stageParams.inertPattern`).
11. **(test-first)** Add two `preflight-selftest.sh` cases: a fixture repo of only `*.sh` with lanes
    configured and no override → WARN fires; the same repo with the override set → no WARN.
12. Update `stages/6-verify.md`'s "Lane reference" to describe the enumerated set as the **default**,
    overridable via `stageParams.inertPattern`, with the fail-closed rule stated.
13. Update the `stageParams` example in `docs/extending.md` with a commented `inertPattern` line.

## Test strategy

Verify-after for the mechanical edits (schema, docs), **test-first** for every behavior change —
steps 1, 2, 6, 11 all write a failing assertion before the code that satisfies it.

`unitTestScope` is `null` in this repo's config, so there is no mutation surface and the Stage-3 unit
test gate is `skip`.

### Why these are per-tool cases and not scenarios

Per the repo's scenario-first rule, each new per-tool case must say why no scenario in
`scenario-liveness-selftest.sh` covers it. That suite's verify involvement is the Stage-6 **attestation**
gate (`ns4`) and the **circuit breaker** — both composed verdict paths that reach a terminal write, and
both unchanged here: the override is absent by default, so every existing scenario runs byte-identically.
This change adds no new pipeline verdict path and no new terminal write, so there is nothing for a
scenario to compose against. The `preflight.sh` WARN is a pre-run advisory that flips a summary line,
not a stage gate.

The composed proof that *does* matter — config → verifyctl → classifier → lane → real command execution
— is `verifyctl-selftest.sh` `(v29)`/`(v30)`, which drive the real verifyctl with a real config fixture
and assert on marker files that `lint` and `test` actually ran. A classifier-only unit case cannot prove
AC-1′, because AC-1′ is a claim about what Stage 6 executes.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | `*.sh`-only diff runs the configured lanes; `verifySummary` is real (read as AC-1′) | 3, 5, 6 | `verifyctl-selftest.sh` `(v29)`; `is-inert-diff-selftest.sh` override-present `*.sh` → suite |
| AC-2 | docs-only diff still skips the suite (override absent — the discriminating input) | 1, 3, 6 | `verifyctl-selftest.sh` `(v1)` unchanged + `(v30)`; `is-inert-diff-selftest.sh` override-absent rows (28 pre-existing) |
| AC-3 | pattern set is override-when-present / default-otherwise; selftest covers the three states (read as AC-3′) | 1, 2, 3, 4, 6 | `is-inert-diff-selftest.sh` — override-absent, override-present, malformed-override; `verifyctl-selftest.sh` `(v31)` for the all-lanes-null case |
| AC-4 | unreachable configured lanes surface as a WARN before a run | 10, 11 | `preflight-selftest.sh` — WARN fires / does not fire |

## Verification commands

```bash
# scoped, fastest first
bash plugins/dev-pipeline/skills/run/tools/is-inert-diff-selftest.sh
bash plugins/dev-pipeline/skills/run/tools/config-lint-selftest.sh
bash plugins/dev-pipeline/skills/run/tools/preflight-selftest.sh
bash plugins/dev-pipeline/skills/run/tools/pre-commit-typecheck-selftest.sh   # INERT_RE lockstep
SKIP_STRESS=1 bash plugins/dev-pipeline/skills/run/verifyctl-selftest.sh

# repo gates (CLAUDE.md)
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -P 4 -n1 -I{} env SKIP_STRESS=1 bash {}

# commit-time gates — these run on the branch, not just in CI, so a violation blocks
# the commit rather than surfacing at review. The shadowing check is load-bearing for
# this change specifically: it is what fails if the new config key is published
# without a reader.
bash plugins/dev-pipeline/skills/run/tools/check-config-shadowing.sh
bash plugins/dev-pipeline/skills/run/tools/check-config-shadowing-selftest.sh
bash scripts/check-frozen-files.sh main        # both take the base ref; without it
bash scripts/check-changelog-trailer.sh main   # they print usage and exit non-zero

# the config-lint contract against this repo's own config
bash plugins/dev-pipeline/skills/run/tools/config-lint.sh .claude/second-shift.config.json
```

## Risks / rollback notes

- **SUITE brings more than lint/test.** A diff flipped from INERT to SUITE also runs setup `lanes[]`,
  `extraLanes`, and switches format from a scoped `prettier --check` to `prettier --write`. Inert for
  this repo (`commands.second-shift.format: null` → `FORMAT_MODE=skip`, so no formatter runs on either
  lane). Real for a consumer that leaves `format` **absent**: they get the prettier default, and with no
  local binary the `npx` fallback's rc 126/127 becomes an `INFRA` hard stop. Documented in step 12's
  `6-verify.md` edit; not otherwise changed (D-7).
- **Replace-semantics drift.** A consumer's override is a hand-copy of the default and will not inherit
  future additions to it. Accepted under D-3; the `6-verify.md` edit says so.
- **`stageParams` is global; the classifier runs per-repo.** Raised by plan review. `verifyctl --repo <id>`
  verifies one target at a time in a `be-fe-pair` topology, but resolves this single global value for
  every one of them, so a pair whose repos have genuinely different product surfaces (a TS front end
  beside a shell back end) cannot express that. The workable answer is the union pattern that leaves
  BOTH surfaces non-inert — which errs toward SUITE, the safe direction. Documented in the `6-verify.md`
  edit rather than fixed: a per-repo override belongs under `topology.repos.<id>`, and D-1 excludes
  schema expansion. Deferred until a real pair consumer needs it.
- **Selftest fixture reality.** `preflight-selftest.sh`'s shared fixture repo tracked only `*.md`, so its
  whole tree classified inert — meaning its configured typecheck lane could never run, and the new AC-4
  check fired across cases about other things. The fixture gains one tracked `.ts` source. This is a
  correction to the fixture's realism, not a weakening of the check: the AC-3 assertion "a repo that
  verifies something still reports pipeline-ready" was resting on a repo that in fact verified nothing.
- **Lockstep with the pre-commit hook.** `INERT_RE` keeps its name and literal precisely so
  `pre-commit-typecheck-selftest.sh`'s substring assertions keep passing; that suite is in the
  verification list and its failure is the intended tripwire if step 3 restructures too aggressively.
- **This repo is not fixed by this PR.** Its config is gitignored, so the override must be set
  machine-locally after merge. Until then a `*.sh`-only branch here still reports
  `skipped (inert diff)`. Called out in the PR body as an operator handoff.
- **AC-4's predicate does not fire for this repo** — measured: `git ls-files | is-inert-diff.sh` returns
  `suite`, because tracked non-inert JSON exists (`.claude-plugin/marketplace.json`, `schema/*.json`,
  every `plugins/*/.claude-plugin/plugin.json`). This repo's problem is that lanes never run for the
  *typical* diff, which is strictly weaker than AC-4's "could never run for **any** diff". Implementing
  the AC as written rather than widening the predicate so it fires here.
- **Rollback:** every step is additive and independently revertible. Reverting only the `verifyctl.sh`
  call-site change (step 5) restores today's behavior everywhere while leaving the key inert.

## Out-of-scope

- What `verifyctl` does *inside* a lane once selected (issue's out-of-scope).
- The prettier/format path for JS/TS consumers (issue's out-of-scope).
- A per-lane `scope` glob and any `commands.<host>` schema expansion (excluded by D-1; reserved until
  real non-JS adoption materializes).
- Setting the override in this repo's own gitignored config (operator step after merge).
- Rewriting AC-1/AC-3 in the issue body.

Unverified references: none.
