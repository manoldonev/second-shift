issue: 552
run_id: lean-552-54aec70-a
session_id: dfb9ee56-1085-4762-b2dc-6d8acc42078f
region: undeclared
disposition: pause-and-ask
ratified: no
ratified_by:

## Gap

AC-10 adds a `prose-budget` job to `.github/workflows/nightly-guards.yml`. AC-8, as filed,
required that "existing markdown baseline rows keep their current values".

Those two are incompatible on this tree. The markdown ratchet is **already failing 26 files at
`54aec70`** — pre-existing drift, identical in count and membership on `main` and on this
branch, so it is nothing this slice introduced. It has been invisible because
`pipeline-doctor.sh` is the tool's only caller and it downgrades every failure to a WARN. The
nightly job would therefore have been **red on its first run**, entirely for reasons unrelated
to #552.

The pre-flight receipt does not cover this. Its OR-1 concerns the opposite direction — a ceiling
left loose when a ratio *falls* — and no other region touches the state of the markdown baseline
at the branch point. So the gap is `undeclared`: BUILD had no default it was entitled to take.

Neither horn is obviously right, which is why it was not taken silently. Shipping red-on-arrival
honors both ACs literally but trains readers to ignore the guard, defeating what AC-10 is for.
Refreshing the baseline lands the guard green but moves 26 rows that no AC asked to move, inside
a diff whose subject is shell measurement.

## Disposition followed

Paused and asked. The operator chose to **refresh the markdown baseline in this PR**, overriding
the recommendation to ship red and file a follow-up.

Carried out as follows:

- `--update-baseline` re-snapshotted both files; `.claude/prose-budget.baseline.tsv` moves by 40
  insertions / 38 deletions (2 new files, the rest re-measured word and char counts).
- `prose-budget.sh` now exits `0` on this tree: `0 fail(s), 20 warning(s)`. The 20 warnings are
  pre-existing narrative-`#NNN` flags, which are warnings by design and do not red the job.
- AC-8 in `docs/plans/second-shift-552-lean.md` was amended **before milestone 5** to scope its
  no-change guarantee to the markdown path's *behavior* — its format, its column-2 lookup, and
  all 17 pre-existing selftest cases — rather than to its row *values*.
- The refresh is called out as its own item in the PR body, so a reviewer sees it as a distinct
  change rather than as churn inside a shell-measurement diff.

No mechanism was added to keep the markdown baseline fresh; that remains as unowned after this
run as before it, and is the same class of gap OR-1 records for the shell path.
