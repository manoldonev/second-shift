# second-shift #780 — delete the fixture reaper; delete the condition it existed for

`tools/reap-lean-fixtures.sh` walks `${TMPDIR}` on every sweep entry and deletes leftover
`leangate.*` / `orchestrate-lean-selftest.*` fixture directories, guarding each delete with a
pid-plus-`lstart` ownership check so it never removes a live suite's working tree. A milestone-3
lane discovers 78 suites, defers 14, and runs 64 — and the two suites that produce those
directories are both in the deferred set. So the reaper runs, every lane, over a directory that
lane can never populate.

Re-scoped at intake (`.claude/pipeline-state/780-ledger.md`, binding): the original premise
("nothing routine exercises the reaper") is false for its ownership decision —
`tools/reap-lean-fixtures-selftest.sh` case D10 already drives the real `kill -0` / `ps -o
lstart=` path against a fixture owned by the running suite, on every sweep. What has no
recurring exercise is narrower — two reapers racing one directory, and concurrent `cache_put` —
and belongs to the operator-run Concurrent-lane tier, which already owns it. So the finding
indicts the mechanism, not the test coverage: all of the reaper's caution exists for cross-lane
safety, and a lane never reaches it.

The reason lanes share one fixture directory at all is that both producers allocate with
`mktemp -d -t`, the one form that ignores `TMPDIR` on macOS (`docs/testing.md`, "When a run is
killed mid-sweep"). Switching them to the explicit-template form deletes that condition outright:
a lane run under a private `TMPDIR` then isolates its own fixtures, and there is nothing left to
reap.

This is a `harness-internal` ticket (#717); ratified by operator comment on the issue, net diff
negative.

## Acceptance criteria

- AC-1: `tools/reap-lean-fixtures.sh`, `tools/fixture-stamp.sh` and
  `tools/reap-lean-fixtures-selftest.sh` are deleted, and no tracked file outside `docs/plans/`
  still names them. Verify with `git grep -lE 'reap-lean-fixtures|fixture[-_]stamp' -- .
  ':!docs/plans/'`, which must return nothing.
- AC-2: `tools/run-selftests.sh` no longer reaps on entry — the
  `[[ -x "$ROOT/tools/reap-lean-fixtures.sh" ]]` block and its header comment are gone — and the
  case in `tools/run-selftests-selftest.sh` that stages a fake reaper under a fixture root is
  deleted with it.
- AC-3: `plugins/dev-pipeline/skills/build-lean/lean-gate-selftest.sh` and
  `plugins/dev-pipeline/skills/run-lean/orchestrate-lean-selftest.sh` no longer stamp ownership,
  and each allocates its work dir with the explicit-template form
  `mktemp -d "${TMPDIR:-/tmp}/<name>.XXXXXX"`. Both retain the trap-installed-before-`WORK`-exists
  ordering (D-11), and `orchestrate-lean-selftest.sh` retains its `pwd -P` handling (D-15) — on
  macOS `${TMPDIR}` is a `/var/folders/...` path behind a `/var` symlink, so that resolution
  matters more under the new form, not less.
- AC-4: the rows that break on the deletion are removed — the `tools/fixture-stamp.sh` input row
  for `lean-gate-selftest.sh` in `tools/selftest-cache-inputs.tsv` (the runner exits rc=2 on a
  declared input that does not exist), and the `tools/fixture-stamp.sh` row in
  `tools/mutation-pair-map.tsv`. The stale comment cross-reference in
  `tools/check-sweep-bound-selftest.sh` is reworded. A full sweep exits 0.
- AC-5: `tools/selftest-suite-timings.tsv`'s header records that the deferral rule selects purely
  on duration and cannot see whether a suite is the sole producer of a shared-resource class,
  naming the surviving instance: two of the three suites carrying
  `tools/selftest-cache-inputs.tsv` rows are deferred, so a milestone-3 lane has exactly one
  cacheable suite. Prose only — no new column, no validator.
- AC-6: the net diff is negative. This is a `harness-internal` ticket and that is the ratification
  bar.
- AC-7: docs follow the deletion. `docs/testing.md`'s "When a run is killed mid-sweep" section
  drops the reaper paragraph and gains the manual scrub command; its `-t` versus
  explicit-template derivation is retired along with the parallel killed-sweep paragraph in
  `CLAUDE.md`, whose claim that a private `TMPDIR` relocates the scratch and not the fixtures is
  false once AC-3 lands. The Concurrent-lane tier drops criterion C-1, the fixture-row half of its
  step-4 sampler, and the stagger rule that exists only to make C-1 falsifiable — C-2, C-3 and C-4
  keep live subjects and stay — and notes that the recorded run describes a pre-deletion tree. No
  `docs/plans/` record is edited.

## Out of scope

No new guard, no new selftest case, no new script. The deferral rule itself is unchanged — AC-5
touches only its header prose. The Concurrent-lane tier is not re-run: it is operator-run by
design, C-1 is being deleted, and C-2/C-3/C-4 measure surfaces this change does not touch. No
`docs/plans/` record is edited, including the six that name the reaper; all are stamped records of
merged runs, and `second-shift-564-evidence.md` declares itself void when these files change, so
its staleness clause fires without an edit.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Close the un-exercised cross-lane surfaces with a new guard, or leave them to the operator-run tier | No new guard and no new selftest case. The reaper's ownership decision is already exercised every sweep (finding 1 above); the residue is two-reapers-racing and concurrent `cache_put`, which the Concurrent-lane tier owns | user-answered |
| D-2 | `tools/selftest-suite-timings.tsv` selects deferrals purely on duration, blind to whether a suite is the sole producer of a shared-resource class | Record the blind spot in that file's own header prose, in this ticket. No column, no validator: the rule has one surviving instance, and machinery for a population of one is the trap. Aim it at the cache instance — two of the three suites with `tools/selftest-cache-inputs.tsv` rows are deferred, so a milestone-3 lane has exactly one cacheable suite. The fixture instance dissolves with D-4 | user-answered |
| D-3 | Is #780 ratifiable as a docs-only addition | No. Finding 2 above; the issue is currently unlabeled, so nothing has enforced this yet | codebase-derived |
| D-4 | The reshape that makes it ratifiable | Narrow to a deletion. Retire `tools/reap-lean-fixtures.sh` (201 lines), `tools/fixture-stamp.sh` (64), `tools/reap-lean-fixtures-selftest.sh` (306), the 18-line entry call site in `tools/run-selftests.sh`, the fake-reaper case in `tools/run-selftests-selftest.sh`, both producers' stamping preambles, and the dependent TSV rows | user-answered |
| D-5 | What replaces the reaper at sweep entry | Nothing automated. One scrub command added to the existing "When a run is killed mid-sweep" section of `docs/testing.md`. CI runners get a fresh TMPDIR per job so orphans cannot accumulate there, and the measured 107-plus-73 pile was one developer machine between macOS `/var/folders` clears | user-answered |
| D-6 | The two producers' `mktemp` form once stamping goes | Switch both to the explicit-template form, `mktemp -d "${TMPDIR:-/tmp}/<name>.XXXXXX"`, which a private TMPDIR honors. This deletes the reaper's motivating condition rather than only the reaper: a lane run under a private TMPDIR then isolates its own fixtures. Repo-majority idiom already — 12 scripts at 16 sites, including `run-selftests.sh`'s own `BASE` | user-answered |
| D-7 | `docs/testing.md`'s Concurrent-lane tier, whose C-1 is scored off reaper output and whose step-4 sampler parses a stamped name | Drop criterion C-1, the fixture-row half of the step-4 sampler, and the stagger rule that exists only to make C-1 falsifiable. C-2, C-3 and C-4 keep live subjects and stay | user-answered |
| D-8 | `docs/plans/second-shift-564-evidence.md`, which scores C-1 VACUOUS and points at #780 | Untouched. It is a stamped pre-registered measurement whose own discipline forbids post-hoc rewriting, and its staleness clause fires by its own terms — it declares itself void when `reap-lean-fixtures.sh` or `fixture-stamp.sh` changes | user-answered |
| D-9 | Whether #780 owes a fresh Concurrent-lane measurement, since this change voids the record | No. Record the void in `docs/testing.md` and let the next operator run re-take it. The tier is explicitly operator-run and never CI; C-1 is deleted, and C-2, C-3 and C-4 measure surfaces this change does not touch | user-answered |
| D-10 | Whether `CLAUDE.md` is in scope for the retired `-t` derivation | Yes, edit both homes. `CLAUDE.md`'s killed-sweep paragraph asserts that a private TMPDIR relocates the scratch and not the fixtures; after D-6 that is false, and it sits in the file every session loads | user-answered |
| D-11 | #528's "trap installed before WORK exists" hardening, colocated in the blocks D-6 edits | PRESERVED. It is a property independent of the stamping and must survive both producers' edits; the old order left a signal window that orphaned WORK with no trap registered | codebase-derived |
| D-12 | Dependent table rows that break on the deletion | `tools/selftest-cache-inputs.tsv`'s `lean-gate-selftest.sh` to `tools/fixture-stamp.sh` row MUST go — the runner exits rc=2 on a declared input that does not exist. `tools/mutation-pair-map.tsv` line 35 pairs `fixture-stamp.sh` with the deleted suite and goes as dead. `tools/check-sweep-bound-selftest.sh` line 384 carries a comment cross-reference to the deleted suite and is reworded | codebase-derived |
| D-13 | Mutation accounting after the deletion | Nothing to retire: `reap-lean-fixtures.sh` and `fixture-stamp.sh` carry zero `tools/mutation-catalog.tsv` rows today, and deleting them shrinks the `git ls-files` universe that `mutation-sweep-selftest.sh` case (j) walks, so its accounting stays green. `run-selftests.sh`'s four catalog rows are the live risk and are tracked as OR-1 | codebase-derived |
| D-14 | Scope boundary — what this PR explicitly does not do | Adds no guard, no selftest case and no script. Does not change the deferral rule itself, only its header prose (D-2). Does not re-run the Concurrent-lane tier (D-9). Does not edit any `docs/plans/` record (D-8), including the five besides #564's that name the reaper — all are stamped records of merged runs. Does not touch `run-selftests.sh`'s pass cache | user-answered |
| D-15 | The `pwd -P` handling in `orchestrate-lean-selftest.sh`, adjacent to the block D-6 edits | PRESERVED, and it matters MORE after D-6, not less. On macOS `TMPDIR` is a `/var/folders/...` path and `/var` is a symlink to `/private/var`, so the explicit-template form yields a path whose resolved and unresolved spellings differ — the same mismatch the existing `pwd -P` comment describes. Do not remove it as stamping-era residue | codebase-derived |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Whether deleting the entry block from `tools/run-selftests.sh` re-anchors that guard's four `tools/mutation-catalog.tsv` rows | reversible-default-and-flag |

**OR-1, and why the default is reversible.** Editing a guard's code re-anchors its catalog rows,
and `run-selftests.sh` carries four. Since #583 those keys are content-addressed rather than
position-keyed, so deleting an unrelated block should leave them still resolving — but that is a
prediction, not a measurement, and only running the sweep settles it. **Default: if the rows
re-anchor, re-anchor them in this PR and say so in the PR body.** Reversing it is cheap because a
catalog row is a one-line TSV edit with no consumer beyond the sweep, and a wrong anchor reds the
sweep loudly rather than passing silently.
