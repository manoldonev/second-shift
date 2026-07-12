# Plan: feedback channel — issue forms + `/second-shift:doctor --report` (#34)

## Context

For a zero-telemetry project, structured issues ARE the analytics. Every fail-fast abort already
writes its reason to the pipeline state file, so a good feedback report is mostly a matter of
_assembling_ artifacts the toolkit already produces. This issue delivers two halves of one
"feedback channel" feature:

1. **GitHub issue forms** for the three recurring feedback scenarios — "pipeline aborted",
   "config-lint disagreement", "review false positive" — that _require_ the diagnostic evidence
   up front (so a report is actionable the moment it lands).
2. **`/second-shift:doctor --report`** — a new flag on the already-shipped doctor
   (`plugins/second-shift/skills/doctor/tools/doctor.sh`) that assembles the reusable part of that
   evidence (doctor output + `claude plugin list --json` + redacted config + latest pipeline-state
   excerpt) as one paste-ready bundle.

**Gap resolved at intake (see the Stage-1 comment):** the issue body attributes `--report` to
#29, but #29 is **closed** and shipped the doctor skill with **no** `--report` and no argument
parsing at all. So #34 owns building `--report` — the templates and the bundler are one PR.

## Assumptions

- GitHub **issue forms** (YAML, `.github/ISSUE_TEMPLATE/*.yml`) are the right format: only forms can
  mark fields `required: true`; Markdown templates cannot enforce anything, which would silently
  defeat the spec's "requiring …" goal. `.github/ISSUE_TEMPLATE/` does not exist yet.
- The "state-file excerpt" the issue names is the `.failureContext` object `statectl.sh` writes on
  every fail-fast abort (`.claude/pipeline-state/<key>.json`). `--report` surfaces the newest one.
- The config carries **no true secrets today** (the `tracker.bot.app` block is public identifiers —
  clientId/appName/installationId; the private key lives outside the repo). Redaction is therefore
  defensive: strip secret-_shaped_ keys so a future token/secret is never leaked by a paste.
- CI runs the repo test command (`find . -name '*-selftest.sh' … bash {}`) and `shellcheck`
  (`-e SC1091,SC2015,SC2181`). New shell must be shellcheck-clean and dependency-free (no pyyaml,
  no `yq`); a YAML parse in a selftest must be guarded behind `command -v`.

## Decision Ledger

| # | Decision | Provenance | Rationale |
|---|----------|------------|-----------|
| D1 | Issue **forms** (`.yml`), not Markdown templates | codebase-derived | Only forms enforce `required:`; the spec says "requiring". |
| D2 | `--report` is built by **#34** (not #29) | codebase-derived | `doctor.sh` has no `--report`/arg parsing; #29 is closed. |
| D3 | Per-template evidence matrix (fields differ by scenario) | codebase-derived | The three scenarios need different artifacts; a flat 4-field list forces irrelevant attachments. |
| D4 | `--report` **auto-redacts** secret-shaped config keys | codebase-derived | Removes the "who redacts / what" ambiguity; makes the paste safe by construction. |
| D5 | Create 4 repo labels (`feedback` + 3 scenario labels) as an out-of-band setup step | codebase-derived | Forms' `labels:` must reference existing labels; documented in the PR body (not in the diff). |
| D6 | Bundle uses `claude plugin list --json` | codebase-derived | Matches the in-repo convention (doctor SKILL.md L17). |

## Affected files

- `.github/ISSUE_TEMPLATE/config.yml` — **[NEW]** chooser config (`blank_issues_enabled`, contact link to docs).
- `.github/ISSUE_TEMPLATE/pipeline-aborted.yml` — **[NEW]** issue form.
- `.github/ISSUE_TEMPLATE/config-lint-disagreement.yml` — **[NEW]** issue form.
- `.github/ISSUE_TEMPLATE/review-false-positive.yml` — **[NEW]** issue form.
- `plugins/second-shift/skills/doctor/tools/doctor.sh` — add arg parsing + `--report` bundle assembler + `redact_config()` + `state_excerpt()`.
- `plugins/second-shift/skills/doctor/SKILL.md` — document the `--report` invocation + when to use it.
- `plugins/second-shift/skills/doctor/tools/doctor-selftest.sh` — add `--report` scenarios (bundle sections present; secret redacted; non-secret identifiers preserved; exit 0).
- `plugins/second-shift/skills/doctor/tools/doctor-fixtures/config-with-secret.json` — **[NEW]** fixture with a secret-shaped key to prove redaction.
- `tests/issue-forms-selftest.sh` — **[NEW]** dependency-free structural validator for the three forms (grep-based; optional `ruby -ryaml` parse when present).
- `CHANGELOG.md` — Unreleased entry.

## Reuse inventory

- `ok()/warn()/bad()` FAIL/WARN/OK harness in `doctor.sh:18-20` — the report's "doctor output"
  section reuses it verbatim by capturing a nested `bash "$0"` (no-flag) run; no new formatter.
- The data-source resolution in `doctor.sh:34-41` (`DOCTOR_PLUGIN_LIST_FILE` injection else
  `claude plugin list --json`) — the report reuses the same pattern for its plugin-list section,
  which also keeps the new scenarios hermetic in the selftest.
- The `scenario()`/`check()` helpers in `doctor-selftest.sh:8-27` — the `--report` tests extend the
  same env-injection harness (add a thin `report()` helper that calls `bash "$DOCTOR" --report`).
- `jq walk(...)` for the redactor (jq is already a hard doctor dependency, `doctor.sh:23-24`).
- New helpers introduced: `redact_config()`, `state_excerpt()`, `emit_report()` in `doctor.sh`
  (**[NEW]** — no existing equivalents; grep for `redact`/`report`/`failureContext` in the doctor
  tree returned nothing).

## Implementation steps

1. **`doctor.sh` arg parsing.** Immediately after `set -uo pipefail` (L9), add a `while`/`case`
   loop setting `REPORT_MODE`; accept `--report`, `-h|--help` (usage), reject unknown with rc=2.
   Default `REPORT_MODE=0` preserves today's zero-arg behavior exactly.
2. **`doctor.sh` report block.** After the `ok/warn/bad` defs (L20), guard `if [[ $REPORT_MODE -eq 1 ]]; then emit_report; exit 0; fi` so the report path never falls through to the gating checks.
   - `emit_report()` prints a titled bundle with four fenced sections:
     - **doctor output** — captured `DOCTOR_OUT="$(bash "$0" 2>&1)"` (child runs the normal checks; `REPORT_MODE` unset in the child ⇒ no recursion; inherits `DOCTOR_*` env injections).
     - **`claude plugin list --json`** — reuse the L34-35 source resolution (`DOCTOR_PLUGIN_LIST_FILE` else live).
     - **redacted config** — `redact_config` over `$ROOT/.claude/second-shift.config.json` (compute `CONF` locally in the block; the file-level `CONF` is defined later at L150).
     - **pipeline-state excerpt** — `state_excerpt`: newest `$ROOT/.claude/pipeline-state/*.json` → `{ticketKey,status,currentStage,failureContext}` via jq; literal "no pipeline runs recorded" when the dir/glob is empty.
   - `redact_config()`: `jq 'walk(if type=="object" then with_entries(if (.key|test("(?i)(^|_)(secret|token|password|passwd|privatekey|apikey|clientsecret|pem)$|secret|token|password|privatekey|apikey|clientsecret")) then .value="***REDACTED***" else . end) else . end)'`. Non-secret identifiers (`clientId`, `appName`, `installationId`) are intentionally **not** matched.
3. **`SKILL.md`.** Add a short section: `bash "${CLAUDE_PLUGIN_ROOT}/skills/doctor/tools/doctor.sh" --report` assembles a paste-ready bundle for a feedback issue; point at the three issue forms.
4. **Issue forms.** Author the three `.yml` forms + `config.yml` per the field matrix (Test strategy). Each form: `name`, `description`, `title` prefix, `labels`, and `body[]` with `markdown` intro + `required` textareas for its evidence. All three require the `--report` bundle field.
5. **`config-with-secret.json` fixture** — copy `config-valid.json`, add `tracker.bot.app.clientSecret: "SUPER_SECRET_VALUE"` (secret-shaped) alongside a non-secret `installationId`.
6. **`doctor-selftest.sh`** — add a `report()` helper + scenarios: (a) `--report` exit 0 and output contains the four section headers + a "summary:" line from the nested run; (b) redaction: with the secret fixture, `***REDACTED***` present, `SUPER_SECRET_VALUE` absent, `installationId` value still present.
7. **`tests/issue-forms-selftest.sh`** — for each of the three forms assert: parses (`ruby -ryaml` when present, else skip-with-note), has `name:`/`description:`/`body:`, at least one `required: true`, and the `--report` evidence field label is present. Exit code = failure count.
8. **Create labels** (out-of-band, D5): `feedback`, `pipeline-abort`, `config-lint-disagreement`, `review-false-positive` via the bot wrapper. Document in the PR body.
9. **CHANGELOG** Unreleased entry.

## Test strategy

Verify-after (infra/tooling + static templates; no `apps/api` behavior surface — see Unit test surface). New behavior (`--report`) is covered by the doctor selftest; templates by a structural selftest.

**Per-template evidence matrix** (D3 — each form's required fields):

| Form | Required fields |
|------|-----------------|
| `pipeline-aborted` | (1) what happened; (2) **state-file excerpt** (`.failureContext` from `.claude/pipeline-state/<key>.json`); (3) **`/second-shift:doctor --report` output** (covers plugin list + redacted config + doctor output); (4) issue/PR link + run_id |
| `config-lint-disagreement` | (1) the config-lint message disputed; (2) what you expected; (3) **`--report` output** (its redacted-config + config-lint section carry the evidence) |
| `review-false-positive` | (1) the reviewer finding disputed (verbatim); (2) code under dispute (file:line / PR link); (3) why it's a false positive; (4) **`--report` output** (env context) |

**Doctor `--report` selftest scenarios** (extend `doctor-selftest.sh`):
- `report-sections` — `--report` rc 0; output contains "doctor output", "plugin list", "redacted config", "pipeline-state", and a "summary:" line proving the nested check run executed.
- `report-redaction` — with `config-with-secret.json`: `***REDACTED***` present, `SUPER_SECRET_VALUE` absent, `installationId` value preserved.

**Issue-forms selftest** (`tests/issue-forms-selftest.sh`): parse + structural asserts as in step 7.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
|-------|-------------------|---------|---------|
| AC-1 | Three issue forms offered on New Issue | 4 | `tests/issue-forms-selftest.sh` (files exist + parse) |
| AC-2 | Each form marks its evidence fields `required` | 4 | `tests/issue-forms-selftest.sh` (`required: true` present) |
| AC-3 | `--report` assembles the 4-part bundle in one command | 1,2 | `doctor-selftest.sh` `report-sections` (AC-3) |
| AC-4 | `--report` redacts secret-shaped config values | 2,5 | `doctor-selftest.sh` `report-redaction` (AC-4) |
| AC-5 | SKILL.md documents `--report`; selftest covers it | 3,6 | `doctor-selftest.sh` (both scenarios) + doc review |

## Verification commands

```bash
# in the worktree root
bash plugins/second-shift/skills/doctor/tools/doctor-selftest.sh
bash tests/issue-forms-selftest.sh
# full repo gate (what CI runs):
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
# behavior smoke: real bundle against this repo
bash plugins/second-shift/skills/doctor/tools/doctor.sh --report | sed -n '1,40p'
```

## Risks / rollback notes

- **Nested `bash "$0"` capture** could recurse if the child ever saw `--report`; it doesn't (the
  child is invoked with no args). Guarded by the `report()` selftest asserting a single "summary:".
- **Redaction false-negative** (a future sensitive key not matched) would leak on paste. Mitigated
  by a broad case-insensitive key regex; documented as best-effort in SKILL.md; the config has no
  real secret today.
- **Label creation is out-of-band** (not in the diff). If skipped, forms still create issues but
  the declared labels are simply not applied — non-fatal. Rollback: delete the four `.yml` files +
  revert `doctor.sh`; the labels are harmless if left.
- Unverified references: none.

## Out-of-scope

- Changing `#29`'s doctor check logic or exit-code contract (report mode is additive; zero-arg
  behavior is byte-for-byte unchanged).
- A machine-readable/JSON report envelope (`--report` emits human-paste Markdown only).
- Wiring `--report` into the dev-pipeline's own abort path (the pipeline already writes state; the
  filer runs `--report`).
