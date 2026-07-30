# Plan — #260: record a pause span on every cross-session resume

## Context / problem framing

`pauseSpans[]` is written at exactly one site today: `statectl pause-add`, called from
`stages/8-code-review.md` step 2 (the Stage-8 crash-recovery entry). But `SKILL.md`
**Resume logic** rule 2 admits a resume from *any* `currentStage`, and every resume below
Stage 8 records nothing — so the idle gap between the dead session's last write and the
resuming session's first write is billed as compute. `tools/stage-times.sh` then reports
multi-day "effective" durations for runs that used minutes, and `perf-retro` consumes that
corpus to decide what to optimize.

The reporting side is already correct and needs no change: `tools/stage-times.sh:62` reads
`.pauseSpans // []` (tolerates absence) and `:76-79` already subtracts per-span/per-stage
overlap. **The whole fix is making the span get recorded**, and moving the writer from an
opt-in call site to the shared write seam so no resume path can forget it.

## Assumptions

1. **`atomic_write` is the sole write seam.** Verified: `statectl.sh:318` is the only
   function that writes a state file. Every other `state_path` consumer is read-only
   (`read_state:343`, `require_eval_file`, `require_report_file`) or a file-level
   quarantine `mv` (`cmd_reclaim`, `cmd_init`'s eval/report quarantine). No `> "$state"`
   bypass exists.
2. **`$CLAUDE_CODE_SESSION_ID` is the harness's native session identity**, present inside
   any Claude Code session and independent of the opt-in OTel/cost-tracking wiring.
3. **One run has one owning session at a time.** A pre-existing pipeline precondition
   (`cmd_reclaim` already warns that concurrent owners are unsupported). AC-4 holds only
   under it; interleaved live sessions are out of scope.
4. **`now_iso` is second-resolution** (`date -u +%Y-%m-%dT%H:%M:%SZ`), so any test asserting
   `from < to` needs an explicit `sleep 1` — the idiom `(pause1)` already uses.

## Decision Ledger

| D-n | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Where the seam logic lives | A new helper `apply_session_seam()` **[NEW]** in `statectl.sh`, called from `atomic_write` after the existing waiver fold and before the tmp write. Not inlined into `atomic_write`'s body, matching the existing `apply_waivers` factoring. | codebase-derived (`statectl.sh:318-340`, `apply_waivers:398`) |
| D-2 | How the seam reads the on-disk predecessor | Raw `cat` + a `jq empty` parse probe — **never** `read_state`, which `die`s on a missing (`:347`) or unparseable (`:351`) file. The seam must never fail the host write; that would break every subcommand on exactly the truncated-state-file crash-recovery path this issue serves. | codebase-derived (`statectl.sh:343-353`) |
| D-3 | Which surviving subcommand hosts the `--force`/waiver cases that used `pause-add` | `checkpoint` — `require_mutable`-guarded (`statectl.sh:1241`), takes `--force`, and its payload is free-shape so a case needs no schema ceremony. Applies to `(pause2)`, `(fr1)`, `(fr2)`, `(am1)`, `(am2)`, `(wv1)`, `(wv3)`. | codebase-derived (`statectl.sh:1241`; `statectl-selftest.sh:1117-1129,3196-3280`) |
| D-4 | How the suites control session identity | Each of the three named suites exports a **fixed synthetic** `CLAUDE_CODE_SESSION_ID` at the top, overriding whatever the harness supplies; a resume case overrides per call (`CLAUDE_CODE_SESSION_ID=<other> sct …`, which bash propagates through the `sct` function); an anonymous case runs in a subshell that unsets it. `scenario-lib.sh` is left untouched. | codebase-derived (`scenario-lib.sh:29-39`) |
| D-5 | Which write carries the span in `e2e-replay-selftest.sh` scenario 3 | The **second** `pipeline-session-add` (the one recording session `2222…`) — it becomes the resuming session's first mutating write once `pause-add` is deleted. D-3's "`pipeline-session-add` … never writes spans itself" means the subcommand holds no span-writing code; it inherits the seam like every other subcommand. | ticket-sourced — intake gap 1, https://github.com/manoldonev/second-shift/issues/260#issuecomment-5130385303 |
| D-6 | The qualified stamp/span predicate | **Stamp** iff the writer's `$CLAUDE_CODE_SESSION_ID` is non-empty AND the on-disk predecessor parses AND its `.status == "in_progress"`; otherwise leave the stored value untouched (never write `null`). **Span** additionally requires a stored `lastWriteSessionId` that is non-empty and differs from the writer's, plus a predecessor `.lastUpdatedAt` to anchor on. | ticket-sourced — intake gap 4, https://github.com/manoldonev/second-shift/issues/260#issuecomment-5130385303 |
| D-7 | The #243 pure-refusal fallback gets its own named test case | It is the one `atomic_write` call site whose `content` is byte-identical to the on-disk predecessor (`statectl.sh:3016` passes `read_state` output straight through), so both the stamp and the D-2 clock advance must be injected wholly by the seam. Covered as an explicit first-resume-write case. | ticket-sourced — intake gap 2, https://github.com/manoldonev/second-shift/issues/260#issuecomment-5130385303 |
| D-8 | What the new `state-schema.md` entry must state | Type (`string \| null`), writer (the shared seam), and the two distinct absences: **absent** on pre-upgrade files (migrate-by-absence) versus **left untouched** on an anonymous write (never written as `null`). | ticket-sourced — intake gap 3, https://github.com/manoldonev/second-shift/issues/260#issuecomment-5130385303 |

## Affected files/modules

All under `plugins/dev-pipeline/skills/run/`:

| File | Change |
| --- | --- |
| `statectl.sh` | `apply_session_seam()` **[NEW]**; call it from `atomic_write`; delete `cmd_pause_add` + its dispatcher entry; update `cmd_init`'s no-bump rationale comment and the terminal-guard header comment |
| `statectl-selftest.sh` | replace `(pause1)`/`(pause2)`; re-anchor `(fr1)`,`(fr2)`,`(am1)`,`(am2)`,`(wv1)`,`(wv3)` onto `checkpoint`; add the new seam cases |
| `e2e-replay-selftest.sh` | scenario 3: drive the resume by switching session id instead of calling `pause-add`; update the scenario header comment |
| `scenario-liveness-selftest.sh` | resume-leg comment/coverage updated to the new contract |
| `SKILL.md` | CLI-surface list, Resume-logic rule 2, resume table row |
| `state-schema.md` | `pauseSpans` writer prose; new `lastWriteSessionId` entry |
| `stages/8-code-review.md` | delete step 2 |

**No change** to `tools/stage-times.sh`. `docs/plans/*.md` are the historical-note carve-out
and stay untouched.

## Reuse inventory

- `apply_waivers()` (`statectl.sh:398`) — the existing "mutate the document inside
  `atomic_write`" idiom; `apply_session_seam` mirrors its shape (takes a doc, returns a doc
  on stdout) rather than inventing a new one.
- `now_iso()` (`statectl.sh`) — timestamp source; reused for `span.to`.
- `state_path()` (`statectl.sh`) — resolves the predecessor path; reused rather than
  re-deriving.
- `require_mutable()` (`statectl.sh:419`) — **not** reused by the seam. The seam's gate is
  the predecessor's `.status`, read from disk; `require_mutable` operates on the
  caller-supplied document and would die rather than degrade.
- `sct` / `sct_err` / `sct_rc` / `reset_state` / `complete_stage` (`scenario-lib.sh`) —
  reused unchanged for every new test case.
- New helpers introduced: `apply_session_seam()` only. Confirmed no existing equivalent
  (no function in `statectl.sh` reads the predecessor for a write decision today).

## Implementation steps

1. **`statectl.sh` — add `apply_session_seam()`.** Signature `apply_session_seam <key>
   <content>` → mutated document on stdout. Logic, in order:
   - Writer id empty → echo `content` unchanged, return (anonymous: no stamp, no span).
   - Read the predecessor raw (`cat "$(state_path "$key")" 2>/dev/null`). Missing or
     `jq empty` fails → stamp only (`.lastWriteSessionId = $writer`), return.
   - Predecessor `.status != "in_progress"` → echo `content` unchanged, return.
   - Stamp. Then, iff stored `.lastWriteSessionId` is non-empty **and** differs from the
     writer **and** predecessor `.lastUpdatedAt` is non-empty: append
     `{from: <prev .lastUpdatedAt>, to: <now>, reason: "session-resume"}` to `.pauseSpans`
     and set `.lastUpdatedAt = <now>`.
   - Every `jq` failure falls back to echoing the input document — the seam never fails the
     host write.
2. **`statectl.sh` — wire it into `atomic_write`**, immediately after the waiver-fold block
   and before `resolve_writer`/tmp write, so the seam observes the fully-folded document.
3. **`statectl.sh` — delete `cmd_pause_add`** (`:1800-1848`) and its dispatcher entry
   (`:2984`).
4. **`statectl.sh` — update the two stale comments** AC-7 names: `cmd_init`'s
   "no lastUpdatedAt bump (reclaim staleness anchors stay untouched)" rationale (`:1046`)
   gains the resume carve-out, and the terminal-guard header block (`:9-14`) drops its
   `pause-add` ordering claim.
5. **`stages/8-code-review.md`** — delete step 2 entirely and renumber; the pause is now
   recorded automatically by whichever write comes first.
6. **`SKILL.md`** — drop `pause-add` from the CLI-surface list; update Resume-logic rule 2
   and the `currentStage == 7` resume-table row so neither claims a manual span call.
7. **`state-schema.md`** — rewrite the `pauseSpans` entry's writer prose (the seam, not
   `pause-add`); add the `lastWriteSessionId` entry per D-8.
8. **`statectl-selftest.sh`** — export the fixed synthetic session id at the top (D-4);
   re-anchor the six `--force`/mode cases onto `checkpoint` (D-3), including `(wv1)`'s
   `.subcommand` assertion; replace `(pause1)`/`(pause2)` with the new seam cases below.
9. **`e2e-replay-selftest.sh`** — scenario 3 per D-5; update the header comment at `:46`.
10. **`scenario-liveness-selftest.sh`** — update the resume-leg comment at `:65` and its
    coverage to the new contract.

## Test strategy

Verify-after (infra/behavior change to a shell helper; the suites are the only harness).
New `statectl-selftest.sh` cases, each setting `CLAUDE_CODE_SESSION_ID` explicitly:

| Case | Asserts |
| --- | --- |
| `(sr1)` | same-session writes → no `pauseSpans` key, stamp present |
| `(sr2)` | cross-session via `init --mode` as first writer → one span, `from` = dying `lastUpdatedAt`, `lastUpdatedAt` advanced to `span.to` |
| `(sr3)` | cross-session via `set-stage` as first writer → same contract (order-independence) |
| `(sr4)` | K=3 sequential resumes → exactly 3 spans, pairwise non-overlapping; includes a resumed session whose only write is the `init --mode` restamp |
| `(sr5)` | anonymous write → no span, stored stamp untouched; the following resume still records its span anchored at the anonymous write's timestamp |
| `(sr6)` | post-terminal `pipeline-session-add` backfill on a `completed` run → session appended, no span, no stamp change, no `--force` needed |
| `(sr7)` | `mark-completed` as the resuming session's first write → stamps AND spans (predecessor still `in_progress`) |
| `(sr8)` | predecessor unparseable → stamps, no span, host write succeeds |
| `(sr9)` | predecessor parses but has no `.lastUpdatedAt` → stamps, no span, host write succeeds (the case `pause-add` died on) |
| `(sr10)` | #243 pure-refusal fallback as a resuming session's first write → stamps, one span, clock advanced (D-7) |
| `(sr11)` | subsequent writes by the resuming session append nothing |

`e2e-replay-selftest.sh` scenario 3 asserts one span with the correct anchor, driven purely
by switching session ids. `scenario-liveness-selftest.sh`'s resume leg asserts the span
appears with no explicit pause call anywhere in the composition.

Mutation targets (each new conditional in `apply_session_seam` must be killable): empty
writer id; unparseable predecessor; non-`in_progress` predecessor; empty stored stamp;
equal stored stamp; empty predecessor `.lastUpdatedAt`.

`unitTestSurface` is **skip** — this repo declares no `unitTestScope`, so there is no
mutation surface; coverage is the shell selftests above.

## Acceptance-criteria traceability

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |
| AC-1 | One span per resume, anchored on the dying write, from any first-writer | 1, 2 | `(sr2)`, `(sr3)` |
| AC-2 | Post-terminal backfill: no span, no stamp, exemption intact | 1 | `(sr6)` |
| AC-3 | Single-session run writes no `pauseSpans`; `paused 0 min`, `effective == wall` | 1 | `(sr1)`, existing `(pause3)` stage-times fixture case |
| AC-4 | K sequential resumes → K non-overlapping spans; no negative stage time | 1, 2 | `(sr4)`, `(sr11)` |
| AC-5 | Anonymous write: no span, stamp untouched; following resume still recorded | 1 | `(sr5)` |
| AC-6 | `stage-times.sh` effective < wall by span total; straddling stage shrinks | — (no code change; `:62`,`:76-79` already do this) | `(sr4)` + the existing `(pause3)` stage-times fixture case |
| AC-7 | `pause-add` fully removed, docs updated, waiver cases re-anchored | 3, 4, 5, 6, 7, 8 | `(fr1)`,`(fr2)`,`(am1)`,`(am2)`,`(wv1)`,`(wv3)` re-anchored on `checkpoint`; grep sweep in Verification |
| AC-8 | Test surface across all three suites; explicit per-call session ids | 8, 9, 10 | the whole `(sr*)` set + scenario 3 + the liveness resume leg |

## Verification commands

```bash
# Full repo gates (CLAUDE.md), run from the worktree root:
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -P 4 -n1 -I{} env SKIP_STRESS=1 bash {}

# AC-7 removal sweep — must return nothing outside docs/plans/:
grep -rn "pause-add\|cmd_pause_add" plugins/ docs/ --include='*.sh' --include='*.md' \
  | grep -v '^docs/plans/'
```

The three headline suites are also worth running alone while iterating:
`statectl-selftest.sh`, `e2e-replay-selftest.sh`, `scenario-liveness-selftest.sh`.

## Risks / rollback notes

- **Highest risk: the seam runs on every state write.** A bug here breaks all 31 call
  sites, not one subcommand. Mitigated by the never-fail-the-host-write rule (every branch
  falls back to the unmodified document) and by `(sr8)`/`(sr9)` proving degradation is
  tolerated rather than fatal.
- **Second-resolution timestamps** can produce a zero-length span when two writes land in
  the same second. Harmless in production (subtracts 0) but will flake any `from < to`
  assertion — every such test uses the existing `sleep 1` idiom.
- **Suites that inherit a real session id** (the ones not touched here, e.g.
  `stage7-perrepo-checkpoint-selftest.sh`) stay same-session for all their writes, so they
  record no spans and their assertions are unaffected. Verified there are no whole-document
  or top-level key-set assertions that a new field would break.
- **Rollback** is a clean revert: the feature is one helper plus one call line, and
  `lastWriteSessionId` is additive — a state file carrying it is still valid input to the
  pre-change `statectl`.

## Out-of-scope

- **Interleaved concurrently-live sessions** — the trigger cannot distinguish a dead
  predecessor from two live sessions alternating writes. Accepted, not fixed; AC-4 holds
  only under the single-owner precondition.
- **Single-session idle gaps** (operator steps away, no session death) — tracked as #276.
  No resume event exists for this mechanism to hook.
- **`tools/stage-times.sh`** — already pause-aware; touching it is out of scope.
- Unverified references: none.
