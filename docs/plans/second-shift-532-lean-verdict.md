# lean review verdict — #532

verdict=needs-work
run_id: review-532-1
session_id: c2db65e5-4276-4067-b10a-0baf0a980dfe
rounds: 1
pr: #538
reviewed_head: 02a45e2976d99facd7bb0e67e5c479619db7cee8
reviewed_patch_id: 23eb273a63ab6adbec1e1cfd0a8650043bd40d55
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 1. Range reviewed: `128586c..02a45e2` (FULL branch diff — nothing verifiable to inherit).

## Verdict

`needs-work` — one blocker. The implementation is sound and every AC is met on its merits; the
blocker is that the PR's own `lint-and-selftests` lane is red, and it reds *before* the ubuntu
selftest sweep runs.

## Blockers

### B1 — CI `lint-and-selftests` is red: shellcheck SC2317 on the new suite

`plugins/dev-pipeline/skills/run/tools/checked-call-selftest.sh:49,52,54` carry
`# shellcheck disable=SC2329`. SC2329 is emitted only by shellcheck >= 0.10. CI installs
**0.9.0** (`shellcheck is already the newest version (0.9.0-1)`, job 94647756830), which reports
the same "function appears unreachable" condition as **SC2317** — not in the CI exclusion list
(`-e SC1091,SC2015,SC2181`, `.github/workflows/ci.yml:31`). `xargs` therefore exits **123** and
the lane fails at 1m5s.

Two consequences, the second of which is the reason this is a blocker rather than a nit:

1. The lane is red, so the PR cannot merge.
2. shellcheck is the **first** step of that job, so **the ubuntu selftest sweep never ran on this
   PR at all**. AC-5's suites are unexecuted on that lane. (`selftests (macos, bash 3.2)` did run
   and passed, and `mutation-sweep-pr` passed — see below — so this is a lint failure, not a test
   failure.)

Why it was missed: local shellcheck is 0.11.0, where `-e SC1091,SC2015,SC2181` over the four new
files returns **rc=0**. The disable directive matches what the local version emits and misses what
CI's emits.

Fix: widen the three directives to `# shellcheck disable=SC2317,SC2329`. Verified in an isolated
worktree — clean on 0.11.0 (rc=0) and the suite still passes 13/13, so the fix does not trade one
version's red for the other's. `say_nomatch` (:51) and `die_7` (:56) need no directive; both are
invoked directly at :129/:131, so neither version flags them.

## Per-AC scoring

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 | **satisfied** | `checked_match` returns 0/1/2/3 from one canonical text. Lockstep `checked-call` row present; `check-lockstep-pairs.sh` PASS (29 pairs, 0 failed); block SHAs identical by hand (`44a8b9d…`). Probe P1 (`return 2` -> `return 1`, both copies) fails (c3)(c4)(c5) and both halves of detect case 6. |
| AC-2 | **satisfied** | All three arms return 2; `cmd_1:2146` raises `envfail`, from the caller as the spec argues. Probe P2 (gh arm -> `return 0`) fails **(y10) only**, reproducing the pre-fix behavior exactly: `rc=1 attempts=1`. Probe P3' (jq arm's `||` removed) fails **(y9) only**, with `rc=0` — a clean milestone-1 pass on an unparseable issue file, the genuine fail-open. (y11) holds the opposite direction. |
| AC-3 | **satisfied** | Guard green: 16 enumerated sites, and the TSV carries exactly 16 non-converted rows (5 safe + 7 out-of-scope + 4 not-a-site) plus 3 converted. Probe P6 (new command-producer site) reds `UNCLASSIFIED`; P10 (anchor no longer a substring) reds `ANCHOR DRIFT`; P9 (conversion reverted to the old pipeline) reds **twice**, rc=2, exactly as the TSV header claims it must. |
| AC-4 | **satisfied** | Both declared legs fire: P6 (`\| grep -q`) and P7 (`pgrep -fc … \|\| echo 0`) each red. See the warning below on what the legs deliberately do not bind. |
| AC-5 | **satisfied in content; unexecuted on the ubuntu lane** | All five suites pass locally (checked-call 13/13, check-fail-open-shapes 17/17, detect all green, lean-gate all green, lockstep 29/0). `mutation-sweep-pr` passed: `checked-call.sh` applied=5 killed=5 **survived=0**, `check-fail-open-shapes.sh` applied=13 killed=11 survived=2 — the two survivors are exactly the baselined prose `logic` ordinals. All four new catalog rows are proved applied by arithmetic (13 = 10 generic at k=2 x 5 classes + 3 catalog; 5 = 4 generic + 1 catalog) and all four killed, with no `catalog anchor drift`. Blocked only by B1's lane ordering. |

Fidelity: `not-applicable` — the spec declares no `## Design` section.

## Warnings (not blocking)

### W1 — the capture costume has no guard leg

The guard binds `| grep -q` and `pgrep -c`. It does not bind
`out="$(cmd)" || { warn; return 0; }` — which is the shape AC-2 just fixed in
`check_pause_and_ask`, and the shape of the ticket's third session-authored instance (the `gh`
poll loop). Nothing reds if it is reintroduced in a committed file.

Not a blocker: the committed spec states this narrowing explicitly rather than quietly, argues it
from the `stack-generality-lint.sh` posture the ticket itself names as the template, and backs it
with a measurement. I verified the measurement — 54 files here match
`$(… || echo <default>)`, and 198 of 223 such expressions (89%) are the
`$(cond && echo a || echo b)` ternary or a `jq … || echo <config default>`. A leg reddening on
those would be switched off, as the spec says. Worth a follow-up ticket for the narrower
`|| { …; return 0; }`-inside-a-predicate slice, not a change to this PR.

### W2 — `test-coverage-reviewer` went dark this round

The reviewer panel returned 5 approve / 0 findings (security, performance, maintainability,
complexity, scope-completeness); `test-coverage-reviewer` died after its automatic retry
(turn-budget, no emit). That is the dimension this diff most needed, so I covered it directly
rather than leaving it as a gap: seven mutation probes in an isolated worktree, all scored by case
ID. Six killed (P1, P2, P3', P6, P7, P9, P10); one earlier attempt (P3) was **void**, not a
survivor — the edit orphaned an `else` at runtime though `bash -n` passed, so it was re-run
properly as P3'. An eighth (P8, appending text after a converted row's anchor) survived by
construction and is not a defect: the anchor check is a substring match, so appending cannot break
it, which is the intended behavior. Coverage for this round should be read as: panel minus
test-coverage, plus the probe set above.

## The spec amendment, examined

`29a12e2 docs(532): amend the spec to what the code actually does` narrows AC-4 after the
implementation landed, which the review contract flags as blocker-shaped. I do not score it as
one. It narrows the **spec's own first-draft elaboration** (`$(… || echo <literal>)` and
`$(… 2>/dev/null || true)`), not the ticket's AC-4, which asks only for "a guard [that] prevents
reintroduction, as code rather than convention" on the `stack-generality-lint.sh` template — and
that is delivered. The amendment is a separate labeled commit, states the narrowing in the
committed artifact ("because AC-4's own text overreaches"), and carries a measurement that holds
up when re-run.

The AC-2 correction in the same commit is stronger than an argument: it is verifiable, and it
checks out. The ticket asserts the two `gh` arms make milestone 1 **pass** on a blip. Probe P2
restores the pre-fix `return 0` and the gate emits
`✗ milestone-1: could not read issue #7 … (attempt 1/3)`, rc=1 — a refusal that spent a fix
attempt, never a pass. The spec's correction is right and the ticket's premise was wrong.

## Strengths

- The three-outcome vocabulary is carried by **one canonical text** with the second copy pinned
  byte-identical, so the selftest drives production rather than a mirror — the failure mode
  CLAUDE.md bans, avoided by construction.
- The denominator is the guard's own `--list` output rather than a number, and the two halves
  check each other: an unclassified site reds and a stale row reds. P9 demonstrates the pair
  working — one reverted conversion trips both at once.
- (y11) and detect case 6's third arm are both there specifically to stop their siblings passing
  vacuously, and both earn it: P2 and P3' each fail exactly one case, which is what makes the
  other two meaningful.
- `mutation-baseline.tsv` rows say what they displace and why, instead of being re-keyed silently.

## What to do

Widen the three disable directives to `SC2317,SC2329`, push, and let CI re-run. Nothing else in
the diff needs to change. Once `lint-and-selftests` is green — which also lets the ubuntu selftest
sweep actually execute for the first time on this branch — this is an approve on the merits.
