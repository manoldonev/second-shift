# second-shift #408 — tracker README's lean-lane branch-site counts are stale for both scripts

## Problem

`plugins/dev-pipeline/skills/run/tools/tracker/README.md`'s lean-lane section states two numeric
branch-site counts, and both are now wrong:

- `lean-gate.sh` "branches at exactly **three** sites" — true when written in #365, but #376 added
  a fifth `[ "$TRACKER_TYPE" = "jira" ]` conditional (`check_pause_and_ask`, reached from milestone
  1) that belongs to none of entry/claim/exit.
- `lean-reconcile.sh` "branches at exactly **one**" — the file now carries three behavioral
  conditionals (the `--comments-file` refusal under jira, plus two more). Already flagged as a
  warning on both the #388 and #398 verdict records without being filed until now.

#407 already fixed this exact staleness pattern for the adjacent *lane-operation* prose in the
same file (dropped the count rather than re-pinning it), for the same reason: any conditional
added to either script re-stales a pinned number, and the sentence gives no signal that it needs
re-checking.

## Scope

The two sentences in `run/tools/tracker/README.md`'s lean-lane section (`lean-gate.sh`'s and
`lean-reconcile.sh`'s branch-site counts). Apply the #407 remedy: drop the numeric count, keep the
noun phrase.

Out of scope: restructuring the lean-lane operation table; the `run` lane's operation table.

## Design

Design: none — prose-only change to a markdown file, no UI surface, and `design.provider` is
unconfigured in this repo.

## Acceptance criteria

**AC-1.** Neither sentence states a numeric count of a script's tracker branch sites.

**AC-2.** The docs still distinguish gate branch sites from the lane-operation table, and still
record that both scripts reject an unrecognized `tracker.type` rather than falling through to an
arm.

**AC-3.** Prose-only change — no gate or selftest edits; existing suites green untouched.

**AC-4.** `Changelog:` trailer present.

## Test tier

Per `CLAUDE.md`'s tier map, this is prose in a markdown file — **nothing** is written for it; a
grep asserting a literal is present in a `.md` is the banned class. AC-3 is verified by running the
existing verification sweep unchanged (shellcheck, jq, selftests) and confirming no script or
selftest file is touched by the diff.

## Release metadata

- Bump: **patch**. Prose-only fix, no capability change — the honest verb is `docs:`.
- `Changelog:` trailer: the bare no-op form, `Changelog: none.` — nothing in this change is
  consumer-visible (same rationale #407 used for the same file: `derive-release.sh`'s
  `render_bullet` suppresses a Changelog block only when the whole block normalizes to exactly
  `none`, so a dash-rationale form ships verbatim as a release bullet — do not use it here).
