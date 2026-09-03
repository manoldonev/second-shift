# C2-a — ablation arm `U-7`: lines 86–89 removed

One arm of the leave-one-out ablation registered at
[`docs/skill-ablation-addendum.md`](../../../skill-ablation-addendum.md) §C, run 2026-09-03
against sample **C2-a** (PR #654 @ `cfba102`). The SKILL text supplied to the session is
`plugins/dev-pipeline/skills/review-lean/SKILL.md` at `8d5d0897` with **lines 86–89 deleted** —
unit `U-7`, checklist step 7, commit and push the record, last on the branch. Registered reach: **not-reached**.
Everything below each `## r<n>` heading is that run's output verbatim.

## The realised invocation

```bash
cd /private/tmp/c2b-748/clone            # throwaway clone, detached at cfba102
printf '%s' "$(cat prompts/U-7.txt)" \
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
| r1 | `0` | 476688 B, 445 lines, sha256 `6c97ca0a594dfaa7…` | exit 0 — `COMPLETE` | 1 | 37 Bash,  5 Grep,  7 Read | **0** |

Only an exit-0 `COMPLETE` capture is scored. The last column is the ablation's own integrity
check: the clone keeps `plugins/` in the working tree, so a session that read the unablated
`review-lean/SKILL.md` off disk would defeat the line-range ablation. It is counted per run
rather than assumed away.

---

## r1

2026-09-03T19:00:06Z → 2026-09-03T19:09:17Z. stderr empty.

I have enough to conclude. Here's my review.

## Summary

The design is sound and the register is genuinely complete against what the enumerator emits — I verified independently that every `terminal` slug (28) and every `envfail` slug (`env-*` / `usage-*`) in `orchestrate-lean.sh` is covered, that the three `gates-process` anchors (`fail_milestone 1 "$reason"`, `terminal preflight-rejected-resumable 3`, the ratification `note_violation`) are each unique and correctly classified, and that `terminal preflight-rejected 2 ` cannot bleed into `terminal preflight-rejected-resumable 3 `. AC-3's per-file primitive sets match the actual helper definitions in all five corpus files. CI wiring is the always-on `lint-and-selftests` job (AC-7 ✓), `tools/run-selftests.sh`'s `find -name '*-selftest.sh'` discovers the suite and resolves its subject by naming convention, the manifesto edit and its relative link are correct (AC-9 ✓), and the `Guard-mass:`/`Changelog:` trailers are present (AC-10 ✓).

Two defects survive that review.

## Warnings

1. **Refusals not routed through a declared primitive are silently outside the denominator, and the header does not say so.** `check-lean-chain.sh:189`, `:568`; `lean-evidence.sh:160`, `:849`; `operator-override.sh:540` all refuse via a bare `exit 2` rather than through a corpus primitive. All are environment/usage refusals today, so nothing is misclassified — but the header at `check-gate-buckets.sh:56-60` names only one residual ("a NEWLY NAMED refusal helper"), which reads as though inline refusals were considered and aren't a thing. AC-8 asks that a reader be able to tell an excluded surface from a forgotten one; this class is currently indistinguishable from forgotten.

2. **`in_set` glob-matches, so AC-6's positive direction can pass without naming a real value.** `check-gate-buckets.sh:146` — `case " $2 " in *" $1 "*)` leaves `$1` unquoted, so it is a pattern, not a literal. A `gates-process` row whose yield cell is `*` (or any glob) satisfies "names an OVERRIDE_GATES/OVERRIDE_SCOPES value" against a vocabulary that contains no such value. Low likelihood, but it is a fail-open inside the arm whose whole job is to keep the yield cell honest. `"$1"` fixes it.

3. **`exit "$violations"` truncates mod 256.** `check-gate-buckets.sh:300`, against a 305-site denominator. A register wipe today gives 305 → exit 49, still red; a tree state producing exactly 256 violations exits 0. `check-fail-open-shapes.sh` carries the same shape so this is a shared precedent rather than a new hazard, but this guard is the one with a denominator above 256.

## Nits

- `check-gate-buckets.sh:195` and `:198` overlap completely — a non-`gates-process` row whose yield names an override value trips both, counting one defect as two and inflating the exit code.
- `check-gate-buckets-selftest.sh:294-300` (g12b): the case appends `key<TAB><TAB>anchor<TAB>-<TAB>why`, but `IFS=$'\t'` makes TAB IFS-whitespace, so bash collapses the doubled tab and the row is read as four fields. It reds on field count via the same path g12 already covers, not on the empty cell — the `ok` message ("the field count is not the check, the field CONTENT is") describes the opposite of what happens.
- `check-gate-buckets-selftest.sh:330-332` (g18c) is confounded: `launch_note terminal` sits on fixture line 2, which the definition-line exclusion removes regardless, so the command-position rule the case claims to pin is not isolated by it. It is pinned in practice by g0 against the real tree (`orchestrate-lean.sh:333`).

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:109` — the command-position regex misses a refusal that follows a shell keyword, and one such site is live in the tree right now.** The enumerator requires the primitive to sit at line start or after `[;&|(){}]`. `else`, `then`, `elif` and `do` also open a command, and none is in that class. `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` — `else envfail "unexpected argument: $1"` — is therefore not enumerated, while its sibling arm two lines up (`:416`, `-*) envfail "unknown option: $1"`) is, because `)` happens to be in the class. I verified this is the only current miss across all five corpus files and all ten primitives, and that it changes no classification today (it is an `envfail`, `not-a-gate` either way). The consequence is to the guard's sole claim: a future `else fail_milestone 3 "…"` or `then ticket_refuse "…"` is outside the denominator entirely, so AC-2's first red arm ("an enumerated site no row claims") can never fire for it and the register stays green while no longer describing the lane. The header at `:52-54` states this exclusion as if the list were exhaustive, so it also fails AC-8's "a reader can tell an excluded surface from a forgotten one." Extend the character class to cover the keyword-prefixed forms (or anchor on a word boundary and exclude argument position explicitly), and add the `else`-form to the fixture so the case is pinned.

2. **`scripts/check-gate-buckets-selftest.sh:327` — g18b asserts against the wrong line and is vacuous, leaving AC-3's cross-primitive definition exclusion with no targeted coverage.** In the `$OL` fixture (`:76-84`), line 1 is the shebang, line 2 is `terminal() { launch_note terminal "$1 rc=$2"; exit "$2"; }`, line 3 is `envfail() { terminal "$1" 2 "$2"; }`. g18b checks for `$OL::terminal` at `$2 == 1` — the shebang — so it passes whether or not the definition-line exclusion exists, despite reporting "terminal()'s own definition line is not enumerated." It should be `$2 == 2`. The companion case g18d (`:333`) checks `$OL::envfail` at line 3, which the ordinary same-name exclusion already covers; to test what its message claims — that the exclusion is by the file's *whole* primitive set, which is the non-obvious rule `defs` exists for and that AC-3 calls out by name — it needs to check `$OL::terminal` at line 3. As written, neither assertion in the pair exercises the rule; it survives only incidentally through g1/g1c's site count. For a PR whose deliverable is a guard plus a behavioral suite that AC-2 requires to cover each arm, a passing assertion that reads as coverage it does not provide is worse than an absent one.

