# Plan: capture the tool target in the audit ledger (#244)

## Context / problem framing

`plugins/audit-toolkit/hooks/audit-tool-calls.sh` records **that** a tool ran, never **what it ran on**. Every row carries the same seven scalars — `ts, session_id, event, tool, subagent, command_name, outcome` — so the ledger can prove *a* `Read` happened somewhere in a session and nothing more.

The identifying data is already in the hook's hands: it reads the entire hook payload into `$PAYLOAD` and reaches into `.tool_input` for `subagent_type`, then discards the rest. `.tool_input.file_path` sits in that same object.

The consequence is not merely thin observability. `pipeline-retro`'s Step 3 mandates diffing `stages.N.skillsLoaded[]` against the ledger's `Skill` invocations, calling a state-recorded load absent from the ledger *"a fabricated evidence write, strictly worse than the silent skip the gate exists to stop"*. That diff is unperformable today: `Skill` rows exist but carry no identity, so the check can establish count and timing but never *which* skill. Three retro datapoints on the issue record it failing for exactly this reason.

This change adds one field. The `statectl` preconditions that would consume it are **out of scope** (#243 §3).

### Measured grounding for the `Skill` branch

Intake's `spec-reviewer` returned `blocked`, arguing the `Skill` branch is dead code because `plugins/audit-toolkit/skills/audit/SKILL.md:19` and `plugins/audit-toolkit/skills/audit-history/SKILL.md:37` both state the harness never fires `PostToolUse` for `Skill()`.

Measured against the live ledger corpus in this checkout, those two doc claims are false:

| Query over `.claude/audit/*.jsonl` | Count |
| --- | --- |
| rows with `.tool == "Skill"` | 113 |
| distinct sessions containing one | 68 |
| rows with `.tool == "Workflow"` | 225 |

A representative row:

```json
{"ts":"2026-07-20T18:45:31Z","session_id":"00465e5f-…","event":"PostToolUse",
 "tool":"Skill","subagent":"","command_name":"","outcome":"ok"}
```

The `Skill` branch is therefore live, and correcting the two stale claims is part of this change rather than a follow-up — they are the doc surface that would otherwise contradict the new field.

## Assumptions

1. The hook payload field names are as the harness documents them: `Read`/`Edit`/`Write` → `tool_input.file_path`, `Bash` → `tool_input.command`, `Skill` → `tool_input.skill`, `Workflow` → `tool_input.scriptPath` \| `tool_input.name`. Verified against the live tool schemas, not inferred from the issue.
2. A selftest feeding synthesized payloads cannot detect harness-shape drift. No end-to-end capture is reachable from a selftest, so this limitation is **stated in the suite** rather than papered over.
3. The ledger stays local-only (gitignored, `0600` in a `0700` dir). No change to its distribution.

## Decision Ledger

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Field name: the issue's flat `target`, or the `args_excerpt.{command,file_path}` shape already documented in `QUERIES.md`? | `target`. A single identifying scalar matches the existing flat schema (`subagent`, `command_name`); `args_excerpt` was a nested remnant of a stripped experimental design whose queries have never returned anything. `QUERIES.md:12,68,74,89` and `SETUP.md:25` are reconciled to `target` in this PR. | codebase-derived |
| D-2 | `Bash` capture: first line truncated to 200 chars (the issue's stated preference and the form its Selftest section pins), or `argv[0]` + first subcommand? | First line, 200 chars, as specified. The narrower form is genuinely safer but discards `/audit`'s Bash visibility, and narrowing requested scope is not this run's call. The spec's justification — "bounded and non-secret **by construction**" — is *not* true of a prefix slice, since flags and env assignments precede payloads (`gh api -H "Authorization: Bearer …"`); the code comment states honest bounded exposure instead of repeating the false claim. Flagged for the reviewer. | deferred |
| D-3 | Absent case: omit `target`, or always emit it as `""`? | Always present, `""` when unmapped. Consistent with `subagent`/`command_name`, which are always present and frequently empty, and it spares every `jq` consumer a `// empty` guard. | codebase-derived |
| D-4 | Path normalization: raw as received, or repo-relative? | Raw. It is the only lossless form; normalization needs a repo root the hook cannot assume, and the consumer (`statectl`) has one. | codebase-derived |
| D-5 | Framing: does the ledger stay "observability only, never a gate"? | Split the roles as the issue directs — advisory for `/audit` and `/audit-history`, admissible as evidence for pipeline gates. The second-sink alternative is rejected: it would duplicate a hook that already receives everything needed. | ticket-sourced — https://github.com/manoldonev/second-shift/issues/244 ("the ledger stays advisory for `/audit` and `/audit-history`, but becomes admissible evidence for `statectl` preconditions") |

## Affected files/modules

- `plugins/audit-toolkit/hooks/audit-tool-calls.sh` — extract `$TARGET` `[NEW]`; add the `target` row field `[NEW]` to the emitted object; correct the header's framing comment.
- `plugins/audit-toolkit/scripts/audit-selftest.sh` — cases `Test 5` `[NEW]`, `Test 6` `[NEW]`, `Test 7` `[NEW]`, `Test 8` `[NEW]`, `Test 9` `[NEW]` covering the per-tool mapping, truncation, and the empty case.
- `plugins/audit-toolkit/skills/audit/QUERIES.md` — row-schema block (`:3-15`), the two dead `args_excerpt` queries (`:68`, `:74`), the stale Tips note (`:89-91`).
- `plugins/audit-toolkit/skills/audit/SETUP.md` — the row field list (`:25`).
- `plugins/audit-toolkit/skills/audit/SKILL.md` — the false `Skill()`-invisibility bullet (`:19`); the observability framing (`:10`).
- `plugins/audit-toolkit/skills/audit-history/SKILL.md` — the false `Skill()`-invisibility limitation (`:37`).

## Reuse inventory

- `jq` single-invocation extraction — the hook's existing idiom (`jq -r '…' <<<"$PAYLOAD"`, `:15-22`). `$TARGET` reuses it; no new dependency, no second parse pass beyond the existing per-field ones.
- `ok()` / `fail()` counters and the `PASS`/`FAIL` tally in `plugins/audit-toolkit/scripts/audit-selftest.sh:32-33` — new cases use them unchanged.
- The `SID`-scoped `mktemp`-free ledger + `cleanup` trap (`:26-30`) — new cases append to the existing smoke session rather than introducing another ledger to clean up.
- New helpers introduced: none.

## Implementation steps

1. **Hook — extract `$TARGET`.** After the `COMMAND_NAME` extraction (`audit-tool-calls.sh:22`), add one `jq -r` invocation implementing the per-tool `if/elif` chain from the issue. Guard the `Bash` slice so a payload with no `.tool_input.command` yields `""` rather than `null`.
2. **Hook — emit the field.** Add `--arg target "$TARGET"` to the `jq -nc` call (`:38-47`) and `target:$target` to the object literal, positioned after `command_name` so the row reads in extraction order.
3. **Hook — correct the header comment.** Replace the blanket "Observability only… nothing here blocks" (`:8-10`) with the D-5 split: advisory for `/audit` and `/audit-history`, admissible as evidence for pipeline gates. Note beside the `Bash` branch what the truncation does and does not guarantee (D-2) — no "non-secret by construction" claim.
4. **Selftest — per-tool target cases.** Add Test 5 (`Read` → `file_path`), Test 6 (`Skill` → `skill`; `Workflow` → `scriptPath`, then the `name` fallback), Test 7 (`Bash` multi-line + over-length → first line, ≤200 chars), Test 8 (unmapped tool → `target` present and `""`), Test 9 (pre-existing fields unchanged by the addition). Each feeds `$HOOK` a payload and asserts with `jq`.
5. **Selftest — state the fixture limitation.** A comment block above Test 5 recording that these payloads are synthesized from the documented tool schemas and therefore cannot fail on harness-shape drift — the honest scope of the guard, per repo convention against tests that read as coverage they do not provide.
6. **Docs — `QUERIES.md`.** Add `target` to the schema block with its per-tool semantics; rewrite the two `args_excerpt` queries against `.target`; replace the "There's no `args_excerpt`… re-add `tool_input` capture" tip with the current state.
7. **Docs — `SETUP.md`.** Add `target` to the row field list at `:25`.
8. **Docs — the two stale `Skill()` claims.** Rewrite `audit/SKILL.md:19` and `audit-history/SKILL.md:37` to state that `Skill` invocations *are* recorded and now carry the skill name. Adjust `audit/SKILL.md:10`'s framing per D-5.

## Test strategy

Verify-after — this is infrastructure with no product behavior to drive test-first, and the artifact under test is a hook the suite already exercises by piping payloads to it.

The existing four cases are regression cover for the additive change: Test 1 (`tool=Read`), Test 2 (`outcome=fail`), Test 3 (`audit-history` clean), Test 4 (20-way concurrency, `SKIP_STRESS`-guarded) must all stay green, proving pre-existing fields and the atomic-append behavior are untouched. Test 9 asserts that directly rather than leaving it implied.

No mutation surface: `commands.second-shift.unitTestScope` is `null`, so `unitTestSurface` is `skip`.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | `Read`/`Edit`/`Write` → `target` = `file_path` | 1, 2 | Test 5 (AC-1) |
| AC-2 | `Bash` → first line of `command`, ≤200 chars | 1, 2 | Test 7 (AC-2) |
| AC-3 | `Skill` → `skill`; `Workflow` → `scriptPath` \| `name` | 1, 2 | Test 6 (AC-3) |
| AC-4 | Other rows: `target` present and `""`; existing fields and `audit-history.sh` unaffected | 1, 2 | Test 8, Test 9 (AC-4); Tests 1–4 as regression |
| AC-5 | Selftest covers AC-1..AC-4 incl. multi-line over-length `Bash` | 4, 5 | the suite itself — covered-by-selftest |
| AC-6 | Docs reconciled: `QUERIES.md`, `SETUP.md`, both stale `Skill()` claims | 3, 6, 7, 8 | — no test (covered-by-selftest) |

AC-6's doc edits are deliberately not guarded by a test: the repo forbids prose-presence greps, which assert only that a file contains words. Reviewer eyes on the diff are the check.

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -P 4 -n1 -I{} env SKIP_STRESS=1 bash {}
```

Targeted while iterating: `env SKIP_STRESS=1 bash plugins/audit-toolkit/scripts/audit-selftest.sh` (baseline before this change: 3 passed, 0 failed).

## Risks / rollback notes

- **A `Bash` command with an inline credential is now recorded** (D-2). Bounded by the first-line/200-char slice; not eliminated. The ledger is gitignored, `0600` in a `0700` dir, and local-only, so exposure does not widen beyond the machine — but the *content* does, and D-2 records that this was chosen, not overlooked.
- **`jq` cost per hook invocation** rises by one invocation on a payload already in memory. The hook has a 5s timeout in `hooks.json` and currently runs in ~1–2 ms; the added parse is not close to material.
- **A consumer keying on exact row shape** (e.g. a `keys` comparison) would see a seventh field. The only executable consumer, `audit-history.sh:77,82`, selects named fields only and is unaffected — asserted by Test 9 and by Test 3 continuing to pass.
- **Rollback** is the revert of a single additive field: drop `--arg target` and the object key, and the ledger returns to its prior shape. Rows already written keep the field harmlessly.

## Out-of-scope

- The `statectl` preconditions that consume `target` as harness-attested evidence (#243 §3) — the follow-on this unblocks.
- Any redaction pass over `Bash` commands beyond the specified truncation.
- Capturing targets for tools outside the mapped set (`Agent` already has `subagent`; `Grep`/`Glob`/`WebFetch` and others emit `""`).
- Backfilling `target` onto rows already written.
- Hash chain / tamper detection, absent by design in the lean ledger.

Unverified references: none — every path and line cited above was read in this worktree.
