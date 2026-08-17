# lean review verdict — #562

verdict=needs-work
run_id: review-562-1
session_id: ca277839-f457-438e-9787-52f3c98e1129
rounds: 1
pr: #573
reviewed_head: 0c09b2150db37abdedd1318aaf70d26270c53b69
reviewed_patch_id: 7e6439cacd70eb5df0ec4f6996bdf78d07423aba
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

Round 1. Range reviewed: the whole branch diff (`a8cd2b5..0c09b21`) — `lean-gate.sh delta 562`
reported FULL range, nothing verifiable to inherit. Three files, +140/-1: the committed spec,
`lean-gate.sh` (+46), `lean-gate-selftest.sh` (+33).

Panel: 7 reviewers selected, 7 returned, **none dark** — security, performance,
maintainability, complexity, test-coverage, unit-test-mutation, scope-completeness. Scope
Completeness Gate: **PASS** (no findings).

## Verdict: needs-work

All three `AC-n` are **satisfied**. The blockers below are obligations the diff *incurs* rather
than acceptance criteria it misses: two named repo conventions the change triggers and does not
discharge, and one coverage gap on the single new code path that fails open.

## Per-AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — milestone 1 refuses a committed spec whose `## Decision Ledger` rows carry a provenance value outside the interviewing-baseline enum, **reusing** `ledger-lint.sh`, not a re-implementation | **satisfied** | `lean-gate.sh:2962-2969`. No copy of the enum is added — the gate shells out to `ledger-lint.sh`, whose `PROVENANCE_ENUM` stays the only carrier. Reproduced live: running the lint over this repo's own corpus refuses `second-shift-83-lean.md` (`provenance 'issue-specified' not in {…}`), `second-shift-447-lean.md` (`user-directed`) and `second-shift-306-lean.md` (`project convention`) — the T6 datapoint the ticket was filed for. `(a4)` pins the refusal. |
| AC-2 — a selftest case exercises the refusal with an invented-provenance fixture and the pass with a valid one | **satisfied** | `(a4)` (invented `issue-specified` → rc=1, asserting both `fails ledger-lint` and the specific `provenance 'issue-specified' not in` text) and `(a5)` (all-enum-legal → rc=0). Both are discriminating: I confirmed a `-ne 0` → `-eq 0` flip at `:2965` and a `detector` flip on `:2962` each fail `(a4)`. |
| AC-3 — distinct from #517: a spec with no `## Decision Ledger` section at all is unaffected | **satisfied** | The conditional `grep -qiE` at `:2962` is the discriminator and `(a6)` pins it (no-section spec → rc=0). A mutant making the lint unconditional fails `(a6)`, because `ledger-lint.sh`'s own check 1 would then violate on the missing section. |

## Findings

| # | Finding | Class |
| --- | --- | --- |
| 1 | `resolve_ledger_lint()` is a further site of the cross-plugin sibling-resolution ladder whose manifest entry names exactly this trigger, and the diff discharges it nowhere | **blocker** |
| 2 | The cache rung — the only genuinely new logic in the diff — has no killer anywhere in the tree, and the PR-lane sweep computed zero verdicts | **blocker** |
| 3 | The section detector is a byte-identical second copy of `ledger-lint.sh:121` with no guard on either the duplication or its bold-heading branch; drift there fails OPEN | **blocker** |
| 4 | Delegating to `ledger-lint.sh` imports five refusal grounds beyond provenance validity; 7 of this repo's 12 committed lean specs with a ledger fail, one of them not on provenance at all | warning |
| 5 | The producer-side instruction never mentions the Decision Ledger's shape, so the first encounter with the new refusal costs a milestone-1 fix attempt | warning |
| 6 | `$0` rather than `BASH_SOURCE[0]` for the self-anchor, in a file that uses the safer idiom two lines' worth of precedent away | warning |

### Blocker 1 — a further ladder site, with the manifest's own revisit trigger left undischarged

`scripts/lockstep-manifest.tsv:549-602` is the register of record for this exact class: the
"cross-plugin sibling-resolution ladder (#419)" entry enumerates every prior copy, states that
**"The RUNG ORDER is the contract: the last rung is what hits in a real install"**, and closes
with

> `Revisit if a SIXTH site grows the ladder, or if any FURTHER pair converges on identical hop constants — such a pair is byte-anchorable and should be pinned, as the row below pins the first one that did.`

Pre-diff the tree already carries six ladder implementations (`doctor-selftest.sh:43` and `:60`,
`check-model-tiers.sh:122`, `preflight-selftest.sh:64`, `pipeline-doctor.sh:36`,
`design-sync-selftest.mjs`), plus the enumeration variant in `check-emit-deadline.sh` that the
entry accounts for separately. `resolve_ledger_lint()` is another. The diff touches
`lockstep-manifest.tsv` not at all — neither a pinned row nor a DROPPED entry with reasoning,
which CLAUDE.md names as the required form when a coupling is real but not byte-anchorable.

Two facts make this more than bookkeeping:

**(a) It IS byte-anchorable, which is precisely the condition the trigger says "should be
pinned."** The new cache rung is not a re-derivation of the canonical block — it is a verbatim
lift of it. Compare `lean-gate.sh:2935-2938` against `pipeline-doctor.sh:46-49`: the same
`sort -t. -k1,1nr -k2,2nr -k3,3nr`, and the *same shellcheck directive down to the comment text*
(`# shellcheck disable=SC2012  # version dirs are alphanumeric (X.Y.Z); ls is safe and 3.2-portable here`).
The differing part is the hop arithmetic on the monorepo rung, which is exactly what marker
delimiters exist to exclude — `pipeline-doctor.sh` already carries `# >>> resolve-sibling` /
`# <<< resolve-sibling` markers around its copy.

**(b) D-4's justification for a new copy does not survive contact with the nearest precedent.**
D-4 argues the ladder had to be re-derived because "this file sits three directories under its
plugin root … so the hop counts legitimately differ," citing `check-model-tiers.sh`. But the
nearest existing implementation is not `check-model-tiers.sh` in another plugin — it is
`resolve_sibling()` in **this same plugin**, at `pipeline-doctor.sh:36`, which is already
parameterized (`$1` = sibling name, `$2` = path under it), already has three consumers, and
already resolves **this exact target**: `pipeline-doctor.sh:418` calls
`resolve_sibling intake-toolkit skills/plan-interview/tools/ledger-lint-selftest.sh`. Its hop
count is derived from *its own* `SCRIPT_DIR`/`PLUGINS_DIR`, not the caller's, so the differing-depth
argument does not block reuse: extracted into a small sourced lib at its current depth, the hop
constants stay correct for a caller at any depth. `lean-gate.sh` already does exactly that
pattern for a shared resolver — it sources `branch-prefix.sh` at `:630` rather than hand-rolling
a copy. D-4 never considers this option, so the ledger's recorded decision rests on a comparison
that omits the one candidate that would have changed it.

The new copy also silently drops the canonical ladder's **middle rung** (same-version sibling in
the cache), reducing three rungs to two. In fairness this is behaviorally inert for this pair
under the current release scheme — `dev-pipeline` is at 7.0.0 and `intake-toolkit` at 3.0.0, so a
same-version candidate never exists — but the entry calls rung order the contract, so a two-rung
derivation of a three-rung contract is the kind of divergence it exists to record.

**Discharge:** either reuse (extract `resolve_sibling` into a sourced lib and call it, deleting
the new copy), or keep the copy and add the manifest record — a `verbatim` row over
marker-delimited cache rungs if you pin it, or a DROPPED entry stating why the whole block cannot
be compared and what guards it instead. Either satisfies this; asserting the rationale only in
the spec's D-4 does not, because the manifest is where the next person looks.

### Blocker 2 — the cache rung has no killer anywhere in the tree

The version-ordering loop is the only genuinely new logic in the diff, and nothing can currently
fail on it.

**Proved unreachable from the load-bearing suite.** `lean-gate-selftest.sh` invokes `$GATE` at its
real in-repo path, where the first (monorepo) candidate
`plugins/intake-toolkit/skills/plan-interview/tools/ledger-lint.sh` exists — so
`resolve_ledger_lint()` returns at `:2930` and the loop at `:2936` never executes. `(a4)`-`(a7)`
are the only cases that call it, so the rung is dead code under the entire suite. I confirmed this
by mutation as well as by construction: flipping `sort -t. -k1,1nr -k2,2nr -k3,3nr` to the lexical
`sort -r` in an isolated copy changed the suite's result not at all.

**Not covered by the nightly cross-layout run either.** `install-topology-selftest.sh` stages
exactly one version dir per plugin (`mkdir -p "$CACHE/$name/$version"`), so the loop has a single
candidate there and cannot distinguish a descending per-key sort from a lexical one.

**And the PR-lane mutation sweep computed zero verdicts on this diff**, so its green is not
evidence:

```
[mutation-sweep] defer plugins/dev-pipeline/skills/build-lean/lean-gate.sh -> nightly: slow suite (147s)
[mutation-sweep] nothing left to sweep after deferral.
lean-gate.sh  deferred-to-nightly  …  0  0  0
[mutation-sweep] timing: 1s wall — 0 verdict(s) computed
```

Nor will the nightly reach the new sites: `K_BUDGET` defaults to 2, and every site the diff adds
sits at line 2913+, well past ordinal 2 for all six operators.

This matters because the repo has already been bitten here and already built the fix.
`pipeline-doctor-selftest.sh:672-699`'s `(rs)` case exists for exactly this rung on the canonical
copy, and its comment says why nothing weaker works:

> `9.0.0 vs 10.0.0 is the whole point of those numbers. ls -1 | sort -r is lexical and puts 9.0.0 first, so the loop's first hit was the SUPERSEDED sibling. Any pair below 10 agrees under both orderings and cannot tell them apart.`

Both installed plugins are below 10 today, which is why every layout available to the suites is
blind to the defect. The new copy is *correct* — I drove it from a staged cache with siblings
2.9.0 and 10.0.0 and it selected 10.0.0, resolved under a relative `$0`, and returned 1 (→
`envfail`, matching D-5) when `intake-toolkit` was absent. The finding is that nothing in the
tree would notice if it stopped being correct.

**Discharge:** one case using `(rs)`'s technique — marker-delimit `resolve_ledger_lint()`, lift it
by its sentinels, and drive it against a fabricated two-version cache where the pair straddles 10.
That covers the ordering and the total-failure/`envfail` rung in the same fixture. It also
collapses with Blocker 1's reuse path: reusing `resolve_sibling` inherits `(rs)` and leaves nothing
new to guard.

### Blocker 3 — the section detector is an unguarded second copy, and drift fails open

`lean-gate.sh:2962`'s conditional is byte-identical to `ledger-lint.sh:121`'s own check-1
detector:

```
grep -qiE '^(#{1,6}[[:space:]]+|\*\*)[[:space:]]*decision ledger'
```

That identity is load-bearing, not incidental: the gate's conditional decides whether to *run* the
lint, and the lint's check 1 decides whether it *found* a section. If the two ever disagree, a
spec whose ledger matches the lint's detector but not the gate's is skipped silently — which is
#562's own bug reintroduced by drift. There is no lockstep row for this pair (I checked; the
manifest's ledger-related entries cover the receipt vocabulary and the provenance enum, not the
detector), and nothing behavioral pins it either.

The `\*\*` alternative makes it concrete. `intake-interviewer/SKILL.md:226` documents the bold
`**Decision Ledger**` form as the planning artifact the interview emits, so it is a shape a
committed spec can plausibly carry — but all four new cases use `## Decision Ledger`, so a mutant
narrowing the regex to `^(#{1,6}[[:space:]]+)[[:space:]]*decision ledger` **survives every suite**
while silently skipping provenance validation on that form. Fail-open, in the guard whose whole
purpose is to close a fail-open.

**Discharge:** one case committing a bold-form ledger with an invented provenance and asserting
the refusal. That kills the mutant and turns the gate/lint agreement into a checked fact from
`lean-gate.sh`'s side — cheaper than a cross-plugin `verbatim` row, and it lands in the tier map's
first row rather than needing a manifest entry at all.

### Warning 4 — the imported contract refuses on more grounds than AC-1 scopes

`bash ledger-lint.sh <spec>` is not a provenance check; it is six checks. Beyond the enum it
enforces row arity, a non-empty Decision cell, a non-empty Resolution cell, an `https://` citation
on any `ticket-sourced` row, unique `D-n` ids, and rows-or-the-explicit-empty-form. AC-1 mandates
reuse, so importing the whole contract is the *correct* consequence of the AC — but neither AC-1
nor the ledger discloses that milestone 1's refusal surface widened this far, and milestone 1
charges the fix budget with a hard stop on the 4th red.

I ran the lint over the corpus it will now govern. Of the 12 committed `second-shift-*-lean.md`
specs carrying a ledger section, **7 fail**. Most are the intended catch (`issue-specified`,
`user-directed`, `project convention`, `issue body, …` — genuinely invented values). Two other
classes are worth knowing about before the next run meets them:

- **Annotated legal values.** `codebase-derived (docs/extending.md §3.2's closed taxonomy)`,
  `codebase-derived, confirmed at scripts/lockstep-manifest.tsv`, `codebase-derived (schema field
  description)`. The value is in the enum; the citation appended to it is not, because the match is
  anchored `^(enum)$`. Refusing these is consistent with the canonical contract, so this is not a
  defect — but it is the dominant shape in the corpus and the message reads as if the author
  invented a value.
- **A pipe in a Resolution cell reports as a malformed row.** `second-shift-83-lean.md`'s D-5
  fails with `malformed ledger row (expected 4 columns: ID | Decision | Resolution | Provenance)`
  on a row that visually has four columns, because `ledger-lint.sh` masks only escaped `\|` and
  that cell carries a bare pipe-literal. Nothing about provenance is wrong there. The row is also
  broken markdown, so the refusal is defensible — but a build agent reading that message on a
  4-column row can burn attempts before finding the cause.

No code change is required. A sentence in the spec (or the gate's failure prefix) naming that the
delegated lint enforces the whole ledger shape, not just the provenance cell, would keep the next
encounter from reading as a bug.

### Warning 5 — the producer surface never mentions the ledger's shape

`build-lean/SKILL.md:22` is the instruction to the session that writes the artifact milestone 1
gates: "Write the spec/AC file at that path, ≥ 1 numbered `AC-n`." It says nothing about a
Decision Ledger, and no producer-facing doc in the lean lane states the enum constraint on a lean
spec's ledger (the `## Design` section has `docs/live-render.md`; this has no equivalent). So a
build session learns the constraint by failing milestone 1. `SKILL.md:41` makes doc updates
AC-scoped and this spec carries no doc `AC-n`, so the gap is at least a consistent one — but it is
the cheapest place to spend a line, and the 60-line SKILL cap does not forbid amending an existing
bullet.

### Warning 6 — `$0` where the file already prefers `BASH_SOURCE[0]`

`:2927` anchors on `$0`; `:630` and `:670` in the same file use
`$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)`. Under `LEAN_GATE_LIB=1 . lean-gate.sh` the two
diverge — `$0` becomes the *sourcing* script, so the resolver would anchor on the wrong tree.
Latent today, and I checked why: library mode returns at `:5001` before the subcommand dispatch,
and the only library-mode consumers (`lean-gate-selftest.sh:4274`, `:4401`) call a table helper,
not `cmd_1`. `:2417`'s `claim` helper uses `$0` too, so there is same-file precedent for the
weaker idiom. Not worth a round on its own; worth changing while the block is being touched for
the blockers above.

## Strengths

- **AC-1's "not a re-implementation" is honored exactly, and it is the manifest-aligned choice.**
  `lockstep-manifest.tsv:34-40` records that the provenance enum's *second* carrier was deleted in
  #348 and that `ledger-lint.sh` is now the only one, with the instruction "Re-file a row the
  moment a second carrier appears." Delegating rather than copying keeps that one-carrier property
  intact and adds no row to re-file. This is the right shape for the change and the reason it is
  worth having.
- **The conditional-on-presence design is the correct #517 discriminator**, argued in D-2 and
  pinned by `(a6)` — and the detector chosen is the same one `ledger-lint.sh` uses for its own
  section check, so the gate and the lint agree on what "has a ledger" means (see Blocker 3 for the
  part of that agreement that needs a guard).
- **Fail-closed, argued against the right counter-precedent.** D-5 reaches `envfail` (rc=2, no fix
  budget) and explains why the `exitplan-ledger-gate.sh` hook's fail-open posture is a different
  consumer's answer rather than a contradiction. I confirmed the behavior: with `intake-toolkit`
  absent the resolver returns 1 and the gate envfails rather than passing an unevaluated check.
- **Mutation-ordinal hygiene is intact, and this round owns the check.** Because the guard was
  `deferred-to-nightly` the PR lane computed no verdicts, so the ordinal accounting falls to the
  round. I compared base against head for all six operators in `mutation-operators.tsv`: the
  first three matched-line ordinals are identical for every one (`cmp-eq` 218/420/421, `default`
  219/220/298, `cmp-z` 400/417/428, `logic` 400/428/429, `detector` 743/756/814, `fail-open` none),
  because every added site lands at 2913+. So `lean-gate.sh::cmp-eq::1`, `::default::1` and
  `::default::2` keep their anchors and **no re-baseline was owed** — the absence of a
  `mutation-baseline.tsv` change is correct, not an omission.
- **Selftest placement and state hygiene are careful.** The block is deliberately placed after
  `(b1)`/`(b2)` with the reason recorded (those cases assert cumulative counters a `reset_progress`
  would zero), and the restore line is *byte-identical* to `(a3)`'s at `:233`, so every downstream
  case sees exactly the state it did before. `(c)`'s own `reset_progress` follows immediately, so
  the trailing one is redundant — harmless, and mentioning it only because the rest of the block is
  precise enough that it stands out.
- Clean on both CI axes I could check locally ahead of the lane: `bash 3.2 -n` parses both files,
  and `shellcheck -e SC1091,SC2015,SC2181` is silent at 0.11.0, stricter than CI's pinned 0.9.0.

## Suppressed / not upheld

- `(a7)` called decorative relative to `(a5)` (unit-test-mutation, 82). Correct that it adds no
  distinct `lean-gate.sh` path — both are rc=0 passes — but it does pin the integration against
  `ledger-lint.sh`'s `ROW_COUNT == 0` + explicit-empty-form branch, which is the form the repo
  points trivial work at. Keep it; a half-line in the case comment saying it guards D-3's
  default-vs-`--receipt` decision is what makes that visible.
- Unquoted `$(ls -1)` word-splitting over version dirs (security, 40). Version dirs are `X.Y.Z`;
  not reachable.
- Full `ledger-lint` output interpolated into the failure message (security, 35). The content is
  spec diagnostics; that is the point of the message.
- The `#394` comment above `design_state` describes milestone 1's observe pass as reading the spec
  and config with "no subprocess beyond grep/awk"; the new check spawns `bash ledger-lint.sh` ahead
  of it. Read-only and cheap, and no production caller runs milestone 1 under
  `LEAN_GATE_OBSERVE=1`, so this is a stale comment rather than a behavior change. Noting it, not
  charging it.

## CI

`pr-gates` red is the expected pre-verdict state and not a finding — `[lean-evidence] ✗ no
committed verdict record (a file named *-562-lean-verdict.md)`, which this record resolves. Every
other check is green: `lint-and-selftests`, `selftests (macos, bash 3.2)`, `mutation-sweep-pr`
(zero verdicts, deferred — see Blocker 2).

## Design fidelity

`not-applicable`. The spec's `## Design` section carries the explicit disarm (`Design: none — a
shell-script gate change with no UI surface; design.provider is unset in this repo's config`) and
I verified the disarm rather than taking it: `.design` is absent from
`.claude/second-shift.config.json`, and no changed path touches a web-component surface. There is
no handoff link and no `| RS-n |` table to score, so step 5b does not apply and there is no
under-declared-table judgment to make.
