# #229 — pipeline-doctor block 8 silently skips state files with no lastUpdatedAt

`pipeline-doctor.sh` block 8 (stale claims) is meant to anchor an undeterminable
`lastUpdatedAt` at epoch so the file is flagged as ancient — that is what the comment above
the jq expression claims. Because `|` binds looser than `//` in jq, the expression actually
parses as `(.lastUpdatedAt // empty) | (fromdateiso8601? // 0)`: a *missing* field yields
`empty` on the left, and piping `empty` short-circuits the whole pipeline, so the file
produces no output and is silently skipped. An *unparseable* value (a non-null string) still
reaches `fromdateiso8601?`, errors, and correctly anchors at epoch. Landed under #215 as a
characterized-not-fixed divergence, pinned by `(d5a)` in
`pipeline-doctor-selftest.sh`.

Net effect: a truncated or partially-written state file — exactly the shape an infra-killed
run leaves behind — is invisible to the stale-claim check forever, in the diagnostic an
operator reaches for while debugging a dead run.

## Acceptance criteria

- AC-1: An `in_progress` state file with no `lastUpdatedAt` is surfaced as a stale claim,
  matching block 8's own comment ("Missing/unparseable lastUpdatedAt anchors at epoch").
  Fix is one token: `(.lastUpdatedAt // empty)` → `(.lastUpdatedAt // "")` so the left side
  of the `|` always yields a value and `fromdateiso8601? // 0` anchors both the missing and
  unparseable cases at epoch.
- AC-2: `(d5b)` (unparseable `lastUpdatedAt`) is unchanged, and `(d6)` (missing/wrong-typed
  `runId`/`stages`, non-state JSON) still filters those files out entirely — the `select`
  guards ahead of the `|` are untouched.
- AC-3: `(d5a)` in `pipeline-doctor-selftest.sh` is flipped to assert the fixed behavior (the
  fixture is surfaced as stale, mirroring `(d5b)`'s assertion shape) and its "known fail-open"
  annotation is removed.
- AC-4: The `CLAUDE.md` register entry for this item (the `pipeline-doctor.sh` bullet under
  "Characterization is not endorsement", and its `#229` reference in the tracking sentence
  that follows) is removed in this PR, since the divergence it names no longer exists. The
  `exitplan-ledger-gate.sh` / `#228` entry in the same section is untouched — that one is
  still open.

## Out of scope

- `exitplan-ledger-gate.sh` tier 3's `find -newermB` GNU/BSD divergence (#228) — separate,
  unrelated fail-open, tracked independently.
- Any change to block 8's 30-minute threshold, the quarantine filename filter (`(d4)`), or
  the `select` guards on `runId`/`stages`/`status` (`(d6)`) — all correct as-is and covered
  by existing cases.

## Verification notes

Stage 6's INERT lane skips lint/test on `.sh`/`.md`-only diffs; the full local sweep
(shellcheck + `*-selftest.sh` + jq) is run by hand and reported in the PR body. Commit verb
`fix:` (patch bump). This touches `plugins/dev-pipeline/**`, so the commit needs a
`Changelog:` trailer describing the operator-visible behavior change (`pipeline-doctor.sh`
now surfaces a truncated/no-`lastUpdatedAt` state file as a stale claim instead of silently
skipping it) — not `none`, since the WARN output consumers see changes. No frozen release
artifact (`version`/`CHANGELOG.md`/marketplace version) touched.
