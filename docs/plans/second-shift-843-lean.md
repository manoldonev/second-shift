# second-shift #843 — The lane-env load failure is untested in eight guards

`#839` gave eight guards the same two lines:

```
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/…" && pwd)/lane-env.sh" \
  || { echo "FATAL: cannot load lane-env.sh — the LANE_/LEAN_ compatibility reader" >&2; exit 1; }
```

No suite in the tree runs any guard with `lane-env.sh` absent, so the second line is dead text —
and the mutation sweep says so, twice: `526b44acfdb1` survived on `milestone-gate.sh` at
`7b117fadcc9a` and on `orchestrate.sh` at `ef4ce434`. The remaining six went unscored only because
#839's own merge sweep was an infra red.

The exit code is wrong as well as untested. A lib that cannot be loaded is an ENVIRONMENT fault,
and every one of these eight already spells that `2` — `envfail`/`die`, documented in each file's
own exit contract. Answering it with `1` sends the reader to look at their branch.

## Goal

The load-failure branch is executed, by name, in every guard that carries it; it answers with each
guard's own environment-refusal rc; and the mutation baseline carries no row for a site these
eight guards no longer have.

## Scope

### In

- The `lane-env.sh` load-failure branch in all eight guards — `milestone-gate.sh`, `reconcile.sh`,
  `orchestrate.sh`, `operator-override.sh`, `pipeline-cost-block.sh`, `check-lane-chain.sh`,
  `lane-bench.sh`, `lane-bench-arm.sh` — exits `2`.
- One `lane-env-selftest.sh` case that executes every such guard with the lib absent.
- One `tools/mutation-pair-map.tsv` row per guard, joining `lane-env-selftest.sh` to its kill set.
- The `milestone-gate.sh` review hand-back message, reworded off the `exit 1` substring.
- `tools/mutation-baseline.tsv` rows for these eight guards: re-keyed where #839's rename edited a
  site's own line, retired where the site is gone, added where this change promotes a live
  survivor into the scored window. D-3 names the re-key for `orchestrate.sh`; `lane-bench.sh`'s
  `LANE_BENCH_ROOT` row is the same shape and takes the same treatment, because retiring a row
  whose site is still live and still accepted reds the next sweep on the survivor it exists to
  accept.

### Out

- #842, the harness fault at #839's merge. A different failure with a different fix (D-4).
- The `exit 1` sites in these guards that are NOT the lane-env branch. They keep their rc; only
  their sweep ORDINAL moves, and AC-3 triages what that promotes.
- Plugin `version` fields and `CHANGELOG.md` — derived at release time (CLAUDE.md).

## Consequence this change accepts

Pairing `lane-env-selftest.sh` into eight kill sets makes `operator-override.sh` and
`pipeline-cost-block.sh` multi-killer guards, which the PR-lane sweep defers wholesale to merge
time. The other six were already deferred (slow-suite killers). The trade is the ticket's: D-1
asks for the pairing because the merge sweep is where these guards are graded, and that is the
lane the rows serve.

## Acceptance Criteria

- **AC-1** — Each of the eight guards, run with `lane-env.sh` absent, exits `2` and writes the
  `cannot load lane-env.sh` FATAL line to stderr; `lane-env-selftest.sh` asserts BOTH per guard,
  over a census it derives from the tree rather than a hand-kept list, and fails closed on an
  empty census.
- **AC-2** — `bash tools/mutation-sweep.sh --emit-site-keys` lists no `fail-open` site for the
  `lane-env.sh` load line in any of the eight guards, and none at the `milestone-gate.sh` review
  hand-back message.
- **AC-3** — A mutation sweep scoring all eight guards reports no survivor absent from
  `tools/mutation-baseline.tsv`. Any site this change promotes into the k=2 window is triaged in
  this PR — killed, or baselined with a reason.
- **AC-4** — The same sweep reports zero stale baseline rows for the eight guards.
## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Disposition and scope of the lane-env load-failure fail-open survivor | All 8 guards: the load-failure branch exits 2 (each guard's existing env-refusal rc), plus one lane-env-selftest.sh case that runs each guard with lane-env.sh absent and asserts rc 2, plus one tools/mutation-pair-map.tsv row per guard pairing it with lane-env-selftest.sh | user-answered |
| D-2 | Disposition of the milestone-gate.sh prose site 35caac0f4b00 | Reword the hand-back say line so it no longer contains the substring exit 1 (use rc 11); no baseline row | user-answered |
| D-3 | orchestrate.sh default::f131a84fe004 | Re-key baseline row default::4d47aa4f1b08 to f131a84fe004 keeping its accepted verdict (same site, renamed variable; tools/mutation-baseline.tsv row 54); also retire any other baseline row #839 left stale, found by diffing --emit-site-keys against the baseline | codebase-derived |
| D-4 | Relation to #842 (infra red @ e3f9607) | Out of scope: a harness fault, not a coverage gap (its body says so); tracked there | codebase-derived |
| D-5 | Verification of the fix | Moving the lane-env line off exit 1 can promote a previously-unswept exit 1 site into the k=2 window of the 8 guards; score all 8 with the sweep (not only the two the ticket names) and triage any newly surfaced survivor in this PR | codebase-derived |
| D-7 | Issue title | Keep the literal prefix mutation sweep red (title_key in .github/workflows/mutation-merge.yml; file-issue-on-red.yml dedups by startswith over open titles); retitled to mutation sweep red: lane-env load failure is untested in 8 guards | codebase-derived |
| D-6 | Exit-code semantics of rc 2 in the 8 guards | rc 2 is already the env/usage refusal in each (envfail/die helpers, e.g. milestone-gate.sh:406, reconcile.sh:106, check-lane-chain.sh:215, lane-bench.sh:99), so the change adds no new rc meaning | codebase-derived |
