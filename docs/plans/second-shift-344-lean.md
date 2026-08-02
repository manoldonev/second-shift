# #344 — promote the lean lane to default; deprecate the staged run

Child of the block-decomposition epic (#343). Mechanical scope: routing, descriptions,
and deprecation notices; the one behavioral string is the lean claim comment.

## Edit surface

- `plugins/dev-pipeline/skills/run-lean/SKILL.md` — drop EXPERIMENTAL framing from
  frontmatter description and body header; describe the lane as the default.
- `plugins/dev-pipeline/skills/run-lean/lean-gate.sh` — claim comment drops the
  `(experimental)` suffix (markers `run_id:` / `stage: lean-claimed` untouched).
- `scripts/check-lean-chain.sh` — comment header drops the "experimental phase" framing;
  the dogfood-scoping fact and the consumer-CI prohibition stay verbatim in force.
- `plugins/dev-pipeline/.claude-plugin/plugin.json` `description` +
  `.claude-plugin/marketplace.json` dev-pipeline `description` — lean-first, block
  vocabulary. Descriptions only; `version` untouched.
- `plugins/dev-pipeline/skills/run/SKILL.md` — deprecated: kept solely as ablation
  control and rollback lane until the deletion child lands; new work routes
  `/dev-pipeline:run-lean`. Pin policy stated as "the last stage-carrying release", no
  version literal.
- `README.md` + `docs/onboarding.md` — routing updated to the block vocabulary
  (intake → build → review → merge boundary); first-run commands route
  `/dev-pipeline:run-lean`. No skill renamed.

## ACs

- AC-1 (critic — repo-wide grep at review, excluding `docs/plans/` and
  `.claude/pipeline-state/`): no remaining "experimental" qualifier attached to the lean
  lane anywhere — code strings included; the deprecation notice on `run` states the pin
  policy without a version literal. `CHANGELOG.md` is additionally excluded: its entries
  are derived historical release notes and AC-2 forbids editing them.
- AC-2 (oracle — CI): frozen-files gate green — no `version` or `CHANGELOG.md` edits.
- AC-3 (oracle — CI): `lean-gate-selftest.sh` and `check-lean-chain-selftest.sh` green
  after the claim-string edit (both suites match the stage/run-id markers, not the
  suffix — asserted by running them, not assumed).
- AC-4 (critic): PR carries a `Changelog:` trailer; no consumer-identity or
  operator-identity tokens introduced.
- AC-5 (oracle — diff-scoped mutation sweep): the claim-string edit creates or removes
  no mutation sites in `lean-gate.sh`; ordinals expected unchanged — verified, and
  re-baselined only if the sweep says otherwise.

Open regions: none. A surfaced behavioral coupling is an intent-gap record, not a
silent fix.
