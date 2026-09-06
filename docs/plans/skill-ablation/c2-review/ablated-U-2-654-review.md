# C2-a — ablation arm `U-2`: lines 29–30 removed

One arm of the leave-one-out ablation registered at
[`docs/skill-ablation-addendum.md`](../../../skill-ablation-addendum.md) §C, run 2026-09-03
against sample **C2-a** (PR #654 @ `cfba102`). The SKILL text supplied to the session is
`plugins/dev-pipeline/skills/review-lean/SKILL.md` at `8d5d0897` with **lines 29–30 deleted** —
unit `U-2`, checklist step 2, `gh pr view` to resolve the head branch and issue key. Registered reach: **not-reached**.
Everything below each `## r<n>` heading is that run's output verbatim.

## The realised invocation

```bash
cd /private/tmp/c2b-748/clone            # throwaway clone, detached at cfba102
printf '%s' "$(cat prompts/U-2.txt)" \
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
| r1 | `0` | 458499 B, 456 lines, sha256 `ca3a6abe23d14a07…` | exit 0 — `COMPLETE` | 1 | 15 Bash,  23 Grep,  5 Read | **0** |

Only an exit-0 `COMPLETE` capture is scored. The last column is the ablation's own integrity
check: the clone keeps `plugins/` in the working tree, so a session that read the unablated
`review-lean/SKILL.md` off disk would defeat the line-range ablation. It is counted per run
rather than assumed away.

---

## r1

2026-09-03T18:50:12Z → 2026-09-03T19:00:03Z. stderr empty.

I reviewed the guard against the real corpus. I could not execute `check-gate-buckets.sh` or its selftest in this session (the Bash tool declined to run them), so the findings below are derived by reading the code against the tree — the enumeration hole I verified by replicating the enumerator's own regex with ripgrep over the five corpus files.

## What holds up

The shape is right and the register is substantive. Spot-checks I ran that came back clean:

- **AC-7** — the step is in the always-on guard job beside `check-lockstep-pairs.sh` / `check-eval-model-identity.sh` (`ci.yml:164`), not `pr-gates`. Correct.
- **AC-3 coverage** — all 48 live `terminal` call sites in `orchestrate-lean.sh` have a slug present in the register; `check-lean-chain.sh::fail` really is 1 site (D-6's stale-count note is accurate); `envfail()`'s one-line definition at `orchestrate-lean.sh:336` genuinely is a `terminal`-shaped line that only the whole-primitive-set exclusion removes, so AC-3's "by the file's whole declared primitive set" is load-bearing rather than decorative.
- **Anchor over-reach** — the two anchors that worried me most (`fail_milestone 1 "$reason"`, the `spec-open-region` yield row; `fail_milestone 5 "$2"`) are each unique in `lean-gate.sh`. The `preflight-rejected` / `preflight-rejected-resumable` pair does not nest.
- **AC-10** — no new `fail-open-sites.tsv` row is owed: every `| grep -q` in the selftest is a `printf` producer, which `check-fail-open-shapes.sh`'s `VAR_PRODUCER` already excludes; the guard's own two `grep -q`s read files, not pipes. `Guard-mass:` and `Changelog:` trailers are on all three commits.
- **AC-9** — `gates-signal` and the register pointer are the only copies of the bucket vocabulary outside `scripts/`; no agent contract or SKILL.md restates the binary predicate, so nothing drifted.
- The `FILENAME == ENVIRON["CB_ROWS"]` fix (over `FNR == NR`) and the count-as-you-build distinct-bucket set are both correct, and g22/g5 pin them.

## Warnings

**W1 — the register contradicts an already-settled bucket, with no departure recorded.** `docs/prose-blocker-triage.tsv:40` (`pb-94ee597a`) says of `scripts/check-lean-chain.sh::verdict-record`: *"The all-dark rule, settled KEEP / **gates-llm** by the parent epic. Its bucket is pre-settled, its disposition was not."* This PR classifies that same refusal — the absent verdict record, which `check-lean-chain.sh` delegates to `lean-evidence.sh` — as **`gates-signal`** (`gate-buckets.tsv`, anchor `note_violation "no committed verdict record (a file named *-$KEY$LEAN_VERDICT_SUFFIX)`), and `lean-gate.sh`'s milestone-4 sibling likewise. Both buckets never yield, so nothing becomes waivable — but this is a reversal of a bucket the parent epic recorded as pre-settled, on the one axis this slice exists to settle, and the Decision Ledger says nothing about it. D-6 shows the pattern for this (a judgment recorded about why no DEPARTURE row is owed); either take that route or move the rows to `gates-llm`.

**W2 — `ci.yml:159-163` claims to discharge a residual it does not touch.** The comment says *"#610 D-9 left prose-blockers.sh's coverage unwired because 'the parent's register owns the living coverage guard'; this is it."* D-9's residual is the **prose census** — SKILL.md constructs against `docs/prose-blocker-triage.tsv` rows, keyed `path::enforcer-name`. This guard enumerates **shell refusal primitives** in five files, keyed `path::primitive`. Different denominator, different register, no overlap in what is counted. A reader auditing #610's open residuals will now find it marked closed by a step that never looks at it.

**W3 — the "132" in four `why` cells is the aggregate, not the class.** Each of the `lean-evidence.sh::envfail`, `lean-gate.sh::envfail`, `operator-override.sh::envfail` and `check-lean-chain.sh::envfail` rows says *"so 132 near-identical rows would add no classification"*. 132 is the total `envfail` occurrence count across all five files; the per-file figures are 21, 57, 23 and 15. At most one of the four can be right, and none is. The mechanism each cell names (the exit-2 contract) is correct and is what AC-1 actually requires — only the count is wrong — but the register is the artifact a human reads, and the guard's printed per-row count will visibly disagree with it.

**W4 — `terminal preflight-rejected 2 `'s `why` overstates the resumable exit.** It claims *"The one probe whose premise is an absent human exits at the resumable code above before this line."* `orchestrate-lean.sh:630` claims exit 3 **only when the intake probe is the sole failure**; when `r1 -eq 3` and any of `r2`/`r3`/`r4` also fails, control reaches line 634 with the unintaken ticket among the reasons. The `gates-signal` disposition still stands (a co-failing probe is not premised on an absent human), but the sentence as written is false for that combination.

## Nits

**N1** — `check-gate-buckets.sh:145` says the key-validation is *"Pure bash on purpose: this runs once per register row, and a subprocess per row is what the batching below exists to remove."* `in_set "$rprim" "$(corpus_prims "$rfile")"` forks a subshell per row — 156 of them. It's cheap (no exec), but the comment claims the opposite of what the code does, in the one file where that claim is the stated design rationale.

**N2** — the `trap 'rm -f ...' EXIT` is installed after all three `mktemp`s; if the second or third fails, `envfail` exits with the earlier temp files leaked.

**N3** — AC-5 direction 2 (`the yield cell names an OVERRIDE_GATES value but the row is not gates-process`) can never fire alone: any such cell is also `!= "-"`, so direction 1 fires first and the row reports two violations. Intentional-looking (the second message is the more specific one), but worth knowing that g8 is asserting on the second of two.

**N4** — `docs/plans/second-shift-636-lean.md` carries no `## Design` section at all. Every sibling spec (`-610`, `-612`, `-604`, `-609`…) carries an explicit `Design: none — <reason>`. Nothing enforces it here (`design_state()` short-circuits to `unarmed` because this repo configures no `design.provider`), so it costs nothing today — but the convention is otherwise unbroken.

## AC scoring

| AC | Score |
| --- | --- |
| AC-1 | satisfied — closed enum checked, `not-a-gate` `why` prefix checked mechanically, "exactly one disposition" enforced via the AMBIG arm |
| AC-2 | **unsatisfied** — the three disagreements red independently and `--list` checks nothing, but the enumeration the guard checks against is not the enumeration the header claims (B2) |
| AC-3 | satisfied — every primitive per file is named; the whole-set definition exclusion is real and cased (g18d) |
| AC-4 | satisfied — one row per site by default, `hits > 0`, per-row count printed, zero-hit rows red |
| AC-5 | satisfied — both directions, vocabulary read from `operator-override.sh` at run time, empty vocabulary is exit 2 |
| AC-6 | satisfied — form-only check, `unwired — <reason>` accepted |
| AC-7 | satisfied |
| AC-8 | **unsatisfied** — the header's third self-exclusion is stated as "non-command positions", but the implementation also drops genuine command positions after a reserved word (B2). A reader cannot tell the excluded surface from the forgotten one, which is the AC verbatim |
| AC-9 | satisfied |
| AC-10 | satisfied — no new ablation reason, no new fail-open row owed, no `lean-gate.sh` call site added, `Guard-mass:` trailer present on all three commits |

Design fidelity: **not-applicable** — the spec arms no `## Design` section and this repo configures no design provider.

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:297` — GNU-only BRE alternation reds the macOS CI lane.** The register row count is computed with `grep -cv '^[[:space:]]*\(#\|$\)'`. `\|` is a GNU BRE extension; it is undefined in POSIX BRE and BSD/macOS `grep` (FreeBSD grep over the Spencer `regcomp(3)` in libSystem) reduces a backslashed ordinary character to the literal, so the pattern degrades to "a line whose content is literally `#|` at end of line" — which matches nothing, and `grep -cv` then returns the **total line count**. `ci.yml:383` runs a `selftests (macos, bash 3.2)` lane over `run-selftests.sh --full`, which picks up `check-gate-buckets-selftest.sh`; case **g1c** asserts the verdict line contains exactly `all bucketed by 10 register row(s)` against a fixture register of 10 rows plus a comment line and a blank line. On that lane the guard prints `12`, g1c fails, the selftest exits 1 and the macOS job is red. On the real tree the same expression prints `230` instead of `156`. Every other pattern in this script already uses `grep -E`; this is the only BRE, and no other `.sh` in the repo uses `\|` in one. Fix: `grep -cvE '^[[:space:]]*(#|$)'`. (I could not run either grep here to demonstrate the divergence — the finding is from the regex semantics plus the g1c assertion and the fixture's line count, both of which are in the diff.)

2. **`scripts/check-gate-buckets.sh:109` — refusal sites after a shell reserved word are silently outside the denominator.** The enumerator requires the primitive to be preceded by `(^|[;&|(){}])[[:space:]]*`. A command position introduced by `else`, `then`, `elif` or `do` matches none of those characters, so the line is never enumerated — and because it is never enumerated, no row is owed for it and the guard stays green. This is live today: `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420`, `else envfail "unexpected argument: $1"`, is a real refusal site that is in neither `--list`'s output nor `gate-buckets.tsv`. Today's consequence is contained (it is an `envfail`, which the register disposes of as `not-a-gate` wholesale), but the mechanism is not: the next `else fail_milestone …` or `then ticket_refuse …` added to a corpus file lands unclassified with CI green, which is precisely the failure this guard is filed against. It also falsifies the header's own accounting — the third self-exclusion is written as "non-command positions", and line 420 *is* a command position, so an unstated exclusion is doing the work (AC-8, AC-2). Fix by admitting the reserved words into the leading context, e.g. `(^|[;&|(){}]|[[:space:]](then|else|elif|do))[[:space:]]*`, and re-stating the exclusion to match what the pattern actually does. Adding the case to the selftest's `negatives`/positives fixture would pin it.

