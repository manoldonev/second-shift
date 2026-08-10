# lean review verdict — #427

verdict=approve
run_id: review-427-3
session_id: 363dc625-4bb8-4add-b08a-ab286617f320
rounds: 3
pr: #469
reviewed_head: 4e5bea4f421f9e9472a56e5b827bbdc6df7a6ef3
reviewed_patch_id: 7cff6c5e25995981d414d888df51fe194980a076
inherited_patch_id: 122b559e288060c82144a79302f3bae87fe0bb91
inherited_from_verdict: a70056c7df80862c1c9477c6e4bd1cfc2f4bdd13
fidelity: not-applicable
model: unknown

Round 3 — delta since the round-2 tree (`a70056c..HEAD`, two files: the spec's D-13 pointer and
`check-emit-deadline-selftest.sh`'s new case B12). Inherits the coverage of patch `122b559e2880`.
Read **wider than the delta**: the panel ran `d2c790d...4e5bea4`, which re-covers round 2's own
edits (`af6906b`, `a890716`) — round 2's `maintainability-reviewer` went dark over exactly those
commits, and inheriting a domain nobody reviewed is not inheriting coverage.

Panel: security, performance, maintainability, test-coverage, unit-test-mutation,
scope-completeness. **All six returned; none dark** — round 2's coverage gap is closed rather than
carried. a11y + design-fidelity were not routed: no changed path matched
`stageParams.webComponentGlobs` (unset → `apps/web/**/*.{tsx,jsx}`).

Round 2's blocker is fixed, and fixed on the lane that scores it. `mutation-sweep-pr` is **green on
this exact head** (run 31369724174, headSha `4e5bea4`): `applied=13 killed=12 survived=1`, the one
survivor being `catalog::emit-deadline-ceil`, which carries a baseline row. `check-emit-deadline.sh::cmp-z::1`
— the mutant that survived CI's GNU sed at `a890716` while dying on the author's BSD sed — is gone
from the survivor set. That is the measurement round 2 said was missing, taken on the userland that
disagreed.

No blockers. Two warnings, both outside the AC set and neither in shipped code.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | Warning | `.claude/pipeline-state/427-ledger.md:19` (D-13) | Round-2 warning 3's remedy landed, and it names the wrong pair. D-13 reads "One `verbatim` row, between `check-emit-deadline.sh` and `check-model-tiers.sh` … the two share a directory, so their `LOCKSTEP-BEGIN/END cross-plugin-sibling-plugin-root` blocks are byte-identical". The row actually added is `scripts/lockstep-manifest.tsv:532`, pinning `plugins/second-shift/skills/doctor/tools/doctor-selftest.sh` ↔ `plugins/dev-pipeline/skills/run/tools/preflight-selftest.sh` — two files in different plugins that do **not** share a directory, and the only two files in the tree carrying that marker (`grep` for `LOCKSTEP-BEGIN cross-plugin-sibling-plugin-root` returns exactly those two). The committed spec (`docs/plans/second-shift-427-lean.md:75-83`) names the right pair with the right reason; only the ledger is wrong. Not a blocker: the ledger is machine-local and gitignored, no `AC-n` covers lockstep treatment, and nothing ships from it — but the warning it answers was "the binding input and the diff disagree in the place a later reader checks first", and after the amendment they still do, differently. A reader following D-13 goes to two files that carry no lockstep block at all. Fix is one row's text. |
| 2 | Warning (carried) | `docs/plans/second-shift-427-lean.md:125` (OR-3) / ledger D-9 | Round-2 warning 2 stands: the follow-ups OR-3 and D-9 commit to **filing** — Class-C `cost-block-selftest.sh`, and the lexical newest-version sort (`9.0.0` outranks `10.0.0`) — are still not filed. `gh issue list --search lexical --state all` returns only #421 and #427; newest issues are #464/#465. The posture has improved and is now the correct one: the PR body states the bodies are drafted and awaiting the operator's go-ahead to post, which is the right call for a tracker write, and the round re-counted the mirrored sites honestly (**ten across nine files**, not the five stated at round 2 — a correction that widens the follow-up rather than shrinking it). Carried as an operator action, not a code defect, and not escalated. |

### Round-2 blocker — how it was verified closed

CI is the primary evidence and it is unambiguous: the sweep that was red at `a890716` with
`check-emit-deadline.sh::cmp-z::1` as a serially-re-verified baseline-absent survivor is green at
`4e5bea4` with that id absent from the survivor set. Nothing else about the sweep moved —
`applied` is still 13, and the surviving `catalog::emit-deadline-ceil` was already baselined.

The mechanism was checked independently, from the reviewed checkout, by probing the guard and
scoring which CASE moves. Each probe was applied to `check-emit-deadline.sh:191` alone, `bash -n`'d,
and the tree restored after:

| Probe | Expected | Observed |
| --- | --- | --- |
| Whole jq-less lookup → `head -1 "$j"` (returns the constant `{`) | B12 fails, alone | **B12 fails, alone** — `25 passed, 1 failed` |
| Anchor widened `\{0,2\}` → `\{0,\}` (reads the nested `author.name`) | B12 fails, alone | **B12 fails, alone** — `25 passed, 1 failed` |
| Anchor narrowed `^[[:space:]]\{0,2\}"name"` → `^"name"` | B11 fails | **B11 fails** — `25 passed, 1 failed` |

The first probe is the one that matters: it is the exact substitution that left the suite at `25
passed, 0 failed` before B12 existed, and it now fails. B12 discriminates on the **value** read, not
merely on some value being read, which is the axis `cmp-z::1` moves along on GNU sed. The second and
third show the anchor is pinned in both directions by one fixture — round 2's nit closed by
ordering `author` before the top-level `name` rather than by a third case. The assertion inversion is
real and not incidental: B12's two version dirs declare different names, so a correct lookup **keeps
both** roots and the superseded agent's violation reds the lint, while a collapsing lookup comes back
clean — and B12's else-branch greps for `stale-reviewer` rather than accepting any non-zero exit, so
it cannot pass on an unrelated failure.

`shellcheck -e SC1091,SC2015,SC2181` clean on both changed scripts. Suite `26 passed, 0 failed`
under `env -u CLAUDE_CODE_SESSION_ID`.

## Acceptance criteria

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 — selftest passes from a version-keyed install cache, live-tree assertions included | satisfied | Inherited from round 2's direct measurement (`install-topology-selftest.sh` 57 ran / 57 passed / 0 known-red / 2 skipped / 0 red at `a890716`), and the only change since is B12, which is topology-independent by construction: it stages its own marketplace under `$TMP` and copies `$CHECK` — resolved from the suite's own `$HERE` — into it, so it resolves identically from a cache as from the monorepo. The guard is the nightly lane's, not the PR lane's; I did not re-run it at this head, and the PR body's claim of 57/57 here is the build's own. |
| AC-2 — no-args run from an install lints >0 agents; roots to stderr; stdout unchanged | satisfied | Inherited. `check-emit-deadline.sh` is untouched this round (delta is the selftest + spec prose only), and round 2 verified this against a real 12-version cache: 4 agents linted, rc=0, `scanning roots:` on stderr only. B8 pins the split and still passes. |
| AC-3 — `doctor-selftest.sh` passes from that topology and its claims-lint scenarios execute | satisfied | Inherited; that suite is unchanged this round. CI `lint-and-selftests` and `selftests (macos, bash 3.2)` both pass at `4e5bea4`. |
| AC-4 — all three call sites resolve in this checkout; ordinary sweep unchanged | satisfied | CI green at this head on both selftest lanes. Locally `check-emit-deadline-selftest.sh` 26/0 with `env -u CLAUDE_CODE_SESSION_ID`; `shellcheck` clean on both changed scripts. The sweep gained one case and lost none. |
| AC-5 — mutation obligations discharged in the same diff | **satisfied** (was unsatisfied at round 2) | `mutation-sweep-pr` green at headSha `4e5bea4`: `applied=13 killed=12 survived=1`, survivor `catalog::emit-deadline-ceil` (baselined at `tools/mutation-baseline.tsv:20`). The catalog half re-checked here: the `emit-deadline-ceil` sed anchor still matches `check-emit-deadline.sh:320` byte-for-byte, so no re-anchor is owed; the baseline carries no `check-emit-deadline.sh::<op>::N` generic rows to re-key; and the round edits **only** the paired selftest, so the guard's generic ordinals are unmoved — the "editing a guard re-keys its ordinals" obligation is not triggered, which is a correct reading rather than a skipped one. |
| AC-6 — three rows drained from `install-topology-known-red.tsv` | satisfied | Inherited; the file is untouched this round. Round 2 confirmed all three gone with the merge resolved as the union of two independent drains, `0 known-red, 2 skipped, 0 stale row(s)`. |
| AC-7 — `preflight-selftest.sh:38` resolves through the ladder | satisfied | Inherited; that file is untouched this round. ENVIRONMENT-DEPENDENT by the AC's own terms — the falsifiable half (the ladder resolves, an empty `RT_TEST_ROOT` is a counted failure rather than a silent fall-through) is what is asserted, and OR-1 flags the rest honestly. |

## Design fidelity

`not-applicable`. The spec's `## Design` section is disarmed — `Design: none — no design.provider is
configured for this repo; the change is shell path resolution with no rendered surface`. Verified
against the repo config rather than taken on the spec's word: `.design` is absent
(`jq '.design'` → `null`), and the diff is shell path resolution plus a test fixture with no
rendered surface. The disarm is justified, so this is not the fourth design blocker.

## Dismissed

- **scope-completeness-reviewer, minor on the lockstep row** (confidence 88) — the same finding
  round 2 dismissed, on the same reasoning: no `AC-n` covers lockstep treatment, the deviation is
  declared in the committed spec with its rationale and its approval, and it is one of the two
  remedies round 1's own warning named. Its recommendation — "have the human ratify the deviation or
  record it in the run's deviations note" — is what D-13 is, so the remedy exists; warning 1 above is
  about D-13 being wrong on the specifics, not absent.
- **scope-completeness-reviewer, nit "AC-5's CI half is unobservable from this head"**
  (confidence 85) — factually wrong, and the reason to dismiss is evidence rather than judgment. It
  reports `gh run list --commit 4e5bea4` returning `[]`; run **31369724174** exists on that exact
  headSha (`gh run view 31369724174 --json headSha` → `4e5bea4f421f…`), and its `mutation-sweep-pr`
  job passed in 26s with the scored table quoted under AC-5. The sweep IS re-observable green on
  this head, which is precisely why round 2's blocker clears.
- **security / performance / maintainability / test-coverage / unit-test-mutation** — no findings.
  `test-coverage-reviewer` independently reproduced the constant-lookup probe and reached the same
  result, which is corroboration rather than a finding. Suppressed items (`EMIT_DEADLINE_JQ` as an
  invoker-owned seam at confidence 40, fixture `$TMP` path construction at 35, and a
  `${EMIT_DEADLINE_JQ:-jq}` default-operator mutant already killed by B10 at 70) are all below
  threshold and all already-litigated forms in this diff.
