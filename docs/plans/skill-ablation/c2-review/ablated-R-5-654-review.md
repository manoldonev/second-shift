# C2-a — ablation arm `R-5`: lines 117–121 removed

One arm of the leave-one-out ablation registered at
[`docs/skill-ablation-addendum.md`](../../../skill-ablation-addendum.md) §C, run 2026-09-03
against sample **C2-a** (PR #654 @ `cfba102`). The SKILL text supplied to the session is
`plugins/dev-pipeline/skills/review-lean/SKILL.md` at `8d5d0897` with **lines 117–121 deleted** —
unit `R-5`, rule 5, the four design blockers on an armed run. Registered reach: **not-reached**.
Everything below each `## r<n>` heading is that run's output verbatim.

## The realised invocation

```bash
cd /private/tmp/c2b-748/clone            # throwaway clone, detached at cfba102
printf '%s' "$(cat prompts/R-5.txt)" \
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
| r1 | `0` | 460007 B, 432 lines, sha256 `bbc471bcee65c270…` | exit 0 — `COMPLETE` | 1 | 13 Bash,  30 Grep,  8 Read | **0** |

Only an exit-0 `COMPLETE` capture is scored. The last column is the ablation's own integrity
check: the clone keeps `plugins/` in the working tree, so a session that read the unablated
`review-lean/SKILL.md` off disk would defeat the line-range ablation. It is counted per run
rather than assumed away.

---

## r1

2026-09-03T19:09:06Z → 2026-09-03T19:17:49Z. stderr empty.

I reviewed the diff against the tree. Bash execution of the guard was blocked by the permission layer, so my findings come from static analysis of the enumerator regex against the five corpus files (verified with targeted searches) rather than from running `check-gate-buckets.sh` — I could not confirm the guard is green on the real tree, though the register's 156 rows match the count cited in `cfba1022`'s message, which is consistent with it passing as committed.

The design is sound and the register is careful work: the denominator-as-artifact posture, the register-internal safety arm (AC-5 in both directions), the `FILENAME`-over-`FNR == NR` fix, and the `not-a-gate` escape hatch with a checked `why` all hold up. AC-7 placement is correct (`lint-and-selftests`, lines 17–201, alongside `check-lockstep-pairs.sh` and `check-eval-model-identity.sh` — not `pr-gates`). AC-9's manifesto edit and register pointer resolve correctly. No `fail-open-sites.tsv` row is owed: the new `| grep -q` sites in the selftest are all `printf`-producers, which `VAR_PRODUCER` excludes.

## Warnings

1. **`exit "$violations"` wraps at 256, against a 305-site denominator** (`scripts/check-gate-buckets.sh:300`). The doctor convention is the repo's precedent (`check-fail-open-shapes.sh:181`, `stack-generality-lint.sh:100`), but those enumerate ~20 sites; this one enumerates 305 and can produce ~460 violations. An edit landing exactly 256 or 512 violations exits 0 and reads as clean. Clamping (`exit $(( violations > 250 ? 250 : violations ))`) costs one line and keeps the convention.

2. **AC-4's covered-site count is printed but never baselined.** The header's own argument is that a loose anchor swallowing a future refusal is "visible rather than silent" — but visibility here is a human reading CI logs. The one direction that matters is the single wired `gates-process` row (`lean-gate.sh::fail_milestone` → `spec-open-region`): if its anchor ever widened enough to cover a new site, nothing reds, and that site becomes operator-waivable. The AMBIG arm only fires when a *second* row disagrees. This is the spec's recorded tradeoff (OR-1/AC-4), so it isn't a defect, but the register's safety claim is weaker than the header reads.

3. **Temp-file leak on partial mktemp failure** (`scripts/check-gate-buckets.sh:161-167`). The `trap` is installed after all three `mktemp` calls, so if the second or third fails, `envfail` exits leaving the earlier file(s) behind. Move the trap up, or add each path to it as it is created.

## Nits

- `*) ROOT="$1"` (`check-gate-buckets.sh:80`) silently accepts an unknown flag as the repo root; `--verbose` becomes a path and reports "corpus file is missing". Same shape as the precedent, so consistent, but it makes a typo look like a tree problem.
- A literal TAB in a corpus source line would truncate awk's `$3` (`check-gate-buckets.sh:241`), so an anchor spanning it matches nothing, the row shows 0 hits, and `grep -qF` then reports it as "outlived what it classified" — a misleading red for a parsing artifact. No corpus file contains a tab today, so this is latent.
- Two byte-identical register rows are accepted silently: both get hits, `nb == 1`, no AMBIG, no zero-hit. Defensible under AC-1 read as "one bucket value", worth a sentence in the header.
- A non-`gates-process` row whose yield names an `OVERRIDE_GATES` value trips both AC-5 checks (`:195` and `:198`) and is reported twice.

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:109` — the command-position regex omits reserved-word position, so a live refusal site is outside the denominator today.** The enumerator requires the primitive to follow line-start or one of `; & | ( ) { }`. A command that begins after a shell reserved word — `then`, `else`, `elif`, `do` — matches neither branch. `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` is exactly that: `      else envfail "unexpected argument: $1"`, with no separator character anywhere on the line. It is a live refusal site at command position and it is not enumerated, so it carries no bucket and the guard is green anyway. The header states its self-exclusions exhaustively ("line start, or after `;`, `|`, `&`, `(`, `)`, `{` or `}`") and AC-8 requires that "a reader can tell an excluded surface from a forgotten one" — this is forgotten, not excluded, and it silently falsifies the "`--list` output IS the denominator" claim that the whole slice rests on. Consequence beyond today's one site: a future `else fail_milestone 3 "lane red"` or `then ticket_refuse …` lands unclassified with CI green, which is the precise failure mode #636 was filed against. Fix is to extend the alternation (e.g. `(^|[;&|(){}]|[[:space:]](then|else|elif|do))`) and add a fixture case, or — if the shape is deliberately out of reach — declare it as a stated residual under AC-8 next to the "newly named primitive" one.

2. **`scripts/check-gate-buckets-selftest.sh:327` and `:333` — both assertions that claim to pin AC-3's definition-line exclusion check the wrong line, and pass vacuously.** In the `$OL` fixture (`:76-84`), line 1 is the shebang, line 2 is `terminal() { launch_note terminal "$1 rc=$2"; exit "$2"; }`, line 3 is `envfail() { terminal "$1" 2 "$2"; }`. g18b asserts no `$OL::terminal` site at **line 1** — line 1 is the shebang and can never be enumerated, so the assertion is true regardless of the guard. g18d asserts no `$OL::envfail` site at **line 3** — but line 3 could only ever be enumerated under the key `$OL::terminal` (via `{ terminal `), never under `$OL::envfail` (`envfail(` has no trailing whitespace), so that assertion is also true regardless. The invariant g18d's own label names — "the exclusion is by the file's whole primitive set, not by the primitive being scanned", which is the reason `grep -vE "^[0-9]+:${defs#^}"` exists at `check-gate-buckets.sh:111` — is therefore untested. Delete that line from the enumerator and both cases still report `ok`. Only g0 (the real-tree case) would catch it, and it would surface as a generic UNCLASSIFIED rather than as an exclusion regression. Given `3196592c` is explicitly a mutation-kill commit and the selftest header advertises g17/g18 as "THE NEGATIVE DIRECTION … pins what the recipe must NOT enumerate", these two need to assert `$OL::terminal` at lines 2 and 3 respectively.

