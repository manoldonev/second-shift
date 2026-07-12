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
