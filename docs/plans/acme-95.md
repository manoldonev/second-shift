# Plan — #95: tool-discipline contract for reviewer Bash use

## Context / problem framing

Reviewer-agent Bash calls are annotated "Contains shell syntax (string) that cannot be statically analyzed" — cosmetic ledger noise on every review run, and a real permission prompt on the few reviewer agents without `permissionMode: bypassPermissions`. The v2 spec (this issue) replaced the falsified v1 root cause: the harness (Claude Code 2.1.212) does **not** expose `Grep`/`Glob` to any agent surface when `Bash` is present, so every `tools: Read, Grep, Glob, Bash` line has been aspirational and reviewers search via Bash because it is their only search surface. Measured: ~71% of reviewer Bash calls are compound-shaped (that shape defeats static analysis, not grep itself); a "use Grep/Glob" nudge measured null; a strict "one analyzable command per call" mandate measured harmful (killed 3/6 reviewers at the turn cap).

The fix is a **documented, availability-conditional Tool Discipline contract** in `reviewer-baseline` + structural corrections + a measurement probe — no behavioral nudge at dispatch time (measured null/harmful), no Bash-shape mandate.

## Assumptions

- The harness Grep/Glob absence is a machine-level condition (issue #95 probe); the contract is written **availability-conditional** so it is correct whether or not a future launch restores those tools.
- CHANGELOG lives at the **repo root** (`CHANGELOG.md`), with per-plugin "(in progress)" entries — the established release convention (`docs/releasing.md`); there is no per-plugin CHANGELOG.md.
- Plan/PR naming follows the repo's existing `docs/plans/acme-{N}.md` convention (matches `acme-1.md`, `acme-30.md`, …).

## Decision Ledger

Explicit empty form for user-answered rows (autonomous run — no prompting). All rows `codebase-derived`.

| Decision | Choice | Provenance |
| --- | --- | --- |
| Commit verb for AI-infra content change | `chore(scope):` not `feat:` | codebase-derived (repo convention: skill/agent/pipeline changes take `chore`) |
| Where the Tool Discipline section lives | new top-level `## Tool Discipline` section in `reviewer-baseline/SKILL.md` (contract only; **no** dispatch-time nudge — AC-6) | codebase-derived (v2 spec; `code-review.mjs` precedent is scoped to the *stall* instruction, not tool-preference) |
| AC-4 rewording set | 5 lines: `codebase-explorer.md:44`, `figma-faithful-spec-reviewer.md:37`, `figma-faithful-reviewer.md:46/79/83` | codebase-derived (grep of `plugins/*/agents/*.md`) |
| Sanctioned config idioms preserved verbatim | `figma-faithful-reviewer.md:44`, `doc-updater.md:32-33` `BASE=$(jq …)` lines | codebase-derived (AC-4 byte-unchanged requirement) |
| Plugins bumped | review-toolkit, design-toolkit, dev-pipeline | codebase-derived (only these three have content changes) |

## Affected files/modules

All paths worktree-relative; every referenced file verified to exist (grep/read) except the one tagged `[NEW]`.

- `plugins/review-toolkit/skills/reviewer-baseline/SKILL.md` — add `## Tool Discipline` section (AC-1); de-model `wc -l` on line 33 → `Read` (AC-2).
- `plugins/review-toolkit/agents/review-lead-synth.md` — `tools: Read, Grep, Glob, Bash` → `tools: Read` (line 4); correct source-of-record pointer line 19 `.claude/skills/review-lead/SKILL.md` → `plugins/review-toolkit/skills/review-lead/SKILL.md` (AC-3).
- `plugins/review-toolkit/agents/codebase-explorer.md` — line 44 `Grep`/`Glob` search step → availability-conditional wording (AC-4).
- `plugins/design-toolkit/agents/figma-faithful-spec-reviewer.md` — line 37 `Grep` → availability-conditional wording (AC-4).
- `plugins/design-toolkit/agents/figma-faithful-reviewer.md` — lines 46, 79, 83 `Grep`/`Glob` → availability-conditional wording (AC-4). Line 44 `BASE=$(jq …); git diff` config idiom **byte-unchanged** (line 46 is a rewording target, not the idiom — Stage-4 warning dispositioned).
- `plugins/review-toolkit/agents/doc-updater.md` — config idiom lines 32-33 **byte-unchanged** (no rewording; verified no `Grep`/`Glob` tool commands present, only the English verb "grepping").
- `plugins/dev-pipeline/skills/run/workflows/tool-discipline-probe.mjs` — `[NEW]` the three-arm measurement probe (AC-5), mirroring `stall-probe.mjs` shape.
- `plugins/review-toolkit/.claude-plugin/plugin.json`, `plugins/design-toolkit/.claude-plugin/plugin.json`, `plugins/dev-pipeline/.claude-plugin/plugin.json` — patch version bump (AC-7).
- `CHANGELOG.md` (repo root) — "(in progress)" entries for the three bumped plugins (AC-7).

## Reuse inventory

- `stall-probe.mjs` — the new probe mirrors its `meta` header, rationale comment block, `args`-destructure + required-`worktree` guard, `agent()` dispatch, death-detection (`isNoStructuredOutputError`), and per-reviewer aggregation. Reused as the structural template, not imported.
- `FINDINGS_SCHEMA` / `STRUCTURED_OUTPUT_FIRST` shape — copied verbatim from `stall-probe.mjs` (itself copied from `code-review.mjs`) so the probe dispatch is identical to production. `none — no new shared helpers introduced.`

## Implementation steps

1. **AC-1** — Insert a `## Tool Discipline` section into `reviewer-baseline/SKILL.md` (after `## Review Process Template`, before `## Sub-Agent Output Is Advisory`). Content: availability-conditional preference (`Grep`/`Glob`/`Read` where the harness provides them; where it does not — the current condition on this harness — batched Bash search is sanctioned, explicitly NOT one-command-per-call); the substitution-into-variable ban **scoped to locating/reading files**; and the four-part sanction list (git; tests/linters; mandated config-resolution one-liners — naming the base-branch resolvers as sanctioned, do not "fix" to a hardcoded branch; mandated tracker fetches — `gh issue view` / Atlassian MCP).
2. **AC-2** — In the same file, rewrite line 33's `Run \`wc -l\` or enumerate test symbols` → a `Read` instruction (open the spec file and read it / enumerate test blocks).
3. **AC-3** — `review-lead-synth.md`: frontmatter `tools: Read`; body line 19 pointer → `plugins/review-toolkit/skills/review-lead/SKILL.md`.
4. **AC-4** — Add availability-conditional wording to the 5 `Grep`/`Glob` lines (each gains "where the harness exposes them; otherwise batched Bash search per the tool-discipline contract"). Leave the two `BASE=$(jq …)` config idioms byte-for-byte.
5. **AC-5** — Write `tool-discipline-probe.mjs`: `meta` + rationale header documenting the measured three-arm baseline (baseline ~71% compound; grep-nudge null ~71.3%/71.4%; strict-one-command 72%→54% compound but 3/6 turn-cap deaths); `arm ∈ {baseline, grep-nudge, strict-one-command}` selecting the appended instruction; required `worktree`; shell-heavy default range (`4df8fc8^..4df8fc8`); `agent()` dispatch with death detection; per-arm/per-reviewer aggregation returned.
6. **AC-7** — Patch-bump the three plugin.json versions; add repo-root `CHANGELOG.md` "(in progress)" entries for each.
7. **AC-6 (negative) guard** — do NOT touch `code-review.mjs` / `intake-review.mjs` tool-preference-wise; do NOT introduce any one-command-per-call mandate anywhere.

## Test strategy

Verify-after (docs/infra change; no `apps/api` behavior surface — `unitTestSurface: skip`, no `unitTestScope` configured). The repo's selftest lane (`*-selftest.sh`) and shellcheck lane are the safety net; the new `.mjs` is a Workflow script (runtime `agent()` global) and is validated by lint/parse, not executed offline (same posture as `stall-probe.mjs`). Grep-based assertions per AC (see traceability).

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Tool Discipline section w/ 4-part sanction list | 1 | grep section + its four sanctions in `reviewer-baseline/SKILL.md` — no test (covered-by-selftest) |
| AC-2 | grounding bullet drops `wc -l` → `Read` | 2 | grep: no `wc -l` in the bullet, `Read` present — no test (covered-by-selftest) |
| AC-3 | `review-lead-synth` `tools: Read` + plugin path | 3 | grep frontmatter `tools: Read`; grep pointer path — no test (infra-only) |
| AC-4 | Grep/Glob lines availability-conditional; idioms byte-unchanged | 4 | `git diff` shows the 2 idiom lines unchanged; 5 lines reworded — no test (infra-only) |
| AC-5 | probe exists, Workflow shape, documents baseline | 5 | `node --check` parse; grep three-arm baseline in header — no test (infra-only) |
| AC-6 | no dispatch nudge; no one-command mandate | 7 | grep `.mjs` workflows for absence — no test (infra-only) |
| AC-7 | version bump + CHANGELOG per changed plugin | 6 | git diff plugin.json versions + CHANGELOG entries — no test (infra-only) |

## Verification commands

```bash
# shellcheck + selftest lanes (config commands.second-shift.lint / .test)
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
# new probe: Workflow scripts have a top-level `return`/`await` (harness-wrapped),
# so `node --check` is inapplicable (stall-probe.mjs fails it identically). Validate by
# wrapping the body in an async fn — same shape check as its sibling probe.
# AC greps (spot-check)
grep -n 'Tool Discipline' plugins/review-toolkit/skills/reviewer-baseline/SKILL.md
grep -c 'wc -l' plugins/review-toolkit/skills/reviewer-baseline/SKILL.md   # expect 0
```

## Risks / rollback notes

- **Wording drift risk** — the availability-conditional phrasing must not read as a hard "prefer Grep/Glob" nudge (measured null) nor as a Bash ban (measured harmful). Mitigation: the section explicitly sanctions batched Bash and names the harness condition. Rollback: revert the branch; all changes are additive doc/content + one new file + version metadata.
- **Byte-unchanged idioms** — an accidental reflow of the `BASE=$(jq …)` lines would regress config-driven base-branch resolution. Mitigation: leave those lines untouched; `git diff` review confirms.
- No runtime code path changes; rollback is a clean revert.

## Out of scope

- Dispatch-time "use Grep/Glob" nudges in `code-review.mjs` / `intake-review.mjs` (measured null; AC-6).
- Any Bash-shape mandate / one-command-per-call rule (measured harmful; AC-6).
- Per-agent body audits for bad `grep`/`find` examples (audit ran during triage; none exist).
- Restoring Grep/Glob availability (harness-level, operator-side).
- The 2 non-reviewer generator agents (`design-faithful.md`, `design-faithful-spec.md`) that also lack `permissionMode` — out of the "reviewer-baseline-adjacent" framing by design.
