# lean review verdict — #473

verdict=approve
run_id: review-473-1
session_id: aa85ad77-bfbb-4507-8a61-37dd8afea103
rounds: 1
pr: #479
reviewed_head: 328d4f4f13a91d7ea25ca38b3944e389fb32a0be
reviewed_patch_id: 99d275e6908ee57b775cf3d104e9bf2ffcb441b3
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

## Review Summary

Round 1, full branch range `1413ca7..HEAD` (nothing to inherit). The change lands the shared
`scope-shadows.sh` helper and makes all three consumer surfaces scope-aware. Every acceptance
criterion is satisfied on the diff. I probed all 12 of the load-bearing new assertions myself in a
detached worktree and **all 12 killed their mutant** — the AC-1…AC-6 guards are real, not
presence checks. The one that matters most, AC-4, kills as advertised: neutering the
project-over-user preference reds `shadowed-verdict` (`rc=0 want 1`), so the fixture's
`lastUpdated` ordering really does discriminate the retired `sort_by(.lastUpdated) | last`
resolver from the new one.

Three warnings, all in the WARN-emission path this PR added, and all guard-strength rather than
behavior: two mutants I confirmed **survive** the suite, and one new production block no suite
executes. None unmets an AC — AC-10 asks for scenarios over AC-3…AC-6 on a both-records fixture,
and those exist and are effective — so they are follow-up debt, not blockers.

CI: `lint-and-selftests`, `selftests (macos, bash 3.2)` and `mutation-sweep-pr` all pass on the
reviewed head. `pr-gates` fails on exactly one arm — `no committed verdict record (a file named
*-473-lean-verdict.md)` — which is the expected pre-review state and is what this record closes.
The mutation sweep computed 22 real verdicts (not a deferred no-op lane): `scope-shadows.sh`
7 applied / 7 killed / 0 survived; `doctor.sh` 13 / 6 / 7, with all 7 survivors matching existing
`tools/mutation-baseline.tsv` rows.

Panel: 7/7 reviewers returned, none dark. a11y + design-fidelity were not routed — no changed
path matched `stageParams.webComponentGlobs` (`apps/web/**/*.{tsx,jsx}`), which is correct for a
shell/markdown diff.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 shared helper (rows, exit status, no lockfile, injection, positional filter) | **satisfied** | 18-case suite green; probes P8 (exit status pinned to 0), P9 (projectPath scoping dropped), P10 (injection branch unconditional), P11 (usage rc 2→1) all killed |
| AC-2 only user-shadows-project; `local` exempt both directions | **satisfied** | probe P7 (local counted as serving record) killed `local is not counted as the serving record`; the paired `local does not shadow a project record` case covers the other direction |
| AC-3 doctor reports the shadowed record (WARN, both versions, uninstall cmd, inline caveat) | **satisfied** | probes P2 (severity `warn`→`bad`) killed `shadowed-warn-only`, P3 (caveat recovery removed) killed `shadowed-caveat`, P6b (helper never invoked) killed `shadowed-warn`. Guard gaps on the message's `$suv` half and the row filter → W1/W3 |
| AC-4 verdict describes the project record | **satisfied** | probe P1 (project-preference removed → back to pure recency) killed `shadowed-verdict` |
| AC-5 `behind` under a user-scope record takes `update` | **satisfied** | probe P4 (`update`→`install --scope project`) killed `user-behind` |
| AC-6 `ahead` under a user-scope record names the registration ref, no reinstall | **satisfied** | probes P5 (`Do not reinstall` removed) killed `user-ahead-no-reinstall`, P6 (registration lever removed) killed `user-ahead` |
| AC-7 bootstrap surfaces untouched | **satisfied** | none of `plugins/second-shift/templates/consumer/second-shift-doctor.sh`, `docs/team-rollout.md`, `docs/onboarding.md`, the onboard CONTRIBUTING snippet appear in the diff; doctor.sh's two not-installed-anywhere branches are unmodified |
| AC-8 `local-dev-refresh` Step 4 declines on a shadowed record, gated on exit status | **satisfied** | SKILL.md Step 4 reads the helper's exit status as the precondition, prints the report + uninstall + `git checkout` recovery, and keeps realignment only on non-zero. Prose-only by nature — no guard, per the repo's no-prose-presence-guards rule |
| AC-9 `onboard` Step 8 item 2 explains the user-scope record | **satisfied** | prints the spec's exact string in place of the install line for `user-served`/`shadowed`; explicitly not a silent skip |
| AC-10 guards | **satisfied** | new same-named `scope-shadows-selftest.sh` (18 cases) covers AC-1/AC-2; `doctor-selftest.sh` gains 8 scenarios over 4 new fixtures for AC-3…AC-6, incl. the both-records fixture whose `lastUpdated` ordering makes the retired resolver grade the other record (P1 confirms). Strength gaps → W1/W2/W3 |
| AC-11 doc | **satisfied** | `doctor/SKILL.md` description gains "project-scope records a user-scope one makes redundant"; `local-dev-refresh/SKILL.md` description gains "reporting rather than refreshing the ones a user-scope record already makes redundant" |

No blockers.

## Findings

| # | Severity | Location | Finding |
| --- | --- | --- | --- |
| W1 | Warning | `plugins/second-shift/skills/doctor/tools/doctor.sh:268` | The `[[ "$kind" == "shadowed" ]] \|\| continue` row filter has no distinguishing assertion. **Confirmed by probe**: replacing the guard with `:` leaves `doctor-selftest.sh` fully green. Every fixture carries a lone user-scope `second-shift@second-shift` record, so the helper emits a `user-served` row on every scenario; without the filter each of those runs additionally prints a bogus `the project-scope record (-) is redundant` WARN. Nothing catches it — `warn()` never increments `$FAILS`, and `scenario()` has no must-be-absent argument (only `report()` does). The shipped behavior is correct; the guard holding it is untested. Worth closing because the automated sweep structurally cannot catch it either: `tools/mutation-baseline.tsv` already carries doctor.sh's full per-class quota (`logic::1/2`, `detector::1/2`, `default::1/2`), so a new logic-class survivor in this file is permanently masked. Remedy: give `scenario()` the must-be-absent parameter `report()` already has, and assert the redundancy WARN is absent from the `green` scenario. |
| W2 | Warning | `plugins/second-shift/skills/doctor/tools/doctor.sh:161-168` | The new shared-snapshot block (`mktemp` → write `$PLUGLIST` → `export DOCTOR_PLUGIN_LIST_FILE` + EXIT trap) is never executed by any suite: every `scenario()`/`report()` call and every ad-hoc block in `doctor-selftest.sh` pre-sets `DOCTOR_PLUGIN_LIST_FILE`, so the branch is only ever taken in production. A dropped `export` degrades safely (the child falls back to its own `claude plugin list --json`), but a corrupted write — e.g. `[]` reaching the temp file — would silently empty the child's view and disable the whole redundant-record feature with zero selftest signal. `scope-shadows-selftest.sh`'s own PATH-shim `no injection` case proves the technique is cheap and available here. |
| W3 | Warning | `plugins/second-shift/skills/doctor/tools/doctor.sh:269` | The WARN interpolates both `$spv` and `$suv`, but only the `$spv`-anchored prefix is pinned. **Confirmed by probe**: substituting `$spv` for `$suv` in the `a user-scope record ($suv) already serves` clause leaves the suite green — `shadowed-warn` asserts only the project-version prefix, and `shadowed-warn-only` uses the aligned fixture where both versions are `2.1.0`, so neither can tell them apart. AC-3 asks the WARN to name **both** versions; half of that is currently unguarded. Impact is informational text only (the `Fix:` command does not reference `$suv`). |
| S1 | Suggestion | `plugins/second-shift/skills/doctor/tools/doctor.sh:210-212` | `RESOLVE_RECORD` prefers a project record over a `local` one, then falls back to recency across `{project@root, user, local}`. This PR's own `scope-shadows-selftest.sh` frames `local` as the sanctioned per-developer override that outranks a project enable (`docs/team-rollout.md:60`), so project-over-local reads backwards against the same document OR-1 cites. Outside the AC set and not a regression — the retired resolver had no scope precedence at all — but the two halves of this PR describe `local`'s standing differently, and it is worth settling alongside OR-2. |

## Suppressed (below confidence threshold)

- `doctor.sh:217` (conf 75) — `SECOND_SHIFT_SCOPE_SHADOWS` is an unexercised override knob: the sibling is already resolved correctly via `$(dirname "${BASH_SOURCE[0]}")`, and unlike the cross-plugin `SECOND_SHIFT_REVIEW_TOOLKIT_ROOT` it models, both files ship in the same plugin directory, so the path cannot vary by layout. No selftest sets it.
- `scope-shadows.sh:76` (conf 60) — redundancy is decided by scope coexistence alone, without checking that the user-scope record actually satisfies the lockfile version. Deliberate per D-1 (the helper reads no lockfile) and AC-1 defines the classification exactly this way; the WARN names both versions so the operator can judge.
- `onboard/SKILL.md:389` (conf 55) — the CONTRIBUTING snippet keeps an unconditional `--scope project` install. AC-7 blesses this explicitly.
- `doctor.sh:165` (conf 40) / `doctor.sh:216` (conf 35) — snapshot export reaches child processes; `SECOND_SHIFT_SCOPE_SHADOWS` selects a bash-executed path. Non-sensitive install metadata and a documented test seam crossing no privilege boundary.
- `doctor.sh:211` (conf 80) — the same-scope duplicate-record tie-break (`sort_by(.lastUpdated) | last`) is untested; reaching it requires malformed `claude plugin list --json` output, and the code's own comment scopes it that way.

## Verdicts

| Reviewer | Verdict | Findings | Confidence Range |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 1 | 75 |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |
| Unit Test Mutation | Fail | 4 | 80–88 |

**Ready to merge?** Yes

**Reasoning:** All 11 ACs are satisfied on the diff and every AC-bearing assertion killed its
probe. The mutation reviewer's request-changes is guard-strength debt in newly added code — two
confirmed survivors and one unexercised block — not an unmet AC and not a behavior defect, so it
routes to follow-up rather than blocking a round.

## Strengths

- **The exit status as the contract.** Making Step 4's precondition a machine-checkable rc rather
  than a sentence in a skill file is the right call, and `scope-shadows-selftest.sh` asserts rows
  **and** status on every case — so a helper that always exited 0 (and left Step 4 declining on
  everything) could not pass. Probe P8 confirms that assertion bites.
- **The AC-4 fixture is built to discriminate, not to pass.** `plugin-list-shadowed.json` sets the
  user record as the *newer* one specifically so the retired recency resolver would grade the wrong
  record. That is the difference between a scenario and a decoration, and P1 proves it.
- **`shadowed-warn-only` isolates severity properly** — both records aligned, so the WARN has no
  drift FAIL to hide behind and the exit code must stay 0. Severity claims are usually asserted by
  assumption; this one is pinned.
- **The un-injected leg is executed, not inferred.** The PATH shim for `claude plugin list --json`
  covers the branch every real caller takes, and the comment explains why an unset variable under
  `set -u` would otherwise be indistinguishable from a legitimate empty answer.
- **The hang found and fixed mid-run** (`shift 2` reachable with one argument left) is exactly what
  the sweep is for, and the commit is honest that the two forms are externally identical — so no
  test can distinguish them and none was invented to look thorough.
