# C2-a — ablation arm `U-5b`: lines 56–66 removed

One arm of the leave-one-out ablation registered at
[`docs/skill-ablation-addendum.md`](../../../skill-ablation-addendum.md) §C, run 2026-09-03
against sample **C2-a** (PR #654 @ `cfba102`). The SKILL text supplied to the session is
`plugins/dev-pipeline/skills/review-lean/SKILL.md` at `8d5d0897` with **lines 56–66 deleted** —
unit `U-5b`, checklist step 5b, design fidelity on an armed run. Registered reach: **not-reached**.
Everything below each `## r<n>` heading is that run's output verbatim.

## The realised invocation

```bash
cd /private/tmp/c2b-748/clone            # throwaway clone, detached at cfba102
printf '%s' "$(cat prompts/U-5b.txt)" \
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
| r1 | `0` | 420606 B, 396 lines, sha256 `0bf86703fc80fb13…` | exit 0 — `COMPLETE` | 1 | 18 Bash,  15 Grep,  4 Read | **0** |

Only an exit-0 `COMPLETE` capture is scored. The last column is the ablation's own integrity
check: the clone keeps `plugins/` in the working tree, so a session that read the unablated
`review-lean/SKILL.md` off disk would defeat the line-range ablation. It is counted per run
rather than assumed away.

---

## r1

2026-09-03T18:56:15Z → 2026-09-03T19:04:40Z. stderr empty.

I verified by reading and by targeted `grep` (the guard itself couldn't be executed in this session — `bash scripts/check-gate-buckets.sh` was denied), so the findings below are static but each is confirmed against the tree.

## Nits

1. **`scripts/check-gate-buckets.sh:198-200` — the second AC-5 direction can never fire on its own.** The check above it already reds whenever a non-`gates-process` row's yield cell is anything but `-`, and `-` is not in `GATE_VOCAB`. So every row reaching line 198's condition has already been counted at 195; the arm contributes a second, better-worded message and a second violation, never an otherwise-missed one. `(g8)` still kills a mutant that deletes it (it asserts the specific message), so this is redundancy, not a gap.

2. **Cross-reference drift in the two new files.** `check-gate-buckets.sh:234` credits the `FNR == NR` fix to "(g21) is the case", but the case that exercises it is `(g22) comments_only`; `g21` is `empty_corpus`. Symmetrically, the selftest header says "THE NEGATIVE DIRECTION (g17)" while the negative-direction cases are `g18a`–`g18d` and `g17` is the missing-register case. Case ids are also out of order in the file (`…g16, g22, g17, g18a…`).

3. **The row parser and the summary counter disagree about what a comment is.** Line 170 skips a row only when `#` is at column 0; line 297 counts `^[[:space:]]*\(#\|$\)` as non-rows. An indented `#` line is a "malformed row" to the parser and a comment to the counter, so the `N register row(s)` figure and the number actually parsed can differ. (`\|` does work as BRE alternation on this machine's BSD grep — I checked, since the macOS CI lane runs this suite.)

## Warnings

1. **`scripts/check-gate-buckets.sh:235-254` — the batched awk pass's exit status is never read.** If awk exits non-zero after emitting a partial `PASS_OUT` (or the `printf … > "$SITES_F"` write at 230 truncates), the two loops that follow read a short file, find fewer `UNCL`/`HITS` records, and the guard reports green. This is the same hazard the script itself argues against at lines 117-120 for the `$(enumerate)` subshell — the reasoning is applied to one half of the pipeline and not the other. No realistic trigger found, but a `|| envfail` on the awk call would close it for one line.

2. **`scripts/check-gate-buckets.sh:300` — `exit "$violations"` truncates mod 256, and this is the first guard in the family where that is reachable.** With 305 enumerated sites plus ~156 rows, the violation count can exceed 255; exactly 256 or 512 violations exits 0 and CI reads a wholly broken register as clean. `check-fail-open-shapes.sh` shares the convention but has a denominator small enough that it cannot happen there. Low probability, but the failure mode is "guard silently passes", which is the one this slice exists to prevent.

3. **OR-1's class rows leave large unwatched spans.** `lean-gate.sh::envfail` alone covers 57 sites behind the anchor `envfail `; four more class rows behave the same way. This is the recorded default and the printed counts make it visible, so it is not a defect — but it is the mechanism that makes blocker 1 below consequential rather than cosmetic, since a new `envfail` site lands inside an existing anchor with nobody re-reading it.

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:109` — the command-position regex omits shell keywords, so a live refusal site is outside the denominator today.**

   The enumerator requires the primitive to be preceded by line start or one of `; & | ( ) { }`:

   ```
   grep -nE "(^|[;&|(){}])[[:space:]]*${p}[[:space:]]" "$ROOT/$f"
   ```

   `then`, `else`, `elif` and `do` also begin a command, and none of them is in that set. `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` is such a site:

   ```
   420:      else envfail "unexpected argument: $1"
   ```

   Confirmed missed: `grep -nE "(^|[;&|(){}])[[:space:]]*envfail[[:space:]]" lean-gate.sh` returns 57 lines, none of them the `unexpected argument` one, while the line is a real `envfail` call. It is the only such instance across the five corpus files today (checked for all eight primitives).

   Two consequences, and the second is the one that matters:

   - **The header states a rule the code does not implement.** Lines 52-54 assert "the primitive must sit at the start of a command — line start, or after `;`, `|`, `&`, `(`, `)`, `{` or `}`". Line 420 *is* at the start of a command and is dropped anyway, so the stated self-exclusion list does not describe the actual exclusions. AC-8 requires that "a reader can tell an excluded surface from a forgotten one"; this surface is forgotten, not excluded, and the register's "the output IS the denominator by definition" claim is false as written.
   - **A future gate lands unclassified and green.** `else fail_milestone 3 "$msg"` or `; then ticket_refuse …` in any corpus file is never enumerated, so `UNCL` never fires, no row is owed, and CI passes. That is precisely the regression AC-2 exists to catch, and it is invisible in the `--list` output a reader would check against.

   Today's single instance is benign — an `envfail` usage error that the existing `lean-gate.sh::envfail` class row would have dispositioned `not-a-gate` anyway — so the register's contents need no change. The fix is the recipe: add the keywords to the leading alternation (or match on "not preceded by a word character" and rely on the existing definition/comment exclusions), re-run `--list`, and add a selftest case pinning `else <primitive> …` as enumerated, alongside the existing `g18a`–`g18d` negatives. The header's exclusion list needs to be brought back into agreement with whichever rule ships.

