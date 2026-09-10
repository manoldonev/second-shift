# Skill-vs-bare-session ablation — recipe correction: `--allowedTools` never bounded an arm

**Recorded 2026-09-08. #796.** This file corrects a *reading* of the frozen bare-arm recipe. It does
not amend the recipe, and it changes no score.

[`docs/skill-ablation-pre-registration.md`](skill-ablation-pre-registration.md) is **not edited** —
it carries exactly one commit and [`docs/skill-ablation.md`](skill-ablation.md):6-11 makes that
unedited history the thing #644's AC-1 was scored on. The same convention already governs the one
other correction this family has needed, the evidence-path relocation, which was recorded in the
results doc rather than fixed inside the registration. This is the second, and it lands the same way.

## What the registration says, and what the flag does

The frozen bare arm reads, at
[`docs/skill-ablation-pre-registration.md`](skill-ablation-pre-registration.md):28:

```
claude -p --model opus --setting-sources '' [--allowedTools "Read,Grep,Glob"]
```

Every registration in this family that took the bracketed flag was read as launching a **read-only**
session. It never was. `--allowedTools` is an **auto-approve list layered on the permission mode** —
`claude --help` gives it as "Comma or space-separated list of tool names to **allow**". Allowing
three tools does not remove the rest. The flag that restricts the surface is `--tools`: "Specify the
list of **available** tools from the built-in set."

So the observation #796 opened with — arms running `Bash`, one of them `Write` — is not a harness
defect and not a flag that silently no-ops. It is the documented behavior of the flag that was
passed, and a misreading of which flag bounds a session.

## Measured

CLI `2.1.263`, 2026-09-08, one throwaway `-p` session per arm under the registered `env -u` scrub,
each asked to list the tools available to it and to answer without using one.

| arm | flag | built-in tools reported |
| --- | --- | --- |
| A | `--allowedTools "Read,Grep,Glob"` | `Agent, Bash, Edit, Glob, Grep, ListAgents, Read, ReportFindings, ScheduleWakeup, Skill, ToolSearch, Workflow, Write, …` |
| B | `--tools "Read,Grep,Glob"` | `Glob, Grep, Read` — and nothing else |

Arm B reports zero occurrences of `Bash`, `Write` or `Edit`. Arm A reports all three.

One residue worth naming rather than discovering later: `--tools` bounds the **built-in** set only.
Arm B still carried this machine's connected MCP tools, because those are not built-ins.
`--strict-mcp-config` is the flag for that half, and a genuinely bounded arm needs both.

## What this means for what has already been measured

Unchanged, and stated rather than re-run:

- Every arm launched under the bracketed flag was **unbounded**, exactly as
  [`docs/skill-ablation.md`](skill-ablation.md) and
  [`docs/plans/skill-ablation/c1-build/consumer-substrate.md`](plans/skill-ablation/c1-build/consumer-substrate.md)
  already record from the transcripts. This file supplies the *reason*, not a new observation.
- The condition was **constant across control and every ablated arm** in the families that ran under
  it, so it biases no within-family comparison. It bounds any reading that leaned on "the session
  could only read" — the object-store leaks already recorded under §1 and §2 are the concrete cost.
- **Nothing is re-run.** Re-running a registered arm under a corrected recipe once results exist is
  the post-hoc move the registration exists to prevent.

## What the next family uses

A bare arm that is meant to be read-only registers:

```
claude -p --model opus --setting-sources '' --tools "Read,Grep,Glob"
```

`--allowedTools` stays correct wherever it is used in its documented sense — a permission rule that
pre-approves a call the classifier would otherwise stop. `tools/lane-bench-arm.sh` uses it that way
via `LANE_ARM_ALLOWED_TOOLS` and is not affected by anything here.
