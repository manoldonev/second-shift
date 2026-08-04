# lean review verdict — #375

verdict=approve
run_id: review-375-2
session_id: ee0785ca-d5d3-45b7-b52d-dcdf2b01ae5a
rounds: 2
pr: #377
reviewed_head: 7363651be9ec64a07409341d69c1639e91c436aa
reviewed_patch_id: f522526b08b3106370923017aa962e83cfdb8359
inherited_patch_id: 0443c97122104c5ff7603e3020fb2b492a3ad374
inherited_from_verdict: 565b6c34a468028dcc6a7f77f0e460dcbcc38a76
model: unknown

## Round 2 — `approve`

Reviewed at `7363651`. `bash G delta 375` (the branch's own gate) printed the **FULL** range
`d5b3fa5..HEAD`, and correctly: the rebase onto #376 resolved two conflict hunks, so round 1's
reviewed patch anchors no commit on this branch and its coverage cannot extend over a resolution
it never saw. **This round therefore read the whole branch diff** — see note 7, since the derived
key in this record's own header will nevertheless name round 1.

Round 1's findings (`review-375-1`, `needs-work`: B1 blocker + W1/W2/W3) were read first, per the
skill's step 5. The committed spec `docs/plans/second-shift-375-lean.md` is the definition of done;
it now carries **twelve** `AC-n`, two of them added in the fix round (see note 1).

**No blockers.** B1 is fixed at both halves and the fix is confirmed in production on this very
branch. W1 and W3 are fully addressed. W2 is addressed at the writer — the half that was
production-reachable — and its reader-side half survives; it is carried forward below as the one
warning, deliberately not escalated.

### B1 — fixed, and confirmed outside the fixtures

The writer now emits the inheritance key on **every** round (sentinel `none` on a root), and all
three readers extract it **header-anchored** via one shared awk program. Both halves verified
independently of the suites:

- **The extraction, driven directly** on four hand-built records (the production reader's awk,
  lifted out of `check-lean-chain.sh`): a header sentinel beats a body value that would resolve;
  a **pre-sentinel** header (key absent entirely) yields nothing rather than the body's value; a
  legitimate header value is read; and a header run with no blank line still stops at the first
  header match. Only the legitimate case returned a value.
- **In production, on this branch.** CI's `pr-gates` at `7363651` prints
  `· verdict record declares no inherited coverage — it covers the whole branch diff on its own`
  for round 1's record — which is a genuine pre-sentinel root, exactly the population the
  header-anchoring half exists for. Round 1's own repro is that this same reader went red here.
  (Honest scope: the corrected round-1 record no longer contains a first-matchable occurrence in
  its body, so this run confirms the *pre-sentinel-root* half, not the *injection* half. The
  injection half is fixture-covered at all three readers — `(z1)`/`(z2)`/`(z3)`, `(V6)`/`(V6b)`,
  `(N7)`/`(N7b)` — each driving both the dangling variant (loud, rc flips) and the resolving one
  (silent, both readings exit 0, only the link **count** separates them).

The two doc consequences round 1 asked for are in: `cmd_verdict`'s note now states the rule as a
property of *unconditional* emission, and `record_key`'s comment says which keys it is correct for.

### W1, W3 — fixed

- **W1 (arm order).** The committed / tracked-but-dirty arms now precede the chain arm in
  `cmd_4`; verified by reading, and `(z4)`/`(z4b)` turn on the `git commit` and nothing else.
- **W3 (three hand-maintained copies).** The extraction became one dialect-neutral awk program
  pinned by two `verbatim` rows; `check-lockstep-pairs.sh` reports 15 pairs, 0 failed, with both
  new rows named. The chain-**walk** loop stays a DROPPED entry with the reasoning recorded —
  correct, and the recorded reason (each reader phrases its own diagnostic; the boundary must
  scope `git log` to the PR head) is verifiable in the diff. The key-schema entry is extended to
  name both new keys.

### Warning — W2's reader-side half is still open

**The merge boundary credits an inheritance link without checking who authored it.**
`check-lean-chain.sh`'s chain walk reads only the reviewed-patch and inherited-patch identities per
link. It never reads a link's session key, though it already has the build identity in hand
(`CLAIM_SESSION_ID`, extracted from the claim comment and compared against the **head** record
about 130 lines above). `lean-reconcile.sh` breaks the chain on three conditions the boundary
ignores: a link naming no review session, a link naming the **build** session, and a link whose
session already authored another round. So the authoritative, model-free gate is strictly weaker
than the advisory operator-side one, on exactly the property inheritance introduced.

What the fix round did address is real and is the half that mattered most: `inherit_candidate` now
skips a candidate this round authored and continues to the last independent round, so the
production writer no longer emits the shape the three readers disagreed about (`(z5)`/`(z5b)`).
That closes the non-adversarial path. The residual is the adversarial one: a hand-written round-1
record naming the build session (or none), inherited by a genuine round 2 that then reads only the
delta.

Two things the spec should not keep saying while that is true:

1. `docs/plans/second-shift-375-lean.md` justifies the split as "the arm only the operator-side
   reader can meaningfully make". That is not so for two of the three sub-arms — the boundary
   already extracts the build session id and already uses it, and the duplicate-session-in-chain
   arm needs no identity at all, only each link's own session key read through the `git show` the
   walk already performs.
2. `check-lean-chain.sh`'s evidence-6 header says the boundary now guarantees "a CHAIN of
   independent reviews covered it". Its **printed** line is precisely honest ("each resolving to
   an earlier verdict record on this branch"); the header comment is the part that overstates.

**Why this is a warning and not a blocker, stated rather than assumed.** Round 1 raised this same
defect as W2 with its reasoning on the record, and the lane's rule is that a round-1 warning is not
re-scored upward in round 2 without new information — there is none here. No `AC-n` is unmet on its
letter: AC-8 assigns the independence arm to the third reader and the spec's Design section states
the split deliberately. And the residual buys an adversary nothing they lacked: the boundary
already passes a hand-written **head** record carrying invented run/session ids, so a forged link
is the same capability applied to an older file version, at the tamper-**evidence** altitude
`lean-gate.sh`'s own header and D-47 already declare. Cheapest close, if taken later: extract the
session key per link inside the existing walk and mirror `lean-reconcile.sh`'s three arms —
otherwise narrow the two prose claims above to "links resolve".

### Per-`AC-n` scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `(V2)` positive / `(V4)` negative at the boundary; `(x3)`/`(x6)` at milestone 4. |
| AC-2 | satisfied | `(x2)` pins both halves (re-touched file in range, untouched file out); `(x5a)`/`(x5)` pin rebase survival with an explicit non-vacuity assertion. Exercised live: `bash G delta 375` on this head. |
| AC-3 | satisfied | `(x7)` and `(V5)` each assert the round that BROKE the chain is named **and** that the round whose link resolves is not. |
| AC-4 | satisfied | Pre-#375 records read as roots at all three readers — `(z3)`, `(V6)`, `(N1)`. Confirmed in production: CI reads round 1's own pre-sentinel record as a root. See note 2 on the AC's now-stale wording. |
| AC-5 | satisfied | `(x6)` / `(V4)` / `(N3)` — refused at all three readers, never downgraded to a root. |
| AC-6 | satisfied | `(x3c)` drives the P10 arm on a record whose chain resolves cleanly, so authorship is the only thing that can red; the boundary's head-record arm is unchanged and green on this PR. The clause's per-link reach at the boundary is the warning above, scored as round 1 scored it. |
| AC-7 | satisfied | `review-lean/SKILL.md` steps 4–5 (delta first; full range when nothing is verifiable to inherit; prior record's findings read first, with the fixed-vs-re-introduced reasoning) plus the new "narrows what you READ, never what you must find" rule. Verified by executing steps 4–5 for this review. |
| AC-8 | satisfied | `(N2)` a two-round chain with distinct sessions reconciles; `(N4)`/`(N5)`/`(N6)`/`(N7)` the four refusals. |
| AC-9 | satisfied | Reproduced independently — see Verification. Survivor set matches the committed baseline member-for-member (13 = 13, no baselined row unenumerated, no unbaselined survivor). The riskier row removal was hand-checked. |
| AC-10 | satisfied | 8/8 commits carry a `Changelog:` trailer; `check-changelog-trailer.sh` on the base → OK. |
| AC-11 | satisfied | Writer emits unconditionally; three readers share one header-anchored extraction (two `verbatim` rows, both PASS). Both the dangling and the resolving variants driven at each reader via `--summary-file`, the path a reviewer's findings actually arrive through. Probed directly besides. |
| AC-12 | satisfied | `inherit_candidate` skips a candidate matching this round's run **or** session id and continues rather than degrading (`(z5)`/`(z5b)`); the committed / dirty arms precede the chain arm in `cmd_4` (`(z4)`/`(z4b)`, verified by reading the ordering too). |

### Notes

1. **Two `AC-n` were added mid-run.** AC-11 and AC-12 were written in the fix round to name the
   defect round 1 found. The skill's rule about a spec amended to match the diff is aimed at a bar
   being *lowered*; this raises it, the build round disclosed it in the PR body rather than folding
   it in silently, and round 1 found the defect without either AC existing. Scored as satisfied,
   with the amendment stated — rejecting it remains the operator's call, not the reviewer's.
2. **AC-4's wording is now stale**, disclosed but not fixed. Its subject is "a round-1 record — no
   inheritance key". After the fix the writer emits the key on every round, so that phrase now
   describes only pre-#375 records. The property still holds for both shapes and `(x1)`'s comment
   says exactly this; the fix round amended the spec anyway, so AC-4 could have been re-worded in
   the same edit.
3. **Round 1's note 3 stands.** `review-lean/SKILL.md` is 60 → 74 lines on this PR, against a
   sibling that carries a hard 60-line cap guarded by `(f)`. The PR body's "the skill edit is
   net-zero on line count" is true of the **fix round** only; it does not address the note. Not an
   action — round 1 flagged the asymmetry only — but the phrasing reads as a resolution.
4. **`cmd_delta` takes the round's identity from the environment**, which is correct and its
   comment explains why the review run-id cache would be wrong (it holds the *previous* round's id
   at that moment). Residual, documented in the code: invoked with neither identity set — an
   operator poking at the range outside a session — a re-run round would anchor on its own earlier
   record and print a narrower range than the record it later writes will declare. In a real review
   session the session id is always set, so the own-record skip still fires.
5. **The help-range trap did not recur.** All three `sed -n '2,Np'` ranges match their file's last
   header line exactly (121 / 67 / 112, checked by re-deriving each), and `(w)` and the new `(O)`
   each assert presence of that last line **and** absence of `set -uo pipefail`, which is what
   makes the `cmp-z` mutant killable on both sed dialects.
6. **This round used the branch's own `lean-gate.sh`**, per round 1's note 4 — the installed plugin
   has neither the `delta` subcommand nor the inheritance keys, so a schema change can only be
   reviewed against itself.
7. **`delta` and `verdict` can disagree, and did on this very record — safely, but say it out
   loud.** `verdict` derives its link from a *committed record whose patch differs*; `delta`
   additionally needs that patch to **anchor a commit** on the branch, so it can print the FULL
   range while `verdict` still names a link. That is what happened here: the rebase's conflict
   resolution means round 1's tree is no state this branch ever passed through, `delta` printed
   FULL and this round read everything, yet the header of this record names round 1 anyway. The
   direction is always the safe one — `delta`'s range is a superset of what the record declares,
   never a subset, because `verdict`'s candidate set is a superset of `delta`'s — so the union
   claim downstream readers compute stays true. The exposure is a reviewer who computes the delta
   themselves from the pointer key instead of running `bash G delta`: they would read less than
   this record implies was read. Worth a line in `cmd_delta`'s comment, or a `delta`-side note that
   an unanchorable link is still recorded.

### Verification (independent, from the PR-head checkout at `7363651`)

| Check | Result |
| --- | --- |
| `shellcheck` repo sweep (`-e SC1091,SC2015,SC2181`) | clean, 0 lines of output |
| `jq empty` over every `*.json` | clean |
| 63 selftest suites, **no** `SKIP_STRESS`, `env -u CLAUDE_CODE_SESSION_ID` | rc=0, zero failure lines |
| `scripts/check-lockstep-pairs.sh` | 15 pairs checked, 0 failed — both new `verbatim` rows PASS |
| `bash G delta 375` (branch's own gate) | FULL range, `d5b3fa5..HEAD` — the honest outcome after a conflict resolution |
| `tools/mutation-sweep.sh --mode pr --base <base>` | `10/7/3`, `12/7/5`, `12/7/5` — reproduces the PR body's counts, and the survivor ids match the baseline member-for-member in both directions |
| `(M2)` kill claim, hand-applied | neutering the `Part of #N` fallback grep reds `(M2)` and **only** `(M2)` — the `detector::2` row removal reflects coverage, not a re-key hiding a survivor |
| header-anchored extraction, driven directly on 4 adversarial records | only the legitimate header value is returned |
| CI at `7363651` | `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass; `pr-gates` red on exactly one fact — round 1's record reads a non-approve verdict — reported twice by design |

### What the diff does well

- **The observability lesson is applied, not just recorded.** The chain's backwards-search window
  was unkillable in all three readers until its effect was printed; `chain_walk` now returns a link
  **count** and milestone 4 puts it in the pass line, which is what makes `(y2)`/`(V3b)`/`(N6)`
  able to red. The converse is handled with the same discipline: the ancestry arm that would have
  held by construction was DROPPED with the reasoning recorded rather than baselined.
- **The B1 fix is two halves that cover disjoint populations**, and the diff says so rather than
  presenting belt-and-braces: the sentinel protects records this writer produces, the header
  anchoring protects the ones it did not — including a record sitting on this very branch.
- **The fixtures are built by the real writer**, with hand-corruption confined to a single key on
  an otherwise production-derived record, and each block gets its own tree so an earlier block's
  committed records cannot make a later case pass for an unrelated reason. `(x5a)`, `(y1)`,
  `(V0)`, `(V2-fixture)`, `(N2-fixture)` each assert their own non-vacuity.
- **The mutation accounting distrusts the right claim.** "No ordinal moved" was checked at the
  **site** level rather than by matching id strings, which is the only method that can tell "same
  ordinal, same line" from "same ordinal, different line" — and it reproduces exactly.
