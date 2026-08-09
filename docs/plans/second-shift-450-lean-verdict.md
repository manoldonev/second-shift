# lean review verdict — #450

verdict=needs-work
run_id: review-450-2
session_id: 75621220-2b71-4a6b-9310-a493d6bbff78
rounds: 2
pr: #463
reviewed_head: 409912153c849ad54f125367effa614bfa3ac6de
reviewed_patch_id: 4d660b6ae2a5b25c4128498746ab606a20d0e9ab
inherited_patch_id: 928c693d1eb322707e7bc50434109b9b6a381843
inherited_from_verdict: 83bc44b8d4221ec4e543fab12038ab6cb3748c09
fidelity: not-applicable
model: unknown

Round 2, delta range `83bc44b..HEAD` (one commit, `4099121`), inheriting the coverage of patch `928c693d1eb3` from round 1's record. Panel plus an independent finder/verifier pass, per round 1's lesson that a specialist fan-out under-reads a single-tool diff. Design: the spec has no `## Design` section, so fidelity is `not-applicable` — unchanged from round 1.

**Verdict: needs-work.** Round 1's blocker is genuinely and completely fixed. Both round-1 reproductions now exit 3 with `not a single JSON object`, a 13-shape document matrix is correct, and the comparison itself is now fail-closed. The two blockers below are new, and both are the same shape: **this round widened three ACs and the diff does not reach two of the widened clauses.** Neither is the spec being bent to match the diff — every amendment is strictly strengthening — so both fixes are small and the contract is already written.

## Blockers

**B-1 — AC-6's widened "each *usage*/IO shape asserts its stderr message" is unmet, and the gap is live.** `config-diff-guard-selftest.sh:210,212`. This round changed AC-6 from `Each **IO** shape asserts its stderr message` to `Each **usage**/IO shape` (`second-shift-450-lean.md:172`), which pulls `no arguments` and `one argument` under the obligation — and it fixed the third-positional case at :214 for exactly that reason. Those two still call `expect_rc … 3` with no message argument.

Not bookkeeping. Independently applied and scored: replacing the argument-count guard at `config-diff-guard.sh:65` with `:` leaves the suite **green at 51/51**, while the tool emits

```
$ bash config-diff-guard.sh            # mutant
config-diff-guard: no such file:       # empty path — fell through to the file check
rc=3
$ bash config-diff-guard.sh            # original
usage: config-diff-guard.sh <existing-config.json> <draft-config.json> [--ack <path>]...
rc=3
```

That is verbatim the fall-through the clause was written against. Fix, measured: add `"usage: config-diff-guard.sh"` as the third argument to both calls — green on the original, and the mutant then fails both cases with `stderr missing 'usage: config-diff-guard.sh'`.

**B-2 — AC-3's widened boundary clause is unmet: a `-`-leading `--ack` value is swallowed and reported nowhere.** `config-diff-guard.sh:91`. This round added to AC-3 (`second-shift-450-lean.md:113-115`) that *"each `--ack` value reaches the comparison verbatim, so one flag is one ack **whatever it contains** and an empty ack is reported in `unmatchedAcks[]` rather than **dropped**."* The newline round-trip is gone, but `jq -nc '$ARGS.positional' --args "${ACKS[@]}"` still lets jq parse a `-`-leading value as one of **its own** options, so it never becomes a positional:

```
$ jq -nc '$ARGS.positional' --args "-n"        → []
$ jq -nc '$ARGS.positional' --args -- "-n"     → ["-n"]

$ bash config-diff-guard.sh e.json d.json --ack -n
{"deltas":[3 paths],"acknowledged":[],"unmatchedAcks":[]}   rc=0
```

The ack vanishes: neither suppressed nor reported. Compare the control — `--ack nope.path` lands in `unmatchedAcks[]` correctly. The round replaced one silent-drop mechanism with another for a different input class, and the two new selftest cases at :195-199 cover exactly the two values the *old* implementation broke.

Severity is bounded and I checked the bound: no swallow path can **fabricate** an ack — every recognized jq option yields `[]`, every unrecognized one exits 3 — so a real delta can never be silently suppressed by this, and the guard stays fail-closed on protection. It is scored a blocker because it is a clause of an AC this round authored, with a two-line reproduction and a one-token fix: `--args -- "${ACKS[@]}"`.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 guard contract | satisfied | The shape check is slurped and reads the whole file. Both round-1 reproductions exit 3 (`[1,2]\n{"a":1}` and two objects destroying `stageParams`). A 13-shape matrix — empty, whitespace-only, `null`, `true`, `42`, `"hi"`, `[1,2]`, one object, object-with-whitespace, `[1,2]\n{…}`, `{…}\n[1,2]`, `{…}\n{…}`, `{…}\nnull` — is correct on jq 1.7.1, `-s`+`-e` behaving as the code assumes. The comparison is fail-closed: under a `jq` shim that kills only the `--slurpfile` invocation, the original exits 3 with `comparison failed` and empty stdout. Capturing `OUT` loses nothing (484KB / 900 deltas round-trips to exactly one document and one trailing newline). Real repo config against itself: zero deltas. |
| AC-2 comparison rule | satisfied | Untouched by the delta; inherited from round 1's record, where the walk and classification tables were verified row by row including the inverted-walk probe. W-4 below is spec-conformant, not a table violation. |
| AC-3 ack channel | **unsatisfied** | B-2. The exactness, suppression, `acknowledged[]`/`unmatchedAcks[]` and prefix-is-not-a-wildcard halves all hold, and the newline and empty-string boundaries are now correct and tested — but the clause says "whatever it contains", and the `-`-leading class is dropped without a trace. |
| AC-4 Step-3 diff-mode clause | satisfied | Untouched by the delta; inherited. `SKILL.md:74-82` still carries both keys forward, `null` only where already `null`. |
| AC-5 accept predicate | satisfied | The delta adds only the exit-3 bullet at `SKILL.md:233-237`; every AC-5 requirement (blocking `deltas[]` with `evidence` then `proposal`, informational `unmatchedAcks[]`, re-run per loop iteration, fresh-onboard skip, no new question batch) is unchanged and holds. W-3 is about that new bullet's accuracy, which AC-5 does not specify. |
| AC-6 tests | **unsatisfied** | B-1. Every other clause has a case, including all five added this round; nothing was weakened (41 added / 2 removed, both removals strengthening-in-place). Eight of ten mutants I scored against the round-2 production changes were killed, each by a case named for the invariant it guards — `length == 1` and the object test are independently necessary and independently guarded. |

## Verification run in this review

- `shellcheck -e SC1091,SC2015,SC2181` clean on both scripts; suite green (51 checks) under bash 5 and `/bin/bash` 3.2.57.
- Round 1's two blocker reproductions re-run at this head — both exit 3. Real committed config against itself — zero deltas.
- Ten mutants applied to the round-2 production changes, each `cmp`-confirmed to change the file and `bash -n`-confirmed to parse: 8 killed, 2 survived (B-1's, and W-1's revert of the capture). The two decision-driving probes were re-applied and re-scored independently of the panel.
- CI at the reviewed head: `lint-and-selftests`, `selftests (macos, bash 3.2)`, `mutation-sweep-pr` (5 applied / 5 killed / 0 survived) all pass. `pr-gates` fails only on `verdict record reads 'verdict=needs-work'` — round 1's record, which this one replaces. Not a finding.
- No row in `scripts/lockstep-manifest.tsv`, `tools/mutation-catalog.tsv`, `tools/mutation-exclusions.tsv` or `tools/selftest-cache-inputs.tsv` references this tool, so no re-keying obligation lands on this diff.

## Warnings

**W-1 — AC-1's new no-fail-open-on-the-comparison clause has zero coverage.** `config-diff-guard.sh:113,160-161`. The code is right, and the `printf '%s\n' "$OUT"` line is load-bearing (dropping it fails 24 cases). But reverting change 2 wholesale — stream the filter, drop the `|| { echo "comparison failed"; exit 3; }` and the `printf` — leaves the suite **green**, and under a dying filter that mutant gives `rc=0` with empty stdout: a caller reads a clean envelope. That is verbatim what `second-shift-450-lean.md:70-71` added this round. The suite contains no PATH/shim manipulation at all (grep confirms), so nothing observes the failure branch. A hermetic, bash-3.2-safe shim case exists and was measured: green on the original, two failures on the revert.

**W-2 — the ack-marshalling `jq`'s exit status is unchecked, and its failure is misattributed.** `config-diff-guard.sh:91`, surfacing at `:160`. When jq rejects an ack value, `ACKS_JSON` is empty, `--argjson acks ""` kills the main filter, and the operator gets three lines of raw jq internals plus `config-diff-guard: comparison failed` — the one guard-authored line naming the wrong subsystem. Behaviorally fail-closed (rc 3), which is what the new `|| exit 3` is for; the defect is diagnostic. Every other error path names which *input* is wrong. `${ACKS_JSON:-}` empty is trivially detectable at :91, and the `--` fix for B-2 removes most of the reachable cases.

**W-3 — the new `SKILL.md` exit-3 paragraph misattributes exit 3, and the remedy it names is itself config-destructive.** `SKILL.md:233-237`. It states exit 3 *"means one of the two documents is not a single JSON object"* and instructs the agent to *"ask the human to repair or replace the existing file"*. Exit 3 has seven shapes and only one is that one — the other six are a missing file, a third positional, a bad argument count, an unknown option, `--ack` with no value, and W-2's flag error. Chained with W-2 this is sharp: a mistyped `--ack` yields `comparison failed`, and an agent following this paragraph verbatim tells the human their healthy committed config is damaged and to replace it — the single remedy in this skill that can itself destroy config values, in the ticket written to prevent exactly that. Key the advice off the *message*: `not a single JSON object` → repair the file; anything else → the invocation is wrong. It is a warning rather than a blocker because the paragraph does say "show the message", so the human sees `unknown option: --waive` and will not act on the replacement advice.

**W-4 — carried from round 1, unaddressed: an all-`null` subtree is still deletable with zero deltas.** `config-diff-guard.sh:127`. Existing `commands.api` with six `null` lanes, draft omitting `commands.api` entirely → `{"deltas":[]}` rc 0. Spec-conformant (AC-2 skips an existing `null` leaf) and correctly not scored against AC-2, but round 1 offered a cheap alternative — write the limit into the header next to the array rule, where a reader looks for it — and neither that nor the fix landed. The empty-object analogue (`{"gates":{}}` dropped) behaves the same way.

**W-5 — carried from round 1, unaddressed: the guard advises restoring keys the docs say to remove.** A config still carrying `commands.<id>.build` / `integrationTest` / `apiTest` diffs as `removed` deltas whose `proposal` reads "Restore …". Dispositioned by the ack channel, so not a wrong verdict — still blocking advice pointing the wrong way on a documented migration.

## Nits

- `--ack --raw-output0` additionally leaks `warning: command substitution: ignored null byte in input` with rc 0 and the ack silently gone — a sub-case of B-2 that the `--` fix closes.
- A depth-2000 document exits 3 with `not valid JSON` (jq's own parser depth limit, hit at `jq empty` before the shape check) — a misleading message for a shape no config reaches.

## Open regions

OR-1 and OR-2 are unchanged by this round. OR-1's ack-volume question is untouched — AC-4's carry-forward is still the only mitigation and still unmeasured on a real adopted config. OR-2 is unchanged by construction; note that B-2 narrows the *mechanism* slightly in the safe direction (no ack can be fabricated) without touching the authorization question.

## Note on the spec amendments

This round amended AC-1, AC-3 and AC-6. All three are strictly strengthening — AC-1's "is JSON that is not an object" became "does not hold exactly one JSON document that is an object", AC-3 gained a boundary clause, AC-6 gained five cases — and AC-1's widening was prescribed by round 1's own review. None of them is a spec bent to fit the diff. Both blockers are the inverse: the spec reached further than the diff did.
