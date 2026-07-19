# Config schema guide (static context)

Machine contract: [`schema/second-shift.config.schema.json`](../schema/second-shift.config.schema.json) (JSON Schema 2020-12). Enforcement the plugins actually run: [`config-lint.sh`](../plugins/dev-pipeline/skills/run/tools/config-lint.sh) — shipped **inside the dev-pipeline plugin** (so installed-cache consumers can run it), invoked at pipeline Pre-flight; keep it in lockstep with the schema. Worked examples for all three topologies: [`config-lint-fixtures/valid-*.json`](../plugins/dev-pipeline/skills/run/tools/config-lint-fixtures/).

| Group | What goes here | Motivating examples |
| --- | --- | --- |
| `tracker` | `github` (optional bot identity for claim-safe issue writes, key pattern) or `jira` | a gh-bot claim model vs read-only JIRA |
| `topology` | `standalone` \| `be-fe-pair` \| `monorepo`; per-repo `path`, `baseBranch`, `worktreesDir`, `ticketTag` | a BE-`alpha`/FE-`main` pair asymmetry; `[BE]`/`[FE]` ticket routing; sibling paths |
| `commands` | Per-repo command truth table (lint/typecheck/test/testFile/unitTestScope/build/format; `null` = lane unavailable) + `lanes` (SETUP-only, INFRA-classed) + `extraLanes` (additive verify lanes with a real failureClass) + `allowUnverified` (boolean zero-lane safety valve — Stage 6 refuses an all-skipped summary unless set; inert when any verifying lane is configured, #98) | verifyctl lane config; a monorepo `apps/*`/`packages/*` install matrix in `lanes`; an integration/e2e tier in `extraLanes`; a docs-only repo with no test surface opting out explicitly |
| `reviewers` | Registry deltas (`add`/`remove`) + per-reviewer `modelOverrides` | a repo-local domain reviewer; FE repos dropping db-reviewer; security-reviewer opus-vs-sonnet split |
| `paths` | plans dir, pipeline-state dir | defaults match all three forks |
| `gates` | `mutation` — defaults off; `false` is an explicit off-switch for the Stage-5 unit-test mutation gate even when `unitTestScope` is set | disabling mutation testing on a repo that has a `unitTestScope` |
| `design` | `provider`: `figma` \| `claude-design` — the design-fidelity axis; key absent = off; prerequisites missing at run time fail closed. Optional `liveRender` `{ command, cwd?, readyProbe? }` arms the Stage-5 live-render verify gate with a repo-owned render command (`{route}`/`{out}` placeholders) — see [`live-render.md`](live-render.md) | a Figma-MCP FE shop vs a Claude-Design (design-sync) shop; a MIFE wiring `yarn render:verify` |

Principles:

- **If two forks differed on a value, it's config.** If they differed on *behavior*, it's a config-selected adapter (`tracker`, or the `design` provider axis) or a gate.
- **No domain knowledge in config.** Prose-shaped knowledge goes to extension files ([`extension-points.md`](extension-points.md)); config stays enumerable and lintable.
- `configVersion` bumps only on breaking schema changes; plugins support one version per release. The migration contract and per-version upgrade docs live in [`migrations/`](migrations/README.md); config-lint fails older/newer configs with the pointer, never a bare "invalid".
