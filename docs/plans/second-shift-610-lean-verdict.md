# lean review verdict — #610

verdict=needs-work
run_id: review-610-1
session_id: 422625a7-b51f-43aa-9ff9-66842f919adb
rounds: 1
pr: #625
reviewed_head: 4f96119a85694ae1d70abc43042ef3dfc3585fdc
reviewed_patch_id: 4ea3297097df04d30a53846e91ad3d171c83ae05
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 1, full-range review of the whole branch diff (`ab0a2d68..4f96119a`, 16 files).
Verdict: **needs-work** — three blockers, two of them one-line fixes, one a red CI lane.

The census machinery itself is sound and I verified it end to end: `census` reproduces
37 constructs on the pre-prune tree and 12 on the pruned one across repeated runs,
`check` exits 0, the selftest is 40/40, and `shellcheck` is clean. The triage record's
arithmetic reconciles (37 pre-prune constructs, four of which collapse into one
lockstep row, gives the 34 rows the record carries). Every enforcer class named by a
`prose-deleted` row was read and confirmed to exist and to enforce the stated rule.

## Blockers

### B-1 — `mutation-sweep-pr` is red: four baseline-absent survivors in the new guard

CI's `mutation-sweep-pr` job fails at the `mutation sweep (PR-scoped)` step. I
reproduced it locally from the reviewed head, and the serial re-verify agrees on all
four, so this is not a pool artifact:

```
[mutation-sweep] swept tools/prose-blockers.sh - applied=8 killed=4 survived=4
[mutation-sweep] RED: baseline-absent survivor: tools/prose-blockers.sh::cmp-z::c5771a736ffe
[mutation-sweep] RED: baseline-absent survivor: tools/prose-blockers.sh::logic::910fb55b7039
[mutation-sweep] RED: baseline-absent survivor: tools/prose-blockers.sh::logic::a9a48aef45b2
[mutation-sweep] RED: baseline-absent survivor: tools/prose-blockers.sh::default::a9a48aef45b2
```

The ids are content-keyed and name no line, so I localized them from
`--emit-site-keys` plus the operators' own match patterns. They are two coverage gaps,
not four:

- **The default root derivation** (`tools/prose-blockers.sh:104-105`) accounts for
  three of them. `logic::a9a48aef45b2` and `default::a9a48aef45b2` share a key, and
  line 105 is the only line in the file carrying both a logical-and and a
  parameter default, which pins that pair to it by construction; `logic::910fb55b7039`
  is the preceding `SELF_DIR` line. Every selftest case supplies
  `PROSE_BLOCKERS_ROOT`, including the shipped-record case, so nothing ever exercises
  the fallback. The logic mutant is not equivalent — flipping that connector makes the
  command substitution emit nothing and `SELF_DIR` empty — it is simply masked by a
  harness that always overrides the value.
- **The `--full` branch** (`tools/prose-blockers.sh:294`) accounts for
  `cmp-z::c5771a736ffe`. `--full` is passed in three cases, but no assertion
  distinguishes full text from the 160-character excerpt, so inverting the test
  changes no observed output. It is killable: real constructs run to 1053 characters,
  so a fixture construct longer than 160 plus one comparison closes it.

Either kill them or add `tools/mutation-baseline.tsv` rows justifying them as
unkillable by construction. As it stands the lane is red on the repo's own contract.

### B-2 — AC-1's "the wider counts are reported" clause ships unimplemented

AC-1 requires the tiered predicate to be "widenable to `bold` and `all` by flag, and
the wider counts are reported so the default is honest about what it excludes." The
flags work — I measured 12 / 58 / 226 for `stop` / `bold` / `all` on the reviewed
tree. But no shipped surface reports them: `census` prints only its rows, `check`
prints only the stop-tier count, the triage record header carries no counts, and the
PR body asserts "their counts are reported" without giving a number.

The honesty this clause buys is that a reader can see the default excludes 214
constructs. Today they have to run two extra commands to learn it. The fix is one
summary line (in `check`, or in the record header) — but as shipped the clause is
unmet.

### B-3 — the `dup-scan-rc2` lockstep pins a sentence that is false at one of its four sites

`pb-5c1cd975` unifies four sites into one contract, pinned by a `LOCKSTEP` anchor. The
pinned sentence is:

> **`2`** - the scan could not run. Hard-stop: report the rc and the reason, and hand nothing off.

At three sites that is exactly right, and each site's tail agrees with it
(`plan-interview:80` "The ledger does not go with it";
`intake-orchestrator:409` "Do not apply the queue label; exit non-zero...").

At `intake-interviewer:250` it is not. The original read "**Hard-stop** the hand-off:
emit the draft, state the rc and the reason, and tell the user it is unscanned" — the
qualifier "the hand-off" was load-bearing, because at that site something *is* handed
to the user. The unification dropped it, so the pinned line now says "hand nothing
off" and the very next line (252, outside the anchor) says "Emit the draft anyway".
An agent reading top-down gets two contradictory instructions about the same rc.

This is worse than a wording slip because `check-lockstep-pairs.sh` now enforces the
contradiction: a future editor correcting that site must make the identical edit at
three sites where the current wording is correct. The lockstep mechanism should pin
the part that really is common — the hard-stop and the rc report — and leave what is
handed off to each site's tail, as the other three already do.

## Warnings

- **`text_has_caps_abort` is dead code** (`tools/prose-blockers.sh:186`). It is
  declared as an extra parameter of `is_construct` — an awk function-local — and read
  inside `stops()`, where the same name is an uninitialized global. The assignment
  never reaches the read. I probed it two ways: promoting it to a real global changes
  the census on neither the pre-prune tree (37 rows, identical) nor the pruned one
  (12 rows, identical); and deleting it from the expression outright fails no selftest
  case. So it is inert today — `commands_abort` catches the shipped arrow form — but
  the header documents a caps-`ABORT` arm that cannot fire, and a bare shouted `ABORT`
  with no connector word would be missed.
- **The PR body's prose-budget accounting names two stale rows; there are three.** I
  measured `prose-budget.sh --check` on `ab0a2d68`: it FAILs on six rows, three of
  which this PR regenerates — `build-lean` 1488→1847, `review-lean` 1683→1805, and
  **`onboard` 4747→5154**, which the body does not mention. Its `narrative_nnn` column
  moving 2→6 is the same stale-carry, not new ticket archeology. The prune takes it to
  5106, a real reduction from the tree it started on, so the conclusion holds — the
  accounting is just incomplete. Worth correcting because "two rows read as growth and
  are not" is precisely the kind of claim a later reader will rely on. The regeneration
  is otherwise commendably surgical: the three FAILs this PR does not touch
  (`QUERIES.md`, `figma-faithful-spec-reviewer.md`,
  `capability-parity-check-selftest.sh`) are left red rather than laundered green.
- **`refus(al|als)` is unkilled by any case.** Narrowing the alternation to
  `refus(e|es|ed|ing)` fails no selftest case, and no fixture or production SKILL.md
  uses the noun form. Minor — the sibling forms are covered — but one fixture line
  closes it.

## Findings raised by the panel and dismissed on probe

Two of the three `unit-test-mutation-reviewer` findings do not survive execution. Both
were predictions, not applied mutants; I applied them in an isolated copy of the tree
and scored by case id against an unmutated control:

- *"`commands_abort()`'s connector regex is untested — always shadowed by the caps-ABORT
  check"* (confidence 85). Refuted, and its premise is backwards: the caps check is the
  dead one (see the warning above), and the connector regex is what actually fires.
  Gutting `commands_abort` to return 0 fails the case "a commanded ABORT is a stop".
- *"`bold_prohibits()`'s even-index scan is only checked for inclusion"* (confidence
  82). Refuted. Widening the loop to every index fails the case "all widens the bold
  tier" — the cross-tier inequality the reviewer judged insufficient does catch it.

The third finding (the `refusal` alternation) reproduced and is carried above.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | **unsatisfied** | Census, corpus, block unit, lockstep/identical-text grouping, content-derived ids and the behavioral selftest all verified and reproducible. The "wider counts are reported" clause is unimplemented — B-2. |
| AC-2 | satisfied | 34 rows, 29 gate-backed / 4 promoted / 1 deleted, exactly one disposition each; `check` exits 0. The all-dark rule triaged like any row — operative site `pb-94ee597a` survives whole, duplicate `pb-bdd633e7` deleted. The one `deleted` row carries its reason, and I confirmed the rule it dropped still survives in the sentence above it. |
| AC-3 | satisfied | `check`'s UNRESOLVED arm passes, and I read the enforcers rather than trusting the cells: the wrong-tree refusal covering `delta` and `verdict`, the role-keyed verdict identity refusal, `check-lean-chain.sh`'s authorship and ratification arms, `scaffold-review-context.sh`'s two refusals, and `orchestrate-lean.sh`'s intake probe. No rule reached `deleted` while a gate still enforced it. |
| AC-4 | satisfied | All four promoted rows are `filed`, naming #622, #623 and #624. All three are open and all three read "Part of #605", so the parent epic owns them. No guard shipped, consistent with the one-guard-small threshold in D-1. |
| AC-5 | satisfied | Every non-comment row parses at exactly six fields; the header declares the column set, the path-plus-subcommand enforcer key, and its reversibility for phase-2 re-keying. |
| AC-6 | satisfied | `check` exits 0 on the pruned tree reporting zero undispositioned constructs, matching the PR body verbatim. The rc=3 arms (undispositioned, unpruned, stale, unresolved) and the rc=4 malformed arm each have selftest cases. |
| AC-7 | satisfied | The record header names #553, #554, #566 and #541 as owning the shell-prose residual, and the agent-contract residual as routing to #605. Baselines regenerated for the rows the prune moved. Scored satisfied because the AC asks for regeneration, not for the PR body's account of it; that account's gap is carried as a warning. |

Design fidelity: `not-applicable`. The spec disarms it explicitly
(`Design: none - this repo configures no design provider`), and I confirmed the repo's
config declares no design provider, so the disarm is justified rather than a
convenience.

## CI

`lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass, `release-pr-gates`
skipped. `pr-gates` fails at the lean-chain reconciliation step only, which is the
expected missing-verdict arm pre-review — the frozen-files, changelog-trailer and
pipeline-chain steps all pass. `mutation-sweep-pr` fails, which is B-1.

## Panel

Seven reviewers selected, seven returned — no dark reviewer and no coverage gap.
Security, performance, complexity, maintainability, test-coverage and
scope-completeness all approve. `unit-test-mutation-reviewer` requested changes; its
three findings are dispositioned above.

`a11y-reviewer` and the design-fidelity dimension were not routed: no changed path
matches the resolved web-component surface (the shipped default, since the repo
declares none). Not a coverage gap — nothing in this diff is a web component.
`db-reviewer` and `pipeline-reviewer` were not triggered.

Security's three suppressed items are recorded for visibility, all below the
confidence threshold and none of them a blocker: a temp-file trap that leaks
`check`'s two files into the temp dir when `census` re-arms the exit trap (70), an
unnormalized operator-supplied record path (60), and a root path containing a
substitution delimiter breaking a `sed` expression (55). The first is the only one I
would bother fixing, and it is hygiene rather than a defect.

## Strengths

- The census/disposition split is the right architecture and the header says why: the
  corpus regenerates from the tree, so a construct can neither enter it by being
  registered nor leave it by being forgotten. That is the defect class the dual-
  declaration registry shape produces, avoided by construction rather than by
  discipline.
- Content-derived ids with the re-key-on-edit failure mode stated as intended, not
  apologized for, and the record's `note` column carrying each predecessor id — the
  37→34 arithmetic is reconstructible by a reader without re-running anything.
- The predicate's narrow default is argued rather than asserted, and the `--tier`
  ladder makes the exclusion measurable instead of a matter of taste. The
  "no exclusion list, anywhere" decision (D-7) accepts a real cost to avoid a file
  that conflicts on every PR appending to it.
- `run-selftests-selftest.sh`'s scrub fix is correctly diagnosed and correctly scoped:
  it is the one invocation that bypasses the driver, so it carries the driver's scrub
  by hand, with the comment naming the concurrent-lane failure mode it prevents.
