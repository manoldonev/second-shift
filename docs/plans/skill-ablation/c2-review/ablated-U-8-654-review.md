# C2-a — ablation arm `U-8`: lines 90–96 removed

One arm of the leave-one-out ablation registered at
[`docs/skill-ablation-addendum.md`](../../../skill-ablation-addendum.md) §C, run 2026-09-03
against sample **C2-a** (PR #654 @ `cfba102`). The SKILL text supplied to the session is
`plugins/dev-pipeline/skills/review-lean/SKILL.md` at `8d5d0897` with **lines 90–96 deleted** —
unit `U-8`, checklist step 8, post the findings as one PR comment. Registered reach: **not-reached**.
Everything below each `## r<n>` heading is that run's output verbatim.

## The realised invocation

```bash
cd /private/tmp/c2b-748/clone            # throwaway clone, detached at cfba102
printf '%s' "$(cat prompts/U-8.txt)" \
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
| r1 | `0` | 372297 B, 379 lines, sha256 `a30ca1e8c7c6d479…` | exit 0 — `COMPLETE` | 1 | 25 Bash,  4 Grep,  5 Read | **0** |

Only an exit-0 `COMPLETE` capture is scored. The last column is the ablation's own integrity
check: the clone keeps `plugins/` in the working tree, so a session that read the unablated
`review-lean/SKILL.md` off disk would defeat the line-range ablation. It is counted per run
rather than assumed away.

---

## r1

2026-09-03T19:03:54Z → 2026-09-03T19:11:59Z. stderr empty.

I couldn't execute the guard or its selftest (Bash approval is unavailable in this session), so "green on this tree" is unverified by me. I reproduced the enumerator's grep recipe by hand against all five corpus files, and read the guard, the register, the selftest, the CI wiring, and the precedent guard it copies.

**What checks out:** AC-7 (the step is in `lint-and-selftests`, beside `check-lockstep-pairs.sh` / `check-eval-model-identity.sh`, not `pr-gates`). AC-9 (manifesto link resolves). AC-10 — the new script introduces no `producer | grep -q` site, so `fail-open-sites.tsv` genuinely needs no row; `Changelog:` and `Guard-mass:` trailers are on `16ae844a`. The two wired `gates-process` dispositions are correctly scoped: `fail_milestone 1 "$reason"` resolves to exactly one site (`check_pause_and_ask`, lean-gate.sh:3451) and `terminal preflight-rejected-resumable 3` to one (orchestrate-lean.sh:631) — neither anchor can swallow a neighbour. All 46 `terminal` sites are covered by the 29 slug-keyed rows with no prefix collisions (`build-inflight` vs `build-inflight-unreadable` etc. are safe under `index()`). `\|` alternation in the row counter works on this BSD grep, so the summary count is not a portability trap. The mutation sweep mutates in-place inside a sandbox clone, so `g0`'s `ROOT` resolves to the sandbox repo and the case is a real kill signal rather than a trivially-failing one.

## Warnings

1. **`scripts/check-gate-buckets-selftest.sh` (g18d) asserts the wrong key and is vacuous.** It checks `$OL::envfail` at line 3, but line 3 of the fixture is `envfail() { terminal "$1" 2 "$2"; }` — the recipe requires `[[:space:]]` after the primitive name and `envfail(` has none, so that key/line pair can never be enumerated under any implementation. The property the case names (AC-3's "the exclusion is by the file's whole declared primitive set, not just the primitive being enumerated") is about the **terminal** enumeration of that same line, and needs `k="$OL::terminal"`. As written, narrowing `defs` (line 107) back to only the primitive being scanned leaves g18d green. The mutant is still killed by g1, so the suite isn't blind — but the per-arm independence the file's header sells is not there for this arm.

2. **(g18c) doesn't exercise the command-position anchor either.** The `launch_note terminal "…"` occurrence sits on `terminal()`'s own definition line, which is already dropped by the definition exclusion. Deleting `(^|[;&|(){}])` from the recipe on line 109 leaves g18c green, because no fixture line puts a primitive name in argument position on a non-definition line. (g18a, the comment case, is genuinely non-vacuous.)

## Nits

3. Two stale case ids in prose. `check-gate-buckets.sh:234` cites "(g21) is the case" for the all-comment register, but that is **g22**; g21 is the empty-corpus case. `check-gate-buckets-selftest.sh:20` bills the negative direction as "(g17)", but g17 is the missing-register case and the negatives are g18a–g18d.

4. A non-`gates-process` row whose yield cell names an `OVERRIDE_GATES` value trips both line 195 and line 198, counting one bad row as two violations. Since the exit code *is* the violation count, the reported number overstates the number of rows to fix.

5. `*) ROOT="$1"` (line 57) swallows a mistyped flag as a repo root — `check-gate-buckets.sh --lst` exits 2 with "corpus file is missing" rather than a usage error. Inherited from `check-fail-open-shapes.sh`, so it is at least consistent.

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:109` — the shape recipe misses call sites in shell reserved-word position, and the miss is undisclosed.** The command-position anchor is `(^|[;&|(){}])[[:space:]]*${p}[[:space:]]`, so the primitive is only recognized at line start or immediately after `; & | ( ) { }`. A call preceded by `then`, `else`, `elif`, `do` or `!` matches nothing. This is live today: `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420`

   ```
         else envfail "unexpected argument: $1"
   ```

   is a refusal site that `--list` does not print. (I checked all five corpus files this way; line 420 is the only live miss — every other unmatched occurrence is a definition line, an argument-position mention, or a string, all of which are intentional exclusions.)

   The consequence is not that one `envfail` today: it is a `not-a-gate` usage error, so nothing is currently *mis*classified. The consequence is that the guard's central claim is false and no reader can discover it. The header states the self-exclusions "because an unstated one is a hole in the 'output IS the denominator' claim" and then declares that the *only* residual a shape enumerator cannot close is a newly-named primitive — which is not true, and AC-8's "a reader can tell an excluded surface from a forgotten one" is therefore unsatisfied. Concretely: a future gate written `else fail_milestone 3 "…"`, or `if ! ok; then ticket_refuse …`, or `if cond; then block_milestone 1 "…"; fi` joins the lane unclassified while `check-gate-buckets.sh` prints `✓ N enumerated refusal site(s) … all bucketed by 156 register row(s)` and CI stays green. That is exactly the failure mode #636 was filed against, reached through a shape the register cannot see. Fix by widening the anchor to cover reserved-word and `!` positions (and adding a fixture case in the negative block), or — if that is judged to over-enumerate — by stating the exclusion in the header and in AC-8 so the residual is recorded rather than implied away.

