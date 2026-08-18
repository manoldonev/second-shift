# #585 — the nightly sweep of record is deterministically red

## Corrected premise (binding — supersedes the ticket body)

`.claude/pipeline-state/585-ledger.md` is the pre-flight receipt and is binding input. Its
correction to the ticket body is load-bearing, so it is restated here as the definition of the
problem this PR solves.

The nightly `mutation-sweep` redness has **three independent causes**, not one. The ticket body
names a single survivor and attributes to it a date range and a shard that belong to a different
cause:

| Night | SHA | Shard | Actual `RED:` line | Status |
| --- | --- | --- | --- | --- |
| 08-13, 08-15, 08-16 | e6a16ef, dc2db95 ×2 | 1 | `pool disagreement` (`lean-evidence.sh::cmp-z::1`, then `check-fail-open-shapes.sh::default::2`) | **already closed by #558** (`ec42f38`, 08-16 20:52) — needs no work here |
| 08-17, 08-18 | 33e6187, a8cd2b5 | 9 | `orchestrate-lean.sh::fail-open::1` + `orchestrate-lean.sh::detector::1`, baseline-absent | **in scope** (D-3) |
| 08-18 | a8cd2b5 | 10 | `doctor.sh::cmp-z::1`, baseline-absent | **in scope** (D-2) |

Both live causes are fixed here, in one PR (D-1). Fixing only the survivor the ticket names
would leave shard 9 red and the stated goal — a green moat before #579 re-keys baseline rows —
unmet, while reading as "the sweep is fixed".

`doctor.sh::cmp-z::1` is **one night old** and on **shard 10**, not "since 08-15 on shard 9".

## Root causes

**`doctor.sh::cmp-z::1` — a case that passes by ordering coincidence (D-6).** #568 (`dc6021f`)
inserted a `*-lean-progress.md` newest-scan loop at the top of `state_excerpt()`. Its
`[[ -z "$newest" || "$f" -nt "$newest" ]]` is the file's new `cmp-z` ordinal 1. The `-z `→`-n `
flip degenerates the loop to "take the **last** file in glob order": with `newest=""` the guard
`[[ "$f" -nt "" ]]` is true (bash `-nt` is true when the second operand does not exist), and every
later iteration short-circuits on the now-true `-n "$newest"`. `doctor-selftest.sh`'s
`report-state-excerpt-lean-newest` case fixtures `88-lean-progress.md` (old) and
`99-lean-progress.md` (new) — the newest file is **also** last in glob order, so mutant and
original select the same file and the case cannot tell them apart. The gap is the fixture's
ordering, not a missing case.

#568's own PR sweep never saw it: `defer … doctor.sh -> nightly: PR-lane cap (6 fast guards
already swept)` — the accepted one-day trade working as designed.

**The `orchestrate-lean.sh` pair — one prose line, two operators (D-7).** #548 (`f9c8777`) added
`orchestrate-lean.sh:251`, a comment containing both the literal the `fail-open` operator matches
and a `grep`-plus-quoted-string the `detector` operator matches, so a single prose line became
ordinal 1 for two operators. Compounding it, #568 deleted all thirteen real status-1 exit sites
(the taxonomy that comment describes) by routing them through `terminal()`: at `128586c` the file
had 14 `fail-open` sites, at HEAD it has **1 — the comment**. `fail-open` is now genuinely
non-applicable to this guard, and the comment is manufacturing a phantom site while pushing a real
`detector` site out of the k=2 budget window.

## Scope

Both remedies are the ones the receipt fixes; neither is re-derived here.

- **D-2** — strengthen the existing `report-state-excerpt-lean-newest` case **in place** so the
  newest `*-lean-progress.md` is not last in glob order. No new case, no new fixture tree, no
  baseline churn. `state_excerpt()` itself is not edited: its behavior is correct, and changing it
  would be the regression rather than the fix (S-7).
- **D-3** — **reword** `orchestrate-lean.sh:251` so it matches neither ERE. Zero baseline rows
  added, so #579's re-keying has nothing new to collide with. Baselining the pair was rejected at
  intake: it would record an accepted survivor for an operator that has no applicable site.
  Comment-only — any behavior or exit-code change here would mean the reword touched code (S-8).
- **D-5** — the enumerator-level fix (prose never becoming a mutation site) is **out of scope**,
  owned by #567's decomposition (#579/#583). Duplicating it here collides with that program's
  sweep-wide re-keying.
- **D-4** — #585 is a hard merge precondition for #579.

## Acceptance criteria

**AC-1** — `plugins/dev-pipeline/skills/run-lean/orchestrate-lean.sh` line 251 is reworded so that
`grep -nE -- 'exit 1'` over the file returns **zero** lines, and the `detector` ERE
`grep[^|;&]*('[^']*'|"[^"]*")` no longer matches it. The reword preserves the paragraph's meaning:
a reader still learns that a naive text count over this file used to return thirteen terminal
sites, that one of them conflated three remedies, and that every run-ending exit now prints a
stable slug.

**AC-2** — The reword is comment-only. `git diff` on that file touches no executable line, and the
matched-line **sequence** of every other operator (`cmp-eq`, `cmp-z`, `logic`, `default`) over
`orchestrate-lean.sh` is byte-identical base-to-head. Only `detector` changes, and only by losing
line 251 — its remaining sites keep their relative order and shift down by exactly one ordinal.

**AC-3** — `tools/mutation-baseline.tsv` is **unchanged**: no row added, removed, or re-keyed.
`orchestrate-lean.sh` has no `fail-open` or `detector` baseline row today, so the ordinal shift in
AC-2 re-keys nothing that exists. Post-fix `detector` ordinals 1 and 2 (the `$QUEUE_LABEL` and
`$CLAIMED_LABEL` label probes) are both killed by the guard's existing kill set, so no new row is
owed either.

**AC-4** — `doctor-selftest.sh`'s `report-state-excerpt-lean-newest` case is strengthened in place
so the file `state_excerpt()` must select by mtime is **not** the last entry in the directory's
glob order. The case keeps its name, its position, and its two assertions (the newer marker
present, the older marker absent). No new case is added and no new fixture tree is created.

**AC-5** — `plugins/second-shift/skills/doctor/tools/doctor.sh` is **not modified**. The fix is
test-only; `state_excerpt()`'s observable output for every input is unchanged.

**AC-6** — Applying the `cmp-z` operator's flip to `doctor.sh` ordinal 1
(`[[ -z "$newest" || "$f" -nt "$newest" ]]` → `[[ -n "$newest" || … ]]`) makes
`report-state-excerpt-lean-newest` **fail**, and `doctor-selftest.sh` passes unmutated. Both
directions are demonstrated, not asserted — a case that reds only because the suite is broken is
not a kill.

**AC-7** — The green gate passes on the branch: `shellcheck` over every `*.sh`, `jq empty` over
every `*.json`, and `SKIP_STRESS=1 bash tools/run-selftests.sh --exclude
tools/install-topology-selftest.sh`.

**AC-8** — Pre-merge proof of the kills is a **dispatched** `mutation-sweep.yml` run on this
branch (`gh workflow run mutation-sweep.yml --ref claude/second-shift-585`), which with the
baseline present and `seed=false` is **enforcing**, in the canonical `ubuntu-latest` +
`SKIP_STRESS=1` environment (D-8). The PR lane cannot prove it — it defers `doctor.sh` under the
six-fast-guard cap, which is exactly how #568 shipped this. Local macOS runs are advisory only
(`RUNNER_OS` must be `Linux`). The run's conclusion and id are recorded on the PR.

**AC-9** — The PR body carries the corrected triage table above. #579/#583 key off survivor
identity, so a wrong attribution left in the record is the input that poisons them (D-9).

## Open Regions

| ID | Region | Disposition | How it is discharged here |
| --- | --- | --- | --- |
| OR-1 | Durability of the D-3 reword — nothing prevents a future comment from re-introducing a phantom mutation site | reversible-default-and-flag | The reword ships as the stated default (reversing it is a one-line edit with no downstream consumers). The residual risk is **flagged** in the PR body and by a short in-file note at the site, itself worded to match neither ERE. The durable fix is owned by #579/#583. |
| OR-2 | Whether the dispatched sweep surfaces a further baseline-absent survivor beyond the two in scope | **pause-and-ask** | All ten shards ran on 08-18 and only 9 and 10 failed, so the expected finding is none. A new one is a **new root cause**: it routes back to the operator and does **not** acquire a baseline row. #585's binding constraint is never re-baseline blind — a survivor recorded without a root cause is the vacuous-green class #567 exists to delete. |

## Out of scope

- The pool-disagreement class (closed by #558).
- Any enumerator change that stops prose being read as code (#579/#583, per D-5).
- `doctor.sh --report` bundle behavior (S-7) and `orchestrate-lean.sh` runtime behavior (S-8) —
  both unchanged by construction; a diff touching either means a remedy overreached.
