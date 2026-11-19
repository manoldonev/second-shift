# Plan — the implementability probe runs one round, with a 30-turn cap and resumes

All four ACs are exempt in the record's Test intent (D-14). Selftest case B1 of
`check-emit-deadline-selftest.sh` lints the new cap and deadline pair at the head.

## 1. The probe agent

- [ ] 1.1 Raise the cap to 30 and the deadline to turn 20 (plugins/intake-toolkit/agents/implementability-probe.md)
- [ ] 1.2 Add the `unverified` status for an AC line and a guess-point, and replace the `[human]` deadline fallback (plugins/intake-toolkit/agents/implementability-probe.md)
- [ ] 1.3 Add the resume rule: the deadline counts from the resume, and the probe works only the named items (plugins/intake-toolkit/agents/implementability-probe.md)
- [ ] 1.4 Remove the body-only mode from the description and the body (plugins/intake-toolkit/agents/implementability-probe.md)

## 2. The Receipt stage

- [ ] 2.1 Remove "### 3. Implementability probe" and the "one more round" sentence of the exit gates (plugins/intake-toolkit/skills/intake/receipt.md)
- [ ] 2.2 Move the routing list and the no-`Task` rule into "Probe the record", and run it whenever the ticket has an AC block (plugins/intake-toolkit/skills/intake/receipt.md)
- [ ] 2.3 Add the partial-report rule: at most 2 SendMessage resumes, then the operator question, the `Requirements:` line and the `OR-n` per unverified item (plugins/intake-toolkit/skills/intake/receipt.md)

## 3. The docs that name the rounds

- [ ] 3.1 Say one round in the gate row (plugins/intake-toolkit/skills/intake/SKILL.md)
- [ ] 3.2 Say one round in both SECOND-SHIFT.md files (.claude/SECOND-SHIFT.md, plugins/second-shift/templates/consumer/SECOND-SHIFT.md)

## 4. The probe eval

- [ ] 4.1 Retire README steps 1 to 4 and keep the record round (plugins/intake-toolkit/evals/implementability-probe-eval/README.md)
- [ ] 4.2 Drop run 1 and the body-round part of run 2 (plugins/intake-toolkit/evals/implementability-probe-eval/BASELINE.md)
