# lean review verdict — #695

verdict=needs-work
run_id: review-695-1
session_id: 82da75bb-2583-44d1-bf8c-d9d8593a7df9
rounds: 1
pr: #702
reviewed_head: 0ad8c00a2eeb0e8c296bead231e400aea199d9f2
reviewed_patch_id: 5c7d72737f9c8371ae83b7ed5e61809a21fc8f4b
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: opus
capabilities: pr-marker

# Review round 1 — PR #702 (#695)

**Verdict: needs-work.** One blocker.

Range read: `6dd9f70..0ad8c00` (root round — full branch diff, 2 files, +193/-7).
Reviewed from the lane worktree with `claude/second-shift-695` checked out.

Gate of record: the **branch copy** of `lean-gate.sh`
(`plugins/dev-pipeline/skills/build-lean/lean-gate.sh`), not the installed
`dev-pipeline/11.0.0` cache — `main` is at 12.1.0 and the cached gate lacks
`plan_patch_id` / `PLAN_MANIFEST_REL` / `seed_lane_worktree_settings`. Same choice the build
session made and recorded.

## Finding table

| # | Severity | Location | Finding |
| --- | --- | --- | --- |
| B1 | **Blocker** | `docs/live-render.md:34` | `"Your script owns **boot, auth, and screenshot**. The gate owns route derivation and comparison."` — the gate owns **no** comparison. This is the ticket's own defect class, in the file this PR rewrote to remove it, 29 lines above the correction it added. |
| W1 | Warning | `docs/live-render.md:203`, spec "Follow-up owed" | Direction 2 "belongs to its own ticket, with those costs priced" — that ticket is not filed. A shipped doc points at a component that does not exist, which is the shape #695 exists to retire. Mitigated but not removed by the adjacent **"Nothing here defers to it."** |
| W2 | Warning | `0ad8c00` commit trailer | `Changelog: none` on a correction to the consumer-facing wiring doc that materially changes what a consumer believes the lane does for them. |

### B1 — the same false-capability claim survives in the same file

`docs/live-render.md:34` sits in **`## The command contract`**, the section a consumer reads to
build their render harness, and states the division of labour as:

> Your script owns **boot, auth, and screenshot**. The gate owns route derivation and comparison.

It is flatly contradicted by three things, one of which this PR wrote:

- this PR's own new opening, `docs/live-render.md:5-6` — "**The gate compares nothing against
  the design** — it caches no design frame";
- the file's pre-existing `docs/live-render.md:167` — "**Comparison is still not the gate's.**
  Nothing here diffs a screenshot against a design frame";
- `lean-gate.sh:3552` — "What this gate does NOT do: compare anything. Comparison against the
  design frame is review judgment (D-5) and lives in the review-lean session."

Verified against the code, not just the prose: `cmd_3`'s render loop runs the consumer command,
requires a non-empty PNG at `{out}`, `lean_sha256`es it, runs the byte-identical-states detector,
and writes the manifest. There is no design-side input anywhere in it. Route derivation IS the
gate's (`{route}` comes from the spec's `| RS-n |` rows), so only the trailing "and comparison"
is false.

Why this is a blocker and not a pre-existing-gap note:

1. **It is the ticket's defect class verbatim.** D-5 is on the record calling exactly this shape
   out — "a document crediting a component with fidelity work it does not do" — and justifying
   AC-5 on the ground that "shipping AC-4 without it leaves the file self-contradictory." The
   file is still self-contradictory, for the same reason, 29 lines up.
2. **AC-1 requires the decision to be recorded "operatively in `docs/live-render.md`."** Line 34
   operatively records the opposite, in the one section a consumer implementing a harness cannot
   skip.
3. **AC-6's completeness check is structurally blind to it.** The grep enumerates four *phrases*
   (`pixel-diff`, `pixel diff`, `screenshot-diff`, `screenshot diff`), not the *defect shape*, so
   a sentence that credits the gate with comparison without naming a pixel differ passes it. The
   grep reads as complete and is not — the audit that found this was
   `grep -E '(gate|milestone[ -]?3|lane).{0,80}(compar|verif...|check.{0,20}against the design)'`
   over `docs/ plugins/ schema/`, which returns line 34 as the only live instance repo-wide.

Fix: delete "and comparison" (and, if you want the sentence to keep saying something true, the
gate owns route derivation, the state matrix, the PNG hashes and the manifest — line 168 already
words that). One line. Consider whether AC-6's grep should be widened to the defect shape rather
than the phrase list, so the next instance is caught by the criterion instead of by a reviewer.

### W1 — an unfiled follow-up is a live pointer

`docs/live-render.md:203` ships "It belongs to its own ticket, with those costs priced." No such
ticket exists; the PR body says filing is the operator's action and "this needs your action to
land." The adjacent **"Nothing here defers to it."** is what keeps this out of blocker territory
— no verification responsibility is routed to the unfiled ticket, and the section heading says
"none is coming." But until the ticket is filed, a reader who follows that sentence lands
nowhere. File it, or reword to "would need its own ticket" so the doc does not assert one exists.

### W2 — `Changelog: none` on a consumer-visible correction

The behaviour did not change, but what `docs/live-render.md` tells a consumer their lane does
changed materially: a consumer reading the old opening believed the gate "semantically compares"
their render against the design. That is the kind of correction a consumer would want to see in
the release notes. Judgment call, not a gate — the presence check passes either way.

## Per-AC scoring (against the committed spec `docs/plans/second-shift-695-lean.md`)

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 | **satisfied** | Direction 3 recorded in the spec's `## Decision (AC-1)` with reasoning against directions 1 and 2, and operatively in `docs/live-render.md:190-212`. D-1/D-2 carry it in the ledger with legal provenance values. |
| AC-2 | **satisfied** | Re-measured independently at `0ad8c00`, not taken from the spec's table: `figma-faithful-spec-reviewer.md:33`, `figma-faithful-plan-reviewer.md:59,64`, `figma-faithful-reviewer.md:39`, `figma-faithful-spec/SKILL.md:219`, `design-faithful/SKILL.md:59` — every one denies the gate exists. Cited line numbers all resolve at the base too. A sixth file the issue does not name, `figma-faithful/SKILL.md:228`, also already complies. Zero edits to these files is correct, not a gap: #694 satisfied them, and a no-op edit would manufacture a diff. |
| AC-3 | **satisfied** | No gate built, so nothing is owed on "asserted by the lane" and no selftest is owed. Verified no document promises a gate is *coming*: the broadened grep for `once/when/until the gate`, `future gate`, `planned gate`, `not yet built` over `plugins/ docs/` returns nothing. (B1 is a claim that a capability *exists*, which is a different and worse shape, scored there.) |
| AC-4 | **satisfied** | `docs/live-render.md:180-186` no longer reads "the pixel-diff gate is still deferred"; the settled posture and its reasoning replace it at `:190-212`. |
| AC-5 | **satisfied as written** | The opening (`:3-12`) now describes what the gate does — runs the command, takes the PNG, hashes it into the receipt — and names the review session as the comparer. Verified against `cmd_3`. **Scored satisfied because the AC scopes itself to "the opening"**; B1 is the same defect elsewhere in the file, filed as a finding rather than as an AC miss. |
| AC-6 | **satisfied as written, weak as a criterion** | The literal grep returns only denials plus this PR's own explanation. See B1(3): the criterion is phrase-shaped, so passing it is not evidence the file is free of the defect — and here it is not. |

**Design fidelity: `not-applicable`.** The config declares no `design.provider`, so no `## Design`
section is required or present in the spec, and no render receipt exists. Step 5b does not apply.

## Panel

| Reviewer | Verdict | Findings | Model |
| --- | --- | --- | --- |
| Maintainability | Pass | 0 | sonnet |
| Scope completeness | Pass | 0 (1 suppressed: AC-2 satisfied in the base by #694, promoted after independent re-measurement) | opus |

Routing: **trivial-inert** — every changed file is Markdown outside `.claude/`, so security,
performance, complexity and test-coverage were not selected (no executable surface); a11y and the
design-fidelity dimension were not routed (no changed path matches
`stageParams.webComponentGlobs`, which the config does not set — default
`apps/web/**/*.{tsx,jsx}`). Not-selected, not dark: both selected reviewers returned usable
results, so the round is intact. B1 is a `[Cross-cutting]` orchestrator finding — no reviewer
reported it, and it was verified against `lean-gate.sh` before being raised.

## Strengths

- **The stale-evidence handling is the right call and is done honestly.** Every one of the
  issue's three line citations described pre-#694 text. The build re-measured all five AC-2
  targets at head, recorded the measurement in a table with quoted text, and edited **nothing** —
  refusing to churn five files for a diff. That is the harder and correct answer.
- **The unfiled second defect was carried under its own AC rather than folded in.** AC-5 and D-5
  make the addition visible and reviewable instead of smuggling it into AC-4's edit.
- **The rejection of direction 1 is grounded, not rhetorical.** "No `package.json` anywhere" and
  "the dependency lands on every consumer's harness" both check out; the repo has no image
  tooling and the `design.liveRender` contract is explicitly install-free.
- **Direction 2 is deferred without being disparaged**, with its precondition (#701's committed
  `dimensions` table) named and its known limitation — plan→code only, blind to design→plan —
  stated up front in the draft ticket.
