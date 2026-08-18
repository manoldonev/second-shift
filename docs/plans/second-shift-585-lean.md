# #585 — the nightly sweep of record is deterministically red

## Corrected premise (binding — supersedes the ticket body)

`.claude/pipeline-state/585-ledger.md` is the pre-flight receipt and is binding input. Its
correction to the ticket body is load-bearing, so it is restated here as the definition of the
problem this PR solves.

The nightly `mutation-sweep` redness has **three independent causes**, not one. The ticket body
names a single survivor and attributes to it a date range and a shard that belong to a different
cause. A **fourth** cause was found after the fact, by this branch's own dispatched sweep, and
folded in by the operator's OR-2 resolution — see *Scope addition* below:

| Night | SHA | Shard | Actual `RED:` line | Status |
| --- | --- | --- | --- | --- |
| 08-13, 08-15, 08-16 | e6a16ef, dc2db95 ×2 | 1 | `pool disagreement` (`lean-evidence.sh::cmp-z::1`, then `check-fail-open-shapes.sh::default::2`) | **already closed by #558** (`ec42f38`, 08-16 20:52) — needs no work here |
| 08-17, 08-18 | 33e6187, a8cd2b5 | 9 | `orchestrate-lean.sh::fail-open::1` + `orchestrate-lean.sh::detector::1`, baseline-absent | **in scope** (D-3) |
| 08-18 | a8cd2b5 | 10 | `doctor.sh::cmp-z::1`, baseline-absent | **in scope** (D-2) |
| — (never seen by a nightly) | f969c8c, this branch | 2 | `capability-parity-check.sh::logic::2`, baseline-absent | **in scope** — added by the OR-2 resolution (AC-10) |

Every live cause is fixed here, in one PR (D-1, extended by the OR-2 resolution). Fixing only the
survivor the ticket names would leave shard 9 red and the stated goal — a green moat before #579
re-keys baseline rows — unmet, while reading as "the sweep is fixed". The fourth row is the same
argument one step further: it is not this branch's defect, but leaving it red leaves the moat red,
which is the only thing D-4 actually asks for.

`doctor.sh::cmp-z::1` is **one night old** and on **shard 10**, not "since 08-15 on shard 9".

## Scope addition — the fourth cause (OR-2 resolved, 2026-08-18)

AC-8's dispatched sweep on this branch (run `32172818773`, `headSha` `f969c8c`) put **9 of 10
shards green**, including both shards the ticket owns. Shard 2 returned one further
baseline-absent survivor that no nightly has ever reported:
`tools/capability-parity-check.sh::logic::2`.

**It is not this branch's.** Three independent checks settle that, and each is one command:

1. This branch's diff cannot reach the guard. `git diff --name-only a30c29b..HEAD` names three
   files and `tools/capability-parity-check.sh` is not among them.
2. The arming edit is visible at the blob. `git show a8cd2b5:tools/capability-parity-check.sh`
   has `ROOT="$(cd "$HERE/.." && pwd)"` at line 52; `git show a30c29b:` has it **absent**,
   deleted by #577 (`7620251`).
3. No nightly has ever run on an arming SHA. The newest nightly is `a8cd2b5` (08-18 03:57),
   which predates #577 — so the survivor was invisible to every nightly *by construction*, and
   main's next nightly reds on it with or without #585.

**Why it lands here anyway.** D-4 makes #585 a hard merge precondition for #579 *because #579
needs a green moat*. Closing only the two in-scope causes no longer delivers one, so the operator
widened this ticket rather than opening a second lane (issue comment, 2026-08-18 19:56Z). The
remedy is already diagnosed and is the same **shape** as D-2, so it costs one spec amendment.

**The deletion-pulls-a-site-into-budget class.** Removing a matched line *above* a known-unkillable
idiom arms that idiom, and the PR that removes the line is nowhere near the guard that goes red.
#577 deleted the `ROOT=` assignment — a `logic` site above the file's
`while IFS= read -r line || [[ -n "$line" ]]` — which moved the read idiom from `logic` ordinal 3
to ordinal **2**, into the `k=2` budget window where it had never been mutated. This is the mirror
image of the prose-adds-a-site class that causes D-7, and `mutation-sweep.sh` already documents its
twin ("The third was never safe, only out of budget — ordinal 5 against k=2").

**Why the idiom is dark.** The `||`→`&&` flip only changes a verdict for a register whose final
line is unterminated (`read` returns 1, so without the second operand the last row is never
judged) or one containing a blank line. `capability-parity.tsv` has neither, and every fixture in
`capability-parity-check-selftest.sh` is `printf`-written with a trailing `\n`, so mutant and
original agree on all 14 cases. The gap is the fixtures' termination, not a missing case — exactly
D-2's shape, one operator over.

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
- **OR-2 resolution** — strengthen the existing `(c)` case in
  `tools/capability-parity-check-selftest.sh` **in place** so its fixture register's final line
  lacks a trailing newline. Remedied **at the site**, never by a baseline row: "never re-baseline
  blind" stands unchanged, and this acquires no row. `capability-parity-check.sh` itself is not
  edited — its read idiom is correct, and changing it would be the regression rather than the fix.

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
owed either. The same holds for the fourth cause: `tools/capability-parity-check.sh` has **no**
baseline row and **no** `tools/mutation-catalog.tsv` row today, and AC-10 edits only its selftest,
so the guard's own matched-line sequence — and therefore every operator's ordinals over it — is
byte-identical base-to-head. Nothing is re-keyed and nothing is added.

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
Because the AC-10 remedy landed after run `32172818773`, the proof of record is a **re-dispatched**
run on the amended head; the earlier run stands only as the evidence that surfaced the fourth cause.

**AC-9** — The PR body carries the corrected triage table above. #579/#583 key off survivor
identity, so a wrong attribution left in the record is the input that poisons them (D-9).

**AC-10** — `tools/capability-parity-check-selftest.sh`'s existing `(c)` case
(`disposition outside the enum ('deferred') reds`) is strengthened **in place** so the register it
writes ends **without** a trailing newline, putting the row it asserts on last and unterminated.
The case keeps its name, its position, and its assertion (`rc == 1`). No new case is added, no new
fixture helper is introduced, and no other case's fixture is changed.

**AC-11** — `tools/capability-parity-check.sh` is **not modified**. The fix is test-only; the
guard's observable output for every input, and its matched-line sequence for every mutation
operator, are unchanged.

**AC-12** — Applying the `logic` operator's flip to `tools/capability-parity-check.sh` ordinal 2
(`while IFS= read -r line || [[ -n "$line" ]]` → `&&`) makes `capability-parity-check-selftest.sh`
**fail on case (c) specifically**, and the suite passes unmutated. Ordinal 1
(`HERE="$(cd … && pwd)"`) is likewise killed, so the guard's entire `k=2` window is covered. All
three directions are demonstrated, not asserted.

## Open Regions

| ID | Region | Disposition | How it is discharged here |
| --- | --- | --- | --- |
| OR-1 | Durability of the D-3 reword — nothing prevents a future comment from re-introducing a phantom mutation site | reversible-default-and-flag | The reword ships as the stated default (reversing it is a one-line edit with no downstream consumers). The residual risk is **flagged** in the PR body and by a short in-file note at the site, itself worded to match neither ERE. The durable fix is owned by #579/#583. |
| OR-2 | Whether the dispatched sweep surfaces a further baseline-absent survivor beyond the two in scope | **pause-and-ask** | **RESOLVED 2026-08-18 19:56Z** by operator comment on #585. It did: `tools/capability-parity-check.sh::logic::2` on shard 2. It was root-caused before disposition (#577 deleted a `logic` site above the read idiom, pulling it into the `k=2` window) and the operator widened this ticket to fix it **at the site** — AC-10/11/12. It acquires **no** baseline row, so the binding "never re-baseline blind" constraint is honoured rather than waived. S-7 and S-8 stay out of scope. |

## Out of scope

- The pool-disagreement class (closed by #558).
- Any enumerator change that stops prose being read as code (#579/#583, per D-5).
- `doctor.sh --report` bundle behavior (S-7) and `orchestrate-lean.sh` runtime behavior (S-8) —
  both unchanged by construction; a diff touching either means a remedy overreached. S-7 and S-8
  are explicitly reaffirmed as out of scope by the OR-2 resolution.
- `capability-parity-check.sh`'s own runtime behavior (AC-11) — the fourth remedy is test-only,
  for the same reason D-2's is: the read idiom is correct, and editing it would be the regression.
- The `logic` flip's *other* divergence — a register containing a blank line, where the mutant
  stops early. One kill closes the survivor; asserting a second vector is not what "remedied at
  the site" asks for, and `capability-parity.tsv` has no blank lines to protect.
