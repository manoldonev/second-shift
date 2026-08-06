# second-shift #395 — review-lean carries no jira tracker delta

Child of the combo-guarantees epic (#391).

`run-lean`'s SKILL.md carries a tracker-delta block for `tracker.type: jira`
(no queue label, no tracker writes, `Closes [<KEY>]` under `### Jira Items`).
`review-lean`'s SKILL.md carries none: its step 2 resolves the issue key from
`Closes #N` in the PR body, which resolves nothing under jira. The gate itself
is adapter-insensitive (it takes the issue key as an argument) — this is a
skill-prose gap only.

## Scope

Add one tracker-delta note to `plugins/dev-pipeline/skills/review-lean/SKILL.md`,
mirroring `run-lean`'s, covering:

- **Key resolution.** Under jira, the issue key resolves from `Closes [<KEY>]`
  under `### Jira Items` in the PR body, not `Closes #N` (checklist step 2).
- **Findings comment unaffected.** The step-8 findings comment is a PR comment
  posted via `gh`, not a tracker write — `tracker.writes: false` does not apply
  to it, and it posts identically under both adapters.
- **No other closing-step difference.** Verdict authoring (steps 6–7) and the
  stop condition (step 8) are tracker-agnostic; nothing else in the checklist
  changes under jira.

Prose-only change: no gate script or selftest edit.

## ACs

- AC-1 (critic): `review-lean`'s SKILL.md carries a tracker-delta note
  documenting key resolution (`Closes [<KEY>]` under `### Jira Items`) for the
  jira adapter, in place of the github-default `Closes #N` reading.
- AC-2 (critic): the note confirms the step-8 findings comment is a PR comment
  unaffected by `tracker.writes: false`, and states that no other checklist
  step differs under jira.
- AC-3 (oracle — CI): prose-only change — no gate script or selftest is
  touched; existing suites stay green untouched.
- AC-4 (critic): `Changelog:` trailer present on the commit.

Open regions: none.
