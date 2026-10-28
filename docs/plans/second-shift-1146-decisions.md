# Decision record — #1146 The planted bench runs a probe on a case's code before and after its change

Receipt: v4

## Summary

`planted.py probe` builds a planted case's neutral `before` and `after` checkouts and installs each side's dependencies with the upstream's own package manager. It runs one shell command in both sides, with no network where a sandbox exists. It prints one JSON verdict: `DIFFERS`, `SAME` or `UNPROVEN`. Nothing calls a model, and the lane and plain renders do not change.

Open regions: OR-1 the selftest fakes both npm and corepack on PATH.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof. `deferred` = not decided yet, under an open region.

Open region legend: `reversible-default-and-flag` = the build uses the stated default.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How each side gets its dependencies | Each checkout runs its own install with the package manager its base names. No `node_modules` is copied between sides. The package manager's own store makes the second install cheap. | user-answered | intent |
| D-2 | Network during the probe command | The command runs under a `sandbox-exec` profile that denies network where `sandbox-exec` exists. Elsewhere it runs unsandboxed, and the JSON says `"sandbox": "none"`. Installs keep the network. | user-answered | intent |
| D-3 | An npm base with no lockfile | `before` installs unpinned. `after` then installs from the `package-lock.json` that `before` generated, so both sides get the same versions. The JSON says `"lockfile": "generated"`. | user-answered | intent |
| D-4 | Where an overlay declares a build step | A new file `overlays/<upstream>/probe.json` with a `setup` command. vite's is `pnpm --filter ./packages/vite run build`. The step runs in each side after that side's install. `config.json` does not change. | user-answered | intent |
| D-5 | The overlay's `review-context.md` in the neutral checkouts | It stays. It describes the project, not the change, and plain's checkout carries it too. | user-answered | intent |
| D-6 | Probe files and the timeout | Probe files live in a `--dir` outside both checkouts, which the command reads as `$PROBE_DIR`. No checkout gets a new file. Each side times out at 120 s by default, and `--timeout` overrides it. | user-answered | intent |
| D-7 | When two outputs are equal | Each side's checkout root is replaced with `<ROOT>`, and timing lines are stripped. Then exit code, stdout and stderr are compared one by one. The raw outputs stay in the JSON. | user-answered | intent |
| D-8 | The command interface | `planted.py probe <case> --cmd '<bash string>' [--dir D] [--timeout S] [--dest D]` runs the string with `bash -c` in each side. It prints one JSON object with `verdict`, each side's `rc`, `out` and `err`, `sandbox`, `lockfile` and `reason`. It exits 0 on every verdict and non-zero only on a usage error. | user-answered | intent |
| D-9 | A case that cannot be built | Every failure outside the command is `UNPROVEN` with a `reason`: a failed fetch, a patch that does not apply, a missing package manager, or a failed install or setup. Only an unknown case or bad flags exit non-zero. | user-answered | intent |
| D-10 | Install flags and branch names | npm uses `ci` where a lockfile exists. yarn uses `--immutable`, and pnpm uses `--frozen-lockfile`. Lifecycle scripts stay on. The checkouts use branches `before` and `after`, and no name or subject carries the issue number. | user-answered | intent |
| D-11 | Whether `install_deps` changes | No. `build()` calls it for every arm's render, and AC-5 keeps those renders unchanged. The probe gets its own installer and cache directory. run: `grep -n 'install_deps(' planted.py` → 526 (definition) and 598 (in `build()`) | codebase-derived | fact |
| D-12 | The package manager per upstream | prettier is yarn@3.2.4, vite pnpm@9.12.3 and vue pnpm@9.6.0, from each base's `packageManager`. The other six name none and use npm. express and dayjs have no lockfile. run: `git -C bases/<u> show refs/bases/<base>:package.json \| jq -r .packageManager` → yarn@3.2.4, pnpm@9.12.3, pnpm@9.6.0, six none | codebase-derived | fact |
| D-13 | Where the plan file comes from | The patch adds it, so the neutral `after` drops `plan_rel(case)` after applying. run: `sed -n 385,386p planted.py` → `if plan_rel(case) not in touched: bad("the patch does not add the plan …")` | codebase-derived | fact |
| D-14 | The selftest's package managers | Parked under OR-1 (owner: the build, by its default) | deferred | open |
| D-15 | AC-5 test intent | `holds`. render-selftest and score-selftest keep passing unchanged. | user-answered | intent |
| D-16 | A bound on installs and setup steps | Each install and each `probe.json` setup step stops at 1800 s, and the probe reports `UNPROVEN` with a reason. Added in build: no row bounded the install, and a hung install would hang the probe. | user-delegated | intent |
| D-17 | Where the checkouts go without `--dest` | A new temporary directory, kept after the probe and named in the JSON as `dest`. A `--dest` that exists is a usage error. Added in build: D-8 names `--dest` but not its default. | user-delegated | intent |
| D-18 | What counts as a timing line, and how a setup step reaches pnpm or yarn | A line that starts with `Time`, `Duration`, `Start at`, `Done in` or `Finished in`, or ends with a duration in parentheses, is stripped. `yarn` and `pnpm` shims that call `corepack` sit first on PATH for the setup and the command. Added in build: D-7 and D-4 leave both open. | user-delegated | intent |

Options weighed:

- D-1: install per side, or install once per base and copy. The operator chose per side.
- D-2: `sandbox-exec` where present, no sandbox, or a sandbox required. The operator chose `sandbox-exec` where present.
- D-3: pin `after` to `before`'s generated lock, install each side unpinned, or refuse. The operator chose to pin.
- D-4: `overlays/<u>/probe.json`, or a key in `config.json`. The operator chose `probe.json`.
- D-5: keep `review-context.md`, or drop it. The operator chose to keep it.
- D-6: an outside `--dir` with 120 s, or files copied in with 300 s. The operator chose the outside `--dir`.
- D-7: normalize then compare, exit code only, or raw bytes. The operator chose to normalize.
- D-8: a shell string with JSON out, or argv with text out. The operator chose the shell string.
- D-9: `UNPROVEN` with a reason, or an error exit. The operator chose `UNPROVEN`.
- D-10: frozen lockfile with scripts on, or `--ignore-scripts` everywhere. The operator chose scripts on.

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Which package managers the model-free selftest fakes | reversible-default-and-flag |

- OR-1 default: the selftest puts fake `npm` and fake `corepack` scripts on PATH, as `render-selftest.sh` fakes npm. It covers the npm path, the corepack path and a `probe.json` setup step on a local fixture upstream. The intake chose it. Reversing it is a test edit.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5

AC-1: `probe` on a fixture case builds `before` and `after` with no plan file, record or ticket, and neither commit subject equals the case's `commit`
AC-2: the installer picks npm, yarn or pnpm from the base's `packageManager` and lockfile, runs a `probe.json` setup after the install, and a second probe on the same base reuses the cache
AC-3: `probe` prints `SAME` for equal normalized outputs, `DIFFERS` for unequal ones, and `UNPROVEN` with a reason for a failed install and for a timeout
AC-4: `probe-selftest.sh` drives the fixture to each of `DIFFERS`, `SAME` and `UNPROVEN` and checks AC-1's excluded files are absent
AC-5: holds — `render-selftest.sh` and `score-selftest.sh` keep passing, since the lane and plain renders, `ARMS` and `gate()` do not change

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | `planted.py probe` JSON output | decided (D-8) |
| S-2 | `probe` exit codes | decided (D-8) |
| S-3 | `UNPROVEN` reasons | decided (D-9) |
| S-4 | `overlays/<u>/probe.json` | decided (D-4) |
| S-5 | `probe-selftest.sh` output | decided (D-14) |
| S-6 | The lane and plain review prompts | out-of-scope — AC-5 keeps their renders unchanged. |
| S-7 | `planted/changelog.md` | out-of-scope — `probe` runs no model and records no row. |

## Checks

- `bash plugins/review-toolkit/evals/code-review-bench-eval/planted/probe-selftest.sh`
- `bash plugins/review-toolkit/evals/code-review-bench-eval/planted/render-selftest.sh`
- `bash plugins/review-toolkit/evals/code-review-bench-eval/planted/score-selftest.sh`
- `python3 plugins/review-toolkit/evals/code-review-bench-eval/planted/planted.py check`

## Intake steps

Requirements: the parent #1145 as filed. spec-reviewer found three blockers: no scorable ACs, the size, and open regions. The split answered all three.

Split: split into #1146 and #1147 (sequential). This receipt is for #1146.

Explore: done. Read build, install_deps, render and the selftest fakes. Probed npm, yarn and pnpm installs plus probes on the host.

Fan-out: skipped — by the operator at the intake notice: no reason given

Dup-scan: no candidates at or above threshold 12

Post-merge scan: no AC moved. PM-1 was already a post-merge check.

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Fan-out: skipped — by the operator at the intake notice: no reason given

</details>
