# acme-93 — `is-inert-diff` treats `.claude/second-shift/.known-extensions` as inert

## Context / problem framing

`INERT_RE` in [`plugins/dev-pipeline/skills/run/tools/is-inert-diff.sh`](../../plugins/dev-pipeline/skills/run/tools/is-inert-diff.sh) carves out `.claude/**/*.{mjs,cjs,py,tsv,json,jsonl}` but matches no extensionless path. The consumer allowlist file `.claude/second-shift/.known-extensions` is therefore unmatched, so any diff touching it selects the SUITE lane — even when every other path in the diff is inert Markdown/config.

Observed on a real run (`/dev-pipeline:pipeline-retro #283`, cadenza-ai consumer): deleting one redundant `.known-extensions` forced the full SUITE lane (install → build → lint + type-check + test, ~3 min) on a diff with zero executable changes.

The carve-out rationale already established for `.claude/**/*.{tsv,json,jsonl,py}` applies verbatim: `.known-extensions` is read only by `check-extensions.sh` ([`tools/check-extensions.sh`](../../plugins/dev-pipeline/skills/run/tools/check-extensions.sh) line 59, `ALLOW="$SS/.known-extensions"`), is referenced by no `tsconfig`/`eslint`/`jest` config, and is extensionless so it falls outside the prettier format-glob `*.{ts,tsx,js,json,md}`. Zero coverage is lost by reclassifying it.

## Assumptions

- `.claude/second-shift/` is the single canonical location for this file. Grounded: `check-extensions.sh` line 14 sets `SS="$ROOT/.claude/second-shift"` and line 59 reads `$SS/.known-extensions`; no other reader exists.
- The selftest's `CANONICAL_RE` is a lockstep mirror of `INERT_RE`, not a frozen historical artifact — so it is updated alongside. (Decision D-2 below.)

## Decision Ledger

| D-n | Decision | Provenance | Rationale |
| --- | --- | --- | --- |
| D-1 | Add exactly one alternative, anchored to the full canonical path `^\.claude/second-shift/\.known-extensions$` — not the issue's suggested arbitrary-depth `^\.claude/.*/\.known-extensions$` | codebase-derived | `check-extensions.sh` reads exactly one location, so depth-flexibility buys nothing while widening a deliberately fail-conservative classifier. `6-verify.md` states the governing principle: the boundary is "config that cannot affect lint/type-check/test, NOT any extensionless dotfile". |
| D-2 | Update `CANONICAL_RE` (selftest line 100) in lockstep and extend `GOLDEN_CASES`; reword the DRIFT MODEL prose to drop the stale "byte-identical to the old inline grep" framing | codebase-derived | The golden-master tail re-derives expected lane from `CANONICAL_RE`. Leaving it stale fails the tail outright; the guard's real value is catching transcription drift between the two copies, which survives a deliberate lockstep edit. |
| D-3 | Update the prose inert-set enumerations in the `is-inert-diff.sh` header and the `6-verify.md` lane reference, and add a per-class rationale paragraph | codebase-derived | Both files enumerate the set verbatim; every prior carve-out ships with its own "Why X is inert" paragraph. |
| D-4 | Scope closed to `.known-extensions` only — no other extensionless dotfile is added | codebase-derived | The issue's "at minimum" is an open set. `.npmrc`/`.nvmrc`/`.yarnrc.yml` affect toolchain/install behavior and must keep selecting SUITE (`6-verify.md` names them explicitly). |
| D-5 | The SUITE format lane rewriting unrelated pre-existing files is out of scope | codebase-derived | Standing documented behavior with a manual remedy in `6-verify.md`; this change alters lane classification only. |

## Affected files/modules

- `plugins/dev-pipeline/skills/run/tools/is-inert-diff.sh` — `INERT_RE` (line 32) + header inert-set enumeration (lines 10-13)
- `plugins/dev-pipeline/skills/run/tools/is-inert-diff-selftest.sh` — new `check` cases, `CANONICAL_RE` (line 100), `GOLDEN_CASES` (lines 103-129), DRIFT MODEL header prose (lines 13-20) and golden-master tail comment (lines 93-96)
- `plugins/dev-pipeline/skills/run/stages/6-verify.md` — lane-reference pattern list + new rationale paragraph

## Reuse inventory

- `is-inert-diff.sh` `INERT_RE` — the single existing definition; extended, not duplicated.
- `is-inert-diff-selftest.sh` `check()` / `run()` / `classify_old()` helpers — reused as-is for the new cases.
- `pipeline-doctor.sh` section 5h already discovers and runs `is-inert-diff-selftest.sh`; no registration needed.

`none — no new helpers introduced.`

## Implementation steps

1. **(test-first)** Add three `check` cases to `is-inert-diff-selftest.sh`: canonical path → INERT; a `.known-extensions` outside `.claude/second-shift/` → SUITE; canonical path mixed with a `.ts` source → SUITE. Run the selftest and confirm the INERT case FAILS (proving the case is real).
2. Add `^\.claude/second-shift/\.known-extensions$` as one new alternative in `INERT_RE` (`is-inert-diff.sh` line 32), placed after the `jsonl?` alternative and before the ignore-file alternatives.
3. Update `CANONICAL_RE` (selftest line 100) to the identical new string.
4. Add the three new paths to `GOLDEN_CASES` so the parity tail covers the new alternative.
5. Update the `is-inert-diff.sh` header enumeration (lines 10-13) to name the new carve-out.
6. Reword the selftest's DRIFT MODEL header prose + golden-master tail comment: `CANONICAL_RE` is a lockstep mirror of `INERT_RE`, edited in lockstep with it, not a frozen copy of a historical inline grep.
7. Update `6-verify.md`'s lane-reference pattern list, and add a "Why `.claude/second-shift/.known-extensions` is inert" paragraph alongside the existing per-class paragraphs.
8. Re-run the selftest — all cases and the parity tail pass.

## Test strategy

Test-first (step 1 precedes step 2): this is a behavior change to a classifier with an existing pure-local selftest, so the new cases are written and observed failing before the regex changes.

No new test file — `is-inert-diff-selftest.sh` is the established home and is auto-discovered by both CI (`*-selftest.sh` glob) and `pipeline-doctor.sh` section 5h.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | `.known-extensions`-only diff → INERT (exit 0) | 1, 2 | `check ".known-extensions (canonical path)" inert` |
| AC-2 | `.known-extensions` + real source → SUITE (exit 1) | 1, 2 | `check ".known-extensions + .ts" suite` |
| AC-3 | `.known-extensions` outside `.claude/second-shift/` → SUITE | 1, 2 | `check ".known-extensions outside second-shift" suite` |
| AC-4 | Golden-master parity tail passes against the updated regex | 3, 4 | golden-master parity loop over `GOLDEN_CASES` |

## Verification commands

```bash
bash plugins/dev-pipeline/skills/run/tools/is-inert-diff-selftest.sh
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}
```

## Risks / rollback notes

- **Risk: widening the classifier hides a real suite regression.** Mitigated by D-1's exact-path anchor — the single narrowest pattern covering the real case. A `.known-extensions` anywhere else still selects SUITE (AC-3 asserts it).
- **Risk: the two regex copies drift.** The golden-master tail is precisely the guard for this and is extended (step 4) rather than weakened.
- **Unaffected, verified:** `check-extensions.sh` skips dotfiles as control files (line 69), so it never lints this file as extension content. `pre-commit-typecheck-selftest.sh` lines 98-108 assert lockstep only on the `.claude/**/*.{mjs,cjs}` sub-pattern via literal `grep -qF`, so a new alternative cannot break that guard.
- **Rollback:** revert the commit; the change is two regex strings, test cases, and prose.

Unverified references: none. All cited paths and line numbers were read in a pinned `origin/main` checkout.

## Out-of-scope

- The SUITE format lane rewriting unrelated pre-existing files (D-5) — standing behavior, tracked separately.
- Any other extensionless dotfile (D-4). `.npmrc`/`.nvmrc`/`.yarnrc.yml` intentionally keep selecting SUITE.
- The pre-commit hook's `needs_typecheck()` predicate — a separate, JS/TS-relevance-gated predicate.
