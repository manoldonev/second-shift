# C2-a — ablation arm `U-4`: lines 38–47 removed

One arm of the leave-one-out ablation registered at
[`docs/skill-ablation-addendum.md`](../../../skill-ablation-addendum.md) §C, run 2026-09-03
against sample **C2-a** (PR #654 @ `cfba102`). The SKILL text supplied to the session is
`plugins/dev-pipeline/skills/review-lean/SKILL.md` at `8d5d0897` with **lines 38–47 deleted** —
unit `U-4`, checklist step 4, `bash G delta` — the range this round must READ. Registered reach: **not-reached**.
Everything below each `## r<n>` heading is that run's output verbatim.

## The realised invocation

```bash
cd /private/tmp/c2b-748/clone            # throwaway clone, detached at cfba102
printf '%s' "$(cat prompts/U-4.txt)" \
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
| r1 | `0` | 351508 B, 384 lines, sha256 `92b5a4a0e2c05917…` | exit 0 — `COMPLETE` | 1 | 11 Bash,  14 Grep,  5 Read | **0** |

Only an exit-0 `COMPLETE` capture is scored. The last column is the ablation's own integrity
check: the clone keeps `plugins/` in the working tree, so a session that read the unablated
`review-lean/SKILL.md` off disk would defeat the line-range ablation. It is counted per run
rather than assumed away.

---

## r1

2026-09-03T18:55:32Z → 2026-09-03T19:03:48Z. stderr empty.

## Summary

Well-built slice: the register/enumerator pair is the right shape, the safety arm is register-internal in both directions, and the selftest is unusually thorough (g0 grading the real tree from the sweep is a good call). I verified statically — this sandbox denied execution of `bash scripts/check-gate-buckets.sh`, so I could not run the guard or the selftest; everything below comes from reading the recipe and grepping the corpus with the guard's own regexes.

AC scoring: AC-1 ✅, AC-2 ✅, AC-3 ✅, AC-4 ✅, AC-5 ✅, AC-6 ✅, AC-7 ✅ (confirmed: the step is in `lint-and-selftests`, the job that already runs `check-lockstep-pairs.sh` and `check-eval-model-identity.sh`, unconditional on `pull_request`), AC-8 ❌ (blocker 1), AC-9 ✅, AC-10 ✅ (no corpus file edited, no new `| grep -q` command-producer — the selftest's `printf … | grep -q` sites fall under `check-fail-open-shapes.sh`'s `VAR_PRODUCER` exclusion, so no `fail-open-sites.tsv` row is owed; `Guard-mass:` trailers present on all three commits).

## Warnings

**W1 — `exit "$violations"` collides with the script's own exit-2 contract, and wraps at 256.** `scripts/check-gate-buckets.sh:300` returns the violation count; `scripts/check-gate-buckets.sh:90` returns 2 for an environment refusal, and the header at line 69 declares both meanings in one sentence. Exactly two violations is indistinguishable from "the denominator could not be computed" — and `check-gate-buckets.sh --list` reports 305 sites, so the count can also exceed 255, where 256 violations exits 0 and CI reads green. The precedent (`check-fail-open-shapes.sh`) has no exit-2 arm, so the ambiguity is new here rather than inherited. Nothing consumes the code beyond zero/non-zero today, so this is a latent contract defect, not a live one; capping (`exit $((violations > 1 ? 1 : violations))`, or reserving 2) would close both.

**W2 — the `envfail` class rows auto-dispose of every future `envfail`, and AC-4's mitigation is unguarded.** The anchor `envfail ` on `plugins/dev-pipeline/skills/build-lean/lean-gate.sh::envfail` matches every enumerated site in that file, so a newly added `envfail` is silently classified `not-a-gate` — the count moves 132 → 133 and nothing reds. OR-1 records this default and AC-4 says the printed per-row count is what keeps it visible, but no baseline count is recorded anywhere, so "visible rather than silent" holds only for a human reading the coverage block of a *green* CI run. Accepted by the spec, so not a blocker, but the visibility claim is weaker than the spec asserts.

**W3 — a row with more than five fields is silently well-formed.** `scripts/check-gate-buckets.sh:172` only reds on too-few/empty fields; `read` folds any extra tab-separated fields into `$rwhy`. A stray tab in the `why` column therefore reads as a valid row with a truncated-looking rationale. g12/g12b cover only the under-count and empty-cell directions.

## Nits

**N1 — stale case cross-references.** `scripts/check-gate-buckets-selftest.sh:18` says "THE NEGATIVE DIRECTION (g17)", but the negative cases are `g18a`–`g18d`; `g17` is the missing-register case. `scripts/check-gate-buckets.sh:234` says "(g21) is the case" for the all-comment register, but that is `(g22)`; `(g21)` is the empty-denominator case. The `g22` block also sits above `g17` in the file.

**N2 — prefix anchors double-cover.** e.g. the `lean-evidence.sh::note_violation` rows anchored `…reads 'verdict=${VERDICT_VALUE:-<none>}', n` and `…, not 'verdict=approve' — freshness is`: the first is a prefix of the second's site text, so it covers two sites. Same bucket, so no AMBIG, but the printed counts will read one higher than the register intends.

**N3 — an unknown flag is silently taken as the repo root.** `scripts/check-gate-buckets.sh:78` (`*) ROOT="$1"`), so `--lst` reports "corpus file is missing" rather than a usage error. Matches the precedent, so purely cosmetic.

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:109` — the enumerator misses refusal sites in command position after a shell reserved word, and the header (AC-8's requirement) declares the opposite.** The site regex is `(^|[;&|(){}])[[:space:]]*${p}[[:space:]]`, so a call reached via `then`/`else`/`elif`/`do`/`in` — or via a backtick substitution — matches neither alternative. The header at `scripts/check-gate-buckets.sh:52` states the recipe's third self-exclusion as "non-command positions. The primitive must sit at the start of a command — line start, or after `;`, `|`, `&`, `(`, `)`, `{` or `}`", which asserts coverage of exactly the case that is missed: `else envfail …` *is* the start of a command.

   This is live, not hypothetical: `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` is `else envfail "unexpected argument: $1"`, a real refusal call the enumeration does not contain. It is silent in both directions — the site never appears in `--list`, so it is never UNCLASSIFIED, and the class row's anchor `envfail ` still matches other lines in the file, so it never reds as drift either.

   Consequence: the slice's central claim — "`--list` prints the denominator, that output IS the denominator by definition" — is false against the current tree, and AC-8's "a reader can tell an excluded surface from a forgotten one" is unmet because this exclusion is neither declared nor intended. Today's single miss is benign (an `envfail`, which the register disposes of as `not-a-gate` anyway), but the guard's whole purpose is the future case: an `else fail_milestone …` or `then ticket_refuse …` added later joins the lane unclassified and CI stays green — the vacuous coverage the spec's own corpus rationale says this slice exists to prevent. Fix is to widen the position alternation (add the reserved words and the backtick) and add a selftest case pinning `else <primitive>` as enumerated, or — if the narrower recipe is deliberate — say so in the header's exclusion list and dispose of `lean-gate.sh:420` explicitly.

