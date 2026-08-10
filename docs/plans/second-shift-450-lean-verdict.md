# lean review verdict — #450

verdict=approve
run_id: review-450-3
session_id: 83e477a7-cffd-4444-a038-d91047985eaa
rounds: 3
pr: #463
reviewed_head: 6715c560ffb52644e50735f9a65c0bf83f3db3bf
reviewed_patch_id: 8c11800f8e96280d3d06e1f4b527397f4ba21152
inherited_patch_id: 4d660b6ae2a5b25c4128498746ab606a20d0e9ab
inherited_from_verdict: 30e370e3b2f7b66966afe1eccc7d6ae8339a9b49
fidelity: not-applicable
model: unknown

Round 3, delta range `30e370e..HEAD` (one commit, `6715c56`), inheriting the coverage of patch `4d660b6ae2a5` from round 2's record. **Deviation, declared:** the checklist names `review-lead` as the implementation and I did not run its specialist fan-out, for the third round running and for the reason round 1's record established — on a single shell+jq document comparator the security / perf / a11y / db axes have no surface, and that panel returned approve/approve-with-nits here while missing the only blocker of round 1. This round's method is the one that produced rounds 2's and 3's blockers: read the delta against the spec clause by clause, then apply mutants to the production body and score each against the paired suite.

**Verdict: approve.** Both round-2 blockers are fixed at the mechanism, not at the assertion, and I reproduced each fix and each failure independently. Every warning round 2 raised is either closed in the diff or dispositioned by a stated decision. No AC clause is unmet. This round amended no AC contract — the spec gained two bullets in AC-6's coverage list and nothing else — so it creates no new obligation elsewhere in the suite, which is what made round 2's two blockers.

## Blockers

None.

## Round-2 blockers — both closed, verified independently

**B-1 (AC-6, usage shapes asserted rc alone) — closed.** `config-diff-guard-selftest.sh:254,256` now pass `"usage: config-diff-guard.sh"` as the message argument. Re-applied round 2's own mutant, `[[ -n "$EXISTING" && -n "$DRAFT" ]] || usage` → `:` (`cmp`-confirmed changed, `bash -n`-confirmed parsing): the suite now **reds on exactly those two cases** —

```
✗ one argument is a usage error (stderr missing 'usage: config-diff-guard.sh': config-diff-guard: no such file: )
✗ no arguments  is a usage error (stderr missing 'usage: config-diff-guard.sh': config-diff-guard: no such file: )
```

— against green at 51/51 last round. The gap the clause was written against is now the thing that fails.

**B-2 (AC-3, a `-`-leading `--ack` value swallowed by jq's own option parser) — closed at the mechanism.** `config-diff-guard.sh:100` is `--args -- "${ACKS[@]}"`. Round 2's reproduction now behaves: `--ack -n` and `--ack --raw-output0` both land in `unmatchedAcks[]` with the two real deltas untouched. I widened the input class past the two values the suite tests, and the whole interpretation class is closed:

| `--ack` value | `unmatchedAcks[]` | deltas |
| --- | --- | --- |
| `-n` | `["-n"]` | 2 |
| `--raw-output0` | `["--raw-output0"]` | 2 |
| `--` | `["--"]` | 1 |
| `-` | `["-"]` | 1 |
| `--args` / `--slurpfile` / `--ack` | echoed back verbatim | 1 |

and `--ack -- --ack commands.web.testFile` suppresses the real path while reporting `--` unmatched, so the terminator did not cost the channel its function. Dropping the `--` reds both new cases and nothing else.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 guard contract | satisfied | The clause round 2 left uncovered — "a filter that did not run must not be spelled the same way as a comparison that found nothing" — now has a kill criterion. Streaming the comparison instead of capturing it (probe P5) reds `a comparison that could not run exits 3` at rc 0; dropping the ack-marshal status check (P3) and misattributing its message (P4) each red the marshal case. The slurped shape check and the fail-closed comparison from earlier rounds are inherited and unchanged in this delta. |
| AC-2 comparison rule | satisfied | Untouched by the delta; inherited. The only change under it is a header comment stating the all-`null`-subtree limit (W-4), which is spec-conformant, not a table change. I re-confirmed the behavior it documents: `commands.api` with six `null` lanes, draft omitting the key → `{"deltas":[]}` rc 0, exactly as the new prose says. |
| AC-3 ack channel | satisfied | B-2. Exactness, suppression, `acknowledged[]`/`unmatchedAcks[]`, prefix-is-not-a-wildcard, the newline and empty-string boundaries are all inherited and hold; the interpretation half is now correct for every hostile value I could construct, including the terminator itself. |
| AC-4 Step-3 diff-mode clause | satisfied | Untouched by the delta; inherited. |
| AC-5 accept predicate | satisfied | The delta rewrites only the exit-3 bullet at `SKILL.md:233-240`. Every AC-5 requirement — blocking `deltas[]` with `evidence` then `proposal`, informational `unmatchedAcks[]`, re-run per loop iteration, fresh-onboard skip, no new question batch — is unchanged and holds. W-1 below is about that bullet's enumeration, which AC-5 does not specify. |
| AC-6 tests | satisfied | Both new coverage bullets are real cases with kill criteria, and no assertion was weakened (68 added / 2 removed, the removals being the two `expect_rc` calls replaced in place by their message-carrying form). Every `expect_rc` asserting rc 3 — all 18 of them — now carries a stderr substring, which is the AC-6 sentence in full. The inert-marker control is load-bearing, not decoration: breaking the shim's passthrough (probe P6) reds it first, so the two kill cases cannot pass vacuously. |

## Verification run in this review

- `shellcheck -e SC1091,SC2015,SC2181` clean on both scripts. Guard suite green at 62 checks under bash 5 and under `/bin/bash` 3.2.57.
- Five mutants applied to the round-3 production changes, each `cmp`-confirmed to have changed the file and `bash -n`-confirmed to still parse; **five killed, zero survived**, each by the case named for the invariant it guards: P1 drop the `--` terminator → the two interpretation cases; P2 argument-count guard → `:` → the two usage-message cases; P3 drop the ack-marshal status check → the marshal case; P4 rename the marshal message to `comparison failed` → the marshal case and its no-misattribution sibling; P5 stream the comparison → the comparison case.
- One mutant against the **harness** (P6, shim kills every invocation) to prove the control is not vacuous: it reds `the shim is inert when its marker matches nothing` and the delta-count assertion under it before either kill case is reached.
- Round-2 blocker reproductions re-run at this head: both fixed, as tabulated above.
- Corpus datapoint for OR-1: the repo's own committed `.claude/second-shift.config.json` (17 protected non-null leaves) against itself → zero deltas, rc 0.
- CI at the reviewed head: `lint-and-selftests`, `selftests (macos, bash 3.2)` and `mutation-sweep-pr` all pass; the sweep genuinely scored this tool — `swept plugins/second-shift/skills/onboard/tools/config-diff-guard.sh — applied=5 killed=5 survived=0`, not a deferred zero-verdict pass. `pr-gates` fails on one line only: `verdict record reads 'verdict=needs-work'`, round 2's record, which this one replaces. Not a finding.
- No row in `scripts/lockstep-manifest.tsv`, `tools/mutation-catalog.tsv`, `tools/mutation-exclusions.tsv`, `tools/mutation-baseline.tsv` or `tools/selftest-cache-inputs.tsv` references this tool, so no re-keying obligation lands on this diff.

## Warnings

**W-1 (new) — the rewritten exit-3 bullet's enumeration misses the one other shape that IS the human's to repair.** `SKILL.md:233-240`. The rewrite fixes what round 2 flagged: the remedy is keyed off the message, and the destructive instruction now carries an explicit "never propose replacing a config on an exit 3 whose message did not name it". The residual is the sentence beside it — *"only `not a single JSON object` … is the human's to repair. Every other shape (a missing file, a malformed invocation, a `--ack` with no value, a comparison that could not run) is this call being wrong, and is yours to fix and re-run."* `not valid JSON: <existing config>` is in "every other shape" and is not this call being wrong; it is the same damaged-config class as `not a single JSON object`, arriving through `jq empty` one line earlier. An agent reading the enumeration literally re-runs and loops instead of surfacing a corrupt config. Fail-closed, so no destruction and no wrong verdict — the safety instruction keys off "message names the config", which `not valid JSON: <path>` satisfies — but the two sentences disagree about the same shape. One clause: add `not valid JSON` beside it.

**W-2 (carried, closed as a decision) — the all-`null` subtree.** Round 1 and round 2 both raised it; round 3 takes the cheap half round 1 offered and writes the limit into the header at `config-diff-guard.sh:109-112`, next to the null-leaf rule that causes it. That is the right disposition — the behavior is what AC-2 specifies, so a walk change would be a spec change — and the limit is now where a reader looks for it rather than something to rediscover.

**W-3 (carried, closed as a decision) — `proposal` says "Restore" for keys the migration docs say to drop.** Left alone by stated decision: the ack channel dispositions it, and rewording would churn the assertions on it for advice the human already overrides. I agree with the call at this size; it belongs to whatever ticket does the migration-aware proposals, if one is ever wanted.

**W-4 (new, minor) — one half of a spec clause has no kill criterion.** AC-6's new bullet says each shim case "names its own subsystem rather than the other's", and the marshal case asserts both halves (`could not marshal --ack values`, and no `comparison failed`) while the comparison case asserts only the positive. No mutant can make the comparison print the marshal's line, so the missing assertion has nothing to catch — it is an asymmetry in the prose, not a gap in the suite. Noted so a later reader does not mistake it for one.

## Nits

- `expect_no_stdout` on both shim cases is unfalsifiable in the shapes that reach it: when the filter dies, stdout is empty whether or not the guard checks the status, so the assertion rides along with the rc one rather than adding a kill criterion. Harmless and cheap; it would earn its place against a mutant that printed a partial envelope before exiting.
- A depth-2000 document still exits 3 with `not valid JSON` (jq's own parser depth limit, hit at `jq empty` before the shape check) — unchanged from round 2, and a shape no config reaches.

## Open regions

OR-1 (first-run delta volume on a real adopted config) is measured for the first time, on one config: this repo's own, 17 protected leaves, zero deltas against itself. That is a floor, not the answer — it exercises AC-4's carry-forward on a single-command repo and says nothing about a multi-command adopter with months of detection drift. Still open, and still the thing to watch on the first real re-onboard. OR-2 (nothing mechanically proves a human authorized each `--ack`) is unchanged by construction; this round strengthens the surrounding fact only — no ack value of any shape can now be silently reinterpreted or dropped, so what `acknowledged[]` and `unmatchedAcks[]` report is exactly what the caller typed.
