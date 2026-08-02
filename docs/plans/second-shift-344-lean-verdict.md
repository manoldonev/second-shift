# Lean verdict — #344

verdict=approve
run_id: lean-344-x9f4t
rounds: 1

## Summary

Mechanical promotion of run-lean from experimental to default, with run deprecated. All 5
ACs verified directly (not just read): AC-1 repo-wide grep (excluding docs/plans,
.claude/pipeline-state, CHANGELOG.md) finds zero 'experimental' hits tied to the lean lane
— the two remaining hits are unrelated (cost-tracking-setup.md, audit QUERIES.md);
run/SKILL.md's deprecation notice states the pin policy with no version literal. AC-2:
check-frozen-files.sh runs clean (versions and CHANGELOG.md untouched, both still 3.6.0).
AC-3: both lean-gate-selftest.sh and check-lean-chain-selftest.sh pass all-green after the
claim-string edit. AC-4: commit carries a substantive Changelog trailer; grepped the diff
against the identity-token scrub list — none introduced. AC-5: ran
tools/mutation-sweep.sh --mode pr --base <merge-base> myself;
lean-gate.sh's survivor set (cmp-eq::1, cmp-z::1, detector::1, default::1, default::2) and
check-lean-chain.sh's survivor set (cmp-eq::1/2, cmp-z::1/2, detector::2, default::1/2)
match tools/mutation-baseline.tsv byte-for-byte — no new/removed mutation sites.
check-lean-chain.sh's dogfood-scoping and consumer-CI-prohibition sentences remain
verbatim as required. Commit verb feat: is defensible under this repo's honest-verb rule
(a real behavioral change ships: the claim comment string). No blockers found.

## Findings

None.
