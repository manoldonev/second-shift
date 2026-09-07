# C2-a — CONTROL, with `review-lead` loaded

The control arm of the re-measurement registered at
[`docs/skill-ablation-addendum-2.md`](../../../skill-ablation-addendum-2.md), run 2026-09-06/07
against sample **C2-a** (PR #654 @ `cfba102`). The SKILL text supplied to the session is
`plugins/dev-pipeline/skills/review-lean/SKILL.md` at `8d5d0897`, **all 127 lines, unablated** —
identical to arm 2b's control. Registered n=3. Everything below each `## r<n>` heading is that run's
output verbatim.

**This arm exited `no basis` — construction not delivered.** `review-lead` was available in every
run and invoked in **none**. See the adjudication below, and
[`README.md`](README.md) for the apparatus.

## The realised invocation

```bash
cd /private/tmp/c2b803/clone            # throwaway clone, detached at cfba1022
printf '%s' "$(cat prompts/control.txt)" \
  | env -u CLAUDE_CODE_SESSION_ID -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT \
      -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_BRIDGE_SESSION_ID -u CLAUDE_CODE_MESSAGING_SOCKET \
      -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_SSE_PORT -u CLAUDE_EFFORT -u CLAUDE_PID \
      -u RUN_ID -u LEAN_RUN_MODEL -u LEAN_ATTEND_MODE \
      caffeinate -dims claude -p --model opus --setting-sources '' --allowedTools "Read,Grep,Glob" \
        --output-format stream-json --verbose \
        --plugin-dir /private/tmp/c2b803/review-toolkit
```

Arm 2b's §C invocation, with **one addition**: `--plugin-dir`. The plugin is the *shipping*
`plugins/review-toolkit` — git tree `549b0d1768`, copied verbatim to a scratch path — and
explicitly **not** the clone's own copy, whose `review-lead` predates #730 and carries no rule
naming R-3. Addendum 2 registers that choice and the nonce probe that verified the flag governs.

The prompt is the full unablated SKILL text, then
[`c2-review/prompt-template.txt`](../c2-review/prompt-template.txt) verbatim, then the pinned diff
`dfd68a47..cfba1022` — the assembly §C registers, unchanged. sha256 of the assembled prompt:
`e8b0c82b13e84f6f2b5b2e668254ab29dde0ad2d828a42b1c9b7994416337269`.

`caffeinate -dims` wraps each run (this machine sleeps at one minute idle) and the batch was
launched detached with `start_new_session`, which is the #795 mitigation D-10 registers: arm 2b's
first control batch died as children of a session that ended its turn.

## Apparatus

| run | rc | capture | `classify-capture.sh` | `result` events | turns | wall | tool calls | Bash calls denied | tool inputs naming `review-lead` | tool inputs naming `review-lean` |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| r1 | `0` | 429190 B, 408 lines, sha256 `1dc8e82adff07b6b…` | exit 0 — `COMPLETE` | 1 | 34 | 504 s | 16 Grep, 14 Bash, 3 Read | 5 | **0** | **0** |
| r2 | `0` | 373490 B, 417 lines, sha256 `bdd0844b5ce82d15…` | exit 0 — `COMPLETE` | 1 | 45 | 514 s | 27 Bash, 11 Grep, 6 Read | 4 | **0** | **0** |
| r3 | `0` | 374521 B, 371 lines, sha256 `bf231415ef185cfb…` | exit 0 — `COMPLETE` | 1 | 32 | 471 s | 18 Grep, 9 Bash, 4 Read | 5 | **0** | **0** |

Only an exit-0 `COMPLETE` capture is scored; all three qualify, so there are **zero indeterminate
runs** and no arm is short a replicate. Raw captures are not committed — no raw capture in this
study is, scored or not — so what survives in-repo is the measurement, hashed so the reading can be
repudiated on a machine that still has them.

`tool inputs naming review-lean` is arm 2b's integrity column: the clone keeps `plugins/` on disk,
so a session that read the unablated SKILL off disk would defeat a line-range ablation. It is 0 in
every run. `tool inputs naming review-lead` is this arm's own counterpart, and it is the column the
arm turns on.

## The construction was delivered as an availability, and never used

Every run's `system`/`init` event lists the plugin's whole surface:

- `slash_commands` carries `review-toolkit:review-lead`, `review-toolkit:reviewer-baseline` and
  `review-toolkit:mutation-review`;
- `agents` carries all 18 `review-toolkit:*` reviewer agents;
- `tools` carries `Skill` and `Task`, so both the invocation route and the fan-out route were open.

No run used either. Across the three captures: **0 `Skill` tool calls, 0 `Task` dispatches, 0 tool
inputs naming `review-lead`.** Each session reviewed the diff directly with `Grep`, `Bash` and
`Read`, exactly as arm 2b's plugin-free control did.

Under the asymmetry addendum 2 registers **before any run** — for the control, invocation is what
proves the construction was delivered — 0 of 3 is below the 2-of-3 bar, and the arm exits
**`no basis` — construction not delivered**. No unit is scored. The U-5 and R-3 ablated arms were
**not run**, per §C's rule that a void control does not proceed to the ablation runs.

## The finding-void condition, adjudicated separately — it cleared

The two void conditions are independent, and recording only the one that failed would hide that the
review half of the construction behaved normally. Against the frozen C2 hit rule — the finding must
name the **same mechanism and the same consequence**; the same file with a different defect is a
miss — the control reproduced the C2-a ground-truth blocker in **2 of 3** runs, clearing the ≥2-of-3
bar:

- **r1 — HIT.** Blocker 2 names `scripts/check-gate-buckets.sh:109`, the class
  `(^|[;&|(){}])`, the omitted reserved words (`then`, `else`, `elif`, `do`), the live
  `lean-gate.sh:420` `else envfail` site, and the denominator consequence.
- **r2 — HIT.** Blocker 1, the same mechanism and the same consequence, and it goes further:
  it replays the regex over the corpus and reports `lean-gate.sh:420` as the only live site dropped.
- **r3 — MISS.** Its single blocker names the same file at a different line (`:300`) and a
  different defect — `exit "$violations"` wrapping modulo 256, so exactly 256 violations report
  success. Quoted so the call can be repudiated rather than taken on trust:

  > **`scripts/check-gate-buckets.sh:300` — `exit "$violations"` wraps modulo 256, so exactly 256
  > violations report success.**

  Naming the same file with a different defect is a miss under
  `docs/skill-ablation-pre-registration.md`:147-152. It is scored a miss.

So the finding-void condition **cleared at 2 of 3** while the construction-delivery condition
**failed at 0 of 3**. The arm's exit is owed entirely to the second.

## `--allowedTools` — recorded, per OR-3

`--allowedTools "Read,Grep,Glob"` did **not** restrict the tool set: the `init` event lists the full
set including `Bash`, `Write`, `Edit`, `Task` and `Skill`, and every run executed `Bash`. That
reproduces #796's finding on CLI 2.1.241, now on 2.1.263.

Separately — and *not* what #796 recorded — the default permission mode denied individual `Bash`
invocations: 5, 4 and 5 per run, all of the form *"This command requires approval"*. Read-only
shapes (`git log`, `sed -n`) ran; executing a repo script (`bash scripts/check-gate-buckets.sh`)
and some `grep` pipelines did not. Nothing was changed to force parity with arm 2b's realised
condition, per OR-3's default.

This is not incidental to r3's miss. r3's own output says so:

> Note that `bash scripts/check-gate-buckets.sh` required approval in this session, so I verified
> the enumeration by reproducing the guard's own grep patterns rather than by executing it.

Arm 2b's captures are not committed, so whether its control met the same denials cannot be checked
from this repo. It is recorded as observed here, not as a difference.

---

## r1

Started 2026-09-06T23:24:29Z. `stderr` empty. `review-lead` **not invoked**.

I reviewed the guard, the register, the selftest, and cross-checked both against the five corpus files in this checkout. (Script execution is blocked in this session, so the dynamic assertions below are derived by reading the enumerator's regex against the actual source lines, which I quote.)

## Summary

The design is sound and the guard is genuinely self-checking: denominator-as-artifact, four independent disagreement arms, a register-internal safety arm in both directions, and a selftest that points a case at the real tree (g0) rather than only at fixtures. The batched awk pass and its `FILENAME`-over-`FNR == NR` rationale are correct — the empty-rows-file trap is real and the comment explains it accurately.

Two things block: one is a substantive misclassification in the register, one is a hole in the enumerator that is live in the tree today.

## Warnings

1. **`scripts/gate-buckets.tsv` — the only row that grants a wired yield is anchored on a generic shape.** The `spec-open-region` row's anchor is `fail_milestone 1 "$reason"; return $?; }`, and `lean-gate.sh:3451` is literally that line — the message is a bare variable. Any future `fail_milestone 1 "$reason"; return $?; }` written anywhere in that file silently inherits `gates-process` + a *wired* operator override. AC-4's per-row count is the only signal, and nothing reds. This is the one row where a loose anchor is qualitatively different from a loose `not-a-gate` `envfail` class. Cheap fix: anchor on `[ -z "$reason" ] || { fail_milestone 1 "$reason"`, which is unique.

2. **`scripts/check-gate-buckets.sh:300` — `exit "$violations"` wraps at 256.** With a 305-site denominator, a register state producing exactly 256 violations exits 0 and the CI step reads green. `check-fail-open-shapes.sh` uses the same doctor convention, so this is inherited, but this is the first guard in the tree whose denominator makes the wrap reachable at all. Consider `exit $(( violations > 250 ? 250 : violations ))`.

3. **`scripts/check-gate-buckets.sh:195-200` — AC-5's two arms double-count.** Direction 2 is a strict subset of direction 1 (`-` is not in `GATE_VOCAB`), so a `gates-llm` row whose yield cell names `spec-open-region` fires both `fail` calls and reports 2 violations for one cell. Harmless for the verdict; the count is the exit code, so it isn't free.

4. **`scripts/gate-buckets.tsv` — `check-lean-chain.sh::envfail`'s class `why` under-describes two of its sites.** `check-lean-chain.sh:457` ("refusing to guess") and `:674` ("a check that cannot run must not report a pass") are fail-closed-on-unknown — the same shape the register classifies `gates-signal` at every site that reaches `note_violation`. The exit-2 contract makes `not-a-gate` defensible here, but the class `why` currently reads as if the whole class is unset-env-var refusals; it should name the fail-closed sites explicitly.

## Nits

1. `scripts/check-gate-buckets.sh:234` — "A register whose rows are all comments would then dispose of its own denominator with a blank row … **(g21)** is the case." That scenario is **g22** (`comments_only`); g21 is the empty-corpus case. A reader following the citation lands on the wrong test.
2. `scripts/check-gate-buckets-selftest.sh:29` — "THE NEGATIVE DIRECTION **(g17)** pins what the recipe must NOT enumerate." The negative cases are g18a–g18d; g17 is the missing-register case.
3. `scripts/check-gate-buckets-selftest.sh` — g22 is emitted between g16 and g17, which makes the file read out of order against its own header.
4. `scripts/check-gate-buckets.sh:80` — `*) ROOT="$1"` swallows unknown flags: `--lst` becomes the repo root and surfaces as `corpus file is missing: …`, and a second positional silently wins over the first.
5. `scripts/gate-buckets.tsv` — the `fail_milestone 5 "progress file is not current…"` row's `why` says "Covers the close-out's sibling call too — same message, same read." The two sites (`lean-gate.sh:4753`, `:5036`) diverge after the shared prefix ("nothing to certify" vs "nothing to close out and nothing public should be written about it"). The disposition is right; the claim of identity isn't.

## BLOCKERS

1. **`scripts/gate-buckets.tsv` — the `operator-override.sh::envfail` row dispositions three real gates as `not-a-gate`, and its `why` asserts something false about the file.**

   The file's entire register content is one catch-all row: anchor `envfail `, bucket `not-a-gate`, `why` = *"environment refusal — operator-override.sh's envfail is its single refusal primitive and covers both halves — a malformed invocation and an unusable environment — at exit 2. **The gate it guards (whether a record may be written at all) is the attendance check, not this primitive.**"*

   That last sentence is wrong: the attendance check refuses *through this primitive*, and the anchor covers those sites.
   - `operator-override.sh:141` — `headless) envfail "this process tree is marked headless (LEAN_ATTEND_MODE=headless) — the scheduler sets it on every payload it spawns. Attendance cannot be minted here…"`. This is the gate that stops a scheduler-spawned session from minting the affordance every `gates-process` yield depends on.
   - `operator-override.sh:110` — `envfail "LEAN_ATTEND_MODE='…' is not a value this reads … attendance is never self-asserted, it is minted by an operator running 'attend'."`
   - `operator-override.sh:298` — `envfail "refusing to record an override from a headless session ($ATTEND_REASON). This record's whole content is an operator's stated answer; a headless run has no operator to quote."`

   All three are self-assertion / fabrication defenses — the same class this register scores `gates-llm` everywhere it appears in `lean-evidence.sh` and `check-lean-chain.sh` (the *reading* side of these very records). Unlike `lean-gate.sh`, `operator-override.sh` carries no header contract fixing exit 2 as "nothing was evaluated," so OR-1's "the exit-2 contract is what makes every site in it true" does not hold for this file — the register had to assert that contract itself, and it asserted it incorrectly.

   **Consequence:** the register states that the file owning the entire yield mechanism contains zero gates, and that its attendance defense is an environment refusal. The guard is green and AC-4's count print cannot expose it — a catch-all count of *N* gives a reader no way to see that some of the *N* are gates. This is exactly the vacuous coverage the slice's own corpus rationale (why `lean-evidence.sh` had to be included) exists to prevent, and it lands on the most safety-relevant refusals in the lane. Fix: split the attendance/fabrication sites out of the class row into their own `gates-llm` rows, leaving the residual usage/environment sites in the catch-all.

2. **`scripts/check-gate-buckets.sh:109` — the command-position regex misses shell keyword positions, and a live site is already outside the denominator.**

   The recipe is `grep -nE "(^|[;&|(){}])[[:space:]]*${p}[[:space:]]"`. The header states the intended rule as *"The primitive must sit at the start of a command — line start, or after `;`, `|`, `&`, `(`, `)`, `{` or `}`."* But `then`, `else`, `elif` and `do` are also command-start positions, and none is in the character class.

   `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` is `      else envfail "unexpected argument: $1"`. Neither alternative matches (`^` + `[[:space:]]*` hits `else`, and the line contains no character from `[;&|(){}]`), so this refusal site is **not enumerated today**. The denominator — the artifact the whole design rests on ("`--list` prints the enumeration, that output IS the denominator by definition") — is short by at least this site, and the commit message's "305 refusal sites" is correspondingly wrong.

   **Consequence:** an ordinary shell shape — `else ticket_refuse "…"`, `then fail_milestone 3 "…"`, `do terminal … 1 "…"` — lets a new gate join the lean lane unclassified with the guard green. That is the precise failure the slice was filed against, and the header's own framing names it: *"A file that refuses through five helpers and is scanned for one is 80% unguarded while reading as covered."*

   This also fails **AC-8**: the surface is neither in the stated self-exclusions nor in the stated residual (which names only "a *newly named* refusal primitive"), so a reader cannot tell an excluded surface from a forgotten one — and this one is forgotten. Fix: extend the prefix to cover keyword positions (e.g. `(^|[;&|(){}]|\b(then|else|elif|do)\b)[[:space:]]*`), add the resulting site to the register, and add a selftest case for the shape — the current fixtures contain no `then`/`else` refusal, which is why nothing caught it.

---

## r2

Started 2026-09-06T23:24:30Z. `stderr` empty. `review-lead` **not invoked**.

I reviewed the guard, its selftest, the register, and the five corpus files it enumerates. I could not execute the guard (Bash approval was declined for `bash scripts/check-gate-buckets.sh`), so the runtime verdict below is derived by replaying the enumerator's own regex against the tree with `grep`, which is exactly what the script does.

## What holds up

The design is sound and the parts I could verify against the tree check out:

- **AC-3's "whole primitive set" exclusion is genuinely load-bearing.** `orchestrate-lean.sh:336` is `envfail() { terminal "$1" 2 "$2"; }` — `{ terminal ` matches the site regex, and only the *file-wide* `defs` alternation keeps that definition line out of the `terminal` enumeration. The selftest cases this directly (g18d).
- **AC-7 wiring is correct.** The step sits in the always-on guard job beside `check-lockstep-pairs.sh` and `check-eval-model-identity.sh` (`ci.yml:164`), not `pr-gates`.
- **D-4 is right about the lockstep debt.** `OVERRIDE_GATES` at `operator-override.sh:182` sits inside a `LOCKSTEP-BEGIN override-record-reader verbatim` block already twinned to `lean-evidence.sh:989`. Reading it at run time genuinely avoids a third copy owing a marker.
- **No new `fail-open-sites.tsv` row is owed.** Every `| grep -q` in the selftest is a `printf … | grep -q`, which `check-fail-open-shapes.sh`'s `VAR_PRODUCER` exclusion already covers; the guard itself never pipes into `grep -q`.
- **Register coverage is exact where I could count it.** `check-lean-chain.sh::note_violation` — 18 enumerated sites, 18 rows. `lean-evidence.sh::note_violation` — 16 and 16. The `envfail` classes total exactly 132 sites across the five files, matching OR-1's stated default.
- **The g22 fix is real.** `FILENAME == ENVIRON["CB_ROWS"]` instead of `FNR == NR` genuinely closes the empty-rows-file false-green; the commit message describes the bug accurately.

Per-AC: AC-1, AC-4, AC-5, AC-6, AC-7, AC-9, AC-10 satisfied. AC-2 and AC-3 and AC-8 are unsatisfied on one point — see BLOCKERS.

## Nits

1. **`scripts/gate-buckets.tsv` — the "132" in four per-file `why` cells is the aggregate, not the row's own count.** The boilerplate "so 132 near-identical rows would add no classification" is repeated verbatim in the `lean-gate.sh::envfail`, `lean-evidence.sh::envfail`, `operator-override.sh::envfail` and `check-lean-chain.sh::envfail` rows, where it reads as that row's coverage. The actual per-file counts are 57 / 21 / 23 / 15 (and 16 for orchestrate, split across two rows); 132 is the sum. The `why` column is specified as "name the mechanism", so a figure that is wrong per-row undercuts the one column a human reads.

2. **`scripts/check-gate-buckets.sh:195` and `:198` both fire on the same row.** A `gates-llm` row whose yield cell names an `OVERRIDE_GATES` value trips "Only gates-process may yield" *and* "A row that yields IS gates-process", counting one defect as two violations. Cosmetic only, since the exit code is a count by convention.

3. **`scripts/check-gate-buckets.sh:161-167` — the `trap` is armed after the third `mktemp`.** If the second or third fails, `envfail` exits with the earlier temp files leaked.

4. **`scripts/check-gate-buckets.sh:80` — a second positional argument silently overwrites the first** (`*) ROOT="$1"`), rather than being a usage error.

## Warnings

1. **`scripts/gate-buckets.tsv` — two anchors overlap, and one row is currently redundant.** The row anchored `…reads 'verdict=${VERDICT_VALUE:-<none>}', n` is a strict prefix of the line the next row targets, so it covers **both** `lean-evidence.sh:778` and `:913`, while the longer `…— freshness is` row covers only `:913`. Both are `gates-signal`, so the AMBIG arm stays quiet and AC-4's printed count (2 vs 1) is the only signal. Consequence today is nil — a future disagreement *would* red — but deleting the second row would leave `:913` silently dispositioned by the first. Tightening the shorter anchor to `…, not 'verdict=approve'."` would make each row cover its own site.

2. **`exit "$violations"` wraps at 256.** This is the repo's doctor convention (`check-fail-open-shapes.sh` does the same), so it is not introduced here — but this guard's denominator is ~305 sites, an order of magnitude larger than the precedent's, which is the first place the convention has a plausible collision. Exactly 256 unclassified sites exits 0. Also, `exit 2` from two violations is indistinguishable from the environment refusal the script reserves 2 for. Worth a `[[ $violations -gt 250 ]] && exit 250` clamp given what this guard is for.

3. **The coverage table prints ~120 lines to stdout on every green PR run.** Intentional per AC-4, but it lands in the always-on job's log on every PR. Not a defect; flagging so it is a deliberate cost.

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:109` — the enumerator's command-position regex misses reserved-word command positions, and drops a live refusal site in the tree today.**

   **Mechanism.** The site pattern is `(^|[;&|(){}])[[:space:]]*${p}[[:space:]]` — a primitive counts as a call only at line start or after `;`, `|`, `&`, `(`, `)`, `{`, `}`. Bash reserved words that also open a command — `then`, `else`, `do`, `elif`, `!` — are not in that set. The script header states the rule as "*the primitive must sit at the start of a command — line start, or after `;` …*", so the implementation is narrower than its own stated contract, and AC-8's residual list does not name this exclusion.

   Replaying the exact regex against the corpus and subtracting comment lines and definition lines, one live site is dropped:

   ```
   plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420
         else envfail "unexpected argument: $1"
   ```

   (That is the only one across all five files and all eleven primitives today — `lean-evidence.sh`, `orchestrate-lean.sh`, `operator-override.sh` and `check-lean-chain.sh` are all clean, and the two other `lean-gate.sh` near-misses at `:676`/`:1583`/`:3987` are definition lines that are correctly excluded.)

   **Consequence.** The denominator this slice defines as ground truth (`--list`, and the verdict line's "N enumerated refusal site(s)") is short by one: the tree has 58 `lean-gate.sh::envfail` sites, not 57, and 133 `envfail` sites, not 132. The guard stays green while under-reporting. That is benign for `envfail`, which the loose `envfail ` anchor would classify `not-a-gate` anyway — but the miss is silent and general: a future `else fail_milestone 3 "…"`, `then ticket_refuse …`, or `else note_violation "…"` is invisible to the enumerator, so no row is owed, no `UNCLASSIFIED` fires, and CI passes. That is precisely AC-2's first arm ("an enumerated site no row claims") failing to hold, and the failure mode `#636` was filed against — a new gate joining the lane unclassified with nothing going red.

   **Fix.** Add the reserved words to the anchor alternation, e.g. `(^|[;&|(){}]|[[:space:]](then|else|do|elif|!))[[:space:]]*${p}[[:space:]]`, re-run `--list`, add the row for `lean-gate.sh:420` if the count moves (it will), and either state the remaining positional residual in the header per AC-8 or add a negative case to `check-gate-buckets-selftest.sh`'s g18 block pinning `else <prim>` as enumerated — the g18 block currently pins only what must *not* be enumerated, which is why this direction went uncased.

---

## r3

Started 2026-09-06T23:24:30Z. `stderr` empty. `review-lead` **not invoked**.

I've completed the review. Here are my findings.

## Context

The design is sound and unusually well-defended: the denominator is the enumerator's own output rather than a count, the register and the tree check each other in four independent directions, and the safety-critical rows hold up under inspection. I verified the three `gates-process` rows individually — `lean-gate.sh:3451`, `orchestrate-lean.sh:631`, and `lean-evidence.sh:971` — and each anchor resolves to exactly one site, so no over-broad anchor is silently granting a wired operator waiver to a neighbouring refusal. The two code-side yield call sites in the tree (`orchestrate-lean.sh:547` → `intake-unqueued`, `lean-gate.sh:3064` → `spec-open-region`) are exactly the two the register marks as wired. The `in_set` `case` pattern is correctly written — quoted expansions are literal in patterns, so no glob hazard. CI placement matches AC-7, and the BRE `\|` in the row counter is an established repo idiom (`tools/mutation-sweep-selftest.sh:614`, `tools/check-sweep-bound-selftest.sh:61`), not a portability bug.

Note that `bash scripts/check-gate-buckets.sh` required approval in this session, so I verified the enumeration by reproducing the guard's own grep patterns rather than by executing it. My per-file counts (57/88/37/34/23/67 raw ≈ 306) match the 305 sites the feat commit claims, which is what the blocker below turns on.

## Warnings

1. **`scripts/check-gate-buckets-selftest.sh:346` and `:352` — the two negative-direction assertions (g18b, g18d) are vacuous.** g18b asserts no site at `$OL::terminal` line **1**, but `terminal()`'s definition in the fixture is on line **2**; line 1 is the shebang, so the condition can never hold regardless of the code under test. g18d asserts no site at `$OL::envfail` line 3, but `envfail()` can never match the enumeration pattern anyway (`envfail(` has `(`, not whitespace, after the name) — so it too passes unconditionally. The invariant g18d names is the interesting one, and the assertion that would actually test it is `$OL::terminal` at line **3** (`envfail() { terminal "$1" 2 "$2"; }` matches the `terminal` pattern via `{ terminal ` and is suppressed only by the whole-primitive-set `defs`). This is test quality, not a guard defect: narrowing `defs` to the scanned primitive would surface line 3 as an unclassified `OL::terminal` site and red both g1 and g0 — and the same construct exists in production at `orchestrate-lean.sh:336`, so g0 covers it against the real tree.

2. **AC-5's safety arm is register-internal only, and the manifesto text added here overstates it.** The guard binds *yield cell → bucket* within the TSV, but nothing binds a code-side `operator-override.sh check --gate X` call to a `gates-process` row naming `X`. A future edit could wire a real yield at a site the register calls `gates-signal` and nothing would red. AC-5 declares this scope explicitly, so it isn't a defect — but `docs/pipeline-manifesto.md`'s new "Which gate is which is not left to a reading" reads as a stronger guarantee than the register proves. The register is a declaration checked for internal consistency, not a check on yield wiring.

3. **`scripts/check-gate-buckets.sh:195-200` double-counts one defect.** A non-`gates-process` row whose yield cell names an `OVERRIDE_GATES` value trips direction 1 (non-`-` yield) and direction 2 (names an override value), adding 2 to `violations` for a single bad cell. Harmless while the exit code is only read as zero/non-zero, but it inflates the number the header documents as a violation count.

## Nits

1. **`scripts/check-gate-buckets.sh:185` — the comment contradicts the code.** "Pure bash on purpose: this runs once per register row, and a subprocess per row is what the batching below exists to remove" sits directly above `$(corpus_prims "$rfile")`, which forks a subshell on every register row — ~156 forks. Cheaper than an `exec`, but it is precisely the per-row spawn the perf commit set out to eliminate. `case "$CORPUS" in *"$rfile:"*)` would hoist it.

2. **A 6th+ column in a register row is silently folded into `why`.** `read -r rkey rbucket ranchor ryield rwhy` lets `rwhy` absorb all trailing fields, so an accidental extra column is not caught by the malformed-row check.

3. **`scripts/check-gate-buckets-selftest.sh:243` mis-describes its own mechanism.** g12b's comment says "the field count is not the check, the field CONTENT is", but because tab is an IFS *whitespace* character, `IFS=$'\t'` collapses the consecutive tabs and the row is detected as a short 4-field row, not as a five-field row with an empty cell. The assertion passes; the explanation of why is wrong.

4. **A literal TAB inside a site's source line truncates awk's `$3`**, so an anchor spanning it would match nothing. This fails closed (the row reds as drift *and* the site reds as unclassified), but the two messages would point away from the real cause.

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:300` — `exit "$violations"` wraps modulo 256, so exactly 256 violations report success.** The header at line 69 documents "Exit code = number of violations (doctor convention); 0 = clean", and the CI step at `.github/workflows/ci.yml:162` reads only zero/non-zero. The guard enumerates **305 sites** today (stated in commit `16ae844a`, and consistent with the per-file counts I reproduced), and the theoretical violation ceiling is well over a thousand once per-row schema failures and AMBIG are included — so the count routinely lives in a range where `exit` truncation applies.

   Failure scenario: `scripts/gate-buckets.tsv` loses coverage of exactly 256 enumerated sites — e.g. a bad merge or a partial revert drops the row blocks for `lean-gate.sh` (145 sites), `orchestrate-lean.sh` (67) and `lean-evidence.sh` (37), plus seven more. Every one of those sites is emitted as `UNCLASSIFIED` on stderr, `violations` reaches 256, `exit 256` yields wait status **0**, the CI step passes, and the lane merges with the overwhelming majority of its refusal sites carrying no bucket at all. This is the "green-looking pass built from nothing" the g22 case was added to prevent, arriving through the exit path instead of the awk read. The reachable window is narrow — one value in ~305 — but it is reachable precisely during a bulk-uncoverage event, which is the one moment the guard has to red, and the exposure multiplies (256, 512, 768) as the epic widens the corpus to the `scripts/`+`tools/` guards it names as out of scope. Clamping is one line, e.g. `[ "$violations" -gt 255 ] && exit 255` before the final `exit`, which preserves the doctor convention everywhere it is meaningful (including g22's `rc -ge 10` assertion) while making the signal monotonic.
