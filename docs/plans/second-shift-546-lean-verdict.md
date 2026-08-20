# lean review verdict — #546

verdict=needs-work
run_id: review-546-1
session_id: c18b0306-0319-417a-ac65-24fb2b9e3021
rounds: 1
pr: #615
reviewed_head: d2656754059164b09177d3067e54dd2e3a42f854
reviewed_patch_id: 062382144fc2c06334672b161d3480240f19e835
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

## Review — round 1

The derivation is right, and it is right for the reason the ticket asked for: I ran the new
`--issue` mode against **this run's own** progress record from the lane worktree and it
reproduced the PR body's block exactly — `$13.93`, 48 min, `Sessions: 3`, fence 19:06–19:55 —
so AC-1/AC-2 are demonstrated on production data, not only on a fixture. The fixture geometry
(one decoy datapoint before the fence, three distinguishable totals over one metrics file) is
the right shape for this defect class: it pins the derived answer against a *well-formed wrong*
one rather than against emptiness.

I probed the new assertions rather than reading them. Eleven mutants applied to
`pipeline-cost-block.sh` in an isolated worktree; ten were killed by the named case —
fence-start reading the last stamp, the retitle neutered, `record_key`'s charset narrowed to
`lean-gate.sh`'s (which is exactly the divergence the new lockstep exists to prevent), the row
identity dropping `runId`, the row written without `--close-out`, `--close-out` no longer
requiring `--issue`, the stampless refusal rendering a default, and the `--start` override
ignored. AC-10's stated claim ("only this case would say so") also holds: relocating the writer
above the fence skip exits reds AC-10 and nothing else. Suite is 51/51 under bash 5 **and**
under stock `/bin/bash` 3.2; shellcheck clean; `check-lockstep-pairs.sh` 25 anchors, 0 failed.

One blocker, and it is a lane that is red right now on this PR's own new code.

## Blockers

**B1 — `mutation-sweep-pr` is red: three baseline-absent survivors, all inside the new
`--issue` block, all killable by a fixture.**
`plugins/dev-pipeline/tools/pipeline-cost-block.sh:163`, `:168`, `:266`

CI run 32411363210 reds with `applied=12 killed=8 survived=4`; I reproduced it locally
(rc=1, same three ids) and reverse-mapped the content keys to their sites:

| id | line | site |
| --- | --- | --- |
| `default::c2c7786871fb` | 163 | `CONFIG="${SECOND_SHIFT_CONFIG:-$MAIN_ROOT/.claude/second-shift.config.json}"` |
| `logic::1e2b5beb13a7` | 168 | `cfg()`'s `[ -n "$v" ]` AND `[ "$v" != "null" ]` |
| `cmp-eq::8d37545e081b` | 266 | the derived-summary log line's `REVIEW_SESSION_INCLUDED -eq 1` suffix |

The first two are one gap, not two: **no fixture in the suite ever supplies a config file**, so
the whole `CONFIG` → `cfg()` → `state_dir()` ladder — the code that decides *which progress
record `--issue` reads* — is undriven. Every fixture lands on the built-in default and would
land there with the ladder deleted.

None of the three is unkillable by construction, so a `tools/mutation-baseline.tsv` row is the
wrong remedy. I verified each kill:

- **163** — a fixture whose config sets `paths.pipelineStateDir` to a non-default directory:
  unmutated resolves the record there and derives the fence; mutated points `CONFIG` at a
  non-existent path, falls back to the default dir, and exits 2 "no readable lean progress
  record". Clean fire/no-fire pair.
- **168** — needs a *second* fixture: a config that **exists but omits** `paths.pipelineStateDir`.
  `jq -r` yields the literal string `null` there, which is the only input on which AND and OR
  disagree; the mutant then resolves a state dir literally named `null` and refuses. (A config
  that *has* the key does not kill it — I checked, it survives.)
- **266** — assert the derived-summary stderr line. Measured, same fixture, unmutated vs mutant:
  `…, 2 session(s) (review included)` vs `…, 2 session(s)`.

That third one is worth more than a mutant score: the `(review included)` parenthetical is the
**only** operator-visible signal that AC-3's union fired. AC-3 makes the degrade deliberately
silent, so a close-out accidentally run from the main checkout — where the branch-committed
verdict record does not exist — is indistinguishable from a legitimate pre-review invocation
*except* by that suffix. It is the one thing standing between this ticket's own defect class and
a recurrence, and nothing asserts on it.

Per this repo's contract the PR-scoped sweep is where survivors become a red rather than data,
and the build lane no longer sweeps at milestone 3 — so `mutation-sweep.sh --mode pr` is a
pre-handoff step that was skipped here. Running it is how this gets closed, not re-baselining.

## Warnings

**W1 — the AC-13 "class guard" cannot catch a revert of the site it names.**
`plugins/dev-pipeline/tools/cost-block-selftest.sh:648-660`

The case's comment claims it "asserts the CLASS rather than the one site: any surviving call to
something that no longer exists shows up here as an interpreter complaint **on a path the suite
actually drives**." Measured both directions:

- Re-inserting the deleted `record` call at its original site (the no-readable-metrics-file
  branch) → suite still **51 passed, 0 failed**. That branch fires only when file selection
  yields nothing *despite* a metrics file existing, which no case sets up.
- Planting a call to a non-existent helper on a genuinely driven path (just above
  `COST_BLOCK=$(render_block)`) → the case **fails**.

So the guard is live, but strictly narrower than its comment says, and blind to exactly the
regression AC-13 names. AC-13 itself is satisfied — the deletion is visible in the diff — and
AC-15 scopes fixture coverage to AC-1..AC-11, so this is not an unmet criterion. It is a
rationale that overstates its reach, and in this repo that is the thing that goes stale
unnoticed. Either drive the branch (an unreadable metrics dir) or narrow the sentence to what
it actually covers.

**W2 — a test invocation's env assignment is parsed as a positional argument.**
`plugins/dev-pipeline/tools/cost-block-selftest.sh:658`

`bash "$SCRIPT" --stateless --issue 900 --close-out --out /dev/null COST_LOG_FILE="$CL2"` places
the assignment *after* the command, so it is argv, not the environment — confirmed by echoing
`$COST_LOG_FILE` and `$*` from a stub. `COST_LOG_FILE` is therefore unset for that run and the
row lands in the fixture repo's default state dir instead of `$CL2`. Harmless today (nothing
reads `$CL2` after that point, and the fixture tree is a `mktemp` dir), but it is wrong by
construction and will silently mislead the next case appended below it. Move it before `bash`.

Related, and not worth a finding on its own: under `--stateless` the script collects unknown
bare words into `POSITIONAL_ARGS` and ignores them, which is why the stray token was swallowed
rather than refused. Only `-*` tokens error.

## Suggestions

- **The corrupt-JSONL fallback is untested — but it is correct.** Rather than report it as an
  unknown, I drove it: seeded `cost-log.jsonl` with a garbage line plus a valid row, ran
  `--close-out`, and got the documented behavior — the `does not parse as JSONL` diagnostic, the
  original two lines preserved byte-for-byte, one new valid row appended. Also checked a valid
  log with no trailing newline: jq re-emits it and the result is two clean lines, no
  concatenation. Worth a case for the same reason the rest of this suite exists, but there is no
  defect behind it. (Raised independently by test-coverage-reviewer at confidence 85.)
- **`--issue`'s two early validation branches are undriven** (non-numeric argument; not in a git
  repo). Both verified working by hand — rc=2 with the named message, and a non-numeric value
  containing shell metacharacters is rejected by the `case` before it reaches any expansion.
  Two one-line cases alongside AC-6 would close it. (test-coverage-reviewer, confidence 80.)
- **Informational, not this PR's debt:** the sweep also emits `WARN: slow-list drift —
  retro-corpus-selftest.sh measured 15s (>= 5s)` and is not recorded at that bar in
  `tools/mutation-slow-suites.tsv`. This PR is what pulled that guard into the PR lane (it added
  markers to `retro-corpus.sh`), which is why the warning surfaced here. It is a warning, not the
  red, and the sweep itself says to fix it by ordinary PR.

## Dismissed

- `scope-completeness-reviewer` suppressed a note (confidence 70) that the `--close-out`
  cost-log row, `--prs`, and the corpus restoration "are not traceable to any deliverable in
  issue #546". They are — the ticket's owner comment of 2026-08-16 explicitly adds "restore the
  machine-readable cost row" and asks that the review-session question be settled in the same
  change. Both are carried as D-5 and D-3 in the spec's ledger. The reviewer read the issue body
  and not its comments.
- `security-reviewer` suppressed a path-traversal note (confidence 45) on `"$REPO_ROOT/$_vrec"`.
  Agreed with the suppression: the progress record is a locally generated pipeline-state artifact
  with no untrusted writer, the operation reads one token out of the target, and
  `retro-corpus.sh` already reads the same key the same way.

## AC scoring

All fifteen satisfied. The blocker above is a repo-contract failure, not an unmet criterion.

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 fence derived from the record | satisfied | reproduced on the real #546 record (19:06:23→19:55:10); mutants on the first/last stamp and on the `--start` override both die |
| AC-2 session set derived | satisfied | `Sessions: 2`/`3` cases; narrowing `record_key`'s charset kills three cases; `check-lockstep-pairs.sh` green on `lean-session-set` |
| AC-3 review session unioned in | satisfied | `$3.50` vs `$3.00` over one fixture; absent verdict record degrades silently |
| AC-4 title moves with the set | satisfied | forcing `Session total` reds exactly the retitle case |
| AC-5 explicit args win individually | satisfied | `--start`-only and `--sessions`-only cases; ignoring the `--start` override dies |
| AC-6 underivable fence is rc=2 | satisfied | absent, stampless, non-numeric and non-repo all rc=2 naming the resolved path |
| AC-7 `--close-out` gates the row | satisfied | writing unconditionally, and dropping the `--issue` requirement, each die |
| AC-8 cross-era row schema | satisfied | exact key-set equality; `byLabel` absent; no marker field; `tiers` not restated |
| AC-9 identity is (ticketKey, runId) | satisfied | replace/append pair; dropping `runId` from the filter dies |
| AC-10 no rollup, no row | satisfied | relocating the writer above the fence skip exits reds this case and only this case |
| AC-11 `--prs` supplies the refs | satisfied | present and absent both asserted; no network call anywhere in the script |
| AC-12 prose sites corrected | satisfied | script header, `build-lean/SKILL.md` 7 and 9, `cost-tracking-setup.md` both paragraphs; step 9 states the PR-body replacement |
| AC-13 dead `record` call removed | satisfied | deleted in the diff — see W1 on the guard's overstated rationale |
| AC-14 `--help` range moves | satisfied | `2,106p`; line 106 is the header's last line, 107 blank, 108 the first code; three cases pin all three edges |
| AC-15 new assertions driven end-to-end | satisfied | 25 new cases against the real script; the AC-1..AC-11 coverage AC-15 enumerates is present |

## Verification run for this round

- `cost-block-selftest.sh` — 51 passed, 0 failed (bash 5.3 and stock `/bin/bash` 3.2)
- `shellcheck -e SC1091,SC2015,SC2181` on all four changed shell files — clean (0.11.0 local)
- `scripts/check-lockstep-pairs.sh` — 25 anchors checked, 0 failed
- `mutation-sweep.sh --mode pr --base origin/main` — **rc=1**, reproducing CI's three
  baseline-absent survivors
- 14 hand-applied mutants in an isolated worktree at the reviewed head; 11 killed, and the three
  that survived are B1
