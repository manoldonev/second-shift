---
name: doctor
description: Verify this repo's second-shift install/config state against the committed lockfile - prerequisites, settings/lockfile ref lockstep, never-installed, enabled-but-not-installed, version drift (behind AND ahead), project-scope records a user-scope one makes redundant, ref-less marketplace shadowing, skill/agent shadow collisions, opt-outs (informational), stale consumer CI from the retired verdict-record lane, config keys configVersion 3 removed, config-lint, config grill (advisory). Prints exact remediation commands, scoped to the record that actually loads. Run after cloning, after upgrades, whenever the toolkit feels absent.
---

You are `/second-shift:doctor`.

1. Run: `bash "${CLAUDE_PLUGIN_ROOT}/skills/doctor/tools/doctor.sh"` from the repo root.
2. Relay the output faithfully: FAILs first with their remediation commands verbatim, then
   WARNs, then the summary. Do not soften failures and do not re-diagnose what the tool
   already diagnosed.
3. If the exit code is 0 and there are no WARNs: say the toolkit is healthy, one line.
4. Tone contract: missing plugins are "missing accelerators", not violations — this is fast
   local feedback. Config grill findings are WARNs by design: each proposes a value and says
   what it buys, and declining one is the repo's call.
5. A config still on configVersion 2 gets one FAIL per removed key (`topology`, `gates`,
   `stageParams`, `grillWaivers`, `design.liveRender.tolerancePx`, `design.liveRender.cwd`), each
   pointing at `docs/migrations/v2-to-v3.md`. An installed `second-shift-ci.yml`,
   `second-shift-ci-check.sh` or `second-shift-delta-guard.*`, or any `LANE_VERDICT_SUFFIX`
   reference under `.github/` or `.claude/`, is one FAIL: those read a verdict record the lane no
   longer writes, and the consumer deletes them.
6. If the user asks about pipeline RUNTIME issues: gh auth is `gh auth status`; a ticket's
   labels are `gh issue view <n> --json labels`. `/dev-pipeline:run <ticket> --dry-run` checks
   the config, the intake record, the lane's commands and the design declaration and lists the
   checks, writing nothing; it does not read the tracker, and the checks and the design smoke
   run only in a real round.

## `--report` — assemble a feedback bundle

When the user wants to file a feedback issue (a pipeline abort, a config-lint disagreement, a
review false positive) or asks for a report bundle, run doctor with `--report`:

`bash "${CLAUDE_PLUGIN_ROOT}/skills/doctor/tools/doctor.sh" --report`

It prints one paste-ready Markdown block — the normal doctor output, `claude plugin list --json`,
the **redacted** config, context coverage, and the tail of the newest detached run's log from
`.claude/pipeline-state/` (its `terminal: <slug>` line and the reason before it; a foreground run
leaves no log, so its run directory's file list stands in) — sized to drop straight into the
matching issue form in the second-shift repo's `.github/ISSUE_TEMPLATE/` (pipeline aborted,
config-lint disagreement, review false positive). Relay it verbatim. Sensitive-shaped config
values are auto-redacted, but remind the user to glance over it before posting. `--report` always
exits 0 — it assembles, it does not gate.
