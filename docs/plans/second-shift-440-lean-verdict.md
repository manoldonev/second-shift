# lean review verdict — #440

verdict=approve
run_id: review-440-1
session_id: 9e0819c6-0402-48dd-adf0-b2b67488799a
rounds: 1
pr: #457
reviewed_head: ca7f04602295db22fe2df37a6cfe484570e98dc4
reviewed_patch_id: 369cf526e622fb02ea7b98cb91b8729794ae4ff4
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

Round 1 — full branch diff (`c19f19e..ca7f046`, 12 files), the range `lean-gate.sh delta 440`
printed. No prior record to inherit from.

## Verdict

**approve.** No blockers. Three warnings and one nit, none of which changes the diff's
correctness; the first is a PR-body correction, which does not touch the patch and so does not
void this record.

## Acceptance criteria

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | The `tracker.bot is github-only` rule is gone from `config-lint.sh`. The five shape rules underneath it (`tracker.bot: unknown keys`, the three type checks, `tracker.bot.app: unknown keys`) are byte-unchanged and sit inside `(.tracker.bot // {}) \| …`, which carries no tracker condition — so they fire under either adapter by construction. The sibling `tracker.labels is github-only` rule is retained at `:56`, with a comment recording why the two keys part company. |
| AC-2 | satisfied | `config-lint-fixtures/valid-standalone-jira-bot.json` is the issue's reproduction config (jira + `writes: false` + `bot.enabled` + `app.appName`). `config-lint-selftest.sh:17` globs `valid-*.json`, so it is exercised with no registration — re-adding the deleted rule reds it. `invalid-bot-app-unknown-key.json` and `invalid-type-gaps.json` expectations are untouched. Suite run locally: all green. |
| AC-3 | satisfied | `arm_identity` now branches on `[ "$BOT_ENABLED" != "true" ]`, through the same `inapplicable identity reduced-strength` class-(b) emitter, reason reworded to name the writer. Resolution is `LEAN_BOT_ENABLED` → `cfg '.tracker.bot.enabled'` → tracker-derived default (`false` jira / `true` github), with a closed true\|false envfail. The behavior-preservation argument holds where it matters most: this repo gitignores its own config, so its CI reads nothing, `TRACKER_TYPE` defaults to github and the arm keeps gating at full strength. Verified by probe, not by reading — see below. |
| AC-4 | satisfied | `cmd_mark`'s early return is re-keyed to `BOT_ENABLED`, and its `say` names the absent bot. `cmd_claim`'s jira branch is unchanged; only its parenthetical is corrected, and a new comment states why that one stays tracker-keyed (a read-only tracker has no comment surface — a tracker fact, unlike the PR). `(pm6b)` drives `mark` under jira+bot and asserts a spooled post, with a `jq -e` non-vacuity guard on its fixture builder. |
| AC-5 | satisfied | `review-lean/SKILL.md` step 8 routes the findings comment through `gh-bot.sh` when its `--status` is `ok`, plain `gh` otherwise. The predicate is stronger than the AC's wording ("when the bot is enabled"): `--status` also returns `not-executable` / `missing-file` / `unset-var`, so a repo that declares a bot it cannot exec falls back rather than failing the post. The tracker-delta note no longer says "posted via `gh`". |
| AC-6 | satisfied | Corrected at all eight named sites: `schema/second-shift.config.schema.json` (`bot` description), `tracker/README.md:92`, `tracker/jira/README.md:74`, `templates/consumer/SECOND-SHIFT.md:59`, and the in-file comments in `lean-evidence.sh`, `lean-evidence-selftest.sh`, `lean-gate.sh`, `lean-gate-selftest.sh`. A repo-wide grep for the prohibition ("github-only" / "forbid" near `bot`) returns no residue outside `docs/plans/` and the derived `CHANGELOG.md`, both correctly untouched. `run-lean/SKILL.md:36` already claimed "the step-7 PR marker … is made under every tracker that has a bot" on `main`, where it was false; this PR makes it true rather than leaving new drift. |
| AC-7 | satisfied | Six new cases — `(ab1)`–`(ab4)` in `lean-evidence-selftest.sh`, `(pm6b)` in `lean-gate-selftest.sh`, plus the re-anchored `(aa1)`. Both suites re-run green here, and I re-derived the probe claim independently rather than taking the PR body's word for it. |

## Probes run in this review

Each mutation applied to the production line, suite re-run, then reverted (`git status` clean
after each):

| Mutation | Kills |
| --- | --- |
| `arm_identity` re-keyed to `[ "$TRACKER_TYPE" = "jira" ]` | `(ab1)`, `(ab2)`, `(ab3)` |
| `BOT_ENABLED="${LEAN_BOT_ENABLED:-}"` → `BOT_ENABLED=""` | `(ab4)` |
| `lean-evidence` jira default `false` → `true` | `(aa1)` |
| `lean-evidence` github default `true` → `false` | 16 cases, incl. `(a)`, `(c)`, `(k)` |
| `cmd_mark` re-keyed to `[ "$TRACKER_TYPE" = "jira" ]` | `(pm6b)` |
| `lean-gate` jira default `false` → `true` | `(pm6)`, `(n2)`, `(n14)`, `(n15)` |

Every new assertion is killed by mutating the line it claims to guard. No survivors.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | Warning | PR body, Verification | The claim "the new `[ -z "$BOT_ENABLED" ]` takes `cmp-z` ordinal 1, which the suite kills" is wrong on both halves. Ordinals index the operator's full matched-line list in file order, and in `lean-evidence.sh` `cmp-z` ordinal 1 is the `-h\|--help) sed -n '2,130p'` line and ordinal 2 is `[ -n "$SUB" ]`; the new site is **ordinal 8**, past `k=2`, so the sweep never mutated it and "the suite kills it" is not a sweep result (it is true — I probed it — but by a different route). The companion `default` ordinal 7 claim is correct. **No baseline row is re-keyed either way:** I diffed ordinals 1 and 2 for all six operators across all three edited guards, `origin/main` vs `ca7f046`, and every one is byte-identical — which is what the green `mutation-sweep-pr` independently confirms. Fix the sentence in the PR body; the body is not part of the patch id, so this costs no round. |
| 2 | Warning | `lean-gate.sh:993` (and `:897`) | The gate now believes config about the writer but the write still demands one hardcoded env var: `"${GH_BOT:?GH_BOT must point at the bot wrapper}"`. `tracker.bot.envVar` and `tracker.bot.wrapperPath` are schema-legal and resolved by `tools/gh-bot.sh`'s three-rung ladder — the resolver this very PR adopts for `review-lean` step 8 — but `cmd_mark` does not use it. Newly reachable population: a jira consumer that legally configures a bot under a custom `envVar` now passes the `BOT_ENABLED` gate and then hard-fails milestone 5, where before #440 it took the documented degrade. Pre-existing for github consumers and identical in `cmd_claim`, so this is not a regression introduced here and it is outside the ticket's stated scope — warning, not blocker. Worth a successor. |
| 3 | Warning | `lean-evidence.sh:255-257`, `lean-gate.sh:265-268` | "Bot block absent" now resolves differently across readers on the same run: these two default to `true` under github, while `pipeline-cost-block.sh:232` and `bot-commit.sh` read `.tracker.bot.enabled // false`. A github consumer writing `bot: { app: { … } }` without an explicit `enabled` therefore gets bot identity demanded by `mark` and operator identity used by the cost block. The github `true` is deliberate and well argued (the strict reading, the unreadable-config posture, this repo's own CI), so this is a documented divergence rather than a defect — recorded so the next reader does not re-derive it, and because a partial `bot` block is now a shape a jira consumer can write for the first time. |
| 4 | Nit | `config-lint-fixtures/` | AC-1 asserts the shape rules "still fire under both trackers", and both fixtures that prove it (`invalid-bot-app-unknown-key.json`, `invalid-type-gaps.json`) carry `tracker.type: github`. The assertion is true by construction — the rules sit under an unconditional `(.tracker.bot // {})` — so nothing is at risk. But on a ticket whose entire subject is a rule that keyed on the tracker where it should not have, a one-line jira variant of a `bot`-shape violation would pin the other half for the cost of a fixture. |

## CI

`lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass, `mutation-sweep-pr` pass,
`release-pr-gates` skipped. `pr-gates` fails on exactly one thing — `no committed verdict record
(a file named *-440-lean-verdict.md)` — which this record supplies. Nothing else is red.

## Design fidelity

`not-applicable`. The consumer config declares no `design.provider`, and the spec carries no
`## Design` section, which `lean-gate.sh:1167` requires only when a provider is declared. There
is nothing to render against and nothing to score.
