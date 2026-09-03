# C2-a — ablation arm `U-P`: lines 6–22 removed

One arm of the leave-one-out ablation registered at
[`docs/skill-ablation-addendum.md`](../../../skill-ablation-addendum.md) §C, run 2026-09-03
against sample **C2-a** (PR #654 @ `cfba102`). The SKILL text supplied to the session is
`plugins/dev-pipeline/skills/review-lean/SKILL.md` at `8d5d0897` with **lines 6–22 deleted** —
unit `U-P`, the preamble — the session's purpose, `G`'s location, the jira tracker delta. Registered reach: **not-reached**.
Everything below each `## r<n>` heading is that run's output verbatim.

## The realised invocation

```bash
cd /private/tmp/c2b-748/clone            # throwaway clone, detached at cfba102
printf '%s' "$(cat prompts/U-P.txt)" \
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
| r1 | `0` | 335270 B, 303 lines, sha256 `2c131a588dcd7a7a…` | exit 0 — `COMPLETE` | 1 | 7 Bash,  13 Grep,  5 Read | **0** |

Only an exit-0 `COMPLETE` capture is scored. The last column is the ablation's own integrity
check: the clone keeps `plugins/` in the working tree, so a session that read the unablated
`review-lean/SKILL.md` off disk would defeat the line-range ablation. It is counted per run
rather than assumed away.

---

## r1

2026-09-03T18:49:23Z → 2026-09-03T18:56:10Z. stderr empty.

I reviewed the branch statically against the tree (Bash execution of the guard needed approval unavailable in this non-interactive session, so I verified the enumeration recipe by reading it and grepping the corpus directly).

## Per-AC scoring against `docs/plans/second-shift-636-lean.md`

| AC | Verdict | Note |
| --- | --- | --- |
| AC-1 | satisfied | closed enum checked at `check-gate-buckets.sh:189-192`; `not-a-gate` `why` constrained to the three-value set at `:208` |
| AC-2 | satisfied | UNCL / ANCHOR-DRIFT / outlived-row all red independently; `--list` exits 0 without checking (`:128-131`); selftest g2/g3/g4 plus g1 cover the arms |
| AC-3 | satisfied | `CORPUS` (`:93-97`) names all five primitive sets; the whole-set definition exclusion at `:107` is implemented and load-bearing against the real `orchestrate-lean.sh:336 envfail() { terminal "$1" 2 "$2"; }` |
| AC-4 | satisfied | `hits > 0` counting rule; per-row count printed at `:288-292` |
| AC-5 | satisfied | both directions at `:195-200`; vocabulary parsed from `operator-override.sh` at run time (`:139-143`), never copied |
| AC-6 | satisfied | `:202-206`, `unwired — <reason>` accepted as form only |
| AC-7 | satisfied | `ci.yml:164` sits in the always-on guard job beside `check-lockstep-pairs.sh` / `capability-parity-check.sh`, not `pr-gates` |
| AC-8 | **unsatisfied** | see blocker 1 — the header's exclusion list does not account for a command position the corpus already uses |
| AC-9 | satisfied | manifesto gains `gates-signal` and the register pointer; no lockstep twin exists for that list, so no marker is owed |
| AC-10 | satisfied | diff touches no corpus file; the new scripts' `\| grep -q` sites are all `printf` producers and so fall under `check-fail-open-shapes.sh`'s `VAR_PRODUCER` exclusion, needing no `fail-open-sites.tsv` row; no `lean-gate.sh` call site added; `Guard-mass:` trailer present on all three commits |

## Warnings

1. **`scripts/check-gate-buckets-selftest.sh:329-338` — both definition-exclusion assertions are vacuous.** g18b asserts `$OL::terminal` is absent at **line 1**, but `terminal()`'s definition is on line 2 of the fixture (line 1 is the shebang), so the assertion holds regardless of the exclusion. g18d asserts `$OL::envfail` is absent at line 3 — but `envfail()` can never be enumerated under the `envfail` scan anyway, since the pattern requires whitespace after the primitive and `(` follows. The assertion that AC-3 and the header actually turn on — that `envfail() { terminal "$1" 2 "$2"; }` at line 3 is not enumerated as `$OL::`**`terminal`** — is never made. g18c catches a line-2 regression only incidentally (the site text would contain `launch_note terminal`). Reversing the whole-set exclusion to per-primitive would leave g18b/g18c/g18d green; only g0 against the real tree would catch it.

2. **`scripts/check-gate-buckets.sh:300` — `exit "$violations"` wraps at 256.** The denominator is 305 sites, so a register damaged to exactly 256 violations exits 0 and CI reads green. This follows `check-fail-open-shapes.sh`'s existing doctor convention rather than being introduced here, but this guard is the first one whose violation count can plausibly reach that magnitude. Capping (`exit $(( violations > 250 ? 250 : violations ))`) would keep the convention and close it.

3. **`scripts/check-gate-buckets.sh:195-200` — the two AC-5 directions overlap.** A `gates-llm` row whose yield cell names `spec-open-region` trips both `:195` (non-`-` yield on a non-process row) and `:198`, producing two violations for one defect. Harmless to the verdict, but it inflates the exit code and prints the same row twice.

## Nits

- `scripts/check-gate-buckets.sh:169` — with `IFS=$'\t'`, tab is IFS whitespace, so runs of tabs collapse and an empty mid-row cell shifts fields left rather than reading as empty. The malformed-row check still reds (the last variable ends up empty), and g12b passes, but for a different mechanism than its comment claims ("the field count is not the check, the field CONTENT is").
- A site claimed by two rows carrying the *same* bucket is silently permitted and double-counted in the AC-4 coverage print. Consistent with the AMBIG-only reading of AC-1's "exactly one disposition", just worth knowing the count can exceed the site total.
- `scripts/check-gate-buckets-selftest.sh:34` — `bad()` returns non-zero when called without a detail argument (the `[ -n "${2:-}" ] && printf` tail). No caller reads it, and there's no `set -e`, so it's inert.

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:109` — the enumeration regex misses refusal calls in command position after a reserved word, and the header does not declare the gap.** The recipe requires the primitive to be preceded by line start or one of `; & | ( ) { }`: `grep -nE "(^|[;&|(){}])[[:space:]]*${p}[[:space:]]"`. A call written after `then`, `else`, `do` or `elif` on the same line matches none of those, so it is never enumerated — it is not merely unbucketed, it is invisible to `--list`. This is not hypothetical: `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` (`else envfail "unexpected argument: $1"`) is a live refusal site in the corpus that the guard does not see today. It goes unnoticed only because the `lean-gate.sh::envfail` class row draws its `hits > 0` from other sites, so nothing reds. The consequence is the failure mode the slice exists to prevent: a future gate written as `if …; then fail_milestone 3 "…"; fi` or `else ticket_refuse "…"` carries no bucket, `check-gate-buckets.sh` stays green, and CI reports "all bucketed" over a denominator that silently excluded it. It also falsifies the two completeness claims the artifact rests on — the header's "`--list` prints the enumeration, that output IS the denominator by definition" and AC-8's "a reader can tell an excluded surface from a forgotten one". Fix by widening the command-position class to cover the reserved words (e.g. an alternative branch for `(^|[;&|(){}]|\b(then|else|elif|do)[[:space:]])`) and adding a selftest fixture line in that shape; if the shape is instead judged out of scope, it has to be stated in the header's self-exclusion list and `lean-gate.sh:420` reworked, since the corpus currently contradicts the stated recipe.

