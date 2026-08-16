# Intent-gap record — second-shift#549

region: D-2
ratified: no

## The decision the receipt did not cover

`.claude/pipeline-state/549-ledger.md` D-2 resolved the transport mechanism as **not
pre-committed**: "AC-1 probes the candidates against D-3's criteria list and the winner is
whichever survives all of them", followed by an enumeration of three candidates —
`claude --bg` + `claude agents --json`, a `script(1)` pty wrapper, and `--tmux` / iTerm2 native
panes.

**All three fail D-3's criteria.** The measured per-candidate, per-criterion table is AC-1 of
`docs/plans/second-shift-549-lean.md`; in summary, `--bg` fails (iii) and (iv), `script(1)` fails
(i), (ii), (iv) and (vi), and `--tmux` fails (i) and (vi) before anything else is reached.

**A fourth candidate, which the receipt does not enumerate, survives all six**: the streaming
transport — `claude -p --input-format stream-json --output-format stream-json --verbose`, with
the prompt delivered as one compact JSON user message on stdin.

The gap is narrow and specific: **may the probe adopt a candidate the receipt did not
enumerate?** D-2's decision *rule* is criteria-based and would admit it. D-2's *list*, and OR-1's
wording ("no candidate survives … a genuine disqualifier for the only native candidate"), both
read as though the enumeration were the universe — which is what makes this the build run's own
call rather than the receipt's.

## What was decided, and why it was not deferred

The streaming transport was adopted as the winner and built. Deferring instead would have meant
firing OR-1 — "no candidate survives" — while holding measured evidence that one does, i.e.
landing nothing and reporting the opposite of what was measured. That is the shape #531 was filed
for, and OR-1's own reasoning ("landing nothing while reporting success") argues against it here
rather than for it.

The choice is cheap to reverse: it is one capability check in `spawn()`, and the `-p` fallback it
would revert to is code that ships and stays exercised (OR-3, and AC-9 cases 2 and 3).

## Two smaller departures, recorded here rather than separately

1. **The capability check does not test for a TTY.** D-1 names the fallback triggers as "no TTY,
   CI, or a binary lacking the flag". The first two were written for a presumed TTY-dependent
   winner; the streaming transport needs no TTY (criterion vi, measured), so a TTY test would
   select the fallback for a condition that does not affect it. The check tests what the winner
   actually needs: the binary advertising `--input-format`, and `jq` resolving.
2. **Two doc surfaces outside D-5's naming.** D-5 names `build-lean/SKILL.md` for the two-branch
   in-flight rule. `review-lean/SKILL.md` and `lean-gate.sh`'s milestone-3 rationale each assert
   the retired premise as fact, and D-8 moves all three spawn sites, so leaving them would leave
   two live surfaces stating something false. Both are narrowed to the fallback (AC-7, AC-8); no
   mechanism changes, per D-9.

## What ratification decides

Ratifying accepts the widened candidate set — that a probe bounded by D-3's criteria may consider
a candidate D-2 did not list — together with the two departures above. Declining it reverts
`spawn()` to `-p` unconditionally and fires OR-1 with AC-1's table as the artifact.

ratified_by:
