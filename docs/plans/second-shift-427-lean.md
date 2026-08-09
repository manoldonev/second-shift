# second-shift #427 — suites that resolve a cross-plugin path by a fixed hop count

## Problem

Three shipped call sites reach across plugins by counting `..` hops. The count holds only in
this monorepo; from a version-keyed install cache the same expression lands on a directory that
does not exist, and each site degrades differently:

| site | expression | what it does from an install |
| --- | --- | --- |
| `plugins/review-toolkit/scripts/check-emit-deadline.sh` | `REPO="$HERE/../../.."`, then `"$REPO"/plugins/*/agents` | resolves to the cache root, which has no `plugins/` — **zero** agents linted, so `check-emit-deadline-selftest.sh`'s live-tree assertions (B1/B2/B4/B5) fail |
| `plugins/second-shift/skills/doctor/tools/doctor-selftest.sh` (review-toolkit) | `$HERE/../../../../review-toolkit` | unresolved, so the "resolved" context-coverage scenario degrades into the unresolved one and **fails** |
| `plugins/second-shift/skills/doctor/tools/doctor-selftest.sh` (claims-lint) | `$HERE/../../../../dev-pipeline/skills/run/tools/claims-lint.sh` | unresolved, and the `if [[ -f ]]` else-branch prints `claims-lint scenarios skipped` — an **uncounted, non-failing** print. Fixing only the review-toolkit site turns the suite green while these scenarios stay vacuous |
| `plugins/dev-pipeline/skills/run/tools/preflight-selftest.sh:38` | `$SCRIPT_DIR/../../../../review-toolkit` | `SECOND_SHIFT_REVIEW_TOOLKIT_ROOT` lands empty, so `preflight.sh:144-147` falls through to its `claude plugin list` rung instead of the env override the selftest means to exercise |

All three carry a row in `tools/install-topology-known-red.tsv`; draining those rows is the
observable outcome.

The fix belongs in the production lint for the first site. `check-emit-deadline.sh` does take
explicit roots when `$# -gt 0`, but the selftest's live-tree cases invoke it with **no args**
precisely to exercise the resolution branch — passing roots from the selftest would delete the
coverage rather than fix the defect.

## Approach

Two shapes, picked by what each call site needs — both running the house ladder
(monorepo path → cache sibling at this plugin's own version → newest cache version carrying the
marker):

- **Named-sibling resolution** (`doctor-selftest.sh` → review-toolkit and → `claims-lint.sh`;
  `preflight-selftest.sh` → review-toolkit). Reference implementations:
  `resolve_sibling_plugin_root()` in `plugins/review-toolkit/scripts/check-model-tiers.sh` for a
  plugin **root**, `resolve_sibling()` in
  `plugins/dev-pipeline/skills/run/tools/pipeline-doctor.sh` for one **named file**.
- **Enumeration** (`check-emit-deadline.sh`), which walks an unbounded set of plugin names rather
  than resolving one known name. Built on the same relative anchors: `check-emit-deadline.sh` and
  `check-model-tiers.sh` sit in the same directory, so that ladder's hop constants transfer
  verbatim. The real layout is `<cache>/<marketplace>/<plugin>/<version>/`, so the anchor is
  already scoped to this plugin's own marketplace and enumerating it cannot reach another
  marketplace's plugins; `tools/install-topology-selftest.sh` stages `<root>/<plugin>/<version>/`,
  the same relative shape.

Hop constants are **re-derived per directory**, not copied (ledger D-6):
`plugins/second-shift/skills/doctor/tools` and `plugins/dev-pipeline/skills/run/tools` each sit
three levels under their plugin root, so their rungs are `../../../../<name>` and
`../../../../../<name>/*/` against `check-model-tiers.sh`'s two and three.

**No skips.** Exit code `77` (the sibling slice's "named, counted skip") is not available here: a
miss is the defect this slice removes. An unresolvable named sibling and a zero-plugin
enumeration each fail loudly — the `claims-lint.sh` else-branch becomes a counted failure through
`doctor-selftest.sh`'s existing `check`/`FAILS` tally (D-7), not an early `exit`.

**Newest-version selection stays lexical**, mirroring both house ladders (`9.0.0` outranks
`10.0.0`). That is a pre-existing latent defect in the code this slice copies; it is mirrored
deliberately and filed separately (D-9).

**Lockstep** (D-3, overriding the issue's stated default): no new `scripts/lockstep-manifest.tsv`
rows. The existing cross-plugin sibling-resolution DROPPED entry is extended to record the new
copies and why none is byte-anchorable — `verbatim` compares an entire marker block, and the
enumeration variant walks an unbounded name set rather than resolving one name, so pinning it
would mean carrying a dead copy of `resolve_sibling_plugin_root`. The enumeration stays local to
`check-emit-deadline.sh` (D-4).

## Acceptance criteria

- **AC-1** — Run from a version-keyed install cache outside any git repository,
  `check-emit-deadline-selftest.sh` passes, including the live-tree assertions that name specific
  agents (B1, B2, B4, B5).
- **AC-2** — `check-emit-deadline.sh` invoked with no args from an install lints a non-zero number
  of agent files, and prints the roots it resolved **to stderr**, leaving stdout byte-identical to
  today so AC-4 stays checkable.
- **AC-3** — Run from the same topology, `doctor-selftest.sh` passes and its claims-lint scenarios
  **execute**. A run in which they take the else-branch fails the suite rather than printing and
  continuing.
- **AC-4** — All three call sites still resolve in this checkout, and the ordinary `*-selftest.sh`
  sweep is unchanged.
- **AC-5** — Mutation obligations are discharged in the same diff: `check-emit-deadline.sh` carries
  the `emit-deadline-ceil` catalog row, and editing a guard re-keys its generic survivor ordinals.
  Re-anchor the catalog row and re-baseline affected rows in `tools/mutation-baseline.tsv`.
- **AC-6** — The three corresponding rows are removed from `tools/install-topology-known-red.tsv`:
  `check-emit-deadline-selftest.sh`, `doctor-selftest.sh`, and `preflight-selftest.sh`.
- **AC-7** — `preflight-selftest.sh:38` resolves its review-toolkit sibling through the same
  root-resolution ladder rather than the fixed `$SCRIPT_DIR/../../../../review-toolkit` hop count,
  so from an install `SECOND_SHIFT_REVIEW_TOOLKIT_ROOT` is populated and `preflight.sh:144-147` is
  exercised through the env override instead of falling through to its `claude plugin list` rung.
  **ENVIRONMENT-DEPENDENT:** the row passes wherever the Claude CLI is installed, so a green local
  `install-topology-selftest.sh` is no evidence the fix works — the removal of its row is
  unverified in the authoring environment by construction.

## Design

Design: none — no `design.provider` is configured for this repo; the change is shell path
resolution with no rendered surface.

## Open regions (from `.claude/pipeline-state/427-ledger.md`)

All three are `reversible-default-and-flag`; the defaults are applied and flagged in the PR body.

- **OR-1** — the preflight fix is not falsifiable here (the row is ENVIRONMENT-DEPENDENT and the
  suite passes wherever the Claude CLI is installed, which is here). Apply the ladder, remove the
  row, flag the removal as unverified in this environment.
- **OR-2** — the new hard-fails red a suite for anyone running it from a partial checkout that
  genuinely lacks the sibling. That is the defect the slice exists to remove; fail loudly and flag
  the behavior change.
- **OR-3** — file follow-ups referencing #421 for the epic's remaining rows: Class-C
  `cost-block-selftest.sh` and the lexical-sort defect shared across every ladder copy.
