# Plan — the planted bench runs a three-stage blind-prove review arm

## 1. The probe, built once per case-run

- [ ] 1.1 A selftest case that the probe's checkouts are built once and back on their commit after each command, and that the bound `probe` wrapper hides the case id (plugins/review-toolkit/evals/code-review-bench-eval/planted/blind-prove-selftest.sh) [AC-1]
- [ ] 1.2 Split `probe()` into a `Prober` that prepares both checkouts once and runs many commands, and add the `bound-probe` subcommand behind prove's `probe` wrapper (plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py)

## 2. The three stages

- [ ] 2.1 Selftest cases with a fake `claude` and a fake probe function: the stage order, three session ids, models and blindness results, the probe results and the summed cost in one record (plugins/review-toolkit/evals/code-review-bench-eval/planted/blind-prove-selftest.sh) [AC-1] [AC-2] [AC-6]
- [ ] 2.2 Selftest cases that hunt's and prove's text reaches the next stage's prompt byte for byte (plugins/review-toolkit/evals/code-review-bench-eval/planted/blind-prove-selftest.sh) [AC-4] [AC-6]
- [ ] 2.3 Selftest cases that a hunt or prove session voids on the corpus, plain's checkout or the state dir, and intent only on the case's `case.json`, not on the ticket or the record (plugins/review-toolkit/evals/code-review-bench-eval/planted/blind-prove-selftest.sh) [AC-3] [AC-6]
- [ ] 2.4 Selftest cases that a failed stage stops the case-run and names the stage, and that the cost cap stops it (plugins/review-toolkit/evals/code-review-bench-eval/planted/blind-prove-selftest.sh) [AC-2] [AC-6]
- [ ] 2.5 Selftest cases that intent's verdict goes through `collect("plain", …)` and `score_review` (plugins/review-toolkit/evals/code-review-bench-eval/planted/blind-prove-selftest.sh) [AC-5]
- [ ] 2.6 The stage prompts (plugins/review-toolkit/evals/code-review-bench-eval/planted/arms/hunt.md, plugins/review-toolkit/evals/code-review-bench-eval/planted/arms/prove.md, plugins/review-toolkit/evals/code-review-bench-eval/planted/arms/intent.md)
- [ ] 2.7 `blind_prove_one`, the fenced-block parser, the probe blocks and the per-stage blindness scan (plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py)

## 3. The run

- [ ] 3.1 Selftest cases that `run --arm blind-prove` refuses another arm, a prove model in hunt's family and a missing stage model before any model call, and that `gate()` still reads plain and lane only (plugins/review-toolkit/evals/code-review-bench-eval/planted/blind-prove-selftest.sh) [AC-1]
- [ ] 3.2 The `run` flags, the arm's dispatch, the judge-family check over every stage model and the changelog row (plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py, plugins/review-toolkit/evals/code-review-bench-eval/planted/run.sh)
- [ ] 3.3 The docs (plugins/review-toolkit/evals/code-review-bench-eval/README.md, docs/testing.md)
