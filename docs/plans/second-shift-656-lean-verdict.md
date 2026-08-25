# lean review verdict — #656

verdict=approve
run_id: review-656-4
session_id: 2ebca176-c333-4b3b-abc5-d116ea81dad7
rounds: 4
pr: #681
reviewed_head: 83aa9b9f26bd8c93689d0278fe38a2a983b9ec39
reviewed_patch_id: a77d34b15785b841b68f3a301b620059414f83e4
inherited_patch_id: 4a5d6ea102c11c18dc27aabfaa181b5c4b5b980f
inherited_from_verdict: f8f19812f32e9969913fdfed6dbc78be4da36462
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 4, delta range `f8f19812..HEAD` (one commit, `83aa9b9f`), inheriting patch `4a5d6ea102c1`
(round 3). Four files: `CLAUDE.md`, `docs/testing.md`, `docs/plans/second-shift-656-lean.md`,
`tools/reap-lean-fixtures.sh`. Rounds 1–3 findings were read first.

**Verdict: approve.** Both round-3 blockers are fixed, and each fix was re-derived here rather
than read off the diff. Every factual claim the delta introduces was executed — the counts, the
structural claim, the citation target, the line-count invariant behind `--help` — and all of them
reproduce exactly. No blockers.

The shape of the fix is the notable part. R3/B-1 was a compound finding whose two halves cost
very different amounts to answer, and the build split them correctly: the *structural* half
(`BASE` is a sibling, not a parent) was settled by reading the worker branch, and the *size*
superlative was **deleted rather than re-derived** — the paragraph's argument (the honored form
is widely used) never rested on which directory is biggest, so dropping the clause discharges
AC-4's derivation obligation instead of creating one. R3/B-2's count was re-derived from the
matched lines rather than from a `-l`, and corrected on all four surfaces it had reached,
including the ledger row that decided it.

## Blockers

None.

## Warnings

**W-1 — the line-range citation `tools/run-selftests.sh:127-170` overshoots the worker branch by
four lines, and it came from the round-3 review record.**

The `--run-one` branch opens at `:127` and closes at its `fi` on **`:166`**; `:167-170` is blank
plus the head of the option parser (`while [[ $# -gt 0 ]]; do`). The cited range fully contains
the block a reader is being sent to, so nothing is false and nobody is misrouted — this is a nit,
not a finding against the prose.

It is worth naming only because of where the number came from: the round-3 verdict record wrote
`:127-170` in its own B-1, and the build adopted it into `docs/testing.md` and into ledger row
D-12. That is the identical mechanism as this ticket's round-3 blocker, where the round-2 record's
`14` became a shipped doc claim — a figure the review role puts in circulation gets treated as
derived. The build re-derived the *count* it was handed this round and did not re-derive the
*range*. Tightening `170` to `166` is a one-character-class edit whenever this file is next
touched; it does not justify a round on its own.

## Also verified (no findings)

- **The counts reproduce exactly, all three of them.** `grep -rl 'TMPDIR:-/tmp}/' --include='*.sh' .`
  → **14** files; the lines behind that `-l` → **18**; stripping comment matches → **16 sites in
  12 files**. The two files the prose puts on the *ignored* side are exactly the two that fall
  out of `comm -23` between the `-l` set and the call-site set: `tools/mutation-sweep.sh:1359`
  and `plugins/intake-toolkit/hooks/exitplan-ledger-gate-selftest.sh:121`. Both do allocate with
  `-t` themselves, as claimed — `mutation-sweep.sh` at `:828`, `:1261`, `:1326`, `:1809`, and the
  ledger-gate selftest at `:42`. Run through a `bash` script file, not the harness shell, because
  `grep --include` returns 0 under zsh.
- **`CLAUDE.md`'s derived figure is arithmetically consistent with it**: 12 callers minus the
  sweep runner = "eleven other scripts", on a basis the prose now names (scripts, not "callers").
  `docs/testing.md`'s "the other eleven scripts' scratch" is the stronger claim of the two and it
  also holds: every `mktemp` in all eleven — listed exhaustively, comments stripped — uses the
  honored explicit-template form and nothing else, so a private `TMPDIR` moves all of their
  scratch and not merely some of it. No over-generalization this round.
- **The sibling claim is confirmed twice, structurally and live.** `tools/run-selftests.sh:87`
  sets `ROOT="$(dirname "$HERE")"` (the repo root), and the worker runs
  `( cd "$W_ROOT" && env -u RUN_SELFTESTS_DROP_LAST -u RUN_SELFTESTS_DROP_RC -u
  LEAN_SELFTEST_CACHE_DIR bash "$W_SUITE" ) > "$W_OUT/$W_IDX.log"` — `TMPDIR` is not among the
  three stripped vars, so a suite allocates against the ambient value and lands beside `BASE`,
  not under it. Sampled during the live AC-6 sweep: `BASE` held exactly `worklist`,
  `cache-inputs`, `cache-manifest`, `cache-suites`, `cache-suites.u`, `dispatch`, `hits`,
  `results` — i.e. precisely "its worklist and cache bookkeeping plus each suite's captured
  `log`/`rc`/`secs`" — and `find` over it matched no `leangate.*` or
  `orchestrate-lean-selftest.*` at any depth.
- **The size superlative is gone from every surface.** `grep` for `largest` / `parent of every` /
  `thirteen` / `fourteen` across `CLAUDE.md`, `docs/testing.md`, `tools/reap-lean-fixtures.sh` and
  the spec returns only D-12's quotation of the refuted claim, which is correct usage. The single
  surviving `14` is the accurate `-l` count.
- **AC-7's round-3 warning (W-1) is discharged.** `tools/reap-lean-fixtures.sh:9` now cites
  `docs/testing.md#when-a-run-is-killed-mid-sweep` directly instead of forwarding through
  `CLAUDE.md`. The anchor resolves — `### When a run is killed mid-sweep` at `docs/testing.md:163`
  — and that section does carry the derivation the header promises. The header remains internally
  coherent: `-t` resolves against `_CS_DARWIN_USER_TEMP_DIR`, and its own `${TMPDIR:-/tmp}` default
  reaches those fixtures only because launchd exports `TMPDIR` already set to that directory.
- **The `--help` invariant D-13 leans on is real and holds.** The file is 201 lines before and
  after, so `sed -n '2,55p' "$0"` still stops inside the header. `reap-lean-fixtures-selftest.sh:294-297`
  asserts rc=0, the presence of the usage line, and the *absence* of `^set -uo pipefail` — none of
  which a same-line-count comment edit can move.
- **The enumeration command re-run verbatim** from the reviewed checkout returns
  `/var/folders/…/T/gitkraken/gitlens/agents` — a real match with no `.claude-plugin/plugin.json`
  beside it, which is the harmless vendor case the runbook names. Read-only (`ls -d`, and the
  `mktemp -u -d` inside it creates nothing).
- **The spec amendment is legitimate.** D-10 was corrected in place and D-12/D-13 added; **no
  `AC-n` was edited this round**. The ledger records a re-derivation in response to review
  findings, which is the opposite of a spec bent to match the diff. D-12 additionally names where
  the bad `14` originated (the round-2 record's own B-1), which is the right disclosure.
- `bash scripts/check-guard-budget.sh origin/main` → base 51793, HEAD 51793, **delta 0**,
  reproduced at `83aa9b9f` after the `tools/reap-lean-fixtures.sh` header edit. That file matches
  no arm of the guard predicate, exactly as D-11 predicted.
- `bash scripts/check-lockstep-pairs.sh` → 29 anchors, 0 failed. The split-by-role decision (D-1)
  still owes no anchor: the two sites do not restate each other.
- `bash scripts/check-frozen-files.sh origin/main` → clean, no release-owned file touched.
- **CI at `83aa9b9f`**: `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass,
  `mutation-sweep-pr` pass. `pr-gates` red, and read from its own log rather than assumed: both
  arms name only `verdict=needs-work` in `docs/plans/second-shift-656-lean-verdict.md`
  (`lean-evidence` 1 artifact, `lean-chain` 2, the latter explicitly declining to evaluate the
  freshness arms because freshness is undefined for a non-approve record). No other gate fails.
  This record is what clears it.

## Per-AC scoring

| AC | verdict | basis |
| --- | --- | --- |
| AC-1 | satisfied | All three required elements sit under the recipe fence in `CLAUDE.md`, not behind a link: the 2-minute foreground reap and that `timeout` does not lift it (600000ms still SIGKILLed at 2m 0s); `nohup <cmd> > <log> 2>&1` under `run_in_background` as the shape that survives and is collected in the same turn, with a bare backgrounded command explicitly excluded; and the scrub obligation routed to the runbook anchor, which resolves. The `lean-gate.sh 3` exception is named. The only line this delta touches here is the count, corrected to "eleven other scripts"; the rest is inherited from rounds 1–3, which measured it first-hand. Dogfooded again this round: the AC-6 sweep was run through exactly this shape. |
| AC-2 | satisfied | All six elements hold and were re-run at this head. The *why `TMPDIR` cannot isolate the litter* element — where rounds 2 and 3 both landed — is now correct in both halves: the two-family split is right, and the worked example beside it (`BASE`) is characterized accurately as the runner's own bookkeeping and a sibling of the fixture dirs, confirmed both by reading `:127-166` and by sampling the live sweep. The reaper-clears mechanism is correct and dated; the enumeration is read-only and returns a real match; the `stat`-before-delete check is present and correctly motivated by a concurrent lane's live fixtures. |
| AC-3 | satisfied | `bash scripts/check-guard-budget.sh origin/main` at `83aa9b9f`: base 51793, HEAD 51793, **delta 0**. No new gate, no new script. No `Guard-mass:` trailer owed, and none present. |
| AC-4 | satisfied | The one measurement that carried neither a derivation nor a date — "the single largest thing a killed run strands" — is **deleted**, which is the correct discharge: the claim was load-bearing for nothing. Every surviving measurement carries a runnable derivation that reproduces here (the `grep -rl` → 14, the 18 matched lines → 16 sites in 12 files with the two comment-only files named by path, the five-line `mktemp` form block, the two-line reaper-reach block) or a stated measurement date. The second half is met unchanged: no sentence asserts a currently-fixed defect as live, and the emit-deadline live-scan case is still described by mechanism without being named. |
| AC-5 | satisfied | `Changelog: none` on all eight branch commits. No `plugins/**` file changed, so `check-changelog-trailer.sh` does not require one regardless. |
| AC-6 | satisfied | Re-run **cold** at the reviewed head `83aa9b9f`, in the reviewed checkout, via the shape this PR documents: `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh` → `summary: 75 scored, 75 run, 0 served from cache, 0 failed`. Byte-identical to the PR body's claim, and `0 served from cache` confirms the run was cold. 76 discovered, 1 excluded. |
| AC-7 | satisfied | `tools/reap-lean-fixtures.sh`'s header no longer contradicts the note it cites, and as of this round no longer forwards through it either — round 3's W-1 is discharged by naming `docs/testing.md#when-a-run-is-killed-mid-sweep` directly, an anchor verified to resolve. Header comment only, same line count, `--help` contract intact and independently asserted by the file's own selftest. Guard mass still 0. |

## Deviation to record

The reviewer panel was not fanned out this round, as in rounds 1–3: this session runs under a
standing operator instruction not to dispatch subagents or workflows unasked, which is in tension
with review-lean step 5 naming `review-lead` as the implementation. The review is first-hand — the
delta was read in full and every factual claim in it was executed, including three independent
count derivations, an exhaustive `mktemp`-form audit of the eleven scripts the prose generalizes
over, a live-sweep sample of `BASE`'s contents and nesting, and a full cold 75-suite sweep. That
mode found both blockers in each of rounds 2 and 3; this round it found none, which is the first
round of this ticket where executing the delta's claims turned up nothing to fix.
