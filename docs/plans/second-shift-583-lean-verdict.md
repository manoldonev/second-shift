# lean review verdict — #583

verdict=approve
run_id: review-583-1
session_id: e45b5499-1922-4038-9057-f15d34a8158c
rounds: 1
pr: #593
reviewed_head: 37bbfbd9d90ede3503c71fa4080ad7f0443b2ebd
reviewed_patch_id: 1decd12550cd77340fef38cb1ddf98d290695b5a
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

## Verdict: approve — round 1

Round 1 covered the whole branch diff (`ea299d6..37bbfbd`, 8 files, +960/−197): the content-keying
implementation in `tools/mutation-sweep.sh`, its companion suite, the 108-row baseline migration,
and the four contract surfaces. Six reviewers ran (security, performance, maintainability,
complexity, test-coverage, scope-completeness); all six returned `approve` with zero findings and
none went dark. Every load-bearing claim below was **reproduced independently of the suite** —
against production `tools/mutation-sweep.sh` on purpose-built fixtures and against the real tree —
rather than read off the PR body.

### Independent verification (not inherited from the build's evidence)

| Check | How | Result |
| --- | --- | --- |
| Migration is 1:1 and derivable | Re-ran `--emit-site-keys` on the branch tree (2,748 sites, 65 guards), joined each **old** `guard::op::ordinal` to its emitted key, diffed the derived set against the committed baseline | **108/108 exact**, zero unresolved, zero derived-vs-committed differences |
| Every migrated row still names a live site | `comm -23` of the 108 committed generic ids against all 2,748 enumerated sids | **zero** orphans |
| Row set preserved, not re-derived | data rows before/after; generic before/after; note text of each row under the derived mapping | **136 → 136**, generic **108 → 108**, **93 of 108 notes byte-identical** |
| `catalog::` rows untouched | `git show ea299d6:…\|grep '^catalog::'\|sort` vs head | **byte-identical as a set** (28 rows) |
| No collision on the real tree | all 2,748 emitted keys grouped by `guard+operator` | **no duplicate** at the shipped 12-hex width |
| Operator regexes unchanged | `git diff` of `tools/mutation-operators.tsv` | prose only — so the ordinal→key join above is a valid basis |

### AC scoring — all satisfied

| AC | Verdict | Evidence |
| --- | --- | --- |
| **AC-1** insert above re-keys nothing | **satisfied** | Reproduced: 3-site fixture, one killable line inserted above all three → `f2f25aa14ec4 / 2a2c6954719a / d21a35b95aae` **unchanged**, only the new site is new. Case `(an)` green (3/4/3, differential). |
| **AC-2** move + re-indent re-keys nothing | **satisfied** | Reproduced: `gamma`'s block moved to the top of the file and re-indented 2 → 6 spaces; its key stays `d21a35b95aae` while its **ordinal** goes 3 → 1. Case `(ao)` green. |
| **AC-3** identical lines get distinct ids | **satisfied** | Reproduced: `alpha` and `beta` normalize identically (differ only in indentation) and key to `f2f25aa14ec4` / `2a2c6954719a`; deleting `alpha` moves `beta` onto `f2f25aa14ec4` and leaves `gamma` alone — exactly "hands its key to the second, and nothing else". Case `(ap)` green. |
| **AC-4** migrated, not re-seeded | **satisfied** | The 108-row mapping re-derived from `--emit-site-keys` matches the committed baseline exactly (table above); PR body carries **108** mapping rows; **136 rows before and after**. |
| **AC-5** catalog rows untouched | **satisfied** | 28 `catalog::` rows byte-identical as a set. |
| **AC-6** collision reds by name, over ALL sites | **satisfied** | Reproduced on a 20-arm fixture at `k=2`: `MUTATION_SWEEP_SITE_KEY_CMP_HEX=1` → `rc=1`, `RED: site-key collision: two enumerated sites of fail-open on g.sh both key to 1`, `colliding lines: 4 6 12`. The k=2 window is lines 3–4, so **lines 6 and 12 are sites no sid was ever emitted for** — the check demonstrably ranges over the enumerated list, not the emitted one. Control at the shipped 12-hex width: `rc=0`, no collision. |
| **AC-7** no sha binary reds, lazily | **satisfied** | Case `(ar)` green in four parts **with its control first** (`ar1`: pruned PATH + one sha binary runs a clean sweep — so `ar2`'s red is attributable to the missing binary, not to a too-thin fixture); `ar3`/`ar4` show nothing-to-sweep PR mode and `--mode merge` staying green. Code reading confirms `require_sha` fires at the first key computation, not at `SHA_KIND` resolution, and that merge/PR-empty exit before the guard loop. |
| **AC-8** keying mismatch reds in any mode | **satisfied** | Reproduced in **both** lanes on a real fixture: unkeyed baseline → `rc=1`, `RED: baseline-keying-mismatch: … declares '<no keying header>' …  Survivors NOT compared.` with **no** `now KILLED` and **no** `baseline-absent survivor` line in either the advisory or the enforcing run. A wrong *value* (`# keying: ordinal-v0`) reds naming what the file declares. Case `(as3)` covers the shard-disagreement merge check. |
| **AC-9** contract surfaces updated | **satisfied** | All five named surfaces updated (`CLAUDE.md` — compound sentence split, catalog-anchor half kept; `tools/mutation-operators.tsv`; `docs/testing.md` — three sites plus three new runbook entries; `tools/mutation-catalog.tsv`; `tools/mutation-baseline.tsv` header + footer). Repo-wide grep for the retired coupling finds **no live surface still asserting it**: remaining hits are archived `docs/plans/*` run records (point-in-time artifacts, correctly left alone) and row notes narrating history, each reconciled with #583 where it mattered. |
| **AC-10** differential, no mirror harness | **satisfied** | `sid_for()` derives ids by invoking production `--emit-site-keys`; no sha is computed anywhere in the suite. Only two key-shaped literals remain (`gone/removed.sh`, the fleet fixture's `guard2.sh`) — both name guards with **no matching site**, which is the case the AC explicitly permits. The suite's TSV lint was also tightened to reject a surviving positional id (`want 12 hex`). |

### Corroborating evidence, checked rather than accepted

- **The dispatched full sweep transfers to the head.** Run `32194565969` on `69cdc1e`: `event=workflow_dispatch`, **10/10 shards + merge green**, and shard 1 logs `enforcing mode: event='workflow_dispatch', baseline present=yes` — so it compared live verdicts against the committed content-keyed baseline and would have redded on an absent survivor. `git diff --name-only 69cdc1e..37bbfbd` returns exactly `tools/mutation-sweep-selftest.sh`, and `--stat` over `mutation-sweep.sh`, `mutation-baseline.tsv`, `mutation-operators.tsv`, `mutation-exclusions.tsv`, `mutation-catalog.tsv`, `mutation-pair-map.tsv` is **empty** — the sweep's subject is byte-identical, so the verdict transfers.
- **Companion suite, run here:** `bash tools/mutation-sweep-selftest.sh` → `EXIT=0`, `all cases passed`, including `(an)`–`(as)` and the tightened TSV lint.
- **CI on the head SHA `37bbfbd`:** `lint-and-selftests` ✅, `mutation-sweep-pr` ✅, `selftests (macos, bash 3.2)` ✅. `pr-gates` ❌ on **`no committed verdict record`** and nothing else — the one arm that cannot be green before this record exists.
- **Design:** `Design: none — harness plumbing`, and the repo's config declares no `design.provider`. The disarm is justified; fidelity scores **not-applicable**.

### Strengths

- **The negative controls are the real work.** `(aq1)` at the shipped width, `(ar1)`'s pruned-PATH-plus-one-binary control, and `(as)`'s both-lanes loop each make the corresponding red *attributable*. `37bbfbd` is the model case: the collision assertion was rewritten from "a collision was reported" to "the reported group names a line past the budget" after the first version was shown to pass by ordinal coincidence on the `bad01..bad20` labels.
- **The index-equivalence-class decision is argued from measurement, not taste** — 119 normalization-identical groups against 95 byte-identical ones, so indexing over the byte-identical class would collide 24 groups and red `main`. Reproduced in miniature by `(ap)` and by my own fixture.
- **The env seam is honestly bounded.** `MUTATION_SWEEP_SITE_KEY_CMP_HEX` narrows the *comparison* only; `${key:0:12}` is unconditional, so a leaked value can manufacture a loud false collision but can never quietly re-key a baseline. Confirmed by reading both call sites.
- **The migration preserved curated rationale rather than flattening it** — 93 of 108 notes are byte-identical, and the 15 rewrites keep their reasoning while dropping the now-false positional claim.

### Warnings (non-blocking; neither costs a round)

1. **PR body over-counts the rewritten notes.** The AC-9 evidence cell says "21 rows' positional prose rewritten with their rationale kept". The actual count is **15**. (22 old notes carried positional language; 11 still do — all as historical narration of *why a site sits inside the positional budget*, which remains true, or explicitly reconciled with #583. So the spec's criterion — rewrite "where it becomes false" — is met; only the number in the body is wrong.) Body-only, no commit required.
2. **`SHA_KIND` preference flip is outside the spec's letter.** `sha256sum` now precedes `shasum`. It is a direct consequence of this change (hashing moves from once-per-cache-probe to once-per-site, 2,748 sites here) and is documented in-code with the measurement (~45s → ~10s). Both binaries emit the same sha256 digest, so cache keys and `SELF_SHA` are unaffected and no cache is invalidated. Called out for the record, not as a defect.

### Suppressed (below threshold)

- `sed -E -e "$opflip"` applies operator expressions from a repo-controlled TSV — pre-existing pattern, not an injection surface (confidence 40).
- `mktemp` REPL/sandbox temp files in the mutated loop are unchanged pre-existing behavior (confidence 35).
- `require_sha`'s detail line says "Nothing was enumerated", which is true at the first key but not literally true if an earlier guard had already enumerated. Cosmetic.

### Verdicts

| Reviewer | Verdict | Findings | Confidence Range |
| --- | --- | --- | --- |
| Scope Completeness | Pass | 0 | — |
| Security | Pass | 0 | — |
| Performance | Pass | 0 | — |
| Complexity | Pass | 0 | — |
| Maintainability | Pass | 0 | — |
| Test Coverage | Pass | 0 | — |

`a11y-reviewer` and the design-fidelity dimension were **not routed**: no changed path matches
`stageParams.webComponentGlobs` (key absent; resolved default `apps/web/**/*.{tsx,jsx}`) — this is
a shell/docs diff. Not a coverage gap.

**Ready to merge?** Yes — `approve`. Ten of ten ACs satisfied, every one of them reproduced against
production code rather than scored from the PR body; the only red on the head is the missing verdict
record this document supplies.
