# Plan — #123: session registration moves into the statectl write seam

## Context / problem framing

`pipelineSessions[]` is the session set `pipeline-cost-block.sh` attributes OTel cost against. Today it is written **only** by explicit `statectl pipeline-session-add` calls that three prose sites must remember to make: `stages/2-worktree.md`, `SKILL.md` resume rule 2, and `stages/8-code-review.md`. A missed call is silent — the run terminalizes with the array empty or short and nothing objects.

The sibling field `pauseSpans[]` had the identical shape until #260 moved it into `apply_session_seam()` (`plugins/dev-pipeline/skills/run/statectl.sh:356`), called from `atomic_write()` (`:398`). There it is **observed** at every mutating write rather than **declared** by whichever site remembered. This change applies the same move to session registration, at the same site, from the same signal.

The seam already holds every input registration needs: the writer's `$CLAUDE_CODE_SESSION_ID`, the on-disk predecessor's `status`, and its `lastWriteSessionId`. Nothing new has to be plumbed.

Consequence worth stating: because both fields then derive from one signal inside one function, the #232 shape (a `pauseSpans[]` entry alongside a single `pipelineSessions[]` record) stops being *detectable* and becomes *unreachable* within a run.

## Assumptions

1. `$CLAUDE_CODE_SESSION_ID` is the native Claude Code session UUID and is the same value the OTel exporter tags as `session.id` — as `state-schema.md` already asserts for `pipelineSessions[].sessionId`.
2. A legitimately anonymous write (env var unset — headless/CI, or an operator running `statectl` from a plain terminal) should register nothing. The seam's existing early return at `statectl.sh:359` already delivers this.
3. Pre-change state files are not migrated. In-flight runs keep whatever they recorded (D-7).
4. The repo's testing contract couples a guard change to its selftest in the same diff, so the selftest edits are part of this change rather than a follow-up.

## Decision Ledger

Hydrated verbatim from the pre-flight ledger at `.claude/pipeline-state/123-ledger.md`.

| ID  | Decision | Resolution | Provenance |
| --- | -------- | ---------- | ---------- |
| D-1 | Where session registration happens — a completion gate, a doctor WARN, or a mechanical helper (the body's three candidate designs) | **None of the three: fold registration into the shared write seam `apply_session_seam` (`plugins/dev-pipeline/skills/run/statectl.sh:356-394`).** The seam already runs on every `atomic_write` (`:410`), already reads `$CLAUDE_CODE_SESSION_ID` (`:358`), and already detects the session-identity switch (`:386`). #260 made exactly this move for the sibling field `pauseSpans[]`; session registration is the same problem at the same site. Registration becomes *observed*, not *declared*. | codebase-derived |
| D-2 | Whether the explicit `pipeline-session-add` subcommand survives | **Retained, unchanged.** The seam is deliberately inert on a terminal predecessor (`statectl.sh:374-379`), so it cannot serve the documented post-terminal manual backfill (`cost-tracking-setup.md:111`); that backfill is pinned by `(sr6)` and `(rm7)`. What is removed is the *prose mandate* at the three call sites — `stages/2-worktree.md:150-158`, `SKILL.md:484-491`, `stages/8-code-review.md:48-54` — which the seam supersedes. | codebase-derived |
| D-3 | What `source` a seam-written record carries, given the seam cannot know "interactive" | **`null`.** *Revised at intake — the original grounding ("no consumer") was wrong:* `perf-retro/SKILL.md:58` degraded-signal 4 does key on `source`. But all three call sites pass `--source interactive` unconditionally against an `interactive \| null` enum, so the field is a **constant** and signal 4 cannot discriminate — read literally it degrades 100% of runs. `null` exposes an already-inert classifier rather than breaking a working one; the same PR re-keys signal 4 off `.mode`. Prose at `state-schema.md:304`. | codebase-derived |
| D-4 | Where the `pauseSpans` non-empty ⟹ ≥2 `pipelineSessions` cross-check lands | **`perf-retro` fidelity triage + a statectl selftest invariant — not a runtime completion gate.** The maintainer's triage names it "the perf-retro cross-check": https://github.com/manoldonev/second-shift/issues/123#issuecomment-5110259664 | ticket-sourced |
| D-5 | Whether Stage 2 gains a completion-evidence precondition on non-empty `pipelineSessions[]` | **No.** Post-seam the gate is satisfiable exactly when the seam fires — both key on `CLAUDE_CODE_SESSION_ID` being set — so it can never fail for a compliant run and never pass for a legitimately anonymous one. A gate that cannot fail is the "prose-presence guard" class CLAUDE.md's testing section rejects. The structural fix replaces the gate rather than joining it. | user-delegated |
| D-6 | Blast radius on existing suites | **In scope and enumerated, not absorbed silently.** Every suite that pins `CLAUDE_CODE_SESSION_ID` and writes state now grows a `pipelineSessions[]` record: `scenario-liveness-selftest.sh:113` (pinned id), `statectl-selftest.sh` cases `(psa1)`–`(psa6)` and `(sr1)`–`(sr13)` which assert exact counts, and `e2e-replay-selftest.sh:399` which asserts length 2. | codebase-derived |
| D-7 | Migration of in-flight runs at upgrade | **Additive, no backfill.** A run mid-flight when the seam lands registers its resuming session and keeps whatever Stage-2 record it already has; the array is append-only and idempotent on `sessionId`. Same migrate-by-absence posture `lastWriteSessionId` took (`state-schema.md:64`). | codebase-derived |
| D-8 | `launchedAt` semantics under seam registration | **First mutating state write by that session**, documented as such in `state-schema.md`. Not a regression in precision: the current Stage-2 call also stamps at call time, and Stage 2 is not session launch either. | codebase-derived |
| D-9 | Boundary against the adjacent open work | **Out of scope, named in the issue:** single-session idle gaps (#276 — no session boundary exists, so no seam signal applies); the Stage-9 `costBlockApplied` completion gate and `--force`/waiver transport (#241 → #243, already landed in part on `origin/main`). This issue owns session *registration* only. | codebase-derived |
| D-10 | Seam behavior on a non-UUID writer id (added at intake — spec-reviewer blocker, verified) | Apply the same `8-4-4-4-12` hex test as `cmd_pipeline_session_add` (`statectl.sh:1367-1371`) and **skip registration** on a mismatch — never fail the host write, per the seam's `:349-353` contract. **Scoped to registration only:** the `lastWriteSessionId` stamp and the `pauseSpans[]` span keep accepting any non-empty string, as #260 shipped them. Preserves `(psa3)`/`(psa6)` and keeps `cost-tracking-setup.md:114`'s "can no longer reach this state" claim true. | codebase-derived |

## Affected files/modules

| File | Change |
| --- | --- |
| `plugins/dev-pipeline/skills/run/statectl.sh` | `is_session_uuid()` `[NEW]`; registration inside `apply_session_seam()`; header comment |
| `plugins/dev-pipeline/skills/run/state-schema.md` | `pipelineSessions` writer prose (`:304`); `skipped-no-sessions` catalog entry (`:324`) |
| `plugins/dev-pipeline/skills/run/SKILL.md` | resume rule 2 session block only |
| `plugins/dev-pipeline/skills/run/stages/2-worktree.md` | drop the session-record block |
| `plugins/dev-pipeline/skills/run/stages/8-code-review.md` | drop the session-record block |
| `plugins/dev-pipeline/skills/run/cost-tracking-setup.md` | writer attribution at `:7`, `:17`, `:94`, `:111`, `:114` |
| `plugins/dev-pipeline/skills/run/pipeline-cost-block.sh` | Stage-2 writer attribution in the header comment and the `skipped-no-sessions` log line |
| `plugins/dev-pipeline/skills/run/statectl-selftest.sh` | `(psa1)`/`(psa2)`/`(psa5)` exact-count **and** positional-index updates; `(sr5)` extended; `(sr14)`–`(sr16)` `[NEW]` |
| `plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh` | pinned-id rationale comment (`:111-113`) — comment only, no assertion change |
| `plugins/dev-pipeline/skills/run/e2e-replay-selftest.sh` | scenario 3 reaches length 2 without the explicit calls |
| `plugins/dev-pipeline/skills/perf-retro/SKILL.md` | AC-10-scoped cross-check; degraded-signal 4 re-keyed |

**`SKILL.md`'s CLI-surface listing is deliberately NOT edited.** It sits in a documented lockstep pair with `statectl.sh`'s usage block (`scripts/lockstep-manifest.tsv:121-134`), but it does not list `pipeline-session-add` at all, and D-2 retains that subcommand unchanged — so neither half of the pair moves. The only `SKILL.md` edit is resume rule 2.

**`scenario-liveness-selftest.sh` needs a comment-only edit.** No scenario asserts on `pipelineSessions`, so no assertion changes — but its pinned-id rationale at `:111-113` explains the pin purely in terms of `pauseSpans`, and after this change the pin also determines that every scenario registers exactly one session. Left alone the comment becomes a half-truth about its own mechanism.

## Reuse inventory

- `now_iso()` (`statectl.sh`) — existing timestamp helper; reused for `launchedAt`.
- The `8-4-4-4-12` hex regex currently inline in `cmd_pipeline_session_add` (`statectl.sh:1370`) — extracted to `is_session_uuid()` `[NEW]` and called from **both** sites. Two copies of one regex is exactly the lockstep drift this repo rejects, so extraction is the reuse decision rather than duplication. `cmd_pipeline_session_add`'s behavior is unchanged (same predicate, same refusal text).
- The append-if-absent jq idiom in `cmd_pipeline_session_add` (`:1381-1391`) — the seam's registration mirrors its `any($existing[]; .sessionId == $sid)` idempotency test.
- No other new helpers introduced.

## Implementation steps

1. **`is_session_uuid()` `[NEW]`** in `statectl.sh` near the other small predicates: `[[ "$1" =~ ^[0-9a-fA-F]{8}-...{12}$ ]]`. Re-point `cmd_pipeline_session_add`'s inline test at it, keeping its existing `die` message byte-identical so `(psa3)`/`(psa6)` still pass unmodified.
2. **Register inside `apply_session_seam()`.** Add a small local jq application that appends `{sessionId, launchedAt: <now>, source: null}` when `is_session_uuid "$writer_sid"` holds AND the id is not already present. Apply it on:
   - the absent/degraded-predecessor branch (`:365-371`) — this is the Stage-1 `init` write, so the first session registers a stage earlier than today;
   - the `in_progress` branch (`:381-392`), alongside the stamp.

   Do **not** apply it on the terminal-predecessor branch (`:374-379`), which returns early untouched — that keeps a post-terminal backfill the exclusive business of `pipeline-session-add` (D-2).
3. **Preserve the never-fail contract.** Every new jq application follows the file's existing `out=$(jq ... ) || out="$content"` fallback shape, so a jq failure degrades to the un-registered document rather than failing the host write (AC-8).
4. **Seam header comment** (`:336-354`) gains the registration paragraph, including the registration-only scoping of the UUID test (stamp and span still accept any non-empty string).
5. **Drop the three prose mandates** at `stages/2-worktree.md`, `SKILL.md` resume rule 2, and `stages/8-code-review.md`, leaving each site's surrounding contract intact (Stage 8 keeps its `init --mode` re-assert; the resume rule keeps its summary line).
6. **Doc writer attribution** — `state-schema.md:304` and `:324`, `cost-tracking-setup.md:7,17,94,111,114`, `pipeline-cost-block.sh`'s header comment plus its `skipped-no-sessions` log line, which currently asks "Stage 2 session derivation did not run?" about a stage that no longer writes the field.
7. **`perf-retro/SKILL.md`** — add the contradiction check to fidelity triage, scoped per AC-10 to runs whose `startedAt` post-dates the change, with the pre-seam shape reported as a distinct "pre-seam accounting" note; and re-key degraded-signal 4 off `.mode`, since `source` is a constant.
8. **Selftests** — `statectl-selftest.sh` pins one session id globally (`:52`), so the harness itself now registers a record before any `(psa*)` case runs. Update **both** the exact-count assertions and the positional reads in `(psa1)`/`(psa2)`/`(psa5)`: `(psa1)`'s `count` goes 1→2, `(psa2)`'s 2→3, and each `.pipelineSessions[0]` / `[1]` read shifts by one so it still addresses the record the case authored. `(psa3)`/`(psa4)`/`(psa6)` assert refusals rather than counts and are unaffected. Then add `[NEW]` cases:
   - `(sr14)` seam registers the writing session on a fresh `init`, with `source: null`;
   - `(sr15)` a malformed `CLAUDE_CODE_SESSION_ID` registers nothing, yet the host write succeeds and the stamp still lands;
   - `(sr16)` the invariant: a two-session run yields a `pauseSpans[]` entry **and** two `pipelineSessions[]` records from seam writes alone, with no explicit `pipeline-session-add` call.
   - `e2e-replay-selftest.sh` scenario 3: drop the two explicit calls and assert the length-2 result still holds.
   - `scenario-liveness-selftest.sh:111-113`: extend the pinned-id rationale comment to cover session registration alongside `pauseSpans`.

## Test strategy

**Verify-after** — this is a behavior change to a shell guard, not a `unitTestScope` surface (the repo configures `unitTestScope: null`, so there is no mutation surface and no co-located unit-test layer). Coverage lands as behavioral selftest cases in the suite that already owns the seam, per the repo's tier map (`docs/testing.md`: "one script's behavior against fixtures → a per-tool behavioral selftest").

`(sr16)` is the load-bearing addition: it is the only case that would fail if a future edit re-separated the two fields, and it is written as a scenario (drive two sessions through real writes) rather than as a unit assertion on the function.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | Writer id present in `pipelineSessions[]` after a mutating write | 2 | `(sr14)` |
| AC-2 | Repeated writes by one session yield exactly one record | 2 | `(sr14)` |
| AC-3 | A resuming session appends both a span and a second record | 2 | `(sr16)` |
| AC-4 | Anonymous write registers nothing, host write succeeds | 2 | `(sr5)` (existing, extended with a `pipelineSessions` assertion) |
| AC-5 | Terminal predecessor registers nothing; backfill still applies | 2 | `(sr6)`, `(rm7)` (existing, unmodified) |
| AC-6 | End-to-end run yields a set `pipeline-cost-block.sh` accepts | 2, 5 | `e2e-replay-selftest.sh` scenario 3 |
| AC-7 | Seam writes alone cannot produce span-without-two-records in a run | 2 | `(sr16)` |
| AC-8 | Seam never fails its host write on any branch | 3 | `(sr9)`, `(sr13)` (existing — degraded/pre-upgrade predecessors), `(sr15)` |
| AC-9 | Non-UUID writer id registers nothing; stamp and span unaffected | 1, 2 | `(sr15)` |
| AC-10 | `perf-retro` scopes the cross-check to post-change runs | 7 | — no test (covered-by-selftest) |

AC-10's row is prose in a skill file with no executable surface; per the repo's "no prose-presence guards" rule it gets the escape hatch rather than a grep assertion.

## Verification commands

```bash
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -P 4 -n1 -I{} env SKIP_STRESS=1 bash {}
bash scripts/check-lockstep-pairs.sh
```

The selftest sweep is run **without** `SKIP_STRESS=1` as well for `statectl-selftest.sh` specifically, since that suite owns the seam and its stress leg is otherwise only exercised on CI's ubuntu lane.

## Risks / rollback notes

- **Every state write now runs one more jq pass.** `statectl-selftest.sh` is already the slowest suite (~94s); registration adds a jq invocation per write. Mitigation: the registration jq is folded into the existing `out=$(jq ...)` application on each branch rather than added as a separate pass, so the write count is unchanged.
- **The seam is on every write path.** A defect here breaks every subcommand, which is precisely why the never-fail fallback (step 3) is non-negotiable and why `(sr15)` asserts the host write still succeeds on the malformed-id path.
- **Attribution widens, in the over-counting direction.** Today only three pipeline sites register, so only the pipeline's own sessions are counted. After this change *any* session whose id is UUID-shaped and which performs a mutating write on an `in_progress` run self-registers — an operator repairing state from another Claude session, or a concurrent `/dev-pipeline:pipeline-retro` that writes, would be billed into the run. This is accepted rather than mitigated: it is the same widening #260 already took for `pauseSpans[]` (an operator repair write anchors a span), and over-attribution is the safer error than the silent under-attribution this issue exists to fix. Recorded so the first surprising cost block is diagnosable rather than mysterious.
- **Rollback** is a clean revert: the change is additive to one function plus doc/test edits, with no state migration to unwind. A reverted seam leaves already-registered records in place, harmlessly.
- **Not a risk, worth recording:** the run implementing this uses the *installed* plugin cache (2.9.0), while the edit lands in the repo copy. The pipeline driving this change cannot be destabilized by it mid-run.

## Out-of-scope

- Single-session idle gaps (#276) — no session boundary exists, so no seam signal applies.
- The Stage-9 `costBlockApplied` completion gate and `--force`/waiver transport (#241 → #243).
- Backfilling historical state files (D-7).
- Any change to `pipeline-session-add`'s own contract beyond re-pointing its regex at the shared predicate.

Unverified references: none.
