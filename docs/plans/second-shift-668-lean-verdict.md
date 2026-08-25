# lean review verdict — #668

verdict=approve
run_id: review-668-2
session_id: cbc85b69-8ee4-4e37-aef2-a1ee1b498939
rounds: 2
pr: #685
reviewed_head: 6ded9df098dbff04e1ec84eac6984173f911e046
reviewed_patch_id: 3c5e8d1f6f6af737d42f8ae1db89163eaea6b679
inherited_patch_id: fcf5f143d970240fcfb93000a5bed05a6d6c7795
inherited_from_verdict: 7da4302d5df40eb0a662473c748af27cfe2e073d
fidelity: not-applicable
model: unknown
capabilities: pr-marker

# Review round 2 — PR 685 (#668)

Range read: `7da4302..HEAD` — the delta since the tree round 1 covered (`inherited_patch_id
fcf5f143d970`). One commit, `6ded9df`: the corrected `cmd_3` comment and the spec's new
`## Verification result (AC-3)` section. Round 1's findings were read first, and every AC is
scored below against the whole spec, not against the delta.

Panel: 5 selected, 5 returned, **none dark**, zero findings from any of them. The one warning
below is operator-side, as in round 1.

## Verdict: approve — 0 blockers, 1 warning

Round 1's blocker and both its warnings are closed. The one new note is a comment premise that
is looser than the fact it is asserting; the conclusion it draws is independently true, and no
behavior depends on it.

## Round 1 findings — disposition

**B1 (blocker) — `pr-gates` red on `check-guard-budget.sh`: CLOSED.** Re-run at this head:

```
[guard-budget] ✓ guard/test shell mass: base 51793, HEAD 51841 (delta +48), covered by a
               'Guard-mass:' trailer.
```

The `Guard-mass: +48` trailer on `6ded9df` matches the measured delta exactly — the figure was
re-derived after the last edit rather than copied from round 1's remedy (which said `+46`, before
the comment edit added two counted lines). CI agrees: at this head the `guard budget guard` step
passes, and so do `frozen files`, `changelog trailer` and `pipeline chain reconciliation`. The
only remaining red is `lean chain reconciliation`, failing on
`verdict record … reads 'verdict=needs-work', not 'verdict=approve'` — round 1's own record. That
is expected state for a pre-approval lean PR, not a blocker; this record clears it.

**W1 — AC-3's result "recorded here": CLOSED, and re-derived rather than taken on trust.** The
spec now carries `## Verification result (AC-3)`. Every row of its table was independently
re-measured in this session at this head, and each matches:

| Row the spec asserts | What I measured |
| --- | --- |
| suite at head: all green, 514 PASS, 0 FAILURE, rc=0 | `lean-gate-selftest.sh` in the lane worktree: **rc=0, 514 PASS, `all green`** |
| gate reverted to `origin/main`: 2 FAILURE(S), exactly (ad6) and (ad7) | isolated probe worktree at this head, `git checkout origin/main -- lean-gate.sh` (mutation confirmed: 0 occurrences of `LANE_ADVISORY_COUNT`, −17/+1 lines): **rc=2, 512 PASS + exactly `(ad6)` and `(ad7)` failing**, (ad8) passing |
| `shellcheck -e SC1091,SC2015,SC2181` on both changed shell files: clean | clean, rc=0 |
| `bash G 3` printed the terminal line unqualified | not re-executed here — running the build gate under a review identity would write progress rows for `review-668-2`. Corroborated instead by `(ad8)`, which pins `[lean-gate] ✓ milestone-3: green gate` with `grep -qFx` on a zero-advisory run, and by the code: the suffix is appended only under `-gt 0`. |

**W2 — the reset's over-claim: ADDRESSED in both places.** The correction landed in the code
comment as well as the PR body, which is the right move — round 1 quoted the body, but the same
sentence was the comment above `LANE_ADVISORY_COUNT=0`, and fixing only the body would have
shipped the defect. See the warning below for what the replacement says.

## Warnings

**W1 — the new `cmd_3` comment's premise is broader than the fact it needs, and is false as
stated.** `plugins/dev-pipeline/skills/build-lean/lean-gate.sh:3811`:

```
# Defensive only, not guarding a live path: `all` runs each milestone once per process, so
# nothing calls cmd_3 twice today, and the file-scope initialiser above already zeroes this.
```

`cmd_all` does **not** run each milestone once per process. Its pre-pass calls `cmd_1` and
`cmd_4` **directly** under `LEAN_GATE_OBSERVE=1`, bypassing `run_milestone`, and then the
`for n in 1 2 3 4 5` loop calls `run_milestone` for all five — so milestone 1's and milestone 4's
bodies each execute **twice** in one `all` process. The premise as written is only true of
milestone 3, and it is true of milestone 3 precisely because the pre-pass "evaluates 1 and 4
alone to avoid paying for milestone 3", as `run_milestone`'s own comment says.

The conclusion — *nothing calls `cmd_3` twice today* — is correct, and I verified it
independently: `cmd_3` is reachable from exactly two sites (`run_milestone`'s dispatch case and
its observe case, mutually exclusive within one call) plus `cmd_all`'s single loop iteration for
`n=3`. So no behavior turns on this and nothing is owed but a narrower sentence, e.g. *"`all`
reaches `cmd_3` exactly once — its pre-pass evaluates only 1 and 4"*. Flagged rather than waved
through because this comment is now on its second revision and its entire job is to state a
reachability fact exactly; the PR body's version of the same note (`cmd_all` runs `run_milestone`
once per milestone 1..5) is accurate, so the two disagree.

## What was verified independently this round (not read on trust)

| Check | Result |
| --- | --- |
| `lean-gate-selftest.sh` at the reviewed head | 514 PASS, 0 FAILURE, rc=0 |
| the same suite with the gate reverted to `origin/main`, in an isolated probe worktree | rc=2 — exactly `(ad6)` and `(ad7)`; `(ad8)` passes on both sides, so it is a control |
| `scripts/check-guard-budget.sh origin/main` | ✓ +48, covered by the trailer |
| `shellcheck -e SC1091,SC2015,SC2181` on `lean-gate.sh` + `lean-gate-selftest.sh` | clean |
| `gh run view --job` on `pr-gates` at this head (step list, not `gh pr checks`) | 4 of 5 steps green; only `lean chain reconciliation` red, on `verdict=needs-work` |
| every `cmd_3` call site | `run_milestone`'s two mutually-exclusive arms + `cmd_all`'s one loop iteration — never twice per process |
| both `lane_advisory` call sites | `:3869` (fixed-key `for`), `:3957` (extraLanes `for (( ))` under `if [ "$el_count" -gt 0 ]`) — plain loops in `cmd_3`'s own body, no pipeline and no `( … )` wrapper, so both increments reach the caller |
| the file-scope initialiser the comment cites | `:3800`, above both — the comment's second clause is accurate |
| `6ded9df`'s trailer block | `Guard-mass:` and `Changelog: none.` each on one un-indented line, terminated by `Co-Authored-By:` — no indented prose to render into `CHANGELOG.md` |
| the branch's substantive `Changelog:` trailer | present on `1effbb3`, survives the squash (grep-anywhere extraction) |

## AC scoring (against the committed spec, every AC every round)

| AC | Score | Basis |
| --- | --- | --- |
| AC-1 (oracle) — terminal line names the count when nonzero; a fixture asserts it and reds against the unconditional form | **satisfied** | `(ad6)` pins `green gate (1 advisory)` with `grep -qFx`; `(ad7)` pins `(2 advisory)` **and** asserts 2 durable advisory rows, so a hardcoded suffix cannot pass it. Both die on the reverted gate — reproduced in this session, not inherited. |
| AC-2 (critic) — rc, verdict routing, progress-row text and every consumer unchanged; zero-advisory text byte-identical | **satisfied** | `(ad8)`'s `grep -qFx` is the byte-identity assertion and passes on both sides of the mutation. The suffix is appended only under `-gt 0`; the delta touches one comment and adds no code path. |
| AC-3 (oracle) — sweep green, `Changelog:` trailer, deferred suite run explicitly and its result **recorded in the spec** | **satisfied** | The spec now carries the result table, and both of its measured rows reproduce here. Sweep green at this exact head in both CI selftest jobs (`lint-and-selftests` 4m36s, `selftests (macos, bash 3.2)` 7m50s — both pass `--full`, so the deferred suite ran there too). `Changelog:` trailer present and CI-green. Round 1's W1 is what this closes. |

Design fidelity: **not-applicable** — the spec has no `## Design` section and no render receipt.

## Strengths

- The AC-3 warning was closed by **re-measuring at this head**, not by transcribing round 1's
  figures into the spec. Both numbers reproduce exactly, which is the difference between a record
  and a rumour — an asserted figure in a committed spec is a build input nothing downstream
  re-derives.
- The `Guard-mass:` figure was re-derived after the last edit. Round 1's remedy said `+46`; the
  comment edit made it `+48`, because `lean-gate.sh` is itself counted guard mass. Pasting the
  reviewer's number would have shipped a wrong one under a gate that only checks the trailer's
  presence.
- W2 was fixed in the **code** as well as the PR body. The body was a transcription of the
  comment; closing only the quoted copy is the standard way this class of defect survives a round.
- One commit for the blocker and both warnings, rather than the empty trailer commit round 1
  suggested. A trailer-only commit already costs a full re-read, so folding the content in was
  free — the right call, and it is why this round's delta is readable at all.

## Panel verdicts

| Reviewer | Verdict | Findings | Confidence |
| --- | --- | --- | --- |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Scope Completeness | Pass | 0 | — |

Security's one sub-80 note (confidence 40) is the retained reset line, and reads it as defensive
state hygiene with no security surface — consistent with the reading above.

Depth routing: the delta is 2 files / +19/−1, and touches a `.sh`, so it is **Small** (the
trivial-inert carve-out does not apply). Complexity and unit-test-mutation were not selected —
not dark. `scope-completeness-reviewer` was dispatched against the **full branch** range
(`295f4ea...HEAD`), not the delta, so its gate scored the whole issue rather than one commit.
`a11y-reviewer` + the design-fidelity dimension were not routed: no changed path matched
`stageParams.webComponentGlobs` (absent from config, so the shipped default
`apps/web/**/*.{tsx,jsx}` applied). `db-reviewer` / `pipeline-reviewer` — no DB or queue surface.
