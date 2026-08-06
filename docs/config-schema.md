# Config schema guide (static context)

Machine contract: [`schema/second-shift.config.schema.json`](../schema/second-shift.config.schema.json) (JSON Schema 2020-12). Enforcement the plugins actually run: [`config-lint.sh`](../plugins/dev-pipeline/skills/run/tools/config-lint.sh) — shipped **inside the dev-pipeline plugin** (so installed-cache consumers can run it), invoked at pipeline Pre-flight; keep it in lockstep with the schema. Worked examples for all three topologies: [`config-lint-fixtures/valid-*.json`](../plugins/dev-pipeline/skills/run/tools/config-lint-fixtures/).

| Group | What goes here | Motivating examples |
| --- | --- | --- |
| `tracker` | `github` (optional bot identity for claim-safe issue writes, key pattern) or `jira` | a gh-bot claim model vs read-only JIRA |
| `topology` | `standalone` \| `be-fe-pair` \| `monorepo`; per-repo `path`, `baseBranch`, `worktreesDir`, `ticketTag` | a BE-`alpha`/FE-`main` pair asymmetry; `[BE]`/`[FE]` ticket routing; sibling paths |
| `commands` | Per-repo command truth table (lint/typecheck/test/testFile/unitTestScope/format; `null` = lane unavailable) + `lanes` (SETUP-only, INFRA-classed) + `extraLanes` (additive verify lanes with a real failureClass) + `allowUnverified` (boolean zero-lane safety valve — Stage 6 refuses an all-skipped summary unless set, and `preflight` warns + withholds its `pipeline-ready` verdict unless set; inert when any verifying lane is configured, #98) | verifyctl lane config (also read directly by `lean-gate.sh` milestone 3, #379); a monorepo `apps/*`/`packages/*` install matrix in `lanes`; an integration/e2e tier in `extraLanes`; a docs-only repo with no test surface opting out explicitly |
| `reviewers` | Registry deltas (`add`/`remove`) + per-reviewer `modelOverrides` (`haiku` \| `sonnet` \| `opus` \| `fable`; `fable` is override-only and subscription-gated — never a shipped default, and a `check-model-tiers.sh` error inside plugin code) | a repo-local domain reviewer; FE repos dropping db-reviewer; security-reviewer opus-vs-sonnet split; a Fable-enabled repo elevating plan-reviewer |
| `paths` | plans dir, pipeline-state dir | defaults match all three forks |
| `gates` | `mutation` — defaults off; `false` is an explicit off-switch for the Stage-5 unit-test mutation gate even when `unitTestScope` is set | disabling mutation testing on a repo that has a `unitTestScope` |
| `design` | `provider`: `figma` \| `claude-design` — the design-fidelity axis; key absent = off; prerequisites missing at run time fail closed. Optional `liveRender` `{ command, cwd?, readyProbe? }` arms the Stage-5 live-render verify gate with a repo-owned render command (`{route}`/`{out}` placeholders) — see [`live-render.md`](live-render.md) | a Figma-MCP FE shop vs a Claude-Design (design-sync) shop; a MIFE wiring `yarn render:verify` |

Principles:

- **If two forks differed on a value, it's config.** If they differed on *behavior*, it's a config-selected adapter (`tracker`, or the `design` provider axis) or a gate.
- **No domain knowledge in config.** Prose-shaped knowledge goes to extension files ([`extension-points.md`](extension-points.md)); config stays enumerable and lintable.
- `configVersion` bumps only on breaking schema changes; plugins support one version per release. The migration contract and per-version upgrade docs live in [`migrations/`](migrations/README.md); config-lint fails older/newer configs with the pointer, never a bare "invalid".
- **A `commands.<host>` lane runs in a scrubbed child env.** `verifyctl.sh`, `preflight.sh`, and `lean-gate.sh` milestone 3 all spawn every configured lane command (`lint`/`typecheck`/`test`/`format`/`lanes`/`extraLanes`) with the pipeline's own seam vars (`SECOND_SHIFT_CONFIG`, `STATECTL_STATE_DIR`, and related overrides) stripped from its environment (`env -u`) — a lane command that is itself second-shift tooling (dogfooding) must not see the caller's pipeline state. See [`stages/6-verify.md`](../plugins/dev-pipeline/skills/run/stages/6-verify.md#deterministic-verify-runner-verifyctl).
- **`ticketTag` reads two ways depending on the lane.** Both readings key off the same
  `topology.repos.<id>.ticketTag` values on a confirmed pair's `be`+`fe` entries — nothing
  about the field or its config location changes. Under the staged lane (`/dev-pipeline:run`)
  it's a gate input — Stage 1.T resolves `TARGET_REPOS` from it and fails closed on an
  unrecognized title. Under the lean lane (`/dev-pipeline:run-lean`, the default) it is
  purely advisory: no gate reads it, `lean-gate.sh` included, and the sibling's own separate
  standalone onboard (needed for `run-lean` — see
  [`onboarding.md` § Pair repos (BE/FE)](onboarding.md#pair-repos-befe-under-the-lean-lane))
  carries no `ticketTag` of its own. The `intake-orchestrator` skill reads it as ticket-title
  routing policy, not a gate. Neither reading changes the other.
