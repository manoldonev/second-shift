# second-shift #441 — onboard/doctor GRILL the consumer on detectable config gaps

Issue: #441 · lane: run-lean · pre-flight ledger: `.claude/pipeline-state/441-ledger.md` (binding)

## Problem

Every optional config key is legally absent, so `config-lint` — a structural validator — is
incapable of noticing that a capability is off. Onboard finishes green, doctor finishes green,
and the capability never runs. Three audited cases: a re-onboard reverted `testFile`/
`unitTestScope` to `null` (mutation gate silently off); `webComponentGlobs` fell back to a
default matching zero files (a11y + design-fidelity never routed); the adopted `testFile`
resolved to a watch-mode script that would have hung forever.

## Shape

One shared checker, `plugins/second-shift/skills/onboard/tools/config-grill.sh`, run by both
front doors — `/second-shift:onboard` on its draft before the accept-or-edit screen, and
`/second-shift:doctor` on the committed config. A finding names the benefit and forces a
disposition: fix the key, or record a `grillWaivers` entry. Three of the five grill triggers
land here (T2, T4, T5); T1 and T3 are deferred to #449 / #450.

## Acceptance Criteria

**AC-1 — checker contract.** `plugins/second-shift/skills/onboard/tools/config-grill.sh`
takes `<repo-root> [<config-path>]` (config path defaults to
`<repo-root>/.claude/second-shift.config.json`) and writes ONE JSON document to stdout with
exactly two arrays:

- `findings[]` — each `{ id, key, evidence, proposal }`. `id` is the stable check id
  (`<trigger>.<check>[.<repoId>]`), `key` the dotted config path, `evidence` what was found,
  `proposal` a concrete next action.
- `notEvaluated[]` — each `{ id, key, reason }`. A not-evaluated notice is **never** a finding:
  it carries no proposal, cannot be waived, and must not block AC-7's accept predicate.

Findings are data — the script exits **0** whether or not it emitted any, so neither caller
treats a finding as a crash. Usage/IO errors (missing root, unreadable or non-JSON config)
exit **3** with a message on stderr, matching `config-lint.sh`.

Under a multi-repo topology it evaluates only the repo whose `topology.repos.<id>.path`
resolves to the root it was handed, and emits one `notEvaluated` entry per sibling rather than
reaching outside that root.

bash 3.2 compatible, read-only, no network.

**AC-2 — trigger 2 is a per-key table; keys outside it are out of scope.** Each active row
fires on **both** an absent key whose resolved default matches nothing and a hand-set value
that matches nothing — an adopted value can itself be broken (case C), so setting a key
wrongly must not silence the check.

| Key | What is validated | What counts as a finding |
| --- | --- | --- |
| `stageParams.webComponentGlobs` | value, else resolved default, globbed against tracked files | matches 0 tracked files |
| `stageParams.formatGlob` | value, else resolved default, globbed against tracked files | matches 0 tracked files |
| `stageParams.visualCapture.triggerGlobs` | value, else resolved default, globbed against tracked files | matches 0 tracked files |
| `stageParams.inertPattern` | — | dropped: its predicate belongs to `is-inert-diff.sh`, which ships in dev-pipeline and is frequently not installed at onboard time; `preflight.sh` already runs it at Step 8 |
| `stageParams.planFilePattern` | — | dropped: names a file Stage 3 creates |
| `paths.plansDir`, `paths.pipelineStateDir` | — | dropped: a fresh repo legitimately lacks them |
| `visualCapture` non-glob keys | — | dropped: not tree-shaped |

Check ids: `T2.webComponentGlobs`, `T2.formatGlob`, `T2.visualCaptureTriggerGlobs`.

**AC-3 — what a trigger-2 finding says, and how it counts.** The finding quotes the
**runtime-resolved** default — the jq fallback literal the consuming stage applies — never the
JSON Schema `default`, which nothing injects into a config:

| Key | Runtime-resolved default | Source of the literal |
| --- | --- | --- |
| `stageParams.webComponentGlobs` | `apps/web/**/*.{tsx,jsx}` | `review-lead/SKILL.md`, `stages/8-code-review.md` |
| `stageParams.formatGlob` | `*.{ts,tsx,js,json,md}` | `verifyctl.sh` |
| `stageParams.visualCapture.triggerGlobs` | `apps/web/src/app/**/*.{tsx,jsx}`, `apps/web/src/app/**/*.css`, `apps/web/src/components/**/*.{tsx,jsx}`, `apps/web/tailwind.config.{ts,js}` | `stages/6-verify.md` |

Each finding states the match count and a **detected alternative with its own count**, drawn
from a fixed per-key candidate list. When no candidate matches, the finding still fires and
says no alternative was detected. Candidate lists (seeded from the framework shapes
`review-lead/SKILL.md` already enumerates):

- `webComponentGlobs`: `src/app/**/*.{html,ts}` (Angular), `src/**/*.vue` (Vue),
  `app/**/*.tsx` (React Router v7), `src/**/*.{tsx,jsx}` (React under `src/`).
- `visualCapture.triggerGlobs`: `src/**/*.{tsx,jsx}`, `src/**/*.vue`, `app/**/*.tsx`.
- `formatGlob`: `*.{ts,tsx,js,jsx,json,md}`, `*.{py,md,json}`, `*.{sh,md,json,yml}`,
  `*.{go,md,json}`, `*.{rs,md,toml}`.

Match counting transliterates the glob to an extended regular expression over `git ls-files`
— these scripts stay bash 3.2 compatible, 3.2 has no `globstar`, and git pathspec globbing
does not brace-expand. The transliteration:

1. ERE metacharacters other than the glob operators are escaped.
2. `{a,b,c}` → `(a|b|c)`.
3. A pattern containing `/`: `**/` → `([^/]*/)*`, remaining `**` → `.*`, `*` → `[^/]*`,
   `?` → `[^/]`.
4. A pattern containing **no** `/` (the `formatGlob` shape) is matched with `*` → `.*`, which
   crosses path separators. This reproduces `verifyctl.sh`'s `[[ "$f" == $a ]]` semantics
   exactly; `[^/]*` there would match only root-level files and would fire a zero-match
   finding on every repo whose sources sit in a subdirectory.
5. Anchored `^…$` against each `git ls-files` path.

The coupling between the checker's restated literals and their sources is recorded as a
**DROPPED** entry in `scripts/lockstep-manifest.tsv` with its reasoning, not as rows: the
`webComponentGlobs` literal alone is restated at seven sites across two plugins, which
file-to-file anchored pairs cannot express.

**AC-4 — trigger 4, internally inconsistent config.** One finding for each of:

| Check id | Condition | Note |
| --- | --- | --- |
| `T4.testfile-plumbing.<repoId>` | `commands.<repo>.unitTestScope` non-null **and** `commands.<repo>.testFile` null | the condition Stage 5 already fail-closes on |
| `T4.mutation-plumbing.<repoId>` | `gates.mutation` not literally `false` **and** `commands.<repo>.unitTestScope` null | see below |
| `T4.design-liverender` | `design.provider` set **and** `design.liveRender` absent | not per-repo |

The `gates.mutation` check follows **runtime** semantics, not the schema default: Stage 5
resolves `.gates.mutation // empty` and only the literal `false` takes the off-switch branch,
so **absent is not false**. The finding text states the state actually found — `true` or
`absent (not false — the gate is ON)`.

**AC-5 — trigger 5, a declared command that contradicts repo reality.** It inspects **every**
configured command for the evaluated repo: `testFile`, `test`, `lint`, `typecheck`, `format`,
`lanes[].commands[]`, `extraLanes[].commands[]` — a command that never exits hangs Stage 6
exactly as it hangs a mutation run.

Resolution is deliberately narrow, because the missing-script half can produce a false FAIL on
a valid config and that is worse than a missed warning:

| Command shape | `<name>` in root `package.json` scripts | Outcome |
| --- | --- | --- |
| `<pm> run <name> …` | yes | resolved — watcher test runs on the script body |
| `<pm> run <name> …` | no | **finding** `T5.missing-script.<repoId>.<slot>` |
| `<pm> <name> …` | yes | resolved — watcher test runs on the script body |
| `<pm> <name> …` | no | not-evaluated (`<pm> <name>` is ambiguous — `yarn workspaces …`, `pnpm dlx …` are not script invocations) |
| anything else (`npx tsc --noEmit`, `bash scripts/verify.sh`, workspace fan-out) | — | not-evaluated |

`<pm>` ∈ `npm` \| `yarn` \| `pnpm` \| `bun`. Root manifest only, matching `detect.sh`. On a
stack with **no** root `package.json` at all, every configured command is reported
not-evaluated rather than passing silently.

The watcher test runs against the **manifest script body**, not the configured command string:
`yarn test {file}` looks fine, and it is `scripts.test: "vitest"` underneath that hangs
forever. Finding id `T5.watcher.<repoId>.<slot>`. Starter taxonomy, stated so the criteria and
fixtures are writable, expected to grow (OR-1):

- first token `vitest` or `vite` with no exiting subcommand (`run`, `build`, `preview`,
  `optimize`, `bench`, `list`) **and no `--run` flag anywhere** — `--run` is the flag spelling
  of the `run` subcommand and exits exactly as it does;
- a `--watch`, `--watchAll` or `--watch=true` flag anywhere (covers `jest --watch`);
- a standalone `-w` flag **whose first token is a runner that defines `-w` as watch**:
  `jest`, `vitest`, `vite`, `tsc`, `tsup`, `webpack`, `rollup`, `esbuild`, `parcel`, `karma`,
  `ava`, `mocha`, `sass`, `nodemon`;
- `nodemon` as a command token;
- a dev-server script: `next dev`, `webpack serve`.

The qualifications on `--run` and `-w` are **narrowings of the taxonomy this AC first stated**,
folded in from review round 1. Unqualified, the `-w` rule fires on `prettier -w .` (where `-w`
is `--write`) and the vitest rule fires on `vitest --run` — each a doctor `FAIL` on a valid
config, whose only escape is a `grillWaivers` entry excusing a non-problem. That inverts this
AC's own governing principle — *a false FAIL on a valid config is worse than a missed warning*
— which is written against the missing-script half but binds the watcher half identically, and
it weakens AC-8's "a clean report stays reachable" from *adopt or declare* to *declare, because
there is nothing to adopt*. Both narrowings can only reduce firing, so nothing the original
wording caught is lost but the two shapes it caught wrongly. Under-firing remains OR-1's
subject.

`<slot>` is the command's config location: `testFile`, `test`, `lint`, `typecheck`, `format`,
`lanes.<i>.<j>`, `extraLanes.<i>.<j>`.

**AC-6 — `grillWaivers`.** A top-level `grillWaivers` object is accepted by
`schema/second-shift.config.schema.json` and by `config-lint.sh`'s top-level key allowlist;
`configVersion` stays at **2** and no migration doc is required. Keys are check ids carrying
the repo id wherever the check is per-repo (`T4.mutation-plumbing.api`); values are the reason
string (non-empty). `config-lint` rejects a non-object `grillWaivers` and any non-string or
empty value. A finding whose id is waived is suppressed by the checker itself, so both callers
suppress it identically.

Neither a config path nor a bare check id is sufficient: two distinct trigger-4 checks both key
on `commands.<repo>.unitTestScope`, so a path-keyed waiver would silence both, and under a
multi-repo topology a check-id-only waiver would silence every repo at once.

`check-config-shadowing.sh` carries no row for the key: its `CHECKS` array is rooted at the
dev-pipeline skill dir and this key's only reader lives in the second-shift plugin. The
omission is a stated exception, not an oversight, and is recorded in the checker's header.

**AC-7 — onboard.** `/second-shift:onboard` materializes its Step-3 draft to a temp JSON file
and runs the checker on it **before** presenting the accept-or-edit screen. Unresolved findings
render as blocking lines on that screen; the checker re-runs on each loop iteration; the screen
cannot be accepted while any finding is neither fixed nor waived. `notEvaluated` entries render
informationally and never block. Onboard's "at most one AskUserQuestion batch" rule and its
"a diff review of a 90%-correct document, not a wizard" framing stay verbatim and unamended,
and every waiver reason is typed by the human — never authored by the tool.

**AC-8 — doctor.** `/second-shift:doctor` runs the checker on the committed config and reports
each unwaived finding as a `FAIL` with its remediation, incrementing doctor's exit code exactly
as any other FAIL does. `notEvaluated` entries are informational and never affect the exit
code. A clean report stays reachable: every finding is resolvable by adopting the capability or
by declaring the waiver. The checker resolves within doctor's own plugin
(`${CLAUDE_PLUGIN_ROOT}/skills/onboard/tools/`, env-overridable for the selftest) — a strictly
shorter reach than the cross-plugin one doctor already performs for `config-lint.sh`.

**AC-9 — tests.** `plugins/second-shift/skills/onboard/tools/config-grill-selftest.sh`
(discovered by the CI glob, no registration) covers, against fixtures:

- every **active** row of the AC-2 table — absent-key-default-matches-zero and
  hand-set-value-matches-zero, plus a matching case that emits no finding;
- the detected-alternative branch and the no-alternative-detected branch;
- every rule in AC-4, including `gates.mutation` absent vs `true` vs `false`;
- every row of the AC-5 resolution table and every entry of the watcher taxonomy, plus the
  no-manifest non-evaluation and — one case per narrowing — the two shapes the narrowings
  exclude (`prettier -w .` and `vitest --run`), each asserted **silent**;
- the multi-repo scoping rule (evaluated repo vs sibling not-evaluated);
- a waived-finding case proving suppression;
- a not-evaluated case proving it does **not** block acceptance (it is absent from
  `findings[]`);
- exit 0 with findings present, and exit 3 on a bad config path.

`config-lint-selftest.sh` gains a `grillWaivers` fixture case (valid accepted; invalid
rejected). `doctor-selftest.sh` covers, besides the finding / waived / not-evaluated
scenarios, both of doctor's grill **degrade** branches — checker present but exiting non-zero,
and checker absent — each asserted to `warn` and to leave the exit code at 0. Those branches
cannot produce a wrong verdict; what they can do is let a broken integration read as green,
which is exactly what an untested `warn` path invites.

**AC-10 — docs.** `docs/config-schema.md` gains a `grillWaivers` row in its group table, and
`docs/extending.md` names the grill in the section that explains why a published key that
nothing reads is a lint failure. Without this the new top-level key is undocumented on the
field-by-field surface both docs claim to be exhaustive about.

## Open regions (from the ledger, unchanged)

OR-1 watcher-taxonomy completeness · OR-2 non-npm stacks (checker states non-evaluation) ·
OR-3 triggers 1 and 3 deferred to #449/#450 · OR-4 glob match parity with prose consumers ·
OR-5 first-run volume on the existing consumer corpus is unmeasured.

## Out of scope

`stageParams.inertPattern` (AC-2, dropped — `preflight.sh` owns it); trigger 1 (#449);
trigger 3 (#450); the pre-existing `gates.mutation` schema-default-vs-description
contradiction noted in the ledger.
