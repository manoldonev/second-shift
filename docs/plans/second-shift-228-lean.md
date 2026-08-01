# #228 — exitplan-ledger-gate tier-3 plan resolution is vacuous under GNU find

`plugins/intake-toolkit/hooks/exitplan-ledger-gate.sh` tier 3 resolves session-fresh plan
files with BSD `find -newermB` (birth time). GNU find has no `-newermB`; the scan errors,
the trailing `|| true` swallows it, `CANDIDATES` comes back empty, and the hook takes the
zero-candidates branch and allows — indistinguishable from a scan that legitimately found
nothing. Tier 3 is therefore permanently vacuous on Linux: it can never lint a session-fresh
plan there. Landed under #215 as characterization, not a fix; pinned by `(t3h)` in
`exitplan-ledger-gate-selftest.sh` on every platform via a `find` shim that rejects
`-newermB`.

## Acceptance criteria

- AC-1: With `-newermB` unavailable, the hook probes once and falls back to `-newer`
  (mtime). A single session-fresh plan with an invalid ledger is then **blocked** (rc 2),
  not allowed.
- AC-2: A candidate scan that errors (find exits non-zero for any reason, including after
  the fallback) is distinguishable in the hook's stderr from a scan that legitimately found
  zero candidates, and fails **closed** (block, rc 2) rather than warn-and-allow — instead
  of both cases sharing the same `|| true` branch.
- AC-3: The exit contract is unchanged — 0 allow, 2 block, never 1 — asserted across all
  cases in `exitplan-ledger-gate-selftest.sh`, including the new scan-error case.
- AC-4 (doc): `(t3h)` is updated to assert the new blocked behavior instead of the old
  vacuous-allow characterization; the per-case `NEWERMB`-degrade branching in tier-3 cases
  `(t3d)`–`(t3g)` is removed since the fix makes them behave identically on both platforms.
  The `exitplan-ledger-gate.sh` bullet in `CLAUDE.md`'s "Characterization is not
  endorsement" register (and the now-empty surrounding subsection, since it was the
  register's only remaining entry) is removed in this PR.
- AC-5 (doc): `docs/testing.md`'s "Characterization is allowed" paragraph cites `(t3h)` as
  its example of a still-open characterization case. Landing AC-1–AC-4 makes that citation
  false — `(t3h)` now asserts fixed behavior — and a repo-wide grep turns up no other live
  characterization case to cite instead. Drop the dangling example sentence, keep the
  principle.

## Out of scope

- Any change to tier 1 (inline plan) or tier 2 (payload path field) resolution — both
  already work correctly and are untouched.
- The `-newer` (mtime) fallback is a weaker freshness signal than birth time (a
  touched-but-old plan could qualify) — accepted per the issue's scoped tradeoff: a working
  tier beats a permanently vacuous one.

## Verification notes

Stage 6's INERT lane skips lint/test on `.sh`/`.md`-only diffs; the full local sweep
(shellcheck + `*-selftest.sh` + jq) is run by hand and reported in the PR body. Commit verb
`fix:` (patch bump). This touches `plugins/intake-toolkit/**`, so the commit needs a
`Changelog:` trailer describing the operator-visible behavior change (tier 3 of the
ExitPlanMode ledger gate now works on GNU find instead of silently allowing every plan) —
not `none`.
