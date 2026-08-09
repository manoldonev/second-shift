# second-shift #450 — a re-onboard must not silently destroy a human-authored config value

Issue: #450 · lane: run-lean · pre-flight ledger: `.claude/pipeline-state/450-ledger.md` (binding)

## Problem

Onboard's Step 0 promises diff mode on a re-onboard — "present changes against the existing
values" — and Step 3's key contract overrides it unconditionally: `testFile` and
`unitTestScope` are emitted **always as explicit `null`**. `always` beats the diff intent.
Those two keys are exactly the ones a human sets when adopting the mutation gate, so a
re-onboard silently reverts the adoption:

```diff
-      "testFile": "yarn test {file}",
-      "unitTestScope": "src/**",
+      "testFile": null,
+      "unitTestScope": null,
```

`unitTestScope: null` is a legal "no mutation surface", so Stage 5 prints `gate OFF` and
proceeds and `config-lint` passes. The gate stayed off across many runs until a manual audit.

## Shape

The ticket names a blocker — no discriminator exists for "human-authored". The ledger (D-1)
retires the framing rather than answering it: protect **every** existing non-null value by
diffing the committed config against the draft onboard is about to write. A value the draft
reproduces identically yields no delta, so the generality costs nothing.

Two halves (D-2): the Step-3 key contract is fixed at source so the common case stops firing,
and a new sibling tool is the mechanical backstop so a prose fix cannot be overridden again.

## Acceptance Criteria

**AC-1 — guard contract.** New tool
`plugins/second-shift/skills/onboard/tools/config-diff-guard.sh`, invoked as

```
config-diff-guard.sh <existing-config.json> <draft-config.json> [--ack <path>]...
```

It takes **no repo root and reads no tree** — pure document comparison (D-3). It writes ONE
JSON document to stdout with exactly three arrays:

- `deltas[]` — each `{ path, kind, existing, draft, evidence, proposal }`. `path` is the dotted
  config path (`commands.web.testFile`), `kind` is `removed` or `changed`, `existing` and
  `draft` are the JSON values found, and `evidence` / `proposal` are rendered sentences so the
  caller composes a blocking line without re-deriving one.
- `acknowledged[]` — the dotted paths suppressed by an `--ack` this run. Suppression is
  auditable rather than invisible; OR-2 is the reason it is listed rather than merely applied.
- `unmatchedAcks[]` — `--ack` paths that matched no delta. Informational, never blocking: a
  mistyped ack cannot let a real delta through (that delta stays in `deltas[]`), but it does
  leave the caller believing it dispositioned something, so the guard says so.

Deltas are data — the script exits **0** whether or not it emitted any, so the caller does not
treat a delta as a crash. Usage/IO errors — wrong argument count, a missing file, a file on
either side that is not JSON *or is JSON that is not an object*, `--ack` with no value, an
unknown option — exit **3** with a message on stderr,
matching `config-grill.sh:33-38`. An unreadable *existing* config is specifically an exit 3
and never a silent skip (D-10): diff mode is impossible against a document Step 0 could not
load, so skipping would disable the guard exactly when the config is already damaged.

bash 3.2 compatible, read-only, no network.

**AC-2 — the comparison rule.** The guard walks the **existing** document (D-5):

| Existing value at a path | Treatment |
| --- | --- |
| object | descend into its keys |
| array | a leaf — compared as a whole subtree by deep equality, never descended |
| scalar (string / number / boolean) | a leaf — compared by equality |
| `null` | skipped — there is nothing to destroy (D-1 protects non-null values) |

Arrays are whole units because `commands.<id>.lanes`, `extraLanes` and `reviewers.add` are
arrays of objects: index-level paths would report a cascade of shifted elements on a single
insertion, and that noise trains the human to ack blindly.

Classification of a protected leaf at path `P` with existing value `E`:

| Draft at `P` | `kind` |
| --- | --- |
| path absent | `removed` |
| `null` | `removed` — the key survives and the value does not; this is the motivating evidence |
| present, differs from `E` | `changed` |
| present, deep-equals `E` | no delta |

**Draft-only paths are never reported** — an addition destroys nothing.

`$schema` is excluded (D-5): Step 4 rewrites it to the pinned ref on every run, so a
pin-upgrade re-onboard would otherwise fire a delta every single time. It is the only
exclusion; a closed protected-key set is explicitly *not* the mechanism (D-1).

A dotted path is ambiguous for a config key containing a literal `.`. The guard documents
this in its header rather than escaping it: repo ids come from a package.json short name or a
directory basename, both dot-free in practice, and an escaping scheme would have to be typed
correctly into `--ack` by the caller to buy anything.

**AC-3 — the ack channel.** `--ack <path>` is repeatable and exact, with no wildcards (D-4).
A delta whose `path` equals an acked path is suppressed from `deltas[]` and listed in
`acknowledged[]`. Acks are **per-run only** — the guard writes nothing, and no config key is
introduced.

`grillWaivers` is deliberately not reused: it is permanent config state for a one-time event,
so waiving this path would silence the guard for it on every future re-onboard and the second
accidental destruction of the same key would go through silently.

**AC-4 — Step-3 key contract gains its diff-mode clause.** `onboard/SKILL.md`'s
`commands.<repo>` bullet (currently "`testFile`, `unitTestScope` **always** as explicit
`null`") states that on a RE-onboard (Step 0 diff mode) both keys are **carried forward from
the existing config**, and are `null` only where they were already `null`. This is the fix at
source: without it the guard fires a blocking delta on every re-onboard of every mutation-gate
adopter, forever, and a predicate that always fires is one the human learns to clear blindly.

**AC-5 — onboard runs the guard, as a hard accept predicate.** `onboard/SKILL.md` Step 3, in
the same block that already materializes the draft to a temp file for `config-grill.sh`, runs
the guard on `(existing config, that same temp draft)` **when and only when Step 0 found an
existing config**. On a fresh onboard there is nothing to diff and the guard is not run.

Each `deltas[]` entry renders as a **blocking line** at the top of the accept-or-edit screen,
alongside the grill's findings; `unmatchedAcks[]` renders informationally and never blocks.
The guard re-runs on each loop iteration, and "no unacknowledged deltas" joins "no unwaived
findings" as the accept predicate. A delta is cleared by fixing the draft or by the human
confirming the removal, after which onboard re-runs with `--ack <path>` for that one path.

This adds no question batch and no new surface: disposition is captured by the human editing
the screen they are already editing, so Step 3's "at most one AskUserQuestion batch" rule and
its "a diff review of a 90%-correct document, not a wizard" framing stay unamended.

**AC-6 — tests.** `plugins/second-shift/skills/onboard/tools/config-diff-guard-selftest.sh`
(discovered by the CI glob, no registration; fixtures are two JSON documents, per D-9) covers:

- each `kind` row of the AC-2 classification table — draft-absent, draft-null, draft-differs,
  draft-identical — including the motivating `testFile`/`unitTestScope` reversion;
- each treatment row of the AC-2 walk table: a nested object descended to its scalar leaves; an
  array compared whole (a changed element reports the array's own path, once, and never an
  index path); an existing `null` leaf skipped even when the draft sets a value there;
- draft-only paths absent from `deltas[]`;
- `$schema` differing on both sides emitting no delta, and — the case that proves the exclusion
  is scoped rather than blanket — a *sibling* key changing under the same document still firing;
- `--ack` suppression: one acked path drops out while an unacked sibling delta remains; a
  repeated `--ack` suppressing two; `acknowledged[]` listing what was suppressed; an ack
  matching nothing landing in `unmatchedAcks[]` and leaving `deltas[]` untouched;
- an ack path that is a *prefix* of a real delta path clearing nothing — the "exact, no
  wildcards" half of AC-3, which a suppression-only test cannot distinguish from a bug;
- exit 0 with deltas present, exit 0 with none, and exit 3 for each usage/IO shape: no
  arguments, one argument, a third positional, missing existing file, missing draft file,
  non-JSON existing, non-JSON draft, valid JSON that is not an object, `--ack` with no value,
  and an unknown option.

## Open regions (from the ledger, unchanged)

OR-1 first-run delta volume on a real adopted config is unmeasured — fixture-green is not
corpus-green, and detection drift on `lint`/`test`/`format` is normal over months. AC-4 is the
mitigation that keeps the common case at zero deltas; if the count is still high the blocking
predicate becomes ack-spam. · OR-2 the ack channel's trust boundary: `--ack` is typed by the
agent, not the human, and nothing mechanically proves a human authorized each acknowledgment.
`acknowledged[]` (AC-1) makes the suppression visible; no mechanism available at the
accept-or-edit screen closes it.

## Out of scope

Doctor gains nothing (D-6) — it never rewrites a config, so there is nothing for it to destroy;
`doctor.sh:353` keeps invoking `config-grill.sh` only. No `configVersion` bump and no migration
doc (D-7): this adds no config key at all — the ack channel is a CLI flag — and
`schema/second-shift.config.schema.json` is untouched. No independent guard for AC-4's prose
half (D-8): `CLAUDE.md` bans prose-presence greps, and the AC-1 tool is itself the detector —
if the carry-forward regresses, every re-onboard of a mutation-gate adopter fires a blocking
delta, so the failure is loud rather than silent. Trigger 1 of #441's OR-3 is filed as #449 and
is not touched here.
