# lean review verdict — #656

verdict=needs-work
run_id: review-656-2
session_id: 0ffd7fdf-fe71-470c-9444-205654a9a761
rounds: 2
pr: #681
reviewed_head: 375aa0b7e98a758f65cbdcf37c2b90847b3de73f
reviewed_patch_id: e759b3e53257da5db37674405cb525dc92cceae0
inherited_patch_id: c244e28d6086655a9e8f9d79beaaa30f1bc9e733
inherited_from_verdict: af3f8e19f244c195a2a5702a13969ac4d5cb00bf
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 2, delta range `af3f8e19..HEAD`, inheriting patch `c244e28d6086` (round 1). Three files:
`CLAUDE.md`, `docs/testing.md`, `docs/plans/second-shift-656-lean.md`. Round 1's findings were
read first.

**Round 1's B-1 is fixed.** The `(the -t form does honor it)` parenthetical is gone, the
replacement is correct about `-t`, and the runbook now carries a runnable `-u` derivation with a
`-p` control and names the vacuous `TMPDIR=/tmp/x` form so it is not repeated. D-6 was corrected
rather than quietly left standing, and D-9 records the reversal. That is the right shape.

**Verdict: needs-work.** The fix over-generalized. Round 1's claim was narrow and true; round 2
replaced it with a blanket claim that is false for the most common `mktemp` form in this repo —
including the sweep runner's own state dir.

## Blockers

**B-1 — "no `mktemp` form puts that litter where `TMPDIR` points" is false. The largest single
piece of killed-sweep litter is the one form that DOES honor `TMPDIR`.**

Three bolded sentences assert it:

| Site | Claim |
| --- | --- |
| `CLAUDE.md`, killed-sweep note | "on macOS **no `mktemp` form puts that litter where `TMPDIR` points**" |
| `docs/testing.md` | "**`TMPDIR` cannot contain what that leaves behind — in any `mktemp` form.**" |
| `docs/testing.md` | "pointing `TMPDIR` somewhere private before a run moves none of it" |

The counterexample is `tools/run-selftests.sh:394-395` — the sweep runner's own base directory,
which holds every suite's scratch:

```
BASE="$(mktemp -d "${TMPDIR:-/tmp}/run-selftests.XXXXXX")" || die "mktemp failed"
trap 'rm -rf "$BASE"' EXIT
```

That is an **explicit template**, not `-t` and not the no-template form. The shell interpolates
`$TMPDIR` before `mktemp` ever runs, so the path is honored unconditionally — and line 395 is
exactly the `trap … EXIT` a killed sweep skips. Measured 2026-08-25, same machine and derivation
style as the runbook's own block:

```sh
PRIV="$(mktemp -d /private/tmp/probe656b-XXXXXX)"
TMPDIR="$PRIV" bash -c 'mktemp -u -d "${TMPDIR:-/tmp}/run-selftests.XXXXXX"'
  -> /private/tmp/probe656b-RxjOCd/run-selftests.fFDayv     # TMPDIR honored
env -u TMPDIR bash -c 'mktemp -u -d "${TMPDIR:-/tmp}/run-selftests.XXXXXX"'
  -> /tmp/run-selftests.ZbdKw9                              # falls back to /tmp
TMPDIR="$PRIV" /usr/bin/mktemp -u -d -t leangate
  -> /var/folders/…/T/leangate.jvDkRSQkke                   # the form the runbook DOES test
```

`grep -rln 'mktemp[^|]*"${TMPDIR:-/tmp}'` finds **14** guard scripts using this form
(`check-sweep-bound.sh`, `check-gate-buckets.sh`, `check-fail-open-shapes.sh`,
`exitplan-ledger-gate.sh`, `orchestrate-lean.sh`, several `*-selftest.sh`, …). It is the repo's
dominant form, not an edge case.

The runbook's own derivation block contains the tell: its `-p "$PRIV"` control line is annotated
*"a NAMED dir is honored"*. An explicit template is that same category. The block tests
`-u -d`, `-u -d -t stamp` and `-u -t stamp` — three spellings of one behavior — and the prose
generalizes from them to "any form" without testing the fourth, which behaves oppositely.

Why this blocks rather than nits: the operational advice inverts. A reader is told a private
`TMPDIR` buys nothing, so nobody sets one; in fact it relocates the runner's `BASE` and 14 guards'
scratch, which is most of the volume. The narrower claim round 1 approved — a no-template
`mktemp -d` ignores `TMPDIR` — was true. This is a regression introduced by the fix.

Remedy: scope the claim to the forms measured. The honest statement is that the `-t` and
no-template families are not containable by `TMPDIR` (which is what the stamped fixture families
use, and is the whole point), while explicit-template callers do follow it.

**B-2 — "an unset `TMPDIR` and the directory `-t` resolves to are the same path here" is false;
the word is *default*, not *unset*.**

`docs/testing.md` explains the reaper's reach with:

> **That pass reaches them because an unset `TMPDIR` and the directory `-t` resolves to are the
> same path here — not because it was aimed there.**

`run-selftests.sh:241` invokes it as `--dir "${TMPDIR:-/tmp}"`. Measured:

```sh
env -u TMPDIR bash -c 'echo "${TMPDIR:-/tmp}"'   -> /tmp                  # where the reaper looks
env -u TMPDIR /usr/bin/mktemp -u -d -t leangate  -> /var/folders/…/T/…    # where fixtures land
bash -c 'echo "${TMPDIR:-/tmp}"'                 -> /var/folders/…/T/     # inherited TMPDIR
```

With `TMPDIR` genuinely unset the two paths **diverge** and the pass reaches nothing. The
coincidence the sentence relies on holds because macOS launchd exports `TMPDIR` at its default,
which equals the confstr directory — i.e. because `TMPDIR` is *set*, to a value nobody changed.

This is refuted by a command printed fifteen lines below it in the same section: the enumeration
deliberately runs `env -u TMPDIR mktemp -u -d | xargs dirname` and gets `/var/folders/…/T`, not
`/tmp`. The document already knows unset ≠ `/tmp` for `-t`; only this sentence does not.

The sentence carries neither a derivation nor a date, which AC-4 requires of a measurement.

**B-3 — the cross-reference the PR claims to land now resolves to a refutation.**

The PR body lists as a deliverable: *"`tools/reap-lean-fixtures.sh`'s header has been citing
'CLAUDE.md's killed-sweep note' … That cross-reference now lands."* It lands on text that denies
the clause citing it. `tools/reap-lean-fixtures.sh:6-8`:

> a templated `mktemp -d -t <name>.XXXXXX` work dir **under TMPDIR (or /tmp)** … BSD `mktemp -t`
> **DOES honor TMPDIR** (unlike its no-template form — see CLAUDE.md's killed-sweep note), so the
> template is not the problem.

The note now says no such `-t`/no-template distinction exists. Both halves are false by this PR's
own measurement, and this is the header of the live guard the runbook routes readers to as the
automated remedy — it misdescribes where the script looks versus where the fixtures are.

Round 1 scored this W-1, non-blocking, on the reasoning that the PR "is answerable for what it
writes into `CLAUDE.md`, not for a script comment it did not touch". That reasoning held while the
two surfaces agreed. The PR has since inverted the cited authority, so the contradiction is now
this PR's.

Cost of the remedy: zero. `check-guard-budget.sh`'s predicate is `*-selftest.sh`, `check-*.sh`,
`*-lint.sh`, `*/skills/*/lean-gate.sh`, plus `run-selftests.sh`/`mutation-sweep.sh`/
`gate-ablation.sh`. `reap-lean-fixtures.sh` matches none, so a header edit cannot move guard mass
and AC-3 stays green.

## Per-AC scoring

| AC | verdict | basis |
| --- | --- | --- |
| AC-1 | satisfied | All three required elements sit directly under the recipe fence: the 2-minute foreground reap and that `timeout` does not lift it; the surviving `nohup … > log` shape under `run_in_background` and that it is collected in the same turn; the scrub obligation. Verified first-hand this round — the documented shape carried the full sweep detached, and a foreground variant was SIGKILLed at exactly 2m 0s. The obligation is correctly stated; its supporting mechanism sentence is B-1, charged to AC-4. |
| AC-2 | **unsatisfied** | The AC's first required element is *why `TMPDIR` cannot isolate the litter*, and the answer given is a blanket claim measurement refutes for 14 guards including the runner's own `BASE` (B-1). Its "what the reaper already clears" element carries B-2's false mechanism. The remaining elements hold: the enumeration is read-only and was run verbatim here, returning `/var/folders/…/T/gitkraken/gitlens/agents` — a vendor directory with no `plugin.json` beside it, exactly the harmless case the prose names; the `stat`-before-delete check and the permission-denied note are present. |
| AC-3 | satisfied | `check-guard-budget.sh origin/main`: base 51793, HEAD 51793, delta 0. Markdown-only diff; no new gate, no new script. No `Guard-mass:` trailer owed. |
| AC-4 | **unsatisfied** | B-1 and B-2. The `-u` derivation block is runnable and reproduced exactly here, but the conclusion drawn from it exceeds the forms it tests; B-2's claim carries neither derivation nor date and is false. The second half of AC-4 IS met: no sentence asserts a currently-fixed defect as live, and the emit-deadline live-scan case is correctly described by mechanism without being named as still redding. |
| AC-5 | satisfied | `Changelog: none` on all three commits. `check-changelog-trailer.sh origin/main`: no `plugins/**` change, trailer not required. |
| AC-6 | satisfied | CI `lint-and-selftests` green at `375aa0b7`: `summary: 75 scored, 74 run, 1 served from cache, 0 failed`. `selftests (macos, bash 3.2)` also passes at that head. A local cold sweep was started via the documented shape and aborted once CI answered; AC-6 rests on CI, as it did at round 1. |

## Also verified (no findings)

- `check-lockstep-pairs.sh`: 29 anchors, 0 failed. The split-by-role decision (D-1) owes no anchor —
  the two sites genuinely do not restate each other.
- `check-frozen-files.sh origin/main`: clean, no release-owned files touched.
- The `mktemp(1)` mechanism the prose cites is accurate as far as it goes: DESCRIPTION confirms
  `-t` resolves against `_CS_DARWIN_USER_TEMP_DIR` with `TMPDIR` only as a fallback, and that
  "if only the `-d` flag is passed mktemp behaves as if `-t tmp` was supplied".
- The "no such note existed" premise checks out: `git show main:CLAUDE.md` has zero `killed-sweep`
  matches, so the dangling-reference diagnosis was correct.

## Deviation to record

The reviewer panel was not fanned out this round, as in round 1: this session runs under a standing
operator instruction not to dispatch subagents or workflows unasked, which is in tension with
review-lean step 5 naming `review-lead` as the implementation. The review is first-hand — the delta
was read in full and every factual claim in it was executed rather than accepted. The verdict does
not turn on the omission: all three blockers were found by measurement, which is the mode that has
carried both rounds of this ticket.

CI at review time (`375aa0b7`): `lint-and-selftests` pass, `mutation-sweep-pr` pass,
`selftests (macos, bash 3.2)` pass, `pr-gates` fail. The `pr-gates` red is the lean-chain
reconciliation arm naming the absent round-2 verdict record — this record — and no other gate.
