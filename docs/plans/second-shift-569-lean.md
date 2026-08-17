# #569 — retire EP-6 / EP-7 / EP-8 (`stageWorkflows`, `implementDelegates`, `planGates`)

Issue: [#569](https://github.com/manoldonev/second-shift/issues/569) · base `main` @ `dc6021f`
(the #568 merge). Follow-up to #348 / PR #568, filed at round-5 approve.

## The change in one line

#568 took two dispositions on one class of thing — a config key whose only consumer was the
deleted staged lane. `stageParams.visualCapture` was **retired**; EP-6/7/8 were **kept**,
schema-legal, banner-marked `INERT`. This ticket applies the retirement disposition to the other
three, because a kept dead key **silently disarms a consumer's blocking gate** and a dead-key
rejection is the only mechanism that reaches them.

The design record survives; only the live key dies.

## Acceptance criteria

- **AC-1** — `stageWorkflows`, `implementDelegates` and `planGates` are removed from
  `schema/second-shift.config.schema.json`, and `config-lint.sh` rejects each **by name** with a
  message stating the removal and its reason, following the `visualCapture` shape. No
  `configVersion` bump (precedent `36630a8`; `check-configversion-migration-doc.sh` passes on
  `OLD == NEW`).
- **AC-2** — `check-extensions.sh` loses arm (2) entirely (the `if [[ -f "$CONFIG" ]] && command
  -v jq` guard and all three resolution loops), plus the now-dead `CONFIG=` assignment and its
  `SECOND_SHIFT_CONFIG` override. EP-3 manifest lint untouched and still called from
  `preflight.sh`. The script header, `preflight.sh`'s success line and `check-doc-routing.sh`'s
  cross-reference comment stop claiming EP-6/EP-7 coverage. `check-extensions-selftest.sh`
  updated.
- **AC-3** — the mutation registers move in the **same diff**:
  - `tools/mutation-catalog.tsv`'s `check-extensions-plangates` row **and** its
    `catalog::check-extensions-plangates` row in `tools/mutation-baseline.tsv` are deleted
    together. A `catalog::` orphan never self-heals (`mutation-sweep.sh` exempts `catalog::` from
    the stale-guard warn), and this exact class cost PR #568 a round.
  - `plugins/dev-pipeline/tools/check-extensions.sh::logic::2` is **re-keyed** by AC-2. Re-derive
    the operator's matched-site sequence at the new head and re-baseline from evidence — proven
    with a byte-identical matched-line **sequence**, not a count.
- **AC-4** — `docs/extending.md` §3.6–3.8 survive as a **past-tense design record**, reframed the
  way `state-schema.md`'s historical banner is. The `INERT since #348` banners go with the keys.
  `docs/config-schema.md`, `docs/migrations/v1-to-v2.md` and every other doc asserting these are
  configurable-today are re-pointed. One `docs/migrations/v1-to-v2.md` entry, alongside
  `visualCapture`'s.
- **AC-5** — `Changelog:` trailer plus a `Migration:` line naming the three keys and the remedy.
  A previously-valid consumer config becomes rejected, so the honest verb is breaking (`!`) per
  CLAUDE.md — and the **PR title** carries it, since the squash subject is what
  `derive-release.sh` reads.
- **AC-6** *(amendment — see "AC set amended", below)* — `config-grill.sh`'s
  `T1.extension-points` check is removed, along with its `config-grill-selftest.sh` block, the
  two `doctor-selftest.sh` scenarios keyed on it, its `doctor-fixtures/config-t1-waived.json`
  fixture, and the `docs/config-schema.md` `grillWaivers` prose that names it. Nothing shipped
  may tell a consumer to adopt a key `config-lint` now rejects.

### Out of scope

Re-arming any extension point on the lean lane — the deferred product decision this ticket
deliberately does not make. The live `stageParams` keys (`inertPattern`, `formatGlob`,
`webComponentGlobs`, `planFilePattern`, `requiredLabels`) are untouched, as is EP-3's manifest
lint. `CHANGELOG.md` and plugin `version` fields are release-derived and frozen.

## AC-1: an internal contradiction, resolved against the tree

AC-1 as filed says two incompatible things:

> Follow the `visualCapture` shape exactly, including the mechanic at `config-lint.sh:243-244`:
> **the key stays in the sibling allowed-keys list** so the *specific* rejection fires instead of
> the generic "unknown top-level keys" one. **Drop all three from the top-level allowlist at
> `config-lint.sh:40`.**

For a *top-level* key the "sibling allowed-keys list" **is** the top-level allowlist, so the two
sentences cannot both hold. `err()` accumulates rather than short-circuits, so:

| | consumer sees |
| --- | --- |
| keep in the allowlist + specific rejection | one message, naming the key and the reason |
| drop from the allowlist + specific rejection | two messages — a generic `unknown top-level keys: stageWorkflows` **and** the specific one |

**Resolved: keep them in the allowlist.** Three reasons, in order of weight:

1. **The AC's own stated purpose clause requires it** — "so the specific rejection fires instead
   of the generic one". Dropping them defeats the thing the sentence is there to achieve.
2. **Every retirement already in this tree does it that way.** `gates.costTracking`,
   `gates.figma` and `gates.apiTests` (the `36630a8` precedent AC-1 cites) all stay in
   `gates`' allowlist with a `has(...)` rejection above it; `stageParams.visualCapture` stays in
   `stageParams`' allowlist the same way. There is no counter-example.
3. It is the behavior a consumer benefits from. A bare "unknown top-level keys: planGates" is
   exactly the uninformative rejection the retirement pattern exists to avoid.

The keys are genuinely retired either way — the schema property is dropped and config-lint
rejects by name. The allowlist entry is a **message-routing mechanism**, not a grant of
legality. Flagged here rather than settled silently so the reviewer can disagree on the record.

## AC set amended — why AC-6 exists

The filed AC set enumerates four surfaces per key and, in its preamble, folds in the two
`config-lint.sh` messages (`:99`, `:171`) that #568 shipped recommending EP-6/EP-7. It misses a
**third shipped recommendation, and this one blocks**:

`config-grill.sh`'s `T1.extension-points` check fires into `unadopted[]` whenever all three keys
are absent, and its proposal text tells the consumer to adopt one. Per `docs/config-schema.md`,
`/second-shift:onboard` **blocks its accept-or-edit screen on an unwaived `unadopted` entry.**

After AC-1 lands, that check's only two exits are:

- adopt a seam → config-lint rejects the resulting config; or
- type a waiver.

The "adopt" arm becomes impossible, so an onboarding consumer is deadlocked into a waiver for a
capability that no longer exists. That is a strictly worse instance of the same defect the
ticket's preamble names ("the consumer hits a rejection, follows the remedy the tool prints, and
gets silence"), so it is retirement work, not new scope. The sibling `T1.mutation-sweep.<repo>`
check — keyed on `commands.<repo>.test`, durable config, and deliberately independent — survives
untouched and keeps the `unadopted` severity exercised.

## Surface inventory

Derived by grepping the three key names, `EP-6|EP-7|EP-8`, and `T1.extension-points` across the
tree (excluding `.git/`, `CHANGELOG.md` and `docs/plans/**`, all of which are historical records).

| Surface | File | AC |
| --- | --- | --- |
| schema properties (3) | `schema/second-shift.config.schema.json` | AC-1 |
| top-level allowlist + 3 rejections + 3 validation blocks | `plugins/dev-pipeline/tools/config-lint.sh` | AC-1 |
| stale EP-6/EP-7 remedies in two rejection messages | `plugins/dev-pipeline/tools/config-lint.sh` `:99`, `:171` | AC-1 |
| lint fixtures using the keys | `config-lint-fixtures/{valid-be-fe-pair-jira,invalid-type-gaps,invalid-bad-stageworkflow,invalid-bad-plangate}.json` | AC-1 |
| lint selftest expectations | `plugins/dev-pipeline/tools/config-lint-selftest.sh` | AC-1 |
| arm (2) + `CONFIG=` + header | `plugins/dev-pipeline/tools/check-extensions.sh` | AC-2 |
| selftest case (6) | `plugins/dev-pipeline/tools/check-extensions-selftest.sh` | AC-2 |
| pre-flight success line | `plugins/dev-pipeline/tools/preflight.sh` `:126` | AC-2 |
| cross-reference comment | `plugins/dev-pipeline/tools/check-doc-routing.sh` `:7` | AC-2 |
| catalog row + `catalog::` baseline row | `tools/mutation-catalog.tsv` `:44`, `tools/mutation-baseline.tsv` `:10` | AC-3 |
| re-keyed generic ordinal | `tools/mutation-baseline.tsv` `:62` | AC-3 |
| decision-guide rows + §3.6–3.8 + §4 case study | `docs/extending.md` | AC-4 |
| migration entry + three stale EP remedies | `docs/migrations/v1-to-v2.md` | AC-4 |
| `grillWaivers` prose naming the retired seams | `docs/config-schema.md` `:14` | AC-4 / AC-6 |
| stale EP-6/EP-7 remedy | `plugins/second-shift/skills/onboard/SKILL.md` `:88` | AC-4 |
| parity rows saying "retirement candidate for #348" | `tools/capability-parity.tsv` | AC-4 |
| `T1.extension-points` check | `plugins/second-shift/skills/onboard/tools/config-grill.sh` | AC-6 |
| its selftest block | `config-grill-selftest.sh` | AC-6 |
| two scenarios + fixture | `plugins/second-shift/skills/doctor/tools/doctor-selftest.sh`, `doctor-fixtures/config-t1-waived.json` | AC-6 |

**Deliberately untouched.** `CHANGELOG.md` (frozen, release-derived). `docs/plans/**` (committed
specs and verdict records — historical). `plugins/dev-pipeline/state-schema.md` `:189`, `:228`
(already under its own "Historical record — the pre-#348 staged-lane format" banner, whose
explicit contract is that its dead references "are not to be 'fixed'").

## Verification

- `find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181`
- `find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty`
- `env -u CLAUDE_CODE_SESSION_ID SKIP_STRESS=1 bash tools/run-selftests.sh --exclude tools/install-topology-selftest.sh`
- `bash tools/mutation-sweep.sh --mode pr --base origin/main` for the AC-3 re-baseline evidence.

The load-bearing suites: `config-lint-selftest.sh`, `check-extensions-selftest.sh`,
`config-grill-selftest.sh`, `doctor-selftest.sh`, `derive-release-selftest.sh` (which drives
`check-frozen-files.sh` and `check-configversion-migration-doc.sh`).

## Design

Design: none — no UI surface. This is a config-key retirement across schema, validators, docs
and mutation registers; `design.provider` is unset in this repo's config.
