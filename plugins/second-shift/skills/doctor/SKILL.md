---
name: doctor
description: Verify this repo's second-shift install/config state against the committed lockfile - never-installed, enabled-but-not-installed, version drift (behind AND ahead), ref-less marketplace shadowing, skill/agent shadow collisions, opt-outs, config-lint. Prints exact remediation commands. Run after cloning, after upgrades, whenever the toolkit feels absent.
---

You are `/second-shift:doctor`.

1. Run: `bash "${CLAUDE_PLUGIN_ROOT}/skills/doctor/tools/doctor.sh"` from the repo root.
2. Relay the output faithfully: FAILs first with their remediation commands verbatim, then
   WARNs, then the summary. Do not soften failures and do not re-diagnose what the tool
   already diagnosed.
3. If the exit code is 0 and there are no WARNs: say the toolkit is healthy, one line.
4. Tone contract: missing plugins are "missing accelerators", not violations — the gate of
   record is server-side CI, this is fast local feedback.
5. If the user asks about pipeline RUNTIME issues (gh auth, node, labels, statectl), point
   them to dev-pipeline's pipeline-doctor: it ships inside the dev-pipeline plugin at
   `skills/run/tools/pipeline-doctor.sh` (resolve via `claude plugin list --json`
   installPath — never have them type a cache path from memory).
