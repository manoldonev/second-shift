# lean review verdict — #388

verdict=approve
run_id: review-388-1
session_id: e9b896d5-764e-4213-b2d0-0441c0bfcfa7
rounds: 1
pr: #389
reviewed_head: 8439758033f1797b919e0412567328f187a93bc7
reviewed_patch_id: cb4468b201ba5423af28c02fe810befd013f78c5
inherited_patch_id: none
inherited_from_verdict: none
model: unknown

Round 1, root record — `delta` printed the FULL range (`a102ae2..HEAD`, 6 files), nothing to
inherit. Reviewed the whole branch diff.

Spec of record: `docs/plans/second-shift-388-lean.md`. The pre-flight receipt is binding and
extends the issue's AC set by three (AC-8, AC-9, AC-10) and constrains the reading of AC-5.

## Outcome

**approve.** Ten of ten ACs satisfied. Three warnings, none of them an unmet AC: each names a
property that no `AC-n` and no ledger decision states, so none is a blocker under this lane's
rule. They are recorded because each is a drift the repo has no lane that can red on.

## Findings

| # | Class | Where | Finding |
| --- | --- | --- | --- |
| W1 | test strength | `lean-reconcile.sh:450-453`, `lean-reconcile-selftest.sh` (P2) | The closing-line reduced-evidence guard is unkillable in the always-on direction. Verified by execution: replacing `if [ "$TRACKER_TYPE" = "jira" ]` with `if true` — every arm, github included, prints ` (jira adapter — REDUCED evidence: …)` — leaves the suite at **0 reds, rc=0**. (P1) pins the jira direction (`grep -q 'REDUCED evidence'`); nothing pins its absence on github. (P2) does not catch it: it compares `out_absent` against `out_github` (both mutated identically) and greps only for `NOT RUN`, which is the check-site note, a different string. Fix is one clause in (P2): `&& ! printf '%s' "$out_github" \| grep -q 'REDUCED evidence'`. Note for the record that the PR body's evidence row "closing-line qualifier neutralized → (P1) only" tested the *emptying* direction only; it reads as bidirectional coverage and is not. |
| W2 | doc accuracy | `tools/tracker/README.md:46-48` | "`lean-reconcile.sh` … branches at exactly **one**" undercounts by the counting convention the same paragraph applies to `lean-gate.sh` two sentences earlier. The script carries three `[ "$TRACKER_TYPE" = "jira" ]` conditionals — `:138` (the `--comments-file` refusal), `:231` (the check-(1) arm), `:451` (the closing-line qualifier) — and `lean-gate.sh`'s counted three include its own disclosure-only branch. The substance is right (one adapter-sensitive *check* site); the sentence as written is the same class of claim whose drift is what let this bug through in the first place. "branches at exactly one **check** site" would be accurate. |
| W3 | contract drift | `lean-reconcile.sh:129-132` ↔ `lean-gate.sh:224-228` | The `case`/enum block is now **byte-identical** across the two files (I diffed them; the only delta in the region is the `TRACKER_TYPE=` assignment line above it), and the code comment asserts the coupling in prose — "lean-gate.sh's enum, verbatim." Nothing pins it. `scripts/lockstep-manifest.tsv` is CI-enforced (`ci.yml:118`) and already carries several `verbatim` rows over exactly this file pair, and the block is byte-anchorable, so this is not a DROPPED-with-reasoning case — it is an available row that was not taken. Both suites drive the refusal against a hardcoded `gitlab` (`lean-gate-selftest.sh` (n1), `lean-reconcile-selftest.sh` (P3)), so neither couples the enums: if `lean-gate.sh` and `config-lint.sh` later admit a third adapter, both stay green while `lean-reconcile.sh` hard-exits `rc=2` before any check on every consumer of it — which is #388's own failure shape, reintroduced one adapter over. |

Nothing else survived. The reviewer panel returned seven of seven with no dark reviewer;
security, performance, maintainability, complexity and test-coverage each returned clean. W1
and W2 originate from the panel and are recorded here only because I reproduced them; the
three findings security suppressed (55/50/45) were correctly held below threshold — the
`$ISSUE` interpolation one is pre-existing code outside this diff.

## AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | (P1): rc=0, `[ ! -s "$GH_CALLS" ]`, and greps for the skipped-arm disclosure. The zero-network assertion is real — the recording stub is installed on both the `${GH:-gh}` seam and as `gh` earlier on `PATH`, so it is not inferred from the absence of a network error. |
| AC-2 | satisfied | (P5)-(P9), one per surviving arm, each failing on its own broken evidence under the jira fixture. **Non-vacuity verified independently:** I injected `exit 0` after the disclosure line — the mutant that skips (1b) and (2)-(6) alongside the fetch — and the suite redded exactly (P1), (P5), (P6), (P7), (P8), (P9). That reproduces the PR body's load-bearing evidence row. |
| AC-3 | satisfied | All 27 pre-existing cases pass, `--comments-file` ones included; 39/39 green on the suite. |
| AC-4 | satisfied | (P2) asserts the absent-key run **fetches** (`p_calls >= 1`), that its output is byte-identical to an explicit `github`, and that it carries no `NOT RUN`. The default is asserted, not assumed. |
| AC-5 | satisfied | `SKILL.md` is still exactly 60 lines — net-zero, the integrity paragraph rewritten in place, not appended. `tracker/README.md` gains the **reconcile** table row and the falsified blockquote is rewritten rather than supplemented; the page has no self-contradiction left. See W2 on one sentence added beyond the AC's letter. |
| AC-6 | satisfied | `check-frozen-files.sh a102ae2` → clean; `check-changelog-trailer.sh a102ae2` → OK. A `Changelog:` trailer is present on the fix commit (`Changelog: none` on the other two). |
| AC-7 | satisfied | Scanned the whole diff for consumer/operator identity tokens — clean. |
| AC-8 | satisfied | (P3): rc=2 naming the offending value, plus the second assertion that it refuses **before** any check runs (`! grep -q 'reconciling #'`). |
| AC-9 | satisfied | (P4): rc=2 with the refusal message, rather than an ignored flag. |
| AC-10 | satisfied — with the deviation named | The letter reads "the five rows … **are re-keyed** in this diff … with the re-baseline reason recorded in each row", and no existing row changed; one row was added. I re-derived every operator site list independently rather than accepting survivor-id equality: `git show a102ae2:<guard>` vs the branch copy under each operator regex from `tools/mutation-operators.tsv`. `fail-open` (3 sites), `detector` (3) and `default` (5) are unmoved in content and order, so the four rows keyed to them need no re-key. `cmp-eq` did re-key: the new adapter comment contains "zero-**ne**twork", enumerating as a site at ordinal 2 and pushing the file's one real `-eq` comparison from ordinal 2 to 3 — `cmp-eq::1` still designates the same original prose line, the added `cmp-eq::2` row is correct and genuinely unkillable, and the real comparison at ordinal 3 stays outside the baseline as a killed site. So the baseline is provably correct against the edited script, which is the property the AC exists to secure; stamping "#388" on four unmoved rows would have been false provenance. The spec's Design sentence "They are re-baselined in this diff" is now inaccurate for four of the five and should not be read as a record of what happened. No `tools/mutation-catalog.tsv` or `tools/mutation-exclusions.tsv` row addresses this guard, so nothing re-anchors there — confirmed. |

## Verification run in this review session

Worktree at the PR head `8439758`, tree clean, re-fetched and confirmed unmoved immediately
before writing this record.

- `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh` — clean.
- `jq empty` over every `*.json` — clean.
- Full selftest sweep, `-P 4`, **without** `SKIP_STRESS` and under `env -u CLAUDE_CODE_SESSION_ID`
  so the session-id leak cannot flatter the result: 63 suites, 918 passing assertions,
  `xargs` exit 0.
- Two adversarial mutation probes, each `cp`-restored (never `git checkout`), tree verified
  clean after: the AC-2 non-vacuity probe (6 reds, as claimed) and the W1 probe (0 reds).
- `lean-reconcile.sh --help` prints through line 77 — the last header line, `Exit 0 = reconciled`
  — and stops before `set -uo pipefail`. The hand-maintained `sed -n '2,77p'` range moved
  correctly with the header, and case (O) is content-anchored on both sides of that boundary.
- Confirmed `RUN_CLAIM` and `$COMMENTS` are referenced only inside the github branch, so the
  jira arm carries no unset-variable exposure under `set -u`.
- Confirmed no programmatic consumer of this script and nothing parsing its `reconciled:` line,
  which is what makes D-2's prose disclosure reversible at the cost the spec claims.

## What the change gets right

The bug is fixed at its cause with one resolution and one check-site branch, and checks (1b)
and (2)-(6) are left textually untouched — the reconciler does not become a second tracker
authority. The two loud refusals are the right call over silent tolerance, and refusing
`--comments-file` under jira closes the specific hole where a fixture-bearing case goes green
while asserting nothing. Most of all, (P5)-(P9) exist at all: without them (P1) could not
distinguish "the five checks run" from "the five checks were skipped along with the fetch",
since both exit 0 on a healthy fixture. That is the assertion this change lives or dies on, and
it is the one the diff invested in.
