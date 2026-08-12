# lean review verdict — #500

verdict=approve
run_id: review-500-1
session_id: 21cfb6da-0018-483f-bad1-e2d95b7a9e46
rounds: 1
pr: #510
reviewed_head: 1c45a97bf0bc1855f0500c12933c55238aec4f19
reviewed_patch_id: f844266e9812074e58231c353a91da5b3a9fedfc
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 1, full branch range `288d7e1..HEAD` (no prior record to inherit — `inherited_patch_id` is a root).

Panel: security, performance, maintainability, complexity, test-coverage, scope-completeness — 6 selected, 6 returned, none dark. All six returned `approve`. Adversarially probed every new assertion myself in an isolated worktree (13 mutations); results below.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | Warning | `plugins/dev-pipeline/skills/build-lean/SKILL.md:13` | Step 2's re-entry escape hatch — "Export the run's ESTABLISHED id instead of minting one (`cat <issue>-run-id`, **or the id preflight named**)" — has no plumbing behind its second clause. `spawn()` builds the build prompt as a bare `/dev-pipeline:build-lean $ISSUE` (`orchestrate-lean.sh:457,476,534`) and scrubs `RUN_ID`, so the marker's run id that `probe_intake` prints reaches the operator's log and nothing else. A headless `-p` block cannot consume it. On the machine that stopped the run — the case #500 is about — `<issue>-run-id` is present in `MAIN_ROOT/.claude/pipeline-state/` and the first clause works, so the shipped path is sound; a re-entry from a *different* checkout host would silently mint a second identity and split the run's milestone records. Not scored against an `AC-n` (none requires cross-host id continuity, and the ledger's D-1 accepts machine-dependence as the price of tracker-only evidence), and a one-line fix — appending the marker's id to the build prompt — closes it later without a contract change. |
| 2 | Suggestion | `orchestrate-lean.sh:277` | `gh api …/comments --paginate` without `--slurp` emits one JSON array *per page*, so on a >100-comment issue `claim_marker_run_id` returns one line per page and the accept message can print a run id with an embedded newline. It cannot produce a false accept or a false reject (`$(…)` strips the all-empty case to `""`), and it is the identical construction `check-lean-chain.sh:535` already uses against the same endpoint — so this is consistency with the boundary reader, not a new gap. Worth `--slurp` in both, together, whenever either is next touched. |

Nothing blocking. Security's two suppressed items (confidence 60 / 45) were both correctly self-filtered: the `.user.type == "Bot"` filter's breadth is the merge boundary's own established filter, and `$ISSUE` interpolation into the `gh api` path is properly quoted and identical to the pre-existing `gh issue view` usage at `:307`.

Scope-completeness raised one nit (confidence 85) — AC-2's build-side half is carried only by SKILL.md prose with no suite that can fail if the sentence is deleted. Correct as an observation, not a defect: CLAUDE.md's testing tier map forbids prose-presence guards outright, and the code half (preflight's read-only posture) *is* guarded, by `(s3)`. Recorded, not charged.

## Per-AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `orchestrate-lean.sh:312-327` — claimed label **and** bot-authored marker accepted, run spawned. Tracker-only holds literally: the only occurrence of `<issue>-run-id` in the whole file is the comment at `:99` explaining why it is not read. Guarded by `(s1)`; probe P1 (delete the arm) kills `(s1)(s2)(s4)(s5)(s6)`. |
| AC-2 | satisfied | Preflight half: `(s3)` asserts zero writes across the re-entered run; probe P10 (insert a `gh issue edit` on the accept path) kills it. Build half: SKILL.md step 2's skip conditional, prose per D-4 — see finding 1 for its one unplumbed clause. |
| AC-3 | satisfied | `:243-245` — `envfail` (exit 2) before any probe, message names the conflict and points at re-entry. `(s7)` drives it on an unlabelled ticket so the intake reject cannot be mistaken for it; `(s8)` proves it unconditional on a ticket that needed no attestation. Probes P6 (remove) and P7 (make it conditional) each kill both. Jira arm unchanged — existing `(m2)` passes untouched. The flag's `:122` doc sentence stands verbatim. |
| AC-4 | satisfied | Existing `(g1)` passes unchanged; `(s10)` adds the other half — a bot marker with **no** claimed label rejects with the original hand-back wording and spawns nothing. Probe P8 (drop the label half) kills `(s10)`. |
| AC-5 | satisfied | `(s4)` label-alone rejects (probe P2 kills); `(s5)` user-authored marker rejects (probe P3, dropping the `Bot` filter, kills `(s1)` and `(s5)`). |
| AC-6 | satisfied | `(s6)` — `COMMENTS_FAIL` fixture, asserts the failed-read message **and** the absence of the no-marker message. Probe P5 (collapse the read failure to an empty return) kills it. |
| AC-7 | satisfied | `(s1)` asserts both `ok intake: re-entry` and the literal `lean-500-abc123`; `(s9)` asserts the queue arm's own wording and that `re-entry` does *not* appear. |
| AC-8 | satisfied | Step 1 accepts both states, step 2 carries the skip. `build-lean/SKILL.md` is 46 lines. |
| AC-9 | satisfied | Exit-2 remedy and "When it stops" both drop the re-label instruction; `--help` header documents the arm and the tightened flag. `run-lean/SKILL.md` is 58 lines (`(n0)`). `sed -n '2,139p'` lands exactly on the last comment line — `--help` emits 0 non-comment lines. Probes P11 (stale `118`) and P11b (overshoot to `145`) both kill `(n)`. |
| AC-10 | satisfied | All nine required cases present: `(s9)`+existing fresh-queued, `(s1)` re-entry with the id named, `(g1)` neither, `(s4)` label alone, `(s5)` non-bot, `(s6)` failed read, `(s7)(s8)` flag refused with nothing spawned, `(m2)` jira unchanged, `(s3)` zero writes. |
| AC-11 | satisfied | The fake's `"api "*` arm serves the real API's shape. Both decoys are live discriminators, not scenery: probe P4 (drop the tag filter) kills `(s1)(s5)` via decoy 1, probe P3 (drop the type filter) kills `(s1)(s5)` via decoy 2. `(s1)` is scored on the arm — the run id in the log — not on the exit code alone. |

## Verification run at this head

- `orchestrate-lean-selftest.sh` — 64 cases, all green, run with `CLAUDE_CODE_SESSION_ID`/`RUN_ID`/`LEAN_RUN_MODEL` unset.
- `shellcheck -e SC1091,SC2015,SC2181` on both changed shell files — clean (local 0.11.0; CI pins 0.9.0, and nothing here uses a construct the two disagree on).
- `check-lockstep-pairs.sh` — 28 pairs, 0 failed. The S4 decision not to make `CLAIM_MARKER_TAG` a fourth row is defensible *and* covered: probe P13 (drift the tag to `lean-claim`) kills `(s1)(s4)`, so the suite catches the drift the manifest deliberately does not pin. Probe P12 (drift `CLAIMED_LABEL`'s default away from `lean-gate.sh:294`) kills `(s1)(s4)(s5)(s6)`.
- `check-frozen-files.sh 288d7e1` — clean. `check-changelog-trailer.sh 288d7e1` — trailer present.
- Probe battery ran in a throwaway `git worktree` at `/tmp/probe510-wt`, since removed; the reviewed checkout was never mutated.

## Design fidelity

`not-applicable`. The spec's `## Design` section is the implementation design (S1-S4) — no handoff link and no `| RS-n |` render-state rows, so it is not armed. The repo configures no `design.provider`, so there is no provider against which an absent disarm line would need justifying, and no under-declared RS table to catch.
