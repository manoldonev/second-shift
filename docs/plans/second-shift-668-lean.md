# #668 — milestone 3's terminal line states its advisory count

## Problem

After #642 demoted `lint`, `test` and `extraLanes` to advisory, a red on any of them calls
`lane_advisory` — which appends a durable `| milestone-3 | advisory |` progress row, prints two
warn lines, and returns 0 so the milestone concludes on its own merits. `cmd_3` then ends at
`pass_milestone 3 "green gate"` unconditionally: it never consults whether any advisory row was
written above it.

The warn lines scroll. The terminal line — the one thing an operator or a scheduler reads — asserts
an unqualified green. Observed live on PR 660: a real selftest failure (anchor drift) rode an
advisory lane under an `rc=0` gate whose last line read `✓ milestone-3: green gate`, and only the
operator-side disclosure surfaced it to review.

The compensating controls are real and stay: two warn lines, the durable advisory row, and the
merge boundary re-running the demoted lanes blocking. The defect is scoped to the terminal line
hiding them.

## Fix shape

`cmd_3` counts the advisories written during this invocation and states the count in the terminal
line when it is nonzero — `green gate (2 advisory)`. No change to the verdict, the rc, the progress
rows, or any consumer. One formatted string, plus fixture cases pinning both forms.

## Acceptance Criteria

- **AC-1** (oracle): when one or more advisory rows are written during a milestone-3 run, the
  terminal line names the count — `green gate (<n> advisory)`, singular/plural not distinguished.
  A behavioral fixture case in `lean-gate-selftest.sh` asserts it and reds against the
  unconditional form.
- **AC-2** (critic): rc semantics, verdict routing, progress-row text, and every existing consumer
  are unchanged. A fixture case pins the zero-advisory terminal text as **byte-identical** to
  today's (`✓ milestone-3: green gate`), so the counted form cannot leak onto clean runs.
- **AC-3** (oracle): the selftest sweep is green and the branch carries a `Changelog:` trailer.
  `plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh` has a row in
  `tools/selftest-suite-timings.tsv` (141s), so milestone 3's bounded sweep **defers it** — the
  suite this change edits must be run explicitly and its result recorded here.

## Notes

- The counter is per-invocation and lives in `cmd_3`; `lane_advisory` is called from exactly two
  sites, both inside `cmd_3` (the fixed-key loop and the extraLanes loop), so no other milestone
  can contribute to it.
- A fix round re-runs `bash G 3` in a fresh process, so the count describes that invocation — which
  is the intended reading: it qualifies the green it is printed beside.
