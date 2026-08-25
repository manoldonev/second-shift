# lean review verdict — #656

verdict=needs-work
run_id: review-656-1
session_id: d7133ae6-8744-42f6-99a2-9a2319b3a7df
rounds: 1
pr: #681
reviewed_head: 56f2908dee3287e5e1b9dc540557735314e77229
reviewed_patch_id: c244e28d6086655a9e8f9d79beaaa30f1bc9e733
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 1, full range `93b857fe..HEAD` (nothing verifiable to inherit). Three files:
`CLAUDE.md`, `docs/testing.md`, `docs/plans/second-shift-656-lean.md`.

**Verdict: needs-work.** One blocker, one warning. The slice is otherwise well-built: the
split-by-role decision is right, the runbook leads with what is already automated rather than
sending a reader to hand-delete from a shared directory, and the dangling
`reap-lean-fixtures.sh` cross-reference now lands.

## Blocker

**B-1 — `CLAUDE.md` asserts that `mktemp -t` honors `TMPDIR`. It does not, on this machine.**

The added killed-sweep note reads: a no-template `mktemp -d` ignores `TMPDIR` *(the `-t` form
does honor it)*. The parenthetical is false. Measured on the lane machine, system
`/usr/bin/mktemp`, with `TMPDIR` set to a directory that exists and is visible to the process:

- no-template form resolves under the `_CS_DARWIN_USER_TEMP_DIR` path, not `TMPDIR` — claim holds
- `-t` form resolves under the same path, NOT `TMPDIR` — claim fails
- `-t` without `-d`: same
- positive control: the `-p <dir>` form DOES resolve under the named directory

The positive control matters — it shows the probe can observe a directory being honored, so the
two negative results are not a harness artifact. The first attempt at this check was vacuous and
is worth naming: it set `TMPDIR` to a path that does not exist, which cannot distinguish "ignores
TMPDIR" from "falls back because the directory is missing". The spec's own D-6 records that same
vacuous form as its verification. D-6's conclusion for the no-template case is nonetheless correct
— it just is not established by the derivation it cites.

Why this is a blocker rather than a nit. `docs/testing.md` states, correctly and in bold, that
`TMPDIR` cannot contain this litter and that pointing it somewhere private before a run moves none
of it. It also states that the two reaped fixture families stamp ownership into a `mktemp -t`
template. Compose those with `CLAUDE.md`'s parenthetical and a reader concludes the `-t` families
ARE contained by `TMPDIR`, so a private `TMPDIR` isolates them — the exact false comfort this
section exists to remove. It lands in the auto-loaded surface, where it is read by every session in
the repo without being asked for.

The measurement also makes the section's own thesis STRONGER, not weaker: nothing here is
contained by `TMPDIR`, and the parenthetical is the one clause undercutting that.

Remedy: drop or correct the parenthetical. One clause; no restructuring.

## Warning (not blocking this round)

**W-1 — the same false claim is pre-existing in `tools/reap-lean-fixtures.sh`'s header**, which
states that BSD `mktemp -t` honors `TMPDIR` "so the template is not the problem", and cites the
CLAUDE.md note this PR creates. The PR faithfully propagated an existing assertion rather than
inventing one, which is why this is a warning and B-1 is the blocker: the PR is answerable for
what it writes into `CLAUDE.md`, not for a script comment it did not touch.

It is worth filing, because something downstream may rest on it: `run-selftests.sh` reaps over
`${TMPDIR:-/tmp}`. If the stamped families do not in fact land under `TMPDIR`, that pass finds
them only while `TMPDIR` holds its default value, and silently reaps nothing when an operator or
a lane overrides it. Not verified either way here — it is out of this branch's range, and it is
a mechanism question, not a prose one.

## Per-AC scoring

| AC | verdict | basis |
| --- | --- | --- |
| AC-1 | satisfied | The rule sits directly under the recipe fence, not behind a link, and names all three required elements: the 2-minute foreground reap and that `timeout` does not lift it; the surviving background shape and that it is collected in the same turn; the scrub obligation for an already-killed attempt. |
| AC-2 | satisfied | The runbook covers why `TMPDIR` cannot isolate the litter, what the reaper clears before a reader touches anything, a read-only enumeration, and a check before deleting. The published command was run verbatim here: it returns a real match, a vendor directory with no plugin marker beside it — the harmless case the prose names. |
| AC-3 | satisfied | `check-guard-budget.sh origin/main`: base 51793, HEAD 51793, delta 0. No new gate, no new script; the diff is markdown only. No `Guard-mass:` trailer owed. |
| AC-4 | **unsatisfied** | B-1. The `-t` clause carries neither a runnable derivation nor a measurement date, and measurement contradicts it. The second half of AC-4 IS met: no sentence asserts a currently-fixed defect as live, and the runbook correctly describes the emit-deadline isolation in the past tense without naming that case as still redding. |
| AC-5 | satisfied | `Changelog: none` present on the branch. |
| AC-6 | satisfied | Verified twice over: `lint-and-selftests` and the macos bash-3.2 lane both pass at this head, and the CI log carries `summary: 75 scored, 75 run, 0 failed`. |

## Deviation to record

The panel was NOT fanned out this round. This session runs under a standing instruction not to
dispatch subagents or workflows unless the operator asks, which is in tension with review-lean's
step 5 naming `review-lead` as the implementation. The review above is first-hand: the diff was
read in full and every factual claim in it was executed rather than accepted. The verdict does not
turn on the omission — a blocker was found by measurement, and a panel finding nothing could not
have overturned it — but the deviation belongs in the record rather than in a transcript, and the
operator may want the round re-run with the panel before this counts toward the campaign row.

CI state at review time: `lint-and-selftests` pass, `mutation-sweep-pr` pass, macos bash-3.2 pass,
`pr-gates` fail. The `pr-gates` red was read from its job log and is solely the absent verdict
record this review writes — no other gate is implicated.
