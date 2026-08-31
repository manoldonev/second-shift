# #711 — no gate reads a rendered measurement against the plan's design dimensions

Slice 4 of 4 of #705 (sequential; predecessor #710 closed).

## Problem

Milestone 3 renders and hashes; `review-lean` 5b writes a per-state evidence table the writer
checks for shape. No gate reads a rendered MEASUREMENT, so a screen 2.2× the design's width
passes every mechanical check (#692). The translation plan's node table (#710) already records the
design's numbers per node — the design side of a comparison exists; the rendered side does not.

## Approach

The harness emits `<png>.rects.json` beside each screenshot, keyed by the plan's node name. The
plan's node table gains three required columns — `node` (the rects key), `RS` (which declared
render state the node is measured in), and `px` (`<w>×<h>`, each side an integer or `-`) — and
milestone 3's render pass compares the two, scale-adaptively (D-2): per RS row, `k = median(r_i)`
over the axes the plan states, `shape` when a node is out of proportion with the rest of the row,
`scale` when `k` itself is not explained by `design.liveRender.tolerancePx` (default 2).

Node→element mapping stays the consumer harness's job — it owns the DOM. The gate compares
numbers.

## Acceptance criteria

Inherited verbatim from the issue body, which the pre-flight receipt (D-12, D-16) records as the
authority for this slice. AC-9 to AC-11 are ADDED here: they are the issue's own `## Scope` items
1, 4 and 5, which the inherited AC set does not cover, and adding them widens the definition of
done rather than re-deciding it.

- **AC-1**: given a node row whose `px` cell is `-×32` for node N and a rects entry
  `{N: {height: 107}}`, milestone 3 reds naming RS-n, N, 32, 107.
- **AC-2**: `{N: {height: 33}}` with default tolerance passes; `tolerancePx: 0` reds it.
- **AC-3**: a declared RS row with no rects file, or a plan node absent from the file, reds —
  never passes silently.
- **AC-4**: editing the rects file after the receipt is written stales the receipt
  (`render_bytes_ok` covers it).
- **AC-5**: `config-lint` rejects a non-integer or negative `tolerancePx` and accepts its absence;
  `docs/config-schema.md` documents it.
- **AC-6**: catalog rows for each new red — including one whose mutant DELETES the `scale` arm,
  since an exit-code-only case would score that fail-open shape as covered; liveness extended;
  `feat(dev-pipeline):` + `Changelog:` naming the consumer migration.
- **AC-7**: a row whose every stated node is rendered at a common factor — design `-×32`/`-×50`,
  rects `{height: 70}`/`{height: 110}` — reds as `scale` naming k≈2.2 ONCE, not once per node.
  This is the #692 defect class and it is the arm's fail-open flank: median normalization absorbs
  a uniform scale, so an arm that lost this check still reds on genuine per-node defects and looks
  alive while being blind to #692 exactly.
- **AC-8**: a row with three mismatching nodes reds naming ALL THREE in one message, following
  `plan_violations`' accumulate-and-join style rather than the render loop's return-on-first-row.
- **AC-9**: `docs/live-render.md` states the rects sibling in the command contract next to `{out}`,
  the CSS-pixel obligation, and what a harness that cannot resolve a node does — omit the key, and
  the gate then reds that node, because silence is not a pass.
- **AC-10**: `review-lean` 5b tells the reviewer that a sizing row's `rendered` cell cites the
  rects value rather than a reading taken off the PNG.
- **AC-11**: `figma-faithful` step 7 declares the `node`, `RS` and `px` columns alongside
  `dimensions`, so the columns milestone 3 requires are the columns the plan-writing skill names.

## Decision Ledger

Carried forward from `.claude/pipeline-state/711-ledger.md` (`ledger-carry-forward.sh`), same
`D-n` ids and Resolution text.

| ID | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | Where the machine-readable size lives, given that guess-point 2 would make `dimensions` structured | A NEW `px` column on the plan's node table carries `<w>×<h>`; `dimensions` stays PROSE. `figma-faithful` step 3b mandates sizing/fill/overflow per node in the `dimensions` cell and step 8 self-verifies against it ("no stretch on an incomplete wrap row, fixed dimensions hold — overflow truncated"); `348×32` cannot carry that payload. `plan_violations` (lean-gate.sh:3970-3971) already anchors two independent column names in one awk, so a third anchor is the same mechanism and no existing skill prose is re-keyed. AMENDS guess-point 2. | user-answered |
| D-2 | Comparison method: absolute-pixel equality vs an invariant that survives the coordinate-system difference | SCALE-ADAPTIVE, not absolute. Per RS row, over the axes the plan states: `r_i = rendered_i/design_i`, `k = median(r_i)`. Two separately-named reds, both in px against one tolerance: `shape` when `abs(design_i*k - rendered_i) > tolerancePx` (this node is out of proportion with the rest of the row), `scale` when `abs(design_i*k - design_i) > tolerancePx` (k itself is not explained by tolerance — the whole row renders at k). Browser viewport and Figma frame width differ as a matter of course; the gate infers the scale rather than requiring it be declared. | user-answered |
| D-3 | Whether the render viewport is pinned so absolute-px equality is meaningful | NOT pinned. No `design.liveRender.viewport` key, no plan header frame-width, no viewport field in the rects file, no consumer migration beyond the one already in scope. D-2 dissolves the question: a uniform viewport difference surfaces as the `scale` red naming k, which is more attributable than six unexplained per-node deltas. Fill-width nodes keep the `-` axis escape (guess-point 2). | user-answered |
| D-4 | Red-budget class for each new milestone-3 red | Split by IN-WORKTREE FIXABILITY — the criterion guess-point 8 already applied to malformed JSON, generalized. Fix attempt (costs 1 of 3): `shape` mismatch, `scale` mismatch, a `px` cell that does not parse, a plan node absent from the rects file, a plan missing the `node`/`RS` columns. Absent budget (free): the rects file missing entirely, malformed rects JSON. Missing-node is deliberately on the fix budget — otherwise a session earns unlimited free retries by naming nodes the harness never emits. | user-answered |
| D-5 | First mismatch vs all mismatches on a red | Collect ALL and report joined, following `plan_violations`' own accumulate-and-join style (`tr '\n' ';'`, lean-gate.sh:4191) rather than the render loop's return-on-first-row. With mismatch on the fix budget, first-only spends one of three attempts per node revealed, and the 2.2×-wide screen hard-stops at attempt 4 having never shown the operator the shape of the problem. | user-answered |
| D-6 | Required columns on the plan's node table | `node` (the rects key) and `RS` (which declared render state the node is measured in), asserted by the same column-anchored predicate. Per guess-point 1, attached to the D-1 table rather than to `dimensions`. A plan without them reds milestone 3; plans are per-run artifacts, so the only migration is in-flight armed runs re-emitting the plan. | codebase-derived |
| D-7 | Whether relative position / inter-node gaps join the rects schema | NO — deliberate non-goal this slice. `getBoundingClientRect` would give x/y for free and `figma-faithful` step 3b names inter-node gaps as the thing an isolated-node read misses (`next.x − (this.x + this.width)`), but the plan has no column that states a gap today, so the gate would have a measurement and no design-side number to compare it against. Road named, not taken; D-7 of the #705 receipt fixed the schema at `{width, height}`. | user-delegated |
| D-8 | Whether rects rows enter the byte-identity (`dup`) collision detector | EXCLUDED. That detector's stated purpose is a `{state}`-blind harness shooting the same view twice (lean-gate.sh, render loop) — a claim that is false for a rects file. Guess-point 4 explicitly blesses `{}` for a state with nothing to report, so two legitimate `{}` files hash identically and would red as a state-blind harness. | codebase-derived |
| D-9 | Whether AC-4 (editing the rects file stales the receipt) needs new gate code | NO — satisfied by construction. `render_bytes_ok` (lean-gate.sh:3937-3949) reads `id/png/sha` positionally and asserts only non-empty plus a sha match, so a `.json` path is covered unchanged. Guess-point 7's second row per state (`RS-n.rects`, same three fields) is correct as written. | codebase-derived |
| D-10 | Whether a corrected `dimensions`/`px` table can slip past the cached render path | It cannot. `render_patch_id` (lean-gate.sh:975) excludes only `VERDICT_REL` and `RENDER_MANIFEST_REL`, with an explicit comment that the symmetric plan exclusion is deliberately absent ("the plan is asserted and committed BEFORE the render pass ever computes an id"). Editing the plan moves the id, stales the receipt and forces a re-render, so path (b)'s short-circuit is not a hole. | codebase-derived |
| D-11 | `tolerancePx` validation site and default | Joins the `liveRender` known-keys list at `plugins/dev-pipeline/tools/config-lint.sh:243` in the house `err(...)` combinator style; optional integer >= 0; the default `2` lives gate-side in `cfg`. Guess-point 9 verified accurate against current main. | codebase-derived |
| D-12 | Provenance of the nine "resolved guess-points" the ticket cites | The ISSUE BODY is the authority of record. `.claude/pipeline-state/705-ledger.md` does NOT exist on this machine, and its rows are not in #705's comments. Its absence from git history is expected and uninformative — `.gitignore:7` ignores `.claude/pipeline-state/`, so no receipt is ever committed; a receipt written on another machine simply does not travel. The nine resolutions inlined in #711's body are the only surviving record, and D-7 of that receipt is attested by the body alone. https://github.com/manoldonev/second-shift/issues/711 | codebase-derived |
| D-13 | Scope addition: who tells a plan author to emit the new columns | `figma-faithful` step 7 must emit the `px`, `node` and `RS` columns (SKILL.md:198 declares the `dimensions` column today). Not in the ticket's scope list; without it the gate requires columns the plan-writing skill never mentions, and every armed run reds at milestone 3 with no instruction to follow. Added to scope. | codebase-derived |
| D-14 | Line references in the ticket body | Stale after #710 — resolve by SYMBOL, not line. `plan_violations` awk is at :3988 (body says :3787), `render_bytes_ok` at :3937 (body says :3755-3770). `config-lint.sh:243` and `docs/live-render.md:46` are still accurate. | codebase-derived |
| D-15 | Guard against the fail-open shape D-2 introduces | Median normalization ABSORBS a uniform scale, so an arm that lost its `scale` check still reds on genuine per-node defects and looks alive while being blind to #692 exactly. The `scale` red therefore needs its own `lean-gate-selftest.sh` scenario AND a `tools/mutation-catalog.tsv` row whose mutant deletes the `scale` arm — an exit-code-only case would score the fail-open shape as covered. | user-delegated |
| D-16 | AC coverage for the new defect class | AC-1 and AC-2 survive verbatim under D-2 (at N=1 the median absorbs everything and the arm degenerates to absolute comparison: `33 vs 32` passes at tolerance 2, reds at 0). AMENDMENT APPLIED at pre-flight, retiring OR-1: guess-point 2 re-pointed at the `px` column with the step-3b rationale, guess-points 10-12 added (scale-adaptive comparison, no viewport pin, budget split), AC-1 re-spelled against `px`, AC-7 added for the `scale` class, AC-8 for all-mismatches-joined, AC-6 extended to demand a mutant that deletes the `scale` arm, scope item 5 added for `figma-faithful` step 7. https://github.com/manoldonev/second-shift/issues/711 | user-answered |

## Open Regions

| ID | Region | Disposition |
| --- | --- | --- |
| OR-2 | A harness screenshotting at `deviceScaleFactor: 2` renders a correct implementation at a legitimate k=2.0 and would take a hard `scale` red | reversible-default-and-flag |

OR-2 takes the reversible default, as the pre-flight receipt resolved it: `docs/live-render.md`
states that the harness reports CSS pixels, not device pixels, and any k not explained by
tolerance reds. Reversing it later is one predicate — tolerate an exact integer k — and the
flagged default is the safer side, because under the CSS-pixel contract a device-pixel harness is
a harness bug and a silently tolerated integer k is precisely the #692 blindness this slice
closes.

OR-1 was retired at pre-flight (id not reused); its amendment is applied in the issue body.
