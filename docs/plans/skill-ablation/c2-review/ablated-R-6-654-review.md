# C2-a — ablation arm `R-6`: lines 122–127 removed

One arm of the leave-one-out ablation registered at
[`docs/skill-ablation-addendum.md`](../../../skill-ablation-addendum.md) §C, run 2026-09-03
against sample **C2-a** (PR #654 @ `cfba102`). The SKILL text supplied to the session is
`plugins/dev-pipeline/skills/review-lean/SKILL.md` at `8d5d0897` with **lines 122–127 deleted** —
unit `R-6`, rule 6, review the patch you will name. Registered reach: **not-reached**.
Everything below each `## r<n>` heading is that run's output verbatim.

## The realised invocation

```bash
cd /private/tmp/c2b-748/clone            # throwaway clone, detached at cfba102
printf '%s' "$(cat prompts/R-6.txt)" \
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
| r1 | `0` | 399213 B, 418 lines, sha256 `a00258fcaa16018e…` | exit 0 — `COMPLETE` | 1 | 6 Bash,  20 Grep,  9 Read | **0** |

Only an exit-0 `COMPLETE` capture is scored. The last column is the ablation's own integrity
check: the clone keeps `plugins/` in the working tree, so a session that read the unablated
`review-lean/SKILL.md` off disk would defeat the line-range ablation. It is counted per run
rather than assumed away.

---

## r1

2026-09-03T19:09:08Z → 2026-09-03T19:18:13Z. stderr empty.

I couldn't execute scripts in this session (Bash is restricted to a few read-only commands), so everything below is verified by reading the tree — the corpus files, `ci.yml`, `tools/run-selftests.sh`, and the precedent guard this one copies.

## Summary

The design is sound and matches its spec: an enumerator whose `--list` output *is* the denominator, a register that must cover it exactly, four independent red arms (unclassified / drift / outlived / ambiguous), a register-internal safety arm in both directions, and a paired selftest that grades the real tree (g0) as well as fixtures. `gates-signal` is well-argued and the manifesto edit is consistent with the rest of that section. AC-7's placement is right — `lint-and-selftests` has no path filter and runs on every PR. AC-10's fail-open reconciliation holds: every `| grep -q` in the new selftest is a `printf`-producer, which `check-fail-open-shapes.sh:84` already excludes, so no new row is owed, and the `Guard-mass:` trailers are on all three code commits.

Two defects, both in the enumerator/guard rather than in the register's judgments.

## Warnings

1. **AC-5's two checks double-count.** `check-gate-buckets.sh:206` and `:209` both fire for a single bad cell (a non-`-` yield naming an `OVERRIDE_GATES` value trips "Only gates-process may yield" *and* "A row that yields IS gates-process"). Harmless for red/green, but the exit code is documented as the violation count, so one edit reports two.

2. **The exit code is an uncapped count, and this guard's denominator is 305.** `exit "$violations"` wraps mod 256; exactly 256 violations exits 0. The precedent (`check-fail-open-shapes.sh:181`) shares the convention over a much smaller denominator. A `[ $violations -gt 250 ] && violations=250` clamp before the exit would close it without touching the selftest (g22 asserts `rc -ge 10`).

3. **One line = one site.** The enumerator counts matching *lines*, so `… || envfail "a"; … || envfail "b"` on one line enumerates once. Nothing in the corpus does this today, but the header's "the output IS the denominator" claim would be stronger for saying so alongside the other self-exclusions.

4. **The `132` in each `envfail` row's `why` is the corpus-wide total, not that row's count.** The register header states it correctly ("132 sites, 6 rows"); the sentence is then copy-pasted into all five per-file rows, each of which covers only its own file's class. A reader reconciling a row against the printed per-row count will find they disagree.

## Nits

- `docs/plans/second-shift-636-lean.md` OR-1 records "5 rows over 132 sites"; the register ships 6 (`orchestrate-lean.sh` splits `envfail` into `env-` and `usage-`). The spec and the artifact should agree on the count the spec chose to state.
- `check-gate-buckets.sh:31` describes `not-a-gate` as covering "`orchestrate-lean.sh`'s exit-0 `terminal` success calls"; the `attended-…` handoff row is exit 9, not 0. The register row itself gets this right.
- `*) ROOT="$1"` (`:70`) makes a typo'd flag a repo root, surfacing as "corpus file is missing" at exit 2. Same as the precedent, so consistent — just noting it.

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:297` — GNU-only BRE alternation reds the macOS selftest lane.** `r="$(grep -cv '^[[:space:]]*\(#\|$\)' "$TSV")"` uses `\|`, which is a GNU extension; POSIX BRE has no alternation and BSD grep treats `\|` as a literal `|`. `.github/workflows/ci.yml:382-418` runs the **full** selftest set on `macos-latest` under stock `/bin/bash` 3.2 with BSD grep, and `tools/run-selftests.sh:327` discovers `scripts/check-gate-buckets-selftest.sh` by glob. There, the pattern matches almost nothing, `-v` counts every line of the register including comments and blanks, and the fixture (`# fixture register` + a blank + 10 rows) reports **12** register rows instead of 10 — so g1c, which asserts the exact string `10 enumerated refusal site(s) across 5 file(s), all bucketed by 10 register row(s)`, fails and the `selftests (macos, bash 3.2)` job goes red. On the real tree the same line would report ~230 instead of 156. Consequence: CI red on every PR, and a wrong denominator in the verdict line the guard exists to make trustworthy. Fix: `grep -cvE '^[[:space:]]*(#|$)'`, which is the repo's existing spelling (`plugins/second-shift/skills/onboard/tools/config-grill-selftest.sh:685`); this is the only `\|` BRE in any `.sh` in the tree. (I could not run BSD grep from this session to confirm the byte-level behavior; the ERE form is correct on both greps regardless.)

2. **`scripts/check-gate-buckets.sh:106` — the command-position recipe omits shell reserved words, so a live refusal site is silently outside the denominator.** The enumerator requires the primitive to follow line start or one of `[;&|(){}]`, but a call in command position may also follow `then`, `else`, `elif` or `do`. Live instance in the corpus: `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` — `else envfail "unexpected argument: $1"` — is not enumerated, while its sibling arm two lines up (`:416`, `-*) envfail "unknown option: $1"`) is. The classification isn't wrong today (both are `not-a-gate`), but the guard's whole contract is that `--list` *is* the denominator and that a new gate cannot join the lane unclassified: a future refusal written as `else fail_milestone 1 "…"` or `then ticket_refuse "…"` is invisible to this guard and passes green. It is also not among the stated self-exclusions (`:52-62`), which AC-8 requires so "a reader can tell an excluded surface from a forgotten one" — this one reads as excluded and is forgotten. Fix: widen the alternation to `(^|[;&|(){}]|[[:space:]](then|else|elif|do)[[:space:]])`, and add both directions to the g18 negative/positive set so the recipe stays pinned.

