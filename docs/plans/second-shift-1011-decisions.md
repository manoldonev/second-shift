# Intake receipt — #1011

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Mechanism and reach of the quoting fix (item 1) | `-c core.quotePath=false` on every name-list read `run.sh` makes: the review input's name-status and name-only reads, the two staleness-overlap reads in `premise_holds`, and the `CHANGED` read that gates when-scoped lanes (a lane whose glob names a non-ASCII path is skipped today, not only listed as not run). The deleted/renamed awk gets `-F'\t'` so a space in a path stops splitting the field. Weighed: the ticket's review_input-only scope (leaves lane selection and the staleness check quoted); `-z` with NUL parsing (raw names for every path, but status and path arrive as separate NUL records, a rename as three, so both awk consumers and the pathspec loop are rewritten). Residual: a path holding `"`, `\` or a tab stays C-quoted under `quotePath=false` and is still dropped; out of scope, bounded by D-9 | user-answered | intent |
| D-2 | This repo's `*-selftest.sh` / `*-selftest.mjs` never match `TEST_PATH_ERE` (item 2) | Append `\|-selftest\.` to the built-in pattern. The widened pattern matches exactly the 55 selftest files more and no non-test file, and consumer output is byte-identical over eight recent consumer commits. #956 D-3 (built-in patterns only) stands. Weighed: a consumer-declared glob under `paths` (the schema is `additionalProperties:false`, so a schema edit; additive, no `configVersion` bump; config-lint and doctor touched; no consumer shows demand: 0 unmatched test files across five local consumer checkouts); keeping the pattern and recording the consequence | user-answered | intent |
| D-3 | Manual review skill parallel path | `plugins/dev-pipeline/skills/review/SKILL.md` step 4 lists the test-path conventions in prose, so the clause gains `*-selftest.*`, as #956 D-4 and #957 D-7 did for their widenings — run: `sed -n '45p' plugins/dev-pipeline/skills/review/SKILL.md` → "(a top-level `tests/`, `__tests__/`, `test_*.py`, `conftest.py`, `_spec.` count too)" | codebase-derived | fact |
| D-4 | Regression guards | `run-selftest.sh` cases that fail without the fix: a modified spec at a non-ASCII path listed in the expectations section with its removed line; a deleted test whose path holds a space listed in the deleted/renamed section; a modified `*-selftest.sh` fixture listed in the expectations section; a when-scoped lane whose glob names the non-ASCII path runs. The fixture name and the expected literal are written in NFC bytes (macOS git recomposes to NFC; Linux does not). The harness pins `core.quotePath=true` through `GIT_CONFIG_COUNT`/`GIT_CONFIG_KEY_0`/`GIT_CONFIG_VALUE_0` around these cases, since a machine with a global `quotePath=false` would pass them without the fix and `-c` overrides that env — run: `grep -cE 'HOME=\|GIT_CONFIG' plugins/dev-pipeline/skills/run/run-selftest.sh` → 0 (no git-config isolation today); CLAUDE.md: a `run.sh` behavior change lands with a `run-selftest.sh` case that fails without it | codebase-derived | fact |
| D-5 | How the pattern reaches awk | Stays `ENVIRON["TEST_PATH_ERE"]`, never `awk -v`: BSD awk expands backslash escapes in `-v`, so `\.test\.` becomes `.test.` and `run-selftest.sh` matches spuriously — run: `printf 'plugins/dev-pipeline/skills/run/run-selftest.sh\n' \| awk -v e="$TEST_PATH_ERE" '$0 ~ e'` → prints the line; the `ENVIRON` form prints nothing | codebase-derived | fact |
| D-6 | PR verb | `fix(dev-pipeline):`, patch, with a `Changelog:` trailer, as #956 did for the same detector widening | user-answered | intent |
| D-7 | Duplicate scan | None — run: `dup-scan.sh --issue 1011` → "no candidates at or above threshold 12 (corpus: 0 scanned)" | codebase-derived | fact |
| D-8 | Stack-generality lint | Not a constraint on `TEST_PATH_ERE`: the lint guards `.project/` and `unit-testing` literals in named files only — run: `grep -c 'run.sh' scripts/stack-generality-lint.sh` → 0 | codebase-derived | fact |
| D-9 | Consumer exposure to item 1 | No probed checkout tracks a path with a non-ASCII byte, a space, a quote or a backslash, so item 1 is latent in consumers and D-1's residual costs nothing today — run: `git -c core.quotePath=false ls-files \| LC_ALL=C grep -c '[^ -~]'` → 0 in this repo and in each of two consumer checkouts (a backend and a frontend) | codebase-derived | fact |

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | Review input: "Existing test or snapshot expectations changed" on a diff with a non-ASCII test path | decided (D-1) |
| S-2 | Review input: "Deleted or renamed test files" on a non-ASCII path or a path with a space | decided (D-1) |
| S-3 | Review input: "CI or check configuration edited" on a non-ASCII config path | decided (D-1) |
| S-4 | Review input: "Configured lanes not run on this diff", and the lanes actually run, when a `when` glob names a non-ASCII path | decided (D-1) |
| S-5 | Staleness check: base-branch overlap on a non-ASCII path | decided (D-1) |
| S-6 | Both test sections on a second-shift PR that edits `*-selftest.sh` / `*-selftest.mjs` | decided (D-2) |
| S-7 | Manual review skill step 4 convention list | decided (D-3) |
| S-8 | How the review reads `(none)` in a section | out-of-scope — nothing in the review prompt or the review skill says an empty section is not clean evidence (the rule lives in a `run.sh` comment); surfaced by the fan-out, filed separately if wanted |
| S-9 | Any section on a path holding `"`, `\` or a tab | out-of-scope — still C-quoted under `quotePath=false`; `-z` weighed and rejected in D-1; no consumer tracks one (D-9) |
| S-10 | Consumer config, schema, doctor output | out-of-scope — no config key is added (D-2) |
| S-11 | Scheduler log, tracker comment, PR run block | out-of-scope — unchanged; the sections stay inside the review input file |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Design frames

Design: none — a scheduler script change renders nothing.

## Fan-out

Refuter: cross (opus/fable alternating)
Lenses: path-encoding-surface opus 6/6 · pattern-census fable 4/6 · decision-record opus 5/6 · selftest-fidelity fable 6/6 · premortem fable 4/6
Tally: rows added 2 · snapshot claims overturned 1 · questions added 0

Checkouts: two consumer checkouts (a backend and a frontend) were handed to every lens alongside this repo.

| ID | Angle | Claim | Tag | Disposition |
| --- | --- | --- | --- | --- |
| F-1 | path-encoding-surface | `quotePath=false` fixes non-ASCII only; quote, backslash and tab paths stay quoted and dropped; only `-z` hands back raw names | already-had | D-1 residual, S-9 |
| F-2 | path-encoding-surface | The deleted/renamed awk splits on any whitespace; a deleted test with a space in its path drops out under every quoting mode | new | became part of D-1 (`-F'\t'`), D-4 guard |
| F-3 | path-encoding-surface | The CI-config section's own name-only read is quoted; `^` and `$` anchors fail on a quoted path | already-had | D-1 |
| F-4 | path-encoding-surface | `CHANGED` is a third quoted read feeding `lane_hit`; a when-scoped lane whose glob names a non-ASCII path is actually skipped; the staleness overlap reads are a fourth | new | became part of D-1 (reach widened to four reads), D-4 guard |
| F-5 | path-encoding-surface | A selftest for item 1 passes without the fix on a machine with global `core.quotePath=false` or `GIT_CONFIG_*` set | new | became part of D-4 (env pin) |
| F-6 | path-encoding-surface | No probed repo tracks a non-ASCII, space, quote or backslash path | already-had | D-9 |
| F-7 | pattern-census | Item 1 reproduces; a rename row prints both names escaped | already-had | D-1 |
| F-8 | pattern-census | Census: current pattern matches 10 of this repo's files; `\|-selftest\.` adds exactly 55, all selftests; bare `selftest` adds 3 non-test files; consumers unchanged | new | D-2 grounding (option chosen) |
| F-9 | pattern-census | Replay over #1000, #1001, #980 and eight consumer commits: widened pattern lists the modified selftests, consumer output byte-identical | new | D-2 grounding |
| F-10 | pattern-census | Moving the pattern into `awk -v` widens every alternative on BSD awk | new | became D-5 |
| F-11 | decision-record | Item 1 reproduces; `-c core.quotePath=false` keeps the `-F'\t'` parser, `-z` would rewrite it | already-had | D-1 |
| F-12 | decision-record | The ticket scopes item 1 to name-status but the CI-config and deleted-tests sections share the fault | already-had | D-1 |
| F-13 | decision-record | Option (a) keeps D-3 but the review skill's step-4 convention list needs the same clause, per the #956 D-4 / #957 D-7 precedent | overturned (snapshot D-4: "No change: review/SKILL.md names no test-path pattern") | became D-3 |
| F-14 | decision-record | Option (b) is a schema edit under `paths`, additive, no `configVersion` bump, still a `Changelog:` trailer | new | D-2 (option weighed, rejected) |
| F-15 | decision-record | Nothing the reviewer reads says how to interpret `(none)`; the rule lives in a `run.sh` comment | not material | S-8, out of scope; a separate ticket if wanted |
| F-16 | selftest-fidelity | A harness-shaped case fails on current `run.sh` and passes with `-c core.quotePath=false` on the name-status read alone | new | D-4 (case shape) |
| F-17 | selftest-fidelity | The drop is locale-independent (C.UTF-8 and C) | not material | no row; D-4 pins nothing about locale |
| F-18 | selftest-fidelity | Unicode normalization is the cross-platform hazard: macOS git writes `precomposeunicode=true` and stores NFC; the fixture and literal must be NFC | new | became part of D-4 |
| F-19 | selftest-fidelity | Neither CI nor the suite pins a locale or git version | not material | no row |
| F-20 | selftest-fidelity | Item 2 reproduces on three recent main commits; 56 `-selftest` files vs 2 `.test.` | already-had | D-2 |
| F-21 | selftest-fidelity | `-c core.quotePath=false` is a one-token change; `-z` rewrites both awk consumers; consumers have no non-ASCII paths | already-had | D-1, D-9 |
| F-22 | premortem | Quote and backslash paths remain dropped under the ticket's fix | already-had | D-1 residual, S-9 |
| F-23 | premortem | A naive NUL-to-newline `-z` conversion leaves every row one field; a rename is three records | already-had | D-1 (option rejected) |
| F-24 | premortem | The ticket's "never match" is overstated: 10 files match today (`tests/` and `.test.mjs`); `*-selftest.*` outside `tests/` never do | new | no row — D-2 unchanged; the ticket's premise holds for every cited PR |
| F-25 | premortem | Whether a Linux runner stores an NFD-written name as NFD was not measured | not material | D-4 writes NFC bytes, so the case never depends on it |

### Snapshot

    # Snapshot — #1011 (explore-first register, before the fan-out pool was read)

    | ID | Decision | Resolution |
    | --- | --- | --- |
    | D-1 | Mechanism for the non-ASCII path drop (item 1) | To ask. Options: `-c core.quotePath=false` on the three git reads in `review_input` (name-status, full diff, name-only), or `-z` with NUL parsing. Probe: `-z` emits `M\0path\0`, which breaks the `-F'\t'` awk; `quotePath=false` leaves only `"`/`\`/control-char paths quoted. The quoted form also hides a non-ASCII `.yml` from the CI-config section, so the fix covers all three reads, not just line 562 |
    | D-2 | This repo's `*-selftest.sh` / `*-selftest.mjs` never match `TEST_PATH_ERE` (item 2) | To ask. Options: add `-selftest\.` to the built-in pattern; revisit #956 D-3 (consumer-declared glob); keep and record. Grounding: across five local consumer checkouts every test file already matches the pattern (0 misses), so second-shift is the only known repo with the gap |
    | D-3 | Regression guards | run-selftest.sh cases that fail without the fix: a modified non-ASCII spec listed with its removed line in the expectations section; if D-2 widens the pattern, a modified `*-selftest.sh` listed too (CLAUDE.md: a run.sh behavior change lands with a run-selftest.sh case) |
    | D-4 | Manual review skill parallel path | No change: `plugins/dev-pipeline/skills/review/SKILL.md` names no test-path pattern |
    | D-5 | Stack-generality lint | Not a constraint: `scripts/stack-generality-lint.sh` guards `.project/` and `unit-testing` literals only, never `run.sh` |
    | D-6 | Duplicate scan | rc 0, no candidates |
    | D-7 | PR verb | `fix(dev-pipeline):` with a `Changelog:` trailer, as #956 D-5 did for the same detector widening |

    Surfaces: the three review-input sections (expectations changed, deleted/renamed test files, CI config edited) on a diff with a non-ASCII path; the two test sections on a second-shift PR that edits selftests; the review prompt that embeds them; the manual review skill; consumer config/schema/doctor (out of scope unless D-2 revisits D-3).

    Open regions: none seen. Checks: the configured test lane runs the sweep that includes run-selftest.sh. Design: none (no design.provider).
