# Issue #107 — onboard/verify robustness: pair sibling detection name-bound; lintAutofixes+npm-run lint no-ops

## Context

Two robustness gaps surfaced during the 2026-07 stack-generality evaluation:

1. `detect.sh`'s be/fe sibling detection only proposes a pair when an on-disk sibling
   matches `../<current-repo-base>-{ui,web,frontend,client,app}` — i.e. the sibling must
   share the current repo's base name (after stripping a trailing `-api`) AND use one of a
   fixed FE-suffix vocabulary. Two synthetic pairs with physically-adjacent sibling
   checkouts (`fastapi-be` + `vue-fe`, `express-api` + `angular-fe`) reported "no sibling
   candidates" because neither shares a base name with its sibling, and `-be`/`-fe` are not
   in the checked suffix sets.
2. `config-lint.sh` does not flag `commands.<repo>.lintAutofixes: true` combined with a
   `commands.<repo>.lint` value shaped like `npm run <script>` — `verifyctl.sh` appends a
   bare ` --fix` to the configured lint command (`$CMD_LINT --fix`), and plain `npm run`
   swallows a trailing flag instead of forwarding it to the underlying tool unless the
   command already carries a `--` separator. The autofix loop then silently does nothing,
   with no lint signal that the config combination is inert.

## Scope

- AC-1 and AC-2 below. Doc updates are AC-scoped; no doc AC is opened since neither change
  alters a documented contract (detect.sh's header already says "never asks, never
  guesses" — broadening the on-disk match still only detects, never guesses; config-lint's
  README/schema already document that `commands.<repo>.lint` is a free-form string).
- Out of scope (issue explicitly notes these as cosmetic, not filed): no `statectl
  reset/clear` verb, the INERT verdict string phrasing on a Python repo, and plain lint
  failures always classed `LINT_AUTOFIX`.

## AC-1 — `detect.sh` recognizes name-unrelated be/fe sibling pairs

**Given** the current repo's own basename carries a recognized BE-side suffix
(`-api`, `-be`, `-backend`, `-server`, `-service`) or FE-side suffix (`-ui`, `-web`,
`-frontend`, `-client`, `-app`, `-fe`),
**when** an adjacent directory (`../<name>`) is a git repository (has a `.git` entry) whose
own basename carries a suffix from the *counterpart* set — regardless of whether it shares
the current repo's base name —
**then** `detect.sh` adds that directory to `topology.siblingCandidates` and sets
`topology.value` to `be-fe-pair-candidate`, exactly as it already does for a same-base-name
match.

The existing same-base-name convention match (e.g. `shop-api` finding `../shop-ui`) keeps
working unchanged — this is an *addition* to the candidate scan, not a replacement.
`detect.sh` remains read-only and non-interactive: it only widens what counts as
evidence for a candidate; onboard's existing "topology pair confirm" elicitation step
(SKILL.md Step 3, batch item 2) is still the only place a pair is accepted.

Verified by: `detect-selftest.sh` — a new case constructs `fastapi-be` next to `vue-fe`
(name-unrelated, both suffix-shaped) and asserts `../vue-fe` appears in
`topology.siblingCandidates` and `topology.value == "be-fe-pair-candidate"`. The existing
same-base-name case (`shop-api`/`shop-ui`) is left in place unmodified to prove the addition
doesn't regress it.

## AC-2 — `config-lint.sh` flags `lintAutofixes: true` with a non-forwarding `npm run` lint command

**Given** `commands.<repo>.lintAutofixes == true`,
**when** `commands.<repo>.lint` matches `^npm run ` and does not already end with a `--`
separator (trimmed),
**then** `config-lint.sh` reports a violation naming the repo, the configured lint command,
and the concrete fix (add a trailing `--`, e.g. `"npm run lint --"`, or invoke the
underlying tool directly, e.g. `"npx eslint ."`).

A lint command that already ends with `--` (ready to receive forwarded args) is not
flagged. Non-`npm run` invocations (yarn/pnpm/direct tool calls) are not flagged — they
forward unrecognized flags to the underlying tool without needing a separator.

Verified by: `config-lint-selftest.sh` — a new `invalid-lintautofix-npm-nofix.json`
fixture (`lintAutofixes: true`, `lint: "npm run lint"`) must fail mentioning the new
violation text; a new `valid-lintautofix-npm-withfix.json` fixture (`lint: "npm run lint
--"`) must pass, proving the trailing-`--` escape hatch works and the rule doesn't
over-fire on yarn-style commands already covered by the existing valid fixtures.
