# lean review verdict — #516

verdict=needs-work
run_id: review-516-1
session_id: d79f3a7d-0501-478c-bcd3-25de0096c516
rounds: 1
pr: #523
reviewed_head: 7c8ef8e29d454c69e0dc588146c30d51d5787d97
reviewed_patch_id: aad82870d64bba388c7bb06ff1b6c0eff2759376
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review round 1 — PR #523 (issue #516)

Range reviewed: `e6a16ef..7c8ef8e` (full branch diff — round 1, nothing to inherit).
Panel: security, performance, maintainability, complexity, test-coverage,
unit-test-mutation, scope-completeness — 7 selected, 7 returned, none dark.
Verified independently in an isolated worktree: 32/32 suite green, shellcheck clean,
and 16 kill-probes applied to a throwaway copy and scored by case id.

## Verdict: needs-work — 1 blocker

## Blocker

**B-1 — the decomposition exit labels tickets it never scanned, and strips the label from
the one it did.** `intake-orchestrator/SKILL.md:385` runs the scan at Step 5.5 as
`dup-scan.sh --issue {ISSUE_NUMBER}` — the **parent**. Step 6 then creates 1–5 **new**
sub-issues, each with `--label ready-for-dev` (lines 467, 470), none of which existed at
scan time, and immediately removes `ready-for-dev` from the parent (line 493). On that
branch the only item that was scanned is the only item that does not end up queue-labeled,
so AC-7's stated invariant — *queue-labeled ⇒ scanned* — is not merely unproven but
inverted. It is also the exact wording of the issue's own first acceptance bullet:
"Intake surfaces likely duplicates among open queue-labeled tickets **before labeling a
new one**." The `sub-issues` / `sub-issues-sequential` verdicts are the route by which
intake mints new queue-labeled tickets; they are the ones the invariant most needs to hold
for.

The remedy needs no new tool capability: `dup-scan.sh` already supports the unfiled-subject
form (`--title <slice title> --body-file <slice body>`), which is precisely what
`intake-interviewer` was wired to use in this same diff. Scanning each synthesized slice
before `issue create --label ready-for-dev`, with the same rc-2 hard-stop, closes it.
Alternatively, scope AC-7 to the `no-split` verdict and declare the decomposition branch
out of scope in the spec — but that is a narrowing of the ticket, not a satisfaction of it.

## Warnings

**W-1 — `--issue` with `--body-file` is an untested branch.** `dup-scan.sh:127-130` rejects
the combination, and no case exercises it. Measured: deleting the whole guard leaves the
suite at 32/32. Six sibling usage errors (ds-a…ds-f) are each pinned, and AC-9 claims the
suite covers "each exit-code arm", so this one is an omission rather than a decision. One
case in the ds-b mould closes it.

**W-2 — the selftest's own header points at the wrong cases.**
`dup-scan-selftest.sh:11` says "cases (ds-i)/(ds-j) pin that the shipped threshold
separates them". Those are the non-array-tracker-response and unparseable-config cases; the
calibration pair is (ds-k)/(ds-l). The comment exists to send the next person re-taking the
measurement to the right guard, and it sends them to the wrong one.

## Suggestions

- **S-1** — the `-ss` de-pluralization exception (`dup-scan.sh:218`) is unexercised:
  removing it leaves the suite green (measured). Near-equivalent, since the strip is applied
  symmetrically to both sides, but the header calls it "the only exception worth carrying",
  which is a stronger claim than any case makes.
- **S-2** — the tie-break direction in `sort -t "$US" -k1,1r -k2,2n` (`dup-scan.sh:339`) is
  unpinned: no fixture pair ties, and flipping to `-k2,2r` leaves the suite green (measured).
  (ds-z) pins byte-identity across two runs of an unchanged corpus, which is a different
  property.
- **S-3** — the `0` / `10` / `2` taxonomy now lives in four places (the tool plus three SKILL
  blocks) and nothing couples them. Not byte-anchorable, so not a lockstep row — but
  `scripts/lockstep-manifest.tsv` carries 28 DROPPED annotations for exactly this shape, and
  AC-10's "nothing here is a second copy of another file's contract" is the one line of the
  manifest audit that does not survive contact with the diff.

## Acceptance criteria

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `dup-scan.sh` fetches, ranks and emits at/above threshold; (ds-k) surfaces #502 with its URL. The "before a new one is labeled" clause fails at the decomposition exit — charged to AC-7 rather than double-counted here. |
| AC-2 | satisfied | No write path of any kind; the JUDGE block names the three readings and forbids closing. Probe: deleting the block kills (ds-ab). |
| AC-3 | satisfied | Two queries unioned, `unique_by(.number)`, subject excluded. Probes: queue-only corpus kills 15 cases incl. (ds-q); dropping `unique_by` kills (ds-r)+(ds-s); dropping self-exclusion kills (ds-t). |
| AC-4 | satisfied | 0/10/2 taxonomy holds. Probes: a failed corpus query exiting 0 kills (ds-g)+(ds-i); a failed subject fetch exiting 0 kills (ds-h); accepting a non-array kills (ds-i). |
| AC-5 | satisfied | (ds-u) not-applicable line + rc 0; (ds-v) asserts an empty tracker-invocation log, so the arm provably did not look. |
| AC-6 | satisfied | (ds-n)/(ds-o) threshold, (ds-p) title weight, (ds-y) `--explain`. Probe: removing the truncation warning kills (ds-aa). |
| AC-7 | **unsatisfied** | The rc-2 hard-stop is stated at all three exits. The "before the ticket is labeled" half does not hold on `intake-orchestrator`'s `sub-issues` / `sub-issues-sequential` branch — see B-1. |
| AC-8 | satisfied | One ledger row per judged candidate on `10`, nothing on `0`, at all three exits. |
| AC-9 | satisfied | 32/32 against the `PATH`-stubbed tracker; every dimension the AC enumerates has a case, and 13 of them were confirmed live by probe. W-1/S-1/S-2 sit outside the enumerated list. |
| AC-10 | satisfied | Manifest description updated; `version` untouched at 2.3.3 across merge-base, branch and `origin/main`, and `check-frozen-files.sh` anchors on the merge-base, so the v5.0.0 release moving `main` does not implicate it. |

Design fidelity: `not-applicable` — the spec declares no `## Design` section and the repo
configures no design provider.

## Strengths

- The calibration is a fixture, not a comment: `corpus-live.json` is the real queue #500 and
  #502 were filed into, and (ds-k)/(ds-l) pin **both** sides of the 8–16 gap, so retuning
  `THRESHOLD` without re-taking the measurement reds the suite.
- The config-discovery case is run from a `git worktree add`, not the checkout root — the
  build session measured that the root form passes with the `--git-common-dir` anchor
  deleted, and moved it. Confirmed: from the worktree, deleting the anchor kills (ds-x0).
- The `US` (`\037`) field separator is chosen against the tab it replaces, with the
  IFS-whitespace collapse that would silently shift columns spelled out at the `printf`.
- The corpus summary line states the arithmetic ("union of N and M, less the subject") rather
  than three bare counts that would read as an off-by-one.
