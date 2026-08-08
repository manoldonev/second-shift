# lean review verdict — #413

verdict=needs-work
run_id: review-413-1
session_id: ab950fa9-f6c9-4a19-a46c-c1876b57bc61
rounds: 1
pr: #438
reviewed_head: 9838cf9bb7ff53f2ab4e207c8168a8f7913e801a
reviewed_patch_id: e2a480d6b5da0e3e48bbe3eafface815c9953832
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

Round 1 (chain root) over the full branch diff `5c8c25c..9838cf9`, 20 files, +1362/−446.
`bash G delta 413` printed the FULL range — nothing verifiable to inherit — so this round read
everything.

**Verdict: needs-work.** Two blockers. The change is otherwise strong, and its coverage is real
rather than decorative: three independent kill-probes run from this checkout redded exactly their
target cases across three suites.

## Blockers

| # | Site | Finding |
| --- | --- | --- |
| B-1 | `plugins/dev-pipeline/skills/run-lean/lean-evidence.sh:257,259` | `changed_files()` returns EMPTY-and-rc-0 when `PR_BASE_REF` is unset or `merge-base origin/$PR_BASE_REF` is unresolvable. That was safe while a branch-prefix arm existed; this diff deletes that arm, so the artifact scan is now the SOLE applicability input and an unreadable diff silently classifies a lean PR as non-lean. |
| B-2 | `docs/plans/second-shift-413-lean.md:103` (AC-11) | AC-11 requires the retired-`LEAN_BRANCH_PREFIX` notice on **stdout**; the implementation emits on **stderr**. |

### B-1 — the sole applicability arm fails OPEN on an unreadable diff

Reproduced by execution from this checkout, at this head:

```
# control — PR_BASE_REF present
$ PIPELINE_BRANCH_PREFIX=claude/second-shift- PR_HEAD_REF=claude/second-shift-413 \
  PR_HEAD_SHA=9838cf9 PR_BASE_REF=main PR_BODY='Closes #413' bash lean-evidence.sh classify
applicable=1
trigger=lean-artifact (docs/plans/second-shift-413-lean.md)

# probe — PR_BASE_REF absent
$ env -u PR_BASE_REF … bash lean-evidence.sh classify
applicable=0
trigger=
key=413
spec_in_diff=

# probe — PR_BASE_REF set, origin/<base> unresolvable (the shallow-checkout shape)
$ PR_BASE_REF=develop-does-not-exist … bash lean-evidence.sh classify
applicable=0

# and through the merge boundary itself, both times:
$ … bash scripts/check-lean-chain.sh --comments-file /dev/null
[lean-chain] non-lean change — lean chain check not applicable.
[lean-chain]   head branch: claude/second-shift-413
rc=0
```

That is this very PR — the one whose verdict record is missing — passing the merge-boundary gate.

**It is a regression, not a pre-existing gap.** `main`'s classifier, driven the same way on a real
lean branch with no `PR_BASE_REF`:

```
$ env -u PR_BASE_REF LEAN_BRANCH_PREFIX=lean/second-shift- PR_HEAD_REF=lean/second-shift-417 \
  … bash plugins/dev-pipeline/skills/run-lean/lean-evidence.sh classify     # on main
applicable=1
trigger=branch-prefix
```

Applicable on the prefix arm, after which the freshness arm's own `envfail` on a missing
`PR_BASE_REF` made the failure LOUD (exit 2). Post-change the same input is silent (exit 0).

The comment that justified the `return 0` is still in the file and its premise is gone:

```sh
[ -n "${PR_BASE_REF:-}" ] || return 0   # no base ref ⇒ no artifact arm; the prefix arm still applies
```

There is no prefix arm any more. The second arm that made this fall-through safe was deleted in
this diff; the fall-through was not revisited.

This contradicts three things the same diff writes:

- `docs/pipeline-manifesto.md`: *"There is no prefix to go stale and no constant to empty, so the
  self-neutralization mode above has nothing to act on here: a run wanting to escape this gate
  would have to remove its own spec from its own PR."* Not so — deleting one `PR_BASE_REF:` line
  from a workflow `env:` block also does it, and milestone 2 classifies a workflow edit as
  **advisory**, not fatal (this PR's own progress record shows exactly that advisory). The kill
  switch moved from a constant to the workflow's PR-context wiring; it did not stop existing, and
  unlike the old constant there is no second arm behind it.
- `scripts/check-lean-chain.sh`'s header: *"NON-VACUOUS BY CONSTRUCTION."*
- `lean-evidence.sh`'s own posture, twice stated: *"a check which cannot run must not report one"*,
  *"ZERO MARKERS IS A VIOLATION, not a vacuous pass."*

Neither shipped workflow is exposed today — `.github/workflows/ci.yml` and
`templates/consumer/second-shift-ci.yml` both pass `PR_BASE_REF` with `fetch-depth: 0`. The
objection is not that it is broken now; it is that the gate's only remaining arm no longer
fails closed, in a threat model where the workflow is agent-editable.

**Remedy.** Make an unresolvable diff an environment error in `changed_files()`, matching the
`envfail`s `arm_freshness()` already raises on the same two conditions — unset `PR_BASE_REF`, and
an unresolvable merge-base. Cost: three `check-pipeline-chain-selftest.sh` cases currently invoke
the delegation with no `PR_BASE_REF` (the trail-newer-than-PR-open case and the two `gh`-mock
cases at the end) and would need `PR_BASE_REF`/`--diff-files-file` added. Fail-closed there is
also what `check-pipeline-chain.sh`'s own header already claims (*"required for the lean
exclusion"*) and what AC-7's *"a delegation that cannot run is an environment error, never a
silent exemption"* asks for.

### B-2 — AC-11's stream

`AC-11` (committed spec, line 103): *"produces a deprecation notice **on stdout** and is otherwise
ignored."* `lean-evidence.sh:178` writes it to stderr. The PR body discloses this as a deviation
from `D-17` and the reasoning is right — `classify`'s stdout is a machine-read `key=value` block
that two delegating gates parse, and `(bb1b)` pins that purity. **The implementation is the correct
half; the spec line is the stale half.** Scored `unsatisfied` because the letter fails and this
lane scores by the letter; the fix is to reconcile the two, not to quietly leave them disagreeing.
AC-11's other two clauses (otherwise ignored, never an `envfail`) hold and are pinned by `(f)`.

## Warnings

- **W-1 — `.github/workflows/ci.yml`, the lean-chain step comment is now false.** *"the two cover
  disjoint branch namespaces … and editing check-pipeline-chain.sh would have re-keyed its four
  mutation-baseline rows for zero benefit."* Both halves are wrong after this change, and the same
  diff rewrote the identical sentence in `check-lean-chain.sh`'s header. Outside AC-15's enumerated
  list, but in a file the diff edits.
- **W-2 — the `pipeline-retro` PR-lookup recipe has no fallback for records written before
  `branch:` existed.** The new recipe reads `^branch:` from the progress record; **29 of 29**
  progress records under `.claude/pipeline-state/` lack that key today, including this run's own.
  `BR` is then empty and `gh pr list --head ""` returns rc=0 with the newest open PR — measured:
  it returns PR #438. A retro of any pre-`#413` run silently reads the wrong PR. One line fixes it
  (fall back to `<branch_prefix><issue>`, or abort when `BR` is empty). Self-heals for runs started
  after this merges.
- **W-3 — the artifact discriminator is now implemented twice, with no manifest entry.**
  `retro-corpus.sh:220-225` re-implements both halves of `lean-evidence.sh`'s test — the fixture
  exclusion (`is_fixture_path`'s three `case` patterns, as a three-pattern `grep -v`) and the
  key-matched `-<key>-lean.md` suffix — in a different dialect. `D-12` makes `open-prs` a
  discriminating site and `D-13` scopes delegation to `check-pipeline-chain.sh` only, so the copy is
  a reasoned choice (the mode has a `gh pr list` file array, not a PR context). But AC-8's first
  sentence reads *"No second copy of the lean discriminator exists"*, and the repo's own convention
  for a real-but-not-byte-anchorable coupling is a **DROPPED** note in
  `scripts/lockstep-manifest.tsv`. AC-8's enumerated obligations are all met, so it is scored
  satisfied; the missing note is the warning.

## Suggestions

- `branch-prefix-selftest.sh (g)` bounds `--help` at `Exit / return:` (header line 36), not at the
  last header line (38). The defect this run actually hit — a `sed -n '2,Np'` range four lines short
  — would still pass if it recurred by two. Anchor on line 38's text.
- `lean-evidence.sh:257`'s comment (*"the prefix arm still applies"*) is stale regardless of how B-1
  is resolved.

## Dismissed

`scope-completeness-reviewer` returned two blockers, both about issue #413's *"Carried forward from
the closed attempt"* residuals. Both are **settled by the binding pre-flight ledger**
(`.claude/pipeline-state/413-ledger.md` rev 2, whose full row set was posted to the issue as a
comment on 2026-08-08, so the disposition is in the tracker record, not only in a local file):

- *"the branch-key preference is closes-local"* → **`D-14`** (user-answered, intent): *"Branch
  suffix first, body as fallback … **Kills the phantom-key class the re-cut carries forward,
  including the closes-local residual.**"* The re-cut's arm (a) is strictly stronger than a
  closes-local preference: wherever a branch key exists it wins unconditionally, and the body is
  never read. The reviewer's counterexample — a legacy `lean/`-prefixed PR whose body carries
  `Closes #999` — has no parseable branch key at all, so the residual's premise ("the branch-key
  preference") does not hold there.
- *"check-pipeline-chain.sh still resolves its body key by first match"* → **`D-21`**: *"Closed for
  the payload by D-14 … `check-pipeline-chain.sh` keeps its own first-match body derivation
  unchanged — its mismatch arm is fail-closed, so a phantom body key there produces a red, not a
  vacuous green."* Verified independently: `KEY_BODY != KEY_BRANCH` is a hard `fail` at
  `check-pipeline-chain.sh:171-173`, so the divergence cannot produce a silent exemption.

Recorded as a disagreement rather than a suppression: the findings are factually accurate about the
code; what they lack is the ledger.

## Independent verification performed in this round

Everything below was run from the checkout of the reviewed head, not taken from the PR body.

| Check | Result |
| --- | --- |
| All six directly-affected suites, `env -u CLAUDE_CODE_SESSION_ID`, no `SKIP_STRESS` | 6/6 green |
| **Probe C** — neutralize the lean exclusion (`LEAN_APPLICABLE -eq 1` → `-eq 9`) | `check-pipeline-chain-selftest` reds on exactly one case, *"lean exclusion"*. KILLED |
| **Probe D** — restore the `claude/acme-` placeholder rung | `branch-prefix-selftest` reds `(d1)` — the target — plus `(c2)`, `(e2)`, `(e4)`. KILLED |
| **Probe E** — drop the key match in `classify()` | `check-pipeline-chain-selftest` *"cross-key lean spec wrongly exempted"*, `lean-evidence-selftest (d)` + `(z2)`, and `scenario-liveness-selftest (lr3)` (78 passed, 1 failed) all red. KILLED across three suites — the scenario legs are live, not decorative |
| **AC-9 replayed on real data** — #420 (`lean/second-shift-417`) head ref, base and 14-path file list pulled from the API, driven through the NEW classifier | `applicable=1`, `trigger=lean-artifact (docs/plans/second-shift-417-lean.md)`, `key=417` |
| `mutation-baseline.tsv` ordinal claim | Confirmed: `-eq`/`-ne` sites in the new `lean-evidence.sh` are line 83 (the *"zero-network"* Seams comment — ordinal 1, row correctly kept), 481, 595. The retired ordinal 2 (*"self-neutralization"* prose) is gone and the row is correctly dropped |
| CI on this head (run 31276273272) | `lint-and-selftests` PASS, `selftests (macos, bash 3.2)` PASS, `pr-gates` FAIL on the single line *"no committed verdict record"* — the ordinary pre-review shape |
| AC-6 / AC-7 in real CI, on the delivering branch | `[pipeline-chain] lean-lane change — chain check not applicable … classified lean via lean-artifact (docs/plans/second-shift-413-lean.md)` and `[lean-chain] applicable via lean-artifact …: branch=claude/second-shift-413`. Exactly one gate claimed it |
| Head unmoved / worktree clean after probing | `HEAD == origin/claude/second-shift-413 == 9838cf9`; `git status --porcelain` empty |

## Reviewer panel

`review-lead` fan-out over the branch's own diff (`origin/main...HEAD`): security, performance,
maintainability, complexity, test-coverage, scope-completeness.

| Reviewer | Verdict | Findings |
| --- | --- | --- |
| Security | Pass | 0 (3 suppressed, all < 55 confidence) |
| Performance | Pass | 0 |
| Maintainability | Pass | 0 (1 suppressed — the `retro-corpus.sh` fixture-exclusion duplication, promoted here to W-3) |
| Complexity | Pass | 0 |
| Test coverage | **Dark (no output)** | died after retry on the turn-budget cap |
| Scope completeness | Fail | 2 blockers, both dismissed above on the binding ledger |

**Coverage gap:** `test-coverage-reviewer` went dark (turn-budget cap mid-exploration, the known
emit-deadline class). Its domain is the one this round independently covered hardest — six suites
run green plus three kill-probes across three suites — so the gap is stated rather than papered
over, and merge readiness here does not rest on it.

**Not routed:** `a11y-reviewer` and the design-fidelity dimension — no changed path matched
`stageParams.webComponentGlobs` (unset; resolved default `apps/web/**/*.{tsx,jsx}`). `db-reviewer`,
`pipeline-reviewer`, `unit-test-mutation-reviewer` — no DB layer, no queue/worker files, no
co-located unit specs in this repo's test surface.

## Design fidelity

`not-applicable`. The spec declares no `## Design` section, this repo's committed config sets no
`design.provider`, and the diff has no UI surface at all (shell, YAML, TSV, Markdown). The merge
boundary reached the same conclusion on this head: *"[lean-chain] · spec declares no armed design
render lane — design evidence not applicable."*

## AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `LEAN_BRANCH="$BRANCH_PREFIX$BRANCH_KEY"` (`lean-gate.sh:286`) is the only name `mark` and milestone 5 look up; no `lean/` segment survives. The delivering branch is itself `claude/second-shift-413` |
| AC-2 | satisfied | key-only `tr '[:upper:]' '[:lower:]'`; `lean-gate-selftest (e3)`: `jdoe/` + `GH-540` → `jdoe/gh-540`, asserted off the record's own `branch:` key |
| AC-3 | satisfied | `branch-prefix.sh` rung 2; `(b1)` 2-votes-beat-1, `(b2)` optional slug, `(b3)` a non-`origin` remote peeled by ref depth |
| AC-4 | satisfied | rung 3 refuses and prints the whole tally; `(d1)` zero candidates, `(d2)` a tie naming both counts, `(d3)` the tie broken — which is what proves the refusal is about dominance and not about scanning. Probe D killed |
| AC-5 | satisfied | one `resolve_branch_prefix()`, sourced by both lanes. Proved behaviorally, not by grep: `retro-corpus-selftest (AC-5d)` resolves an unset prefix through detection and `(AC-5e)` inherits the shared refusal — a restored local default fails both |
| AC-6 | satisfied | real CI on this head, no `LEAN_BRANCH_PREFIX` in the workflow; key-matching proved by probe E killing `(d)`/`(z2)` |
| AC-7 | satisfied | real CI on this head; non-vacuity and the missing-payload fail-closed case both pinned; probe C killed exactly the exclusion case |
| AC-8 | satisfied | live row + both `LOCKSTEP-BEGIN/END` blocks deleted, the same-named DROPPED note rewritten, no new row, `check-lockstep-pairs.sh` green in CI. See W-3 |
| AC-9 | satisfied | replayed independently against #420's API data — `applicable=1`, `key=417` |
| AC-10 | satisfied | arm (a) returns before the body scan on a prefixed branch; `(z2)` kills a body-key-first mutant. (Narrow note: a prefixed branch whose suffix does *not* parse still reaches the body scan, which AC-10's second clause reads as non-prefixed-only — no strength is lost, since anyone who can name the branch can name a parsing one) |
| AC-11 | **unsatisfied** | stderr, not stdout — B-2 |
| AC-12 | satisfied | key-matched, fixture-excluded, read off the PR's own `files`; `(AC-5)` staged PR ignored, `(AC-5b)` other-key and fixture paths cast no vote, `(AC-5c)` a missing `files` field is rc=2 rather than an empty result |
| AC-13 | satisfied | verified in the CI job's own env dump: no `LEAN_BRANCH_PREFIX`; `PR_BASE_REF`/`PR_HEAD_SHA` present on the pipeline-chain step |
| AC-14 | satisfied | zero `LEAN_BRANCH_PREFIX` under `templates/consumer/`; the template already passes `PR_BASE_REF`/`PR_HEAD_SHA` under `fetch-depth: 0`; the selftest's fixture head refs move to the shared namespace |
| AC-15 | satisfied | all three enumerated sites updated (manifesto T0 note, `pipeline-retro` recipe, both chain-gate headers). W-1 and W-2 are adjacent, not enumerated |
| AC-16 | satisfied | `branch-prefix-selftest.sh` 16 cases for `AC-3`/`AC-4`; `(lr1)`/`(lr2)`/`(lr3)` compose both gates over one tree and one branch shape and assert *exactly one* claims the PR. Probe E redded `(lr3)` alone out of 79 cases |

15 satisfied, 1 unsatisfied, 0 undeterminable.

## Strengths

- **The delivering branch is the shape being rewired.** `D-16`'s choice to cut
  `claude/second-shift-413` rather than a `-recut` name means `pr-gates` on this PR *is* the AC-6 /
  AC-7 evidence — one gate claimed it, the other exempted it by delegation, on a branch the retired
  namespace test would have routed the other way. No fixture can produce that.
- **The scenario tier was used for what it is for.** `(lr1)`/`(lr2)`/`(lr3)` differ only in the
  fixture diff, which is precisely the claim ("the discriminator is the artifact, not the name"),
  and they compose both gates rather than checking each against itself.
- **The retro-corpus coverage is behavioral, not structural.** `(AC-5d)`/`(AC-5e)` would fail
  against a re-introduced local copy even if that copy re-implemented detection — a grep for an
  absent function would not.
- **The install-cache skip is keyed on the right discriminator.** Gating on
  `.claude-plugin/marketplace.json` at the resolved root keeps a missing gate a hard failure inside
  the repo while letting a staged plugin cache skip, which is the generic fix for any shipped suite
  reaching outside its own plugin.
- **A baseline-absent survivor was killed rather than baselined**, and the dropped
  `lean-evidence.sh::cmp-eq::2` row was retired in the same diff that re-keyed it — the ordinal
  obligation in the direction nobody watches.

## What round 2 must cover

Both blockers, and nothing else is required. The delta will re-expose whatever the fix touches;
everything unchanged is inherited from this record.
