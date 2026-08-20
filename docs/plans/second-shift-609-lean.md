# second-shift #609 — paper ablation of the lane's gates over the run corpus

**Issue:** [#609](https://github.com/manoldonev/second-shift/issues/609)
**Branch:** `claude/second-shift-609`

## Problem

The lane's blocking gates have never been held to the bar the mutation sweep holds every guard to:
name the regression class only you catch, with a dated incident. `docs/pipeline-manifesto.md`'s V1
already states the thesis — strictness that cannot change the merge decision does not get to block
— but nothing measures it, so every pruning argument is rhetorical.

## Approach

The mutation-testing transplant, on paper: disable a gate and ask whether any historical run's merge
decision changes. The substrate already exists — every lean run leaves a timestamped, append-only
`{issue}-lean-progress.md` whose `attempt` / `absent` / `obligation` rows are exactly the gate's
firings, and every reviewed run leaves a committed verdict record whose per-round patch-id chain is
the one true content-diff observation the lane records.

A checked-in generator reads that corpus against two committed input tables — a reason-class map and
a recorded adjudication set — and emits the report's mechanical tables. A committed corpus manifest
of record ids plus content hashes defines "unchanged corpus", so the mechanical half is reproducible
even though the records themselves are host-local and gitignored.

## Findings that amend the issue

Recorded before implementation; each changes what the ACs must cover.

- **F-1 — a true per-firing content diff is not recomputable, and that is the report's central
  limitation.** The lane's branches are squash-merged and deleted, so no branch history survives on
  `main`; the progress record carries no commit sha at any row. The only committed patch-identity
  observations are the verdict record's `reviewed_patch_id` / `inherited_patch_id` pair, which cover
  milestone-4 round boundaries and nothing else. The mechanical column therefore resolves to a real
  content diff for milestone-4 firings and to a labeled `unmeasured` everywhere else. AC-3 exists to
  say so rather than to let `unmeasured` read as a pass.
- **F-2 — milestone 2 has never fired.** Across the whole corpus: 52 `satisfied` rows, **zero**
  `attempt` rows. Its two constituent checks (`check-frozen-files.sh`, `check-changelog-trailer.sh`)
  also run at the merge boundary in `pr-gates`, so its blocking arm is redundant by construction.
  This is the report's headline demotion candidate and it must survive contact with the earn-your-keep
  test, not be asserted.
- **F-3 — twelve of the twelve `advisory` rows in the corpus are milestone 2's**, all the frozen-files
  workflow-edit notice. A milestone whose only recorded output is advisory is a distinct finding from
  one that never ran, and the report must not merge the two.
- **F-4 — the `obligation` row kind postdates almost the whole corpus.** `append_obligation` (#531)
  writes one row per `(obligation, state)` pair at milestone 5; exactly **one** such row exists in
  the corpus today. AC-1's "milestone-plus-obligation granularity where the records name obligations"
  is therefore satisfied by one row, and every other sub-milestone identity must come from the
  reason-class map — which is why that map is a committed deliverable and not an implementation
  detail.
- **F-5 — `no committed spec` appears in two row kinds.** Older records record it as
  `milestone-1 | attempt` (39 rows, spending fix budget); newer ones as `milestone-1 | absent`
  (21 rows, spending none). The same gate decision point straddles a schema change, so the generator
  must key on the reason class rather than the row verb, and the report must state the split — a
  point counted twice under two identities would fabricate a fire count.
- **F-6 — repeat `started` rows without an intervening `concluded` are the reap signature, not
  firings.** `528-lean-progress.md` carries three such pairs. They inflate any "the gate ran again"
  proxy and are precisely why AC-4 makes the repeat-firing count an upper bound.
- **F-7 — three lanes are in flight while this runs** (#546, #609, #611, per `lean-lanes.tsv`). Their
  records are still being appended to, so pinning them in a manifest would pin a moving file. The
  manifest generator excludes registered live lanes mechanically and records the exclusion in the
  manifest header, so the corpus boundary is derived rather than hand-curated.
- **F-8 — the stage-era corpus is 47 records** (`{issue}.json`, a `stages` key). They describe gates
  that no longer exist. Listed as out-of-corpus, counted, never scored.

## Design decisions

- **D-a — the mechanical column is record-derived, four-valued, and never repaired by inference.**
  `content-moved` / `content-still` are written only where a verdict-record round boundary covers the
  interval after the firing (a real `reviewed_patch_id` vs `inherited_patch_id` comparison);
  `no-response` where the record shows no later evaluation of that milestone at all; `unmeasured`
  where a later evaluation exists but no patch-identity observation covers the interval. There is no
  fifth value and no fallback to git metadata, file mtime or merge time (F-1).
- **D-b — the adjudicated column is data, not prose.** `tools/gate-ablation-adjudication.tsv` carries
  one row per gate point, optionally overridden per `issue:gate-point`, each with a mandatory
  citation. The generator refuses to emit for a firing whose gate point has no row, so the file
  cannot silently go stale as the corpus grows.
- **D-c — an unclassified firing reds.** A reason text no `tools/gate-ablation-classes.tsv` pattern
  matches is a hard failure naming the record and the text, not an `other` bucket. A silent `other`
  bucket is how a new refusal class joins the corpus without ever being enumerated.
- **D-d — the report embeds generated blocks between markers, and `check` regenerates and diffs.**
  This is what makes AC-5's byte-for-byte claim testable rather than asserted, and it needs no
  prose-presence grep.
- **D-e — OR-1 gets its reversible default plus a flag.** `--granularity class` (default) keys at
  milestone-plus-reason-class; `--granularity milestone` collapses to the milestone. The default is
  the finer one because collapsing is lossless and re-splitting is not.
- **D-f — the scrub is a gate, not a convention.** `emit` refuses (rc=4) when its own output contains
  a UUID-shaped token or an absolute path, so AC-5's "no session ids, no absolute local paths" cannot
  regress into the committed report through a quoted reason.

## Decision Ledger

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Ablation scoring rule | Two labeled columns per firing: a mechanical outcome-diff (reproducible; the reproducibility criterion binds to it) and a recorded adjudication citing the record (ranks the demotion table; disclosed as judgment). Phase 2 inherits both, labeled. | user-answered |
| D-2 | Corpus and reproducibility substrate | Artifact-schema (lean-era) runs only; subjects are the lane's record-backed gate decision points — prose constructs belong to the census slice. Progress records stay host-local; a committed corpus manifest (record ids plus content hashes) defines "unchanged corpus"; the committed report carries no session ids and no absolute paths. | codebase-derived |
| D-3 | False-red tally semantics | A stated lower bound counting only refusals a committed record explicitly contradicts; the repeat-firing heuristic is reported separately as a labeled upper-bound diagnostic (reaped and idempotent re-invocations over-count it). | codebase-derived |
| D-4 | Generator and report location | Repo-level (tools/ plus docs/), not inside a shipped plugin; write-nothing refusal classes are unmeasured by construction and listed as such. | codebase-derived |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-1 | The reason-class mapping table's granularity below the milestone-plus-obligation key | reversible-default-and-flag — resolved by D-e |

## Acceptance criteria

- **AC-1** `docs/gate-ablation.md` enumerates the lane's record-backed gate decision points, keyed at
  milestone-plus-obligation granularity where the records name an obligation and by reason class
  otherwise. The reason-class map is `tools/gate-ablation-classes.tsv`, committed and part of the
  deliverable. Every point carries its fire count across the corpus, including the zero-fire points,
  and every firing is listed with a citation of the form
  `<record-id> • <milestone> • <ISO timestamp>`. A reason text no pattern matches is a hard failure
  (D-c), not an `other` bucket.
- **AC-2** Each firing carries two labeled columns: `mechanical` (D-a, generator-computed) and
  `adjudicated` (D-b, from the committed adjudication table, each row citing a record). The
  demotion-candidate table ranks by the adjudicated column — primary key the count of firings
  adjudicated as changing no decision, secondary key measured cost — and every gate point with at
  least one adjudicated decision-changing firing carries that dated incident as its earn-your-keep
  row instead of appearing as a candidate.
- **AC-3** The report's method section states what is recomputable from records and what is not
  (F-1). Refusal classes that write no record — the wrong-tree refusal (`rc=9`), the unattested-entry
  refusal, usage/environment errors (`envfail`), and every scheduler decision, since the scheduler
  authors nothing — are listed as unmeasured by construction, with the sentence that an unmeasured
  gate is a stated limitation and never an implied pass. The 47 stage-era records are listed as
  out-of-corpus with their count.
- **AC-4** The false-red tally is a stated lower bound counting only firings a committed record
  explicitly contradicts, each carrying that record's citation. The repeat-firing count — the same
  milestone re-fired with the same reason class and no intervening evaluation of another milestone
  and no session-change row — is reported separately and labeled an upper bound, naming reaping (F-6)
  and idempotent re-invocation as the over-count sources.
- **AC-5** `tools/gate-ablation.sh` is checked in with `tools/gate-ablation-selftest.sh` beside it,
  offline via `--state-dir` / `--classes` / `--adjudication` / `--manifest` seams. `manifest` mode
  emits `docs/gate-ablation-manifest.tsv` (record id plus sha256, live lanes excluded per F-7 and
  named in the header); `emit` verifies every manifest row against the live corpus and exits 3 naming
  any record that drifted or went missing; `check` regenerates and diffs against the block embedded
  in the committed report, exiting 1 on drift. Two `emit` runs over a manifest-matching corpus are
  byte-identical. `emit` exits 4 if its own output carries a UUID-shaped token or an absolute path
  (D-f).
- **AC-6** `docs/pipeline-manifesto.md`'s V1 points at the report, so the principle that motivated
  the measurement names the evidence that now exists. No gate behavior, skill or manifesto principle
  is otherwise edited.

## Known trades

- **The adjudicated column is judgment and is disclosed as such.** It is authored by the run that
  builds the generator, from the records, and it is the column the demotion table ranks by. The
  mechanical column exists so that half the report can be re-derived by someone who does not trust
  the other half.
- **`unmeasured` will dominate the mechanical column** (F-1). That is the honest state of the
  evidence, and AC-3 is the mitigation: it is reported as a limitation on the report's own reach, not
  smoothed over with a proxy that would read as a measurement.
- **The corpus is one machine's.** Progress records are host-local by design. The manifest makes what
  was measured auditable; it does not make the corpus universal.

## Sequencing

Blocks #610 (census triage) by design — the successor consumes this report. No dependency in the
other direction, and nothing here touches a gate, so it cannot collide with the other batch-1 slices.
