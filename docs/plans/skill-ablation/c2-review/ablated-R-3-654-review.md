# C2-a — ablation arm `R-3`: lines 110–114 removed

One arm of the leave-one-out ablation registered at
[`docs/skill-ablation-addendum.md`](../../../skill-ablation-addendum.md) §C, run 2026-09-03
against sample **C2-a** (PR #654 @ `cfba102`). The SKILL text supplied to the session is
`plugins/dev-pipeline/skills/review-lean/SKILL.md` at `8d5d0897` with **lines 110–114 deleted** —
unit `R-3`, rule 3, inheritance narrows what you READ, never what you must find; read wider whenever the delta looks misleading. Registered reach: **in-reach**.
Everything below each `## r<n>` heading is that run's output verbatim.

## The realised invocation

```bash
cd /private/tmp/c2b-748/clone            # throwaway clone, detached at cfba102
printf '%s' "$(cat prompts/R-3.txt)" \
  | env -u CLAUDE_CODE_SESSION_ID -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT \
      -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_BRIDGE_SESSION_ID -u CLAUDE_CODE_MESSAGING_SOCKET \
      -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_SSE_PORT -u CLAUDE_EFFORT -u CLAUDE_PID \
      -u RUN_ID -u LEAN_RUN_MODEL -u LEAN_ATTEND_MODE \
      claude -p --model opus --setting-sources '' --allowedTools "Read,Grep,Glob" \
        --output-format stream-json --verbose
```

The prompt is the ablated SKILL text, then
[`prompt-template.txt`](prompt-template.txt) verbatim, then the pinned diff
`dfd68a47..cfba1022` — the assembly §C registers.

Three additions to the registered `env -u` list, recorded rather than folded in: `RUN_ID`,
`LEAN_RUN_MODEL` and `LEAN_ATTEND_MODE` are unset by the runner, and were **also absent from the
launching environment** — these runs were launched detached (`start_new_session`) from an
interactive session that scrubbed them, not from inside a lean build session. That reproduces
arm 2a's realised condition. Nothing else about the invocation differs from the registered form.

## Apparatus

| run | rc | capture | `classify-capture.sh` | `result` events | tool calls | tool inputs naming `review-lean` |
| --- | --- | --- | --- | --- | --- | --- |
| r1 | `0` | 434526 B, 403 lines, sha256 `806b32ddf3aa287f…` | exit 0 — `COMPLETE` | 1 | 12 Bash,  13 Grep,  11 Read | **0** |
| r2 | `0` | 451608 B, 499 lines, sha256 `762b9e6c1873e88d…` | exit 0 — `COMPLETE` | 1 | 37 Bash,  7 Grep,  6 Read | **0** |
| r3 | `0` | 391775 B, 424 lines, sha256 `330972a82ac91e18…` | exit 0 — `COMPLETE` | 1 | 7 Bash,  17 Grep,  6 Read | **0** |

Only an exit-0 `COMPLETE` capture is scored. The last column is the ablation's own integrity
check: the clone keeps `plugins/` in the working tree, so a session that read the unablated
`review-lean/SKILL.md` off disk would defeat the line-range ablation. It is counted per run
rather than assumed away.

---

## r1

2026-09-03T18:39:44Z → 2026-09-03T18:48:29Z. stderr empty.

I couldn't execute the scripts in this session (Bash is restricted here), so everything below is derived by reading the guard's recipe and matching it by hand against the five corpus files. Findings are anchored to lines I verified.

## What the change does well

The register/denominator pairing is the right shape, and the four independent reds (unclassified / drift / outlived / ambiguous) are each genuinely cased. `gates-signal` is a well-argued addition — the `fail_milestone 3 "$key failed (rc=$rc)"` row is the case that justifies it, and making the safety arm register-internal (a yield cell naming an `OVERRIDE_GATES` value forces `gates-process`) is a better mechanism than proximity. Reading the enum from `operator-override.sh` at run time instead of copying it is correct per D-4. The `FILENAME ==` fix over `FNR == NR` in `cfba1022` is a real bug caught, and (g22) is the right case for it.

I verified AC-10's obligations independently: no corpus file is edited; `check-fail-open-shapes.sh` needs no new row (every `| grep -q` in the two new files is a `printf` producer, already excluded by `VAR_PRODUCER`); `Guard-mass:` trailers are present on all three commits; no `lean-gate.sh` call site is added, so `scenario-liveness-selftest.sh` is correctly untouched. AC-7 is satisfied — the step is in the always-on guard job beside `check-lockstep-pairs.sh`, not `pr-gates`.

## Per-AC scoring

AC-1 ✅ · AC-2 ✅ · AC-3 ✅ · AC-4 ✅ · AC-5 ✅ · AC-6 ✅ · AC-7 ✅ · **AC-8 ❌** · AC-9 ✅ · AC-10 ✅

## Warnings

1. **`scripts/gate-buckets.tsv` — the `terminal preflight-rejected 2` row's `why` misstates its own mechanism.** It reads "The one probe whose premise is an absent human exits at the resumable code above before this line." That is true only when the intake probe is the *sole* failure: `orchestrate-lean.sh:630` gates the resumable exit on `r1 -eq 3 && r2 -eq 0 && r3 -eq 0 && r4 -eq 0`. With `r1 == 3` *and* `r3 != 0`, control falls through to line 634 and the composite refusal does carry an absent-human premise. The disposition (`gates-signal`, never yields) is still right — #613 AC-3 deliberately makes that composite non-resumable — but AC-1 requires the `why` to name the mechanism that makes it true, and this one names a mechanism that does not hold in the case that matters.

2. **`scripts/check-gate-buckets-selftest.sh:326` and `:336` (g18b, g18d) are vacuous.** g18b asserts no `orchestrate-lean.sh::terminal` site at **line 1** — line 1 of the fixture is the shebang; `terminal()`'s definition is line 2. g18d asserts no `orchestrate-lean.sh::envfail` site at line 3, but the exclusion it claims to pin is that line 3 is not a **`terminal`** site (`envfail() { terminal "$1" 2 "$2"; }`, the whole-primitive-set exclusion AC-3 calls out as subtle). Both pass regardless of the logic under test. The mutation is still caught indirectly by (g1) going red, but neither case tests what its own label says.

3. **`scripts/check-gate-buckets.sh:198-200` — AC-5 direction 2 is strictly subsumed by direction 1.** Any yield cell naming an `OVERRIDE_GATES` value is by definition `!= "-"`, so line 195 always fires first and the row is counted twice. The specific message is a useful diagnostic, but it can never appear alone, and one bad cell costs two violations.

## Nits

- `scripts/check-gate-buckets.sh:234` cites "(g21) is the case" for the all-comment register; that case is (g22). (g21) is the empty-denominator case.
- `scripts/check-gate-buckets-selftest.sh:19` labels the negative-direction block "(g17)"; those cases are g18a–g18d, and (g17) is the missing-register case.
- A row with **more than** five tab-separated fields is accepted silently — `read` folds the extras into `rwhy`. Only the too-few direction is checked (`:171`).
- `scripts/check-gate-buckets.sh:161-167`: the `trap` is installed after all three `mktemp` calls, so an `envfail` on the second or third leaks the earlier temp file(s).
- `scripts/check-gate-buckets.sh:80`: a second positional argument silently overwrites `ROOT` instead of erroring.

## BLOCKERS

**1. `scripts/check-gate-buckets.sh:93-97` — refusal sites that go through no named helper are invisible to the denominator, and two of them are substantive gates.**

The enumerator can only see calls to the five declared primitive sets in `CORPUS`. Several live refusals in the corpus files refuse inline with `echo … >&2; exit N` and route through none of them, so they are not enumerated, carry no bucket, and CI stays green:

- `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:5369-5373` — "this run has no entry attestation in `$PROGRESS_FILE`" → `exit 2`. This is a real gate: `review-lean`'s step 4 reads exactly this exit as "no entry attestation is READABLE" and hands the run back on it.
- `plugins/dev-pipeline/skills/build-lean/lean-evidence.sh:1156-1159` — "PR body carries no resolvable issue reference … but this PR commits a lean spec" → `exit 1`, whose own comment reads "A refusal, never a waiver". Its twin in `scripts/check-lean-chain.sh` **is** classified (`check-lean-chain.sh::fail`, `gates-signal`). The same fact is bucketed in one file and unbucketed in the other.
- `lean-gate.sh:5350-5352` (unresolvable merge-base → `exit 2`), `lean-evidence.sh:846-850` and `check-lean-chain.sh:563-568` (comment-fetch failure → `exit 2`), `lean-evidence.sh:160`, `check-lean-chain.sh:189`, `operator-override.sh:540`, `lean-gate.sh:2594` (inline usage errors → `exit 2`).

**Consequence:** the script's title, the CI step name, and the new manifesto sentence "an unclassified one fails CI" are all false for these sites. AC-8 requires "A reader can tell an excluded surface from a forgotten one," and the header's only declared residual (`:56-60`) covers "a NEWLY NAMED refusal helper … is not enumerated until it is declared" — which does not describe a refusal that uses no helper at all and is already in the tree today. These are forgotten, not excluded. Either add them to the corpus (an `exit`-shape leg, or route them through the existing primitives) or state this class explicitly in the header and the spec's residual, so the coverage claim matches what is actually covered.

**2. `scripts/check-gate-buckets.sh:109` — the command-start character class omits `then`/`else`/`elif`/`do`, contradicting the rule the header states.**

The regex is `(^|[;&|(){}])[[:space:]]*${p}[[:space:]]`, but the header at `:52-54` states the rule as "The primitive must sit at the start of a command — line start, or after `;`, `|`, `&`, `(`, `)`, `{` or `}`." A primitive following a shell keyword *is* at the start of a command and is silently dropped. Live proof: `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420`, `      else envfail "unexpected argument: $1"` — a refusal site the enumeration does not contain. I checked the whole corpus for this shape; today it is the only live call site affected, and it would be `not-a-gate` anyway, so nothing is currently misclassified.

**Consequence:** the harm is forward-looking and is exactly the failure mode #636 was filed against — a future `… ; then fail_milestone …` or `else ticket_refuse …` joins the lane unclassified and the guard stays green, while the header's stated exclusion list gives a reader no way to know it happened. Add the keywords to the class (or make the exclusion accurate in the header and the AC-8 residual).

**3. `scripts/check-gate-buckets.sh:300` — `exit "$violations"` truncates mod 256, so 256 violations exit 0.**

The doctor convention is inherited from `check-fail-open-shapes.sh`, but that guard's denominator is ~20 sites and can never reach 256. This one enumerates 305, so a count of exactly 256 is inside the reachable range (e.g. renaming or deleting a primitive orphans every site keyed to it at once — the `envfail` classes alone are ~132 sites across five files).

**Consequence:** the guard prints 256 `✗` lines to stderr and exits 0, and the CI step passes green on a register that describes nothing. That is a silent fail-open in the guard whose stated purpose is to prevent one. Clamp it — `exit $(( violations > 0 ? 1 : 0 ))`, or `exit $(( violations > 254 ? 254 : violations ))` if the count is worth preserving. Note this also resolves the collision where `exit 2` means both "environment refusal" (`:69`) and "exactly two violations".

---

## r2

2026-09-03T18:39:46Z → 2026-09-03T18:50:07Z. stderr empty.

I could not execute the guard in this environment (command execution is restricted here), so everything below is from reading the code plus targeted `grep` probes against the real corpus files. I verified enumerator/register coverage per primitive by hand where I could: `orchestrate-lean.sh` terminal slugs (49 sites, 29 rows, every slug claimed), `envfail` totals (57+23+21+16+15 = 132), `check-lean-chain.sh::note_violation` (18 sites / 18 rows), `::fail` (1/1). The CI wiring (AC-7), the `Guard-mass:` trailers (AC-10), and the `fail-open-sites.tsv` reconciliation (the new `printf … | grep -q` shapes are excluded by `check-fail-open-shapes.sh`'s `VAR_PRODUCER` filter, so no row is owed) all check out.

## Nits

1. `scripts/check-gate-buckets.sh:234` — the awk `FILENAME` comment cites "(g21) is the case" for the empty-rows-file scenario. That case is **g22** (`comments_only`); g21 is the empty-corpus case.
2. `scripts/check-gate-buckets-selftest.sh:20` — the header says "THE NEGATIVE DIRECTION (g17)". The negative cases are g18a–g18d; g17 is the missing-register case.
3. `scripts/gate-buckets.tsv` — the four `envfail` class rows each say "so 132 near-identical rows would add no classification". 132 is the corpus-wide `envfail` total, not any single class's count (lean-gate 57, operator-override 23, lean-evidence 21, orchestrate 16, chain 15). Each row asserts the aggregate as if it were its own.
4. `scripts/check-gate-buckets.sh:182-184` — "Pure bash on purpose: … a subprocess per row is what the batching below exists to remove", but `in_set "$rprim" "$(corpus_prims "$rfile")"` forks a subshell for the command substitution once per row anyway.
5. `scripts/check-gate-buckets.sh:170` vs `:297` — the row loop skips comments with `'#'*` against the raw key, while the verdict's row count uses `^[[:space:]]*\(#\|$\)`. An indented `#` line would be a "malformed row" to one and a comment to the other.
6. `scripts/check-gate-buckets-selftest.sh:212` — g13 captures `rc` and never reads it.

## Warnings

1. **`exit "$violations"` truncates mod 256.** `scripts/check-gate-buckets.sh:300`. The denominator here is 305 sites over 156 rows; a rename of a corpus file's primitive or a botched register edit can easily produce hundreds of violations, and exactly 256 or 512 exits **0** — CI green on a fully rotted register. `check-fail-open-shapes.sh` uses the same convention, but its denominator is single digits, so the precedent doesn't carry. Clamping (`exit $(( violations > 250 ? 250 : violations ))`) keeps the doctor convention and closes it.

2. **AC-5 direction 2 is a strict subset of direction 1.** `:195-200`. `in_set "$ryield" "$GATE_VOCAB"` can only be true when `$ryield != "-"`, so a single offending row emits both messages and counts **two** violations. Harmless for safety (direction 1 is the load-bearing one) but it double-counts the exit code.

3. **`GATE_VOCAB` is not guarded against emptiness the way `YIELD_VOCAB` is.** `:138-143`. The script explicitly envfails when `YIELD_VOCAB` is empty ("AC-5's safety arm would pass vacuously"), yet `:141-142` states that it is `OVERRIDE_GATES` — i.e. `GATE_VOCAB` — that binds AC-5's direction. If `OVERRIDE_GATES` is renamed or reformatted while `OVERRIDE_SCOPES` survives, direction 2 goes silently dead with no red. (Direction 1 still holds, which is why this is a warning and not a blocker.)

4. **`in_set` matches by glob, not by string.** `:145-148` uses `case " $2 " in *" $1 "*)`. A yield cell or key primitive containing `*`, `?` or `[` matches spuriously — e.g. a `gates-process` row with yield `*` passes AC-6's vocabulary check.

5. **`gate-buckets.tsv`: two `lean-evidence.sh::note_violation` rows overlap by prefix.** The row anchored `…reads 'verdict=${VERDICT_VALUE:-<none>}', n` is a strict prefix of the row anchored `…reads 'verdict=${VERDICT_VALUE:-<none>}', not 'verdict=approve' — freshness is`. The shorter anchor covers both sites. Same bucket, so no AMBIG red, but the register reads as a 16-row/16-site bijection when it isn't; the printed count (2 vs 1) is the only signal.

6. **The `terminal preflight-rejected 2` row's `why` overstates its own premise.** It claims "the one probe whose premise is an absent human exits at the resumable code above before this line". Per `orchestrate-lean.sh:630-634` the resumable exit fires only when the intake probe is the *sole* failure; intake-unqueued plus any other probe failure reaches line 634 and is dispositioned `gates-signal`. The disposition is still right (the run isn't resumable by an operator answer alone, which the code comment at :627-629 says outright) — the justification text is what's wrong.

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:109` — the enumerator misses refusal calls in reserved-word command position, and there is a live instance in the corpus today.**
   The recipe is `grep -nE "(^|[;&|(){}])[[:space:]]*${p}[[:space:]]"`. Shell command position also follows the reserved words `then`, `else`, `elif` and `do`, none of which are in the alternation. `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` — `else envfail "unexpected argument: $1"` — is a genuine refusal site that the recipe does not match (verified: it is absent from the primary grep's output while `:416` and `:529` are present). The header at `:52-54` states the rule as "the primitive must sit at the start of a command — line start, or after `;`, `|`, `&`, `(`, `)`, `{` or `}`", which presents the character list as *equivalent to* command position; it is not, and the discrepancy is not listed among the self-exclusions. **Consequence:** the "`--list` output IS the denominator" claim is false by one site now, and a future `then fail_milestone 3 "…"` or `else ticket_refuse "…"` — a real gate written in an idiom the corpus already uses — joins the lane unclassified with the guard staying green. That is precisely the rot AC-2 and AC-8 exist to make impossible, and AC-8's "a reader can tell an excluded surface from a forgotten one" is not met: this one reads as forgotten. Fix by extending the alternation (`(^|[;&|(){}]|\b(then|else|elif|do)[[:space:]])`) or, if the omission is deliberate, stating it in the header's exclusion list with the residual it leaves.

2. **`scripts/check-gate-buckets-selftest.sh:327` and `:333` — g18b and g18d assert conditions that can never be true, so both print `ok` without evaluating what they claim.**
   The `negatives` fixture's `orchestrate-lean.sh` is: line 1 shebang, line 2 `terminal() { launch_note terminal …; }`, line 3 `envfail() { terminal "$1" 2 "$2"; }`, line 5 `terminal preflight-rejected 2 …`.
   - g18b (`:327`) tests for a site at key `…::terminal`, **line 1** — the shebang. `terminal()`'s definition is on line **2**. The assertion is unreachable regardless of whether the definition exclusion works.
   - g18d (`:333`) tests for a site at key `…::envfail`, line 3. Line 3 can never be enumerated under that key: the primary regex requires whitespace after the primitive and line 3 has `envfail(`. The condition the label describes — that line 3 is excluded from the **`terminal`** enumeration by the whole-primitive-set `defs` rule, which is AC-3's explicit requirement — would need key `…::terminal`, line 3.
   **Consequence:** the two cases the file's own header calls the negative direction report passes for checks that never ran. The underlying definition-exclusion mutations happen to be caught by g1 (the green fixture goes red), so no production defect follows — but the suite claims coverage it does not have, and a fixture edit that shifted those lines would still print `ok`. Compounding this, **g18c (`:330`) is masked**: the `launch_note terminal` argument-position text sits on line 2, which the `defs` exclusion removes first, so dropping the command-position prefix from `:109` leaves g18c green — and I could find no other fixture line that would newly enumerate under that mutation, meaning the command-position rule named in blocker 1 is also entirely untested. Fix g18b to line 2, g18d to key `…::terminal` line 3, and move the argument-position text to a non-definition line so g18c has something to fail on.

---

## r3

2026-09-03T18:39:48Z → 2026-09-03T18:49:16Z. stderr empty.

## Summary

This is a well-built guard: the denominator-as-artifact posture is copied faithfully from `check-fail-open-shapes.sh`, the four red arms are genuinely independent, the safety arm is register-internal rather than proximity-based, and the selftest fixtures are real trees handed to the real guard. The `gates-signal` bucket is justified and the register's `why` cells generally name a mechanism rather than an opinion. Three things need fixing before merge.

## Acceptance criteria

| AC | Score | Note |
| --- | --- | --- |
| AC-1 | satisfied | closed enum checked (`unknown bucket`), `not-a-gate` `why` prefix checked, one-disposition enforced via `AMBIG` |
| AC-2 | **unsatisfied** | see Blocker 1 — the enumeration is not shape-complete over command position |
| AC-3 | satisfied | all five primitive sets declared; `terminal` exit-0 calls enumerated and dispositioned |
| AC-4 | satisfied | per-row covered count printed; zero-hit row reds |
| AC-5 | satisfied | both directions present (though direction 2 is subsumed — see W3); vocab read from `operator-override.sh` at run time |
| AC-6 | satisfied | `unwired — <reason>` form checked, existence of a ticket not checked |
| AC-7 | satisfied | `lint-and-selftests`, alongside `check-lockstep-pairs.sh` / `check-eval-model-identity.sh`; not `pr-gates` |
| AC-8 | **unsatisfied** | the reserved-word exclusion is real, undeclared, and unintended — a reader cannot tell it from a forgotten surface |
| AC-9 | satisfied | manifesto gains `gates-signal` + register pointer, no enforcement restated |
| AC-10 | satisfied | no corpus file edited; no new `\| grep -q` site (every one in the selftest is a `printf` producer, excluded by `VAR_PRODUCER`); `Guard-mass:` trailers present on all three commits |

## Warnings

**W1 — `exit "$violations"` wraps at 256, and this is the first guard whose denominator exceeds 255.** `scripts/check-gate-buckets.sh:300` follows the repo's unclamped doctor convention, which is fine at `check-fail-open-shapes.sh`'s ~20-site scale. Here the enumeration is 305 sites, so a register breakage producing exactly 256 (or 512) violations exits 0 and the CI step reads green while every `✗` line is on stderr. `exit $(( violations > 255 ? 255 : violations ))` preserves the convention and closes it. I'm flagging rather than blocking because the convention is inherited repo-wide, but this PR is what makes the wrap reachable.

**W2 — the "132" figure is restated as a per-row claim in four rows where it is a corpus-wide total.** The TSV header is correct: "the `envfail` classes … 132 sites, 6 rows." But the `why` cells on `lean-gate.sh::envfail`, `lean-evidence.sh::envfail`, `operator-override.sh::envfail` and `check-lean-chain.sh::envfail` each read "132 near-identical rows would add no classification", which reads as that row's own coverage. Four rows cannot each cover 132 of 132 sites. The printed per-row count will contradict the prose on every run.

**W3 — AC-5 direction 2 is fully subsumed by direction 1, so a single bad cell scores two violations.** `check-gate-buckets.sh` fires "Only gates-process may yield" whenever `rbucket != gates-process && ryield != "-"`, then fires "A row that yields IS gates-process" whenever `rbucket != gates-process && in_set "$ryield" "$GATE_VOCAB"`. No `OVERRIDE_GATES` value is `-`, so the second condition can never hold without the first. The more specific message is worth keeping, but `(g8)` presents it as an independent arm and it is not one; consider making it an `elif` so the count matches the defect count.

## Nits

- `corpus_prims` is invoked as `$(corpus_prims "$rfile")` — one subshell fork per register row (~186 on this tree) — directly under a comment reading "Pure bash on purpose: this runs once per register row, and a subprocess per row is what the batching below exists to remove." Hoisting the corpus into two parallel arrays outside the loop matches what the comment claims.
- The `trap 'rm -f "$COVERED_ROWS" "$SITES_F" "$PASS_OUT"'` is installed after all three `mktemp` calls, so a failure of the second or third leaks the earlier files.
- `in_set` expands its argument into a `case` pattern, so a yield cell or primitive containing `*`, `?` or `[` would match spuriously. No current value does; a `[[ " $2 " == *" $1 "* ]]` with the LHS quoted has the same problem, so the honest fix is a loop. Low priority.
- `scripts/check-gate-buckets.sh:297` uses GNU BRE alternation (`grep -cv '^[[:space:]]*\(#\|$\)'`). There is precedent in the tree (`tools/check-sweep-bound-selftest.sh:61`, `tools/mutation-sweep-selftest.sh:1199`) so the macOS bash-3.2 lane presumably tolerates it, but `grep -cvE '^[[:space:]]*(#|$)'` removes the question. Only the verdict line's row count depends on it — and `(g1c)` asserts that number exactly.

## BLOCKERS

**1. The enumerator misses refusals in command position after a shell reserved word, and one already exists in the corpus.**

*File:* `scripts/check-gate-buckets.sh:109` (recipe), header self-exclusion list at `:45–56`.

*Mechanism:* the recipe is `grep -nE "(^|[;&|(){}])[[:space:]]*${p}[[:space:]]"`. A command may also begin after `then`, `else`, `elif`, `do` or `!`, none of which are in that class, and none of which is followed by `^` or a delimiter. `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` is exactly that shape:

```
      else envfail "unexpected argument: $1"
```

There is no `;&|(){}` anywhere before `envfail` on that line, and `^[[:space:]]*` is followed by `else`, so no branch of the alternation matches. That site is absent from `--list`, absent from the denominator, and therefore never required to carry a row. I confirmed by running the exact recipe regex and its complement across all five corpus files: this is the only live instance today (`check-lean-chain.sh:386`, `lean-evidence.sh:218` and the `orchestrate-lean.sh` hits are all comment lines, which are excluded on purpose).

*Consequence:* the invariant the whole slice exists to establish — "a new gate joining the lane unclassified reds CI" — does not hold for this shape. A future `else fail_milestone 3 "…"` or `then ticket_refuse "…"` lands unenumerated, unclassified, and green, which is precisely the silent-rot failure #636 was filed against. It is also an AC-8 failure: the header declares three self-exclusions (comments, definition lines, non-command positions) and this is none of them — the header explicitly says "The primitive must sit at the start of a command," which `else envfail` does. Because the exclusion is undeclared, a reader cannot tell it from a forgotten surface, and the "output IS the denominator" claim at `:31–37` is inaccurate as written. Widening the class to include the reserved words (and re-checking the definition-line exclusion against the widened set) restores it; the fix must land with `lean-gate.sh:420` dispositioned in the register.

**2. `(g18d)` — the case written for the "exclusion is by the file's whole primitive set" rule — asserts a condition no implementation can violate.**

*File:* `scripts/check-gate-buckets-selftest.sh:333`.

*Mechanism:* the case checks that key `$OL::envfail` does not appear at line 3 of the fixture. Line 3 is `envfail() { terminal "$1" 2 "$2"; }`, and the behavior under test — stated in its own `ok` message and in the guard header at `:48–51` — is that this line must not be enumerated as a **`terminal`** site. The key checked is the wrong one: `envfail(` is never followed by `[[:space:]]`, so `$OL::envfail` can never be emitted for that line under any variant of the recipe, and the assertion is unfalsifiable.

*Consequence:* the specific regression it names goes untested. Narrow `defs` from the file's whole primitive set to just `$p` — the exact edit the header warns against — and line 3 is enumerated as `$OL::terminal` at line 3, yet `(g18d)` still reports `ok`. (`(g1)`'s baseline fixture catches that mutant via an `UNCLASSIFIED` red, so the guard is not defenceless, but the case advertised as pinning it contributes nothing and would survive a mutation sweep.) The fix is to check `$OL::terminal` at line 3.

**3. `(g18b)` asserts against the wrong line and is likewise vacuous.**

*File:* `scripts/check-gate-buckets-selftest.sh:327`.

*Mechanism:* it checks that no `$OL::terminal` site exists at **line 1** of the fixture. In `new_fixture` (`:57`, `:73–80`) line 1 is the shebang `#!/usr/bin/env bash`; `terminal()`'s definition is at line **2**. A shebang can never be a `terminal` site, so the predicate is a tautology.

*Consequence:* the `ok` message claims "terminal()'s own definition line is not enumerated" while nothing about that line is examined. The behavior happens to be covered incidentally by `(g18c)` — which greps the `--list` output for `launch_note terminal`, text that only appears on the definition line — so this is a narrower gap than Blocker 2, but the case as written is a false evidence claim in a suite whose header advertises it as pinning the negative direction. Change `$2 == 1` to `$2 == 2`.

