# Plan — every relevant finding gates

## 1. The verdict checker

- [ ] 1.1 Test: an approve that carries a `[note]` fails; a needs-work whose only findings are notes passes; a needs-work with no finding still fails (plugins/dev-pipeline/tools/verdict-check-selftest.sh)
- [ ] 1.2 Fail an approve on any finding, and accept a needs-work on any finding (plugins/dev-pipeline/tools/verdict-check.sh)

## 2. The join of the blind review

- [ ] 2.1 Test: an unmatched blind note is added as a `[blind]` note with the next N id and flips an approve; a matched one is not listed twice; the machine line counts it (plugins/dev-pipeline/tools/verdict-join-selftest.sh, plugins/dev-pipeline/skills/run/run-joined-selftest.sh)
- [ ] 2.2 Match, add and count blind notes under `--format verdict`; leave `--format report` as it is (plugins/dev-pipeline/tools/verdict-join.sh)

## 3. The scheduler

- [ ] 3.1 Test: a canned needs-work whose only finding is a convention note binds and starts round 2; the round-2 build is told to fix or rebut every finding (plugins/dev-pipeline/skills/run/run-verdict-selftest.sh, plugins/dev-pipeline/skills/run/run-selftest.sh, plugins/dev-pipeline/skills/run/run-selftest-lib.sh)
- [ ] 3.2 Rewrite the review rules, the verdict grammar and style, and the round-2 build order in every copy (plugins/dev-pipeline/skills/run/run.sh, plugins/dev-pipeline/skills/review/SKILL.md, plugins/dev-pipeline/skills/build/SKILL.md, plugins/review-toolkit/evals/code-review-bench-eval/arms/lane-review.md)
- [ ] 3.3 Apply the relevance bar to both tags of the blind review (plugins/dev-pipeline/skills/run/plain-review.md)

## 4. The planted eval scorer

- [ ] 4.1 Test: on the lane and joined arms a `[note]` is send-back, an approve that misses P5 is wrong, an unmatched note is noise and a note on a control is harm; the plain arm keeps its scoring and its contract, so a note-only plain needs-work is unscorable (plugins/review-toolkit/evals/code-review-bench-eval/planted/score-selftest.sh)
- [ ] 4.2 Score notes as send-back for the lane and joined arms (plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py, docs/testing.md)
- [ ] 4.3 Test: on the lane and joined arms a pathless `[note]` on a path-level case goes to the judge, and a match is right (plugins/review-toolkit/evals/code-review-bench-eval/planted/score-selftest.sh)
- [ ] 4.4 Send a pathless send-back finding to the judge, a note too on the lane and joined arms (plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py, docs/testing.md)
- [ ] 4.5 Test: a stored lane or joined approve that carries a `[note]`, as `--rescore` reads it, is no harm on a control and wrong on a planted case (plugins/review-toolkit/evals/code-review-bench-eval/planted/score-selftest.sh)
- [ ] 4.6 Count a lane or joined `[note]` as send-back only on a needs-work (plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py, docs/testing.md)
- [ ] 4.7 The bench lane arm writes every finding it reports, with no dismissed or suppressed finding (plugins/review-toolkit/evals/code-review-bench-eval/arms/lane-review.md)
