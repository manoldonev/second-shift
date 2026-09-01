# second-shift #724 — a consumer-shaped eval is the release gate

CI is model-free by design, so nothing it runs can answer "did this release make the kit
better or worse to use". This ticket adds the one measurement it structurally cannot make:
replay a fixed corpus of five tickets through the lean lane **in a consumer repo, with the
kit installed rather than in tree**, and record what it cost — so a release-over-release
delta says something about the kit rather than about the day.

The deliverable is a protocol, not an instrument. Nothing under `tools/` or `scripts/`
changes, no CI job is added, and no threshold blocks a release: the eval's output is four
numbers per fixture ticket and the maintainer's judgment over them.

## What this branch changes

- **`docs/consumer-eval.md`** `[NEW]` — the protocol of record: the corpus obligation, the
  pinned-base recipe, the four metric definitions with their exact sources, the non-merge
  rule, the per-release recording obligation, and the results table.
- **`docs/releasing.md`** — the release-time obligation stated inside the existing flow.
- **`CLAUDE.md`** — one pointer line alongside the existing per-doc pointers.

## Acceptance Criteria

- **AC-1** `docs/consumer-eval.md` exists and states all five of: the corpus obligation, the
  pinned-base recipe, the four metric definitions, the non-merge rule, and the per-release
  recording obligation.
- **AC-2** WHEN the protocol document and the issue are read THEN no consumer repository
  name, organization name, or stack-identifying technology appears in either; every
  reference is generic.
- **AC-3** **[AMENDED — see "Amendments" below]** For each of the four metrics the document
  prescribes its exact source: lane wall-clock from `retro-corpus.sh timing --state-dir`
  pointed at the consumer's state directory; **rounds from the committed verdict record's
  `rounds:` header key**; **the launch timestamp from the `launch` row of the last launch
  group in that ticket's `<issue>-lean-launches.tsv` that spawned anything at or before the
  merge**; the merge timestamp from
  `gh pr view --json mergedAt`; and, once the cost-per-merged-PR ticket lands, USD from the
  mechanism it establishes — until then the document states the `unavailable` fallback in
  its place.
- **AC-4** The document states the base-pinning recipe as an alternate config selected by
  `SECOND_SHIFT_CONFIG` whose `baseBranch` names a branch cut from a pinned commit, and
  states explicitly both that the consumer's default branch is neither modified nor rewound,
  and that the alternate config differs from the consumer's committed config in exactly one
  field — `baseBranch` — with every other field identical.
- **AC-5** The document states that the five specs live in the consumer repo, and states what
  the five must collectively exercise: a single-round pass, a seeded ambiguity that should
  cost a pause-and-ask, a bug carrying a reproduction, a multi-file change that exercises
  review depth, and one touching the consumer's stack edges — and that `F-1`..`F-5` bind to
  those five roles in that order, so a slot is comparable against itself across releases.
- **AC-6** **[AMENDED — see "Amendments" below]** `docs/consumer-eval.md` carries a results
  table whose columns are exactly those named under this plan's Data Contracts, with one row
  per (release, fixture ticket).
- **AC-7** WHEN a fixture ticket does not reach merge THEN its row records a null metric set
  and the named refusal class, and the document states such a run is never re-run and never
  dropped.
- **AC-8** The document states that the result is posted as a comment on the release PR
  before that PR merges, that the table row lands on `main` separately, and that the verdict
  is operator judgment — no stated threshold blocks a release automatically.
- **AC-9** `docs/releasing.md` states the release-time obligation — run the eval, comment the
  result on the release PR, land the rows on `main` — within its existing release flow.
- **AC-10** **[AMENDED — see "Amendments" below]** The body of the PR that implements this
  issue carries the bootstrap block for one fixture ticket run through this recipe in the
  consumer repo: each of the four metrics as actually measured, **or the named reason it was
  unavailable**. This is a one-time bootstrap artifact on an ordinary feature PR — the
  release-PR restriction in AC-8 does not apply to it, and it does NOT become a row in the
  results table.
- **AC-11** The change adds and modifies no file under `tools/` or `scripts/`, and adds no
  `*-selftest.sh`.
- **AC-12** WHEN no release has yet been evaluated THEN the results table is present in an
  explicit empty form rather than omitted.
- **AC-13** The document states WHY the result is a comment rather than an edit to the
  release PR body or branch — that the release-PR derivation force-pushes the branch and
  PATCHes the body on every push to `main`, erasing both — so the placement is not later
  "simplified" back into the body.
- **AC-14** The document states that the five replays run sequentially, one lane at a time,
  and states why — wall-clock is a compared metric and concurrent lanes on one machine
  contend for it.
- **AC-15** **[AMENDED — see "Amendments" below]** The document mandates that every eval
  launch passes the build model, the review model and the round cap explicitly rather than by
  default, and that all three are recorded on the row.
- **AC-16** The document states that each release files fresh fixture issues rather than
  reusing the prior release's, and states why — per-issue lane state would otherwise be
  reused, and the wall-clock figure would silently become release-to-release elapsed time
  rather than run time.
- **AC-17** `CLAUDE.md` carries a pointer line to `docs/consumer-eval.md` alongside its
  existing per-doc pointer lines.

### Amendments

Four ACs are amended against the issue's text. Each amendment is a measured fact about the
tree at this branch's base (`471ddadd`), not a scope reduction chosen here.

**AC-15 and AC-6 — the continuation cap does not exist.** The issue mandates that every eval
launch pass "the continuation cap" explicitly and carries a `continuationCap` column. #718
removed `--max-continuations` along with the continuation budget it bounded, and the flag is
now a hard refusal:

```
orchestrate-lean.sh:332
--max-continuations)  envfail usage-max-continuations "--max-continuations was removed in #718 …
                      There is no value of this flag to pass."
```

An eval launch that obeyed AC-15 as written would not start. The AC's *intent* — pin every
launch parameter the lane accepts, record each on the row — is honored over the three that
survive. Correspondingly `continuationCap` is dropped from the results table's column set.
Measured corroboration: every launch row written by the current orchestrator carries three
parameters, not four (`branch_key=… build=… review=… rounds=…`); the `continuations=…` field
appears only on rows written before #718 landed.

**AC-3 — the start rule the AC abbreviates does not hold when a ticket has more than one
launch group.** The AC prescribes "the first `launch` row … that was not a rejected
preflight". The issue's own Behavior §4 prescribes something different — "the first `launch`
row of **the run that produced the merged PR**" — and the two coincide only when exactly one
launch group survives the preflight filter. They do not coincide on this ticket's own ledger:
`724-lean-launches.tsv` carries three groups, of which `…223046Z-24696` is a rejected
preflight, `…223407Z-28860` spawned and stranded with no `terminal` row, and
`…062648Z-11087` produced the PR. The AC's rule returns the stranded group's `22:34:07Z`; the
Behavior clause's returns `06:26:48Z`, ~8 hours later, the gap being an operator asleep. The
same shape is live on #745's ledger. The document implements the Behavior clause and the AC
follows it, because a metric that exists for release-over-release comparability cannot carry
an operator's overnight gap. The generalized discard — keep only launch groups that spawned,
take the last at or before `mergedAt` — subsumes the rejected-preflight exclusion the AC
names, since a rejected preflight is exactly the group that spawns nothing. Correction of an
internal inconsistency in the issue, resolved toward the issue's own Behavior section, not a
scope change.

**AC-3 — `retro-corpus.sh timing` does not source `rounds`.** Its `rounds` field greps
`round=[0-9]+` out of the progress record, and the current record grammar no longer writes
that token: measured over this repo's four most recent lean runs, `wallClockMin` is populated
(122, 113, 44, 39) and `rounds` is null on all four. The figure is live on the **committed
verdict record's `rounds:` header key**, which is where the document points. `timing` keeps
the lane wall-clock half of D-13's prescription, which it does answer.

**AC-10 — the bootstrap run's stated dependency is unmet.** The issue lists as a dependency
that "the consumer repo must already be onboarded with the kit installed from a release pin,
which is the state that makes the measurement consumer-shaped rather than canary-shaped."
That state does not hold: the consumer repo's lockfile pins the marketplace at a moving
branch ref rather than a release tag, and its config is a schema generation behind. A replay
run there today would measure a canary-shaped configuration under a consumer-shaped name — a
figure worse than no figure, because it would enter the series as a baseline. The bootstrap
block therefore records each of the four metrics as `unavailable` with that reason named,
which is the branch AC-10 itself provides for. The recipe's computability is separately
demonstrated in the PR body against real recorded runs, so what is outstanding is the
consumer-repo replay, not the instrument.

**This amendment is not the build session's to make, and is not claimed as one.** The unmet
precondition sits under the issue's **Dependencies**, not its **Deferred** section, and an
unmet dependency means the ticket was not ready to build — it is not a licence for the build
to declare the AC void. The decision is recorded as an intent-gap record at
`docs/plans/second-shift-724-lean-intent-gap.md`, `ratified: no`, and the merge boundary
holds the PR red until an operator ratifies it. Whichever way it resolves — the replay runs
here, or the bootstrap is deferred to its own ticket — this amendment is provisional until
then.

## Data Contracts

**Results table** — one row per (release, fixture ticket):

| column | type | notes |
| --- | --- | --- |
| `release` | release tag | the tag this eval gates |
| `ticket` | fixture slot + issue number | `F-1`..`F-5` bind to the five roles in order; the cell also carries that release's issue number, since each release files fresh issues |
| `launchToMerged` | `HH:MM` or null | the last launch group that spawned anything, at or before the merge → PR `mergedAt` |
| `laneWallMin` | integer or null | the record's first timestamped row → milestone-4 satisfied, per `retro-corpus.sh timing` |
| `rounds` | integer or null | the verdict record's `rounds:` key |
| `usd` | decimal, or `unavailable` | never inferred, never estimated |
| `buildModel` | model id | passed explicitly, never defaulted |
| `reviewModel` | model id | passed explicitly; the shipped default is a constant a release can change |
| `roundCap` | integer | the launch cap, not the observed round count |
| `outcome` | `merged` \| `did-not-merge:<refusal-class>` | closed enum on the left side |

**Eval config delta** — the alternate config differs from the consumer's committed config in
exactly one field, `topology.repos.<host>.baseBranch`, which names the pinned eval base
branch. Every other field is identical.

## Out of scope

- The five spec bodies. They live in the consumer repo so they can name its actual stack; this
  repository carries the protocol and never the specs.
- Any file under `tools/` or `scripts/`, any selftest, any CI job (AC-11).
- A blocking threshold, a bare-session arm, and any kit-versus-bare comparator — that work
  belongs to the ablation-localisation epic.
- Automating `launchToMerged`. At five tickets per release the arithmetic is trivial, and
  automating it would grow the instrument this epic exists to shrink.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Reading of "5, fixed, replayed" | Five fixed fixture specs replayed against a pinned eval base branch; not fresh backlog tickets, and the consumer's default branch is never rewound | user-delegated |
| D-2 | What a bad result does | Recorded number plus operator judgment; presence is required, the verdict is not automated | user-answered |
| D-3 | Who computes launch-to-merged | The operator, by hand; the protocol doc prescribes the command | user-answered |
| D-4 | What the five specs exercise | Spread across the lane's failure modes: single-round pass, seeded ambiguity, bug with repro, multi-file review depth, stack edge | user-answered |
| D-5 | A fixture ticket that does not merge | Null metrics plus the named refusal class; never re-run, never dropped | user-answered |
| D-6 | Ratchet resolution under the stopping-rule epic | Doc-only: nothing under tools/ or scripts/ is touched, so the ticket is not harness-internal and owes no paired deletion | user-answered |
| D-7 | Where the fixture specs live | The consumer repo, stack-specific; this repo carries the protocol only | user-answered |
| D-8 | Where the release-over-release series lives | A committed table in docs/consumer-eval.md, one row per (release, ticket) | user-answered |
| D-9 | Whether the PR must prove the recipe runs | DEPARTURE — no end-to-end fixture ticket ran. The consumer repo is not onboarded from a release pin (the issue's own Dependency), so a replay there would enter a canary-shaped figure into the series as a consumer-shaped baseline. The recipe's computability is demonstrated in the PR body against real recorded ledgers instead. This departure is NOT the build's to decide: it is routed to the operator as the intent-gap record at docs/plans/second-shift-724-lean-intent-gap.md and is unratified until answered | user-answered |
| D-10 | Where the result durably lands | A comment on the release PR plus the row on main; the branch is force-pushed and the PR body PATCHed on every push to main (.github/workflows/release-pr.yml:94,110) | user-answered |
| D-11 | Queue order and the USD dependency | The cost-per-merged-PR ticket lands first; USD reads from whatever it establishes, per https://github.com/manoldonev/second-shift/issues/724#issuecomment-5479015792 | ticket-sourced |
| D-12 | How the pinned base is selected without changing the lane | An alternate config via SECOND_SHIFT_CONFIG; baseBranch is read from it (lean-gate.sh:489,529; orchestrate-lean.sh:357) | codebase-derived |
| D-13 | Instrument for rounds and lane wall-clock | `retro-corpus.sh timing --state-dir` (repo-agnostic) sources lane wall-clock. It does NOT source rounds: its `rounds` field greps a `round=` token the current progress-record grammar no longer writes, and reads null on every recent run. Rounds are read from the committed verdict record's `rounds:` header key. Correction of a codebase-derived fact, not a departure from intent | codebase-derived |
| D-14 | Consumer anonymization in this repo's artifacts | Generic "the consumer repo" throughout; the repo's own docs are uniformly generic (docs/skill-ablation.md:95, docs/context-model.md:10) | codebase-derived |
| D-15 | Whether the five replays run sequentially or concurrently | Sequential, and the doc states why: wall-clock is a compared metric, five lanes on one machine contend, and #525 records that a lane assumes it is the only run on the machine | user-answered |
| D-16 | Which launch parameters are pinned, and whether they are recorded per row | DEPARTURE — the continuation cap no longer exists: #718 removed `--max-continuations`; passing it is a hard refusal (`orchestrate-lean.sh:332`), and the current launch row writes three parameters, not four. The intent is honored over the three the lane accepts: build model, review model and round cap are passed explicitly on every eval launch and carried as table columns | user-answered |
| D-17 | Whether corpus slots bind to roles | F-1 through F-5 bind to the five roles in order, so a slot is comparable against itself across releases rather than only in aggregate | user-answered |
| D-18 | Whether the bootstrap dry run gets a table row | No, it lives in the implementing PR body only. The table is keyed on release tag and AC-12 mandates an explicit empty form until a release is evaluated | user-answered |
| D-19 | Fixture ticket identity across releases | Fresh issues each release; the ticket column carries both the slot and that release's issue number. Reuse would reuse the per-issue progress record, and retro-corpus timing computes wall as milestone-4 satisfied minus the record's FIRST timestamped row, silently yielding release-to-release elapsed time | user-answered |
| D-20 | Discoverability of the protocol document | One pointer line in CLAUDE.md alongside its existing per-doc pointers | user-answered |
| D-21 | The results table's explicit empty form | Mirrors the repo's established explicit-empty convention rather than inventing a phrasing | codebase-derived |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | Whether USD is attributable per fixture ticket, given the cost figure is not yet captured on the spawn path | reversible-default-and-flag |
| OR-2 | When the pinned eval base may be re-pinned, and what a re-pin does to series comparability | reversible-default-and-flag |
| OR-3 | The lean lane has never run in the consumer repo at all — the first eval is also the first proof the lane works there | reversible-default-and-flag |

OR-1's default: the column reads `unavailable` and the release row is flagged, rather than the
eval blocking on the cost ticket. Reversible because a later release backfills nothing and
simply starts recording. OR-2's default: never re-pin; a re-pin is disclosed and starts a new
series segment. Reversible because the prior segment stays readable. OR-3's default: the first
release's run is recorded and marked as a shakedown, so a lane bug found on first contact is
not misread as a baseline. Reversible because the second release supersedes it as the baseline.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | The protocol document a maintainer reads at release time | decided (D-1, D-15, D-19) |
| S-2 | The results table, including its no-run-yet state | decided (D-8, D-16, D-17, D-21) |
| S-3 | The release-time obligation in the release checklist of record | decided (D-6) |
| S-4 | The result as it appears on the release PR | decided (D-10) |
| S-5 | A row for a ticket that did not merge | decided (D-5) |
| S-6 | The bootstrap proof on the implementing PR | decided (D-9, D-18) |
| S-7 | The five fixture spec bodies and the eval config | out-of-scope — they live in the consumer repo, not here (D-7) |
| S-8 | Any rendered CI or release-PR checklist output | out-of-scope — no file under scripts/ is touched (D-6) |
| S-9 | The pointer line in CLAUDE.md that makes the protocol findable | decided (D-20) |
