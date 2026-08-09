# lean review verdict — #441

verdict=needs-work
run_id: review-441-1
session_id: 1d4f35e9-6993-4458-87ca-eb4409f0668c
rounds: 1
pr: #455
reviewed_head: 630082c95a26e3190425ad8e1ba11e0857443124
reviewed_patch_id: deac7154105db3c6d6a77d81892439581e97de03
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

Round 1 review of PR #455 (issue #441) over the full branch diff `9c50602..HEAD` — the range
`lean-gate delta` printed, with nothing verifiable to inherit. Panel: security, performance,
maintainability, complexity, test-coverage, scope-completeness (all six returned; none dark).
a11y + design-fidelity not routed — no changed path matched `stageParams.webComponentGlobs`
(`apps/web/**/*.{tsx,jsx}`). The spec carries no `## Design` section, so the design arm scores
`not-applicable`.

Verdict: **needs-work** — one AC is unmet by its letter. Everything else in the diff is sound,
and the mechanism was verified against a real config, not only against fixtures.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 checker contract | satisfied | `config-grill.sh <root> [<config>]`, default config path, one JSON doc with `findings[]`/`notEvaluated[]`; exit 0 with findings present, exit 3 on missing/non-JSON config and on no arguments (all four asserted and re-run green here). Multi-repo scoping evaluates only the repo whose `topology.repos.<id>.path` resolves to the handed root and emits one `notEvaluated` per sibling. Read-only, no network; shellcheck clean; no bash-4 idiom (no `globstar`, no assoc arrays, `${arr[@]+…}` used throughout). |
| AC-2 per-key table | satisfied | Three active rows implemented; all four dropped ids (`planFilePattern`, `plansDir`, `pipelineStateDir`, `inertPattern`) asserted to emit nothing. Both halves — absent-key-default and hand-set-value — fire through the same `t2_key` predicate. |
| AC-3 finding text + counting | satisfied | All three restated defaults verified **verbatim** against their runtime sources: `apps/web/**/*.{tsx,jsx}` vs `review-lead/SKILL.md:68` + `stages/8-code-review.md:65`; `*.{ts,tsx,js,json,md}` vs `verifyctl.sh:236`; the four `triggerGlobs` literals vs `stages/6-verify.md:182`. That was the one thing the DROPPED lockstep entry leaves unguarded, so it was checked by hand. Detected-alternative and no-alternative branches both present; the slash-free `formatGlob` shape correctly crosses separators (`src/deep/a.ts` stays silent). |
| AC-4 inconsistent config | satisfied | All three checks present. `gates.mutation` follows runtime semantics — `absent` is not `false` — and the finding text names the state found; `false` is silent. |
| AC-5 command reality | satisfied (see W1) | Every slot inspected including `lanes[]`/`extraLanes[]`; watcher test runs on the manifest script **body**; resolution table implemented row-for-row, including the ambiguous `<pm> <name>` and no-manifest non-evaluations. Implemented exactly as specified — the over-firing in W1 is a defect in the specified taxonomy, not a deviation from it. |
| AC-6 `grillWaivers` | satisfied | Schema `additionalProperties: {type: string, minLength: 1}`; `config-lint` allowlist + non-object and empty-reason rejections, all three fixtures present; `configVersion` stays 2; ids carry the repo id and a repo-less id is asserted **not** to silence a per-repo check. `check-config-shadowing.sh` run here: clean, so the stated exception holds. |
| AC-7 onboard | satisfied (see W3) | SKILL.md carries the grill step before the accept-or-edit screen, the blocking-line rendering, the re-run-per-iteration accept predicate, the informational `notEvaluated` rendering, and the never-author-a-reason rule. The one-batch rule and the not-a-wizard framing are unamended. |
| AC-8 doctor | satisfied | Verified live, not only by fixture: run against this repo's own committed config it emits 3 findings and would move doctor's exit code. `grill-finding` (exit 1), `grill-waived` (exit 0) and `grill-noteval` (exit 0) scenarios all green. Resolution is within doctor's own plugin with a `SECOND_SHIFT_CONFIG_GRILL` override. |
| AC-9 tests | **unsatisfied** | See B1. |
| AC-10 docs | satisfied | `docs/config-schema.md` group-table row present; `docs/extending.md` names the grill in the shadowing section as the mirror-image rot. |

## Blocker

**B1 — AC-9: `formatGlob`'s hand-set-value-matches-zero case is absent.**
`config-grill-selftest.sh` covers, for `webComponentGlobs` and `visualCapture.triggerGlobs`,
all three enumerated cases (absent-default-zero, hand-set-zero, matching-silent). For
`formatGlob` it covers only two — `t2-format-go` (absent default, zero match) and
`t2-format-nested` (absent default, matches → silent). There is no case setting
`stageParams.formatGlob` to a value that matches nothing. AC-9's first bullet requires
"every **active** row of the AC-2 table — absent-key-default-matches-zero **and**
hand-set-value-matches-zero, plus a matching case that emits no finding". Eight of the nine
enumerated cases exist; this is the ninth.

Not purely formal: `formatGlob` is the only slash-free row, and its transliteration takes the
other branch (`*` → `.*`, not `[^/]*`). The configured-value path has never been exercised
through that branch — the combination is what is untested, and it is precisely the pairing
AC-3 point 4 was written to protect. The fix is a fixture and two assertions alongside the
existing `t2-format-*` cases.

## Warnings

**W1 — the watcher taxonomy over-fires on two mainstream script bodies, and each is a doctor
`FAIL`.** Probed directly against `config-grill.sh` on a scratch repo:

- `"format": "prettier -w ."` → `T5.watcher.app.format`. Prettier's `-w` is `--write`, not a
  watch flag; the script exits.
- `"test": "vitest --run"` → `T5.watcher.app.test`. `--run` is the flag spelling of the
  `run` subcommand; it exits. `is_watcher` only inspects `${t[1]}` against the exiting-subcommand
  list, so the flag form falls through to the default watcher branch.

Both are AC-5-conformant — the spec says "a standalone `-w` flag anywhere" and "no exiting
subcommand" in those words, so this is a defect in the approved taxonomy rather than a
deviation from it, and is scored as such. But it inverts the principle AC-5 states in its own
paragraph: *a false FAIL on a valid config is worse than a missed warning*. That principle is
written against the missing-script half; the exposure is now on the watcher half, where the
only escape is a `grillWaivers` entry excusing a non-problem — which weakens AC-8's
"a clean report stays reachable" from *adopt or declare* to *declare, because there is nothing
to adopt*. Cheap narrowings: gate `-w` on a known test/build-runner first token, and treat
`--run` as an exiting form for `vitest`. Worth folding in with B1 rather than deferring to
OR-1, since OR-1 is scoped to taxonomy *completeness* (under-firing), not over-firing.

**W2 — doctor's two grill degrade branches are unexercised** (`doctor.sh:371` "could not run"
and `:388` "not found next to doctor"). All three new scenarios run the real checker
successfully. Both branches are `warn`, so neither can move the exit code — the risk is a
broken integration reading as green rather than a wrong verdict. Confidence 82
(test-coverage-reviewer, confirmed against the source).

**W3 — `plugins/second-shift/skills/onboard/SKILL.md`: no blank line before the new
"**Before you render the screen, GRILL the draft.**" paragraph**, so it runs on from the
preceding `lanes`-guidance sentence as one block. Cosmetic for a file read as raw text, but it
visually buries the step that gates the accept screen.

## Not blockers

- Doctor on this repo's own config now exits non-zero (3 findings:
  `T2.webComponentGlobs`, `T2.visualCaptureTriggerGlobs`, `T4.mutation-plumbing.second-shift`).
  This is the blast radius the PR body states, the config is gitignored so it cannot be fixed
  in this diff, and no CI lane invokes `doctor.sh` — verified: the only repo references are
  `doctor-selftest.sh` and the consumer template's ported copy. `formatGlob` correctly stays
  silent here, which is the slash-free rule earning its keep.
- Security, performance, maintainability, complexity all returned clean with no findings.
  Security's three suppressed items (config-derived globs into a `grep -E` alternation; the
  `SECOND_SHIFT_CONFIG_GRILL` override; config values interpolated into finding text) all sit
  below threshold on a repo-local operator tool with no trust boundary crossed — agreed.
- `scripts/check-frozen-files.sh` and `scripts/check-changelog-trailer.sh` both clean locally;
  `lint-and-selftests` green in CI. `pr-gates` is red on the lean-chain arm, which is the
  designed pre-verdict state, not a finding. `selftests (macos, bash 3.2)` was still queued at
  review time — the bash-3.2 claim rests on inspection plus shellcheck here, and that job is
  the one that settles it.

## Strengths

- The negative half is written everywhere it matters: `t2-web-match`, the `mut-false`
  off-switch, `vitest run`/`eslint`/`vite build`, and the "repo-less waiver id does **not**
  silence a per-repo check" case. A checker that only ever fires would have passed a suite
  missing any of them.
- AC-3's slash-free rule is the sharpest call in the diff: transliterating `*` to `[^/]*` for
  `formatGlob` would have fired a zero-match finding on essentially every consumer, and
  `t2-format-nested` pins the reasoning rather than the outcome.
- The `notEvaluated[]` / `findings[]` split is carried through both callers — a not-evaluated
  notice has no proposal, cannot be waived, and would deadlock onboard's accept predicate if it
  rode in `findings[]`. `doctor-selftest`'s `grill-noteval` scenario proves the exit code stays
  0, and the T5 no-manifest case proves the notice never leaks into `findings[]`.
- The lockstep DROPPED entry argues the case rather than asserting it — seven restatement sites
  across two plugins, why a file-to-file pair cannot express one-canonical-to-seven, and what is
  guarded instead.
