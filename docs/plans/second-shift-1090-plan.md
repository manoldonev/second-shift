# Plan — a planted-defect corpus and a recipe that runs a plain review and the lane on it

## 1. Corpus structure

- [ ] 1.1 A selftest checks the shipped corpus passes the structure check, and that a copy missing each required part, or short of a class, fails naming it (plugins/review-toolkit/evals/code-review-bench-eval/planted/corpus-selftest.sh) [AC-7] [AC-8]
- [ ] 1.2 The structure check in the recipe: upstream, license, base sha, ticket with an AC block, record with a Test intent line, overlay, patch with a plan, ground truth, per-class counts, NOTICE (plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py)
- [ ] 1.3 The corpus: four cases per class P1–P5 and five clean controls from MIT upstreams, with their overlays and NOTICE (plugins/review-toolkit/evals/code-review-bench-eval/planted/cases, plugins/review-toolkit/evals/code-review-bench-eval/planted/overlays, plugins/review-toolkit/evals/code-review-bench-eval/planted/NOTICE)

## 2. Building a case and rendering both arms

- [ ] 2.1 A selftest builds a local case for each arm, checks the commit order, the missing remote and the origin ref, runs the lane gates, renders both prompts without a model, serves the ticket and the empty PR through the local gh, captures a posted verdict, and finds no planted marker in either prompt or checkout (plugins/review-toolkit/evals/code-review-bench-eval/planted/render-selftest.sh) [AC-9] [AC-8]
- [ ] 2.2 Materialize a case: base, overlay commit, record commit (lane only), patch commit, no remote, a local origin ref (plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py)
- [ ] 2.3 Extract the review prompt, the scheduler input, the gates and their helpers from run.sh as merged, and run them in order (plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py, plugins/review-toolkit/evals/code-review-bench-eval/planted/lane-render.sh)
- [ ] 2.4 The local gh and the plain arm's prompt (plugins/review-toolkit/evals/code-review-bench-eval/planted/gh, plugins/review-toolkit/evals/code-review-bench-eval/planted/arms/plain.md)
- [ ] 2.5 The blindness scan takes the pattern the planted mode allows (plugins/review-toolkit/evals/code-review-bench-eval/bench.py)

## 3. Scoring

- [ ] 3.1 A selftest drives the scorer on canned reviews with a canned judge and checks right, wrong, harm and noise per class and arm, the three-line window, the judge only on in-range findings, P2 by row id, P5 by note, gate stops, unscorable verdicts and the gate (plugins/review-toolkit/evals/code-review-bench-eval/planted/score-selftest.sh) [AC-10] [AC-8]
- [ ] 3.2 The scorer, the calibration gate first, the per-class report with cost and wall time, and the changelog rows (plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py, plugins/review-toolkit/evals/code-review-bench-eval/planted/changelog.md)
- [ ] 3.3 The operator's entry point (plugins/review-toolkit/evals/code-review-bench-eval/planted/run.sh)

## 4. Docs

- [ ] 4.1 The Benchmark tier documents the recipe, the gate and that CI never runs it (docs/testing.md, plugins/review-toolkit/evals/code-review-bench-eval/README.md)
