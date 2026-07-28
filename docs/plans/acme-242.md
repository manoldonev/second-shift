# Plan — #242: statectl `--repo` CLI-surface drift + `pr-add` cross-keying idempotency

## Context / problem framing

Two defects, one file, both surfaced by the same incident (run `2026-07-28T143305Z`, a
single-target `[FE]` pair run that recorded a branch-keyed `.prs` entry stamped `repo: "be"`).

**Defect A — CLI-surface drift.** `--repo` is the be-fe-pair keying flag on statectl's
per-repo boundary writes. The stage files document it correctly
(`plugins/dev-pipeline/skills/run/stages/9-open-pr.md:100`, `:109`) and so does
`plugins/dev-pipeline/skills/run/state-schema.md:307` (`[--repo <id>]`), but statectl's own
usage text omits it on four commands. A caller reading the CLI surface rather than the
stage file sees a three-arg form that is wrong on a pair topology.

The issue as filed named `pr-add` at two sites. Its own premise was then retracted by the
filer (the stage file *does* document the flag; the root cause was executor error, now
tracked as #243). What survives is the CLI-surface alignment — and grounding against
`origin/main` shows the omission is a **class**, not two lines.

**Defect B — `pr-add` is not idempotent across keyings.** `cmd_pr_add` writes through two
disjoint `jq` branches: repo-keyed under `--repo`, branch-keyed otherwise. Re-running with
the *correct* `--repo` after a mis-keyed write therefore **adds** a second entry rather than
replacing the first — one PR, two records. Every consumer iterates `.prs | values[]?` and
reads `.url` (the Stage-9 cost block; `pipeline-retro`), so the duplicate double-counts.
With no `pr-remove` subcommand, the only route back was a raw `jq del` on the state file —
the one thing the "every load-bearing state write goes through statectl" rule forbids.

Defect B was added to the issue mid-run and is the reason this run is not docs-only.

## Assumptions

1. Scope comes from the issue's **comments**, not its body. The body's `## Problem` and
   `## Proposed fix` are historical: the retracted premise and the rung-1 fail-closed
   precondition are out of scope (the latter is subsumed by #243).
2. Of the three repair options in the newest comment, option 1 (self-healing `--repo`) and
   option 3 (schema invariant) are taken; option 2 (`pr-remove`) is not — option 1 makes the
   correct call *be* the repair path, so a removal subcommand would be a second way to do
   one thing.
3. The asymmetry is deliberate: the repo-keyed write heals, the branch-keyed write does
   **not**. Repo-keying is the correct form on a pair topology, so healing in that direction
   repairs a mistake; healing in the reverse direction would let an incorrect call silently
   clobber a correct record.
4. A URL identifies a PR. Two `.prs` entries carrying the same `url` are always a duplicate,
   never two legitimate records — a PR lives in exactly one repo.

## Decision Ledger

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Fix only the two sites the issue names, or the whole `--repo` drift class? | Whole class — 4 commands. The issue's rationale ("a caller reading the CLI surface sees the pair-aware form") is command-agnostic, and it holds `worktree-set` up as the discoverable counterexample while that command's own CLI surface carries the identical trap. | `codebase-derived` |
| D-2 | Which repair mechanism for defect B? | Option 1 (self-healing `pr-add --repo`) + option 3 (schema invariant). Not option 2 (`pr-remove`). | `ticket-sourced` — https://github.com/manoldonev/second-shift/issues/242#issuecomment-5107831395 |
| D-3 | Should the branch-keyed path heal symmetrically? | No. Asymmetric by design (assumption 3) — a wrong call must not clobber a right record. Pinned by a dedicated selftest case. | `codebase-derived` |
| D-4 | How is the doc contract kept from re-drifting, given a lockstep row cannot express it? | A `statectl-selftest.sh` case derived from the script itself: any command whose parser accepts `--repo` **and** carries a usage line must name `--repo` in it. Plus a DROPPED manifest entry for the `statectl.sh` ↔ `SKILL.md` leg. | `codebase-derived` |
| D-5 | Cover commands that have no usage line at all? | No. `cmd_build_checkpoint_7_perrepo` accepts `--repo` and has no usage comment; its requiredness is stated in its error message. "Has no usage text" is a different, lesser gap than "has usage text that drifted". Guard covers drift only; recorded in Out-of-scope. | `codebase-derived` |
| D-6 | Sweep the unrelated `--force` documentation inconsistency? | No. Several commands omit `[--force]` from their usage lines; cosmetic, unrelated to be-fe-pair keying, and would bloat the diff. | `codebase-derived` |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/statectl.sh` — header `Usage:` block; four command usage
  comments; the `cmd_pr_add` repo-keyed `jq` branch.
- `plugins/dev-pipeline/skills/run/SKILL.md` — CLI-surface listing + one requiredness note.
- `plugins/dev-pipeline/skills/run/state-schema.md` — the one-PR-one-entry invariant under `.prs`.
- `plugins/dev-pipeline/skills/run/statectl-selftest.sh` — three `[NEW]` cases.
- `scripts/lockstep-manifest.tsv` — one `[NEW]` DROPPED entry.

## Reuse inventory

- `atomic_write` (`statectl.sh`) — reused unchanged by the amended `cmd_pr_add`.
- `require_mutable` (`statectl.sh`) — reused unchanged; the terminal-state guard is untouched.
- `sct` / `sct_err` / `sct_rc` / `pass` / `fail` / `reset_state` (`statectl-selftest.sh`) — the
  existing case harness; the new cases use it as-is.
- `scripts/lockstep-manifest.tsv` DROPPED-entry prose convention — followed, not re-invented.
- No new helper functions are introduced in `statectl.sh`. The selftest adds one local
  extractor, `usage_repo_drift` `[NEW]`, scoped to that suite.

## Implementation steps

1. **`statectl.sh` header block** — add `[--repo <id>]` to the four drifting lines:
   `worktree-set` (`:36`, also gains `[--base <ref>]`), `pr-add` (`:37`), `verify-attempts`,
   `verify-summary-set`. Placed before the existing `[--force]`.
2. **`statectl.sh` per-command usage comments** — same four commands
   (`cmd_worktree_set`, `cmd_pr_add`, `cmd_verify_attempts`, `cmd_verify_summary_set`):
   append `[--repo <id>]` and one line stating it is **required** under
   `topology.type: be-fe-pair`, pointing at the existing contract rather than restating it.
3. **`cmd_pr_add` self-heal** — in the repo-keyed `jq` branch only, drop any pre-existing
   entry carrying the same `url` under a different key before writing `.prs[$r]`:
   `.prs |= with_entries(select(.key == $r or (.value.url // "") != $u))`.
   The branch-keyed branch is left byte-identical.
4. **`SKILL.md`** — add `[--repo <id>]` to `worktree-set`, `pr-add`, `verify-summary-set` in
   the CLI-surface listing, plus one sentence under the block covering all of them
   (`verify-attempts` is not in this listing and needs no line here).
5. **`state-schema.md`** — under `.prs`, record the invariant: one PR ⇒ exactly one entry,
   whichever keying applies, and note that a repo-keyed write repairs a mis-keyed one.
6. **`statectl-selftest.sh`** — three `[NEW]` cases (see Test strategy).
7. **`scripts/lockstep-manifest.tsv`** — `[NEW]` DROPPED entry recording why the
   `statectl.sh` ↔ `SKILL.md` leg stays reviewer-guarded.

## Test strategy

Verify-after (infra/docs + one narrow behavior change). No mutation-gate work: config
`commands.second-shift.unitTestScope` is `null`, so this repo declares no mutation surface.

Three `[NEW]` cases in `statectl-selftest.sh`:

- **`(pa6)` cross-keying self-heal.** Seed a branch-keyed entry, then `pr-add --repo fe`
  with the *same* url. Assert `.prs | length == 1`, the surviving key is `fe`, and its
  `repo` is `fe`. Red before step 3, green after.
- **`(pa7)` asymmetry.** Seed a repo-keyed entry, then `pr-add` **without** `--repo` at the
  same url. Assert both entries survive (`length == 2`) — the branch-keyed path must not
  delete a correct repo-keyed record. Pins D-3 so a later "make it symmetric" edit fails.
- **`(pa8)` usage-drift guard.** Parse `statectl.sh`: for every `cmd_*` whose parser has a
  `--repo)` arm **and** which carries a usage line, assert that line names `--repo`.
  Mechanical, derived from the script — not a prose grep. Red before steps 1–2, green after.

`(pa6)` also covers a distinct-url case implicitly: the `with_entries` predicate keys on url
equality, so unrelated entries are untouched — asserted inside `(pa6)` rather than as a
fourth case.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Header `Usage:` block names `--repo` | 1 | `(pa8)` |
| AC-2 | Each command's own usage comment names `--repo` + requiredness | 2 | `(pa8)` |
| AC-3 | `SKILL.md` listing names `--repo` + requiredness note | 4 | — no test (non-functional) |
| AC-4 | A `--repo`-accepting command omitting `--repo` from its usage text fails a test | 6 | `(pa8)` |
| AC-5 | (negative) parser surface unchanged — no new flags, preconditions, or key choice | 3 | `(pa7)` |
| AC-6 | `pr-add --repo` drops a same-url entry under a different key | 3 | `(pa6)` |
| AC-7 | `state-schema.md` records one PR ⇒ exactly one `.prs` entry | 5 | — no test (non-functional) |
| AC-8 | Asymmetry pinned; branch-keyed path does not delete a repo-keyed entry | 3, 6 | `(pa7)` |

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
bash scripts/check-lockstep-pairs.sh
```

## Risks / rollback notes

- **`with_entries` on a legacy url-only entry.** `state-schema.md:310` guarantees legacy
  entries may lack `branch`/`repo`, so the predicate reads url defensively
  (`(.value.url // "")`) and never assumes shape. A legacy entry with a *different* url is
  preserved; one with the *same* url is a genuine duplicate and is correctly dropped.
- **Silent deletion.** The heal removes a record. It is bounded to same-url-different-key,
  which is exactly the duplicate case, and `(pa6)`/`(pa7)` pin both directions. Rollback is
  reverting step 3 alone — steps 1–2 and 4–7 are inert docs/tests.
- **`(pa8)` breadth.** It asserts against every `cmd_*`, so a future `--repo` command with a
  drifted usage line fails the suite. That is the intent, not a regression.
- Rollback for the whole change is a branch revert; nothing is migrated and no state file
  shape changes.

## Out-of-scope

- The rung-1 fail-closed precondition (refuse branch-keyed writes on a pair topology) —
  retracted by the filer, subsumed by #243.
- `pr-remove` (option 2) — superseded by the self-heal (D-2).
- The `--force` usage-line inconsistency across unrelated commands (D-6).
- `cmd_build_checkpoint_7_perrepo`'s missing usage comment (D-5).
- Any change to which key each `pr-add` form writes (AC-5).

Unverified references: none.
