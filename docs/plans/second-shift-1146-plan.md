# Plan — the planted bench runs a probe on a case's code before and after its change

## 1. Neutral checkouts

- [ ] 1.1 A selftest that probes a fixture case and finds no plan file, record or ticket in either checkout, and no commit subject equal to the case's commit (plugins/review-toolkit/evals/code-review-bench-eval/planted/probe-selftest.sh) [AC-1]
- [ ] 1.2 Build the `before` and `after` checkouts with neutral subjects, and drop the plan file from `after` (plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py)

## 2. Dependencies

- [ ] 2.1 A selftest with fake npm and corepack that checks npm ci, npm with a generated lockfile, yarn and pnpm through corepack, a probe.json setup after the install, and a second probe that reuses the cache (plugins/review-toolkit/evals/code-review-bench-eval/planted/probe-selftest.sh) [AC-2]
- [ ] 2.2 A probe installer per side that picks the package manager from the base's packageManager and lockfile, keeps its stores in a cache per upstream and base, and runs the overlay's probe.json setup (plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py, plugins/review-toolkit/evals/code-review-bench-eval/planted/overlays/vitejs__vite/probe.json)

## 3. The probe command

- [ ] 3.1 A selftest that drives probe to DIFFERS, SAME after normalization, and UNPROVEN on a failed install, a patch that does not apply and a timeout, and checks the exit codes (plugins/review-toolkit/evals/code-review-bench-eval/planted/probe-selftest.sh) [AC-3] [AC-4]
- [ ] 3.2 The `probe` subcommand: run the command in both sides under the sandbox where present, normalize, compare and print one JSON verdict (plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py)

## 4. Existing renders

- [ ] 4.1 The render and score selftests keep passing unchanged (plugins/review-toolkit/evals/code-review-bench-eval/planted/render-selftest.sh, plugins/review-toolkit/evals/code-review-bench-eval/planted/score-selftest.sh) [AC-5]
