# second-shift#72 — doc-routing.md: lint that routed doc paths resolve

## Problem

`doc-routing.md` is an EP-3 extension file (`extension-manifest.txt:12`) checked only by
**basename** — its content (the change-category → doc-path routing map read by dev-pipeline's
Stage-7 `doc-update.md` and `review-toolkit/agents/doc-updater.md`) has no lint. A routing
entry pointing at a moved or deleted doc silently misroutes future doc updates to a fallback
(CLAUDE.md router / basename grep), with no signal.

## Acceptance criteria

- **AC-1.** `plugins/dev-pipeline/skills/run/tools/check-doc-routing.sh` exists, callable as
  `check-doc-routing.sh [consumer-repo-root]` (default `.`). Follows this repo's `check-*.sh`
  conventions (mirrors `check-extensions.sh`): `#!/usr/bin/env bash`, `set -euo pipefail`,
  bash-3.2-safe (no associative arrays / `${var,,}`), an env-seam override for the
  doc-routing-file path for hermetic selftests.

- **AC-2.** When `.claude/second-shift/doc-routing.md` does not exist in the consumer repo,
  the check is a clean no-op (exit 0) — doc-routing.md is an optional extension file, and
  this repo's own tree currently has none, so its own preflight/Stage-7 must stay green.

- **AC-3.** When present, the script scans only two line shapes and ignores everything else
  (prose, blockquotes, headings): markdown table body rows (lines starting with `|`,
  excluding the header and `---` separator rows) and top-level list items (lines starting
  with `-` or `*`). From each scanned line it extracts every backtick-quoted (`` `...` ``)
  span as a candidate doc path — except that for a list item, only spans occurring before an
  em-dash (` — `) description separator (if one is present) count; text after it is prose,
  not a path.

- **AC-4.** Each candidate path is resolved relative to the consumer repo root:
  - a `#`-suffixed anchor is stripped and the remaining path is checked to file level only
    (the anchor itself is never verified);
  - a candidate containing `*` is resolved via shell glob and passes if it matches at least
    one path (matches how `extension-manifest.txt` glob entries already work) — needed
    because real routing maps reference sibling groups this way (see AC-9);
  - any other candidate must exist as a file or directory.

- **AC-5.** A dangling entry fails closed: one line per failure to stderr, tagged
  `DANGLING-DOC-ROUTE:`, naming both the source row/list-item text the path came from and the
  unresolved path itself, plus a one-line summary count. Exit code = number of distinct
  dangling paths found (0 = clean, matching the `check-extensions.sh` doctor convention).

- **AC-6.** Wired at the same two venues `check-extensions.sh` already runs at, immediately
  alongside its existing call at each: dev-pipeline's own pre-flight
  (`plugins/dev-pipeline/skills/run/SKILL.md`, the pre-flight step around "(0b) Extension
  integrity") and the onboarding preflight
  (`plugins/dev-pipeline/skills/run/tools/preflight.sh`, Section 1 "Config gates"). Both
  fail closed (abort / FAIL line) on any `check-doc-routing.sh` failure, naming the rejected
  entries.

- **AC-7.** Additionally wired at Stage-7 entry
  (`plugins/dev-pipeline/skills/run/doc-update.md`): before the protocol consumes
  doc-routing.md's rows as the Step 7.B routing table, it runs `check-doc-routing.sh` and
  stops with the failure output if it fails — a stale routing map is caught right where it
  would otherwise misroute, instead of silently falling back to the CLAUDE.md router.

- **AC-8.** `plugins/dev-pipeline/skills/run/tools/check-doc-routing-selftest.sh` exists
  alongside the script, mirroring `check-extensions-selftest.sh`'s per-scenario
  `mktemp -d` fixture pattern (`ok()`/`bad()` helpers, `trap ... EXIT` cleanup, grep the
  captured output for the expected tag/substring). Covers at minimum:
  - a valid map (a plain-file entry, a directory entry, and a glob entry all resolving)
    passes clean;
  - one entry pointing at a renamed/moved doc fails, and the failure output names that entry;
  - one entry pointing at a deleted doc fails;
  - no `doc-routing.md` present passes trivially (AC-2).

- **AC-9.** cadenza's real `.claude/second-shift/doc-routing.md` — the routing map named as
  the live fixture in the source issue — passes the new check unmodified. Verified manually
  against the external consumer checkout available on this machine as part of milestone-3
  implementation (not a committed selftest fixture: cadenza is not part of this repo's
  tree). This is what motivates the glob-matching rule in AC-4: that file's
  "stale-risk hotspots" list includes a `` `review-context/*.md` `` glob entry alongside
  literal paths, in the same row.

- **AC-10.** No CI workflow edit needed: `check-doc-routing-selftest.sh` is auto-discovered
  by `.github/workflows/ci.yml`'s existing `find . -name '*-selftest.sh'` sweep, the same way
  `check-extensions-selftest.sh` already is — satisfying "listed in the #33 CI emission set
  alongside the other config gates" by the repo's existing coverage-by-naming-convention.

## Non-goals

- No change to `doc-routing.md`'s format itself, and no scaffold/template is added for it —
  none exists in this repo today (confirmed: no `doc-routing.md` anywhere in this repo's own
  tree), and this issue is about linting a consumer's existing file, not authoring one.
- No change to the `/second-shift:onboard`-emitted consumer-side CI check
  (`second-shift-ci-check.sh`) — that surface only runs `config-lint.sh` today and adding
  `check-doc-routing.sh` there is separate scope not requested by this issue.
