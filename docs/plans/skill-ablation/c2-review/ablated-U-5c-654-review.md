# C2-a — ablation arm `U-5c`: lines 67–76 removed

One arm of the leave-one-out ablation registered at
[`docs/skill-ablation-addendum.md`](../../../skill-ablation-addendum.md) §C, run 2026-09-03
against sample **C2-a** (PR #654 @ `cfba102`). The SKILL text supplied to the session is
`plugins/dev-pipeline/skills/review-lean/SKILL.md` at `8d5d0897` with **lines 67–76 deleted** —
unit `U-5c`, checklist step 5c, a voided round is handed back. Registered reach: **not-reached**.
Everything below each `## r<n>` heading is that run's output verbatim.

## The realised invocation

```bash
cd /private/tmp/c2b-748/clone            # throwaway clone, detached at cfba102
printf '%s' "$(cat prompts/U-5c.txt)" \
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
| r1 | `0` | 541709 B, 541 lines, sha256 `360102d2b392bfb7…` | exit 0 — `COMPLETE` | 1 | 38 Bash,  8 Grep,  2 Read,  1 Write | **0** |

Only an exit-0 `COMPLETE` capture is scored. The last column is the ablation's own integrity
check: the clone keeps `plugins/` in the working tree, so a session that read the unablated
`review-lean/SKILL.md` off disk would defeat the line-range ablation. It is counted per run
rather than assumed away.

---

## r1

2026-09-03T18:58:02Z → 2026-09-03T19:09:04Z. stderr empty.

I reviewed this statically — the sandbox here won't let me execute the guard, so I reconstructed its enumeration with `grep` and cross-checked it against the register by hand.

**What I verified holds.** The denominator reconciles exactly: 63 `fail_milestone` + 1 `block_milestone` + 12 `fail_obligation` + 12 `ticket_refuse` + 57 `envfail` (lean-gate) + 16 + 21 (lean-evidence) + 50 + 16 (orchestrate) + 23 (operator-override) + 18 + 1 + 15 (check-lean-chain) = **305**, matching the commit message, and the six `envfail` class rows cover exactly the **132** sites the register claims. Register rows = 156, and `grep -cv '^[[:space:]]*\(#\|$\)'` returns 156 on this grep (I probed `\|` alternation directly — it works). Corpus primitive sets are complete against every refusal-shaped helper definition in the five files. AC-7's wiring lands in the always-on guard job beside `check-lockstep-pairs.sh` / `capability-parity-check.sh` ✓. AC-10's obligations check out: `check-fail-open-shapes.sh` needs no new row (every `| grep -q` in the new selftest is a `printf` producer, which its `VAR_PRODUCER` arm excludes), the same-stem rule accounts for the guard in `mutation-sweep.sh` with no pair-map row owed, and all three commits carry `Guard-mass:`. The three `gates-process` rows' yield cells are all valid against `OVERRIDE_GATES='intake-unqueued spec-open-region'` / `OVERRIDE_SCOPES='intake-attestation open-region-resolution'`.

## Warnings

1. **`scripts/check-gate-buckets-selftest.sh:311` (g18d) does not test the mechanism it names.** It claims to pin AC-3's whole-primitive-set definition exclusion — the `orchestrate-lean.sh` case where `envfail() { terminal "$1" 2 "$2"; }` defines one primitive and calls another — but it asserts on key `$OL::envfail` at line 3. That row is never emitted regardless of the code under test, because `envfail(` has no trailing whitespace and so never matches the call regex at all. The site the exclusion actually removes is `$OL::terminal` at line 3. Weaken `defs` to `^[[:space:]]*($p)\(\)` and g18d still passes. (g1 does kill that mutant, via UNCLASSIFIED — so coverage isn't zero, but the case that names the subtlety is vacuous.)

2. **`scripts/check-gate-buckets-selftest.sh:307` (g18b)** checks `$OL::terminal` at line **1** — the shebang. `terminal()`'s definition is on line 2. As with g18d the assertion can't fail; and in this instance there is no mechanism to guard anyway, since the call-shape regex already excludes `terminal(`.

3. **`scripts/check-gate-buckets.sh:300` — `exit "$violations"` truncates mod 256.** Exactly 256 or 512 violations exits 0 and CI reads the guard as green. `check-fail-open-shapes.sh` has the same shape, but over ~20 sites; here a single wholesale register loss already produces 305, so the exposure is materially larger. `exit $(( violations > 250 ? 250 : violations ))` closes it.

## Nits

- `scripts/check-gate-buckets.sh:291` — `%-12s` misaligns `gates-process` (13 chars).
- `scripts/gate-buckets.tsv` (the `terminal preflight-rejected 2 ` row) — the `why` says the intake probe "exits at the resumable code above before this line". It does so only when intake is the *sole* failure (`orchestrate-lean.sh:628`); an unintaken ticket plus any second probe failure lands here. The `gates-signal` disposition still holds (that combination isn't resumable by attendance), but the prose overstates.
- `scripts/check-gate-buckets.sh:186` — for a key naming a file absent from `CORPUS` entirely, the message reads "the enumerator does not scan '<file>' for '<prim>'", implying the file is scanned.
- `scripts/check-gate-buckets.sh:80` — any non-flag argument becomes `ROOT`, so a typo'd `--lst` surfaces as "corpus file is missing".

## BLOCKERS

1. **`scripts/check-gate-buckets.sh:109` — the enumerator drops refusal calls in `then`/`else`/`do`/`elif` command position, and one exists in the corpus today.** The leading-context class `(^|[;&|(){}])` does not include the reserved words, so `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:420` — `      else envfail "unexpected argument: $1"` — is never enumerated. Measured: 58 command-position `envfail` calls in `lean-gate.sh`, 57 in the denominator. **Consequence, two parts.** (a) The header's SELF-EXCLUSIONS section states the rule as "the primitive must sit at the start of a command — line start, or after `;`, `|`, `&`, `(`, `)`, `{` or `}`", and line 420 *is* at the start of a command, so a reader checking the denominator would conclude it is covered when it is not — AC-8's "a reader can tell an excluded surface from a forgotten one" is unsatisfied, and the 305 figure the plan and commit message assert as the shape-enumerated set is short by one. (b) The live failure mode is forward: a future `else fail_milestone 3 "$key failed"` or `then ticket_refuse …` joins the lane carrying no bucket and nothing reds — precisely the silent-rot this slice exists to prevent, and invisible to every other arm since an unenumerated site is neither UNCLASSIFIED nor drift. Nothing is *misclassified* today (the missed site is a usage-error `envfail`, and the class row anchored `envfail ` would absorb it once enumerated, taking that row from 57 hits to 58), so the register needs no edit. Fix the alternation — `(^|[;&|(){}]|\bthen\b|\belse\b|\belif\b|\bdo\b)` — and add a fixture case putting a refusal in `else` position, since no existing case would catch the regression.

