# C2-a — ablation arm `U-1`: lines 26–28 removed

One arm of the leave-one-out ablation registered at
[`docs/skill-ablation-addendum.md`](../../../skill-ablation-addendum.md) §C, run 2026-09-03
against sample **C2-a** (PR #654 @ `cfba102`). The SKILL text supplied to the session is
`plugins/dev-pipeline/skills/review-lean/SKILL.md` at `8d5d0897` with **lines 26–28 deleted** —
unit `U-1`, checklist step 1, export a review identity. Registered reach: **not-reached**.
Everything below each `## r<n>` heading is that run's output verbatim.

## The realised invocation

```bash
cd /private/tmp/c2b-748/clone            # throwaway clone, detached at cfba102
printf '%s' "$(cat prompts/U-1.txt)" \
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
| r1 | `0` | 430196 B, 465 lines, sha256 `402ea3d7edd18527…` | exit 0 — `COMPLETE` | 1 | 18 Bash,  18 Grep,  5 Read | **0** |

Only an exit-0 `COMPLETE` capture is scored. The last column is the ablation's own integrity
check: the clone keeps `plugins/` in the working tree, so a session that read the unablated
`review-lean/SKILL.md` off disk would defeat the line-range ablation. It is counted per run
rather than assumed away.

---

## r1

2026-09-03T18:49:30Z → 2026-09-03T18:59:14Z. stderr empty.

I reviewed the diff, the corpus files it enumerates, the CI wiring, and the obligations AC‑10 names.

## What I verified as good

- **AC-7** — the step lands in `lint-and-selftests`, which is unconditional (`.github/workflows/ci.yml:164`), not `pr-gates`.
- **AC-10** — no corpus file is edited by the diff; `check-fail-open-shapes.sh` needs no new row (every `| grep -q` the two new files introduce is a `printf`-producer, which `VAR_PRODUCER` excludes at `scripts/check-fail-open-shapes.sh:81`); no `lean-gate.sh` call site is added; all three commits carry `Guard-mass:` trailers.
- **AC-5/AC-6** — the yield vocabulary really is parsed at run time from `operator-override.sh:182-183`, never copied, and both directions plus the `unwired — <reason>` form are cased (g7/g8/g9/g10/g16).
- The register is internally consistent with the counts the commits claim: 156 rows, and the primitive-by-primitive spot checks match (`check-lean-chain.sh::fail` = 1 site at :475, `lean-gate.sh::block_milestone` = 1 at :3372, all 16 `orchestrate-lean.sh::envfail` sites are `usage-*` or `env-*`, matching the two class rows).
- The `FILENAME`-over-`FNR == NR` reasoning at `check-gate-buckets.sh:231` is correct and the batched awk pass is sound — the distinct-bucket set, the empty-denominator guard, and the short-circuit that keeps `[[ "$c" -eq 0 ]]` from arithmetic-evaluating a path all hold.

I could not execute the guard in this session (the sandbox declined to run it), so the green-on-this-tree claim rests on g0 plus CI rather than on my own run.

## AC scoring

AC-1 ✅ · AC-2 ✅ · **AC-3 ❌** · AC-4 ✅ (mechanically; see W2) · AC-5 ✅ · AC-6 ✅ · AC-7 ✅ · **AC-8 ❌** · AC-9 ✅ · AC-10 ✅

## Warnings

1. **`scripts/check-gate-buckets-selftest.sh:327` — g18b is a vacuous assertion.** It asserts there is no `orchestrate-lean.sh::terminal` site at **line 1** of the fixture, but line 1 of the generated `$OL` file is the shebang (`selftest:77`); `terminal()`'s own definition is on **line 2** (`selftest:78`). The case can never fail, so the "a helper's definition line is not a site" claim has no coverage. Its sibling g18d (line 3, `envfail() { terminal … }`) is correctly targeted and does test the whole-primitive-set exclusion — which is why the gap is easy to miss.

2. **`scripts/gate-buckets.tsv:67` — two anchors where one is a strict prefix of the other.** Row 67's anchor ends `…', n`, which is a prefix of row 68's `…', not 'verdict=approve' — freshness is`. Row 67 therefore covers both `lean-evidence.sh:778` and `:913`; row 68 covers only `:913`. Both are `gates-signal`, so nothing reds and the tree stays green — but AC-4's stated default of one row per site is silently broken here in a place the author clearly intended one-per-site (unlike the sanctioned `envfail`/slug classes), and row 67's printed count will read `2` with no explanation.

3. **`scripts/check-gate-buckets.sh:299` — `exit "$violations"` wraps mod 256.** With 305 enumerated sites and 156 rows, the reachable violation count runs to ~461, so a tree that produces exactly 256 violations exits 0 and CI reads green. The precedent (`check-fail-open-shapes.sh`) has the same posture but roughly an order of magnitude fewer sites, so this slice is where the wrap first becomes reachable. Capping at, say, `[ "$violations" -gt 250 ] && exit 250` would close it.

4. **`scripts/check-gate-buckets.sh:198` — AC-5 direction 2 is strictly implied by direction 1.** `in_set "$ryield" "$GATE_VOCAB"` can only be true when `$ryield != "-"`, which direction 1 (`:195`) has already flagged. Every occurrence of the defect this arm exists to catch is therefore reported twice and counted twice. Worth keeping the message (it is the more specific one) but making the arms mutually exclusive.

5. **The four blanket `not-a-gate` `envfail` rows label a mixed class with a single closed-set value.** `scripts/gate-buckets.tsv:61` opens `environment refusal —` and then says the class covers "an unreadable config, a missing helper, **a bad argument**"; the `operator-override.sh` row does the same ("covers both halves — a malformed invocation and an unusable environment"). AC-1 has the guard check that opening label mechanically, so the check passes on a label the row's own prose says is true of only part of what it covers.

## Nits

- `scripts/check-gate-buckets.sh:234` cites `(g21)` for the all-comment-register case; that case is `(g22)` (`selftest:309`). `selftest:18` credits `(g17)` with the negative direction, but g17 is the missing-register case and the negative direction is g18a–g18d.
- Anchors carry a load-bearing trailing space before the tab (`envfail `, `terminal approved 0 `). Invisible to a reader and to most editors' whitespace rendering.
- `scripts/check-gate-buckets.sh:165` — if the third `mktemp` fails, `envfail` exits before the `trap` at `:167` is armed, leaking the first two temp files.
- `scripts/check-gate-buckets.sh:297` uses GNU BRE alternation (`\(#\|$\)`), an idiom that appears nowhere else under `scripts/`. Only g1c's exact-count assertion on the macOS bash-3.2 lane stands behind its portability.
- `docs/pipeline-manifesto.md:145` points a reader at the register, but the register's fourth value `not-a-gate` exists only in the TSV header — a manifesto reader following the pointer meets an undocumented value.

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:109` — the enumerator misses refusal calls preceded by a shell keyword, so the denominator is incomplete today and the header misdescribes why.** The recipe requires the primitive to follow line-start or one of `[;&|(){}]`. A call written `else envfail …` / `then fail_milestone …` / `do ticket_refuse …` sits at the start of a command but is preceded by a keyword, which is in neither position, so it is never enumerated. This is not hypothetical: `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` is `else envfail "unexpected argument: $1"` — a live refusal site in a corpus file that `--list` does not print and that no register row is required to dispose of. Consequence: the slice's central claim, that `--list`'s output **is** the denominator and that "an unclassified one fails CI", is false as shipped; a future gate added as `else fail_milestone 3 "…"` in any of the five corpus files carries no bucket and the guard stays green — the exact silence #636 was filed against. Today's escaped site is `not-a-gate`, so nothing is currently misclassified, but the shape hole is what has to be fixed: widen the command-position class to admit the keyword prefixes (`then|else|elif|do|;;`), or enumerate on the primitive as a word and exclude argument position explicitly.

2. **`scripts/check-gate-buckets.sh:52-54` — AC-8's "a reader can tell an excluded surface from a forgotten one" is unmet, because the stated exclusion is affirmatively wrong.** The header declares exactly three self-exclusions and describes the third as "The primitive must sit at the start of a command — line start, or after `;`, `|`, `&`, `(`, `)`, `{` or `}`", framing it as excluding *non-command positions*. `else envfail` at `lean-gate.sh:420` **is** at the start of a command and is excluded anyway, so the header documents a denominator the code does not produce. AC-8 requires every self-exclusion to be stated and the one residual a shape enumerator cannot close (a newly-named primitive) to be named as such; a reader auditing this guard against its own header would conclude the miss above cannot happen. Whether or not finding 1 is fixed by widening the regex, the header has to describe the exclusion that actually holds.

