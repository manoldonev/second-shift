# C2-a — ablation arm `U-5`: lines 48–55 removed

One arm of the leave-one-out ablation registered at
[`docs/skill-ablation-addendum.md`](../../../skill-ablation-addendum.md) §C, run 2026-09-03
against sample **C2-a** (PR #654 @ `cfba102`). The SKILL text supplied to the session is
`plugins/dev-pipeline/skills/review-lean/SKILL.md` at `8d5d0897` with **lines 48–55 deleted** —
unit `U-5`, checklist step 5, the Review step — `review-lead`, prior findings, per-`AC-n` scoring, `approve` iff no blockers, do not soften. Registered reach: **in-reach**.
Everything below each `## r<n>` heading is that run's output verbatim.

## The realised invocation

```bash
cd /private/tmp/c2b-748/clone            # throwaway clone, detached at cfba102
printf '%s' "$(cat prompts/U-5.txt)" \
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
| r1 | `0` | 423651 B, 318 lines, sha256 `81fa4b7ca6c9996e…` | exit 0 — `COMPLETE` | 1 | 7 Bash,  23 Grep,  5 Read | **0** |
| r2 | `0` | 404368 B, 421 lines, sha256 `99c5c7bb8260c4a8…` | exit 0 — `COMPLETE` | 1 | 18 Bash,  11 Grep,  5 Read | **0** |
| r3 | `0` | 417519 B, 449 lines, sha256 `4ae926e6adbebc60…` | exit 0 — `COMPLETE` | 1 | 15 Bash,  31 Grep,  5 Read | **0** |

Only an exit-0 `COMPLETE` capture is scored. The last column is the ablation's own integrity
check: the clone keeps `plugins/` in the working tree, so a session that read the unablated
`review-lean/SKILL.md` off disk would defeat the line-range ablation. It is counted per run
rather than assumed away.

---

## r1

2026-09-03T18:39:38Z → 2026-09-03T18:46:20Z. stderr empty.

I reviewed the guard, the register, the selftest, and cross-checked both against the actual corpus files. I couldn't execute the guard (bash execution is blocked in this session), so everything below is derived by reading the code and grepping the corpus with the guard's own regexes.

The design is sound and the selftest is unusually thorough — the `FILENAME` vs `FNR == NR` fix (g22), the empty-denominator case (g21), and the negative-direction cases (g18a–d) all pin things that matter. Two findings block.

## Nits

1. `scripts/gate-buckets.tsv:214` — the `usage-` row's `why` says "the nine `usage-*` slugs". There are **nine sites but eight slugs** (`usage-max-rounds` appears at `orchestrate-lean.sh:373` and `:374`). The sibling row on the same line correctly says "seven `env-*` slugs", which is both count and slug count. Minor, but the register's prose is the thing a reader trusts over the code.

2. `scripts/check-gate-buckets.sh:170` vs `:297` disagree on what a whitespace-only register line is. The row loop's skip is `case "${rkey:-}" in ''|'#'*)` — with `IFS=$TAB`, a line of spaces yields `rkey="   "`, which is neither empty nor a comment, so it falls through and reds as `malformed row`. The verdict-line counter at `:297` (`grep -cv '^[[:space:]]*\(#\|$\)'`) treats the same line as not-a-row. Harmless today, but the two readings of "blank" should be one.

3. `scripts/check-gate-buckets.sh:161-167` — the `trap` is armed after all three `mktemp` calls, so a failure on the second or third leaks the earlier temp files before `envfail` exits.

## Warnings

1. **`scripts/check-gate-buckets.sh:198-200` is dead as an independent arm.** `GATE_VOCAB` is `intake-unqueued spec-open-region`; `-` is not in it. So `in_set "$ryield" "$GATE_VOCAB"` can only be true when `$ryield != "-"`, which means the check at `:195-197` has already fired for the same row. Direction 2 can never fire alone — it adds a second violation and a second message for one defect, and never catches anything direction 1 missed. The selftest's `(g8)` is billed as "AC-5 direction 2" and asserts only on the message string, so it passes without demonstrating independence. AC-5's substance is enforced; this is redundancy, not a hole.

2. **`exit "$violations"` at `:300` can wrap to 0.** The commit message puts the denominator at 305 enumerated sites, which is past the 8-bit exit space. A tree state producing exactly 256 or 512 violations exits 0 and the CI step at `.github/workflows/ci.yml:165` reads green. `check-fail-open-shapes.sh` established this convention against a much smaller denominator; this guard is the first to exceed it. Clamping to e.g. `exit $(( violations > 200 ? 200 : violations ))` costs nothing and preserves the doctor convention.

3. **Two byte-identical rows are not detected.** The AMBIG arm at `:247-251` counts *distinct* buckets, so duplicate rows agreeing on the bucket both accumulate hits and neither reds. The register can silently carry a duplicate; nothing in AC-1/AC-4 forces this, but "one row per enumerated site" (AC-4) is unenforced in that direction.

## BLOCKERS

**1. The enumerator silently drops refusal sites in command position after a shell keyword, and the register's central "the output IS the denominator" claim is therefore false on the current tree.**

File: `scripts/check-gate-buckets.sh:109` (with the self-exclusion list at `:45-54`).

Mechanism: the recipe is `grep -nE "(^|[;&|(){}])[[:space:]]*${p}[[:space:]]"`. A primitive is only enumerated at line start or after `;`, `&`, `|`, `(`, `)`, `{`, `}` — the `[[:space:]]*` cannot consume an intervening `then` / `else` / `do` / `elif`. `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` is exactly that shape:

```
      else envfail "unexpected argument: $1"
```

That line contains none of the seven command separators before `envfail`, and `^[[:space:]]*` stops at `else`. It is a live refusal call and it is not in the denominator. I checked all five corpus files for this shape with the guard's own alternation; `lean-gate.sh:420` is the only current instance, and because `lean-gate.sh::envfail` is a single whole-class `not-a-gate` row, nothing is misclassified *today*.

Consequence: the same shape written as `else fail_milestone 3 "…"`, `then terminal build-idle 1 "…"` or `else note_violation "…"` produces an unclassified gate that the guard reports as green — the precise failure the register exists to prevent, and the one `(g2)` claims to make impossible. It also fails two stated criteria: AC-3's "Every exclusion is stated in the script header" and AC-8's "A reader can tell an excluded surface from a forgotten one." The header declares three exclusions (comments, definition lines, non-command positions), and the third is described as *keeping* argument position out — it does not say that keyword-led command position is also out, because that was not intended. This is a forgotten surface, not an excluded one. Fix by extending the character class to admit the reserved words (e.g. `(^|[;&|(){}]|\b(then|else|elif|do)\b)`), adding a `(g18e)` case pinning it, and — either way — stating the residual in the header. Note the fix will change the denominator, so the register needs the new row(s).

**2. `scripts/gate-buckets.tsv:58` classifies a gate whose bucket the parent epic already settled differently, with no reconciliation.**

File: `scripts/gate-buckets.tsv:58`, against `docs/prose-blocker-triage.tsv:40`.

Mechanism: the new row disposes of `lean-evidence.sh::note_violation` at anchor `note_violation "no committed verdict record (a file named *-$KEY$LEAN_VERDICT_SUFFIX)` as **`gates-signal`**, with the why "the fact is objective: a committed verdict record for this key exists or it does not." That is `arm_verdict`'s absent-record arm at `plugins/dev-pipeline/skills/build-lean/lean-evidence.sh:774`. The pre-existing triage row records the same gate under the enforcer key `scripts/check-lean-chain.sh::verdict-record` and states: "The all-dark rule, settled KEEP / **gates-llm** by the parent epic. **Its bucket is pre-settled**, its disposition was not: an absent verdict record is already a violation at the merge boundary, which is the gate analog."

Consequence: the repo now carries two recorded, conflicting buckets for one gate, which is AC-1's "exactly one disposition" violated at repo scope rather than register scope — and the guard cannot see it, because it only checks the register against itself. The plan's Decision Ledger adopts `prose-blocker-triage.tsv`'s key format explicitly (D-2) and records a departure for a much smaller conflict (D-6, the ticket's stale counts), so the omission here is not a pattern the PR is otherwise willing to leave open. It is also substantively arguable, not just bookkeeping: an absent verdict record means the independent review never ran, which is the self-approval premise `gates-llm` names, and `review-lean` step 5c leans on exactly that reading ("`check-lean-chain.sh` treats an absent verdict record as already a violation, so a hand-back cannot merge"). Both buckets are never-yield, so there is no runtime waivability consequence — the defect is that the PR's whole deliverable is *the statement of which gate is which*, and this one contradicts the repo's existing statement silently. Resolve it either way, but resolve it: correct the row, or record a departure saying the parent epic's settlement is superseded and why.

---

## r2

2026-09-03T18:39:40Z → 2026-09-03T18:49:25Z. stderr empty.

I reviewed by auditing the enumerator's recipe against the real corpus (the shell sandbox here refuses to execute the guard, so I reproduced its grep recipe with `rg` and hand-traced the awk pass and the fixture arithmetic).

The design is sound and unusually well-argued: `gates-signal` is the right answer to a non-total predicate, the safety arm being register-internal (a yield cell naming an `OVERRIDE_GATES` value forces `gates-process`) is the correct place for it, reading the vocabulary from `operator-override.sh` instead of copying it is right, and the batched awk pass is correct — `FILENAME ==` instead of `FNR == NR` genuinely fixes the empty-rows-file hole, and the distinct-bucket set is counted as it is built. AC-7 checks out: the step is in `lint-and-selftests`, which carries no `if:`. I verified the fixture arithmetic independently — 10 sites across the 5 fixture files, matching g1c's exact-count assertion.

## Warnings

**W1 — `check-gate-buckets-selftest.sh:327` and `:333`: the two dedicated negative cases for the definition exclusion are misaimed.**
g18b asserts `$OL::terminal` has no site at line **1**, but `terminal()`'s definition is at fixture line **2** — and line 2 cannot match the call pattern anyway (`terminal(` has no trailing whitespace), so the assertion is unfalsifiable twice over. g18d is labelled "excluded from the TERMINAL enumeration too — the exclusion is by the file's whole primitive set", but the key it checks is `$OL::envfail` at line 3; the behavior AC-3 singles out is `$OL::terminal` at line 3. As written it only re-tests the trivial same-primitive case. Tracing the fixture, OL line 3 (`envfail() { terminal "$1" 2 "$2"; }`) is the *only* line the `defs` filter actually removes anywhere in the fixture, and neither named case covers it. The mutant is still killed — the site would land as UNCL and red g1 — so this is mislabelled coverage rather than a hole, but the suite does not test what these two lines claim.

**W2 — `check-gate-buckets.sh:169`: `IFS="$TAB" read` collapses runs of tabs.** Tab is IFS whitespace, so consecutive tabs are one delimiter and an empty middle cell shifts every later field left rather than being read as empty. Nothing today is affected (every row uses `-`), and each shift happens to drop the trailing field and trip the malformed arm — which is why g12b passes, but for the wrong reason: the guard is detecting a missing 5th field, not an empty bucket cell. A 6-column row with one empty middle cell reads as a well-formed 5-column row with every value shifted one place.

**W3 — the register silently departs from a bucket the repo already recorded.** `docs/prose-blocker-triage.tsv:40` names enforcer `scripts/check-lean-chain.sh::verdict-record` and says its bucket was "settled KEEP / gates-llm by the parent epic". The new register dispositions the enforcing site — `lean-evidence.sh::note_violation` "no committed verdict record" — as `gates-signal`. Both readings are defensible (prose rule vs. gate site), but this register's whole claim is to be the one place that says which gate is which, and D-6 shows the slice was willing to reason explicitly about whether a departure was owed. This one gets neither a reconciliation nor a ledger row.

**W4 — the bucket semantics are now stated three times with nothing binding them:** `docs/pipeline-manifesto.md:134-143`, `scripts/gate-buckets.tsv:9-20`, `scripts/check-gate-buckets.sh:12-27`, in near-identical prose. D-4 refuses a third copy of the `OVERRIDE_GATES` enum precisely because a copy owes a lockstep marker; the same argument applies to the definitions a future editor is most likely to amend in exactly one of the three.

## Nits

- `check-gate-buckets.sh:300` — `exit "$violations"` truncates mod 256. Emptying the register on this tree yields 305 violations → exit 49 (still red), but a count landing on 256 or 512 exits 0. It is the repo-wide doctor convention, not this PR's to change; noting only that the exposure scales with the denominator.
- `gate-buckets.tsv` — "132 near-identical rows would… drown the register" is pasted verbatim into all five per-file `envfail` rows. 132 is the corpus-wide total; `lean-evidence.sh` has ~22 and `check-lean-chain.sh` ~15. It reads as a measured per-row figure.
- `check-gate-buckets.sh:208` — the `not-a-gate` `why` check is prefix-anchored only, so `usage errors happen sometimes` passes.
- `docs/pipeline-manifesto.md:145` — the pointer says the register "declares one bucket per refusal site", but a reader following the link meets a fourth value (`not-a-gate`) the manifesto never mentions.
- `check-gate-buckets.sh:163,165` — the second and third `mktemp` failures `envfail` before the EXIT trap at :167 is installed, leaking the temp file(s) already created.

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:109` — the enumerator's command-boundary class misses a refusal call that follows a shell keyword, and the corpus already contains one.**

   The recipe requires the primitive to sit immediately after line start or one of `; & | ( ) { }`:
   ```
   grep -nE "(^|[;&|(){}])[[:space:]]*${p}[[:space:]]" "$ROOT/$f"
   ```
   A call in command position after `then`, `else`, `do` or `elif` on the same line has none of those characters before it. `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` is exactly that:
   ```
         else envfail "unexpected argument: $1"
   ```
   It is a live `envfail` refusal site in a declared corpus file, and the enumeration does not contain it. (I swept all five corpus files for the shape — `[^;&|(){}[:space:]][[:space:]]+<prim>[[:space:]]` — and line 420 is the only non-comment hit today, so the tree is green solely because nothing is *mis*classified: the missed site would be dispositioned `not-a-gate` by the class row anyway.)

   The consequence is that the guard's central claim is false on the tree it ships against. The header states "THE DENOMINATOR IS THIS SCRIPT'S OWN OUTPUT… `--list` prints the enumeration, that output IS the denominator by definition", and AC-2 rests on it, but the enumeration is provably short of the real site count (305 enumerated, ≥306 present). Worse for AC-8, the self-exclusion list at `:45-56` does not name this exclusion — it describes the third exclusion as "The primitive must sit at the start of a command", which is precisely what line 420 does. A reader therefore *cannot* tell this excluded surface from a forgotten one, which is the property AC-8 exists to guarantee. The live failure mode: a future `else fail_milestone …` or `then ticket_refuse …` joins the lean lane unclassified, `check-gate-buckets.sh` stays green, and the "an unclassified one fails CI" promise the manifesto now makes at `docs/pipeline-manifesto.md:146` does not hold — the exact regression #636 was filed against.

   One caution on the fix: it must be keyword-specific, e.g. `(^|[;&|(){}]|[[:space:]](then|else|do|elif)[[:space:]])`, not a general "any preceding whitespace" widening. Widening to whitespace would start enumerating `launch_note terminal "…"` inside `terminal()`'s own body, which selftest g18c pins as a non-site. Either fix the recipe or, if the keyword form is judged out of scope, state it in the header's exclusion list *and* add the register row it implies — but leaving it unstated is what makes this a blocker rather than a nit.

---

## r3

2026-09-03T18:39:42Z → 2026-09-03T18:49:03Z. stderr empty.

I reviewed the guard, the register, the selftest, and the CI wiring against the spec's AC-1…AC-10, and cross-checked the enumerator's recipe against the five corpus files it ships against.

A note on method: script execution was denied in this session, so I could not run `check-gate-buckets.sh` or its selftest. Everything below is established statically or by targeted `grep` over the corpus, and I've stated the mechanism for each finding so it can be re-derived.

## What holds up

- **CI placement (AC-7)** is right: the step lands in `lint-and-selftests` beside `check-lockstep-pairs.sh` / `check-eval-model-identity.sh`, not `pr-gates`.
- **AC-3's primitive sets match the tree.** `lean-gate.sh` defines exactly `envfail`, `ticket_refuse`, `fail_obligation`, `fail_milestone`, `block_milestone` (:379, :676, :1583, :1751, :1791); `check-lean-chain.sh` exactly `fail`, `envfail`, `note_violation`; `operator-override.sh` exactly `envfail`. No declared-but-unscanned refusal helper.
- **The `FILENAME`-over-`FNR == NR` fix is correct and load-bearing.** With an all-comment register `COVERED_ROWS` is empty, `FNR == NR` would have loaded the denominator's own first record as a row; `FILENAME` cannot. `(g22)` cases it.
- **The AMBIG arm is genuinely independent** of the UNCL arm, and counting `nb` as the set is built (rather than splitting a separator string) avoids the off-by-one the commit message describes.
- **No tabs in any corpus file**, so `awk`'s `$3` site-text field is never truncated — the anchor `index()` comparison is safe as written.
- The **`| grep -q` shapes** in the new files are all either direct file greps or `printf …| grep -q`, which `check-fail-open-shapes.sh`'s `VAR_PRODUCER` arm already excludes. No `fail-open-sites.tsv` row is owed (AC-10).
- `Guard-mass:` trailers are present on all three commits.

## Warnings

**W1 — the enumerator's recipe is not exercised for the exclusion AC-3 singles out; `(g18d)` asserts the wrong key.** `scripts/check-gate-buckets-selftest.sh:387`. The invariant AC-3 and the guard header both call out is that `orchestrate-lean.sh`'s `envfail() { terminal "$1" 2 "$2"; }` must not be enumerated as a **`terminal`** site. The fixture reproduces that line at `$OL` line 3, but the assertion looks for `$OL::envfail` at line 3 — a key that can never appear there, because `envfail(` has no whitespace after the name and so never matches the site regex at all. Weaken `defs` to a per-primitive exclusion and `(g18d)` still passes; only `(g1)`'s baseline catches it, incidentally. The assertion should be `k="$OL::terminal"`.

**W2 — `(g18b)` is vacuous twice over.** `scripts/check-gate-buckets-selftest.sh:383`. It asserts no `$OL::terminal` site at line **1**, which is the shebang; `terminal()`'s definition is line **2**. And line 2 never matches the site regex regardless (`terminal` is followed by `(`, not whitespace), so the case would pass with the definition exclusion deleted entirely.

**W3 — the register contradicts a bucket an earlier register recorded as settled, with no DEPARTURE.** `docs/prose-blocker-triage.tsv:40` dispositions the enforcer `scripts/check-lean-chain.sh::verdict-record` — the all-dark rule's gate analog, "an absent verdict record is already a violation at the merge boundary" — as "settled KEEP / **gates-llm** by the parent epic. Its bucket is pre-settled." The corresponding refusal site in the new register is `gates-signal` (`scripts/gate-buckets.tsv:58`). Both never yield, so nothing behaves differently, but #636's entire deliverable is the classification, and two registers in this repo now answer the same question differently. Either follow the pre-settled bucket or record the departure in the spec's ledger.

**W4 — `operator-override.sh::envfail`'s `why` opens with one `not-a-gate` reason while describing two.** `scripts/gate-buckets.tsv:224`: "environment refusal — … covers both halves — a malformed invocation and an unusable environment". A malformed invocation is the enum's `usage error`. The mechanical check only reads the opening token, so it passes; the row is nonetheless the one place the closed set is collapsed rather than chosen. The sibling `orchestrate-lean.sh` rows split exactly this distinction into `envfail env-` / `envfail usage-`.

**W5 — exit code truncation.** `scripts/check-gate-buckets.sh:300`, `exit "$violations"`. This is `check-fail-open-shapes.sh`'s inherited convention, but that guard's denominator is a handful of sites while this one's is 305: 256 violations exits 0 and CI reads green. Capping at, say, `exit $(( violations > 250 ? 250 : violations ))` keeps the doctor convention without the wrap.

## Nits

- `scripts/check-gate-buckets.sh:234` cites "**(g21)** is the case" for the all-comment register; that is `(g22)` in the selftest — `(g21)` is the empty-denominator case. The selftest header's "THE NEGATIVE DIRECTION (**g17**)" is likewise stale: the negative cases are `g18a`–`g18d`, and `g17` is the missing-register case.
- `in_set` (`:145`) tests membership with `case " $2 " in *" $1 "*)`, so a `$1` containing `*`, `?` or `[` glob-matches. It cannot produce a green run today (awk's key comparison is exact, so such a row falls out as zero-hit drift), but the membership test is not the literal one it reads as.
- `trap` (`:167`) is installed after the third `mktemp`; a failure of that third one `envfail`s and leaks the first two.
- A non-`gates-process` row whose yield names an `OVERRIDE_GATES` value trips both `:195` and `:198`, counting two violations for one cell. `(g8)`'s fixture is exactly this shape.
- `IFS="$TAB" read` (`:169`) collapses adjacent tabs — tab is IFS whitespace — so an empty interior cell shifts every later field left and is reported as "malformed row" rather than as an empty cell. Fail-closed, and `(g12b)` passes, but for a different reason than its `ok` message states.

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:109` — the denominator omits live refusal sites in command position after a shell reserved word, and one such site exists in the corpus today.** The site recipe is `(^|[;&|(){}])[[:space:]]*${p}[[:space:]]`: the primitive must be preceded by line start or one of `; & | ( ) { }`. A command that begins after `then`, `else`, `do`, `elif` or `!` on the same line matches none of those. `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` is `      else envfail "unexpected argument: $1"` — a live call to a primitive `CORPUS` declares for that file, in command position, on a non-comment non-definition line — and it is not enumerated. A complement search over all five corpus files (`[^;&|(){}[:space:]][[:space:]]+<prim>[[:space:]]`) returns this line and nothing else that is not a comment or a definition, so it is the only current instance.

   Consequence, in two parts. Today it is benign: the missed site is an `envfail`, which the class row dispositions `not-a-gate` anyway, so no gate is misclassified. But the guard's stated contract is falsified — `scripts/check-gate-buckets.sh:73` claims "`--list` prints the enumeration, that output IS the denominator by definition", `:88` claims the primitive "must sit at the start of a command" (line 420 *is* the start of a command; the reserved-word list is simply incomplete), and `:91` names the newly-declared-primitive case as **the** residual a shape enumerator cannot close, so AC-8's "a reader can tell an excluded surface from a forgotten one" does not hold for this one. Going forward the mechanism is the exact fail-open #636 was filed against: a future `else fail_milestone …`, `then ticket_refuse …` or `do terminal …` joins the lane with no bucket, no row, and a green CI — and nothing in the selftest would catch the regression, because the negative-direction block (`g18a`–`g18d`) cases only comments, definition lines and argument position, never a reserved-word-preceded command position.

   Fix is small: extend the leading-context alternation to the reserved words (`(^|[;&|(){}]|\b(then|else|elif|do|in)\b|!)[[:space:]]*`), or invert the test to "not preceded by a word character or a quote", then add the `else envfail` line to the fixture's `$LG` and a `(g18e)` case pinning that it *is* enumerated. Either way the register needs no new row — the existing `lean-gate.sh::envfail` class anchor `envfail ` already covers it — so the change is enumerator-and-test only.

