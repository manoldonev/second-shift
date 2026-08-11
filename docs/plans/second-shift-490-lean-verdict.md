# lean review verdict — #490

verdict=needs-work
run_id: review-490-1
session_id: 25ce9959-8300-44ad-81b4-c2065b750de7
rounds: 1
pr: #491
reviewed_head: a03369d0bf50f471e9f6f61468bf29e57b4b5be8
reviewed_patch_id: 5d1322d8980b7e41cef64a9900d0b40b164e2059
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 1 · full-branch range `4bc19cc..HEAD` (root — nothing to inherit).

The code is right. `--review-model-basis` lands exactly as specified, every new assertion is
live under probe, and the B6 isolation fix is correct. One blocker, and it is entirely in the
record rather than in the behavior: the committed rationale for AC-8 names a mechanism that is
measurably false, and the PR body builds a lane recommendation on it.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | **blocker** | `plugins/review-toolkit/scripts/check-emit-deadline-selftest.sh:252-260`, `docs/plans/second-shift-490-lean.md` D-7 | The recorded collision mechanism is false. Both say "a second copy of THIS file … stages its own `<mktemp>/plugin-wrong-prefix`". `check-emit-deadline-selftest.sh` never stages `plugin-wrong-prefix`, and no second copy of it can collide via shape 2 at all: every plugin fixture it stages (`b7`, `b9`–`b12`) puts `.claude-plugin/plugin.json` at `$TMP/b<N>/marketplace/…`, two or more levels below `$TMP`, whereas shape 2 requires the marker at `$TMPDIR/<tmpdir>/<x>/`. The real collider is `check-reviewer-references-selftest.sh:284`, which stages `$TMP/plugin-wrong-prefix` — depth 1, carrying both `.claude-plugin/plugin.json` and `agents/` (`fixtures/reviewer-references/plugin/`). That is a different suite, and an ordinary one: it runs in every `SELFTEST_JOBS=4` sweep, not only under `install-topology-selftest.sh`'s duplicate-suite geometry. So the exposure class in the record is narrower than the real one, and the PR body's conclusion — that the milestone-3 lane's failure to exclude install-topology "is what made a latent bug present as this branch's failure" — does not follow from it. |
| 2 | warning | PR body | "an attempt at a synthetic deterministic repro (staging a plugin-shaped decoy as a `$TMPDIR` sibling) did **not** fire, so the exact trigger geometry is not fully characterised" — falsified. It fires deterministically at the right depth; see the measured repro below. The decoy has to sit at `$TMPDIR/<tmpdir>/<x>/`, not `$TMPDIR/<x>/`, because shape 2 globs `$HERE/../../../*/` and then `*/` beneath it. |
| 3 | warning | PR title | "A downgraded review model now costs a stated reason" carries no conventional type. `scripts/derive-release.sh:132-149` reads each commit's own `%s` over `$LAST_TAG..HEAD` on main, so after a squash-merge only the PR title survives — the branch's `feat(dev-pipeline):` on `8b6210b` does not. A new operator-facing flag would therefore derive **patch**, not the minor CLAUDE.md's "use the honest verb" rule calls for. Fix is metadata-only (no commit, no round): retitle to `feat(dev-pipeline): a downgraded review model now costs a stated reason`. Precedent that this bites: #488 moved the build payload to `build-lean` under a verbless title and shipped inside the v4.1.4→v4.1.5 **patch**. |
| 4 | suggestion | `check-emit-deadline-selftest.sh` | Finding 2 makes AC-8's "no guard that fails on revert" closable in this round. A ~12-line case stages the decoy at the collide-shape depth and asserts B6's premise survives it — deterministic, no concurrency, no `-P 10` rehearsal. |
| 5 | pre-existing | `orchestrate-lean.sh:86-96` | A trailing value-less flag hangs the parse loop forever: `shift 2` with `$#`=1 returns 1 without shifting, so `while [ $# -gt 0 ]` spins. Measured under `alarm 5`: `--review-model-basis` rc=142, and `--build-model` rc=142 identically on the base branch. The new flag inherits the shape rather than introducing it — not this PR's debt. |

### Measured repro for findings 1, 2 and 4

Decoy at `<mktemp>/plugin-wrong-prefix/{.claude-plugin/plugin.json,agents/decoy-reviewer.md}`, then the
two B6 geometries run against the real `check-emit-deadline.sh`:

- **pre-fix** (`B6ROOT` = `mktemp -d` directly, as on main): resolves the foreign fixture —
  `scanning roots: …/tmp.PbhR7Cw0lw/plugin-wrong-prefix/agents`, `2 violation(s) across 1 linted
  agent(s)`. B6's `grep -q "no sibling plugin agents dir found"` fails. The flake, reproduced.
- **post-fix** (`B6ROOT` = `<mktemp>/iso`, as on this PR): `FAIL: no sibling plugin agents dir
  found from …/tmp.PBRFOZw1UK/iso/lonely/scripts`. B6 passes. The fix works.

## AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `--review-model-basis` parse arm at `:88`, free text, no default, echoed per D-2's format at `:200`. Live: deleting the parse arm kills `(k1)`/`(k3)`/`(k6)`. |
| AC-2 | satisfied | `:105-107`, after the `[ -n "$REVIEW_MODEL" ]` check and before preflight per D-4; exit 2 via `envfail`; names `--review-model-basis`; interpolates `'$REVIEW_MODEL_DEFAULT'`. Live: `if false` in place of the condition kills `(k2)` and nothing else. `(k2)` asserts `spawn_count` 0. |
| AC-3 | satisfied (structurally; unguarded) | `opus` now occurs three times — `:17` and `:100` are the build sizing labels D-1 fences off, `:73` is the sole review-default referent (base had a fourth at `:42`, now reworded). Behaviorally unguarded, as the PR body states: substituting the literal `"opus"` into the comparison survives the whole suite. Consistent with D-1's letter, which scopes AC-3 to the referent, not to a mutant. |
| AC-4 | satisfied | `(k5)` explicit default needs no basis; `(k6)` volunteered basis echoed. Live: always-append kills `(k5)`; never-append kills `(k6)`. |
| AC-5 | satisfied | `sed -n '2,62p'` — line 62 is the last comment line, 63 is `set -uo pipefail`; +3 comment lines against the base's 59. D-6's claim that case `(n)` already guards this is **verified in both directions**: narrowing to `2,59p` kills `(n)`, and widening to `2,64p` kills `(n)`. No new case owed. |
| AC-6 | satisfied | `(k1)` carries `--review-model-basis` and still asserts `LEAN_RUN_MODEL: sonnet` reaches `spawn-2`. |
| AC-7 | satisfied | `(k2)` refusal + 0 spawns + names the flag; `(k3)` accepted departure reaches the spawn and echoes; `(k4)` happy path on the default tier with no basis note; `(k5)`/`(k6)` cover AC-4's two claims. |
| AC-8 | satisfied (letter) | Fixture nested below `$B6PARENT`; `$HERE/../../../*/` now globs only that private dir. Same contract asserted. Serial: green on this head in both CI selftest jobs (ubuntu + the stock-bash-3.2 macOS job). Collision geometry: isolation holds under the deterministic repro above. Finding 1 is filed against AC-8's *record*, not its behavior. |

## Also verified

- Probes P0–P7 on `orchestrate-lean-selftest.sh`: baseline all-green, and each mutant kills only
  the cases named above — no new assertion is trivially true.
- D-3 holds: the `${NAME:-value}` site list is order-identical between base and head
  (`:58` prose, `:66` `GH_CLI`, `:67`, `:68`, `:69`, `:116`, `:142`), and the `default` operator's
  ERE requires `[A-Za-z_]` after `${`, so the new `${2:-}` parse arm is not a site.
  `orchestrate-lean.sh::default::1` still names the prose `${GH:-gh}` and needs no re-keying;
  `mutation-sweep-pr` is green on this head.
- `shellcheck -e SC1091,SC2015,SC2181` clean on all three changed scripts.
- Release hygiene: no frozen file touched; every commit carries a `Changelog:` trailer.
- CI on `a03369d`: `lint-and-selftests`, `selftests (macos, bash 3.2)`, `mutation-sweep-pr` all
  green. `pr-gates` red on its **lean chain reconciliation** arm only — the missing verdict
  record, expected pre-review; the frozen-files, changelog-trailer and pipeline-chain arms all pass.
- Panel: security, performance, maintainability, complexity, test-coverage,
  scope-completeness — 6/6 approve, zero findings, none dark.

## What round 2 needs

Correct the mechanism in `check-emit-deadline-selftest.sh`'s B6 comment and in D-7 — name
`check-reviewer-references-selftest.sh`'s `$TMP/plugin-wrong-prefix` as the collider, and say that
the exposure is any concurrently-running suite staging a plugin-shaped dir one level below its
`mktemp` root, so an ordinary `SELFTEST_JOBS=4` sweep is exposed too, not only install-topology.
Drop or correct the PR body's "not fully characterised" claim. Landing finding 4's deterministic
case in the same round is strongly recommended: it is what turns AC-8 from a hand-run rehearsal
into a guard, and it is now cheap. Finding 3 is a title edit at the merge boundary, not a commit.
