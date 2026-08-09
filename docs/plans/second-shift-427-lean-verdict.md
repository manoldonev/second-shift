# lean review verdict — #427

verdict=needs-work
run_id: review-427-1
session_id: c4558b93-3f4a-4b29-aef9-3aa05b259c8b
rounds: 1
pr: #469
reviewed_head: ab1935fdfa62ece0d7703f0a70a41147b2dbcea5
reviewed_patch_id: f963dd52a8d0d778e721252f6f1b3eebbc2e88aa
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

Round 1 — full branch range (`6a6922c..HEAD`), nothing to inherit.

Panel: security, performance, maintainability, complexity, test-coverage, scope-completeness — all six returned, none dark. a11y + design-fidelity were not routed: no changed path matched `stageParams.webComponentGlobs` (unset → `apps/web/**/*.{tsx,jsx}`).

The three ladders are correct and the two named-sibling copies handle a multi-version cache properly (`tail -1` / `sort -r` over the version dirs). The enumeration variant does not, and that is the one blocker.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | **Blocker** | `plugins/review-toolkit/scripts/check-emit-deadline.sh:~137` (shape 1) | From an install cache holding **more than one version** of review-toolkit — the normal state of `~/.claude/plugins/cache` — shape 1's `$HERE/../../*/` enumerates *every* version dir of the plugin the script ships in, with no newest-version selection. Stale versions' agents are linted as if current. Shape 2 correctly narrows siblings to `newest`; shape 1 does not, and the block's own comment ("shape 1 matches MY OWN version dirs and nothing else") states the fact without acting on it. |
| 2 | Warning | `plugins/second-shift/skills/doctor/tools/doctor-selftest.sh:33` ↔ `plugins/dev-pipeline/skills/run/tools/preflight-selftest.sh:56` | The two new `resolve_sibling_plugin_root()` bodies are identical apart from the anchor variable name (`HERE` vs `SCRIPT_DIR`) — same four/five hop constants, same `[[ ]]`/`printf`/`tail -1` logic. The `lockstep-manifest.tsv` entry this same commit writes ends with "Revisit … if two copies ever converge on identical hop constants — that pair would be byte-anchorable and should be pinned." This commit creates that pair and does not pin it. |
| 3 | Nit | `plugins/review-toolkit/scripts/check-emit-deadline-selftest.sh:247` | B6 ("nothing resolves") depends on no *other* fixture dir under `$TMP` carrying `.claude-plugin/plugin.json` — it passes today only because B7/B9 build their trees later in file order. Reordering the file would silently break it. Staging B6 under its own `mktemp -d` would make it order-independent. |

### Blocker 1 — evidence

Reproduced twice, from a cache with review-toolkit `3.0.0` + `4.1.0` (real shipped trees), the branch's `check-emit-deadline.sh` + selftest in the newest, no git repo above (`git rev-parse --show-toplevel` → `fatal: not a git repository`):

```
[B] real tree
  FAIL: B1 live tree fails the lint: [emit-deadline] scanning roots: …/review-toolkit/3.0.0/agents …/review-toolkit/4.1.0/agents
  FAIL: spec-reviewer.md — maxTurns:15 is at the default cap, but 'spec-reviewer' is enrolled
        in the deadline contract (DEADLINE_AT_DEFAULT) and the body declares no emit deadline.
[emit-deadline] 1 violation(s) across 8 linted agent(s)
[check-emit-deadline-selftest] 22 passed, 1 failed        SELFTEST_RC=1
```

Against this machine's actual plugin cache (12 cached review-toolkit versions) the shipped lint reports **16 violations across 38 linted agents**, rc=1 — 9 from `spec-reviewer.md` and 7 from `plan-reviewer.md` in versions that predate their `DEADLINE_AT_DEFAULT` enrollment.

`tools/install-topology-selftest.sh` cannot see this: it stages exactly one version per plugin (`cache/review-toolkit/4.1.0` and nothing else), and B9 stages `mine/1.0.0` + `other/1.0.0` — one version each. Every instrument in the diff is blind to the multi-version shape. Run here against the branch it is green — `59 ran, 57 passed, 2 known-red, 0 stale row(s), 0 red`, the two known-reds being the pre-existing `config-lint` / `check-review-context-sections` rows — which is exactly the point: the guard the ACs lean on passes while the shipped lint reds on the real cache next to it.

Why it is a blocker and not a note: AC-1's subject is "a version-keyed install cache", and a real one is multi-version. The PR replaces one wrong answer from an install (vacuous clean over zero agents) with another (a hard failure over dead cached copies), so the defect the slice exists to remove is not removed — it changed sign. The stated rationale, "for a lint the safe direction is more agents scanned, never fewer", holds for *sibling plugins* but not for *superseded copies of this plugin*: those are not more coverage, they are historical noise that reds the lint.

Remedy: apply the same newest-per-plugin selection shape 2 already uses to shape 1 (keep only the last candidate per plugin *name* — read from `.claude-plugin/plugin.json`, which every candidate must already carry — which degenerates correctly in both layouts, since monorepo siblings have distinct names and cache version dirs all share one). Then add a selftest case staging **two** versions of the scanning plugin; nothing in the current suite covers that shape.

### Warning 2 — note

The extended DROPPED entry justifies not pinning by "the hop constants **are** the contract and they legitimately differ" — true against `check-model-tiers.sh` (two/three hops), but not true of the new pair, whose constants are identical. D-3 answered "no new rows" on the premise that none of the new copies is byte-anchorable; this pair nearly is. Either rename one anchor variable so the marker blocks are byte-identical and add the `verbatim` row, or amend the DROPPED entry to say why this specific pair stays dropped. Not merge-blocking on its own — no behavior is wrong — but the manifest currently states a revisit trigger that the same commit fires.

## Acceptance criteria

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 — selftest passes from a version-keyed install cache | **unsatisfied** | Passes from the single-version cache `install-topology-selftest.sh` stages; fails B1 from a two-version cache (Blocker 1). |
| AC-2 — no-args run from an install lints >0 agents; roots to stderr; stdout unchanged | satisfied | B8 asserts the stderr/stdout split; probes confirm non-zero agents from a cache. The count includes duplicates across versions until Blocker 1 is fixed. |
| AC-3 — `doctor-selftest.sh` passes from that topology and its claims-lint scenarios execute | satisfied | The `if [[ -f ]]` else-branch is now `check … 1` through the existing `check`/`FAILS` tally; `resolve_sibling_file`'s three rungs handle a multi-version cache (`sort -r` over versions). Green in-checkout. |
| AC-4 — all three call sites resolve in this checkout; ordinary sweep unchanged | satisfied | Three suites green in-checkout (`env -u CLAUDE_CODE_SESSION_ID`); CI `lint-and-selftests` and `selftests (macos, bash 3.2)` both pass; `shellcheck -e SC1091,SC2015,SC2181` clean on all four changed scripts. |
| AC-5 — mutation obligations discharged in the same diff | satisfied | The `emit-deadline-ceil` anchor (`(2 * cap + 2) / 3`) is byte-identical to main's, so no re-anchor was owed. `mutation-sweep-pr` computed 13 verdicts on this guard — applied=12, killed=11, survived=1 — and the single survivor is `catalog::emit-deadline-ceil`, already in `tools/mutation-baseline.tsv`. The baseline carries no generic-ordinal rows for this file to re-key, so there was nothing to write. |
| AC-6 — three rows drained from `install-topology-known-red.tsv` | satisfied | All three removed, with the drain reason recorded in the header. |
| AC-7 — `preflight-selftest.sh:38` resolves through the ladder | satisfied | Hop constants re-derived correctly for `skills/run/tools` (four/five); the new `assert` makes an empty `RT_TEST_ROOT` a counted failure instead of a silent fall-through to the `claude plugin list` rung. Environment-dependent by the AC's own terms — the ladder's *resolution* is asserted directly, which is the falsifiable part. |

## Design fidelity

`not-applicable`. The spec's `## Design` section is disarmed (`Design: none — no design.provider is configured for this repo`). Verified against the repo config: `.design` is absent, and the change is shell path resolution with no rendered surface. The disarm is justified.

## Dismissed

- **scope-completeness-reviewer, blocker on AC-5** (confidence 88) — it conceded the catalog half is a verifiable no-op and called the baseline half "unevidenced". CI settles it: `mutation-sweep-pr` swept the guard rather than deferring it, and its one survivor is already baselined. Nothing was owed to the diff.
- security / performance / complexity / test-coverage — no findings above threshold. Suppressed items (`ROOTS` word-splitting on paths with spaces, the widened enumeration scope, the near-duplicate ladders) are either pre-existing forms or already-litigated trade-offs in this diff.
