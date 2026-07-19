# Plan: verified calibration claims — expiry + declarative probes (#68)

## Context

Maturity-calibration claims (e.g. "no auth system exists yet") are severity waivers living in an additive-only surface: `plugins/review-toolkit/agents/security-reviewer.md` downgrades Criticals to `[Pre-existing]` based on them, and nothing re-checks the prose after the code moves. A stale claim keeps suppressing real findings — the extending.md pocket test failing in effect with no diff to review. This plan adds a fenced, machine-parsed `second-shift-claims` block with a mandatory expiry (`reverify-by`) and an optional declarative probe DSL, enforced by a new plugin-owned lint at the per-run pre-flight.

Intake resolutions binding here (issue #68 intake comment, run `2026-07-14T214240Z-Mac-f75ce716`):

1. Expiry FAIL binds to the **per-run pipeline pre-flight** (new tool invoked alongside `config-lint.sh` / `check-extensions.sh`), and additionally surfaces in the onboarding `preflight.sh` and the second-shift doctor.
2. Scanned surface = fence-tag scan over `.claude/second-shift/**/*.md` (the manifest-recognized set).
3. `reverify-by` v1 is **date-form only** (`YYYY-MM-DD`); an optional `verified-against:` ref is recorded for re-blessing diffs but never drives expiry.
4. Probe applicability: the deepest non-wildcard parent of the probed glob must exist, else `probe-broken` — never a silent pass.
5. The seed-consumer migration is **out of scope** (cross-repo; owning follow-up in that repo).

Expiry × probe matrix (explicit, closing the spec ambiguity): an expired `reverify-by` is a FAIL **regardless of probe outcome**; a passing probe only withholds its own probe WARN — it never suppresses the expiry FAIL and never mints "verified" evidence (output wording: `not-yet-contradicted`).

## Assumptions

- Consumers without `.claude/second-shift/` (or with no claims fences) see byte-for-byte current behavior: the lint exits 0 silently. Missing extension = generic behavior.
- No config keys are added; the fence is opt-in inside already-manifest'd extension files, so `extension-manifest.txt` and `config-lint.sh` need no changes.
- The doctor quiet line evaluates via `claims-lint.sh` resolved from the dev-pipeline install path doctor already computes for config-lint, with a graceful skip when dev-pipeline is not installed — no new cross-plugin dependency class.
- macOS bash 3.2 compatibility required for all new shell (repo convention; `preflight.sh:44`).

## Decision Ledger

| Decision | Choice | Provenance |
| --- | --- | --- |
| Executor binding | Per-run pipeline pre-flight step (0c) + onboarding preflight.sh Section 1 + doctor quiet line | codebase-derived (preflight.sh header declares it the run-once onboarding finish line; the threat is post-onboarding drift) |
| reverify-by form | Date-only in v1; verified-against ref recorded, never compared | codebase-derived (no defined current-version source exists in a consumer repo) |
| Scanned surface | All .claude/second-shift/**/*.md, fence-tag anchored | codebase-derived (extension-manifest.txt bounds the file set; fence is opt-in per spec point 5) |
| Probe grammar | Colon-form verbs; ERE dialect via grep -E; pattern-absent takes an `in <target>` clause | codebase-derived (matches spec DSL text; ERE is the repo shellcheck-era default) |
| Doctor surface | Invoke claims-lint via the doctor-resolved dev-pipeline install path (the section-7 config-lint idiom); graceful skip when dev-pipeline is absent | codebase-derived (doctor.sh already resolves DP_PATH for config-lint — invoke-not-duplicate beats a parallel grep counter) |
| CHANGELOG heading | Entries added under an Unreleased heading; release names the marketplace version | deferred (release-time decision owned by /release) |
| seed-consumer migration boundary | Out of scope for this repo PR; owning follow-up in the consumer repo | codebase-derived (single-repo pipeline; a cross-repo same-PR deliverable is not satisfiable) |

## Affected files

- `plugins/dev-pipeline/skills/run/tools/claims-lint.sh` [NEW] — parser + expiry check + probe DSL executor
- `plugins/dev-pipeline/skills/run/tools/claims-lint-selftest.sh` [NEW] — fixture-driven selftest
- `plugins/dev-pipeline/skills/run/tools/claims-lint-fixtures/` [NEW] — fixture consumer roots (see Test strategy)
- `plugins/dev-pipeline/skills/run/tools/preflight.sh` — invoke claims-lint in Section 1 (config gates)
- `plugins/dev-pipeline/skills/run/SKILL.md` — pre-flight step (0c): claims gate, fail-closed on FAIL
- `plugins/second-shift/skills/doctor/tools/doctor.sh` — quiet summary line (claims count + probe-less slugs)
- `plugins/review-toolkit/agents/security-reviewer.md` — Maturity calibration: claims-block contract pointer; expired claims are not honored for downgrades
- `docs/extension-points.md` — the `second-shift-claims` contract (grammar, matrix, failure classes) under "Authoring the review-context surface"
- `docs/extending.md` — one paragraph tying the mechanism to the additive axiom (adds ways to go red, none to go green)
- `docs/context-model.md` — layer-3 staleness-rule note: severity-downgrading calibration claims carry mandatory expiry
- `plugins/dev-pipeline/.claude-plugin/plugin.json` — 2.2.6 → 2.2.7
- `plugins/second-shift/.claude-plugin/plugin.json` — 1.4.1 → 1.4.2
- `plugins/review-toolkit/.claude-plugin/plugin.json` — 2.1.3 → 2.1.4
- `CHANGELOG.md` — per-plugin entries

## Reuse inventory

- `bad()`/`warn()`/`ok()` accumulator + exit-code-equals-FAILs convention — mirrored from `preflight.sh:72-77` and `doctor.sh:34-37` (grep-verified)
- Fixture + selftest triad shape — `config-lint-selftest.sh` / `config-lint-fixtures/` (grep-verified; `expect_violation` helper pattern reused)
- Repo-root/config resolution idiom — `preflight.sh:52-60` (`SECOND_SHIFT_REPO_ROOT` env seam; reused so the selftest can point the tool at fixture roots)
- `check-extensions.sh` invocation shape at SKILL.md pre-flight step (0b) — the (0c) step mirrors it
- No new helpers beyond the one tool; none of the parsing is generalized ahead of need

## Implementation steps

1. **`claims-lint.sh`** [NEW]. Contract:
   - Usage `claims-lint.sh [consumer-repo-root]` (default `.`); env seams `SECOND_SHIFT_CLAIMS_TODAY` (ISO date override, selftest determinism) and `SECOND_SHIFT_REPO_ROOT`-style root arg as above. Exit code = number of FAILs. Prefix `[claims-lint]`.
   - Scan `<root>/.claude/second-shift/**/*.md` for ` ```second-shift-claims ` fences (awk fence extractor). No dir / no fences → exit 0, silent.
   - Strict grammar, fail-closed: entries start `- id: <slug>` (`[a-z0-9][a-z0-9-]*`); keys `claim:` (required), `reverify-by:` (required, `YYYY-MM-DD` only), `verified-against:` (optional ref token), `probe:` (optional DSL). Trailing `# comment` stripped. Unknown key, unknown probe verb, or unparseable line → FAIL `claims-parse-error` naming file + line. A `reverify-by` that is not a date (e.g. `v2.3.0`) → FAIL with a "date-form only" message.
   - Probe DSL (never eval; args are only ever used as literal `compgen -G` patterns, literal `grep -E --` patterns, or paths): `path-exists:<glob>`, `path-absent:<glob>`, `pattern-absent:<ere> in <target>` (ERE may be double-quoted). Glob args reject shell metacharacters (`; & | $ backtick backslash`); the ERE arg is exempt from the `|` reject (alternation) since it is passed as a single non-interpreted argument.
   - Applicability: deepest non-wildcard parent of the glob/target must exist, else `probe-broken` WARN (`probe target vanished`). `path-exists` failing (root present, glob unmatched) / `path-absent` matching / `pattern-absent` matching → loud named WARN with the fixed remediation line: re-verify the claim against the code and edit the prose; extending reverify-by without a prose change is an audit smell.
   - Expiry: `reverify-by < TODAY` → FAIL naming the claim id, regardless of probe outcome (the matrix above).
   - Passing probes report `not-yet-contradicted`; the word "verified" never appears in any output line (the `verified-against` key is parsed but not echoed).
   - Summary line: total claims, expired count, probe warnings, probe-less slugs (the ONE quiet line; probe-less claims are never per-claim nagged).
2. **Fixtures** [NEW] under `claims-lint-fixtures/`, each a mini consumer root with `.claude/second-shift/review-context.md` (+ probe target trees where needed): `passing/`, `expired/`, `expired-with-passing-probe/`, `missing-reverify/`, `version-form/`, `probe-failing/`, `probe-broken/` (vanished parent), `injection/` (arbitrary command strings as probes), `parse-error/` (unknown key).
3. **`claims-lint-selftest.sh`** [NEW], mirroring `config-lint-selftest.sh`: pins `SECOND_SHIFT_CLAIMS_TODAY`, asserts per fixture — (a) `expired/` exits nonzero naming the id; matrix: `expired-with-passing-probe/` still FAILs; (b) `probe-failing/` exits 0 with WARN containing the remediation text; (c) `probe-broken/` exits 0 with `probe-broken`/`vanished` wording and without pass wording for that probe; (d) `passing/` exits 0 and output contains no case-insensitive "verified"; `injection/` + `version-form/` + `missing-reverify/` + `parse-error/` exit nonzero with the expected messages.
4. **Wire `preflight.sh`**: Section 1 (config gates) gains a claims-lint invocation after `check-extensions.sh` — rc>0 → `bad` with tail lines into the report; rc=0 → `ok` with the summary line (WARNs ride through to the report).
5. **Wire the per-run gate**: dev-pipeline `SKILL.md` pre-flight gains step (0c) invoking `claims-lint.sh .` fail-closed (mirrors step (0b) shape); WARN-only outcomes proceed. Brief prose: what FAILs (expired / parse), what WARNs (failing or broken probes).
6. **Doctor quiet line**: `doctor.sh` invokes `claims-lint.sh` via its already-resolved dev-pipeline install path (the section-7 config-lint idiom) — when claims exist, one summary line (claim count + probe-less slugs), FAIL on expired/malformed, graceful skip when dev-pipeline is absent. `doctor-selftest.sh` gains two scenarios (quiet line + expired FAIL) using the real claims-lint copied into the fake install tree.
7. **`security-reviewer.md` pointer**: in Maturity calibration, add that severity-downgrading calibration claims are expected in the `second-shift-claims` block with an unexpired `reverify-by`; a claim past its expiry is not honored for `[Pre-existing]` downgrades (treat as absent — enforcement lives in the pre-flight lint). Additive; severity floors untouched.
8. **Docs**: `extension-points.md` — the block contract (grammar, matrix table, failure classes, quiet-surface rule, dual-target note: probes evaluate in the declaring repo, cross-repo claims expiry-only); `extending.md` — one axiom paragraph; `context-model.md` — one staleness-rule sentence for calibration claims.
9. **Versions + CHANGELOG**: bump the three plugin.json versions (re-derive latest from main at commit time); add per-plugin entries under an Unreleased heading.

## Test strategy

Verify-after (shell tooling + docs; no runtime app surface). The selftest suite is the behavior spec:

- Acceptance (a)–(d) map 1:1 to fixtures in step 2/3 (expired FAIL naming id; failing-probe WARN with remediation; vanished-root `probe-broken` not pass; passing probe with no "verified" wording).
- DSL injection rejection: `injection/` fixture asserts arbitrary command strings (`test -z "$(...)"`, `bash -c`, `rm -rf`) are parse FAILs.
- Matrix regression: `expired-with-passing-probe/` guards the sharpest spec ambiguity.
- Existing suites must stay green: `preflight-selftest.sh` (zero-write suite — the new invocation is read-only), `doctor-selftest.sh`, full `*-selftest.sh` sweep.

Unit-test surface: not applicable — no `unitTestScope` configured for this repo (shell/markdown plugin repo); mutation gate skips.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |

(The Stage-1 snapshot carries no AC IDs — the issue heading is `## Acceptance`, which does not match the normative `/acceptance criteria/i` derivation rule. Acceptance items are covered as scope items in Test strategy above.)

## Verification commands

```bash
# targeted
bash plugins/dev-pipeline/skills/run/tools/claims-lint-selftest.sh
bash plugins/dev-pipeline/skills/run/tools/preflight-selftest.sh
bash plugins/second-shift/skills/doctor/tools/doctor-selftest.sh
# repo lanes (config truth table)
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
# json validity
jq . plugins/dev-pipeline/.claude-plugin/plugin.json plugins/second-shift/.claude-plugin/plugin.json plugins/review-toolkit/.claude-plugin/plugin.json > /dev/null
```

## Risks

- **Fence parsing inside arbitrary markdown**: nested fences or ````-quoted examples in consumer docs could confuse the extractor. Mitigation: the awk extractor keys on exact ```` ```second-shift-claims ```` open and ```` ``` ```` close at line start; the `parse-error/` fixture covers a malformed block. Docs examples in THIS repo use four-backtick outer fences (as the issue body does) so the shipped docs never match the scanner.
- **False FAILs blocking runs** (an expired claim halts every pipeline run in that consumer): intended behavior per spec (self-imposed deadline, near-zero false positives); remediation is a one-line prose edit. Called out in extension-points.md.
- **Selftest sweep runtime**: one more selftest in the `test` lane; keep fixtures tiny.
- Rollback: revert the single PR; no config keys, no state-schema fields, no migrations.

## Out-of-scope

- seed-consumer migration (ids + reverify-by + headline rewording) — owning follow-up in the consumer repo (cross-repo; intake decision 5).
- Onboard scaffolding of probes (issue #67 catalog/scaffold territory; the issue itself says onboard never scaffolds probes).
- Version-form (`reverify-by: v2.3.0`) expiry comparison — deferred until a defined current-version source exists; v1 rejects it with a clear message.
- Any staleness pass over `.claude/second-shift/` by Stage-7 doc-update (this mechanism is the independent guard; doc-update scope unchanged).
