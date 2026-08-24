# Skill-vs-bare-session ablation — evidence

Pre-registration: [`../skill-ablation-pre-registration.md`](../skill-ablation-pre-registration.md)
(landed first, never edited). Results and verdicts: [`../skill-ablation.md`](../skill-ablation.md).

Every file here is a raw session output or a scoring table. No harness was built — the ticket
excludes one, and a checked-in script here would owe a selftest under `CLAUDE.md`, which is
machinery to measure whether there is too much machinery. The commands are recorded instead.

## The bare arm, verbatim

```bash
printf '%s' "$(cat <comparison>/prompt-template.txt <comparison>/ticket-<n>.md)" \
| env -u CLAUDE_CODE_SESSION_ID -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT \
      -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_BRIDGE_SESSION_ID \
      -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN \
      -u CLAUDE_CODE_SSE_PORT -u CLAUDE_EFFORT -u CLAUDE_PID \
  claude -p --model opus --setting-sources '' --allowedTools "Read,Grep,Glob"
```

Run from a detached checkout at the sample's head (comparison 2) or base (comparisons 1 and 3).
`--setting-sources ''` drops the settings files that carry `enabledPlugins`; the same invocation
asked to name any second-shift-family skill answers `NO-SECOND-SHIFT-SKILLS`. `--bare` was rejected:
it demands `ANTHROPIC_API_KEY` and this machine authenticates by OAuth. The env scrub keeps the
build session's own spawn environment out of the child.

CLI `2.1.241`, model `opus`, 2026-08-24. Wall-clock per session in `bare-arm-timings.tsv`.
