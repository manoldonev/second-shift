# C2-a — ablation arm `R-2`: lines 108–109 removed

One arm of the leave-one-out ablation registered at
[`docs/skill-ablation-addendum.md`](../../../skill-ablation-addendum.md) §C, run 2026-09-03
against sample **C2-a** (PR #654 @ `cfba102`). The SKILL text supplied to the session is
`plugins/dev-pipeline/skills/review-lean/SKILL.md` at `8d5d0897` with **lines 108–109 deleted** —
unit `R-2`, rule 2, one identity per review round. Registered reach: **not-reached**.
Everything below each `## r<n>` heading is that run's output verbatim.

## The realised invocation

```bash
cd /private/tmp/c2b-748/clone            # throwaway clone, detached at cfba102
printf '%s' "$(cat prompts/R-2.txt)" \
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
| r1 | `0` | 388109 B, 366 lines, sha256 `16c52830912c58e8…` | exit 0 — `COMPLETE` | 1 | 11 Bash,  13 Grep,  3 Read | **0** |

Only an exit-0 `COMPLETE` capture is scored. The last column is the ablation's own integrity
check: the clone keeps `plugins/` in the working tree, so a session that read the unablated
`review-lean/SKILL.md` off disk would defeat the line-range ablation. It is counted per run
rather than assumed away.

---

## r1

2026-09-03T19:04:48Z → 2026-09-03T19:13:16Z. stderr empty.

I could not execute the guard here (Bash script execution is gated in this session), so the findings below come from reading the enumerator's recipe against the actual corpus files with the search tools. The register↔tree reconciliation itself (g0) I could not re-run and am taking on CI's word.

## AC scoring

| AC | Verdict |
| --- | --- |
| AC-1 | satisfied — closed enum at `check-gate-buckets.sh:189`, the `not-a-gate` `why` set at :208, the two-rows-disagree arm at :249 |
| AC-2 | satisfied — three independent reds (UNCL/ANCHOR DRIFT/outlived), `--list` at :128, cases g2/g3/g4/g1 |
| AC-3 | **unsatisfied** — see blocker 1; the enumerator's command-position rule silently drops a shape it never declares as excluded |
| AC-4 | satisfied — one row per site, `hits > 0`, per-row count printed at :288 |
| AC-5 | satisfied — both directions at :195/:198, vocabulary read from `operator-override.sh:182` at run time |
| AC-6 | satisfied — :202, `unwired — <reason>` form only |
| AC-7 | satisfied — `ci.yml` step sits in `lint-and-selftests` beside `check-lockstep-pairs.sh` / `check-eval-model-identity.sh`, not `pr-gates` |
| AC-8 | **unsatisfied** — the header's self-exclusion list is incomplete (blocker 1); a reader cannot tell the missed shape from a declared one |
| AC-9 | satisfied |
| AC-10 | satisfied — no corpus file edited; every `\| grep -q` the new selftest adds has a `printf` producer, so `check-fail-open-shapes.sh`'s `VAR_PRODUCER` exclusion applies and no `fail-open-sites.tsv` row is owed; `Guard-mass:` trailers present on all three commits |

## Warnings

1. **`scripts/check-gate-buckets-selftest.sh:327` and `:333` — g18b and g18d assert the wrong line/key and pass vacuously.** g18b checks `$OL::terminal` at fixture **line 1** (the shebang); `terminal()`'s definition is line 2. g18d checks `$OL::envfail` at line 3, but the property it names ("excluded from the TERMINAL enumeration too — the exclusion is by the file's whole primitive set") requires checking `$OL::terminal` at line 3. As written neither can fail: `envfail()`/`terminal()` have no whitespace after the name, so the same-primitive scan could never match those lines regardless of `defs`. Line 3 (`envfail() { terminal "$1" 2 "$2"; }`) is in fact the *only* line in the fixture that `defs` removes, and it is the one neither case looks at. A mutant that narrows `defs` to the scanned primitive is still killed today — by g14/g1c's exact counts (10 sites would become 11) — but the two cases written to pin AC-3's exclusion prove nothing while printing `ok:`. The same shape is live on the real tree at `orchestrate-lean.sh:336`, so the exclusion is load-bearing.

2. **Cross-register bucket disagreement.** `docs/prose-blocker-triage.tsv:40` records the enforcer `scripts/check-lean-chain.sh::verdict-record` as "settled KEEP / **gates-llm** by the parent epic", naming "an absent verdict record is already a violation at the merge boundary" as its gate analog. `scripts/gate-buckets.tsv` disposes of that same merge-boundary refusal (`lean-evidence.sh::note_violation`, `"no committed verdict record …"`) as **gates-signal**. Both never yield, so nothing becomes waivable — but two committed artifacts labelling one gate differently is precisely the "left to a reading" state this slice exists to end. A clause in that row's `why` reconciling the two would settle it.

3. **`scripts/check-gate-buckets.sh:300` — `exit "$violations"` is taken mod 256.** The tree enumerates 305 sites (per commit `16ae844a`), so a wholesale register failure can produce a count above 255; at exactly 256 or 512 the guard exits 0 and CI reads green. The precedent `check-fail-open-shapes.sh` has a two-digit denominator and never reaches this. A cap (`exit $(( violations > 250 ? 250 : violations ))`) removes it.

4. **`scripts/check-gate-buckets.sh:161-167` — the EXIT trap is armed only after all three `mktemp`s succeed.** If the second or third fails, `envfail` exits with the earlier temp files orphaned. A single scratch dir, or arming the trap after the first `mktemp`, closes it.

## Nits

- `scripts/gate-buckets.tsv:34` says the `envfail` classes are "132 sites, **6 rows**"; the plan's OR-1 row says "**5 rows** over 132 sites". One is stale.
- The sentence "…so 132 near-identical rows would add no classification…" is pasted verbatim into four per-file `not-a-gate` rows. In each one 132 reads as that file's count when it is the aggregate across all five.
- The `not-a-gate` `why` check (`:208`) is a bare prefix match, so `usage errorless …` passes. A trailing word boundary would close it.
- `:169` — `IFS="$TAB" read` still treats tab as IFS *whitespace*, so tab runs collapse and an empty cell is unrepresentable; an empty field surfaces as "malformed row" rather than naming the empty column. g12b encodes the current behaviour, so this is descriptive, not a bug.
- `:297` — `grep -cv '^[[:space:]]*\(#\|$\)'` relies on `$` being an anchor inside a BRE `\(…\|…\)` group, which POSIX leaves undefined. GNU grep (CI) is fine; on a BSD/macOS grep blank lines may be counted, which would break g1c's exact "10 register row(s)" assertion for local runs. `grep -cvE '^[[:space:]]*(#|$)'` is portable.

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:109` — the command-position rule silently drops refusal sites preceded by a shell keyword, and one exists in the corpus today.** The enumerator requires the primitive to follow line-start or one of `;&|(){}`:
   `grep -nE "(^|[;&|(){}])[[:space:]]*${p}[[:space:]]"`.
   A call written after `then`, `else`, `elif` or `do` on the same line matches none of those. `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` is exactly that shape — `else envfail "unexpected argument: $1"` — a live `envfail` call site in a corpus file that the enumeration never emits. **Consequence:** the guard's stated invariant (script line 2, the manifesto's new "an unclassified one fails CI", and the CHANGELOG entry) is false as merged — there is a refusal site in the lane carrying no bucket, and the guard is green. The disposition is unaffected today only by luck: `lean-gate.sh::envfail`'s class anchor would have covered it as `not-a-gate` had it been enumerated. The forward hazard is the real one — an `else fail_milestone …` or `then ticket_refuse …` added tomorrow joins the lane unclassified with CI green, which is the single failure mode this slice was filed against. It also unmets AC-8: the header's self-exclusion list (:45-54) names comments, definition lines and argument position, so a reader of that list concludes keyword-prefixed calls *are* enumerated; this is a forgotten surface presented as a complete one. Minimal fix, which preserves g18c (`launch_note terminal "…"` stays out because `launch_note` is not in the keyword set):
   `grep -nE "(^|[;&|(){}])[[:space:]]*(then|else|elif|do)?[[:space:]]*${p}[[:space:]]"`
   then re-run `--list`, reconcile the denominator (305 → 306 on this tree, absorbed by the existing `envfail ` class row), add the keyword form to the header's exclusion prose, and add a fixture line pinning it so the shape cannot regress.

