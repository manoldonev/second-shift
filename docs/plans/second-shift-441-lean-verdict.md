# lean review verdict — #441

verdict=needs-work
run_id: review-441-2
session_id: 96c615cb-ed69-4722-b0f6-3de7174a40d3
rounds: 2
pr: #455
reviewed_head: 01d0544ee9f0168e20414578376f9b3ad8cc1091
reviewed_patch_id: 50ae0580a67e913ef7ba7dea5e60990b1c9c725f
inherited_patch_id: deac7154105db3c6d6a77d81892439581e97de03
inherited_from_verdict: 08dba6f8fbdcb2de23cc678a027b8af885e42d1f
fidelity: not-applicable
model: unknown

Round 2 review of PR #455 (issue #441) over `08dba6f..HEAD` — the range `lean-gate delta`
printed, inheriting the coverage of patch `deac7154105d` (round 1's record). Round 1's
findings were read first. Panel: security, complexity, maintainability, test-coverage,
scope-completeness. a11y + design-fidelity not routed — no changed path matched
`stageParams.webComponentGlobs` (`apps/web/**/*.{tsx,jsx}`). The spec carries no `## Design`
section, so the design arm scores `not-applicable`.

Verdict: **needs-work** — one blocker. Round 1's blocker and all three warnings are genuinely
closed, every new assertion was probed live, and the delta is a real improvement over round 1.
The blocker is a defect the fix authored while enumerating the very taxonomy it was narrowing.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 checker contract | satisfied | Envelope re-verified live against this repo's own committed config: `findings[]` + `notEvaluated[]`, exit 0 with findings present. Exit-3 cases (missing config, non-JSON, no arguments) green in-suite. `shellcheck -e SC1091,SC2015,SC2181` clean on all three changed scripts. Round 1's open bash-3.2 question is now settled by evidence rather than inspection: `selftests (macos, bash 3.2)` passes on this head. |
| AC-2 per-key table | satisfied | B1 closed. `t2 formatGlob: hand-set value matching nothing still fires` exists, and it is live: with the formatGlob jq expr mutated to never read a configured value (P1), it is the **only** red in the suite. All nine enumerated cases now present. |
| AC-3 finding text + counting | satisfied | Unchanged in the delta. The new case is the pairing AC-3 point 4 was written to protect: it asserts both counts out of the slash-free crossing branch (configured `*.{rs,toml}` → 0, alternative `*.{ts,tsx,js,jsx,json,md}` → 1). Under `[^/]*` the alternative would score 0 and the proposal would offer a value matching nothing either — which is what makes the assertion load-bearing rather than formal. |
| AC-4 inconsistent config | satisfied | Unchanged in the delta; suite green; live run on this repo's config still emits `T4.mutation-plumbing.second-shift`. |
| AC-5 command reality | **unsatisfied** | See B1. |
| AC-6 `grillWaivers` | satisfied | Unchanged in the delta; round 1's verification stands and is inherited. |
| AC-7 onboard | satisfied | W3 closed — the blank line before "**Before you render the screen, GRILL the draft.**" is present, so the step that gates the accept screen is its own paragraph. The one-batch rule and the not-a-wizard framing remain unamended. |
| AC-8 doctor | satisfied | W2 closed. Both degrade branches are now pinned: `grill-degraded-rc` (checker exits 9) and `grill-degraded-missing`, each asserted to `warn` at exit code 0. Both are live — silencing either branch's `warn` (P5/P6) reds exactly its own scenario and nothing else. Blast radius on this repo's own config is unchanged from round 1: the same three findings (`T2.webComponentGlobs`, `T2.visualCaptureTriggerGlobs`, `T4.mutation-plumbing.second-shift`), `formatGlob` still correctly silent. |
| AC-9 tests | satisfied (see W2) | The amended AC's own additions are met: one case per narrowing (`prettier -w .` and `vitest --run`, each asserted silent) plus `tsc -w` asserted to still fire, so the narrowing qualified the rule rather than deleting it. All three are live — P2 (put `prettier` back in the allowlist), P3 (break the `--run` comparison) and P4 (drop `tsc` from the allowlist) each red exactly their own case. `config-grill-selftest.sh` and `doctor-selftest.sh` both all-green here under `env -u CLAUDE_CODE_SESSION_ID`. |
| AC-10 docs | satisfied | Unchanged in the delta; inherited from round 1. |

## Blocker

**B1 — AC-5: the `-w` allowlist contradicts the rule it enumerates. `jest` does not define
`-w` as watch, so `jest -w 4` is a doctor `FAIL` on a valid config.**

AC-5's amended bullet reads "a standalone `-w` flag **whose first token is a runner that
defines `-w` as watch**", then enumerates fourteen runners. `jest` is one of them, and the
predicate is false for it. Verified against the installed Jest CLI's own source, not from
memory — `jest-cli/build/args.js` declares `maxWorkers: { alias: 'w' }`, while `watch` and
`watchAll` carry **no** alias at all; Jest's own error string reads *"The --maxWorkers (-w)
option requires a number or string"*. `is_watcher()` implements the enumeration, so it
implements the wrong half: the list is an instantiation of the rule, and one member fails the
rule it instantiates.

Measured on the real checker at this head (a scratch repo, `npm run <script>` per shape):

```
  WATCHER  jest -w 4
  silent   jest --maxWorkers=2
```

The same Jest invocation, spelled two ways, gets opposite verdicts — and the wrong one is the
`FAIL` direction. `"test": "jest -w 2"` is an ordinary script; under this diff its only escape
is a `grillWaivers` entry excusing a non-problem, which is precisely the "declare, because
there is nothing to adopt" outcome the amendment paragraph was written to prevent.

Why this is a blocker where round 1 scored the same class a warning: round 1's over-fire was an
unexamined blanket rule and the spec was silent on which runners qualify, so it was a defect in
approved wording. This round **enumerated** the runners, wrote the enumeration into the spec
that is the definition of done, and got one entry wrong while auditing exactly this question —
and AC-5 states in its own paragraph that a false FAIL on a valid config is the worse error,
with over-firing explicitly **not** deferred to OR-1 ("Under-firing remains OR-1's subject").
Found independently by two reviewers on separate dispatches (confidence 90 and 88) and
confirmed here against Jest's source.

Remedy is one token in two files — drop `jest` from the allowlist in `config-grill.sh` and from
the AC-5 bullet — plus one negative case (`jest -w 4` asserted silent) alongside the existing
`prettier -w .` one. `jest --watch` / `jest --watchAll` keep firing through the `--watch` rule,
which is unaffected; the coverage that matters for Jest is not lost.

I checked the other thirteen entries against the same predicate. `vitest`, `vite` (`vite build
-w`), `tsc`, `tsup`, `webpack`, `rollup`, `mocha`, `ava`, `sass` and `nodemon` all define `-w`
as watch. `esbuild`, `parcel` and `karma` appear to define no `-w` at all, which makes them
**inert** rather than wrong — a false FAIL needs a script that already would not run — so they
are not part of this blocker. That check was reasoning plus the corpus probe below, not source
inspection; only the `jest` entry was verified from source, which is the one that changes the
verdict.

## Warnings

**W1 — the amendment's "nothing the original wording caught is lost" is measurably false.**
That sentence is the argument for the amendment being a narrowing rather than a retrofit, so it
should be accurate. Running the checker at `08dba6f` and at `01d0544` over the same shapes,
two more stopped firing besides the two intended:

- `rm -rf dist && tsc -w` — fired before, silent now. Gating `-w` on the **first** token means
  any compound body with a leading non-runner escapes the rule. `--watch` / `--watchAll` still
  fire anywhere, so only the short form regressed.
- `tailwindcss -i a.css -o b.css -w` — fired before, silent now; `tailwindcss` is not in the
  allowlist and its `-w` is a genuine watch flag.

Both are under-firing, which is OR-1's declared subject and the cheaper error by AC-5's own
principle — so this does not block. What is worth fixing is the claim: state the measured loss
(compound bodies, and watch-flag runners outside the list) rather than asserting there was
none.

**W2 — the `-w` allowlist is now the taxonomy's largest untested surface: fourteen members,
one positive case.** `tsc -w` is the only member with a fixture; `prettier -w .` is a negative
for a non-member. Thirteen members have no case in either direction, which is exactly how B1
shipped — the entry was written, reviewed as prose, and never executed. AC-9 requires "every
entry of the watcher taxonomy", and I read *entry* as the bullet (as round 1 did), so AC-9
scores satisfied rather than manufacturing a second blocker. But the reading that would have
caught B1 is per-runner, and the cheap version of it is one table-driven case per allowlist
member — the shapes are one line each.

## Not blockers

- **`vite --run` is silent.** The `--run` exclusion sits on the shared `vitest|vite` branch
  though the spec justifies it for vitest only; `vite` has no `--run` flag, so `vite --run`
  would be a dev server that never exits. Nobody writes that shape, and the AC's principle
  makes a missed warning the cheaper error. Noted for OR-1, not for this round.
- **The spec amendment is narrowing-only.** Diffed for removals: the three deleted lines are
  line-continuation artifacts, no prose was dropped. `--watch=true` moving into the spec text
  is the spec catching up to code that already shipped at round 1 and that round 1 approved —
  a documentation correction, not a behavior change.
- **`pr-gates` red is the designed pre-verdict state**, and the failure log confirms it: the
  only failing arms are `lean-evidence` / `lean-chain` reporting `verdict=needs-work` from
  round 1's committed record. `lint-and-selftests`, `mutation-sweep-pr` and
  `selftests (macos, bash 3.2)` all pass on this head.
- **`scope-completeness-reviewer` (round-1 dispatch) flagged AC-5's narrowing as lacking an
  amendment to the issue's AC text.** Dismissed: it read GitHub issue #441, and under the lean
  lane the **committed spec** is the definition of done. That spec *is* amended, in the same
  commit, with the reasoning stated. Its verdict on the ACs themselves — all of AC-1..AC-9
  implemented in-diff — agrees with the table above.
- Security and complexity returned clean on both dispatches. Security's suppressed items (the
  `SECOND_SHIFT_CONFIG_GRILL` exec seam, which pre-dates this delta; word-splitting a manifest
  body into a `case` with no expansion sink) sit below threshold on a repo-local operator tool
  — agreed.

## Coverage note

The first fan-out went out with a base SHA I had not resolved, so its range did not exist; the
panel was re-dispatched against a verified `08dba6f8...01d0544e`. On the re-dispatch
`test-coverage-reviewer` went **dark** (`turn-budget`, dark after its automatic retry). It had
returned usable output on the first dispatch — where it raised B1 first, at confidence 90 —
and B1 was independently re-found by `maintainability-reviewer` on the clean range at
confidence 88, then confirmed here against Jest's source. So the blocker does not rest on the
broken-range dispatch. What is genuinely thinner this round is the *systematic* coverage read
of the new fixtures; W2 is my own, and I probed the six new assertions directly rather than
inferring their strength.

## Probes run

Each new assertion in the delta was mutated and scored on the **full** case label, with the
whole red list printed so a mis-keyed lookup could not read as a false survivor. All six killed
by exactly their own target and nothing else:

| Probe | Mutant | Target assertion |
| --- | --- | --- |
| P1 | formatGlob's jq expr never reads a configured value | `t2 formatGlob: hand-set value matching nothing still fires` |
| P2 | put `prettier` back in the `-w` allowlist | `t5 non-watcher: prettier -w (-w is --write, not watch)` |
| P3 | break the `--run` token comparison | `t5 non-watcher: vitest --run (flag spelling of the run subcommand)` |
| P4 | drop `tsc` from the `-w` allowlist | `t5 watcher: -w on a runner that defines it as watch (tsc)` |
| P5 | silence doctor's checker-exits-non-zero `warn` | `grill-degraded-rc` |
| P6 | silence doctor's checker-absent `warn` | `grill-degraded-missing` |

Beyond the fixtures, the taxonomy was run against a scratch repo of 32 real script bodies —
which is what produced B1's `jest -w 4` / `jest --maxWorkers=2` split and W1's two lost shapes.
A fixture suite cannot give that evidence.

## Strengths

- The round-1 warnings were not merely acknowledged, they were closed with the reasoning
  written where the next reader hits it: the `is_watcher()` comment argues the false-FAIL
  principle rather than restating the rule, and both selftest comments say what the case would
  catch rather than what it does.
- The `tsc -w` case is the right instinct — a narrowing that deletes its rule instead of
  qualifying it is the classic silent regression, and this suite asserts the rule still fires.
  B1 is a wrong list member, not a wrong mechanism.
- The two doctor degrade cases are worth more than their size: both are `warn`, so the failure
  mode is a broken integration reading green, and the `$9` env-override seam was added so that
  every pre-existing call site passing empty is indistinguishable from unset — none of them
  changed.
- The spec amendment argues its own legitimacy (narrowing vs retrofit) instead of quietly
  editing the AC. That framing is what made this round's scoring mechanical, and it is why W1
  is a correction to one sentence rather than a challenge to the whole amendment.
