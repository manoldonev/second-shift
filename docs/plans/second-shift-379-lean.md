# lean-gate milestone 3 runs the config's extra verify lanes

Closes #379.

`lean-gate.sh` `cmd_3` reads the config's `commands.<repo>` table directly (D-17: no
verifyctl, deliberately no inert-diff lane) but only its fixed keys (`lint`, `typecheck`,
`test`, and a dead `build`) plus `lanes[]` (setup-only). `extraLanes` — the schema's slot for
everything config-lint forces out of the fixed keys (build lanes, path-scoped suites, the
design-driven live-render lane) — is never read, so those tiers silently vanish under lean
and milestone 3 passes green without running them. This closes that gap by porting
verifyctl.sh's `extraLanes` reader into `cmd_3`, and closes a second, adjacent one: none of
milestone 3's lane children (fixed keys, `lanes[]`, now `extraLanes`) run with the pipeline's
seam vars stripped, so a configured lane that is itself second-shift tooling inherits the
gate's own `SECOND_SHIFT_CONFIG`/`STATECTL_STATE_DIR`/etc.

No design/ticket awareness enters the gate. The live-render use case is armed entirely from
consumer config (`docs/live-render.md` gains the extraLane recipe); the gate just runs
whatever `extraLanes` says.

## Design

- **Entry shape**: `{name, when?, commands[], failureClass}` — `commands` is an array,
  `minItems: 1`. The `lanes[]` reader's `(.command // .)` idiom is NOT reused: it reads a key
  extraLanes entries don't have, which would silently no-op every lane. `commands[]` run
  sequentially, stopping at the first non-zero; the failure line names the lane and the
  failing command.
- **Placement**: `extraLanes` run sequentially after the fixed keys and before the
  diff-scoped mutation sweep, in declaration order, fail-fast — same placement verifyctl.sh
  gives them.
- **`when` matcher**: bash pattern matching, `[[ "$path" == $glob ]]` — verifyctl.sh's pinned
  dialect, not globstar and not git pathspec: `*` crosses `/`, so `src/**/*.tsx` needs an
  interior slash and does not match `src/App.tsx`; a bare directory literal never matches a
  file beneath it. Empty/absent `when` = always run. A non-matching lane is a printed skip
  plus a progress-file line
  (`<iso> | milestone-3 | skipped | extra lane '<name>' — no changed path matches when[]`),
  never silent.
- **Diff base, fail-closed**: the `when` diff is
  `git diff --name-only <merge-base(origin/<baseBranch>, HEAD)>..HEAD`. An unresolvable
  `origin/<baseBranch>` reds milestone 3 when any `when`-scoped lane exists — following
  milestone 4's fail-closed precedent (`branch_patch_id` is the fail-open one; that asymmetry
  is intentional and stays). An empty diff from a resolvable base is a real inert diff and
  simply matches nothing.
- **Malformed entries, fail-closed**: nothing in the lean lane ever runs config-lint, so
  `cmd_3` cannot delegate shape validation. A non-object entry, or one missing `name` or a
  non-empty `commands`, reds milestone 3 naming the entry index — mirroring the guard
  verifyctl.sh grew for the same hole (#100).
- **Seam-var scrubbing**: every milestone-3 lane child (fixed keys, `lanes[]`, `extraLanes`)
  runs with the pipeline's seam vars stripped via `env -u` — a verbatim copy of verifyctl.sh's
  `SEAM_SCRUB` denylist (`scripts/lockstep-manifest.tsv` pins it), since lean-gate needs
  nothing narrower or wider. `eval "$cmd"` becomes `env <scrub> bash -c "$cmd"`: functionally
  identical for a shell command string, and the only shape `env` can scrub ahead of.
- **`build` leaves the fixed-key list** — unreachable by any schema-valid config
  (`commands.<repo>` is `additionalProperties: false` with no `build`; config-lint.sh rejects
  it by name) and ratified dead by #113.
- **`failureClass` is message-only**: lean has no failure-taxonomy or attempt-budget
  machinery and borrows none — the milestone's own 3-fix-attempt budget applies regardless of
  the declared class. Not validated by `cmd_3`'s shape guard (only `name`/`commands` are).
- **Schema descriptions re-scoped**: the `when` and `failureClass` description strings
  currently read as stage-lane semantics (`"An inert diff skips extra lanes too"`,
  `"gets the standard 2-attempt budget"`) — both become lane-neutral (blocking; the
  skip/budget behavior is the consuming lane's own).
- **Docs**: `docs/config-schema.md:9,:20` name verifyctl/preflight as the only lane spawners
  — both gain lean-gate.sh. `docs/live-render.md` gains the extraLane recipe as the lean-lane
  path (no Stage-5 gate under lean).

## Acceptance criteria

- AC-1: an extraLane whose `when` matches the milestone-3 diff runs; a non-zero rc reds
  milestone 3 naming the lane and the failing command.
- AC-2: a multi-command lane runs its `commands[]` sequentially and stops at the first
  non-zero.
- AC-3: a non-matching `when` produces the printed skip and the pinned progress-file line —
  proven against a non-empty diff that simply matches nothing.
- AC-4: an empty or absent `when` always runs; the bash-pattern dialect is pinned by a case
  asserting `src/**/*.tsx` does NOT match `src/App.tsx` (and does match `src/a/App.tsx`).
- AC-5: with no `extraLanes` key: `gate 3` output contains no `extra lane` token, the
  progress file gains no new lines beyond today's, and the existing milestone-3 cases stay
  green unmodified.
- AC-6: ordering and fail-fast are observable: fixed keys → extraLanes (declaration order) →
  mutation sweep.
- AC-7: a malformed entry (non-object, missing `name`, empty/missing `commands`) reds
  milestone 3 naming the entry index.
- AC-8: with a `when`-scoped lane present and `origin/<baseBranch>` unresolvable, milestone 3
  reds (fail-closed) rather than skipping the lane.
- AC-9: milestone-3 lane children (fixed keys, `lanes[]`, extraLanes) run with the seam vars
  stripped, pinned by a selftest case.
- AC-10: the dead `build` key is gone from the fixed-key loop (`"build is null — skipped"`
  no longer appears); any selftest pinning it is updated in the same diff.

## Out of scope

- No `format` key addition, no advisory mode, no failure-taxonomy import, no inert lane.
- No design/ticket awareness in the gate.
- No config-lint invocation from the gate — `cmd_3` grows its own minimal fail-closed shape
  guard (AC-7) instead.
