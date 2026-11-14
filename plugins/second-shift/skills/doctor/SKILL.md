---
name: doctor
description: Verify this repo's second-shift install and config state against the committed lockfile, and print exact remediation commands for each problem. Run after cloning, after upgrades, whenever the toolkit feels absent.
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
5. If the user asks about pipeline RUNTIME issues: gh auth is `gh auth status`; a ticket's
   labels are `gh issue view <n> --json labels`. A run checks the config, the intake record,
   the lane's commands and the design declaration before it claims anything, and stops with a
   named `env-*` terminal on the first that fails; the checks and the design smoke run only in
   a round.

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
