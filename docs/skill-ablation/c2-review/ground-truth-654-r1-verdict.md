# lean review verdict — #636

verdict=needs-work
run_id: review-636-1
session_id: 612b96a5-52b4-4403-a803-bdb5a50f2226
rounds: 1
pr: #654
reviewed_head: cfba10220fced059a2fd3032b58d7075ffd538f4
reviewed_patch_id: 588e6431c7c44b4a06563069ae7e90e6f29bfbe9
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

## Round 1 — `needs-work`

**Range read:** `dfd68a4..cfba102` (full branch diff; `G delta` reports FULL — nothing to inherit).
**Panel:** security, performance, maintainability, complexity, test-coverage, scope-completeness — all six returned, none dark. All six `approve` with zero findings; scope completeness **PASS** (every AC-1..AC-10 item grounded in the diff).
**Not routed:** a11y + design-fidelity — no changed path matched `stageParams.webComponentGlobs` (default `apps/web/**/*.{tsx,jsx}`). `unit-test-mutation-reviewer` not selected: no co-located unit-spec surface in this repo.
**Mechanical evidence (run at this head, in a checkout of it):** guard green — 305 sites / 5 files / 156 rows; `check-gate-buckets-selftest.sh` PASS, 29 assertions, 3.25s (under the sweep's 5s slow bar); diff-scoped `mutation-sweep --mode pr` applied=10 killed=10 **survived=0**; `shellcheck -e SC1091,SC2015,SC2181` clean; `check-lockstep-pairs.sh` 29 anchors, 0 failed; `check-fail-open-shapes.sh` green (13 sites); `check-guard-budget.sh` green; CI `lint-and-selftests`, `selftests (macos, bash 3.2)` and `mutation-sweep-pr` all pass. `pr-gates` is red on exactly one reason — the absent verdict record — which is this session's own output.

The slice is well built: the register is real, the guard checks both directions, and the paired suite kills every mutant the sweep proposes. One blocker, and it is about the denominator itself.

## Findings

| # | Sev | Where | Finding |
| --- | --- | --- | --- |
| 1 | **BLOCKER** | `scripts/check-gate-buckets.sh:109` | The command-position class `(^\|[;&\|(){}])` misses a refusal that sits after a shell **keyword**, so a live site in the corpus is outside the denominator today. |
| 2 | Warning | `scripts/check-gate-buckets.sh:96` (CORPUS) | `operator-override.sh` refuses twice through no helper at all (`echo … >&2; return 2`), and the header's residual note does not name that shape. |
| 3 | Warning | `scripts/gate-buckets.tsv:67-68` | Two rows dispose of the same site; row 67's truncated anchor also silently absorbs a second, different site. |
| 4 | Nit | PR body | Three stated figures disagree with the tree. |

### 1 — BLOCKER: a refusal after `then`/`else`/`do` is never enumerated

`enumerate()` requires the primitive to sit at line start or after one of `; & | ( ) { }`. A shell keyword is not in that set, so `else <primitive> …` — ordinary bash, and the shape of every `if …; then fail_milestone …` — is not enumerated at all.

There is one such site in the corpus **right now**:

```
lean-gate.sh:416      -*)              envfail "unknown option: $1" ;;     <- enumerated
lean-gate.sh:420        else envfail "unexpected argument: $1"             <- NOT enumerated
```

`--list` prints 416 and 426 and skips 420. Two sibling refusals in the same argument parser, four lines apart; one is in the denominator and one is invisible.

Why this is a blocker rather than a warning. The deliverable is a completeness claim — "the denominator IS this script's own output", "an unclassified site reds". For this shape the claim is false, and the failure is silent in the direction that matters: AC-2's unclassified-site arm can only red on a site the enumerator produced, so a new gate written as `then fail_milestone 3 "…"` joins the lane unclassified and CI stays green. That is the exact regression class #636 was filed against. Today's consequence is only the count (there are 306 live sites, not 305 — line 420 would classify `not-a-gate` under the existing `envfail ` class row either way), so nothing is *mis*-classified; the cost is entirely the guard's future reach.

Two things the header should be corrected alongside the code. Self-exclusion 3 is labelled "non-command positions", but `else envfail` **is** a command position — the label and the character set it then lists disagree, so a reader cannot tell whether 420 is excluded or forgotten (AC-8's bar). And `(g18a-d)` pin only the negative direction; nothing asserts that a *legitimately* placed call is enumerated from every position, which is why the gap survived a 29-assertion suite and a 10/10 mutation kill.

Remediation: widen the class to accept a keyword-preceded call (`then`/`else`/`elif`/`do`, word-anchored — `launch_note terminal` must stay out, and `(g18c)` already guards that), add the row(s) the widened enumeration produces, correct the header's self-exclusion 3 to describe what it actually does, and add a positive `(g18e)`-style case so the enumerator's reach is asserted rather than assumed.

### 2 — Warning: two helper-free refusals in `operator-override.sh`

`operator-override.sh:440` and `:467` refuse a malformed override block / register row with a bare `echo "[operator-override] …" >&2; return 2` — no `envfail`, no other helper. A primitive-keyed enumerator structurally cannot see them, and CORPUS declares only `envfail` for that file. AC-3 pre-committed to that primitive list, so this is not an AC-3 miss and I am not scoring it as one. But the header's stated residual covers only "a *newly named* refusal helper", and these are refusals with **no** name — a distinct, currently-live gap in the same sentence's spirit. Either name the shape in the header's residual, or route those two sites through `envfail`-style helpers so the register can reach them.

### 3 — Warning: a duplicate row, and an anchor reaching past its own site

`gate-buckets.tsv` rows 67 and 68 are both `lean-evidence.sh::note_violation`, both `gates-signal`. Row 68's anchor resolves only to line 913. Row 67's anchor is a **truncation** of the same text (`…, n`) and therefore matches *both* line 913 and line 778 — a different refusal, in a different arm. Net effect: line 913 is dispositioned twice (legal — the guard's AMBIG arm reds only on *disagreeing* rows, which the PR body states as its reading of AC-1), line 778's only disposition is accidental, and row 68 is fully redundant.

This is what makes the per-row counts sum to **306** against 305 distinct sites — and it is why the PR body's bucket table (142 + 140 + 21 + 3) does not add up to the 305 it states. AC-4's per-row count print did its job and made this visible; it just was not read. Tighten row 67 to line 913's text and give line 778 its own row, or drop row 68 and let row 67 own both deliberately with a `why` that says so.

### 4 — Nit: three PR-body figures disagree with the tree

Body says "28 assertions" (suite prints **29**); "`check-guard-budget.sh` green at delta +570" (measured **+673** at this head — the figure was taken before the last commit); and "**Two** places take AC-4's sanctioned anchor-covers-several exception", where five rows outside the two declared classes carry `hits > 1` (the `note_violation` pair in #3, and two `lean-gate.sh::fail_milestone` rows at 2 each — those two are legitimate same-decision-two-call-paths, matching the `terminal <slug>` precedent, and want only a mention).

## AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 | satisfied | Closed enum enforced (`g6`); anchor/yield/why all non-empty-checked (`g12`, `g12b`); `not-a-gate` `why` mechanically constrained to the three forms (`g11`). |
| AC-2 | **unsatisfied** | The three disagreement arms red independently (`g2`/`g3`/`g4`) and `--list` checks nothing (`g14`) — that half is met. The enumeration half is not: the shape recipe omits keyword-preceded calls, and a live corpus site (`lean-gate.sh:420`) is absent from the denominator. Finding 1. |
| AC-3 | satisfied | All five files carry their full declared primitive set; definition lines self-excluded by the file's whole set, `(g18d)` proving the `orchestrate-lean.sh` `envfail()`-defines-`terminal` case. Finding 2 is about refusals with no primitive, which this AC does not reach. |
| AC-4 | satisfied | One row per site is the default; the per-row covered count is printed unconditionally (`g1b`); a zero-hit row reds, split correctly between drift and outlived (`g3`/`g4`). |
| AC-5 | satisfied | Both directions cased (`g7`/`g8`); the vocabulary is parsed from `operator-override.sh` at run time, and an empty one is exit 2 rather than a vacuous pass (`g16`). |
| AC-6 | satisfied | `-` on a `gates-process` row reds (`g9`); `unwired — <reason>` accepted (`g10`); form only, no ticket check. |
| AC-7 | satisfied | One step in `lint-and-selftests`, beside `check-lockstep-pairs.sh` and `check-eval-model-identity.sh`; job is unconditional on `pull_request`. Not `pr-gates`. Confirmed green in CI at this head. |
| AC-8 | satisfied | Header records the out-of-scope residual, all three self-exclusions and the newly-named-primitive residual. Scored to the letter; self-exclusion 3's *label* is inaccurate for the keyword case and is folded into finding 1's remediation rather than scored separately. |
| AC-9 | satisfied | `gates-signal` added with the not-total-predicate rationale, plus the register pointer; enforcement not restated (P5). |
| AC-10 | satisfied | No corpus file edited, so no new refusal reason and no `gate-ablation-classes.tsv` row owed — verified against `git diff --name-only`. `check-fail-open-shapes.sh` green, no new row. No `lean-gate.sh` call site added, so no `scenario-liveness-selftest.sh` path touched. `Guard-mass:` trailer present on all three code commits; `check-guard-budget.sh` green. |

**Design fidelity:** `not-applicable` — the spec arms no `## Design` section.

**Verdict: `needs-work`** on finding 1. Findings 2-4 are not blocking and can ride the same fix commit.
