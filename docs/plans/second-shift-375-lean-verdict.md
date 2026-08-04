# lean review verdict — #375

verdict=needs-work
run_id: review-375-1
session_id: abe4301f-39be-48e9-be38-982a13dce4df
rounds: 1
pr: #377
reviewed_head: 30d99ec61569f5aeacfa4a43d3b10f9429186870
reviewed_patch_id: 0443c97122104c5ff7603e3020fb2b492a3ad374
model: unknown

## Round 1 — `needs-work`, one blocker

Reviewed at `d833c42` (`main..HEAD`, the full branch diff — `bash G delta 375` printed the FULL
range, this round being a chain root). The committed spec
[`docs/plans/second-shift-375-lean.md`](docs/plans/second-shift-375-lean.md) is the definition of
done.

**All ten `AC-n` are satisfied.** The blocker is not an unmet AC — it is a defect the diff
introduces that no AC names, and it was found by the act of recording this verdict: the first
version of this round's record was written `approve`, committed and pushed, and reduced its own
PR's `pr-gates` to red. That record is the reproduction.

### B1 (blocker) — a chain-ROOT record's own summary prose injects the key all three readers gate on

`inherited_patch_id` is the first key in the verdict-record schema that is **conditionally
emitted**: the writer omits it entirely on a root record. Every other key the readers gate on is
always in the header, which is what makes the documented mitigation work — `cmd_verdict` states it
in as many words, that "all three readers take the FIRST match of each key, so an injected
`run_id` loses to the authentic one written above it". For a key that is **absent** there is no
authentic occurrence to win the race, so the first match in the file is whatever the reviewer's
prose happens to contain.

Reproduction — the record this session pushed at `30d99ec`, written by the production writer, no
hand-editing:

```
$ sed -n '1,11p' docs/plans/second-shift-375-lean-verdict.md     # the header the writer emitted
verdict=approve
run_id: review-375-1
session_id: abe4301f-39be-48e9-be38-982a13dce4df
rounds: 1
pr: #377
reviewed_head: d833c427936d24a2feb0bed38bc37490347c8b1f
reviewed_patch_id: 0443c97122104c5ff7603e3020fb2b492a3ad374
model: unknown
                                                    <-- NO inheritance key. Correct: it is a root.

$ grep -n 'inherited_patch_id' <the record>
71: ... a line inside the round's own findings, quoting a fixture's keys ...

$ bash G 4 375
[lean-gate] ✗ milestone-4: ... round 1 declares an inherited patch of 20cd8549f053, which matches
no earlier verdict record committed on this branch ... Get a review round that reads the full
diff: '/dev-pipeline:review-lean <pr>'.

$ gh pr checks 377
pr-gates   fail
```

Line 71 is prose. The record declares nothing. All three readers use the identical
`grep -oE '<key>:[[:space:]]*[A-Za-z0-9._-]+' | head -n1` extraction
(`lean-gate.sh` `record_key`, `lean-reconcile.sh` `extract_key`, `check-lean-chain.sh` line 322),
so milestone 4, the merge boundary and reconcile all reach the same wrong value.

**Why this is a blocker and not a warning.** It is not reachable-in-principle, it is the state
this PR is in right now. The trigger is a round whose findings *discuss the feature* — which is
every review of this PR and every future round that reports on inheritance at all — and the
remedy the refusal prints is unreachable: a fresh round that writes the same finding reproduces
the same refusal. A correct `approve` on a correct branch cannot be recorded.

**And the refusal is the benign half.** The injected value is read as a *claim of inherited
coverage*, so where the refusal happens to be avoided — a token in prose that matches an earlier
record's reviewed patch — a root record is credited with coverage no round performed. That is the
inverse of the property the chain exists to guarantee.

Fix directions, for the build round to choose between:

- **Emit the key unconditionally**, with an explicit sentinel on a root record (`none`), so the
  authentic header value always wins first-match. This is the shape the schema's other derived
  keys already have, and it makes absence a written fact rather than an inference. Readers map the
  sentinel to "no inheritance".
- **Or anchor the extraction to the header**, e.g. line-anchored `^inherited_patch_id:` or reading
  keys only above the first blank line. Note that `record_verdict`'s comment rejects anchoring for
  `verdict=` specifically because the earliest committed records wrote it as a bullet or a table
  cell — that reasoning is about a legacy corpus, and `inherited_patch_id` has none, so anchoring
  is available for this key even though it was not for that one.

Either way the guard has to be a fixture whose `--summary-file` body **contains the key** — a case
in `lean-gate-selftest.sh` driving the real writer that way, with counterparts at the other two
readers, since all three share the extraction. Without that the fix is unkillable in exactly the
sense this PR's own `(y2)`/`(N6)`/`(V3b)` cases were written to avoid.

Two documentation consequences ride along: `cmd_verdict`'s "nothing escalates today" paragraph is
now false as a statement about the schema, and `record_key`'s comment ("the SAME extraction
`lean-reconcile.sh` uses ... two readers of one schema that disagreed would be a silent
divergence") is right about agreement and silent about the shared blind spot — three readers
agreeing on a wrong value is not the divergence it guards against.

### Per-`AC-n` scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `check-lean-chain-selftest.sh` (V2) positive / (V4) negative. Reproduced independently: a fixture drives the real writer through two rounds and the boundary prints `✓ inheritance chain: 2 inherited link(s)`, rc=0. |
| AC-2 | satisfied | `lean-gate-selftest.sh` (x2) pins BOTH halves — the re-touched file is in the range, the untouched one is not. (x5a)/(x5) pin rebase survival with an explicit non-vacuity assertion that the pre-rebase head really left the branch. Exercised live: `bash G delta 375` on this branch. |
| AC-3 | satisfied | (x7) and (V5) each assert the round that BROKE the chain is named AND that the round whose link resolves is not — a bare presence check would pass on the wrong attribution. |
| AC-4 | satisfied | (x1) the writer emits neither key on a round 1; (V1)/(N1) both readers print the absence rather than skipping it silently. B1 is a consequence of how that absence is *read back*, not of the write side. |
| AC-5 | satisfied | (x6) / (V4) / (N3) — refused at all three readers, never downgraded. See note 1 on the wording change from the issue's own AC-5. |
| AC-6 | satisfied | (x3c) drives the P10 arm on a record whose chain resolves cleanly, so authorship is the only thing that can red. The second clause is the subject of W2. |
| AC-7 | satisfied | `review-lean/SKILL.md` step 4 (delta; full range when nothing is verifiable to inherit), step 5 (prior record's findings first, with the fixed-vs-re-introduced reasoning), plus the new "narrows what you READ, never what you must find" rule. Verified by executing step 4 for this review. |
| AC-8 | satisfied | (N2) a two-round chain reconciles; (N4)/(N5)/(N6) the three refusals. Reproduced live on a production-written record. |
| AC-9 | satisfied | Reproduced, not read off the PR body — see Verification. |
| AC-10 | satisfied | `Changelog:` trailers on 5/5 commits; `check-changelog-trailer.sh main` → OK. |

### Warnings

**W1 — milestone 4 asks "does the chain resolve?" before it asks "is this record committed at
all?", so an uncommitted round-≥2 record gets the wrong refusal and the wrong remedy.**
`cmd_4` reads the inheritance key from the working-tree file and walks the chain at line 790, but
the "was never committed" and "tracked-but-dirty" arms are at 818–829. With a round-2 record
written and not yet committed, `git log -1 -- $VERDICT_REL` resolves to *round 1's* commit, the
window trims it away, and the round-1 identity the record legitimately declares matches nothing
left in the window. Reproduced:

```
### round-2 record WRITTEN but NOT committed, then 'bash G 4'
[lean-gate] ✗ milestone-4: ... round 2 declares an inherited patch of 65d8c022ab75, which matches
no earlier verdict record committed on this branch ... Get a review round that reads the full diff.
### same record, now COMMITTED (control)
[lean-gate] ✓ milestone-4: ... inheriting 1 verified earlier round(s)
```

The correct message is the one at line 820 ("exists but was never committed — commit and push
it"); the message actually printed sends the reviewer to redo an entire round. Fail-closed, no
false pass, round-1 records unaffected. Fix is the arm order: move the chain block below the
`v_commit` / dirty checks — also where the block's own comment ("who wrote this record, then what
does it claim to cover") implies it belongs, since "is there a committed record at all" precedes
both questions.

**W2 — the writer emits, with no hand-editing, a chain link that `lean-reconcile.sh` refuses and
that the CI merge boundary credits as an independent round.**
`review-lean` permits re-running a round on its cached identity. If the branch moved in between,
`inherit_candidate` finds the newest committed record whose patch differs from the current tree —
which is *this round's own earlier version*. Driven entirely through the production writer:

```
run_id: review-9-2      session_id: sess-r2      rounds: 2
reviewed patch  58e60116fd8a...     inherited  20cd8549f053...   <- its own prior version

lean-gate.sh milestone 4      ✓ ... inheriting 2 verified earlier round(s)
check-lean-chain.sh (CI)      ✓ inheritance chain: 2 inherited link(s), each resolving to an
                                earlier verdict record on this branch      → rc=0
lean-reconcile.sh (operator)  ✗ round 2 was authored by session 'sess-r2', which already authored
                                another round in this chain                 → rc=1
```

Two things fall out. The three readers disagree about a record the writer produced — and the count
both other readers print ("2 verified earlier rounds") overstates what happened by one. And the arm
that catches it is the operator-run reader, not CI: the spec places the independence check there on
the grounds that it is "the arm only the operator-side reader can meaningfully make", but CI already
extracts the build run's identity from the claim comment and already compares it against the *head*
record — extending that comparison to every link is mechanical, and it is what would put AC-6's
second clause ("inheritance opens no path around P10") behind the boundary that actually gates
merges.

Not scored a blocker, and the reasoning rather than the conclusion: no `AC-n` is unsatisfied on its
letter; the same-session path only arises once the reviewer has already broken this skill's own rule
that a push changing a line costs a new round, which makes `lean-reconcile`'s refusal *correct* and
the defect "the writer does not warn"; and the P10 face needs a hand-forged record that milestone 4
and CI would each refuse while it was the head record — the tamper-evidence altitude this lane
already declares, not below it.

Cheapest fix at the source: have `inherit_candidate` skip a candidate whose `run_id` or session id
equals this round's. Both values are in hand at write time, and the round then degrades to a chain
ROOT — more reading, the direction the writer already degrades in when the chain beneath it breaks.

**W3 — the chain walk is hand-maintained in three copies, with neither a shared definition nor a
`scripts/lockstep-manifest.tsv` entry recording that decision.**
`chain_walk` / `versions_after` in `lean-gate.sh`, inline in `lean-reconcile.sh` (+ the session
arm), inline again in `check-lean-chain.sh` (`[[ ]]`, `CHAIN_*` naming). Each copy re-derives the
same three engineered edge cases — same-round idempotency, the strictly-backwards window, content
matching for rebase survival — and each re-explains them in its own prose. `CLAUDE.md` routes
exactly this shape either to a shared lib (the `scenario-lib.sh` / `runtime-shim-lib.mjs`
precedent) or, when the coupling is real but not byte-anchorable, to a **DROPPED** manifest entry
carrying the reasoning. Neither was done. The adjacent precedent is already in that file: the
verdict-record key schema has a DROPPED entry naming its one writer and three readers — and this
diff adds two keys to exactly that schema without extending it. B1 is what that entry would have
been for: a schema change whose *reader-side* consequence was not re-derived across all three.

Behaviorally the walk *is* guarded from three sides ((y2) / (N6) / (V3b) each pin the window
independently), which is why this is a warning and not a blocker on its own.

### Notes

1. The spec's AC-5 restates the issue's ("degrades to uninherited and is refused unless it covers
   the full diff") as a flat refusal. The issue's phrasing is unimplementable as written — no
   record asserts "I covered the full diff" — and the restatement is strictly the fail-closed
   reading. The spec is commit 1 of 5, so this is not a spec amended to match the diff. Scored on
   the spec's letter with the deviation stated.
2. OR-2 deviates from the issue's stated reversible default, under a `reversible-default-and-flag`
   disposition, with the rationale in both the spec and the PR body and the operator's answer as
   provenance. Correct handling — and case (x1) writes round 1 as `needs-work` deliberately so the
   resolution is pinned rather than assumed.
3. `review-lean/SKILL.md` went 60 → 74 lines. Its sibling `run-lean/SKILL.md` carries a hard
   60-line cap guarded by `(f)`; this file has no counterpart guard. Flagging the asymmetry only.
4. Schema bootstrap, for the next round: it must invoke the **branch's own** `lean-gate.sh`. The
   installed plugin (3.8.0) has no `delta` subcommand and would write a record without the
   inheritance keys. This review did so. The PR body does not say it.
5. This round's record was first written `approve` and pushed at `30d99ec`; B1 surfaced there and
   the record was corrected in place on the same round and the same review identity. No fix has
   happened yet, so this is still round 1 — not a round 2.

### Verification (independent, from the PR-head checkout at `d833c42`)

| Check | Result |
| --- | --- |
| `shellcheck` repo sweep | clean |
| `jq empty` over every `*.json` | clean |
| 63 discovered selftest suites, **no** `SKIP_STRESS`, `env -u CLAUDE_CODE_SESSION_ID` | rc=0, zero `FAIL` lines |
| `bash G delta 375` | FULL range, `7e8d868..HEAD`, 9 files — correct for a chain root |
| `check-changelog-trailer.sh main` / `check-frozen-files.sh main` | OK / clean |

AC-9 reproduced rather than accepted — a local diff-scoped `mutation-sweep.sh --mode pr --base
main`:

```
lean-gate.sh         applied=10 killed=7 survived=3   cmp-eq::1, default::1, default::2
lean-reconcile.sh    applied=12 killed=7 survived=5   fail-open::2, cmp-eq::1, detector::1, default::1, default::2
check-lean-chain.sh  applied=12 killed=7 survived=5   cmp-eq::1, cmp-eq::2, cmp-z::1, default::1, default::2
```

Matches the PR body's table and `tools/mutation-baseline.tsv` member-for-member after the two
removals. The claim behind the riskier removal was checked by hand rather than inferred: neutering
the `Part of #N` fallback grep reds `check-lean-chain-selftest.sh` on case `(M2)`, so
`detector::2`'s removal reflects coverage and not a re-key hiding a survivor.

### What the diff does well

The two defects the build found on itself are the load-bearing ones, and both are recorded honestly
in the PR body rather than quietly fixed. Making the window **observable** (`chain_walk` returning
`ok <links>`, milestone 4 printing the count) is what converted an unkillable guard into three
independently-pinned cases — the right move, and the general lesson. Dropping the "each link's
commit is an ancestor" arm from `lean-reconcile.sh` *with the reasoning recorded* is the same
judgment applied in reverse. And `(x)`/`(y)` each get their own fixture tree, with the reason
stated: `inherit_candidate` walks the whole path history, so a round-1 case run in the shared tree
would inherit whatever an earlier block left behind and pass for the wrong reason.

B1 sits squarely inside that strength rather than against it: the diff's own discipline is to ask
what a guard would fail on, and the one question not asked was what the *reader* does when the key
it gates on is legitimately absent.
