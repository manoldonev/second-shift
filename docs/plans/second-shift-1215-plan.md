# Plan — one short verdict format for review-lead and the lane

## 1. The verdict checker

- [ ] 1.1 Cases for the one-argument mode: a lane-format review-lead verdict passes, and one with `## Decision record rows`, a Strengths, Suggestions or Verdicts section, a `Ready to merge?` line, or an approve with a finding fails (plugins/dev-pipeline/tools/verdict-check-selftest.sh) [AC-1] [AC-2] [AC-3]
- [ ] 1.2 Cases for the length limits and the `none` contributions line, in both modes, each at and over its limit (plugins/dev-pipeline/tools/verdict-check-selftest.sh) [AC-6] [AC-9]
- [ ] 1.3 Add the no-record mode, the Summary, Notes and note limits, and the `none` rule (plugins/dev-pipeline/tools/verdict-check.sh)

## 2. The join

- [ ] 2.1 Cases: both formats write one `lane vs blind:` line and the hidden JSON line and no fold; the report format takes the verdict path, blind notes included (plugins/dev-pipeline/tools/verdict-join-selftest.sh) [AC-7]
- [ ] 2.2 Replace the folded block with the one line, and join a report by the verdict rules (plugins/dev-pipeline/tools/verdict-join.sh)

## 3. The findings the next build round reads

- [ ] 3.1 Scenario cases: the joined verdict carries the `lane vs blind:` line, and the next build prompt has the findings without that line or the JSON line (plugins/dev-pipeline/skills/run/run-joined-selftest.sh) [AC-10]
- [ ] 3.2 Move the cut to the `lane vs blind:` line (plugins/dev-pipeline/skills/run/run.sh)

## 4. The posting script

- [ ] 4.1 Case: a report that fails the checker is refused with no gh write, in both the post and the `--check` run (plugins/review-toolkit/scripts/post-pending-review-selftest.sh) [AC-5]
- [ ] 4.2 Cases: an inline note leaves the body, an inline blocker keeps one pointer line, a finding outside the diff stays in full, and the count line names the inline notes (plugins/review-toolkit/scripts/post-pending-review-selftest.sh) [AC-8]
- [ ] 4.3 Read the lane head lines, run the checker through plain-review-tools.sh, and derive the body from `## Findings` (plugins/review-toolkit/scripts/post-pending-review.sh, plugins/review-toolkit/scripts/plain-review-tools.sh)

## 5. The reviewers' rules

- [ ] 5.1 Change the shared blocks: drop the `none` line, leave out a topic that changed nothing, and name the `lane vs blind:` line (plugins/dev-pipeline/skills/run/run.sh, plugins/dev-pipeline/skills/review/SKILL.md)
- [ ] 5.2 review-lead writes the lane format, copies the style and contributions blocks, runs the checker, and shows coverage on one `Not reviewed:` line (plugins/review-toolkit/skills/review-lead/SKILL.md, plugins/review-toolkit/skills/review-lead/lead-pass-checklist.md)
- [ ] 5.3 Update the prose that names the folded block or the `none` line (plugins/dev-pipeline/skills/run/SKILL.md, plugins/dev-pipeline/skills/review/SKILL.md, docs/extension-points.md)
