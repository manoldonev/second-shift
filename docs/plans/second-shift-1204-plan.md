# Plan — the verdict's machine line lists each finding and counts the other reviewers' comments

## 1. Path extraction

- [ ] 1.1 A route path is read whole, a markdown link yields the path inside it, and two route files at one line do not pair (plugins/dev-pipeline/tools/verdict-join-selftest.sh) [AC-10]
- [ ] 1.2 loc() keeps balanced `[..]`, `[[..]]` and `(..)` groups inside a path segment (plugins/dev-pipeline/tools/verdict-join.sh)

## 2. The findings list

- [ ] 2.1 The machine line carries `"v":3`, a `findings` array and every v2 field, under `--format report` and `--format verdict` (plugins/dev-pipeline/tools/verdict-join-selftest.sh, plugins/dev-pipeline/skills/run/run-joined-selftest.sh) [AC-1]
- [ ] 2.2 Each entry is `{src, id, class, path, line, pair}`, with null for a missing id or site, and a report-format lane entry has a null id (plugins/dev-pipeline/tools/verdict-join-selftest.sh) [AC-2]
- [ ] 2.3 Two blind blockers merged onto one lane blocker share its pair number, and an added blind blocker carries `posted_as` (plugins/dev-pipeline/tools/verdict-join-selftest.sh) [AC-3]
- [ ] 2.4 A lone lane dismissal has an entry, every lane finding has one when the blind review did not return, and the ticket-unavailable note has none (plugins/dev-pipeline/tools/verdict-join-selftest.sh) [AC-4]
- [ ] 2.5 A join of 320 findings lists 150 entries, sets `findings_omitted` to 170, and stays under 65,536 bytes (plugins/dev-pipeline/tools/verdict-join-selftest.sh) [AC-5]
- [ ] 2.6 devblock() builds the list in the dev list's pair order, caps it at 150 and prints the line as v3 (plugins/dev-pipeline/tools/verdict-join.sh)

## 3. The count of other reviewers' comments

- [ ] 3.1 The tool counts another author's inline comment, review body and issue comment at or before the start, excludes the gh login and `<appName>[bot]`, and writes nothing on a failed read (plugins/dev-pipeline/tools/other-comments-selftest.sh) [AC-6]
- [ ] 3.2 Add the counting tool, with bot-commit.sh's appName resolution (plugins/dev-pipeline/tools/other-comments.sh)
- [ ] 3.3 `--other-comments` emits a well-shaped file as `other_comments`; no flag, an unreadable file, invalid JSON and a wrong shape each emit null (plugins/dev-pipeline/tools/verdict-join-selftest.sh) [AC-7]
- [ ] 3.4 Add the `--other-comments` flag and name it in the usage line (plugins/dev-pipeline/tools/verdict-join.sh)

## 4. run.sh

- [ ] 4.1 The fake gh serves inline review comments and reviews from their own files (plugins/dev-pipeline/skills/run/run-selftest-lib.sh)
- [ ] 4.2 A run with another reviewer's inline comment posted before the review posts a verdict whose line counts it and passes verdict-check.sh; a failed read posts null (plugins/dev-pipeline/skills/run/run-joined-selftest.sh) [AC-8] [AC-11]
- [ ] 4.3 run.sh counts at the review's start with the operator's gh and passes the file to the join (plugins/dev-pipeline/skills/run/run.sh)

## 5. The two skills

- [ ] 5.1 `/dev-pipeline:review` counts at step 2 into its scratch dir and passes the file in its join block (plugins/dev-pipeline/skills/review/SKILL.md)
- [ ] 5.2 review-lead counts at process step 6 when the branch has a PR and the tool exists, and passes the flag only when the usage line names it (plugins/review-toolkit/skills/review-lead/SKILL.md)
