# lean review verdict — #566

verdict=needs-work
run_id: review-566-1
session_id: 70159955-3222-4714-935c-31227a8d91eb
rounds: 1
pr: #621
reviewed_head: 40cfd26d0cf0a5a8fab6d9ccaa7fb860bc94da51
reviewed_patch_id: fae4fa7dfb8499c182ce16ea5341e9ac6ead8920
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

## Verdict: needs-work — round 1

12/12 AC satisfied against the committed spec, one blocker outside the AC set.

The deletion itself is clean and unusually well evidenced. Milestone 3 is an ordinary inline
milestone again, the replacement bound is a committed measurement rather than a judgment, and
every claim in the PR body that I could re-derive, re-derived. The blocker is not in the
mechanism — it is prose the deletion left standing in the shipped gate's canonical env-var
register, where it now describes a **live** variable with statements that are false and points at
machinery this very PR retired. Nothing in the repo can catch that: CLAUDE.md forbids
prose-presence guards, so the round is the only net, which is exactly the class review-lean is
told to hold.

### Blocker

**B-1 — `lean-gate.sh:245-250`: the deleted `LEAN_GATE_WAIT_CEILING_SECS` entry left its tail
behind, and it is now read as part of `LEAN_GATE_OBSERVE=1`.**

At the base (`80276e7:lean-gate.sh:234-251`) the register held two adjacent entries. The diff
deletes the `LEAN_GATE_WAIT_CEILING_SECS` header line, its `#511 D-4` sentences, and the line
`NOT IN \`SEAM_SCRUB\`, exactly like LEAN_GATE_OBSERVE beside it, so` — but keeps the six
continuation lines that followed. With no header of their own they merge into the preceding
`LEAN_GATE_OBSERVE=1` entry, which now reads:

```
#   LEAN_GATE_OBSERVE=1      #496: EVALUATE WITHOUT RECORDING. ...
#                            milestone 3's lane children INHERIT it — and in this repo those
#                            children are lean-gate.sh. An operator who exports a short ceiling to
#                            debug gets spurious `rc=7` out of the nested suite's own milestone-3
#                            calls. Export it for one call rather than for a shell. The register
#                            is a `subset-of` lockstep row against preflight.sh (which carries
#                            the superset) and is not widenable from this side alone.
```

Three defects, one edit:

1. **Affirmatively false statements about a live variable.** `LEAN_GATE_OBSERVE` has no ceiling
   to export short, produces no `rc=7`, and has no "lane children" — this PR deleted the last
   thing that spawned any. A reader of the register (`--help` prints lines `2,271p`, which
   includes all six) is told retired supervision is live. That is the class AC-2 exists to
   remove, surviving in the one place AC-2's token list does not reach.
2. **A true statement was deleted with it.** `LEAN_GATE_OBSERVE`'s own `NOT IN \`SEAM_SCRUB\``
   declaration went out on the deleted line. That fact is load-bearing — not being scrubbed is
   what lets a child inherit observe mode — and `scripts/check-lockstep-pairs.sh` carries a live
   `subset-of` row (`preflight.sh ⊇ lean-gate.sh`, verified PASS) whose lean-gate side this
   register is.
3. **An off-by-one it created two entries down.** `lean-gate.sh:269` still reads
   `NOT IN \`SEAM_SCRUB\`, exactly like the two seams above.` At the base there were two such
   declarations above it; the diff removed both (one with the header, one as the
   `exactly like LEAN_GATE_OBSERVE beside it` line), so the phrase now has zero antecedents.

Remedy: drop the six orphaned lines, restore `NOT IN \`SEAM_SCRUB\`` (plus the `subset-of`
sentence, which is about the register and still true) to the `LEAN_GATE_OBSERVE` entry, and
re-derive `:269`'s count. Confirm `--help`'s `sed -n '2,271p'` range still ends on the last header
line afterwards — `awk 'NR>1 && !/^#/ && !/^$/ {print NR; exit}'` currently answers 272, so the
range is exact and any line count change moves it.

### Warnings

**W-1 — the ticket body's ACs were never amended; only the spec and an intake comment were.**
The scope gate blocked on this, and it is factually right: `gh issue view 566` (body,
updatedAt 2026-08-20T19:44:51Z) still carries `AC-1: ... the sweep invocation carries the
table-derived --exclude set`, `AC-5: scripts/check-lean-chain.sh and .github/workflows/* carry no
diff`, and Scope-In bullet 2's "from which the gate builds the --exclude list up front". The diff
satisfies none of those literally — the bound is repo-side and the workflows carry a 4-site
`--full` diff.

Not a blocker, on the standing rule that a `user-answered` pre-flight ledger row overrides the
issue's ACs and that the committed spec is the definition of done. Both deviations are covered
exactly: ledger **D-1** (`user-answered`) names the repo-side relocation and says AC-1/AC-4 are
amended; **D-5** (`user-answered`) names default-on activation, the four `--full` sites by file
and count, and says AC-5 narrows. Both rows are carried in the committed spec, and the amendments
were also posted publicly to the ticket before the build
([comment 5360677504](https://github.com/manoldonev/second-shift/issues/566#issuecomment-5360677504),
2026-08-20T19:27:22Z, which states in as many words that `.github/workflows/*` **does** carry the
4-site diff). Provenance is clean: `git show b8487fa:docs/plans/second-shift-566-lean.md` — the
first spec commit, two commits before the implementation — already carries every amended and new
AC, so none of this is a spec retrofitted to match a diff.

Still worth closing: the ticket body is what a future reader and the next scope gate read. Amend
AC-1, AC-5 and Scope-In bullet 2 in the issue body. That is a human-authority edit, so it is not
a code remedy and does not gate this round.

**W-2 — AC-2's grep predicate is grazed.** 22 of the 23 named identifiers have zero matches
anywhere outside `CHANGELOG.md` and `docs/plans/**`. `INTERRUPTED_BUDGET_M3` has three, all
comments narrating the retirement: `docs/testing.md:60`, `lean-gate-selftest.sh:1226`, and
`tools/selftest-slow-suites.tsv:5`. AC-2's own wording excludes "selftests" and "the register
TSVs", so two of the three trip it literally. No executable path references it and the variable
itself is gone, so I score AC-2 satisfied on its mechanism — but the AC would have needed a
comment carve-out to be greppable as written, and someone will grep it.

**W-3 — `lean-gate.sh:4404`, a stale comment this PR falsified.** Directly above
`budget="$INTERRUPTED_BUDGET"` sits `# #527 D-7: milestone 3's own, larger bound. Resolved once,
here, ...`. The diff is what retired that bound — `interrupted_budget_for()` is gone and
`(ib2)` now asserts the opposite in the suite. Same class as B-1, one severity down because
nothing about it is affirmatively misleading beyond the first clause.

**W-4 — `tools/run-selftests.sh:239-240`, a sentence broken by the deletion.** Removing
`LEAN_JOB_CEILING (#526).` mid-sentence leaves `... exactly as it already hands down` followed by
`# This is the reading end of that coupling.` — no object, and the surviving example is now the
one the sentence was contrasting against.

**W-5 — `docs/testing.md:14` did not get `--full`, and the surrounding prose still promises a
full sweep.** AC-11 required the `--exclude` caller count and the milestone-3 description be
re-derived; both were, and the new slow-suite section is good. But the file's own headline recipe
under **How the sweep runs** — "One script owns it, locally and in CI:
`SKIP_STRESS=1 bash tools/run-selftests.sh`" — is now the bounded check, while the next paragraph
says it "discovers every `*-selftest.sh` under the repo, runs `SELFTEST_JOBS` at a time". Its
own caller table three sections down lists four `--full` passers and does not include this line.
CLAUDE.md's mandated recipe was updated, so the operator following the mandated path is fine;
the one following the testing doc is not told.

**W-6 — the prose-budget re-baseline is half done.** `lean-gate.sh` (4972→4672) and
`run-selftests.sh` (581→680) were updated and the two `lane-registry` rows deleted, but
`lean-gate-selftest.sh` (baseline 6535, now 6243) and `scenario-liveness-selftest.sh`
(baseline 2954, now 2175) kept their old ceilings after losing 903 and 779 lines. The ratchet only
fails on growth, so nothing reds — it just hands those two files ~1,070 lines of free prose
headroom in the same diff that shrank them. Consistent with a hand-edit of the affected rows
rather than `--update-baseline`; the fix is to hand-edit the other two the same way.

### Suggestions

**S-1 — `tools/mutation-slow-suites.tsv` gains `mutation-sweep-selftest.sh` (135s), and that
defers `tools/mutation-sweep.sh`'s own guards in the PR lane from here on.** It is the right
call — `mutation-sweep.sh:1965` warns for exactly this missing row, so the row closes a
pre-existing gap rather than opening one — and the blast radius is small (that file has 0
`mutation-catalog.tsv` rows, so only generic mutants defer). But it is outside every AC and it is
the same mechanism that made this PR's own `mutation-sweep-pr` job a zero-verdict green. Worth a
line in the PR body.

**S-2 — the base moved twice under the branch and merges clean, but note one consequence.**
`origin/main` is `9c7416a` (#615) via `f51f7d8` (v10.0.1); the branch forked at `80276e7` and does
not contain either. #615's `lean-gate.sh` hunk is a comment plus `LOCKSTEP-BEGIN/END
lean-session-set` markers around `build_session_set` at ~:1429, a region this branch never
touches (its diff mentions no `build_session_set`, `session_in_build_set` or `LOCKSTEP` line), and
its `SKILL.md` edit is steps 7/9 against this branch's 37/41. PR reads MERGEABLE. #615 also adds
`plugins/dev-pipeline/tools/cost-block-selftest.sh`, a suite that postdates the 2026-08-20 census
and so has no row in the new table — "absent = fast" is the safe default, so no action, but the
67-suite measurement is one suite stale the moment this lands.

### Strengths

- **The intake amendments are the reason this PR is coherent.** Four defects in the ticket were
  found and resolved *before* the build, each with the constraint that forced it (the gate runs
  the consumer's `test` string through `bash -c`, so a flag was never reachable; the config that
  would carry an opt-in is gitignored, so an opt-in would be unreviewable). The result is that
  `lean-gate.sh`'s diff is pure deletion and the replacement is a committed, diffable table.
- **OR-1 was resolved by measuring rather than by picking.** 67 suites timed alone, a stated
  threshold (≥9s) rather than a hand-picked list, and a table of four candidate memberships with
  the wall clock each produced — including the two that did *not* fit. The 3-row table at 214s is
  reported as a failure rather than quietly dropped, and the reason the bound has to actually be
  met (a reaped call leaves an unclosed `started` row; five hard-stop at `rc=4`) is stated.
- **The cost is disclosed against the author's own interest.** The PR and the TSV header both say
  plainly that twelve suites carry 84% of the sweep and are disproportionately the lane's own
  guards, name `scenario-liveness` as the most reluctant deferral, and point at the durable fix
  (widening `selftest-cache-inputs.tsv`) while declining to attempt it here.
- **`run-selftests.sh`'s dedupe is a correctness fix, correctly reasoned.** Counting one suite
  twice would under-state `EXPECTED` and red an honest sweep, and the comment says so — and this
  repo's own milestone-3 `test` command is exactly the case that hits it. The union becomes the
  single canonical list that both the count and the dispatch filter read, which is what makes it
  true rather than merely fixed.
- **AC-9 is the narrowest possible change to a contract nothing greps.** `orchestrate-lean.sh`'s
  `infra_token()` body is byte-identical; only two prose references to `m3infra-v2:0` move, and
  the selftest comment moves with them.
- **The seventh catalog row was found by re-sweeping rather than by re-reading.** `mutation-sweep-pr`
  was green on this PR while deferring all three edited guards; the build re-swept scoped anyway
  and found `lean-gate-m3-pid-outlives`, whose id contains no identifier the deletion grep would
  have matched. Catalog drift is a hard red, so that row would have redded nightly.

### AC scoring

All twelve scored against the committed spec `docs/plans/second-shift-566-lean.md`.

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `run_milestone` carries `3) cmd_3` in both the observe arm and the recording dispatch (`lean-gate.sh:4425,4464`); no spawn on any milestone-3 path. `(x3d)` asserts `all` reaches milestone 3 as one inline call, `(if5b)` and `(lean-inline-m3-nv)` assert no lane child outlives the gate's process group. Reap fit corroborated independently: I ran the default sweep in this checkout at **32s wall** (56 scored, 56 run, 0 failed), consistent with the PR's 50s end-to-end including the lint lane. |
| AC-2 | satisfied | 22 of 23 identifiers: zero matches outside `CHANGELOG.md` / `docs/plans/**`. `lane-registry.sh` and `lane-registry-selftest.sh` deleted. `INTERRUPTED_BUDGET_M3` survives in three comments only — see W-2. No live code, no workflow, no executable path. |
| AC-3 | satisfied | `(ib2)` drives milestone 3 to `rc=4` at 5 unclosed and asserts `interrupted 5/5` — the generic bound, its own 8 retired. `(ic3)` asserts exactly one `\| milestone-3 \| attempt \|` row on a red; `(ic4)`/`(ic5)` assert zero on `rc=7`. |
| AC-4 | satisfied | Verified live, not just by fixture: the default sweep printed one `deferred:` line per row carrying path, measured cost and the table's reason (13 lines), exited 0, and `56 scored, 56 run` — the discovered/ran invariant held with the exclusion computed pre-dispatch. |
| AC-5 | satisfied | `scripts/check-lean-chain.sh`, `plugins/dev-pipeline/tools/lean-evidence.sh` and the `pr-gates` job: absent from `git diff --name-only`. `.github/workflows/` diff is exactly four one-word `--full` additions (`ci.yml:121,398`; `nightly-guards.yml:100,134`) and nothing else. Scored against the spec's amended wording; the ticket body's original wording is W-1. |
| AC-6 | satisfied | `scenario-liveness-selftest.sh` gains `(lean-inline-m3)` — started/concluded pair closes inline and the scheduler reads `m3infra-v3:0` — and `(lean-inline-m3-nv)`, a non-vacuity case that kills the evaluation and asserts the read moves to `m3infra-v3:1`. The kill/rejoin scenario is removed, not left asserting deleted machinery. |
| AC-7 | satisfied | (a) no `tools/mutation-baseline.tsv` row resolves to deleted code — zero `lane-registry`/`lane_` rows ever existed, and the two lean-gate survivors are content-keyed and unmoved. (b) all **seven** named catalog rows deleted, verified against the diff. (c) VOID with its reasoning; I confirmed `scripts/lockstep-manifest.tsv` is absent at the base and that `bash scripts/check-lockstep-pairs.sh` is green here — **22 anchors, 0 failed**, with the `subset-of` `preflight.sh ⊇ lean-gate.sh` row passing. (d) PR states −2,180 net bash. |
| AC-8 | satisfied | No `gh`, `curl`, `nohup`, `setsid`, `disown` or background operator on any added line of `lean-gate.sh`; no network call on any milestone-3 path. |
| AC-9 | satisfied | `infra_token()` prints `m3infra-v3:%s` from `unclosed_count 3` alone (`lean-gate.sh:2010-2020`); the `"N runner record(s), M live"` diagnostic is gone, replaced by an unclosed-count line on stderr. `orchestrate-lean.sh`'s own `infra_token()` body is byte-identical — the only change in that file is one prose reference at `:677`. `(ir1)` asserts the token is never empty; `(ir4)` asserts the prefix and the dropped diagnostic. |
| AC-10 | satisfied | `tools/selftest-slow-suites.tsv` committed, 13 rows, each `path<TAB>seconds<TAB>reason`. Applied by default (`FULL -eq 0`), `--full` opts out. Selftested in five directions: default application, `--full` running all suites, explicit-`--exclude` + table dedupe against the run/discovered invariant, a stale row as a hard error with a **table-specific** message, `--full` not reading the table at all, and a malformed row as a usage error. I exercised the default path live. |
| AC-11 | satisfied | `CLAUDE.md:60` gains `--full`. `docs/testing.md` re-derives the four-caller count, adds the slow-suite section with a caller/passes/runs table, and rewrites the milestone-3 description. `SKILL.md:41` now describes the inline milestone and names the table; the file is **48 lines**, under the 60-line cap. Caveat at W-5. |
| AC-12 | satisfied | CI on head `40cfd26`: `lint-and-selftests` and `selftests (macos, bash 3.2)` both **success**, both invoking `run-selftests.sh --full --exclude tools/install-topology-selftest.sh`. PR reports 68 scored / 68 run / 0 failed. `mutation-sweep-pr` green (zero-verdict — it deferred all three edited guards; the build's scoped re-sweep is the real evidence and is reported in the body). |

### Design fidelity

`not-applicable`. The spec's `## Design` section is disarmed —
`Design: none — this is shell tooling with no rendered surface` — and the disarm is justified:
`.design` is absent from this repo's `.claude/second-shift.config.json`, no changed path is a
web-component surface, and the diff is shell, TSV, YAML and Markdown throughout. No RS rows, no
render receipt, nothing to hash.

### Reviewer panel

6 selected, 6 returned, none dark.

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Scope completeness | Fail | 2 blockers, 1 nit — re-derived and re-classified as W-1 / W-2 |
| Security | Pass | 0 (2 suppressed <80) |
| Performance | Pass | 0 |
| Complexity | Pass | 0 |
| Maintainability | Fail | 1 major (92) — B-1, confirmed and extended |
| Test coverage | Pass | 0 |

a11y and the design-fidelity dimension were not routed: no changed path matched
`stageParams.webComponentGlobs` (unset, so the shipped default `apps/web/**/*.{tsx,jsx}`).
Not a coverage gap — the trigger correctly did not fire on a shell-only diff.

CI on the reviewed head: `pr-gates` red on the missing verdict record **only**
(`[lean-evidence] ✗ no committed verdict record`), which is the expected pre-review state; every
other job green.
