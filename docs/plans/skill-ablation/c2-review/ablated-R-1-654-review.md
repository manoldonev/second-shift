# C2-a — ablation arm `R-1`: lines 100–107 removed

One arm of the leave-one-out ablation registered at
[`docs/skill-ablation-addendum.md`](../../../skill-ablation-addendum.md) §C, run 2026-09-03
against sample **C2-a** (PR #654 @ `cfba102`). The SKILL text supplied to the session is
`plugins/dev-pipeline/skills/review-lean/SKILL.md` at `8d5d0897` with **lines 100–107 deleted** —
unit `R-1`, rule 1, never end a turn with uncollected work. Registered reach: **not-reached**.
Everything below each `## r<n>` heading is that run's output verbatim.

## The realised invocation

```bash
cd /private/tmp/c2b-748/clone            # throwaway clone, detached at cfba102
printf '%s' "$(cat prompts/R-1.txt)" \
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
| r1 | `0` | 265070 B, 252 lines, sha256 `8a05e2dbaa0fec6f…` | exit 0 — `COMPLETE` | 1 | 17 Bash,  12 Grep,  2 Read | **0** |

Only an exit-0 `COMPLETE` capture is scored. The last column is the ablation's own integrity
check: the clone keeps `plugins/` in the working tree, so a session that read the unablated
`review-lean/SKILL.md` off disk would defeat the line-range ablation. It is counted per run
rather than assumed away.

---

## r1

2026-09-03T19:04:46Z → 2026-09-03T19:09:59Z. stderr empty.

I reviewed the guard, the register, the selftest, and the CI wiring against the tree. Note: Bash execution is restricted in this session, so I verified the enumerator's recipe by applying its exact regexes to the corpus files with the search tools rather than by running the script.

## What's solid

The design holds up: the denominator is the script's own output rather than a count, the four disagreement arms (unclassified / drift / outlived / ambiguous) are genuinely independent, the yield vocabulary is read from `operator-override.sh` instead of copied, and AC-5's safety arm being register-internal is the right place for it. The `FILENAME ==` choice over `FNR == NR` at `scripts/check-gate-buckets.sh:236` is a real defect avoided — with an all-comment register, the `FNR == NR` form would have loaded the sites file's first record as a row. The three `gates-process` rows all check out: `spec-open-region` and `intake-unqueued` are live `OVERRIDE_GATES` values (`operator-override.sh:182`), and the `fail_milestone 1 "$reason"` anchor resolves to exactly one site (`lean-gate.sh:3451`), so the one wired-yield row isn't swallowing neighbours. The `terminal <slug>` anchors are all trailing-space-delimited, so no slug prefix-matches its `-unreadable`/`-resumable` sibling. Obligations are paid: `Guard-mass:` and `Changelog:` trailers present on all three commits, and the CI step landed in `lint-and-selftests` per AC-7, not `pr-gates`.

## Warnings

1. **`exit "$violations"` wraps at 256** (`check-gate-buckets.sh:300`). With a 305-site denominator, a wholesale register break produces a violation count in the same order of magnitude as the modulus; exactly 256 exits 0 and CI reads green. `check-fail-open-shapes.sh` has the same tail, so this is an inherited convention rather than something this PR invented — but that guard's denominator is much smaller. Capping at, say, `exit $(( violations > 250 ? 250 : violations ))` costs nothing.

2. **AC-5's two directions are not independent** (`check-gate-buckets.sh:195-200`). Direction 2 fires only when `ryield` is in `GATE_VOCAB`, which implies `ryield != "-"`, which means direction 1 has already fired. Every mis-wired row therefore emits two violations. Harmless for the verdict, but it inflates the exit code (see above) and means g8 is asserting on output that direction 1 alone would have produced with a different message — the case doesn't isolate what it claims to.

3. **Two `lean-evidence.sh::note_violation` anchors overlap by prefix.** `note_violation "verdict record '$VERDICT' reads 'verdict=${VERDICT_VALUE:-<none>}', n` is a strict prefix of the sibling row's anchor, so it claims both sites while its `why` ("the record's `verdict=` value is `approve` or it is not") describes only one — the other is the freshness arm. Both are `gates-signal`, so AMBIG can't fire and nothing reds. AC-4 sanctions multi-site anchors and the printed count makes it visible, so this is within the declared contract; it's worth tightening the shorter anchor anyway, since the `why` is the only thing a future reader has.

## Nits

- `check-gate-buckets.sh:234` cites "(g21) is the case" for the empty-rows-file defect; the actual case is **g22**. g21 is the empty-corpus case.
- The selftest header says "THE NEGATIVE DIRECTION (g17)", but the negative cases are labelled g18a–g18d; g17 is the missing-register case.
- g18d's label claims it pins that `envfail()`'s one-line definition is excluded "from the TERMINAL enumeration too", but the assertion checks key `$OL::envfail` at line 3 — the trivially-excluded direction. The whole-primitive-set exclusion is actually killed by g1 (the mutant would make line 3 enumerate as `$OL::terminal`, which no fixture row anchors, so the baseline goes red). The mutant is covered; the case is just mislabelled.
- Unknown flags fall into `*) ROOT="$1"` (`check-gate-buckets.sh:80`), so a typo like `--lst` is silently taken as the repo root and the run checks a nonexistent tree via exit 2 rather than saying the flag was wrong.
- A row with six or more tab-separated fields is not malformed-detected — `read`'s last variable absorbs the surplus into `rwhy`.
- `in_set` interpolates `$1` into a `case` pattern (`check-gate-buckets.sh:146`), so a yield cell containing `*`, `?` or `[` would be matched as a glob. No current row triggers it.

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:109` — the command-position regex misses a primitive preceded by a shell keyword, and one live refusal site is already invisible.**

   The recipe is `grep -nE "(^|[;&|(){}])[[:space:]]*${p}[[:space:]]"`: the primitive must sit at line start (after whitespace only) or immediately after one of `; & | ( ) { }`. A call preceded by `else`, `then`, `do` or `elif` matches neither arm, because the delimiter that opened the compound is on an earlier line.

   `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` is exactly that shape:

   ```
         else envfail "unexpected argument: $1"
   ```

   Applying the enumerator's own pattern to that file returns lines 416, 426, 435, 440, 446, 448… and skips 420. It is a real `envfail` call, not a comment and not a definition, and it is not enumerated.

   Consequence, in two parts. First, the header's central claim — "`--list` prints the enumeration, that output IS the denominator by definition" — is false as written, and AC-8 requires every self-exclusion to be stated so "a reader can tell an excluded surface from a forgotten one." The three declared exclusions (comments, definition lines, argument position) do not cover this one, so today it reads as forgotten. Second, and this is the part that matters after merge: the bucket the miss lands in is arbitrary. `envfail` is `not-a-gate`, so nothing is misclassified right now — but the same regex would silently drop a future `else fail_milestone 3 "…"` or `then ticket_refuse "…"`, and the guard would stay green over an unclassified gate. That is precisely the failure mode #636 was filed against.

   The fix is cheap and does not disturb the register: widen the leading alternation to accept a keyword boundary (e.g. add `|then|else|elif|do` as an alternative prefix, or accept any position preceded by whitespace-plus-keyword). I checked what that would cost — the existing `lean-gate.sh::envfail` row's anchor is the bare `envfail `, which `index()` matches against line 420's text, so the newly enumerated site is already covered. The denominator goes 305 → 306 and that row's printed count goes 57 → 58; nothing reds. If you'd rather not widen the shape, the alternative is to declare the keyword-prefixed form as a fourth self-companion exclusion in the header **and** fix the one live instance so the exclusion is empty in practice — but widening is the honest option, since the exclusion has no principled justification the way the other three do.

