# Lean spec — #207: RUN_ID recipe leaks the machine hostname into public tracker comments

## Context

The Pre-flight `RUN_ID` recipe in `plugins/dev-pipeline/skills/run/SKILL.md` (the single site
that invokes `hostname`, confirmed by repo-wide grep) is:

```bash
RUN_ID="$(date -u +%Y-%m-%dT%H%M%SZ)-$(hostname -s)-$(openssl rand -hex 4)"
```

`hostname -s` frequently resolves to a personally identifying value (macOS default:
`<FirstName>-<LastName>s-<Model>`), and `RUN_ID` lands verbatim in the `<!-- run_id: ... -->`
marker of every pipeline comment posted to the tracker, public repos included. The
`/dev-pipeline:pipeline-retro 205` datapoint on this issue recorded the correct-by-construction
direction: the recipe should stop reading `hostname` at all rather than sanitize it — the host
token carries no diagnostic value the timestamp plus the random suffix don't already provide,
and a run is already correlatable via `pipelineSessions[].sessionId`. No selftest pins the
recipe's string format (confirmed by grep), so this is a documentation-only fix. Two other
files echo the old format string in prose without invoking `hostname` themselves —
`plugins/dev-pipeline/skills/pr-revision/SKILL.md` and
`plugins/dev-pipeline/skills/run/state-schema.md` — both in scope alongside the recipe site so
the documented format stays consistent everywhere it is stated.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Hash-and-keep vs. drop the host component | Drop `hostname` from the recipe entirely (retro's "correct-by-construction" direction), not hash it (issue body's initial "Fix direction" #1) — a hash still couples RUN_ID's uniqueness to whatever the local machine reports, unreviewed, for zero diagnostic gain over timestamp+random-hex, which already disambiguate concurrent runs. | issue retro comment (`/dev-pipeline:pipeline-retro 205`) |
| D-2 | Config override | None added (issue body's "Fix direction" #2, `tracker.hostToken`) — with the host component dropped, there is nothing left to override; adding an unused schema knob would be scope beyond what the fix needs. | codebase-derived |
| D-3 | Format | `{ISO timestamp}-{random 8 hex chars}` — drops the middle segment, keeps the two components that already guarantee uniqueness. | codebase-derived |
| D-4 | Crash-recovery resume | Unaffected — `RUN_ID` is read back from state via `statectl get "$ISSUE" '.runId'`, never re-derived, per the existing SKILL.md prose this fix does not touch. | codebase-derived |

## Acceptance Criteria

- AC-1: The `RUN_ID` recipe in `plugins/dev-pipeline/skills/run/SKILL.md`'s Pre-flight section
  no longer invokes `hostname` in any form — the value is built from the UTC timestamp and a
  random hex suffix only.
- AC-2: The recipe's "Format:" prose line is updated to match the new value shape
  (`{ISO timestamp}-{random 8 hex chars}`), with no remaining reference to a hostname
  component.
- AC-3: Repo-wide grep for `hostname` under `plugins/` finds no remaining occurrence tied to
  RUN_ID generation or its documented format — covers the recipe site plus the two prose
  echoes in `pr-revision/SKILL.md` and `run/state-schema.md`.
- AC-4: shellcheck, jq, and the full `*-selftest.sh` sweep stay green (no selftest asserts the
  old format, so none require updating; this AC guards against a regression introduced
  elsewhere).
- AC-5: `scripts/check-pipeline-chain.sh`'s comment above `FAMILY_SHORT="${FAMILY##*-}"` — which
  described the pre-fix 3-part format and its hostname-redaction rationale — is updated to match
  the new 2-part format. Found by milestone-4 review (round 1); in scope because this change is
  what made the comment stale, even though the file sits outside `plugins/`.

## Out of scope

- Scrubbing historical comments that already carry a hostname — the issue explicitly marks
  this operator judgment, not part of the fix.
- A `tracker.hostToken` config override (issue body's "Fix direction" #2) — superseded by D-2:
  dropping the host component removes the need for an override.
