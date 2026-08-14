# lean review verdict — #532

verdict=approve
run_id: review-532-2
session_id: 3b26a17b-bb80-4504-8d06-92bd5b0fbad5
rounds: 2
pr: #538
reviewed_head: d9c67ab7357d4041861c4f03addbda0693c5f652
reviewed_patch_id: 7ae791219096d01598827d9712134cb263921d40
inherited_patch_id: 23eb273a63ab6adbec1e1cfd0a8650043bd40d55
inherited_from_verdict: 90da2d033694b052e8de5c912851850fe522031b
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 2. Range reviewed: `90da2d0..d9c67ab` (the blocker fix), inheriting patch `23eb273a63ab`
— round 1's coverage of `128586c..02a45e2`, recorded in the prior verdict.

## Verdict

`approve` — round 1's single blocker is closed, and closed for the right reason. Every AC is
scored below against the whole spec; nothing new was introduced by the fix.

## B1 — closed

Round 1 blocked on `checked-call-selftest.sh:49,52,54` carrying `# shellcheck disable=SC2329`,
a code only shellcheck >= 0.10 emits. CI installs 0.9.0, which reports the identical
"function appears unreachable" condition as **SC2317** — absent from the CI exclusion list — so
`xargs` exited 123 and the lane died at its **first** step, taking the whole ubuntu selftest
sweep down with it.

`d9c67ab` widens the three directives to `SC2317,SC2329`. What makes it closed is not the diff
but the evidence on both sides of the skew:

| Evidence | Round 1 (`02a45e2`) | Round 2 (`d9c67ab`) |
| --- | --- | --- |
| `lint-and-selftests` | **fail**, 1m5s | **pass**, 3m47s |
| `shellcheck` step | failure | success (48s) |
| `run all selftests` step | never reached | success (2m35s), `77 discovered, 1 excluded, 76 to run` |
| local shellcheck 0.11.0 | rc=0 | rc=0 |

The duration jump is the tell that the sweep actually executed rather than the lane simply
going quiet — shellcheck is that job's first step, so the earlier red was the *absence* of a
test result, not a test result. All four suites this diff touches are named `pass` in the
ubuntu log: `checked-call-selftest` (13 passed, 0 failed), `check-fail-open-shapes-selftest`
(17 passed, 0 failed), `detect-selftest`, `lean-gate-selftest`.

The fix is version-agnostic rather than version-flipped: naming both codes is clean on either
binary, because a disable for a code the running version never emits is inert. That is the
property that keeps this from trading CI's red for a local one.

I checked the suppression is honest rather than merely quiet. The three functions carrying a
directive — `say_match` (:53), `say_empty` (:56), `say_stderr` (:58) — are invoked **only**
indirectly, through `checked_match … -- <fn>` running them via `"$@"`, so the directives
describe a real indirection and hide no dead code. `say_nomatch` and `die_7` are invoked
directly at :132/:134 and correctly carry no directive; neither version flags them. The
directive at :49 is separated from `say_match` by three comment lines and still binds it —
shellcheck skips comments — which both binaries confirm empirically.

## Per-AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 | **satisfied** | Inherited. `checked_match` returns three distinguishable outcomes from one canonical text, second copy pinned byte-identical. Re-confirmed at this head by CI's `contract lockstep pairs` step (success) and by the ubuntu `checked-call-selftest` run, 13/13. Round 1's probe P1 (`return 2` -> `return 1`, both copies) killed (c3)(c4)(c5) and both halves of detect case 6. |
| AC-2 | **satisfied** | Inherited; untouched by the delta. All three arms of `check_pause_and_ask` return 2 and the caller raises `envfail`. Round 1 probes: P2 (gh arm -> `return 0`) killed **(y10) alone**, reproducing the pre-fix `rc=1 attempts=1`; P3' (jq arm's `||` removed) killed **(y9) alone** at `rc=0` — the genuine fail-open. (y11) holds the opposite direction. `lean-gate-selftest` green on both CI lanes at this head. |
| AC-3 | **satisfied** | Re-run live at this head, not inherited: `check-fail-open-shapes.sh` exits 0 — `16 enumerated site(s), all dispositioned; no banned shapes` — and `--list` prints exactly 16, against 16 non-converted TSV rows (5 safe + 7 out-of-scope + 4 not-a-site) plus 3 converted. Round 1 probes P6 (`UNCLASSIFIED`), P10 (`ANCHOR DRIFT`), and P9 (a reverted conversion, which reds **both** at rc=2) each fired. |
| AC-4 | **satisfied** | Both declared legs fire (round 1 P6 `\| grep -q`, P7 `pgrep -fc … \|\| echo 0`); guard green at this head. The narrowing is stated in the committed spec and measured, not assumed — see W1. |
| AC-5 | **satisfied** | **Upgraded from round 1's "satisfied in content; unexecuted on the ubuntu lane".** The suites now demonstrably ran there: 76 of 77 discovered suites executed (the one exclusion is `install-topology`, per the standing CI recipe) and the sweep passed, alongside a green `selftests (macos, bash 3.2)`. `mutation-sweep-pr` passed with `checked-call.sh` applied=5 killed=5 **survived=0** and `check-fail-open-shapes.sh` applied=13 killed=11 survived=2 — identical to round 1, and the two survivors are exactly the baselined prose `logic` ordinals. No unbaselined survivor on any swept guard. |

Fidelity: `not-applicable` — the spec declares no `## Design` section.

## Panel

5 selected, 5 returned, **none dark**: maintainability, test-coverage, security, performance,
scope-completeness — all `approve`, zero findings. `test-coverage-reviewer`, which went dark in
round 1 and was the dimension that diff most needed, ran this round and approved.
`scope-completeness-reviewer` re-resolved the range to `merge-base(origin/main, HEAD)` and
scored the **whole ticket** rather than the delta: PASS.

Not routed, and not a coverage gap: `a11y-reviewer` and the design-fidelity dimension — no
changed path matched `stageParams.webComponentGlobs` (absent from config, so the default
`apps/web/**/*.{tsx,jsx}`). `complexity` and `test-coverage` are depth-skipped at this size;
test-coverage was spawned anyway because the delta touches a test file.

Provenance note, because it changes how the panel's coverage should be read: the first dispatch
carried a base SHA that did not resolve in the worktree, which made the reviewers' canonical
diff command fatal. Their approvals could not be certified as diff-grounded, so the panel was
re-dispatched against the true SHA `90da2d033694b052e8de5c912851850fe522031b`. The result above
is the second run; the first is discarded, not averaged in.

## Warnings (not blocking)

### W1 — the capture costume still has no guard leg (carried forward from round 1)

The guard binds `| grep -q` and `pgrep -c`. It does not bind
`out="$(cmd)" || { warn; return 0; }` — the shape AC-2 just fixed in `check_pause_and_ask`, and
the shape of the ticket's third session-authored instance. Nothing reds if it is reintroduced in
a committed file.

Unchanged from round 1 and still not a blocker for the same reasons: the committed spec states
the narrowing explicitly, argues it from the `stack-generality-lint.sh` posture the ticket names
as its template, and backs it with a measurement that re-runs true. Per the round contract a
round-1 warning is not escalated to a round-2 blocker, and nothing in the delta touched it. Worth
a follow-up ticket for the narrower `|| { …; return 0; }`-inside-a-predicate slice.

## CI at this head

`lint-and-selftests` pass · `mutation-sweep-pr` pass · `selftests (macos, bash 3.2)` pass ·
`release-pr-gates` skipped · `pr-gates` **fail** — at `lean chain reconciliation` only, every
other step in that job green. That arm names its own reason and clears when this record lands;
it is the expected pre-verdict state, not a finding.

## Strengths

- The blocker fix is the version-agnostic form rather than the version-flipped one, so it cannot
  reintroduce the same class on whichever binary the other lane happens to run.
- Its commit message verifies against CI's actual 0.9.0 binary in both directions (rc=0 after,
  rc=1 with exactly those three SC2317s before) instead of reasoning about the version skew.
- The directives are placed narrowly and honestly: exactly the three indirectly-invoked stubs
  carry one, and the two directly-invoked stubs deliberately do not.
- The round-1 diff's structural strengths hold unchanged — one canonical text with a
  byte-identical pinned copy, and a denominator that is the guard's own `--list` output with each
  half checking the other.
