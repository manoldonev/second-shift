# C2-a — ablation arm `U-3`: lines 31–37 removed

One arm of the leave-one-out ablation registered at
[`docs/skill-ablation-addendum.md`](../../../skill-ablation-addendum.md) §C, run 2026-09-03
against sample **C2-a** (PR #654 @ `cfba102`). The SKILL text supplied to the session is
`plugins/dev-pipeline/skills/review-lean/SKILL.md` at `8d5d0897` with **lines 31–37 deleted** —
unit `U-3`, checklist step 3, check out the PR head by branch name, not detached. Registered reach: **not-reached**.
Everything below each `## r<n>` heading is that run's output verbatim.

## The realised invocation

```bash
cd /private/tmp/c2b-748/clone            # throwaway clone, detached at cfba102
printf '%s' "$(cat prompts/U-3.txt)" \
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
| r1 | `0` | 434518 B, 448 lines, sha256 `b843fe34c3a663ad…` | exit 0 — `COMPLETE` | 1 | 27 Bash,  6 Grep,  4 Read | **0** |

Only an exit-0 `COMPLETE` capture is scored. The last column is the ablation's own integrity
check: the clone keeps `plugins/` in the working tree, so a session that read the unablated
`review-lean/SKILL.md` off disk would defeat the line-range ablation. It is counted per run
rather than assumed away.

---

## r1

2026-09-03T18:55:00Z → 2026-09-03T19:04:43Z. stderr empty.

I reviewed this statically — running `scripts/check-gate-buckets.sh` and its selftest was denied in this environment, so I verified the register against the tree with targeted greps instead. Where it mattered I checked the counts by hand: 132 `envfail` sites → 6 class rows (57/15/21/16/23 across the five files); orchestrate-lean's 9 `usage-*` and 7 `env-*` slugs match the two class-row anchors; one `block_milestone` and one `check-lean-chain.sh::fail` site, matching D-6; and the one *wired* `gates-process` row (`spec-open-region`) anchors on `fail_milestone 1 "$reason"; return $?; }`, which resolves to exactly one site — `check_pause_and_ask` at `lean-gate.sh:3451`. That last one was the finding I most expected to have; it holds up.

## AC scoring against `docs/plans/second-shift-636-lean.md`

| AC | Score | Note |
| --- | --- | --- |
| AC-1 | satisfied | closed enum, `not-a-gate` `why` checked mechanically against the closed set (`:208`) |
| AC-2 | **unsatisfied** | the three disagreements do red independently and `--list` checks nothing, but "enumerates from the tree by shape" is incomplete — blocker 1 |
| AC-3 | satisfied | every primitive declared per file; the whole-set definition exclusion verified against `orchestrate-lean.sh:336` (`envfail() { terminal … }`) |
| AC-4 | satisfied | one row per site default, `hits > 0`, count printed, zero-hit reds and distinguishes drift from outlived |
| AC-5 | satisfied | both directions; vocabulary parsed from `operator-override.sh` at run time; empty vocabulary is exit 2 |
| AC-6 | satisfied | `unwired — <reason>` form-checked, existence of a ticket not checked |
| AC-7 | satisfied | `lint-and-selftests`, which carries no `if:` — always-on, and not `pr-gates` |
| AC-8 | **unsatisfied** | residuals are recorded, but the non-command-position exclusion is misstated — blocker 1 |
| AC-9 | satisfied | manifesto section reads coherently with three buckets plus the register pointer |
| AC-10 | satisfied | no corpus file edited; the selftest's `printf … \| grep -q` sites fall under `check-fail-open-shapes.sh`'s `VAR_PRODUCER` exclusion so no new row is owed; `Guard-mass:` trailers present on all three commits |

Design fidelity: not applicable — the spec arms no `## Design` section.

## Warnings

1. **The register contradicts a committed, explicitly pre-settled bucket, silently.** `docs/prose-blocker-triage.tsv:40` (pb-94ee597a) records the all-dark rule with enforcer `scripts/check-lean-chain.sh::verdict-record` and says "settled KEEP / **gates-llm** by the parent epic. Its bucket is **pre-settled**". The corresponding site here — `lean-evidence.sh::note_violation` / "no committed verdict record (a file named `*-$KEY$LEAN_VERDICT_SUFFIX`)" — is dispositioned `gates-signal`, and the plan's Decision Ledger carries no DEPARTURE row against that settlement, even though D-2 cites that exact file as the key precedent it adopts. Behaviorally this costs nothing (both buckets never yield), which is why it is a warning and not a blocker. But the register's entire value proposition is being *the* answer to "which gate is which", and two committed registers now give different answers with nothing reconciling them.

2. **`(g18c)` does not test what its comment claims, and the untested thing is blocker 1's code.** `check-gate-buckets-selftest.sh:308-310` asserts `launch_note terminal` is not enumerated, under the banner "a primitive's name sitting in ARGUMENT position". But the only occurrence in the fixture is on `terminal()`'s own definition line (`check-gate-buckets-selftest.sh:105`), which the `defs` exclusion drops regardless. Delete the `(^|[;&|(){}])` command-position anchor from the recipe entirely and g18c still passes. So the positional anchor — the one part of the recipe that is actually wrong — has no covering case in a suite that was otherwise mutation-swept.

3. **`exit "$violations"` is taken mod 256 over a 305-site denominator.** `check-gate-buckets.sh:300`. At exactly 256 violations the guard exits 0 and the CI step reads green while 256 `✗` lines go to stderr. The precedent this copies (`check-fail-open-shapes.sh`) has the same shape but over ~26 sites, where the count is unreachable; here it is not obviously so. `exit $(( violations > 250 ? 250 : violations ))` keeps the doctor convention and closes it.

## Nits

1. `in_set()` (`check-gate-buckets.sh:145-148`) interpolates `$1` unquoted into a `case` pattern, so glob metacharacters in the value are matched rather than compared. A `gates-process` row whose yield cell is `*` satisfies AC-6's vocabulary check. A loop (`for w in $2; do [ "$w" = "$1" ] && return 0; done`) compares rather than globs.
2. The comment at `:181-184` says the corpus-pair check is "Pure bash on purpose … a subprocess per row is what the batching below exists to remove" — but `$(corpus_prims "$rfile")` forks a subshell (and on bash 3.2 a here-string temp file) on each of the 156 rows. The claim and the code disagree; either inline the lookup or drop the claim.
3. `:195-200` — a non-`gates-process` row whose yield names an `OVERRIDE_GATES` value trips both AC-5 arms, so one bad cell reports as two violations. Harmless, but it makes the exit code a poor proxy for "things to fix" (and interacts with warning 3).
4. The cleanup `trap` is installed at `:167`, after the second and third `mktemp` can `envfail` at `:163-166`. A failure there leaks the temp file(s) already created.

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:109` — the enumerator's command-position anchor misses refusals that follow a shell reserved word, so the denominator is not the denominator.** The recipe requires the primitive to be preceded by line-start or one of `; & | ( ) { }`:

   ```
   grep -nE "(^|[;&|(){}])[[:space:]]*${p}[[:space:]]" "$ROOT/$f"
   ```

   `then`, `else`, `elif` and `do` are command-start positions too, and none of them is in that set. `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` — `else envfail "unexpected argument: $1"` — is a live refusal site in the shipped corpus that this pattern cannot match (regex-checked: `^` + `[[:space:]]*` runs into `else`, and the line contains none of the seven bracket characters), so it is absent from `--list`'s output and no register row is required for it.

   Today the consequence is contained: the missed site is an `envfail`, which the class-wide `not-a-gate` row would have covered anyway, so nothing is currently misclassified. The consequence that matters is forward. Write the next lane gate as `[ -n "$x" ] || { …; }` and it is enumerated; write the identical gate as `if [ -z "$x" ]; then fail_milestone 3 "verify lane is red"; fi` and it joins the lane unclassified, no row is owed, and `check-gate-buckets.sh` stays green — which is precisely the failure #636 was filed against ("nothing reds when a new gate joins the lane unclassified"), reintroduced inside the guard meant to close it. `lean-gate.sh:420` proves the shape is already idiomatic in the corpus, so this is not a hypothetical style.

   Compounding it, `check-gate-buckets.sh:47-49` states the exclusion as *"non-command positions. The primitive must sit at the start of a command — line start, or after `;`, `|`, `&`, `(`, `)`, `{` or `}`."* That reads as a definition of command-start, and it is not one: it omits reserved-word positions. AC-8's requirement is that "a reader can tell an excluded surface from a forgotten one", and a reader who trusts this header will conclude `else envfail …` is enumerated. The exclusion is misdescribed rather than declared, which is what takes AC-8 from "residual recorded" to unsatisfied.

   Fix: extend the recipe to accept reserved-word positions — e.g. `(^|[;&|(){}]|[[:space:]](then|else|elif|do))[[:space:]]*${p}[[:space:]]` — re-run `--list`, add the one resulting row (or confirm the existing `lean-gate.sh::envfail` class anchor absorbs it, which it should, since the anchor is `envfail ` and the count printed for that row will go up by one). Then add a selftest case that puts a refusal at `else`/`then` position in the fixture, so the positional anchor is covered at all (see warning 2) and the header's exclusion list matches the code.

