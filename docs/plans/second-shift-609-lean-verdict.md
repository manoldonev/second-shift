# lean review verdict — #609

verdict=needs-work
run_id: review-609-1
session_id: ef6d6033-8304-4915-bde3-343afbf7177e
rounds: 1
pr: #614
reviewed_head: 228e595590055d4d830df652c5e88c1dc053276b
reviewed_patch_id: 3c23f90156e0011eccf9a617d15d453ae06c0eca
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

## Review summary

Round 1, full branch diff (`f51f7d87..228e5955`), 9 files / +1607. The report is good work: the
numbers reproduce, the routing table checks out line-for-line against `ci.yml`, and the honesty
discipline the spec promised is actually kept — `unmeasured` is never smoothed into a pass, the
adjudicated column is disclosed as judgment, and the manifest genuinely pins what was measured.

One blocker. `tools/gate-ablation-selftest.sh` is **green on macOS and red on the ubuntu lane** —
13 cases fail, and `emit`'s entire success path dies with exit 139 (SIGSEGV) under that host's awk.
It reds two CI jobs and leaves the new guard with zero mutation coverage. AC-5 is unsatisfied.

Panel: 6/6 reviewers returned, none dark. Their only ≥80 finding does not survive verification at
the severity claimed (see Suggestions); the blocker below came from CI evidence, not from the panel.

## Strengths

- **The limitation is load-bearing rather than decorative.** `mechanical()` consults the committed
  verdict-record round boundary first and falls to `unmeasured`/`no-response` with no inference
  repair — no git metadata, no mtime, no merge time. The method section then states the reach
  limit, lists the four write-nothing refusal classes *in a table* rather than omitting them, and
  the report's own truncation caveat (10 of 52 records reach `milestone-4 satisfied`) keeps
  `no-response` from reading as a lane fact.
- **`check` is a real reproduction, not a prose grep.** The generated block sits between markers and
  is regenerated and diffed, and the corpus is pinned by sha256 — so AC-5's byte-for-byte claim is
  testable. `manifest` deriving the live-lane exclusion from the registry *and* recording where each
  exclusion came from in the header makes the corpus boundary auditable rather than asserted.
- **`tools/gate-ablation-classes.tsv` refusing an `other` bucket** (D-c) is the right call and is
  guarded — cases (g)/(g2)/(g3) pin the hard failure, and they pass on both lanes.
- **The routing table is accurate.** Every row verified against `.github/workflows/ci.yml`:
  `pr-gates` → *frozen files guard* / *changelog trailer guard* / *lean chain reconciliation*,
  `lint-and-selftests` → *shellcheck* / *run all selftests*, and `mutation-sweep-pr`.

## Critical (must fix before merge)

### C-1 — the selftest is green on macOS and red on Linux; `emit`'s success path segfaults there

`tools/gate-ablation-selftest.sh` — CI run
[32410936360](https://github.com/manoldonev/second-shift/actions/runs/32410936360), two jobs red:

| job | result |
| --- | --- |
| `lint-and-selftests` → *run all selftests* | `FAIL tools/gate-ablation-selftest.sh (rc=1)` — **the only failing suite in the sweep** |
| `mutation-sweep-pr` | `RED: unrunnable pair: tools/gate-ablation-selftest.sh does not exit 0 against the unmutated sandbox (exit 1) (guard tools/gate-ablation.sh). Its mutants are NOT scored.` → `mutants_applied 0, killed 0` |
| `selftests (macos, bash 3.2)` | **pass** |

13 cases fail, and the pattern names the mechanism precisely. **Every case that expects `emit` to
succeed returns 139 — SIGSEGV:**

```
FAIL (b)  emit succeeds over a manifest-matching corpus      — want '0', got '139'
FAIL (b2) two emits differ
FAIL (f)  an out-of-manifest record does not red the run     — want '0', got '139'
FAIL (l)  a session-id-shaped token exits 4                  — want '4', got '139'
FAIL (l2) an absolute local path exits 4                     — want '4', got '139'
FAIL (m)  an in-sync report checks clean                     — want '0', got '139'
FAIL (m2) a hand-edited table reds                           — want '1', got '139'
FAIL (m3) a report with no generated block reds              — want '1', got '139'
FAIL (j)(k)(k2)(k3)(m4) — want '1', got '0'
```

Every case that expects a *refusal* (`g`,`h`,`o*`,`p`,`q*`,`r*`,`d`,`e`) passes, because awk exits
before reaching the crash site. `gate-ablation.sh` then does `cat "$OUT" >&2; exit "$rc"`, so the
139 is the awk's, surfaced verbatim.

**Crash window, from which assertions still passed:** `(c)`, `(c2)`, `(c3)`, `(c4)` and `(f2)` all
pass, so Corpus, Decision points, Firings and the Never-fired row all rendered. `(j)` (repeat
firings) and `(k)`/`(k2)`/`(k3)` (false reds) return 0 matches, so those tables never printed. The
crash is inside `report()`, **at or after the Never-fired table's tail (`gate-ablation.awk:296`) and
before the Repeat-firings block completes (`:347`)** — i.e. Earn-your-keep, False reds, or Repeat
firings.

*Hypotheses, not measurements* — I have no mawk on this host to bisect with:
`printf ..., total_fr(), plural(total_fr())` (`:329`, `:348`) calls user functions inside a printf
argument list, and both `total_fr()`/`total_repeat()` iterate `for (gp in …)` over globals that may
never have been assigned an element; `adj_note[keep_key[gp]]` (`:311`) is a nested array subscript.
Bisect on the real host rather than trusting this ordering.

**Two consequences beyond the red build:**

1. **AC-5 is unsatisfied off this machine.** The byte-for-byte reproducibility claim, and the D-f
   rc=4 scrub gate, are both *unreachable* on the ubuntu lane — `(l)`/`(l2)` show the scrub never
   fires because `emit` dies first. A reader who re-runs the generator on Linux gets a crash, not
   the tables. The committed report was generated on macOS and cannot currently be reproduced
   anywhere else.
2. **The new guard has zero mutation coverage.** The sweep classifies the pair as unrunnable and
   scores `0` mutants applied — so the guard shipped without a single mutant proving it can fail.
   `sites_beyond_budget cmp-z:7+logic:17+detector:1+default:1` were all deferred.

The file's own header reasons about exactly this risk and gets the direction backwards:

> `# One-true-awk portable on purpose: no asort, no ENDFILE, no mktime. The macOS selftest lane runs`
> `# this under the same awk the lane's other guards do, and a gawk-only builtin would fail there and`
> `# nowhere else.`

The failure is Linux-only, so "would fail there and nowhere else" points at the one lane that stayed
green. Please fix the comment alongside the code — it is the reasoning that let this through, and
it is the repo's own recorded lesson that a green macOS sweep is no evidence for the other lane.

**Verification the fix needs:** a green ubuntu `lint-and-selftests` *and* a `mutation-sweep-pr` that
actually scores the pair. A local macOS re-run cannot distinguish a fix from the status quo.

## Warnings (should fix)

*(none beyond C-1)*

## Suggestions (consider)

- **S-1 `tools/gate-ablation.sh:213` — the absolute-path scrub anchor is narrower than its stated
  intent.** `grep -nE '(^|[ \`(])(/[A-Za-z_.]|~/)'` requires line-start, space, backtick or `(`
  before the path, so a `key=/Users/…` shape slips through (probed: no match, vs. a match on the
  space-prefixed form).
  The security reviewer filed this at confidence 85 on the premise that free-form `attempt`/`absent`
  reason text and `advisory` rows reach the generated block verbatim — **that premise is wrong.**
  `r_reason` is read only by `classify()` (`gate-ablation.awk:117`, `:201`) and `n_advisory` only
  contributes counts (`:114`, `:218`); the only free-form cells that reach `emit`'s output are
  `adj_note`/`adj_cite`, both from the committed, diff-reviewed adjudication TSV. So the residual
  surface is a hand-written committed cell, not corpus text — real, but a hardening nit, not the
  disclosure path described. Both committed artifacts are verifiably clean today (I grepped the
  whole of `docs/gate-ablation.md` and the manifest for UUIDs and absolute paths: nothing).
- **S-2 the scrub gate covers `emit`'s output, not the committed artifacts.** AC-5 asks that "the
  committed report and manifest carry no session ids and no absolute local paths", but the gate only
  inspects `$OUT` — the hand-written prose half of `docs/gate-ablation.md` is unscrubbed. Both are
  clean now, so this is coverage, not a defect. Running the same two greps over `$REPORT` in `check`
  would close it for the cost of two lines.
- **S-3 the demotion ranking is unpinned by order.** `worse()` plus the bubble sort at
  `gate-ablation.awk:273` decides the table AC-2 says the report ranks by, and no case asserts the
  resulting order — the fixture exercises the path without pinning it. Flagged by test-coverage at
  confidence 55; agreed as a low-cost addition once C-1 is fixed, since a comparator regression
  would currently survive.
- **S-4 spec F-5's counts no longer match the shipped report.** F-5 records the `m1/spec-absent`
  split as 39 `attempt` / 21 `absent`; the generated table says 36 / 18. The gap is the live-lane
  exclusion the manifest applies, which is correct behavior — but F-5 reads as a measurement and is
  now stale. A parenthetical noting the counts predate the corpus pin would keep it honest.
- **S-5 "first decision-changing firing" is manifest order, not chronological.** `keep_when[gp]` and
  `fr_when[gp]` take the first firing in corpus-file order, which is numeric issue id. Close enough
  to chronological to be harmless today, and deterministic either way; worth a word in the column
  header if the corpus ever gains an out-of-order id.

## Plan compliance

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | 33 declared points enumerated including 20 zero-fire ones; `tools/gate-ablation-classes.tsv` committed; every firing cited `record • milestone-N • ISO`; unmatched reason is a hard failure, pinned by (g)/(g2)/(g3) which pass on both lanes. |
| AC-2 | satisfied | `mechanical` and `adjudicated` are separate labeled columns; demotion table ranks by zero-decision-change count then `eval s`; six earn-your-keep rows each carry a dated incident. `attempts` are carried as the firing count and timing spans as `eval s`/`rework s`, so the issue's "attempts and timing spans" secondary key is honored. |
| AC-3 | satisfied | Method section states what is and is not recomputable; all four write-nothing refusal classes tabulated (wrong-tree `rc=9`, unattested-entry, `envfail`, scheduler) with "**It is never an implied pass.**"; 47 stage-era records listed out-of-corpus with their count. |
| AC-4 | satisfied | `**Lower bound: 1 firing.**` with the #531 citation; `**Upper bound: 5 firings.**` reported separately, naming reaping and idempotent re-invocation as the over-count sources. The issue's trailing "Phase 2 inherits both numbers with their labels" clause is not restated in the report; the substance (both numbers separately reported and labeled as bounds) is in-diff, and the report declares itself the successor slice's input at :13 — nit, not a gap. |
| AC-5 | **unsatisfied** | The suite is red on the ubuntu lane (C-1). The byte-for-byte determinism claim `(b2)` and the D-f rc=4 scrub `(l)`/`(l2)` both fail there, so neither guarantee holds off macOS. Determinism and `check` do hold on macOS — verified locally: two `emit` runs byte-identical, `check` clean, shellcheck clean, and the suite green under stock bash 3.2. |
| AC-6 | satisfied | `docs/pipeline-manifesto.md` V1 gains a pointer to the report and nothing else changes (4-line diff, 2 lines touched); no `plugins/**` path in the diffstat, so no gate, skill or other principle is edited. |

No scope creep. The diff is exactly the generator, its two input tables, the manifest, the report,
the spec and the one-line manifesto pointer.

## Pre-existing gaps (not blocking this PR)

None surfaced.

## Suppressed (below confidence threshold)

- `tools/gate-ablation.sh:120` (40) — `for id in $(record_ids)` word-splits, but ids are `[0-9]+` by construction.
- `tools/gate-ablation.sh:96` (35) — operator-supplied `--state-dir`/`--manifest` paths are uncontained; local operator tool, no untrusted caller.
- `docs/gate-ablation-manifest.tsv` (30) — committed sha256s of gitignored records leak no content.
- `tools/gate-ablation.awk:208-280` (55) — demotion ranking order unasserted → promoted to S-3.
- `docs/gate-ablation.md` (70) — AC-2's "attempts and timing spans" secondary key rendered across two tables; judged faithful.
- `tools/gate-ablation-selftest.sh` (70) — AC-5's "existing fixture seams" wording vs. seams this PR introduces; offline determinism is the intent and is met.

## Verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 1 (nit) | 85 |
| Security | Pass | 1 (downgraded to S-1) | 85 |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |

Not routed: `a11y-reviewer` and the design-fidelity dimension — no changed path matched
`stageParams.webComponentGlobs` (unset → default `apps/web/**/*.{tsx,jsx}`). `db-reviewer`,
`pipeline-reviewer` and `unit-test-mutation-reviewer` were not triggered. No reviewer went dark.

**Ready to merge? No.**

**Reasoning:** the analysis is sound and the report is the artifact #609 asked for, but its guard
does not run on the lane that gates the merge: the suite is red on ubuntu, `emit` segfaults there,
two CI jobs are red on it, and the new guard shipped with zero mutation coverage as a direct
consequence. AC-5 fails until a Linux-green sweep exists. Everything else scores satisfied, so this
should be a narrow fix round.

`pr-gates` is also red, on the absent verdict record — that is the expected pre-handoff state and is
not a finding.
