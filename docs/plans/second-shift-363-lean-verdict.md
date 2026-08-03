# lean review verdict — #363

verdict=approve
run_id: review-363-1
session_id: 204fab2a-acd0-4728-91bc-dcb3ec0a19b4
rounds: 1
pr: #367
reviewed_head: 45f32aa069d381b5e71ea09ee88859d99ad591ae

Reviewed `main..lean/second-shift-363` at head `45f32aa`, against
`docs/plans/second-shift-363-lean.md` as the definition of done.

## Per-AC scoring

| AC | Verdict | Evidence |
| --- | --- | --- |
| AC-1 | satisfied | `check-lean-chain-selftest.sh` (R1) key-less record refused, (R2) earlier declared head refused *while its own commit IS the PR head*, (R3) matching head passes and the gate names the arm, (R4) unresolvable head refused rather than compared against nothing. Suite run: all green. |
| AC-2 | satisfied | `lean-gate-selftest.sh` (p5) asserts the writer stamps a git-resolved head against a value the suite derived independently; (p7) feeds that record to milestone 4; (u1)/(u2)/(u3)/(u4) cover missing key / declared-stale / absent commit / match. (u2) is attributable — the record is committed last, so the inferred arm is green and only the declared message `states it reviewed` can red it. Suite run: all green. |
| AC-3 | satisfied | `lean-reconcile-selftest.sh` (L1) key-less is a reconciliation failure, (L2) a record whose commit does not descend from the head it names fails, (L3) the coherent case reconciles and says so. The suite gained a base commit so the descent check is not asserted against a root commit. Suite run: all green. |
| AC-4 | satisfied | `scenario-liveness-selftest.sh` `(lean-declared)` leg composes row 2 of the spec's table: record committed last (inferred arm green), naming an earlier head, rc=1; re-declared round rc=0; plus a key-less leg at rc=1. Leg 1 and the jira leg were re-shaped so the spec commits on its own — folding it into the verdict commit is a shape `review-lean` step 6 forbids. Green in the full sweep. |
| AC-5 | satisfied | Verified independently of the spec's prose: `tools/mutation-baseline.tsv` carries 4 / 6 / 7 rows for `lean-gate.sh` / `lean-reconcile.sh` / `check-lean-chain.sh` — the 17 the evidence section claims — and `tools/mutation-catalog.tsv` has no row referencing any of the three, so there is nothing to re-anchor. CI's diff-scoped sweep step (`ci.yml:112`) passed on this head inside `lint-and-selftests`. The evidence section states the `K_BUDGET=2` limit plainly instead of reading as a coverage claim. |
| AC-6 | satisfied | `review-lean/SKILL.md` step 5 requires the write to run from the PR-head checkout, step 6 states the record is HEAD-BOUND across all three readers, and the closing rule names rebase, force-push and docs-only commits as voiding it. `run-lean/SKILL.md` step 8 says the same from the build side (`whose reviewed_head is the current head`) and its rule bullet adds rebase/force-push. The file is exactly 60 lines — the cap holds. |
| AC-7 | satisfied (by its letter) | The `scripts/lockstep-manifest.tsv` DROPPED entry names `reviewed_head:` and all three readers, and commit `5247084` carries a `Changelog:` trailer with a real `Migration:` line covering key-less in-flight records. Three accuracy defects in the entry's supporting prose are reported below; none of them is what AC-7 asks for. |

## Findings

No blockers.

Three factual errors, all inside the single comment paragraph added to
`scripts/lockstep-manifest.tsv`. None changes behavior, none fails an AC, and each
coupling they mis-describe is in fact covered by a real case in the same suites — but
this is the register whose stated job is to keep a dropped coupling's reasoning visible,
so wrong reasoning in it is worth a follow-up.

1. **A citation to a case that does not exist.** The entry reads
   `lean-reconcile-selftest.sh (J3)/(K1)`. There is no `(K1)` in that suite — `(K)` is
   the retired-build-ledger anchor, and the key-less-`reviewed_head` refusal this
   sentence means is `(L1)`.

2. **A mis-attribution of what a case does.** `lean-gate-selftest.sh (u3) drives
   writer-to-reader end to end` — `(u3)` never invokes the writer; it hand-writes a
   record with a zero SHA via `write_review_verdict` and exercises the reader alone. The
   writer-to-reader end-to-end pair is `(p5)`+`(p7)`.

3. **A claim about reader behavior that is false.** The entry justifies the tighter
   coupling with "a writer that stamped, say, a short sha would still extract cleanly
   everywhere and then fail every comparison". Checked directly on this branch: git
   resolves an abbreviated SHA at both `cat-file -e <short>^{commit}` and
   `git diff --name-only <short> HEAD`, so a short SHA passes every comparison rather
   than failing it. The paragraph's spine — the value is a git object, so its readers
   resolve and compare rather than merely extract — is sound; only this illustration is
   not.

## Observation, not a finding against this diff

No reader validates the *shape* of `reviewed_head`, though D-1 specifies a full 40-char
SHA. The extractor charset `[A-Za-z0-9._-]+` admits `HEAD`, and a record carrying
`reviewed_head: HEAD` would satisfy all three readers vacuously (`git diff HEAD HEAD` is
empty; `merge-base --is-ancestor HEAD <record-commit>` holds when the record is the last
commit). This is unreachable from the writer, which always stamps `git rev-parse HEAD`,
and hand-writing the record is already forbidden — so it sits exactly at the declared
"tamper-evidence, not proof" altitude and is out of scope here. It is, however, the check
that would make finding 3's sentence true, and it is worth its own issue rather than a
reword.

## Verification run for this review

- `lean-gate-selftest.sh`, `lean-reconcile-selftest.sh`, `check-lean-chain-selftest.sh` —
  all green individually.
- Full selftest sweep, `-P 4`, **without** `SKIP_STRESS` — exit 0.
- `shellcheck -e SC1091,SC2015,SC2181` over every `*.sh` — clean.
- `jq empty` over every `*.json` — clean.
- CI on `45f32aa`: `lint-and-selftests` and `selftests (macos, bash 3.2)` both pass.
  `pr-gates` fails on `no committed verdict record` only, which is the pre-review state
  this record clears.
- Spot-checked the hazard this branch's own history names: all three `--help` ranges
  (`lean-gate.sh 2,75p`, `lean-reconcile.sh 2,56p`, `check-lean-chain.sh 2,83p`) end
  exactly on their last header comment line, so none silently truncates.

## On the design

The two-arm argument holds under inspection, and the non-subsumption is real in both
directions. The inferred arm cannot see a record honestly committed on top of a head it
never read; the declared arm cannot see a record naming a head *later* than the one it
sits on, and is the only one that survives a rebase, since CI's `fetch-depth: 0` does not
fetch a commit reachable from no ref. Deriving the value from `git rev-parse HEAD` rather
than a flag is the right call: running `verdict` from the main checkout writes main's
head, which is an ancestor of the branch and therefore resolves — and then reds loudly on
the tree comparison instead of failing open.
