# Config schema guide (static context)

Machine contract: [`schema/second-shift.config.schema.json`](../schema/second-shift.config.schema.json) (JSON Schema 2020-12). Enforcement the plugins actually run: [`config-lint.sh`](../plugins/dev-pipeline/tools/config-lint.sh) — shipped **inside the dev-pipeline plugin** (so installed-cache consumers can run it), invoked at pipeline Pre-flight; keep it in lockstep with the schema. Worked examples for all three topologies: [`config-lint-fixtures/valid-*.json`](../plugins/dev-pipeline/tools/config-lint-fixtures/).

| Group | What goes here | Motivating examples |
| --- | --- | --- |
| `tracker` | `github` (optional bot identity for claim-safe issue writes, key pattern) or `jira` | a gh-bot claim model vs read-only JIRA |
| `topology` | `standalone` \| `be-fe-pair` \| `monorepo`; per-repo `path`, `baseBranch`, `worktreesDir`, `ticketTag` | a BE-`alpha`/FE-`main` pair asymmetry; `[BE]`/`[FE]` ticket routing; sibling paths |
| `commands` | Per-repo command truth table (lint/typecheck/test/testFile/unitTestScope/format; `null` = lane unavailable) + `lanes` (SETUP-only, INFRA-classed) + `extraLanes` (additive verify lanes with a real failureClass) + `allowUnverified` (boolean zero-lane safety valve — `preflight` warns + withholds its `pipeline-ready` verdict unless set, and `lean-gate.sh` milestone 3 reds naming the opt-out unless set; inert when any verifying lane is configured, #98/#392) | the verify-lane truth table, read by `preflight.sh` and by `lean-gate.sh` milestone 3 (#379); a monorepo `apps/*`/`packages/*` install matrix in `lanes`; an integration/e2e tier in `extraLanes`; a docs-only repo with no test surface opting out explicitly |
| `reviewers` | Registry deltas (`add`/`remove`) + per-reviewer `modelOverrides` (`haiku` \| `sonnet` \| `opus` \| `fable`; `fable` is override-only and subscription-gated — never a shipped default, and a `check-model-tiers.sh` error inside plugin code) | a repo-local domain reviewer; FE repos dropping db-reviewer; security-reviewer opus-vs-sonnet split; a Fable-enabled repo elevating plan-reviewer |
| `paths` | plans dir, pipeline-state dir | defaults match all three forks |
| `gates` | `mutation` — defaults off; `false` is an explicit off-switch declaring the unit-test mutation seam deliberately absent even when `unitTestScope` is set. The lean lane's sweep is repo-carried (`tools/mutation-sweep.sh`, run by milestone 3 when the repo ships one), so this key is the declared intent config-grill grades that plumbing against rather than a switch the gate reads | disabling mutation testing on a repo that has a `unitTestScope` |
| `design` | `provider`: `figma` \| `claude-design` — the design-fidelity axis; key absent = off; prerequisites missing at run time fail closed. Optional `liveRender` `{ command, cwd?, readyProbe? }` arms a repo-owned render command (`{route}`/`{out}`, plus `{state}`) on `lean-gate.sh` milestone 3, which is **blocking** on the run's shared 3-attempt budget and additionally requires a per-ticket `## Design` section in the committed spec — config alone arms nothing, and the disarm state-locks once a ticket arms. The staged lane's degrade-to-`render-verify-unavailable` posture died with it in #348, so there is one posture now — see [`live-render.md`](live-render.md) | a Figma-MCP FE shop vs a Claude-Design (design-sync) shop; a MIFE wiring `yarn render:verify` |
| `grillWaivers` | Declared opt-outs for [config-grill](../plugins/second-shift/skills/onboard/tools/config-grill.sh) output, keyed by **check id** (with the repo id where the check is per-repo, e.g. `T4.mutation-plumbing.api`) and valued by the human-authored reason. The grill is what `config-lint` structurally cannot be: absence is legal for every optional key, so the lint never touches the tree and a capability that is off simply never runs. The key waives **two severities**. A *finding* is a detectable defect: `/second-shift:onboard` blocks its accept-or-edit screen on unwaived ones and `/second-shift:doctor` reports each as a `FAIL`. An *unadopted* entry reports an optional capability no question ever named — the `stageWorkflows` / `implementDelegates` / `planGates` seams, id `T1.extension-points`, carrying no repo id because all three are top-level keys — which onboard also blocks on, while doctor reports it as a **note** that leaves the exit code alone: a key at its default is not a defect. Additive and optional — `configVersion` stays at 2 | a shell-and-Markdown repo declaring it has no web-component surface; a repo declaring its mutation opt-out where a reader can see it; a repo declaring that the shipped gates are all it wants |

Principles:

- **If two forks differed on a value, it's config.** If they differed on *behavior*, it's a config-selected adapter (`tracker`, or the `design` provider axis) or a gate.
- **No domain knowledge in config.** Prose-shaped knowledge goes to extension files ([`extension-points.md`](extension-points.md)); config stays enumerable and lintable.
- `configVersion` bumps only on breaking schema changes; plugins support one version per release. The migration contract and per-version upgrade docs live in [`migrations/`](migrations/README.md); config-lint fails older/newer configs with the pointer, never a bare "invalid".
- **A `commands.<host>` lane runs in a scrubbed child env.** `preflight.sh` and `lean-gate.sh` milestone 3 both spawn every configured lane command (`lint`/`typecheck`/`test`/`format`/`lanes`/`extraLanes`) with the pipeline's own seam vars (`SECOND_SHIFT_CONFIG`, `STATECTL_STATE_DIR`, and related overrides) stripped from its environment (`env -u`) — a lane command that is itself second-shift tooling (dogfooding) must not see the caller's pipeline state. The denylist itself is stated once, as `SEAM_SCRUB` inside the `LOCKSTEP-BEGIN seam-scrub` markers in [`lean-gate.sh`](../plugins/dev-pipeline/skills/build-lean/lean-gate.sh); the stage doc that used to carry this note died with the staged lane in #348.
- **Exit code `3` is RESERVED on a verify lane: "this failed for reasons that are not the branch."**
  It applies to the fixed `lint`/`typecheck`/`test` keys and to every `extraLanes` entry (setup
  `lanes[]` are already infra-classed, and are out of it). `lean-gate.sh` milestone 3 reads a `3`
  as infrastructure: it reds with exit `7` — *nothing was evaluated* — instead of `1`, charges **no
  fix attempt**, and the lean scheduler re-spawns the build session rather than reporting an idle
  one. This repo's own [`tools/run-selftests.sh`](../tools/run-selftests.sh) raises it when every
  failing suite is its no-verdict class (the workers were killed); a run mixing infra with a
  genuinely red suite still exits `1`, because a red branch is still a red branch.
  **The exposure:** a lane that already exits `3` for a genuine failure is reclassified as
  infrastructure and charged no fix attempt. There is deliberately no per-lane opt-out — the
  failure direction is a run that retries when it should have stopped, bounded by the scheduler's
  `--max-continuations` and by the gate's milestone-3 interrupt budget, never a red branch reported
  green. Have such a lane exit any other non-zero code.
- **`ticketTag` is advisory, and only advisory.** It keys off
  `topology.repos.<id>.ticketTag` on a confirmed pair's `be`+`fe` entries. It used to read two
  ways: the staged lane's Stage 1.T resolved `TARGET_REPOS` from it as a gate input and failed
  closed on an unrecognized title, while the lean lane treated it as a hint. #348 deleted the
  staged lane, so only the advisory reading remains — no gate reads it, `lean-gate.sh`
  included, and the sibling's own separate standalone onboard (needed for `run-lean` — see
  [`onboarding.md` § Pair repos (BE/FE)](onboarding.md#pair-repos-befe-under-the-lean-lane))
  carries no `ticketTag` of its own. The `intake-orchestrator` skill reads it as ticket-title
  routing policy, not a gate. Neither reading changes the other.
