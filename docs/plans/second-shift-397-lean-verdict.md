# lean review verdict — #397

verdict=approve
run_id: review-397-1
session_id: 0713f1ae-de1d-491d-9148-ef612d16614f
rounds: 1
pr: #488
reviewed_head: 3f185e3ac0daea096d629b8c13f3912417783318
reviewed_patch_id: c037a35d2b4a8e642fcf90915de5fae48c05a545
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 1 — root of the chain, so the range read was the whole branch diff (`origin/main...HEAD`, 45 files, 3 commits). Panel: security, performance, complexity, maintainability, test-coverage, scope-completeness — six selected, six returned, none dark. a11y + design-fidelity were not routed: no changed path is a web component and the repo declares no `design.provider`.

**Verdict: approve.** No blocker. Six warnings, all in the test-assertion and comment layer, none reaching behavior.

## What was verified directly rather than taken from the PR body

- **The rename is a rename.** Byte-compared each of the nine moved files against its `origin/main` original: `branch-prefix.sh`, `branch-prefix-selftest.sh`, `lean-evidence.sh`, `lean-evidence-selftest.sh`, `lean-reconcile.sh`, `lean-reconcile-selftest.sh` are **0 changed lines**; `lean-gate.sh` is 4 lines and `lean-gate-selftest.sh` 2, every one of them the skill's own name in prose.
- **The two marker strings that DO change are cosmetic, and that was the one thing worth chasing.** `lean-gate.sh:1259` and `:1440` rewrite the bot claim comment and the PR marker body from `` `/dev-pipeline:run-lean` `` to `` `/dev-pipeline:build-lean` ``. A writer-side token change with a reader that still greps the old spelling is exactly how a merge boundary goes quietly vacuous. It does not happen here: `lean-evidence.sh` keys both arms on the HTML-comment tags `lean-pr-marker` / `lean-claimed` (`:349`, `:372` — the first inside a `LOCKSTEP-BEGIN` block for this precise failure mode), never on the prose. A repo-wide grep finds no reader of either literal.
- **The suite kills.** Six independent probes of `orchestrate-lean.sh`, each `cmp`-checked to have actually applied and `bash -n`-checked to still parse; each red **exactly one** case, the one that claims to guard it:

  | Probe | Case that red |
  | --- | --- |
  | `${GH:-gh}` → `${GH:-ghXX}` | (m4) shipped tracker-CLI default |
  | a `gh issue comment` added to `resolve_pr` | (f) zero-write posture |
  | `-p` dropped from the spawn argv | (e1) fresh-context spawn flags |
  | the `round > MAX_ROUNDS` bound removed | (i2) independent round bound |
  | `RUN_ID` no longer scrubbed | (d1) env hygiene |
  | preflight made first-failure-abort | (g2) report-every-probe |

  Suite green under `env -u CLAUDE_CODE_SESSION_ID -u RUN_ID -u LEAN_RUN_MODEL`: 27 assertions, 0 failures.
- **Repo gates, re-run on this checkout:** `check-lockstep-pairs.sh` 28 pairs / 0 failed · `capability-parity-check.sh` OK, 37 rows · `check-frozen-files.sh origin/main` clean · `check-changelog-trailer.sh origin/main` OK · `shellcheck -e SC1091,SC2015,SC2181` over every changed `*.sh` clean.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `build-lean/` holds exactly the nine payload files; none remains under `run-lean/`. |
| AC-2 | satisfied | Byte-compare above; suite green. |
| AC-3 | satisfied | `git grep 'skills/run-lean/(lean-\|branch-prefix)'` over the live tree (excluding `CHANGELOG.md`, `docs/plans/`, `.claude/pipeline-state/`) returns nothing. The three AC-3 files carrying no hunk — `docs/config-schema.md`, `run/SKILL.md`, `onboard/SKILL.md` — were each read: every `run-lean` in them is the **command** users type, which the split preserves. Correctly untouched, not missed. |
| AC-4 | satisfied | `mutation-baseline.tsv` 12 build-lean rows + 2 new run-lean rows for the orchestrator; `mutation-catalog.tsv` 9; `lockstep-manifest.tsv` 9; `prose-budget.baseline.tsv` 1 moved + 1 new. Lockstep and mutation gates green. |
| AC-5 | satisfied | `second-shift-ci-check.sh:163` fetches `plugins/dev-pipeline/skills/build-lean/lean-evidence.sh`. The `Migration:` line is on `e41ff25`'s `Changelog:` trailer and names the pin move. |
| AC-6 | satisfied | `run-lean/` = `SKILL.md` + `orchestrate-lean.sh` + `orchestrate-lean-selftest.sh`; SKILL.md 58 lines, and case (n0) asserts the cap rather than leaving it to a reader. |
| AC-7 | satisfied | The loop chains preflight → BUILD → `resolve_pr` → REVIEW → `lean-gate.sh 4` with no operator step between phases. Gate exit codes and two read-only `gh` calls are its whole input; nothing parses a spec, a record or a finding. |
| AC-8 | satisfied | (g1): rc=2, `spawn_count` 0, message names the hand-back. |
| AC-9 | satisfied | Three probes backgrounded to `$PROBE_DIR`, joined by pid; (g2) and (g3) show every probe's verdict surviving a mid-list failure. The suite is candid that concurrency itself is not externally observable and asserts the property a serial short-circuit would break — the right call, and it matches the AC's own wording. |
| AC-10 | satisfied | (e1) + (h2); probed. Note the branch's own last commit fixed a **vacuous** version of (e1) — `grep -q -- '-p'` was matching the `-p` inside `--permission-mode`. |
| AC-11 | satisfied | (d1)/(d2) against a deliberately poisoned parent; probed. |
| AC-12 | satisfied | `--build-model` required with a refusal that names the label (case (a)); `--review-model` defaults `opus`, overridden in (k1). |
| AC-13 | satisfied | Both routes: (i1) gate rc=4, (i2) rounds spent. See W-2 on the default. |
| AC-14 | satisfied | (f) measures a recording fake across the approved run. See W-1 on the second run the AC names. |
| AC-15 | satisfied | (e2), driven with `CLAUDE_CODE_SESSION_ID` unset in the parent so a `yes` could only come from the scheduler — the right construction, and the one that makes this case mean anything. |
| AC-16 | satisfied | `LEAN_SPAWN_BIN`/`LEAN_GATE`/`GH`/`LEAN_SPAWN_PERMISSION_MODE`/`SECOND_SHIFT_CONFIG` all default to the real thing; read the whole file for a selftest-only branch and there is none. (m4) is what makes the `GH` default non-vacuous. |
| AC-17 | satisfied | Same-stem pair in one directory; no diff to `mutation-exclusions.tsv` or `mutation-pair-map.tsv`. |
| AC-18 | satisfied | V1–V3 in `docs/pipeline-manifesto.md` beside P1–P10, framed as a judgment aid with the P5 no-lint note explicit. |
| AC-19 | satisfied | Seven-row measured table in the PR body, each row carrying its number. The honest headline — the volume is small — is recorded as OR-2's result rather than dressed up. |
| AC-20 | satisfied | `intake-orchestrator/SKILL.md` adds the sizing label to both issue-creation forms and to the prose; `run-lean/SKILL.md` step 2 states the `sized-here:` fallback and why the default must not be left in place. |
| AC-21 | satisfied | `README.md`, `docs/onboarding.md`, `docs/team-rollout.md` and the consumer `SECOND-SHIFT.md` each name the split. |

## Warnings

| # | Finding |
| --- | --- |
| W-1 | **AC-14's assertion is half-written.** The AC says "across a full approved run **and** a full hard-stop run"; case (f) scores `$GH_LOG` only after case (b), the approved run. I checked whether the missing half hides anything and it does not — `probe_intake`'s `issue view` and `resolve_pr`'s `pr list` are the only tracker calls in the file, and the hard-stop path adds none, so the asserted call set is identical. The property holds; the case that states it is narrower than the AC. Scored satisfied on that basis, and named here because the next editor should not read (f) as covering both. |
| W-2 | **`MAX_ROUNDS=3` is asserted nowhere.** (i2) drives `--max-rounds 2`, so the *override* is guarded and the *default* — which is what AC-13's "the round budget is three" actually names — rests on a literal no case reads. `say` already prints `rounds: $MAX_ROUNDS`; a `grep -q 'rounds: 3'` in case (b) closes it in one line. |
| W-3 | **`resolve_pr` cannot tell a `gh` outage from an absent PR.** `2>/dev/null` plus `// empty` collapses both to the empty string, and the run stops with "no open PR on '$BRANCH' after the BUILD session" — which sends the operator to look at a BUILD session that did its job. Fails safe (exit 1 either way), so this is diagnostics, not control flow. `probe_intake` two functions up already branches on exit status first and is the model. |
| W-4 | **`--dry-run` is documented as cheaper than it is.** SKILL.md calls it "the cheap way to check routing first", but preflight runs before the dry-run block, so on a ticket that has not been labeled yet — the exact moment you want to check routing — it exits 2 having printed no schedule. Either move the dry-run branch above preflight or say that it dry-runs a ticket that already passes preflight. |
| W-5 | **The close-out BUILD spawn is the one unexplained branch in a heavily-explained file.** On `rc=0` the loop re-enters BUILD with the same prompt (`:266`). It is right — `build-lean` owns steps 9's closing comment, `G 5` and teardown — but every other branch here carries its rationale and this one carries only the word "close-out" in a log line. One sentence at the call site. |
| W-6 | **Four uncovered branches**, from test-coverage and confirmed by reading: `verdict_rc`'s `return 3` worktree-not-found path and its message (`:237`/`:273`); the `*)` unrecognized-gate-rc case (`:274`); the REVIEW and close-out `spawn` failure messages (`:260`/`:267`), of which only the first BUILD site is exercised by (j1); and `--max-rounds`'s non-numeric/zero refusal (`:96–97`). All are diagnostic-message branches with the same exit code as a covered sibling, which is why they are here and not above.

## Strengths

- **The scope discipline is the best thing in the PR.** The comment block at the top of `orchestrate-lean.sh` states what the scheduler is allowed to know — gate exit codes and tracker state — and the code holds to it with no exception. The one place it would have been easy to cheat, sizing the ticket, is a required flag with a refusal message that tells the caller where the answer lives.
- **The suite's anti-vacuity work is real, not stated.** Case (b) is scored first and explicitly as the positive control for the absence assertions in (e)–(g); (m4) exists because every other case set `GH` and left the shipped default unexercised; (e2) runs with the parent's session id unset so it cannot pass on the environment. That last one is the specific trap this repo has been burned by, and it is handled correctly.
- **The two defects the author's own probing found were fixed and disclosed rather than quietly patched** — the EPIPE flake under `pipefail` and the `-p`/`--permission-mode` substring match that made half an assertion vacuous. A suite that found a hole in itself and said so is worth more than one that reports 26 green.
- **The rename's blast radius was worked, not sampled.** Four path-anchored TSVs re-keyed with ordinals deliberately left alone, the consumer template's `?ref=`-pinned fetch identified as a real break and given a `Migration:` line, and `CHANGELOG.md`/`docs/plans/` correctly left as history.

## Suppressed (below threshold)

- `orchestrate-lean.sh:64` (45) — `LEAN_SPAWN_BIN`/`LEAN_GATE` are executed; setting them already requires shell control, and it is the established `${GH:-gh}` seam idiom.
- `orchestrate-lean.sh:215` (50) — spawns default to `--permission-mode auto`; the lane's pre-existing posture, unchanged here.
- `orchestrate-lean.sh:248` (40) — `$ISSUE` interpolated into the spawned prompt with no shape check; operator-supplied, never `eval`'d, and the parser rejects a leading `-`.

## Verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 1 minor | 82 |
| Test Coverage | Pass | 4 minor | 80–82 |

**Ready to merge? Yes.** Every AC is satisfied on the diff, the rename is provably content-preserving where it claims to be, and the one file that is genuinely new is guarded by a suite I probed six ways. W-1 and W-2 are assertion gaps whose underlying behavior I verified by hand rather than by taking the suite's word for it; W-3 through W-6 are diagnostics and comments. Worth folding in on a later pass, not worth a round.

Fidelity: **not-applicable** — the spec carries no `## Design` section and the repo configures no `design.provider`.
