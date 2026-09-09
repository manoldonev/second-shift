# second-shift #832 — The consumer-facing pointers name the current pipeline skills

#829 renamed the pipeline's three skills to `run` / `build` / `review` and left the `-lean`
spellings as deprecated alias stubs. Three shipped surfaces still name the aliases as *the*
invocation, and one of them — the consumer template — is copied into every repo
`/second-shift:onboard` touches, so a newly onboarded repo is told to type a deprecated alias.

This corrects the pointers. It deletes nothing: the aliases stay resolvable until the next major,
which is what keeps already-copied templates working and makes this a prose fix rather than a
consumer migration.

## Goal

The three shipped surfaces that name a pipeline skill invocation name the current spelling, and no
tracked file outside the frozen record set and the alias directories themselves still names a
`-lean` invocation.

## Scope

### In

- `plugins/second-shift/templates/consumer/SECOND-SHIFT.md` — the skill-inventory line and the
  CI-assertion line.
- `schema/second-shift.config.schema.json` — the `ticketTag` `description` string.
- `.github/ISSUE_TEMPLATE/pipeline-aborted.yml` — the `what-happened` placeholder.

### Out

- Deleting the three alias skill directories. They are retained until the next major; that
  deletion is a one-line follow-up at the bump, not this ticket's.
- `LEAN_*` identifiers and the guard-script filenames (`lean-gate.sh`, `lean-evidence.sh`, …) —
  the epic's other deliverable. None of the three files here contains a `LEAN_` token, so the two
  do not collide.
- The surviving `lean lane` / `lean evidence` **prose** phrases in these files. The epic measured
  in-scope prose in the sibling plugins as its own quantity; re-spelling it here would double-count
  against that measurement. See D-1.
- `docs/plans/`, `CHANGELOG.md` — historical records, never rewritten.
- Any plugin `version` field.

## Acceptance Criteria

- AC-1 — `plugins/second-shift/templates/consumer/SECOND-SHIFT.md` names `/dev-pipeline:run`,
  `/dev-pipeline:build` and `/dev-pipeline:review`, and the skills as `run` / `build` / `review`,
  at both sites (the skill-inventory line and the CI-assertion line).
- AC-2 — `schema/second-shift.config.schema.json`'s `ticketTag` description names
  `/dev-pipeline:run`. Only the description string changes; no structural change, so a consumer's
  pin is unaffected. The file still parses as JSON (`jq empty`).
- AC-3 — `.github/ISSUE_TEMPLATE/pipeline-aborted.yml`'s placeholder names `/dev-pipeline:run`.
- AC-4 — The three alias skill directories under `plugins/dev-pipeline/skills/` (`run-lean`,
  `build-lean`, `review-lean`) are present and unmodified. This ticket does not delete them.
- AC-5 — Outside `docs/plans/`, `CHANGELOG.md`, and the three alias skill directories themselves,
  no tracked file names a `-lean` skill invocation. Verified with a fixed-string grep:
  `git grep -nF 'dev-pipeline:run-lean'` and the `build-lean` / `review-lean` equivalents, each
  over that pathspec, returning nothing. Not verified with a `\b` pattern — `\b` is not honored by
  this repo's grep path and silently matches nothing.

## Design

Design: none — this change edits three prose/description strings. It renders no UI and no
`design.provider` is configured for this repo.

## Decision Ledger

No pre-flight ledger exists for this ticket (`.claude/pipeline-state/832-ledger.md` absent), so
every row below is a build-time decision.

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Whether to also re-spell the surviving `lean lane` / `lean evidence` prose in the three edited files | No. #831 measures "in-scope prose in the four sibling plugins" (95 word-bounded lines) as a quantity its other deliverable is sized against, and `plugins/second-shift/templates/consumer/SECOND-SHIFT.md` is inside that count. This ticket's ACs bind the *invocation* spelling only, so the edit stops at the invocation and the parenthetical it sits in. `docs/config-schema.md:61` already reads `/dev-pipeline:run` alongside unchanged `lean lane` prose, so the mixed state is the one #829 already shipped and not a state this ticket introduces | codebase-derived |
| D-2 | Whether AC-5 earns a shipped regression guard | No. A guard for AC-5 would assert the absence of a prose string, which is exactly the no-prose-presence-guards rule the `writing-tests` skill states. AC-5 is a one-time verification recorded in the PR, and the aliases' own deletion at the next major retires the class | codebase-derived |
| D-3 | Whether this repo's own `.claude/SECOND-SHIFT.md` needs the same edit | No — measured 0 hits for all three fixed strings. It is a rendered copy that was already current; the template under `plugins/` is the shipped source and the only site that drifts | codebase-derived |
| D-4 | Whether `tests/issue-forms-selftest.sh` needs updating alongside AC-3 | No. That suite asserts each form's field ids and required-ness, never placeholder text, so the placeholder edit moves nothing it reads | codebase-derived |

## Notes

The `-lean` alias directories are deliberately untouched (AC-4). Their `SKILL.md` bodies say they
resolve for one minor and are removed at the next major; that promise is what makes this a prose
fix, and re-spelling their own text would falsify it.
