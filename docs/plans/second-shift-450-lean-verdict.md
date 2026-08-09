# lean review verdict — #450

verdict=needs-work
run_id: review-450-1
session_id: 4ab50d48-39cd-485f-ae74-f1f49cf30862
rounds: 1
pr: #463
reviewed_head: ca674b30d779cf0b385a50422006378f04315112
reviewed_patch_id: 928c693d1eb322707e7bc50434109b9b6a381843
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

Round 1, full branch range `6a6922c..HEAD` (nothing to inherit). Panel: security, performance, maintainability, complexity, test-coverage, scope-completeness — all six alive, no dark reviewers. a11y + design-fidelity not routed: no changed path matched `stageParams.webComponentGlobs` (unset → `apps/web/**/*.{tsx,jsx}`).

**Verdict: needs-work.** One blocker. The design is right, the walk is right, and the suite is genuinely strong — 13 of 14 mutants I applied to the production body were killed. The blocker is a single input-validation hole that lands the guard in the exact state D-10 was written to forbid: a damaged existing config gets a silent partial skip instead of exit 3.

## Blocker

**B-1 — a multi-document input passes the AC-1 object check, and the guard then protects only the first document.** `config-diff-guard.sh:68-71`. `jq -e 'type == "object"' "$f"` returns the status of jq's **last** output, so a file holding a JSON *stream* passes both gates; `--slurpfile` + `($existing[0])` at :94/:103 then binds only document one and the rest of the file is never walked. Two reproductions at the reviewed head:

```
existing = {"commands":{"web":{"lint":"a"}}}\n{"stageParams":{"x":1}}
draft    = {"commands":{"web":{"lint":"a"}}}
→ {"deltas":[],...}  rc=0     # stageParams.x destroyed, clean screen

existing = [1,2]\n{"a":1}
→ rc=0                        # AC-1: "JSON that is not an object" must exit 3
```

The second one is an unmet AC-1 clause outright — the selftest's `valid JSON that is not an object is an error` case passes only because its fixture is a lone `["a","b"]`, and a stream in front of an object walks straight through it. The first is the consequence, and it is D-10 verbatim: *"skipping would disable the guard exactly when the config is already damaged."* A config damaged into a JSON stream — a doubled write, a botched conflict resolution, a hand-edit — is precisely a damaged config, and it gets the silent skip.

Fix is one line, in the same validation loop: replace the two `jq` calls with a single slurped check, e.g. `jq -se 'length == 1 and (.[0] | type == "object")' "$f" >/dev/null 2>&1`, keeping the existing two-message split if you want to keep telling the operator which input is wrong. Then add the shape to the AC-6 IO block: an `existing` that is `{...}\n{...}`, and an `existing` that is `[...]\n{...}` — the latter is the one that proves the check reads the whole file rather than the last value in it.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 guard contract | **unsatisfied** | Everything else in the clause holds: exact CLI shape, takes no repo root and reads no tree (no `cd`, no `git`, no network), one JSON document with exactly `deltas`/`acknowledged`/`unmatchedAcks`, exit 0 with deltas and with none, exit 3 for a missing file / non-JSON / `--ack` with no value / an unknown option / wrong argument count, and an unreadable *existing* config specifically an error rather than a skip. Ran under `/bin/bash` 3.2.57 with and without `--ack` — the empty-array `${#ACKS[@]}` read that bites bash < 4.4 under `set -u` does not fire, and CI's `selftests (macos, bash 3.2)` lane is green. The single failing clause is "JSON that is not an object → exit 3" for a multi-document input (B-1). |
| AC-2 comparison rule | satisfied | Walk verified against the table: objects descend to scalar leaves, an array is a leaf compared whole, an existing `null` leaf is skipped, `$schema` is the only exclusion and it is key-scoped rather than a document-wide mute. Classification verified: draft-absent → `removed`, draft-`null` → `removed`, differs → `changed`, deep-equal → silent. Draft-only paths never reported — proved by inverting the walk direction, which fails 21 cases. |
| AC-3 ack channel | satisfied | Repeatable and exact: a prefix ack clears nothing and lands in `unmatchedAcks[]`. Suppressed paths appear in `acknowledged[]`. The script writes nothing — no config key, no state file. Header states why `grillWaivers` is not the channel. |
| AC-4 Step-3 diff-mode clause | satisfied | `SKILL.md:74-82`. The `always` is gone and the RE-onboard clause carries both keys forward, `null` only where already `null`. Probed an AC-4-shaped draft against a synthetic adopter config: zero deltas. Probed the pre-fix draft against the same config: exactly the two motivating deltas, both `removed`. |
| AC-5 accept predicate | satisfied | `SKILL.md:213-234`, in the same block that already materializes the draft for `config-grill.sh`, same temp file, explicitly skipped on a fresh onboard. `deltas[]` blocking with `evidence` then `proposal` verbatim; `unmatchedAcks[]` informational; re-runs per loop iteration; "no unacknowledged deltas" joins "no unwaived findings". No new question batch — the one-batch rule and the not-a-wizard framing stand unamended. |
| AC-6 tests | satisfied | Every enumerated case is present and the suite is green. Independently applied 14 mutants to the production body: **13 killed, 1 survived** (W-3). The killed set is the load-bearing one — arrays descending, the `$schema` exclusion dropped, the existing-`null` skip dropped, draft-`null` reclassified, acks not suppressing, `unmatchedAcks` emptied, the not-an-object check dropped, the missing-file check dropped, an unknown option silently skipped, prefix-acks-as-wildcards. Scored satisfied because AC-6 enumerates the cases and they are all there; B-1's missing shape is an AC-1 defect the suite could not have been expected to enumerate, and the AC-6 addition above rides along with the fix. |

## Verification run in this review

- `shellcheck -e SC1091,SC2015,SC2181` on both new scripts — clean.
- `config-diff-guard-selftest.sh` — all green.
- 14 hand-probes of the production body against the suite (above).
- Guard run against this repo's real committed config and several synthetic adopter and damaged-config fixtures.
- CI at the reviewed head: `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass, `mutation-sweep-pr` pass. `pr-gates` fails on `[lean-evidence] ✗ no committed verdict record` — the by-design pre-handoff state this record closes, not a finding.

## Warnings

**W-1 — a subtree whose leaves are ALL `null` can be deleted wholesale with zero deltas.** `select($ev != null)` is applied per leaf, after `leafpaths` has already flattened the object away, so a structural key removal is unrepresentable when nothing under it is non-null. Reproduced: existing `commands.api` = six `null` lanes, draft omits `commands.api` entirely → `{"deltas":[]}`. This is not exotic — Step 3 mandates *"Undetected lanes are explicit `null` — never omit, never invent"*, so an all-null block is a shape the emitter is required to produce, and the next re-onboard can drop the whole repo entry silently. The same mechanism swallows an existing `{}` (`to_entries[]` on an empty object yields nothing, so `add // []` returns no path).

Not scored as an unmet AC: AC-2's table says an existing `null` is skipped and D-1 scopes protection to non-null *values*, so the code matches the spec. But the spec's reasoning ("there is nothing to destroy") is about leaves and does not transfer to the key itself — the existence of `commands.api` was the value. Worth either treating an object with no non-null leaf as a leaf in its own right, or writing the limit into the header next to the array rule, which is where a reader will look for it.

**W-2 — `--ack` boundaries are lost through a newline round-trip.** `:77` joins argv with `\n` and re-splits on `\n`, so a single `--ack` carrying an embedded newline becomes two acks (reproduced: one flag → two entries), and `--ack ""` is dropped without ever appearing in `unmatchedAcks[]`. Impact is bounded — the flag is typed by the agent, not attacker-supplied, and both failure directions are visible in the envelope — but it undercuts AC-3's "exact" and the fix is to pass the array with `--args`/`jq -n '$ARGS.positional'` rather than reconstructing it from text.

**W-3 — the third-positional error message has no assertion, and a mutant survives on it.** `expect_rc "a third positional is a usage error" 3` asserts rc only, so deleting `echo "config-diff-guard: unexpected extra argument: $1" >&2` leaves the suite green — the one survivor of 14. AC-6's assertion sentence binds "each **IO** shape" and this is a usage shape, so the AC holds on its letter; but the suite's own rationale applies, and the neighbouring `--waive` case already depends on this message being distinct (it asserts `unknown option: --waive` precisely to rule out the flag being skipped and its value landing here). One extra argument on that `expect_rc` call.

**W-4 — every `removed` delta asserts "Nothing downstream will notice", unconditionally.** `:126` appends the sentence outside any per-key branch. It is true for the motivating capability keys and false for required ones — losing `topology.repos.<id>.baseBranch` or `tracker.type` is not a quiet no-op. Either scope the sentence to the keys it holds for, or drop it: the delta is already evidence, and a claim the reader can falsify once teaches them to skim the rest.

**W-5 — the guard tells an old adopter to restore keys the docs say to remove.** A config still carrying `commands.<id>.build` / `integrationTest` / `apiTest` (retired in v2.1.6 / #113) diffs against a correct modern draft as four `removed` deltas whose `proposal` reads "Restore …". The ack channel disposes of them, so this is not a wrong verdict, but it is blocking advice that points the wrong way on a documented migration.

## Nits

- **`--` does not terminate option parsing.** `--) shift ;;` consumes the token and re-enters the same `case`, so a later `-`-leading argument still hits the unknown-option branch. Nothing reaches it from the one caller, but the usage string and the `--` arm together imply GNU semantics that are not implemented — implement it or drop the arm.
- **A failure of the main `jq` filter reports "no deltas" and exits 0.** Confirmed with a stub `jq` that passes both validation calls and fails the filter: empty stdout, rc 0. Reachability is very low (inputs are pre-validated and the filter is total via `try/catch` on `getpath`) and `config-grill.sh` ends the same unconditional `exit 0` way, so this is a consistent existing convention rather than something introduced here — but it is the same fail-open family as B-1, and worth fixing in the same pass while you are in that file.
- **`SKILL.md` does not say what to do when the guard exits 3.** The grill block has the same gap, so this is consistent; still, exit 3 on the *existing* config is the D-10 case, and "parse its JSON" has no answer for it.
- **`unmatchedAcks[]` does not dedupe**, so `--ack x --ack x` on an unmatched path lists `x` twice.
- **A whole existing object removed by the draft reports one delta per leaf** — dropping `tracker.bot` yields four. Spec-conformant, and not a shape onboard's emitter produces; recorded because it is the same ack-spam pressure OR-1 tracks.

## Dismissed

`scope-completeness-reviewer` flagged the guard header's "Step 3's key contract" as disagreeing with SKILL.md's numbering. It does not: the key contract sits under `## Step 3 — Draft + one-batch elicitation` (`SKILL.md:55`) and Step 4 is the emit step. Header is correct.

## Open regions

OR-1 gains a sharper reading than "unmeasured", and it stays open rather than becoming a finding. AC-4 carries forward exactly two keys, while the guard protects every existing non-null leaf — so an adopter who set `commands.<id>.lanes`, `grillWaivers`, `stageParams`, `planGates`, `reviewers.add`, `extraLanes` or `allowUnverified` gets a blocking delta per key on a re-onboard where nothing changed, and a repo-id rename re-keys the whole `commands` subtree at once. Those are true positives — Step 3's draft contract genuinely does not preserve them, so the guard is reporting a real destruction — which is why this is OR-1's volume question and not a defect in this PR. It does mean the mitigation AC-4 names is structural for two keys and absent for the rest, and the first real-adopter re-onboard is where that gets measured.

OR-2 is unchanged by construction: `--ack` is still typed by the agent, and `acknowledged[]` makes the suppression visible without proving authorization.
