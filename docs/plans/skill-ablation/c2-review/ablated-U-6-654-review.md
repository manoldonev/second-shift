# C2-a — ablation arm `U-6`: lines 77–85 removed

One arm of the leave-one-out ablation registered at
[`docs/skill-ablation-addendum.md`](../../../skill-ablation-addendum.md) §C, run 2026-09-03
against sample **C2-a** (PR #654 @ `cfba102`). The SKILL text supplied to the session is
`plugins/dev-pipeline/skills/review-lean/SKILL.md` at `8d5d0897` with **lines 77–85 deleted** —
unit `U-6`, checklist step 6, write the record via `bash G verdict`. Registered reach: **not-reached**.
Everything below each `## r<n>` heading is that run's output verbatim.

## The realised invocation

```bash
cd /private/tmp/c2b-748/clone            # throwaway clone, detached at cfba102
printf '%s' "$(cat prompts/U-6.txt)" \
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
| r1 | `0` | 453128 B, 443 lines, sha256 `6febea159ff6881a…` | exit 0 — `COMPLETE` | 1 | 28 Bash,  7 Grep,  3 Read | **0** |

Only an exit-0 `COMPLETE` capture is scored. The last column is the ablation's own integrity
check: the clone keeps `plugins/` in the working tree, so a session that read the unablated
`review-lean/SKILL.md` off disk would defeat the line-range ablation. It is counted per run
rather than assumed away.

---

## r1

2026-09-03T18:59:19Z → 2026-09-03T19:09:01Z. stderr empty.

I've completed the review. I could not execute the guard (command approval is unavailable in this session), so the findings below are established by reading the code and the corpus files directly; each one is verified against specific lines in the tree.

## Warnings

**W1 — `scripts/check-gate-buckets.sh:195-200`: the AC-5 second direction is logically subsumed by the first.** Direction 1 reds any non-`gates-process` row whose yield cell is not `-`. Direction 2 reds a non-`gates-process` row whose yield names an `OVERRIDE_GATES` value — which is necessarily also not `-`. Every input that trips direction 2 trips direction 1, so the "red test lane made waivable" edit is counted as **two** violations, and the exit code (which is the violation count) overstates by one per such row. Both arms are individually mutation-killed (g7 kills one, g8 the other), so this is not a coverage gap — it is a redundant check with a double-counting side effect. Keeping direction 2 for its much better error message is defensible; making it an `elif` would be strictly better.

**W2 — `scripts/gate-buckets.tsv`: the boilerplate `why` on the per-file `envfail` class rows asserts a figure that is only true globally.** `plugins/dev-pipeline/tools/operator-override.sh::envfail`, `scripts/check-lean-chain.sh::envfail`, `lean-evidence.sh::envfail` and `lean-gate.sh::envfail` each carry the identical clause "so 132 near-identical rows would add no classification and would drown the register." 132 is the *combined* `envfail` site count across all five files; `operator-override.sh` contributes a small fraction of it. A reader auditing one row is told that row covers 132 sites. The printed per-row coverage count is the thing that actually answers this, which is the argument for just dropping the number from the prose.

**W3 — `docs/plans/second-shift-636-lean.md:110` (OR-1) says "5 rows over 132 sites"; the shipped register has 6.** `orchestrate-lean.sh` takes two rows (`envfail env-` and `envfail usage-`) rather than one, on a per-slug-prefix split rather than the per-class split OR-1's default describes. The divergence is in the safe direction (more granular, and the split is justified in the register's own prose), but the Open Regions table now misstates what shipped.

## Nits

- `scripts/check-gate-buckets.sh:234` cites "(g21) is the case" for the `FILENAME`-vs-`FNR == NR` defect. g21 is the empty-denominator case; the case that actually pins that defect is **g22** (`scripts/check-gate-buckets-selftest.sh:298`).
- `scripts/check-gate-buckets-selftest.sh:19` — "THE NEGATIVE DIRECTION (g17)". g17 is the missing-register case; the negative-direction cases are **g18a–g18d**.
- `scripts/check-gate-buckets-selftest.sh:270` assigns `rc` in the g13 case and never reads it.
- `scripts/check-gate-buckets.sh:296` drops the `|| true` tail that the precedent (`check-fail-open-shapes.sh:178`) carries on the same `grep -c .` under `pipefail`. Harmless here — there is no `set -e` and the rc is not read, which the commit message says explicitly — but it is now the one place where the two guards' otherwise-identical verdict-line idiom differs.

## BLOCKERS

**1. `scripts/check-gate-buckets.sh:109` — the command-position regex does not recognize shell keyword position, so refusal sites after `then`/`else`/`do`/`elif` are never enumerated. One such site exists in the corpus today.**

The enumerator requires the primitive to sit at line start or immediately after one of `; & | ( ) { }`:

```
grep -nE "(^|[;&|(){}])[[:space:]]*${p}[[:space:]]" "$ROOT/$f"
```

`plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` is `      else envfail "unexpected argument: $1"`. `^` followed by `[[:space:]]*` lands on `else`, not `envfail`, and no character in `[;&|(){}]` precedes the call — so the line does not match, and it is absent from the denominator. It is a live refusal call site, not a comment, not a definition, and not an argument position, so it falls under none of the three self-exclusions the header states at lines 47-54.

Consequence, in two parts. Today: the artifact the whole slice defines as authoritative — "`--list` prints the enumeration, that output IS the denominator by definition" (line 28-31) — under-reports by at least one site, and the verdict line's "305 enumerated refusal site(s)" is wrong. Nothing reds, because `lean-gate.sh::envfail`'s blanket `envfail ` anchor draws its hits from the other sites in the class. Tomorrow, which is what the register exists for: a new `else fail_milestone 3 "…"` or `then ticket_refuse "…"` joins the lane, is not enumerated, produces no `UNCLASSIFIED` red, and CI stays green — the precise failure mode #636 was filed against ("nothing reds when a new gate joins the lane unclassified").

This also leaves **AC-8 unsatisfied**. AC-8 requires the header to record "the one residual a shape enumerator cannot close: a *newly named* refusal primitive in a corpus file is not enumerated until it is declared," so that "a reader can tell an excluded surface from a forgotten one." Lines 56-60 state that as *the* residual. Keyword-position call sites of an already-declared primitive are a second residual, they are demonstrably present in the tree, and the header presents the surface as closed. A reader cannot currently tell this excluded surface from a forgotten one, because it is a forgotten one.

The fix is to add the keyword alternatives to the leading context (e.g. `(^|[;&|(){}]|\b(then|else|elif|do)\b)`), or — if the shape is deliberately out of reach — to state it in the self-exclusion list and disposition `lean-gate.sh:420` explicitly. Either way the selftest fixture needs a keyword-position site, which it currently has none of.

**2. `scripts/check-gate-buckets-selftest.sh:326-335` — both g18b and g18d assert against the wrong record, so neither can fail; the one exclusion AC-3 singles out has no direct case.**

The `orchestrate-lean.sh` fixture (`scripts/check-gate-buckets-selftest.sh:76-84`) is: line 1 `#!/usr/bin/env bash`, line 2 `terminal() { launch_note terminal "$1 rc=$2"; exit "$2"; }`, line 3 `envfail() { terminal "$1" 2 "$2"; }`, line 5 the `terminal` call, line 6 the `envfail` call.

- **g18b** (line 326) asserts no record exists with key `…orchestrate-lean.sh::terminal` at **line 1**. Line 1 is the shebang; no enumeration can ever emit a site there, for any primitive, under any mutation of the guard. `terminal()`'s definition — the thing the assertion's own message names — is on line **2**. The case passes unconditionally.
- **g18d** (line 333) asserts no record exists with key `…orchestrate-lean.sh::envfail` at line 3, and its message claims this proves the definition line "is excluded from the **TERMINAL** enumeration too — the exclusion is by the file's whole primitive set, not by the primitive being scanned." To test that, the key must be `$OL::terminal`. As keyed, it tests the `envfail` enumeration — and line 3 (`envfail() {`) does not even match the `envfail` command-position shape (`envfail` is followed by `(`, not whitespace), so that record cannot exist regardless of whether the definition exclusion is present, correct, or deleted entirely. The case passes unconditionally.

So of the three invariants the suite header declares load-bearing at line 19-21 ("a mention in a comment, a helper's own definition line, and a primitive's name sitting in ARGUMENT position"), only the comment arm (g18a) has a case that can fail. The behavior AC-3 spells out by name — that the definition exclusion is built from the file's whole declared primitive set specifically because `envfail() { terminal "$1" 2 "$2"; }` is one line defining one primitive and calling another — is unguarded by any targeted case.

The guard's implementation of that behavior is correct (`scripts/check-gate-buckets.sh:107` builds `defs` from `$prims`, the full set), and the mutant that breaks it is killed incidentally by g1: widen `defs` to the scanned primitive only and fixture line 3 becomes an unclassified `OL::terminal` site, reddening the baseline case. So this is a test-integrity defect, not a live gap in the guard. It still has to be fixed before merge: a permanently-green assertion inside the block the suite names as its non-vacuous half is the same class of rot the register itself exists to prevent, and it will be read by the next author as coverage that exists. g18b needs `$2 == 2`; g18d needs `k="$OL::terminal"` with `$2 == 3`.

