# Config migrations

`.claude/second-shift.config.json` is the marketplace's public API; `configVersion` is its
version. The contract:

- A schema-**breaking** change ⇒ major release tag + `configVersion` bump + a migration doc
  here named `vN-to-vN+1.md` (exact field-by-field: what moved, what to write instead, a
  before/after example).
- `config-lint` fails older configs WITH the pointer to that doc (never a bare "invalid") —
  a consumer's upgrade PR reviews itself. Newer-than-understood configs point at
  `docs/releasing.md` (upgrade the marketplace pin).
- Additive, non-breaking schema changes do NOT bump configVersion (unknown-key strictness
  means consumers adopt them by choice at their pinned ref).

**Honest history:** v2.0.0 predates this contract and shipped breaking key removals
(`gates.figma`, `gates.apiTests`) on `configVersion: 1` — [`v1-to-v2.md`](v1-to-v2.md)
documents that migration retroactively, and config-lint special-cases both removed keys
with pointers to it. From the release that ships this contract on, the rule binds:
breaking ⇒ major tag + configVersion bump + migration doc, before the tag.

**One filename, two namespaces.** The marketplace version and `configVersion` are numbered
independently, and both crossed their 1 → 2 boundary — while the gate derives the migration
filename from `configVersion` alone. So [`v1-to-v2.md`](v1-to-v2.md) carries **both**
migrations under explicit part headings: part 1 the retroactive marketplace-v2.0.0 key
removals, part 2 the `configVersion` 1 → 2 retirement of the `planFilePattern` slice token.
Later `vN-to-vN+1.md` docs are configVersion-only; this collision is not expected to recur.

## Breaking changes that are not config changes

These leave `configVersion` alone, so config-lint cannot point at them, and a stale copy in your
repo is not reported by any tool. Each is also in that release's `CHANGELOG.md` entry.

- **v13.0.0** — the pipeline's scripts were renamed (`lean-gate.sh` → `milestone-gate.sh`,
  `lean-evidence.sh` → `boundary-evidence.sh`, `lean-reconcile.sh` → `reconcile.sh`,
  `orchestrate-lean.sh` → `orchestrate.sh`) and the `/dev-pipeline:*-lean` skill aliases were
  removed; use `/dev-pipeline:run`, `:build` and `:review`. If you carry the CI workflow,
  re-copy `plugins/second-shift/templates/consumer/second-shift-ci-check.sh` into
  `.claude/tools/` — an older copy fetches `lean-evidence.sh` and reds every PR once the pin moves.
- **v14.0.0** — the retired spellings stopped resolving, **silently**: export `LANE_*` instead
  of any `LEAN_*` knob, rename `.claude/lean-overrides.tsv` to `.claude/lane-overrides.tsv`, and
  export `SECOND_SHIFT_BOUNDARY_EVIDENCE` instead of `SECOND_SHIFT_LEAN_EVIDENCE`. A leftover old
  spelling is ignored, so a run proceeds without the override rather than failing.
- **Next major** — intent-gap records carry `decided_by:` (`user-answered` or `user-delegated`).
  A record that has only the legacy `ratified: yes` + `ratified_by:` pair still counts as decided
  until then; add `decided_by:` to any open one before bumping.
