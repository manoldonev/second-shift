# #718 — the continuation stack is deleted: one BUILD spawn, then a human

Pure deletion. The scheduler spawns BUILD **once** per round. The continuation budget, the
advancement token, the infra-death read and the in-flight recovery all go; a build that ends
without a PR, or with a PR and uncollected work beside it, stops the run and hands it to a
human.

Ratified by the operator on 2026-08-30 (twice — the second against the re-cut): *"pure deletion;
nothing added."* Parent epic #717.

## Base state

Every number below is **re-derived at `10e0928`**, this branch's base — not at `ff3f6f8`, the
head the ticket body was written against. `#732` landed in between and moved three of the four
subject files, so the ticket's `16,617` / `542/520` / `[base: 24]` figures no longer describe
anything measurable. The ticket's *thresholds* are inherited unchanged; only their operands are
re-measured.

| File | Symbol | Lines at `10e0928` |
| --- | --- | --- |
| `plugins/dev-pipeline/skills/run-lean/orchestrate-lean.sh` | `OL` | 1146 |
| `plugins/dev-pipeline/skills/build-lean/lean-gate.sh` | `LG` | 5821 |
| `plugins/dev-pipeline/skills/run-lean/orchestrate-lean-selftest.sh` | `OLS` | 1826 |
| `plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh` | `LGS` | 8374 |
| | **sum** | **17167** |

`LGS` pin multiset at base: **561** `pass "(id)` occurrences over 539 distinct ids.
`OLS` pin multiset at base: **119** occurrences over 119 distinct ids.
`git grep -o 'max-continuations' -- . ':!docs/plans' ':!CHANGELOG.md' | wc -l` at base: **25**.

## What is deleted

**`OL`** — `MAX_CONTINUATIONS`, `MAX_INFLIGHT_RECOVERIES`, `progress_token()`, `infra_token()`,
the `--max-continuations` flag arm and its validator, the `continuations`/`inflight_recoveries`
counters, the `tok_before`/`tok_after`/`infra_before`/`infra_after` reads, the `build-idle`,
`build-continuations-spent`, `progress-unreadable` and `infra-unreadable` terminals, and the
inner `while :` loop that existed only to re-spawn. The `progress --obligations` call
(`closeout_report`) stays.

**`LG`** — `progress_token()`, `infra_token()`, the `--infra` flag and its two validators, and
`cmd_progress`'s no-flag arm. `--obligations` and `--satisfied` stay.

**`OLS`** — cases `(o1)`–`(o8)`, `(oi1)`–`(oi5)`, `(t1)`, `(t1b)`, `(t3)`, `(t4)`, `(j3)`, `(v4)`.

**`LGS`** — cases `(ir1)`–`(ir4)`, `(ir9)`, `(ir10)`, `(pg1)`–`(pg4)`.

**`scripts/gate-buckets.tsv`** — the rows for `build-idle`, `build-continuations-spent`,
`progress-unreadable`, `infra-unreadable`.

**`docs/config-schema.md`** — the `--max-continuations` clause in the exit-3 exposure note.

**`scenario-liveness-selftest.sh`** — the `te_token()` helper and the two `progress --infra`
token assertions inside `(lean-inline-m3)` / `(lean-inline-m3-nv)`.

## What is added

Exactly one new production line: `terminal build-no-pr 1 "…"` in `OL`, plus its one
`gate-buckets.tsv` row. `--max-continuations` becomes a usage refusal naming the removal, in
place of its old parse arm.

## Departures from the ticket body, and why

- **D-A. `--satisfied`'s token is renamed, not kept.** AC-1 forbids the string `progress-v1` in
  `LG`, and the surviving `--satisfied` reader printed exactly that prefix. Keeping the prefix
  reds AC-1; dropping `--satisfied` breaks `OL`'s `rc=3` close-out arm, which AC-7 protects. So
  the gate's reader is renamed `satisfied_token()` and its prefix becomes `m5sat-v1:`. `OL`
  compares it for equality only, so nothing about the comparison changes.
- **D-B. `OL`'s surviving `--satisfied` reader is renamed too**, for the same AC-1 reason —
  `satisfied_token()` in place of `progress_token()`. Not a new code path: the same two-line
  subshell, minus the continuation-predicate rationale its header carried.
- **D-C. `(j3)`, `(v4)` and liveness leg 9 are deleted, though the ticket lists none of them.**
  `(j3)`'s whole assertion is `progress_reads adv >= 2 && progress_reads infra >= 2` — the two
  reads this ticket removes. `(v4)` drove two BUILD spawns in ONE build phase so a staleness read
  count of 2 could only mean "per BUILD spawn"; one phase now has one spawn, and `(v5)` makes the
  same distinction over two ROUNDS. Leg 9 (`lean-infrakill`) composed a real `kill -9` through to
  a terminal write via the continuation. None can survive the deletion it asserts the presence of.
- **D-D. `(t3)`'s surviving half is folded into `(h4)` rather than lost.** `(t3)` is deleted as
  ratified, but the boundary it pinned — `inflight_rc` runs from the MAIN checkout with no
  ambient `RUN_ID` — describes a call that survives. `(h4)`'s rc-8 arm asserts it, so the
  deletion costs no coverage.
- **D-E. `(ob7)`, `(pg7)`, `(pg8)` and `(pg10)` are re-anchored, not deleted.** `(ob7)` pins
  that `--obligations` refuses to combine with a token flag; `--satisfied` is still such a flag,
  so the case drives that pair instead of the deleted `--infra` one. Each pins a property of
  the *reader* (scoping, not-a-creator, generation prefix) that `--satisfied` still has. They
  keep their ids and their subjects, and swap the bare-token call for a `--satisfied` one.
  `(pg9)` is `(pg8)`'s positive control and stays with it.
- **D-G. AC-1's `progress-unreadable` alternand is anchored** as `terminal progress-unreadable`
  — see the AC itself for the substring collision that forces it.
- **D-F. `(td2)` and `(if9)` keep their ids and assertions** and swap the token helper for a
  direct `grep -c '| satisfied'` over the progress file, per the ticket.

## Acceptance criteria

- **AC-1** — for `OL` and `LG`:
  `! grep -qE 'MAX_CONTINUATIONS|MAX_INFLIGHT_RECOVERIES|progress_token|infra_token|tok_before|tok_after|infra_before|infra_after|inflight_recoveries|continuations=|build-idle|build-continuations-spent|terminal progress-unreadable|--infra|progress-v1'`
  holds on both. Base: reds on both (35 and 22 matching lines). *Mutant:* any residue.

  **Amended (D-G).** The ticket's alternation carried a bare `progress-unreadable`, which is a
  SUBSTRING of the surviving terminal `verdict-progress-unreadable` — the `rc=3` close-out arm's
  fail-closed stop, which nothing in this ticket deletes and AC-7 depends on. The bare form is
  unsatisfiable without deleting a slug the ticket keeps, so the alternand is anchored on the call
  form `terminal progress-unreadable`, which is the only way the deleted slug is ever written.
  Every other alternand is verbatim.
- **AC-2 `(h4)`** — a new `OLS` case, two arms. Fake `claude` rc 0, no PR, clean tree ⇒ exactly
  **1** BUILD spawn, terminal slug `build-no-pr`, exit 1. Same fixture with the `inflight` fake
  answering rc 8 ⇒ terminal slug `build-inflight`, exactly **1** BUILD spawn, and the in-flight
  read made from the main checkout with `RUN_ID` scrubbed (D-D). *Mutant:* re-add
  `continuations=$((continuations+1)); continue` ⇒ 2 spawns.
- **AC-3** — `wc -l` of `OL` + `LG` + `OLS` + `LGS` at head ≤ **16717** (base 17167 − 450). Both
  sums stated in the PR body.
- **AC-4** — the `LGS` pin multiset
  (`grep -oE 'pass "\([a-z0-9-]+\)' | sort | uniq -c`) at head equals the base multiset minus
  exactly `(ir1) (ir2) (ir3) (ir4) (ir9) (ir10) (pg1) (pg2) (pg3) (pg4)` and plus exactly
  `(pg13)` — 561 → **552** occurrences. `(ob7)`, `(td2)`, `(if9)`, `(pg7)`, `(pg8)`, `(pg9)`,
  `(pg10)` are NOT on the removal list. The `OLS` multiset equals base minus
  `(o1)…(o8) (oi1)…(oi5) (t1) (t1b) (t3) (t4) (j3) (v4)` plus `(h4)`×3 — 119 → **103**.
  `(h4)` carries three arms under one id: the no-PR stop, the in-flight stop, and the removed
  flag's usage refusal.
  *Mutant:* delete a re-anchored case instead of swapping its helper.
- **AC-5** — `bash scripts/check-gate-buckets.sh` exits 0. *Mutant:* leave a deleted terminal's
  row behind, or omit `build-no-pr`'s.
- **AC-6** — `git grep -n 'max-continuations' -- . ':!docs/plans' ':!CHANGELOG.md'` returns only
  `OL`'s usage-refusal line and the `OLS` case that drives it. Base: 25 occurrences across 6
  files.
- **AC-7** — `bash "$LG" progress <issue> --obligations` still prints the obligations report and
  `--satisfied <n>` still prints a token; bare `progress <issue>` with no flag exits **2** with a
  message containing `unknown`. Pinned as `LGS` case `(pg13)`.
- **AC-8** — `plugins/dev-pipeline/skills/build-lean/scenario-liveness-selftest.sh` still
  composes `(lean-inline-m3)` and `(lean-inline-m3-nv)` over the `started`/`concluded` residue
  itself, with no `progress --infra` call anywhere in the repo's shipped scripts. Leg 9
  (`lean-infrakill`, `lean-infrakill-nv`) is DELETED — its whole subject was the scheduler
  continuing after a killed evaluation, and there is no composed verdict path left for it to
  reach. *Mutant:* delete `(lean-inline-m3-nv)` rather than re-anchor it, leaving the leg above
  green against a gate that closes its pair unconditionally.
- **AC-9** — `plugins/dev-pipeline/hooks/hooks.json` is unchanged and has no `Stop` hook
  (`jq -e '.hooks.Stop == null'`). Nothing is added while here.

## Adversarial pass

| Botch | Closed by |
| --- | --- |
| Keep the loop "as a fallback" | AC-1, AC-2 |
| Delete `INTERRUPTED_BUDGET`, `--obligations` or `--satisfied` as "residue" | AC-7; AC-1 does not name them |
| Delete re-anchorable cases to hit AC-3 | AC-4 |
| Drop the liveness scenario because its token is gone | AC-8 |
| Add a hook or a script "while here" | AC-3, AC-9 |
| Leave `docs/config-schema.md` naming a deleted flag | AC-6 |

## Decision Ledger

No pre-flight ledger was produced for this ticket; the operator's two ratification comments on
the issue are the binding input. D-A … D-F above are this build's own decisions, recorded as
departures from the ticket body's letter.

| id | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | What replaces the continuation loop | One BUILD spawn per round; no PR ⇒ `build-no-pr`, PR + rc 8 ⇒ `build-inflight`, both terminal | user-answered |
| D-2 | Whether a Stop hook backstops the stranded-work exit | No. Rescued by hand with the recipe in `build-lean/SKILL.md`; a Stop hook needs a measured rate first | user-answered |
| D-3 | Whether `--satisfied` survives | Yes — `OL`'s `rc=3` close-out arm reads it; only its prefix and function name change (D-A) | codebase-derived |
| D-4 | Where the deleted `(t3)` boundary goes | Folded into `(h4)`'s rc-8 arm (D-D) | codebase-derived |
