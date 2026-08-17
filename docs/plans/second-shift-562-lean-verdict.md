# lean review verdict — #562

verdict=needs-work
run_id: review-562-2
session_id: eef472aa-37b9-44e7-b09c-ea2f08cbcb51
rounds: 2
pr: #573
reviewed_head: 09fc7bae8685419c7ce60b1fc8641293b25dcec4
reviewed_patch_id: 15bc6d3225819052ede27a9b223d350b00a4469a
inherited_patch_id: 7e6439cacd70eb5df0ec4f6996bdf78d07423aba
inherited_from_verdict: c8f1efed9c7d9192a78ec8f575e22a4bf55449e3
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 2. Range reviewed: `c8f1efe..09fc7ba` — the delta `lean-gate.sh delta 562` printed,
inheriting the coverage of patch `7e6439cacd70` (round 1's record). Nine files: the two fix
commits `813a275` (the `resolve_sibling()` extraction) and `09fc7ba` (the mutation pair-map row).
I read the round-1 findings first, and read wider than the range where the delta was misleading —
`resolve-sibling.sh` is new in the delta but its body is a move, so it was read against
`pipeline-doctor.sh` at the branch base.

Panel: 7 reviewers selected, 7 returned, **none dark** — security, performance, maintainability,
complexity, test-coverage, unit-test-mutation, scope-completeness. Scope Completeness Gate:
**PASS** (no findings). Four reviewers converged independently on the single blocker below, each
reproducing it against its own fabricated cache; I reproduced it separately before dispatching
them.

## Verdict: needs-work

Round 1's Blockers 2 and 3 are **genuinely discharged**, and I proved each by mutation rather than
by reading the claim. Blocker 1's headline remedy — reuse instead of a second ladder — was also
done, and done in the better of the two shapes round 1 offered. But Blocker 1's second half, the
**silently dropped middle rung**, is not fixed: the extraction preserves it for the caller round 1
raised it against, and five artifacts in this round now assert the opposite. That is the one
blocker, and all three `AC-n` remain satisfied.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — milestone 1 refuses a committed spec whose `## Decision Ledger` rows carry a provenance value outside the interviewing-baseline enum, **reusing** `ledger-lint.sh`, not a re-implementation | **satisfied** | Unchanged in substance from round 1 and re-verified at this head. `lean-gate.sh:2946-2957`: the gate shells out to `ledger-lint.sh`, whose `PROVENANCE_ENUM` stays the only carrier — no second copy of the enum anywhere in the branch. `(a4)` pins the refusal. The round-2 refactor moved only how the lint is *located*, not what it enforces. |
| AC-2 — a selftest case exercises the refusal with an invented-provenance fixture and the pass with a valid one | **satisfied** | `(a4)` (invented `issue-specified` → rc=1) and `(a5)` (all-enum-legal → rc=0), plus `(a6)`, `(a7)` and now `(a8)`. Strengthened this round: I confirmed `(a8)` is discriminating by mutation — narrowing the detector to `^(#{1,6}[[:space:]]+)[[:space:]]*decision ledger` leaves `(a1)`-`(a7)` all green and reds `(a8)` alone. |
| AC-3 — distinct from #517: a spec with no `## Decision Ledger` section at all is unaffected | **satisfied** | The conditional `grep -qiE` at `:2952` is the discriminator; `(a6)` pins it. Untouched by the round-2 delta. |

## Findings

| # | Finding | Class |
| --- | --- | --- |
| 1 | The extracted `resolve_sibling()`'s **own-version rung is dead for `lean-gate.sh`'s caller** — `myver` is derived from `$SCRIPT_DIR/..`, a one-hop assumption. The two callers now diverge on identical cache state, and five artifacts in this round assert that they do not | **blocker** |
| 2 | Round 1's warnings 4 and 5 are still open — carried forward, not re-charged | warning |

### Blocker 1 — the shared ladder is shared for two rungs of three

`resolve-sibling.sh:26`:

```
myver="$(basename "$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)")"
```

That line hardcodes "the caller's file sits exactly **one** directory under its own plugin-version
directory." It is true for `pipeline-doctor.sh` (`tools/`) and false for `lean-gate.sh`'s
`resolve_ledger_lint()` (`skills/build-lean/`, two levels down). `PLUGINS_DIR` *is* hop-adjusted by
the new caller (`dirname` × 3) and is correct; `SCRIPT_DIR` is passed through unadjusted and is
consumed inside the lib for arithmetic the lib's own header says stays with the caller.

**Reproduced, on the shipped file, at both callers' real depths.** One fabricated cache —
`dev-pipeline` at `7.0.0`, `intake-toolkit` present at both `7.0.0` and `9.0.0`, both carrying
`ledger-lint.sh` — driven through the two callers' verbatim prep lines:

```
caller A (lean-gate.sh shape,  skills/build-lean)  rung-2 myver = "skills"  -> resolved intake-toolkit/9.0.0   (rung 3)
caller B (pipeline-doctor.sh shape, tools)         rung-2 myver = "7.0.0"   -> resolved intake-toolkit/7.0.0   (rung 2)
```

Same function, same cache, different answer. For caller A the rung-2 candidate is
`<cacheroot>/intake-toolkit/skills/skills/plan-interview/tools/ledger-lint.sh`, which cannot exist,
so the miss is structural rather than situational — it falls through to rung 3 on every input.
That is the same two-rung behavior round 1 flagged in the pre-fix copy, now inside code that reads
as a restored three-rung ladder.

**Five places assert the parity that does not hold**, which is what lifts this above bookkeeping:

- `resolve-sibling.sh:5-14` — "the hop count from a caller's own file to its plugin root is what
  legitimately differs by depth … and that arithmetic stays the CALLER's". The header even names
  `PLUGIN_DIR` among the globals a caller computes; `pipeline-doctor.sh:20` does compute it, and
  the body then ignores it and re-derives the same thing from `SCRIPT_DIR`.
- `lean-gate.sh:2917-2922` — "it bears only on these two lines, not on the ladder itself."
- `pipeline-doctor-selftest.sh:678-681` — "Both callers' … call sites are exercised through THIS
  one function, so a single case here covers both."
- the spec's **D-6** — "No new fixture needed; the existing one now covers both callers."
- the spec's **Tests** section — "now covering both … callers by construction."

**And rung 2 has no killer at any depth.** `(rs)` injects `SCRIPT_DIR`/`PLUGINS_DIR` as environment
rather than deriving them, so it exercises the *function*, never either caller's prep lines. Its
fixture sets `SCRIPT_DIR=.../1.0.0/skills/run/tools` — a third depth, matching neither real caller —
and stages the sibling only at `9.0.0`/`10.0.0` while "this plugin" is `1.0.0`, so rung 2 misses in
the fixture too. The generic mutation tier cannot reach the line either: it carries no `-eq`, `-z `,
`&&`, `grep` or `${x:-y}`, so no operator in `mutation-operators.tsv` enumerates it. That part is
pre-existing rather than introduced — but the `(rs)` comment and the new pair-map row are this
round's, and they read as coverage of it.

**Runtime harm today is nil, and I want that on the record rather than implied.** Plugins here are
versioned independently — `dev-pipeline` 7.0.0 beside `intake-toolkit` 3.0.0 — so rung 2 never
fires for this pair under the current release scheme, for either caller. `design-sync-selftest.mjs`
says exactly this about its mirror ("it also misses in a real cache more often than not … which is
why rung 3 exists"). What is broken is a documented-load-bearing rung and five claims about it, not
a live resolution.

**Discharge — either is sufficient:**

1. **Fix it** (one line, and the header already describes this design): derive `myver` from a
   caller-supplied `PLUGIN_DIR` rather than from `$SCRIPT_DIR/..`, and have `resolve_ledger_lint()`
   compute `PLUGIN_DIR` alongside the `PLUGINS_DIR` it already computes. `pipeline-doctor.sh:20`
   supplies it today. If you take this path, give rung 2 the killer it has never had — `(rs)` with
   the sibling also staged at the harness's own version, driven at both callers' real depths — and
   the fixture stops being blind to the rung as well.
2. **Or correct the five claims**: say plainly that the ladder is shared for rungs 1 and 3, that
   rung 2 is caller-depth-coupled and inert for `lean-gate.sh`, and why that is acceptable. Then
   the manifest's "RUNG ORDER is the contract" language needs the same amendment, since this is a
   second bash consumer resolving on two rungs.

I am explicitly not asking for both. Option 1 is cheaper than the prose option 2 would need to be.

### Warning 2 — round 1's warnings 4 and 5, still open

Neither is re-charged, and neither is a blocker; noting them so the next round does not read their
absence as resolution. **Warning 4**: the delegated lint enforces six checks, not one, and 7 of the
12 committed lean specs with a ledger fail it — nothing in the spec or the gate's failure prefix
discloses that milestone 1's refusal surface widened past provenance. **Warning 5**:
`build-lean/SKILL.md` still never mentions the ledger's shape, so a build session meets the
constraint by failing milestone 1. **Warning 6 is fixed** — `:2926` now anchors on
`${BASH_SOURCE[0]}`, which also makes the resolver correct under `LEAN_GATE_LIB=1`.

## Strengths

- **Blocker 2 is discharged, and it is now machine-checkable rather than argued.** Round 1 could
  only report that nothing in the tree would notice if the version ordering broke. I flipped
  `sort -t. -k1,1nr -k2,2nr -k3,3nr` to the lexical `sort -r` in an isolated copy of the shipped
  tree: `pipeline-doctor-selftest.sh` goes 37/0 → 36/1 with `(rs)` naming the superseded `9.0.0`.
  Because `lean-gate.sh` now calls that same function, its rungs 1 and 3 inherit the guard.
  CI agrees independently — this round's `mutation-sweep-pr` swept the new file for real:
  `resolve-sibling.sh — applied=2 killed=2 survived=0`.
- **Blocker 3 is discharged by a case that genuinely kills the mutant round 1 named.** `(a8)` is
  not decorative: with the detector narrowed to its `#{1,6}` branch, `(a1)`-`(a7)` stay green and
  `(a8)` alone reds with `expected rc=1 …, got 0`. That is exactly the fail-open round 1 described,
  now closed from `lean-gate.sh`'s side without a cross-plugin lockstep row.
- **The remedy chosen for Blocker 1 was the better of the two offered, and it made the tree
  smaller.** Extracting rather than pinning removes a ladder site instead of registering one, and
  `pipeline-doctor.sh` shrank by 16 lines. The manifest was updated in the same diff — including
  the honest narrowing of its own residual paragraph — and the `.mjs` mirror's pointer was
  re-aimed, so the "keep the two ladders in step" instruction still names a file that exists.
- **The guard-accounting follow-through in `09fc7ba` is the right remedy, correctly argued.** A
  new sourced-never-executed file in `tools/` whose killer sits in the same directory under a
  different stem cannot be reached by the directory-scoped same-stem rule; a pair-map row is the
  answer, and an exclusions row would have falsely asserted no kill criterion exists. CLAUDE.md's
  "the rule is coverage, not naming" is cited correctly.
- **Mutation-ordinal hygiene is intact across a guard edit that could easily have broken it, and
  this round owns the check** — `lean-gate.sh` deferred to nightly again, and `pipeline-doctor.sh`
  had ~23 lines deleted from line 30, above most of its baselined sites. I enumerated all six
  operators' first-3 matched lines at `a8cd2b5`, `c8f1efe` and `09fc7ba`: identical source lines
  throughout for both guards (`pipeline-doctor.sh` shifts by −16 in line number only). CI confirms
  from the other direction — `pipeline-doctor.sh — applied=10 killed=2 survived=8`, exactly its
  eight baselined rows, green. **No re-baseline was owed**, and no `mutation-catalog.tsv` row or
  `lockstep-manifest.tsv` TSV row anchors into the moved block, so nothing needed re-anchoring.
- **The dynamic-scope split is genuinely correct where it is used, and the one shellcheck
  consequence was handled at the site rather than globally.** `SC2034` on the caller's
  `PLUGINS_DIR` is unavoidable — shellcheck cannot trace a `local` across a `source` boundary — and
  it is disabled inline with the reason, not added to the repo's `-e` list.
- Clean on both CI axes and locally: `lint-and-selftests` and `selftests (macos, bash 3.2)` both
  green at this head; `shellcheck -e SC1091,SC2015,SC2181` silent at 0.11.0 (stricter than CI's
  0.9.0) over all five changed shell files, and `bash 3.2 -n` parses them. The spec now passes the
  gate it adds — `ledger-lint.sh` reports `7 ledger row(s)` / `OK` on it.

## Suppressed / not upheld

- Unquoted `$(ls -1 …)` word-splitting over version dirs (security, 40). Verbatim carry-over with
  its pre-existing `SC2012` waiver; dirs are locally-created `X.Y.Z`. Not introduced here.
- A failed `cd .../../tools` collapsing the source path to `/resolve-sibling.sh` (security, 35).
  Availability, not security — and it fails closed: `set -uo pipefail` has no `-e`, so the source
  merely errors, `resolve_sibling` stays undefined, `resolve_ledger_lint` returns 127 and the gate
  `envfail`s rather than skipping the check. I confirmed the fail-closed path.
- `(a8)` flagged as possibly redundant with `(a4)` (unit-test-mutation, nit, 88 — raised only to
  say it is *not* redundant). Agreed, and the mutation probe above settles it.
- The `#394` comment describing milestone 1's observe pass as "no subprocess beyond grep/awk" is
  still stale now that the ledger lint shells out ahead of it. Carried from round 1 as noted, not
  charged: read-only, cheap, and no production caller runs milestone 1 under `LEAN_GATE_OBSERVE=1`.

## CI

`pr-gates` red is the expected state and not a finding — the failing arm names its own reason:
`verdict record … reads 'verdict=needs-work', not 'verdict=approve' — freshness is undefined for a
non-approve record`, i.e. it is reading round 1's committed record. Every other check is green at
`09fc7ba`: `lint-and-selftests`, `selftests (macos, bash 3.2)`, and `mutation-sweep-pr` — which
this round, unlike round 1, computed 13 real verdicts rather than deferring everything.

## Design fidelity

`not-applicable`. The spec's `## Design` section carries the explicit disarm (`Design: none — a
shell-script gate change with no UI surface; design.provider is unset in this repo's config`), and
I verified the disarm rather than taking it: `.design` is absent from
`.claude/second-shift.config.json`, and no changed path touches a web-component surface. No handoff
link and no `| RS-n |` table exist to score, so step 5b does not apply and there is no
under-declared-table judgment to make.
