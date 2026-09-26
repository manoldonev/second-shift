# Intake receipt — #907

## Decision Ledger

| ID  | Decision | Resolution | Provenance | Kind |
| --- | -------- | ---------- | ---------- | ---- |
| D-1 | How close-out detects gitignored runtime data | Consumer-declared paths only: `git -C "$WT" status --porcelain --ignored -- <pathspecs>`; any output means data is present. No whole-tree `--ignored` and no shipped cache allowlist. Key absent means today's behavior. | user-answered | intent |
| D-2 | What close-out does when declared paths hold data | Skip `git worktree remove`, print the blocking paths in the close-out line (e.g. `worktree $WT left in place: runtime data under <paths>`), and still end `approved`. Same shape as the existing removal-failed branch at `run.sh:788`. Departs from the ticket's literal "report in INFLIGHT_REASON like not clean" (closeout-inflight). | user-answered | intent |
| D-3 | Config key name and shape | `paths.runtimeData`: array of git pathspecs relative to the repo root (e.g. `["apps/api/storage"]`), in the existing `paths` group. | user-answered | intent |
| D-4 | Whether `/second-shift:onboard` drafts the key | Out of scope: the key is opt-in and documented in `docs/config-schema.md` only. | user-answered | intent |
| D-5 | Whether the post-build check (`run.sh:724`) also checks runtime data | No. Only close-out (`run.sh:786-791`) removes the worktree, so the check lives there and leaves `worktree_inflight` unchanged; runtime data isn't unpushed work. | codebase-derived | fact |
| D-6 | A failed status read for the runtime-data check | Fail safe: keep the worktree and say why, per the scheduler's "wrong only in the SAFE direction" rule (`run.sh:479`). | codebase-derived | fact |
| D-7 | configVersion bump | None: an added optional key isn't a breaking change (`docs/config-schema.md` principles). | codebase-derived | fact |
| D-8 | Contract surfaces the key must land in | `schema/second-shift.config.schema.json` (`paths.properties`), `plugins/dev-pipeline/tools/config-lint.sh` (the `paths` known-keys list at :245, plus a type check for an array of strings), `docs/config-schema.md` `paths` row, and a reader in run.sh so `check-config-shadowing.sh` passes. | codebase-derived | fact |
| D-9 | Selftest obligation | A `run-selftest.sh` case in which a declared path holds an ignored file at close-out: the worktree is kept, the paths are printed, and the run ends `approved`. The case fails without the fix (CLAUDE.md run.sh rule). Also a config-lint fixture that rejects a non-array value. | codebase-derived | fact |
| D-10 | Duplicate scan | `dup-scan.sh --issue 907` returned 0 with no candidates. | codebase-derived | fact |

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | Close-out log line when runtime data keeps the worktree | decided (D-2) |
| S-2 | Terminal outcome of a run whose worktree was kept for runtime data | decided (D-2) |
| S-3 | config-lint error for a malformed `paths.runtimeData` | decided (D-8) |
| S-4 | `docs/config-schema.md` documentation of the key | decided (D-3) |
| S-5 | Onboard prompt for the key | out-of-scope — D-4, operator declares it by hand |
| S-6 | Post-build in-flight terminal (`build-inflight`) | decided (D-5) |

## Checks

No ticket-specific checks — the configured lanes cover this change.

## Design frames

Design: none — scheduler and config change, renders no screen.
