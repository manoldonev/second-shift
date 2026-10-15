# Decision record — #1063 second-shift: doctor and onboard propose testRunners for a vitest or jest repo

Receipt: v4

## Summary

config-grill gains a finding for a repo whose root manifest depends on vitest or jest and whose config has no `testRunners`. The finding carries the exact `vitest-json` or `jest-json` entry in a new `value` field and embeds it in its prose. Doctor renders it unchanged. Onboard drafts it into the config it proposes, which supersedes #1040 D-8. The build starts only after #1053 merges.

Open regions: none.

Provenance legend: `user-answered` = the operator chose. `codebase-derived` = a fact from the code or the docs, with its proof.

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | How the runner is detected | A direct dependency named `vitest` or `jest` in the root `package.json` (`dependencies` or `devDependencies`). Workspace packages are not scanned. Neither or both gives a `notEvaluated` line naming what the grill saw, and no finding | user-answered | intent |
| D-2 | How the finding carries the entry | A new optional `value` field holds the exact entry object. The prose `proposal` embeds the same JSON, so doctor needs no change. Existing findings carry no `value` | user-answered | intent |
| D-3 | What the entry's `command` is built from | The configured `commands.<id>.test` plus the format's required flags and `{files}`, with `--` for npm. This applies only when its script body is the runner. Strip leading `VAR=value` and an `npx`/`bunx` wrapper. The first token must then be the runner, with no `&&`, `\|\|`, `;` or `\|`, and not a watcher. Otherwise the runner is invoked directly through the package manager | user-answered | intent |
| D-4 | Where the `when` globs come from | The runner's documented default test-file pattern. The evidence counts the tracked files the globs match. Config files are not parsed into globs | user-answered | intent |
| D-5 | The glob dialect for `when` and for the count | A bash `case` pattern, as `run.sh`'s `runner_for` matches: one brace-free pattern per suffix, such as `*.test.ts`. The count uses `case` semantics, never the grill's brace-expanding `glob_to_ere` — run: `for g in "*.test.ts" "*.{test,spec}.ts"; do case src/a/b.test.ts in $g) echo "$g y";; *) echo "$g n";; esac; done` → *.test.ts y, *.{test,spec}.ts n | codebase-derived | fact |
| D-6 | When the default globs match no tracked file | The finding still fires, with no `value`. Its proposal says the `when` globs must come from the operator. Onboard drafts nothing. An entry matching nothing would turn every tagged file red in the lane | user-answered | intent |
| D-7 | A second suite under the same runner | Propose one entry. Each other root-manifest script that runs the same runner with `--config` or `-c` is named in the evidence as not covered | user-answered | intent |
| D-8 | What onboard does with the finding | Onboard drafts the `value` into `commands.<id>.testRunners`, as it drafts `reviewers.webComponentGlobs`, then re-runs the grill. The human can remove it on the accept-or-edit screen. This supersedes #1040 D-8. `docs/config-schema.md` stops saying onboard does not draft the key | user-answered | intent |
| D-9 | What the runner version does | Evidence only, with no minimum. It is read from `yarn.lock` (berry or v1), `package-lock.json` or `pnpm-lock.yaml`. An unresolved version is said in the evidence, and the finding still fires | user-answered | intent |
| D-10 | Which files raise the config caveat | For jest, `jest.config.*` or a `jest` key in `package.json`. For vitest, `vitest.config.*`, `vitest.workspace.*`, or a `vite.config.*` that contains a `test:` key. The evidence then says the globs assume the default pattern | user-answered | intent |
| D-11 | The acceptance criteria | Six ACs. AC-1 and AC-2 add the version in the evidence. AC-3 is only the set case. AC-4 covers neither or both runners. AC-5 covers second suites. AC-6 covers onboard drafting. The issue body was amended to match on the operator's yes | user-answered | intent |
| D-12 | AC-6 test intent | Exempt. Onboard's drafting is a prose change to a skill, and no selftest can run it | user-answered | intent |
| D-13 | What "testRunners is set" means | Set and non-empty. An empty array leaves the check off, so it gets the finding — run: `grep -cF 'if [ -z "$(test_runners)" ]' plugins/dev-pipeline/skills/run/run.sh` → 1, and `test_runners` reads `.testRunners[]?` | codebase-derived | fact |
| D-14 | A config with no `commands` entry the lane reads | No finding, as for T5. The grill already reports the unresolved entries as `notEvaluated` — cited (convention): plugins/second-shift/skills/onboard/tools/config-grill.sh:271 | codebase-derived | fact |
| D-15 | Outside a git work tree | A `notEvaluated` line, as T2 reports when tracked files cannot be counted — cited (convention): plugins/second-shift/skills/onboard/tools/config-grill.sh:143 | codebase-derived | fact |
| D-16 | The package manager for the direct form | `detect.sh`'s precedence: yarn, then pnpm, then npm. No lockfile, or a bun lockfile only, means npm, so the direct form uses `npx` — run: `sed -n 110,113p plugins/second-shift/skills/onboard/tools/detect.sh` → yarn.lock, pnpm-lock.yaml, package-lock.json, then package.json with no lockfile → npm | codebase-derived | fact |
| D-17 | When the build can start | After #1053 merges. config-lint on main does not know the json formats yet — run: `git grep -c vitest-json origin/main -- plugins/dev-pipeline/tools/config-lint.sh` → no match (rc 1) | codebase-derived | fact |

Options weighed:
- D-1: root manifest dependencies, dependency plus config file, or scanning workspaces too. The operator chose root manifest dependencies.
- D-2: a new `value` field plus JSON in prose, or JSON in prose only. The operator chose the `value` field.
- D-3: the configured test command plus flags, or always the direct runner. Then a narrow or a broad "runs once" rule. The operator chose the configured command and the narrow rule.
- D-4: the runner default with a caveat, parsing JSON configs, or globs observed from tracked files. The operator chose the runner default.
- D-6: a finding without a value, a finding with a value, or `notEvaluated`. The operator chose a finding without a value.
- D-7: one entry naming the rest, one entry per suite, or ignoring second suites. The operator chose one entry naming the rest.
- D-8: draft it in, or warn only. The operator chose draft it in.
- D-9: evidence only, or a minimum version gate. The operator chose evidence only.
- D-10: runner configs plus a vite config with a `test:` key, or any vite config. The operator chose the first.
- D-11: adopt and amend the body, adopt and let the operator edit, or keep the ACs as filed. The operator chose adopt and amend.

## Open Regions

No open regions. Every decision in scope is settled.

## Test intent

ACs: AC-1 AC-2 AC-3 AC-4 AC-5 AC-6

AC-1: a repo whose root manifest depends on vitest, with no testRunners, gets a finding whose `value` passes the in-repo `plugins/dev-pipeline/tools/config-lint.sh` (not a stub) as a `vitest-json` entry, and whose evidence names vitest and its lockfile version
AC-2: a repo whose root manifest depends on jest gets a finding whose `value` passes the in-repo config-lint as a `jest-json` entry, and whose evidence names jest and its lockfile version
AC-3: a config with a non-empty testRunners gets no finding
AC-4: a root manifest that depends on neither runner, or on both, gets no finding and a `notEvaluated` line naming what the grill saw
AC-5: another root-manifest script that runs the same runner with `--config` is named in the finding's evidence as not covered
AC-6: exempt — onboard's drafting is a prose change to its skill, and no selftest can run it

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The grill finding's evidence and proposal text | decided (D-9) |
| S-2 | The finding's `value` field in the grill JSON | decided (D-2) |
| S-3 | Doctor's WARN line for the finding | decided (D-2) |
| S-4 | The `notEvaluated` line for neither or both runners | decided (D-1) |
| S-5 | The finding without a value on zero matches | decided (D-6) |
| S-6 | The evidence's caveat and second-suite text | decided (D-10) |
| S-7 | Onboard's drafted entry on the accept-or-edit screen | decided (D-8) |
| S-8 | The `docs/config-schema.md` sentence on onboard drafting | decided (D-8) |

## Checks

No ticket-specific checks. The configured checks cover this change.

## Intake steps

Requirements: the ticket body as written. spec-reviewer: needs-spec-work, no blockers, seven warnings. The interview closed them, and the body was amended on the operator's yes.

Split: not split. One trigger in one script plus one onboard bullet. The register reached ten intent rows, but they are facets of one finding.

Explore: done. Read config-grill.sh, doctor.sh's grill rendering, onboard's grill section, config-lint's testRunners rules, run.sh's runner_for, detect.sh and the #1053 record.

Fan-out: skipped — by the operator at the intake notice: no reason given

Dup-scan: no candidates at or above threshold 12 (corpus: 1 scanned)

Post-merge scan: no post-merge AC

Sizing: opus

<details>
<summary>Intake evidence: knowledge source and fan-out</summary>

## Knowledge source

Knowledge source: none declared

## Fan-out

Fan-out: skipped — by the operator at the intake notice: no reason given

</details>
