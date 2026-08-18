# lean review verdict — #563

verdict=approve
run_id: review-563-1
session_id: be9255fe-8c6a-4c20-9139-730953df2fd0
rounds: 1
pr: #586
reviewed_head: 08c6edd6fa42ca414bbd0c295796db2889b294bd
reviewed_patch_id: 7e47e08ce7a2b7647707320ca47fdc7bdb621513
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

## Round 1 — approve

Range read: the whole branch diff (`a30c29b..08c6edd`, 8 files) — `lean-gate.sh delta 563`
printed FULL, nothing verifiable to inherit. Root round, no prior findings to carry.

`review-lead` panel: security, performance, maintainability, complexity, test-coverage,
scope-completeness — six selected, six returned, none dark. All six returned `approve`; the
only non-suppressed finding was the scope reviewer's nit on the issue footer's net-bash-delta
expectation, kept below as a nit for the same reason it raised it.

### What I verified myself, rather than taking from the PR body

| Claim under test | How it was settled | Result |
| --- | --- | --- |
| every operator's k=2 window on `lean-gate.sh` is byte-identical | replayed all 6 `tools/mutation-operators.tsv` regexes against `git show a30c29b:` vs head, byte-comparing the first two matched **lines** | holds — 6/6 identical |
| on `tools/run-selftests.sh` one `cmp-eq` window moved, and the new site is **killed** | same replay confirms only ordinal 2 moved (to `[[ "$CACHE_FROM_ENV" -eq 1 ]]`); then applied the operator's own `-eq`→`-ne` flip in an isolated worktree and ran the paired suite | holds — mutant reds **both** halves of the asymmetry case (`rc=2` where cold was required; `rc=0` where 2 was required) |
| no baseline re-key is owed | `tools/mutation-baseline.tsv` carries **no** active row for `tools/run-selftests.sh` (only a comment block explaining a #448-era drop); the displaced ex-ordinal-2 held no row | holds |
| `lean-gate-selftest.sh` (sc1–sc3) is green at this head | ran the full suite from the reviewed checkout, `< /dev/null` | 442 cases, all green |
| `sc1` is not vacuous — it actually pins the **export**, not inheritance | removed the export line (`SEAM_SCRUB_ENV+=("LEAN_SELFTEST_CACHE_DIR=$store")` → `:`) in a throwaway worktree at the same head and re-ran the full gate suite | holds — **`sc1` alone reds** (`child='unset'`), `sc2` and `sc3` still pass, which is precisely the PR body's mutant-table row and the reason `sc2` was rewritten onto the announcement |
| the gate-side assertion generalizes from an extraLane to the real `test` key | read all four milestone-3 spawn sites (`:3937`, `:4039`, `:4051`, `:4132`) — every one goes through the same `env ${SEAM_SCRUB_ENV[@]…}`, and `lane_apply_selftest_cache` (`:4008`) precedes all four, `cmd_3_render` being called at `:4142` | holds |
| the runner suite is not perturbed by an **ambient** store (the shape the gate now creates) | ran `run-selftests-selftest.sh` twice against one injected store, from a checkout with the variable set | green both runs; the 7 pre-existing unscrubbed direct-`$RUNNER` cases are unaffected |
| the spec was not amended to match the diff | `git show 08c6edd -- docs/plans/second-shift-563-lean.md` | amended mid-run, and **strengthened**: "suppresses the export" → "scrubs", and AC-3's gate clause gains a third, strictly harder case. AC-3's original sentence (a child must report the announced store) survives intact as `sc1`. Not the weakening the rule bans. |
| release artifacts untouched, `Closes #563` live | diff name-list; `closingIssuesReferences` | clean; the issue is linked |

### Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | warning | `docs/testing.md:141` | Property **3** ("Recording takes a second flag. `--cache-dir` reads; only `--cache-write` records") is now path-dependent and still reads as universal. The same PR corrected property **1** in place for the identical reason, and the new lean section 20 lines below states the departure plainly ("It records without a second flag"), so a reader who continues gets the truth — but the four-property list is introduced as the containment contract "all asserted in `tools/run-selftests-selftest.sh`", and that suite now asserts the *negation* of property 3 on the env path (`cache: 0 served, 1 recorded` with no `--cache-write`). A clause on property 3 pointing at the lean row would close it. Not a blocker: AC-4 names property 1 and the CLAUDE.md sentence specifically, and both are corrected. |
| 2 | nit | issue #563 footer | "Net bash delta expected ≈ 0 or negative (2026-08-16 deletion directive)" is not met: +29 non-comment shell lines across the two production scripts (+94 counting the comment blocks), no offsetting deletion. The spec's Notes declare this openly as "a small positive … honest for 'wires an existing mechanism'", and the ~29 figure is close to the "~20 lines of wiring" it claims. The footer sentence is hedged metadata beside `Provenance:`, not a labeled AC, so it does not gate — raised so the doctrine expectation is visibly reconciled rather than silently dropped. |
| 3 | nit | `lean-gate.sh:1756` | `[ -n "$store" ] || return 0` is unreachable — the preceding default expression cannot expand to empty (with `HOME` unset under `set -uo pipefail` it errors rather than yielding empty). Harmless; the `$HOME` dependence itself is `tools/mutation-sweep.sh:206`'s established idiom, not a new gap. |

### AC scoring (against the committed spec, `docs/plans/second-shift-563-lean.md`)

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — close-out path runs with the cache active, rowed suites served | **satisfied** | Gate: `lane_apply_selftest_cache` (`:1737-1760`) appends `LEAN_SELFTEST_CACHE_DIR=$store` to `SEAM_SCRUB_ENV` at `cmd_3:4008`, ahead of all four child-spawn sites. Runner: env intake at `tools/run-selftests.sh:227-249`. Guarded on both sides (`sc1`; `#563/AC-1` case). Reproduced independently: two runs against one injected store went `0 served, 1 recorded` → `1 served`, with the un-rowed neighbour still running. |
| AC-2 — first evaluation cold; #448's contract unwidened | **satisfied** | `tools/selftest-cache-inputs.tsv` is not in the diff. Argv precedence asserted on the **stores** (marker lands in the flag's, the env's stays empty), unset-is-a-no-op asserted against a *hot* store, declared-input edit re-runs with the fixture made red in the same edit. No head-based branch exists anywhere in the gate — the AC-1/AC-2 split falls out of #448's content-addressed key. The scope reviewer's suppressed reading (a rowed suite whose inputs did not move is served even on a moved head) is the AC's own dash-clause and the pre-existing CI contract, not a deviation. |
| AC-3 — behavioral guards on both sides | **satisfied** | Runner: all six enumerated clauses present and green, and the worker scrub carries its own control proving the probe can see the variable at all. Gate: `sc1` pins the export against a **default** store the environment does not carry (so inheritance cannot deliver it); `sc2` pins the override on the announcement; `sc3` runs the disarm in an environment that already carries a store. Full suite green at this head, and the new runner site is a confirmed kill. |
| AC-4 — `docs/testing.md` + CLAUDE.md corrected | **satisfied** | The lean lane is documented as the third participant with all three departures, the seam name, the recording-trust argument, the off switch, the default store and the worker scrub; property 1 and CLAUDE.md's "never participates without that flag" are both corrected. Finding 1 is the residual within this AC's neighbourhood, not a failure of it. |

Design fidelity: **not-applicable** — the spec disarms with `Design: none` and the disarm holds:
this repo's config declares no `design.provider`, and the diff touches no route, template or
rendered surface (two shell scripts, two selftests, three docs and a manifest comment).

CI at review time: `lint-and-selftests`, `selftests (macos, bash 3.2)` and `mutation-sweep-pr`
green; `pr-gates` red **only** on `lean-chain`'s missing verdict record — the artifact this
round produces.

**Verdict: approve.** Neither finding is a blocker. Finding 1 is a one-clause doc edit worth
folding into whichever PR next touches that section.
