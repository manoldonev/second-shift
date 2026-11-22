# Plan — decision questions carry each option's cost, graded by an eval

## 1. Scaffold script

- [ ] 1.1 Selftest that builds its own git repo, runs the scaffold script against it, and checks that the current directory holds `TICKET.md` and the commit's tree without `.git`, `.claude/` and `plugins/intake-toolkit/`, and that the script exits non-zero with one stderr line when the repo lacks the commit or is not a git repo (plugins/intake-toolkit/evals/decision-questions-eval/scaffold-selftest.sh) [AC-5]
- [ ] 1.2 Scaffold script and the fixture ticket (plugins/intake-toolkit/evals/decision-questions-eval/scaffold.sh, plugins/intake-toolkit/evals/decision-questions-eval/fixture/TICKET.md)

## 2. Eval case

- [ ] 2.1 Case definition with the run shape and the five graders (plugins/intake-toolkit/evals/decision-questions-eval/case.yaml)
- [ ] 2.2 README with the run command, the "before" recipe, the trace check and the `BASELINE.md` row format, and an empty `BASELINE.md` (plugins/intake-toolkit/evals/decision-questions-eval/README.md, plugins/intake-toolkit/evals/decision-questions-eval/BASELINE.md)
- [ ] 2.3 Ignore the runner's reports (plugins/intake-toolkit/evals/.gitignore)

## 3. Interview rules

- [ ] 3.1 Replace rule 2, put the decision-question rule in rules 3 and 4, split rule 9 into two cases, and give the `Options weighed:` list one form (plugins/intake-toolkit/skills/interviewing-baseline/SKILL.md)
- [ ] 3.2 Refer to that form from the receipt stage (plugins/intake-toolkit/skills/intake/receipt.md)
- [ ] 3.3 Remove every restatement of the cap and align every sentence that requires a recommendation on every question (plugins/intake-toolkit/skills/plan-interview/SKILL.md, plugins/intake-toolkit/skills/grill-me/SKILL.md, plugins/intake-toolkit/skills/intake/requirements.md, plugins/intake-toolkit/skills/intake/interview.md, plugins/design-toolkit/skills/figma-iterate/SKILL.md)
