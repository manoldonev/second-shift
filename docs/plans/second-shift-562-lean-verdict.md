# lean review verdict — #562

verdict=approve
run_id: review-562-3
session_id: c9a0e72c-b011-4ba0-b75b-ba67d77bfadb
rounds: 3
pr: #573
reviewed_head: 0ebb3c37f4f34942f2bdb6b2c85d8badd9228edc
reviewed_patch_id: 3365b601334bdff5e12002347d0dfcd5c05ce319
inherited_patch_id: 15bc6d3225819052ede27a9b223d350b00a4469a
inherited_from_verdict: 8ff8f52d98a910894daa09c677be8f6da66f3e0e
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 3 on PR 573 (#562). **approve** — zero blockers. Round 2's single blocker is discharged
completely, and the discharge is proved by mutation at both callers' real depths rather than
argued from the diff.

## Range read

`bash G delta 562` printed `8ff8f52..HEAD` — the two round-3 commits (`c17826f`, `0ebb3c3`)
across 8 files. Coverage of `a8cd2b5..8ff8f52` is inherited by reference to the round-2 record
in this same file, whose findings I read first. Read wider than the range where the delta was
misleading: the whole of `resolve-sibling.sh`, `pipeline-doctor.sh`'s prep and its `:409` call
site, `lean-gate.sh`'s `cmd_1` ledger-lint arm, `design-sync-selftest.mjs`'s mirror ladder, and
`docs/testing.md`'s cross-plugin-resolution paragraph.

## AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — milestone 1 refuses a committed spec whose `## Decision Ledger` rows carry a provenance value outside the interviewing-baseline enum, **reusing** `ledger-lint.sh` rather than re-implementing it | **satisfied** | Mechanism untouched by this round's delta and re-verified at this head: `lean-gate.sh:2961-2970` greps for the section, resolves the sibling tool through `resolve_ledger_lint()` (`:2932-2941`), shells out (`bash "$lint" "$spec"`) and calls `fail_milestone 1` on a non-zero rc. `ledger-lint.sh`'s `PROVENANCE_ENUM` remains the only carrier — no second copy of the enum anywhere on the branch. The round-3 change is *inside* `resolve_ledger_lint()`'s hop arithmetic only, and it makes the resolution strictly more correct: I ran the resolver's three rungs at this caller's real depth (below) and rung 2 now hits where it previously could not. Self-applied: `bash plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh docs/plans/second-shift-562-lean.md` → `8 ledger row(s) / OK`, so the spec this ticket ships passes the lint it introduces. |
| AC-2 — a selftest case exercises the refusal with an invented-provenance fixture and the pass with a valid one | **satisfied** | `lean-gate-selftest.sh` `(a4)` (invented `issue-specified` → rc=1 with the `provenance … not in` message) and `(a5)` (all-enum-legal → rc=0), plus `(a6)`, `(a7)`, `(a8)`. Untouched by this delta; CI's `lint-and-selftests` and the `macos, bash 3.2` job both report 69/69 suites green at this head. |
| AC-3 — distinct from #517: a spec with no `## Decision Ledger` section at all is unaffected | **satisfied** | The conditional `grep -qiE '^(#{1,6}[[:space:]]+\|\*\*)[[:space:]]*decision ledger'` at `:2961` is the discriminator; `(a6)` pins it. Untouched by this delta. |

## Round 2's blocker — discharged, and proved by mutation

The build took the review's option 1: `resolve_sibling()` derives `myver` from the
caller-supplied, already-hop-adjusted `PLUGIN_DIR` (`resolve-sibling.sh:34`) instead of re-doing
hop arithmetic on the caller's `SCRIPT_DIR`. Both callers now compute `PLUGIN_DIR`/`PLUGINS_DIR`
themselves inside sentinel-delimited blocks, and `pipeline-doctor-selftest.sh` lifts those blocks
by sentinel and writes each caller's stub **at that caller's real path inside a fabricated cache**
— so `${BASH_SOURCE[0]}` resolves at production depth and no hop constant is re-typed in the test.

I did not accept that from the diff. Six mutants against a scratchpad copy of `plugins/`, each
scored by which of the four cases reds (baseline: 40 passed, 0 failed):

| Mutant | Result | What it proves |
| --- | --- | --- |
| revert `myver` to `basename "$(cd "$SCRIPT_DIR/.." …)"` | `(rs1-gate)` reds **alone**; `(rs1-doctor)` green | the exact asymmetry round 2 found is now caught, and the one-line fix is load-bearing |
| `resolve_ledger_lint()`'s `dirname` count wrong (one, not two) | the two `-gate` cases red, both `-doctor` green | `lean-gate.sh`'s **caller prep** is covered, not just the shared function |
| `pipeline-doctor.sh`'s prep hop wrong (`../..`) | the two `-doctor` cases red, both `-gate` green | the other caller's prep is covered, and the two are independently discriminated |
| `sort -t. -k1,1nr…` → lexical `sort -r` | both `(rs3-*)` red | rung 3's descending sort keeps its killer, now at both depths |
| `# >>> ledger-lint-resolver` sentinel removed | the block reds (`36 passed, 1 failed`) | the guard fails **closed** on a refactor that moves a caller's prep, rather than silently skipping |

That is the asymmetry, not merely "something reds" — which is what makes it evidence that each
caller is covered rather than that the function is.

**Each of round 2's five false-parity claims is now true.** `resolve-sibling.sh:5-22` (header
rewritten, names `PLUGIN_DIR`/`PLUGINS_DIR`, with a new paragraph on why the ladder must not
re-derive a depth); `lean-gate.sh:2917-2926` ("bears only on the three lines below"); the
`(rs)` comment's "a single case here covers both" — deleted, replaced by four cases; spec D-6,
amended to say outright that its "no new fixture needed" half was wrong; the Tests section,
rewritten. The `lockstep-manifest.tsv` residual paragraph was updated in the same direction.

Also worth recording: this change brings the bash ladder **into** step with its `.mjs` mirror
rather than out of it — `design-sync-selftest.mjs:54` computes `MY_VERSION = basename(join(HERE,
'..'))`, i.e. the plugin root's basename, which is exactly what `basename "$PLUGIN_DIR"` now is.
The manifest's DROPPED entry says "keep the two ladders in step"; they are more in step than
before.

## The baseline shrink is justified — three independent confirmations

Removing a baseline row is the direction that can red a lane, so it needs an environment-free
argument rather than a local advisory sweep. It has one, and I confirmed it three ways:

1. **`pipeline-doctor-selftest.sh` never executes `pipeline-doctor.sh`.** All 23 `$DOCTOR`
   references are `sed -n '/# >>> …/,/# <<< …/p'` lifts plus one `[[ -f ]]` existence check — the
   suite is lift-and-run, never invoke. The `# >>> plugin-dirs` block was not among the lifted
   blocks at base, so those lines were genuinely never executed by this suite and it could not
   have killed them. The spec's claim is literally true, not loose.
2. **Hand-applied mutants.** `&&` → `||` (the `logic` operator's own edit) on each of the three
   `cd … && pwd` lines in the block reds `(rs1-doctor)` and `(rs3-doctor)` — including the third
   line, which sits past `K_BUDGET=2` and so is not baselined either way.
3. **CI's own sweep at this head.** `mutation-sweep-pr` green, 13 verdicts computed:
   `pipeline-doctor.sh applied=10 killed=4 survived=6` with survivor ids exactly
   `cmp-z::1,2 · detector::1,2 · default::1,2` — the six rows that remain, and no others.
   `resolve-sibling.sh applied=2 killed=2 survived=0`, and it carries no baseline rows.

## Ordinal accounting — the round's, and discharged

`lean-gate.sh` graded `deferred-to-nightly (0 0 0)`, so its ordinals are this round's to settle.
Settled by enumeration rather than by assumption: for each row of `tools/mutation-operators.tsv`,
`grep -nE --` at base and at head, comparing the first three matched **source lines** (not line
numbers).

- `lean-gate.sh` — all six operators byte-identical, site counts unchanged (fail-open 0, cmp-eq 40,
  cmp-z 146, logic 280, detector 16, default 57). Its three baselined rows (`cmp-eq::1`,
  `default::1`, `default::2`) keep their numbers. No re-baseline owed.
- `pipeline-doctor.sh` — all six operators byte-identical, counts unchanged. The two removed rows
  are a **verdict** flip, not a re-key, exactly as the spec claims.
- `resolve-sibling.sh` — `logic` sites 5 → 4 (the `myver` line lost its `&&`). Ordinals 1–2 are
  byte-identical either side, the guard carries no baseline rows, and CI killed both. Nothing owed.

No `tools/mutation-catalog.tsv` row and no `lockstep-manifest.tsv` TSV row anchors into the moved
block; `scripts/check-lockstep-pairs.sh` → 22 pairs checked, 0 failed.

## Independent verification run this round

- `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh` — clean.
- `pipeline-doctor-selftest.sh` at head — 40 passed, 0 failed.
- **`tools/install-topology-selftest.sh` at this head — `54 ran, 54 passed, 0 known-red, 2 skipped,
  0 stale row(s), 0 red`.** This one was not optional: `pipeline-doctor-selftest.sh` now reads a
  file under `skills/build-lean/` from `tools/`, a layout-sensitive cross-tier read, and that guard
  is nightly-only, so a break would otherwise surface a day after merge.
- CI at `0ebb3c3`: `lint-and-selftests` ✓, `mutation-sweep-pr` ✓, `selftests (macos, bash 3.2)` ✓.
  `pr-gates` ✗ is the round-2-record arm naming its own reason — `verdict record … reads
  'verdict=needs-work', not 'verdict=approve'` — and clears when this record lands. Not a finding.

## Findings

| # | Finding | Class |
| --- | --- | --- |
| 1 | `pipeline-doctor.sh:39`'s pointer comment still names `SCRIPT_DIR/PLUGINS_DIR` as the caller-kept globals — the sixth artifact of the class round 2 flagged, and the one the sweep missed | warning |
| 2 | `docs/testing.md:262` still calls `resolve_sibling()` "in `pipeline-doctor.sh`" — stale since round 2 moved it to `resolve-sibling.sh` | nit |
| 3 | Rung 1 has no cache-fixture case at either depth (panel, conf 82) — pre-existing, and rung 1 has no depth-dependent arithmetic to hide a bug in | nit |

### Warning 1 — one stale variable name in a pointer comment

`pipeline-doctor.sh:37-41` reads "see that file's header for why the caller keeps its own
**SCRIPT_DIR/PLUGINS_DIR** hop count and only the ladder itself is shared." The contract is now
`PLUGIN_DIR`/`PLUGINS_DIR` — `SCRIPT_DIR` is a local step, not something the ladder reads. The
four other artifacts round 2 named were all corrected; this sixth one, seven lines below the
edited block, was not.

Not a blocker, and I want the reasoning on the record rather than implied. Round 2's blocker was
that artifacts asserted a **behavioral parity that was false** — the two callers genuinely
diverged on identical cache state. Here the behavior is correct and proved above; what is wrong is
one variable name in a comment that immediately defers to `resolve-sibling.sh`'s header, and that
header is correct and now carries a dedicated paragraph on exactly this point. The failure mode is
an author of a third caller reading the stale pointer instead of the authority it points at — and
under `set -u` that fails loudly at the first `resolve_sibling` call with an unbound `PLUGIN_DIR`,
never silently. A one-word fix; worth taking on the next commit that touches this file, not worth
a round.

## Panel

7 selected, 6 usable. `security` (opus), `performance`, `maintainability`, `complexity`,
`scope-completeness` (opus) and `unit-test-mutation` all returned **approve** with no blockers.
Scope-completeness PASS with all three ACs `in-diff` — it correctly noticed the dispatched base is
an intra-branch commit and re-judged against the true merge-base `a8cd2b5` (11 files, +563 −58),
which is the right instinct on an inheriting round and is why its PASS is worth more than the
range it was handed.

`unit-test-mutation-reviewer` reached the fix, the fixture and the baseline shrink independently of
me and by tracing rather than reading, and its conclusions match mine on all three at conf 85–92.

**[Coverage gap] `test-coverage-reviewer` went dark** — `died-after-retry`, `turn-budget: agent
emitted no text on either attempt (maxTurns cap reached mid-exploration)`. Its domain — whether the
new cases adequately cover the changed surface — is the one most central to this delta, so I am
naming the gap rather than letting six approvals paper over it. Mitigation, stated so the record is
honest about what replaced it: `unit-test-mutation-reviewer` covers the adjacent domain and did
reach a per-case load-bearingness judgement, and the round's own six-mutant battery, the ordinal
enumeration, the install-topology run and CI's sweep are direct evidence on the same question. That
is not identical coverage, and merge readiness here is assessed without a test-coverage reviewer.
(Cf. the known `intake-fanout-no-emit-deadline` class: the fix is an emit deadline, not a bigger
`maxTurns`.)

`a11y-reviewer` and the design-fidelity dimension were **not routed**: no changed path matched
`stageParams.webComponentGlobs`, which is unset and resolves to the default
`apps/web/**/*.{tsx,jsx}` — a pure-shell diff. Not a coverage gap.

## Design fidelity

`not-applicable`. The spec's `## Design` section reads `Design: none — a shell-script gate change
with no UI surface; design.provider is unset in this repo's config`, and the disarm is justified
rather than taken on the spec's word: `jq '.design' .claude/second-shift.config.json` → `null`, so
this repo configures no design provider and the disarm cannot be the one the merge boundary
cannot see.

## Verdict

**approve.** All three `AC-n` satisfied. Round 2's blocker is discharged at the mechanism, not at
the claim, and the fix carries the killer the rung had never had — at both callers' real depths,
which is the specific thing the previous fixture could not do. The baseline shrink, the direction
that can red a lane, has an environment-free argument and three independent confirmations. The one
warning is a stale variable name in a comment that defers to a correct authority; it costs nothing
to leave for the next commit and is not worth a fourth round.
