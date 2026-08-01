# Lean verdict — #115

verdict=approve
run_id: lean115-1785587404
rounds: 1

## Summary

Correct, complete implementation of the CONFIG failure class per
`docs/plans/second-shift-115-lean.md`. The reviewer traced control flow through
`verifyctl.sh` (`record_failure` sets `overall=fail`, `emit_verdict` exits 1), `statectl.sh`'s
enum guard, and the fix-attempt charging filter — all three coordinated edits land as
specified, and the `el_count==0`/`ALLOW_UNVERIFIED` branch correctly falls through to the
object-shaped `verifySummary` (never masked by an opt-out string) since `unverified_string`
stays empty. All 6 ACs verified satisfied. `verifyctl-selftest.sh` (31/31, including the
extended v16 case asserting `rc==1` and `failures[].class==CONFIG`) and
`statectl-selftest.sh` (260/260) pass locally with `SKIP_STRESS=1`; shellcheck clean on all
three touched `.sh` files. Commit history is clean: `fix:` verb matches the honest-verb rule
(corrects a pre-existing misleading pass, no new capability), `Changelog:` trailer present on
the code commit and `Changelog: none` on the docs-only commit, no frozen release-artifact
files touched (`check-frozen-files.sh` passes). The reviewer additionally investigated a
theoretical edge case — a config author setting `extraLanes[].failureClass: "CONFIG"` to
sneak an immediate, uncontrolled charge through the unrelated extraLanes charging path — and
confirmed it's closed: `config-lint.sh`'s closed-taxonomy `IN()` list still only allows the
original six values, so `CONFIG` can never reach that path via config. No blockers found.

## Findings

- **note** (confidence 30): `statectl-selftest.sh` has no direct positive-path CLI exercise
  of the new `CONFIG` enum value in `cmd_verify_attempts`'s case guard (only the pre-existing
  negative-path bogus-class test). The spec explicitly frames the enum acceptance as
  defensive-only ("nothing charges CONFIG after AC-3, but the enum must accept it
  defensively"), and `verifyctl-selftest.sh`'s v16 case exercises the end-to-end
  CONFIG-recording path via the sidecar/verdict, so behavioral coverage of the outcome
  exists. Not fixed — optional, below the bar for a blocker or the committed AC-6.
