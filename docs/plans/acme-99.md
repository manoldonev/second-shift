# Plan — #99: per-repo fix-attempt budget is dead and silent (`--repo` counter mismatch)

## Context / problem framing

`verifyctl.sh` charges and reads the fix-attempt budget from two different places whenever
`--repo <id>` is set:

- **Charging** goes through `statectl verify-attempts --repo "$REPO_ID"` (wired at
  `plugins/dev-pipeline/skills/run/verifyctl.sh:287` via the `VA_REPO` passthrough), which writes
  `.worktrees[<id>].verifyAttempts` (`plugins/dev-pipeline/skills/run/statectl.sh:866-874`).
- **Reading** is unbranched and always hits the flat top-level `.verifyAttempts`.

The counter that is incremented is therefore never the counter that is checked or reported. The
2-attempt safety valve is inert on every `be-fe-pair` / `monorepo` consumer, and every `--repo`
verdict reports `attempts:{}` so even a prose-level orchestrator budget check sees nothing.

There are **three** unbranched read sites, not the two named in the issue:

| Site | Expression | Consequence when `--repo` is set |
| --- | --- | --- |
| `verifyctl.sh:336` | `sget "$key" ".verifyAttempts.${c} // 0"` | the `(( count >= 2 ))` refusal never fires |
| `verifyctl.sh:339` | `--argjson attempts "$(sget "$key" ".verifyAttempts // {}")"` | the exit-4 verdict's own `attempts` map would be empty |
| `verifyctl.sh:775` | `attempts=$(sget "$key" ".verifyAttempts // {}")` | every emitted verdict reports `attempts:{}` |

Site `:339` sits inside the same block as `:336`, but it is a distinct read: a fix that only
repaired "the budget check" would ship a budget-exhausted verdict that still fails to show the
charges justifying its own refusal.

## Assumptions

1. `REPO_ID` is reachable at all three sites. It is a `cmd_run` local (`verifyctl.sh:238`);
   `emit_verdict` already relies on bash dynamic scoping to see it for the per-repo sidecar suffix
   (`verifyctl.sh:757-758`), so site `:775` inherits it by the same established mechanism.
2. The charging path in `statectl.sh` is already correct and is **not** in scope — only the reads
   are wrong.
3. `stages/6-verify.md` already documents the intended per-repo behavior (`worktrees.<r>.verifyAttempts`),
   so the docs are right and the code is wrong. Code-only fix.

## Decision Ledger

| D-n | Decision | Provenance | Rationale |
| --- | --- | --- | --- |
| D-1 | Under `--repo`, the per-repo map is the sole source of truth; an absent key reads `0`/`{}` and never falls back to the flat field | codebase-derived | `statectl.sh:866-882` keeps the two locations disjoint and `statectl-selftest.sh:548-549` asserts a `--repo` increment leaves the flat count untouched. A fallback would let a stale flat value satisfy a per-repo check, silently re-importing the inert-budget bug |
| D-2 | Route all three reads through one `va_path` helper rather than inlining the conditional three times | codebase-derived | A single branch point cannot drift; three inlined copies is exactly how one of the three sites got missed in the original implementation |
| D-3 | Post-fix per-repo count on the refused run is `2`, not `3` | codebase-derived | `verifyctl.sh:332-343` budget-checks before charging (`(( count >= 2 ))`), so the refusal replaces the third charge. The issue's measured `{TEST_FAILURE:3}` is the bug's signature and must not become the assertion |
| D-4 | Extend `verifyctl-selftest.sh` rather than adding a `stage6-perrepo-*` file | codebase-derived | The `stage5/7/8-perrepo-*` selftests cover stage orchestration; the behavior under test here is verifyctl's own, and the existing file already owns the fixture, the `yarn` shim, and the v4–v7 budget-accounting sequence this extends |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/verifyctl.sh` — add `va_path()`, route the three reads through it.
- `plugins/dev-pipeline/skills/run/verifyctl-selftest.sh` — add the per-repo budget/emission coverage.

## Reuse inventory

- `sget()` (`verifyctl.sh:96`) — the existing state-read helper; the fix composes with it, changing only the jq path it is handed.
- `REPO_ID` (`verifyctl.sh:238`) — the existing per-repo switch; no new flag or plumbing.
- The `${REPO_ID:+-$REPO_ID}` suffix pattern (`verifyctl.sh:314-315`, `:758`) — established precedent for `REPO_ID`-conditional resources in this same file.
- `reset_all()` / `vrun()` / `attempts()` (`verifyctl-selftest.sh:132-139`) — existing fixture helpers; the new cases add a per-repo sibling of `attempts()` rather than a parallel harness.
- `va_path()` `[NEW]` — no existing equivalent; confirmed by `grep -n 'verifyAttempts' verifyctl.sh`, which shows three independently-inlined flat reads and no shared accessor.

## Implementation steps

1. Define `va_path()` in `verifyctl.sh` near the other state helpers, above `cmd_run`. It emits
   `.worktrees["<id>"].verifyAttempts` when `REPO_ID` is non-empty, else `.verifyAttempts`.
   Use `${REPO_ID:-}` so the helper is safe under `set -u` from any call frame.
2. Site `:336` — budget check: `count=$(sget "$key" "$(va_path).${c} // 0")`.
3. Site `:339` — exit-4 verdict payload: `--argjson attempts "$(sget "$key" "$(va_path) // {}")"`.
4. Site `:775` — `emit_verdict` attempts map: `attempts=$(sget "$key" "$(va_path) // {}")`.
5. Extend `verifyctl-selftest.sh` with the per-repo cases (see Test strategy).

## Test strategy

Verify-after (this is a bug fix in shell infrastructure; the selftest is the regression gate). New
cases extend the existing v-series in `verifyctl-selftest.sh`, reusing its fixture, `yarn` shim, and
`monorepo` host id `mono`:

- **Per-repo fixture** — a `reset_repo()` that seeds `.worktrees["mono"].worktreePath` + `.base`
  alongside the flat fields, plus a `rattempts()` reading `.worktrees["mono"].verifyAttempts.<class>`.
  The per-repo sidecar is `8888-mono-verify.json`.
- **Charging is visible** — a `--repo mono` failure then a re-run at a fresh HEAD charges the
  per-repo counter to 1 **and** the emitted verdict's `attempts` map is non-empty (the regression the
  issue reports as `attempts:{}`).
- **Budget refusal fires** — with the per-repo count driven to 2, the next `--repo mono` re-run at a
  fresh HEAD must exit `4` with `status == "budget-exhausted"`, must not run any suite command, and
  must leave the per-repo count at **2** (D-3).
- **The refusal verdict is self-justifying** — that exit-4 verdict's own `attempts` map is non-empty
  (covers site `:339` specifically, which the other two cases would not catch).
- **No flat fallback** (D-1) — with the per-repo counter at 0 and the **flat** counter seeded at 2, a
  `--repo mono` run must proceed normally rather than refuse. This is the assertion that fails if
  someone later "helpfully" adds a fallback.
- **Single-repo non-regression** — the existing v4–v7 sequence is untouched and continues to assert
  the flat path; the no-`--repo` behavior stays byte-identical.

## Acceptance-criteria traceability

The Stage-1 intent snapshot is empty (issue #99 carries no `## Acceptance Criteria` heading), so this
table is intentionally header-only per the traceability rule.

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
```

## Risks / rollback notes

- **`REPO_ID` out of scope at `:775`.** If `emit_verdict` were ever called outside `cmd_run`'s dynamic
  extent, `va_path` would silently fall back to the flat path. Mitigated by `${REPO_ID:-}` (no `set -u`
  crash) and by the fact that the per-repo sidecar suffix at `:758` already depends on the same
  inheritance — a break there would already be failing loudly today.
- **Behavior change for in-flight per-repo runs.** A pair run started before this fix may carry a
  populated flat counter and a populated per-repo counter. After the fix its per-repo counter becomes
  authoritative, which can make a lane refuse earlier than it would have. This is the intended repair,
  not a regression.
- **Rollback** — revert the commit; the three reads return to flat and the budget goes inert again.

## Out-of-scope

- The charging path in `statectl.sh` (already correct).
- `stages/6-verify.md` (already documents the intended behavior).
- Any change to the flat single-repo path's semantics.
- Reconciling or migrating counters that a pre-fix run left in both locations.
