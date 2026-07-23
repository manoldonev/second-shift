# Plan — #191: intake/Stage-1 JIRA fetch sites still hardcode the `mcp__atlassian__` prefix

## Context / problem framing

`#187` made `scope-completeness-reviewer` namespace-agnostic for the Atlassian MCP: the
tool namespace depends on how the session registered the server —
`mcp__atlassian__*` (top-level `mcpServers`), `mcp__plugin_atlassian_atlassian__*`
(plugin-bundled), or `mcp__claude_ai_Atlassian_Rovo__*` (claude.ai Rovo). A hardcoded
single prefix means "No such tool available" for a consumer whose MCP arrives under a
different namespace. `#187` deliberately deferred the parallel intake/Stage-1 fetch
sites; this issue closes them.

The intake/Stage-1 sites are **prose instructions** (SKILL/stage/README files + one
shell skip-note), run in the orchestrating session — lower acute severity than the
subagent-scoped `#187` failure, but the prose still hardcodes one prefix and misleads a
session exposing only another. The fix mirrors `#187`: name the three namespaces + the
`ToolSearch` discovery step at each site, and add a static guard so the fix cannot
regress.

## Assumptions

- The three Atlassian namespace prefixes are the complete set (same set `#187` codified
  in `check-scope-tracker-namespaces.sh` and `scope-completeness-reviewer.md:40-45`).
  Non-Atlassian tracker MCPs are explicitly out of scope (per the issue).
- Editing `plugins/dev-pipeline/skills/**` **in this repo worktree** is normal repo
  source work — not self-modification of the installed skill executing this run (that
  lives under `~/.claude/plugins/cache/…`).
- CI enforces a repo-level guard through its `*-selftest.sh`: the selftest asserts the
  guard green against the real tree (a regression then fails the selftest → CI red),
  mirroring `scripts/stack-generality-lint.sh` + its selftest. No `ci.yml` registration
  is needed (the `find . -name '*-selftest.sh'` glob discovers it on both CI lanes).

## Decision Ledger

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Scope beyond the issue's enumerated list | Also fix `plugins/dev-pipeline/skills/run/SKILL.md` (Tracker-adapters jira fetch) and `plugins/dev-pipeline/skills/run/tools/preflight.sh` (session-side-MCP skip notes) — same prose class; leaving them hardcoded regenerates exactly this bug class (a third follow-up). Non-Atlassian MCPs stay out of scope. | codebase-derived |
| D-2 | AC-2 guard shape | A **repo-level `scripts/` cross-plugin prose lint** (not an extension of `check-scope-tracker-namespaces.sh`, which asserts an agent `tools:` frontmatter grant the prose sites don't have). Mirrors `scripts/stack-generality-lint.sh`: discovery-based, exit-code = violation count, CI via its own selftest. AC-2's "or a sibling" branch sanctions this. | codebase-derived |
| D-3 | Guard discovers sites vs. a hardcoded file list | **Discovery-based**: scan `plugins/intake-toolkit/skills` + `plugins/dev-pipeline/skills/run`; any file naming `mcp__atlassian__` must also name the other two prefixes. A hardcoded list would re-create finding-1's under-inclusive-list bug when a new fetch site is added later. | codebase-derived |
| D-4 | Prose phrasing + shared-reference suggestion | Mirror the canonical `scope-completeness-reviewer.md:40-45` wording, kept terse (one compact clause per file). Per-file self-containment over a cross-plugin shared doc: SKILLs are read standalone and plugins install independently, so a cross-plugin shared reference would break self-containment. The issue's "consider a shared reference" is a soft suggestion, consciously evaluated and declined here. | codebase-derived |

## Affected files / modules

Prose edits (make each file name all three namespaces at its fetch instruction):

- `plugins/intake-toolkit/skills/intake-orchestrator/SKILL.md` — jira-delta callout + Step 0 fetch (lines ~25, 27, 68, 80)
- `plugins/intake-toolkit/skills/intake/SKILL.md` — jira-delta + granularity skim (lines ~13, 20)
- `plugins/intake-toolkit/skills/intake-interviewer/SKILL.md` — jira-delta + conditional ticket enrichment (lines ~22, 58)
- `plugins/dev-pipeline/skills/run/SKILL.md` — Tracker-adapters jira row (line ~55) **[D-1]**
- `plugins/dev-pipeline/skills/run/stages/1-intake.md` — Stage-1 tracker-delta prose (line ~8)
- `plugins/dev-pipeline/skills/run/tools/tracker/README.md` — fetch-ticket operation row (line ~26)
- `plugins/dev-pipeline/skills/run/tools/tracker/jira/README.md` — `## Prerequisite` (line ~16, the file's canonical home) + fetch-ticket row (line ~26)
- `plugins/dev-pipeline/skills/run/tools/preflight.sh` — session-side-MCP skip notes (lines ~33, 232) **[D-1]**

New guard + selftest:

- `scripts/check-intake-tracker-namespaces.sh` `[NEW]` — the discovery-based prose guard
- `scripts/check-intake-tracker-namespaces-selftest.sh` `[NEW]` — green-on-real-tree + red-on-fixtures

## Reuse inventory

- `plugins/review-toolkit/scripts/check-scope-tracker-namespaces.sh` — the `#187` guard; **pattern reused** (namespace array, doctor exit convention, green+red selftest), not extended (its `tools:`-frontmatter assertion shape does not transfer to prose — D-2).
- `scripts/stack-generality-lint.sh` + `scripts/stack-generality-lint-selftest.sh` — **structural template reused** for a repo-level cross-plugin prose lint (repo-root arg, `[repo-root]` default `.`, violation-count exit, CI-via-selftest, no `ci.yml` registration).
- Canonical three-namespace prose at `plugins/review-toolkit/agents/scope-completeness-reviewer.md:40-45` — **wording mirrored** (D-4).
- No new runtime helpers introduced.

## Implementation steps

1. **Write the guard** `scripts/check-intake-tracker-namespaces.sh` `[NEW]`:
   - `NAMESPACES=(mcp__atlassian__ mcp__plugin_atlassian_atlassian__ mcp__claude_ai_Atlassian_Rovo__)`.
   - Scan roots (repo-root-relative, arg `${1:-.}`): `plugins/intake-toolkit/skills`, `plugins/dev-pipeline/skills/run`.
   - Find files containing the bare top-level prefix `mcp__atlassian__`; for each, require the other two prefixes present in the same file (proving the three-namespace discovery is co-located). Report each missing `(file, namespace)` to stderr.
   - Exit code = violation count (doctor convention). Header comment explains why (mirror stack-generality-lint.sh).
2. **Edit the prose sites** so each guarded file names all three namespaces at its fetch instruction, mirroring the `#187` clause (terse). Canonical fuller note in `jira/README.md`'s `## Prerequisite`; compact clauses elsewhere. Include `preflight.sh` + `run/SKILL.md` (D-1).
3. **Write the selftest** `scripts/check-intake-tracker-namespaces-selftest.sh` `[NEW]`: (a) green against the real tree; (b) red on a fixture where one prefix is stripped from a guarded file; (c) red on a fixture with a fresh single-prefix site added. `mktemp -d` fixtures, `trap … EXIT` cleanup — mirror the existing selftests.
4. **Commit** via `bot-commit.sh`, `fix(...)` verb, with a `Changelog:` trailer (consumer-visible prose behavior change).

## Test strategy

Verify-after (prose + shell tooling — no runtime behavior change, no unit-test surface;
config has no `unitTestScope`). The guard's selftest is the behavior proof:

- Green on the real tree once the prose edits land.
- Red when a namespace is dropped from a guarded file (regression caught).
- Red when a new single-prefix fetch site is introduced (discovery works).
- `shellcheck -e SC1091,SC2015,SC2181` clean on both new scripts.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | No intake/Stage-1 fetch site uses a single hardcoded `mcp__atlassian__` prefix; each references the three-namespace discovery | 2 | guard green on real tree (selftest case a) — no test (covered-by-selftest) |
| AC-2 | A static check guards the intake sites the same way #187's guard covers the reviewer | 1, 3 | `check-intake-tracker-namespaces-selftest.sh` green+red cases (b, c) |

## Verification commands

```bash
# from repo root, on the branch
bash scripts/check-intake-tracker-namespaces.sh .                 # expect: clean, exit 0
bash scripts/check-intake-tracker-namespaces-selftest.sh          # expect: OK
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
```

## Risks / rollback

- **Risk:** the guard's "any file naming `mcp__atlassian__` needs all three" invariant
  false-positives on a file that mentions the prefix in a non-fetch context. Mitigation:
  scan roots are limited to the intake/Stage-1 skill surface; the fix makes every such
  file carry all three anyway. Rollback is a clean `git revert` (prose + two new files;
  no runtime code, no state/schema change).
- **Risk:** a namespace-direction (`ci.yml` rule 3) trip. Mitigation: the guard lives in
  repo `scripts/` (outside `plugins/`), references dev-pipeline by **path** not the
  `dev-pipeline:` namespace token, and is a `.sh` (rule 3b only scans `*.md`/`*.mjs`).

## Out of scope

- Any non-Atlassian tracker MCP.
- Refactoring the three-namespace prose into a cross-plugin shared reference doc (D-4:
  declined for self-containment).
- The `#187` sites themselves (`scope-completeness-reviewer.md`, `code-review.mjs`,
  `check-scope-tracker-namespaces.sh`) — already namespace-agnostic.

Unverified references: none.
