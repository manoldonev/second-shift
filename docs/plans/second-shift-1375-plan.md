# Plan — build reply comments are minimized with the verdicts

## 1. Minimize marked replies

- [ ] 1.1 Add reply cases to the minimize selftest, and a run.sh scenario where a lane reply before the bound verdict is minimized: marked replies by a Bot and by the $GH account are minimized; a later reply, an unmarked lane comment, a stranger's marked comment, the kept verdict and, when `api user` fails, the operator's reply stay expanded (plugins/dev-pipeline/tools/minimize-verdicts-selftest.sh, plugins/dev-pipeline/skills/run/run-verdict-selftest.sh) [AC-1] [AC-2]
- [ ] 1.2 minimize-verdicts.sh also minimizes lane comments whose first line is `build: reply`, posted before the kept verdict; its header and the review skill's minimize step say so (plugins/dev-pipeline/tools/minimize-verdicts.sh, plugins/dev-pipeline/skills/review/SKILL.md, plugins/dev-pipeline/skills/run/run.sh)

## 2. The build's reply rule

- [ ] 2.1 Add scenario cases on the later-round build prompt: it carries the `build: reply` first line and the `## Before you merge` rule, and names plain `gh pr comment` with the bot off and the bot wrapper's path with it on (plugins/dev-pipeline/skills/run/run-selftest.sh, plugins/dev-pipeline/skills/run/run-verdict-selftest.sh) [AC-3] [AC-4]
- [ ] 2.2 One LOCKSTEP reply block in run.sh's later-round build prompt and in build/SKILL.md, and the posting command outside the block in each (plugins/dev-pipeline/skills/run/run.sh, plugins/dev-pipeline/skills/build/SKILL.md)
