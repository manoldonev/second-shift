# #877 — config-grill fails consumers on a mutation sweep no repo runs

`config-grill.sh`'s trigger 4 (`T4.mutation-plumbing.<repo>`, a `findings[]` FAIL) and trigger 1
(`T1.mutation-sweep.<repo>`, the grill's *only* `unadopted[]` producer) both grade a repo's
config against `tools/mutation-sweep.sh` — a file no second-shift gate has executed since #580.
Three of five consumer clones FAIL `/second-shift:doctor` and block `/second-shift:onboard`'s
accept-or-edit screen on T4 for a capability none of them run; one maintainer hand-wrote a
`grillWaivers` entry to get past it. Since T1 is the `unadopted[]` channel's only producer,
retiring it retires the whole channel, not just one row in it.

## Acceptance criteria

- **AC-1** — `config-grill.sh` no longer emits `T4.mutation-plumbing.*` or `T1.mutation-sweep.*`.
  With T1 gone the `unadopted[]` channel has no producer left, so it is retired with it:
  `add_unadopted`, the `UNADOPTED` array, and the `unadopted` key in the JSON envelope (header
  comment included) are removed — the output shape becomes `{findings, notEvaluated}`.
  `gates.mutation` is read by nothing in the file. `T4.design-liverender` (trigger 4's other
  occupant) is unchanged. The `MUT_STATE`/`SWEEP_REL`/`HAS_SWEEP`/`TEST_CMD` plumbing that
  existed only to serve the two retired checks is deleted with them.
- **AC-2** — `doctor.sh`'s unadopted-rendering block (the `unadopted` comment paragraph and the
  note-rendering loop reading `.unadopted[]`) is removed; it renders only `findings[]` (FAIL) and
  `notEvaluated[]` (note) from the grill's output.
- **AC-3** — `onboard/SKILL.md` drops the `unadopted[]`-blocking rule (evidence/proposal
  rendering, the "adopt arm unreachable" note) and simplifies the accept predicate to "no
  unwaived `findings[]`" (dropping "and no unwaived `unadopted[]`"). Its "gates to enable"
  mutation-intent elicitation question (question 4 of the batch) is removed outright, not
  trimmed — the question's premise was declaring intent for something to grade, and nothing
  grades it any more; a shorter version asking the same thing for no detectable reason is the
  same dead prose. Subsequent questions renumber.
- **AC-4** — `config-grill-selftest.sh` drops every case asserting `T4.mutation-plumbing.*` or
  `T1.mutation-sweep.*` (the `mut-absent`/`mut-true`/`mut-retired-key`/`mut-false` block, the
  "durable mutation-seam advisory" / both-tiers-independence block, and the now-meaningless
  `unadopted[]`-shape assertions including the two `T1.extension-points`-is-really-gone checks,
  since the envelope no longer has an `unadopted` key for them to query). The envelope-shape
  assertion at the end of the file drops from three arrays to two. The multi-repo scoping case
  (proving a per-repo check id fires for the evaluated repo and not its sibling) is re-vehicled
  onto `T5.missing-script.<repo>.<slot>` — the only other `findings[]` producer keyed on
  `$REPO_ID` — rather than deleted. One new case is added: a config that waives both retired ids
  (`T4.mutation-plumbing.<repo>` and `T1.mutation-sweep.<repo>`) produces no error and no finding
  (pins AC-6).
- **AC-5** — `doctor-selftest.sh` drops `grill-unadopted` and `grill-unadopted-waived` (no
  producer survives to exercise them) and their `config-t1-waived.json` fixture. `grill-finding`
  / `grill-waived` are re-vehicled onto `T4.design-liverender`: it is the only remaining
  `findings[]` check that fires unconditionally on the fixture's non-git root once
  `design.provider` is set with no `liveRender` (its own "outside a readable work tree the probe
  cannot speak, and the finding stands" branch). `config-grill-finding.json` gains
  `design.provider` with no waiver (fires); `config-valid.json`'s baseline waiver moves from
  `T4.mutation-plumbing.app` to `T4.design-liverender` so `grill-waived` keeps proving
  suppression, not just "nothing ever fired".
- **AC-6** — Existing `grillWaivers` entries keyed to `T4.mutation-plumbing.*` /
  `T1.mutation-sweep.*` become inert without being rejected or reported as unknown:
  `config-lint.sh` validates a `grillWaivers` entry's *shape* only (object, non-empty string
  reason), never against a set of known check ids, and `config-grill.sh`'s waiver lookup is a
  bare hash-key test — neither can distinguish a retired id from a live one, so no code changes.
  `config-lint-fixtures/valid-grillwaivers.json` keeps its `T4.mutation-plumbing.app` entry as
  the retired-id-tolerance case on the lint side; AC-4's new case pins it on the grill side.
- **AC-7** — `docs/config-schema.md`'s `gates` row and `grillWaivers` row, and
  `schema/second-shift.config.schema.json`'s `gates.mutation` description, say `gates.mutation`
  is accepted by `config-lint`, read by nothing, and removed from the schema at the next batched
  major (no rejection until then). The `grillWaivers` row drops its `unadopted`-severity
  paragraph (single severity now: finding) and its worked check-id example moves off the two
  retired ids onto a live one (`T5.missing-script.api.lint`). `docs/onboarding.md`'s "Mutation:
  the repo-carried sweep" section is deleted; at most one line survives, stating the same
  accepted/read-by-nothing/removed-at-next-major fact.

## Notes

- Non-breaking (issue's own admission table): removes checks, leaves the config key legal.
  Commit verb `fix(second-shift)` — the affected checks live in the second-shift plugin's
  onboard/doctor skills. `Changelog:` trailer, no version or `CHANGELOG.md` edit (D-9).
- No design section: this repo carries no `design.provider` (D-10).
- Historical/dated references (docs/plans/**, milestone-gate.sh comments, gate-ablation docs,
  capability-parity notes, check-config-shadowing.sh's comment) are left alone (D-6): they are
  records, or they describe the retired *lane*, not the grill checks this PR retires.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Fate of config-grill's `unadopted[]` channel once T1 goes (T1.mutation-sweep is its only producer, `config-grill.sh:476`) | Retire it: remove `add_unadopted`, the `unadopted` key from the grill's JSON output, doctor's NOTE branch (`doctor.sh` ~432-455), the onboard `SKILL.md` rule that blocks on `unadopted[]` (~239-250, including the accept predicate), the `unadopted` wording in the `grillWaivers` row of `docs/config-schema.md` and the schema's `grillWaivers` description, and doctor-selftest's `grill-unadopted` scenario plus the `config-t1-waived.json` fixture | user-answered |
| D-2 | `docs/onboarding.md` section "Mutation: the repo-carried sweep" (~262-296), which the ticket does not name | Delete the section. At most one line stays: `gates.mutation` is accepted, read by nothing, and removed at the next batched major | user-answered |
| D-3 | `gates.mutation` in config-lint and the schema | config-lint keeps accepting it (`config-lint.sh:235-237` unchanged). The schema description is reworded to say accepted, read by nothing, removed at the next batched major. No rejection until that major — ticket body, "Expected" bullet 2 | codebase-derived |
| D-4 | Tolerance of `grillWaivers` entries keyed to retired ids | Already inert. The grill only does `has($k)` lookups for the ids it emits (`config-grill.sh:57-69`) and never lists waiver keys, and config-lint checks only that each value is a non-empty string (`config-lint.sh:254-265`). `config-lint-fixtures/valid-grillwaivers.json` already carries `T4.mutation-plumbing.app` and lints green, which covers the lint side. Add one grill selftest case: a config that waives `T4.mutation-plumbing.<repo>` and `T1.mutation-sweep.<repo>` produces no error and no finding | codebase-derived |
| D-5 | doctor-selftest `grill-finding` scenario, which today uses T4.mutation-plumbing as its example finding | Re-point it at a surviving finding (`T4.design-liverender` or `T5.missing-script.<repo>.<slot>`), so the doctor FAIL path stays exercised | codebase-derived |
| D-6 | Historical references to the sweep: `docs/plans/**` records, `milestone-gate.sh` comments (~3834, ~5165), `tools/gate-ablation-classes.tsv`, `docs/gate-ablation.md`, the `tools/capability-parity.tsv` note, the `check-config-shadowing.sh:24` comment | Leave them. They are dated records, or they describe the retired lane rather than the grill checks. The `check-config-shadowing.sh` comment stays true because the key stays legal (D-3) | codebase-derived |
| D-7 | Duplicate scan | `dup-scan.sh --issue 877` rc 0, 0 candidates. Nothing to record | codebase-derived |
| D-8 | Which surviving check D-5 re-points `grill-finding`/`grill-waived` at, concretely | `T4.design-liverender`. It is the only remaining `findings[]` check that fires unconditionally on the doctor fixture's plain (non-git, no-`package.json`) root — its "outside a readable work tree the probe cannot speak, and the finding stands" branch fires whenever `design.provider` is set and `liveRender` is absent, needing no git tree or manifest. `T5.missing-script` (D-5's other named option) would need a `package.json` fixture file the doctor scenario setup does not otherwise carry, for no added coverage value. `config-grill-finding.json` gains `design.provider`; `config-valid.json`'s waiver moves from `T4.mutation-plumbing.app` to `T4.design-liverender` so it keeps proving suppression rather than "nothing fired". | codebase-derived |
| D-9 | Commit verb and changelog | `fix(second-shift)`: a shipped behavior (doctor FAIL / onboard block on a capability no consumer runs) is corrected to match reality. `Changelog:` trailer states config-grill no longer grades `gates.mutation` against a mutation sweep no second-shift gate executes, and that the grill's `unadopted[]` severity is retired with its only producer. No version or `CHANGELOG.md` edit (CLAUDE.md: those are release-PR-derived). | codebase-derived |
| D-10 | Design section | Omitted — this repo (second-shift dogfooding itself) carries no `design.provider` in `.claude/second-shift.config.json`, so the armed-vs-disarmed choice does not apply. | codebase-derived |
| D-11 | `config-grill-selftest.sh`'s multi-repo scoping case, which today uses `T4.mutation-plumbing.be`/`.fe` to prove a per-repo id fires only for the evaluated repo | `T4.design-liverender` is not per-repo-suffixed (D-8), so it cannot demonstrate per-repo scoping. Re-vehicle onto `T5.missing-script.<repo>.<slot>` instead: an explicit `commands.<repo>.lint = "npm run lint"` over a `package.json` with no `scripts.lint` reproduces the same "evaluated repo fires, sibling doesn't, sibling reports `topology.<repo>` not-evaluated" shape the deleted case proved. | codebase-derived |
| D-12 | `docs/config-schema.md` `grillWaivers` row's worked check-id example, after both `T4.mutation-plumbing.api` (finding) and `T1.mutation-sweep.<repo>` (unadopted) — its only two prior examples — are retired | Replace with `T5.missing-script.api.lint`, a live per-repo `findings[]` id, so the row's "keyed by check id, with the repo id where the check is per-repo" explanation still has a real worked example. | codebase-derived |
