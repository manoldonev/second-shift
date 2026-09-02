# lean review verdict — #780

verdict=approve
run_id: review-780-3
session_id: f01284d1-02bf-4384-9ceb-de02a3a77793
rounds: 3
pr: #784
reviewed_head: 1871ecd91532ac51b275a4b12f8c7ee2e23a3c03
reviewed_patch_id: c1c15358826df3fe2e739b0ce4945e3118ea4dfa
inherited_patch_id: 8b616dcf346d6c61109cf244bc7e8096fa2ca1e4
inherited_from_verdict: 5325ae98c743abcac0b479e5490b9303d94d8f3c
fidelity: not-applicable
panel: review-toolkit:scope-completeness-reviewer
model: opus
capabilities: pr-marker

## Review Summary

Round 3, inheriting round 2's coverage of patch `8b616dcf346d` and reading the delta
`5325ae98..HEAD` — one commit, `1871ecd9`, touching `CLAUDE.md` and `docs/testing.md` only.
Round 2's single blocker is closed, and I close it by re-measurement rather than by reading: both
counts the doc now quotes reproduce exactly at this head, from the doc's own commands. All seven
acceptance criteria are satisfied. Verdict `approve`.

No subagent met a trigger this round beyond `scope-completeness-reviewer` (issue-referenced,
unconditional), which returned Pass with zero findings. `security-reviewer` not selected: a
two-file Markdown delta carries no auth / tenancy / session / upload / query-construction surface
and the repo has no `.claude/second-shift/review-context/security-reviewer.md`; the security
dimension is covered by the lead pass. a11y + design-fidelity not routed: the repo config declares
no `stageParams.webComponentGlobs` and no changed path matches the shipped default
(`apps/web/**/*.{tsx,jsx}`). The spec declares no `## Design` section, so the design-fidelity arm
is `not-applicable` and step 5b did not run.

Depth routing: **trivial-inert** — every changed file in the delta is Markdown outside `.claude/`
(`CLAUDE.md` at repo root qualifies). Same routing as round 2.

## Strengths

- **The blocker is closed at the class, not at the digit.** Round 2 blocked on "33 shell files
  still call `mktemp -d -t` / `mktemp -t`", a figure that counted the two suites the same sentence
  exempted. The fix does not substitute a corrected constant — it replaces the constant with the
  two `git grep` pipelines that produce it, filtering the comment lines a naive `grep -l` catches,
  and follows them with "Re-run both commands rather than trust these two numbers". That is the
  remedy that survives the next commit, and the commit message names the defect class explicitly.

- **Every number in the delta reproduces at this head, including the one the fix re-derived past
  the review.** I ran the doc's two commands verbatim in the reviewed checkout: **34** files on the
  `mktemp -d -t` / `mktemp -t` spellings, **35** on the bare form, `comm -12` over the two sorted
  sets gives **0** overlap, union **69** — the exact triple the doc asserts. Round 2's record had
  re-derived 34 for the bare set and 68 for the union; the commit message flags the divergence
  head-on ("not 33 or the review's own re-derived 68") rather than quietly adopting the reviewer's
  figure, and the re-derivation is the correct one. I also read all 35 bare-form match lines
  individually — every one is a genuine `mktemp -d` call site, none is an unquoted explicit
  template miscounted by the exclusion filter.

- **The `14` is a real count, not a rounded one.** `git grep -nE 'mktemp[[:space:]]+-d[[:space:]]+"' -- '*.sh'`
  (non-comment) returns 14 lines across 14 files, and all 14 are the documented
  `mktemp -d "${TMPDIR:-/tmp}/<name>.XXXXXX"` form — no quoted-template caller uses a different
  spelling. The naive mention-grep the paragraph used to warn about returns 19, so the distinction
  the old caveat drew is still real and the new number is on the right side of it.

- **The scrub caveat now closes the half of the residue round 2 showed it was missing.** Round 2's
  failure story was a contributor whose killed suite is a bare-`mktemp -d` caller reading a caveat
  that told them to "read the caller list above and add its names" — a list that named only the
  `-t` set. The section now calls the bare-form callers "a second, disjoint gap", names where they
  land, and gives two concrete remedies. I confirmed the mechanism on this machine: under
  `TMPDIR=/tmp/mkt-probe-r3/`, a bare `mktemp -d` returned
  `/var/folders/.../T/tmp.dKnTQ24oSG` — the private `TMPDIR` ignored, exactly as the doc says.

- **`CLAUDE.md` regains what round 2 measured it had lost.** The bare-`mktemp -d` clause `main`
  carried and round 2's rewrite dropped is back ("which *is* `-t tmp` — same TMPDIR-ignoring
  behavior, not a safe third option"), all three forms are named, and the file now carries no
  hardcoded figure at all — it routes to `docs/testing.md` for the count with the reason stated
  ("a hardcoded number here would only go stale"). For the file every session loads, that is the
  right side of the trade.

## Critical (must fix before merge)

_None._

## Warnings (should fix)

- **[Scope completeness] PR body (confidence: 88) — the net-diff figures the body quotes are stale
  at this head, and the body declares the command that falsifies them.**

  The body reads "Net diff: -398 lines (389 insertions, 787 deletions) across this PR's commits
  (`git diff origin/main...HEAD --shortstat`); -679 excluding the spec and verdict-record commits
  (`docs/plans/`)". Measured at `1871ecd9`: `--shortstat` gives **442 insertions, 789 deletions**
  (**-347**), and with `':!docs/plans/'`, **129 insertions, 789 deletions** (**-660**). Both
  digits moved when round 2's verdict record (+206 lines under `docs/plans/`) and this round's fix
  landed.

  This is **not** an AC-6 failure and not a blocker: AC-6's bar is that the net diff is negative,
  which holds on both readings and on every intermediate head. It is flagged because the body
  cites the producing command by name, and a cell documented as regenerated from a command is read
  against that command's output — a reader who runs it gets different numbers than the sentence
  claims. Note the figure is stale **by construction** after every round: this record's own commit
  will move it again. The fix is a `gh pr edit` on the body, which changes no reviewed line and so
  does not void this record; do it as part of milestone 5 rather than spending a build round on it.

## Suggestions (consider)

- **[Maintainability] `docs/testing.md:181` (confidence: 82) — the `14` is the one number in the
  section with no command beside it, in a section whose new thesis is that numbers need commands.**

  Two paragraphs below, the doc says of the 34/35 pair: "Re-run both commands rather than trust
  these two numbers — they move every time a suite's scratch allocation changes, and a stale digit
  here is worse than none." The bolded `14` above it is exactly such a digit and has neither a
  command nor the caveat. It is *correct* at this head — I verified it — so this is an internal
  consistency point rather than an accuracy one, and it closes with one line:
  `git grep -nE 'mktemp[[:space:]]+-d[[:space:]]+"' -- '*.sh' | grep -vE ':[0-9]+:[[:space:]]*#' | cut -d: -f1 | sort -u | wc -l`
  reproduces it, and belongs in the same code block as its two complements. Round 2's suggestion
  asked for a count where "some" stood; this is the follow-through that suggestion implies.

- **[Complexity] `docs/testing.md:213-216` (confidence: 80) — the bare-form pipeline's exclusion
  filter rests on an unstated assumption.**

  `grep -vE 'mktemp[[:space:]]+-d[[:space:]]+("|-t)'` separates bare callers from explicit-template
  ones by assuming every explicit template is double-quoted. That holds at this head — I checked
  all 14 — but an unquoted `mktemp -d ${TMPDIR:-/tmp}/x.XXXXXX` would be silently counted as bare,
  inflating the 35 with no visible symptom. One clause naming the assumption ("explicit templates
  in this repo are always quoted, which is what the filter keys on") would make the failure mode
  legible to whoever re-runs it. Not a correctness problem today.

- **[Maintainability] `docs/testing.md:234-236` (confidence: 78) — "no name-based glob in this
  recipe can reach them, `-name` or otherwise" is true as scoped and overstated as read.**

  Scoped to *this recipe* the sentence is correct — the alternation names three families and the
  bare-form dirs are in none of them. But the trailing "`-name` or otherwise" reads as a claim
  about `-name` in general, and `-name 'tmp.*'` does reach them; what it cannot do is reach them
  *selectively*, because the name carries no repo identity and would sweep every other tool's
  scratch under the same root. That distinction is the actual advice, and the doc's own fallback
  ("scrub the whole root when nothing else is running there") already implies it. Related nit: the
  illustrative name is written `tmp.XXXXXXXX` (8) where the observed suffix is 10 characters
  (`tmp.dKnTQ24oSG`), so a reader building `-name 'tmp.????????'` from it would match nothing.

## Plan Compliance

Implementation matches the spec. The delta touches only the two files AC-7 and D-10 name, adds no
guard, no selftest case and no script (Out of scope, D-14), edits no `docs/plans/` record beyond
this round's own, and leaves the deferral rule itself unchanged. The spec has not been amended
since it was committed at `a5ebc38f` — `git log --oneline origin/main..HEAD -- docs/plans/second-shift-780-lean.md`
names that commit alone, so nothing in it was rewritten to match a later diff.

## CI at the reviewed head

Run `33645841301`, `head_sha` `1871ecd9` — the reviewed head exactly. Cited, not re-run:

- `lint-and-selftests` — **pass**, 4m22s. This is `tools/run-selftests.sh`, the same sweep AC-4's
  "a full sweep exits 0" names.
- `selftests (macos, bash 3.2)` — **pass**, 4m55s.
- `mutation-sweep-pr` — **pass**, 13s. OR-1's prediction holds: `run-selftests.sh`'s four catalog
  rows still resolve after the entry block was deleted, with no catalog edit.
- `install-topology` / `install-topology (macos, bash 3.2)` — skipped; the diff touches no
  packaging path.
- `pr-gates` — **fail**, on step 6 "lean chain reconciliation" alone. I read the job's step list
  via the API: step 3 (frozen files) and step 4 (changelog trailer) both **pass**, as does step 5
  (pipeline chain reconciliation). So no policy-gate red exists on this branch, and the step-6 red
  is the ordinary pre-approve structural state — the branch's committed verdict record is round
  2's `needs-work`. It resolves when this round's record lands.

Locally at the reviewed head, `scripts/check-lane-class-doc.sh` and `scripts/check-lockstep-pairs.sh`
both exit 0 — the two guards that read prose in the changed files.
`tools/check-sweep-bound.sh` exits 2 without `--log` here and identically on `main`, so that is its
argument contract, not a branch red.

## Pre-existing gaps (not blocking this PR)

- The 69-file TMPDIR-ignoring set is the repo's real state and this ticket deliberately does not
  reduce it (Out of scope: no new guard, no script). Converting the rest of the tree to the
  explicit-template form is a separate initiative; the doc's job here is to stop mis-stating which
  side of the line a suite is on, and it now does.

## Suppressed (below confidence threshold)

- `scope-completeness-reviewer` suppressed the stale PR-body net-diff figures as outside its
  domain. I promoted it to a Warning above — the scope reviewer is right that AC-6 holds either
  way, and right that it is not a scope gap, but the body names the producing command, so the
  claim is checkable and currently false.

## Verdicts

| Reviewer | Verdict | Findings | Confidence Range |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Lead pass — ✅ | 0 | — |
| Performance | Lead pass — ✅ | 0 | — |
| Complexity | Lead pass — ✅ | 1 | 80 |
| Maintainability | Lead pass — ✅ | 2 | 78-82 |
| Test Coverage | Lead pass — ✅ | 0 | — |

**Ready to merge?** Yes

**Reasoning:** Round 2's blocker is closed at the class rather than the digit — the hardcoded count
is replaced by the commands that produce it, and every figure the delta asserts reproduces exactly
in the reviewed checkout. The three remaining points are doc-polish suggestions and one PR-body
edit that changes no reviewed line.

## AC scorecard

| AC-n | score | evidence |
| --- | --- | --- |
| AC-1 | satisfied | Re-measured at `1871ecd9`: the spec's own oracle, `git grep -lE` over its two name patterns, excluding `docs/plans/`,, returns nothing (rc=1). All three files absent from the tree (`ls` errors on each), and present as full deletions in the branch diff — `tools/reap-lean-fixtures.sh` -201, `tools/fixture-stamp.sh` -64, `tools/reap-lean-fixtures-selftest.sh` -306. |
| AC-2 | satisfied | `grep -n 'reap' tools/run-selftests.sh tools/run-selftests-selftest.sh` returns nothing at this head. The entry block plus its header comment (-18 lines in `run-selftests.sh`) and the fake-reaper case (-40 in `run-selftests-selftest.sh`) are both gone. |
| AC-3 | satisfied | Both producers on the explicit-template form: `lean-gate-selftest.sh:82` `mktemp -d "${TMPDIR:-/tmp}/leangate.XXXXXX"` and `orchestrate-lean-selftest.sh:59` `mktemp -d "${TMPDIR:-/tmp}/orchestrate-lean-selftest.XXXXXX"`. D-11 holds in both — `trap cleanup EXIT` at `lean-gate-selftest.sh:69` and `orchestrate-lean-selftest.sh:49`, each before its `WORK` assignment. D-15 holds — `orchestrate-lean-selftest.sh:60` keeps `pwd -P`, and `lean-gate-selftest.sh:83` carries the mirror. No stamping remains in either. |
| AC-4 | satisfied | `grep -n 'fixture-stamp' tools/selftest-cache-inputs.tsv tools/mutation-pair-map.tsv` returns nothing; the branch diff shows -1 row in the pair map and the input row removed. `tools/check-sweep-bound-selftest.sh`'s comment cross-reference is reworded (-1/+1). "A full sweep exits 0" is cited, not re-run — the command and the head both match: `lint-and-selftests` pass 4m22s in run `33645841301` at `head_sha` `1871ecd9`, running the same `tools/run-selftests.sh`, with `selftests (macos, bash 3.2)` pass 4m55s beside it. |
| AC-5 | satisfied | `tools/selftest-suite-timings.tsv` gains a 10-line header block, prose only — no new column, no validator, and `check-sweep-bound.sh` parses the file unchanged. Its factual claim re-verified at this head rather than inherited: `tools/selftest-cache-inputs.tsv` declares exactly three suites; `lean-gate-selftest.sh` and `check-lean-chain-selftest.sh` both carry timings rows above the 9s threshold and are deferred, and `cost-block-selftest.sh` carries no row and is treated as fast — so a milestone-3 lane runs exactly one cacheable suite, which is the surviving instance the header names. |
| AC-6 | satisfied | `git diff origin/main...HEAD --shortstat` at `1871ecd9`: 442 insertions, 789 deletions — **-347**. With `':!docs/plans/'`: 129 insertions, 789 deletions — **-660**. Negative on both readings, which is the whole of AC-6's bar. The PR body still quotes the round-2 figures (-398 / -679) and is stale; recorded as a Warning above, not scored against this AC, because AC-6 constrains the diff and not the body. |
| AC-7 | satisfied | Round 2's sole blocker is closed and I close it by re-measurement. **The count.** Both `git grep` pipelines the doc now prints reproduce exactly in the reviewed checkout: 34 files on the `mktemp -d -t` / `mktemp -t` spellings, 35 on the bare form, `comm -12` over the sorted sets gives 0 overlap, union 69 — the doc's triple. Neither exempted producer appears in either set (a grep for either producer name over both sets returns nothing), which is precisely what round 2 found false. **All three forms named**, in both homes. **`CLAUDE.md`'s bare-form clause restored**, and the file now carries no hardcoded figure at all, routing to `docs/testing.md` instead. **The scrub caveat's missing half closed** — the bare-form callers are named as a disjoint gap landing under `_CS_DARWIN_USER_TEMP_DIR`, with two remedies; I confirmed the mechanism on this machine (`TMPDIR=/tmp/mkt-probe-r3/` + bare `mktemp -d` → `/var/folders/.../T/tmp.dKnTQ24oSG`). **The rest of AC-7 re-verified, not inherited:** the reaper paragraph is gone from `docs/testing.md`; the manual scrub command is present with its widening caveat; the `-t`-versus-explicit-template *derivation whose conclusion AC-3 falsified* is retired in both homes — `CLAUDE.md` now asserts the opposite and correct thing, that a private `TMPDIR` does relocate the two producers' scratch; the Concurrent-lane tier drops C-1 (`docs/testing.md:1851` records the retirement), its step-4 sampler is load-only with the fixture-row half gone, the stagger rule is absent, and C-2/C-3/C-4 keep live subjects; the record-void is noted at `docs/testing.md:1900-1902`. No `docs/plans/` record is edited — the branch's only `docs/plans/` changes are two new files, the spec and this verdict record. |
