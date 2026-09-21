# #867 — A read-only tracker's lane session cannot call an Atlassian write tool

The JIRA adapter promises that nothing in the lane calls an Atlassian write tool, and nothing
enforced it: a consumer BUILD session on `tracker.writes: false` rewrote the ticket it was later
graded against. The scheduler already removes tools from every spawned session with
`--disallowedTools`; under a read-only tracker it now removes the Atlassian write tools too, and
the README says what enforces the promise and where that stops.

## Acceptance criteria

- **AC-1** — When the resolved config's tracker is read-only (`tracker.writes`, defaulting as
  `preflight.sh` does: `true` for github, `false` otherwise), `orchestrate.sh`'s spawn call — the
  one call both BUILD and REVIEW go through — appends every Atlassian write tool to its
  `--disallowedTools` list, under each of the three MCP namespaces the JIRA README names
  (`mcp__atlassian__`, `mcp__plugin_atlassian_atlassian__`, `mcp__claude_ai_Atlassian_Rovo__`).
  The write-tool names live in one list in the scheduler. Read tools (`getJiraIssue`,
  `getJiraIssueRemoteIssueLinks`, `getConfluencePage`, …) are not on it.
- **AC-2** — With `tracker.writes` true (the github default, or an explicit `true`), the spawn
  line is unchanged: `--disallowedTools AskUserQuestion EnterWorktree ExitWorktree`.
- **AC-3** — `orchestrate-selftest.sh` asserts both arms on the spawn argv: every listed write
  tool under all three namespaces on a jira config with no `writes` key (so the default is what is
  exercised), no read tool among them, and no Atlassian tool at all on the github default.
- **AC-4** — `tools/tracker/jira/README.md`'s "No JIRA writes" paragraph names what enforces it
  (the scheduler's spawn deny list, under `tracker.writes: false`) and its boundary: a
  `/dev-pipeline:build` or `/dev-pipeline:review` the operator invokes directly is operator-attended
  and not covered.

## Notes

- No new refusal message and no gate: a denied tool is simply not offered to the session (D-7).
- Commit verb `fix(dev-pipeline)`, `Changelog:` trailer, no version or CHANGELOG.md edit (D-9).

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Which way the acceptance closes: enforce, or retract the documentation | Enforce. An Atlassian write-tool call from a lane session under `tracker.writes: false` is refused, not executed. The README's promise is kept and narrowed to what is enforced (D-6), not dropped. | user-answered |
| D-2 | Where the refusal lives | In the scheduler: `plugins/dev-pipeline/skills/run/orchestrate.sh` extends the spawn's `--disallowedTools` (today `AskUserQuestion EnterWorktree ExitWorktree`, at the spawn call beside `spawn_settings`) with the Atlassian write tools. Both lane roles, BUILD and REVIEW, go through that one call, so both are covered. No plugin PreToolUse hook. A `/dev-pipeline:build` the operator invokes directly is operator-attended and out of this guard's reach. | user-answered |
| D-3 | When the extra deny list applies | Only when the resolved config's tracker is read-only. `tracker.writes` is derived with the same default `preflight.sh` uses: `if .tracker.writes != null then .tracker.writes else (.tracker.type // "github") == "github" end`, read from the config the scheduler already resolves (`${SECOND_SHIFT_CONFIG:-$MAIN_ROOT/.claude/second-shift.config.json}`). With `writes: true` the spawn line stays exactly as it is today. | codebase-derived |
| D-4 | Which tools are denied | Every Atlassian **write** tool, JIRA and Confluence alike, because the principle in `tools/tracker/jira/README.md` says "an Atlassian write tool", not "a JIRA write tool". The read tools the adapter's fetch-ticket operation needs (`getJiraIssue`, `getJiraIssueRemoteIssueLinks`, `getConfluencePage`, …) stay callable. The list is kept in one place in the scheduler. | codebase-derived |
| D-5 | MCP namespace coverage | Every denied tool is listed under all three namespaces the JIRA README's Prerequisite names: `mcp__atlassian__*`, `mcp__plugin_atlassian_atlassian__*` and `mcp__claude_ai_Atlassian_Rovo__*`. | codebase-derived |
| D-6 | Documentation after the change | `tools/tracker/jira/README.md`'s "No JIRA writes" paragraph states what enforces it (the scheduler's spawn deny list) and its boundary (a directly invoked `/dev-pipeline:build` is operator-attended and not covered). The build and review SKILL.md tracker-delta notes change only if they repeat the claim. | codebase-derived |
| D-7 | What happens in the session when a denied call is attempted | Nothing new: the tool is not offered to the session, the same way the existing D-6 entries on that line are not (the scheduler's comment at the spawn call). No new refusal message and no new gate. | codebase-derived |
| D-8 | Test coverage | `orchestrate-selftest.sh` asserts the spawn argv: the Atlassian write tools are present under a `writes: false` jira config and absent under the github default. No new selftest file (CLAUDE.md: tests are discovered by glob, and each script is covered by some selftest). Not a new gate contract, so the liveness scenario is not extended. | codebase-derived |
| D-9 | Commit verb and changelog | `fix(dev-pipeline)`: shipped behavior is brought in line with shipped docs. The `Changelog:` trailer says lane sessions on a read-only tracker can no longer call Atlassian write tools. Migration: none. No version or CHANGELOG.md edit (CLAUDE.md, frozen release files). | codebase-derived |
| D-10 | Build-model sizing | `opus`. Basis: in this repo the answer is always opus, and this changes a shipped scheduler launch line every consumer lane goes through. | codebase-derived |
