# Relocate the design-fidelity reviewer routing into review-lead

The provider-keyed design-fidelity routing contract lives only in the stage lane's prose
(`plugins/dev-pipeline/skills/run/stages/8-code-review.md`). The lean lane reviews exclusively
through `review-lead`, whose panel names neither fidelity reviewer — so a design-driven FE PR under
lean gets zero design-fidelity review, and the contract's only home is deleted by the stage wipe.

This is a **relocation, not a new design**: mirror the Stage 8 contract, with exactly one deliberate
source change — the provider is read from repo config (`design.provider`) instead of from run state
(`stageCheckpoint["1"].designSource.provider`), which dies with the stage lane.

The dispatch half already exists: `code-review.mjs`'s `REVIEWER_MODEL` carries both
`design-toolkit:*-reviewer` entries at `sonnet`, and `check-model-tiers.sh` already resolves
design-toolkit frontmatter via `resolve_sibling_plugin_root`. Only the routing/registry half was
never ported.

## Surfaces

| File | Change |
| --- | --- |
| `plugins/review-toolkit/skills/review-lead/SKILL.md` | routing contract + config reader + all three parsed sub-registries + dispositions |
| `plugins/review-toolkit/scripts/check-reviewer-references.sh` | three-root resolution, design-toolkit-absent DANGLING exemption, sed label map |
| `plugins/review-toolkit/scripts/check-reviewer-references-selftest.sh` | present-toolkit + absent-toolkit cases |
| `plugins/review-toolkit/scripts/fixtures/reviewer-references/**` | fixtures backing those two cases |

## Acceptance criteria

- **AC-1** — `review-lead`'s Reviewer Routing carries the relocated contract: the
  `stageParams.webComponentGlobs` trigger (config-sourced, default `apps/web/**/*.{tsx,jsx}`,
  matched as in-session model judgment over the `--stat` path list), the three-way provider map
  (`figma` → `figma-faithful-reviewer`; `claude-design` → `design-faithful-reviewer`; **no provider**
  → `design-faithful-reviewer` as the generic web-component fidelity reviewer, its prior Stage 8
  default preserved and not narrowed), and never depth-suppressed. **Both** conditional-reviewer
  enumerations in the skill — the never-suppressed sentence under Review Depth Routing and the
  Conditionally-spawn table under Reviewer Routing — name the design-fidelity dimension.

- **AC-2** — the three sub-registries `check-reviewer-references.sh` parses (the pre-flight panel
  parenthetical, the **bold** entries under `## Reviewer Routing`, the Verdicts-table first-column
  labels) and its sed label map are updated together; the script exits green on the grown panel and
  the `git commit` PreToolUse hook does not deny.
  Mechanical constraint: the Routing sub-registry regex excludes `:`
  (`\*\*[a-z][a-z0-9-]+-reviewer\*\*`), so the bold Routing entries are written **bare**; the panel
  parenthetical may be qualified (the parse strips qualifiers).

- **AC-3** — `check-reviewer-references.sh` resolves design-toolkit-shipped panel agents via the
  sibling root, using the same resolution `check-model-tiers.sh` implements
  (`resolve_sibling_plugin_root design-toolkit`), its two-root contract header becoming three-root.
  With design-toolkit absent (the sibling root resolves empty), those names produce a printed notice
  and **no** DANGLING denial — otherwise every consumer without design-toolkit is commit-blocked by
  this change. The selftest gains a case for each (present-toolkit resolution, absent-toolkit
  degrade), and the existing real-root case (`check-reviewer-references-selftest.sh:102-105`) stays
  green. Because the exemption set is *declared*, every name in it is guarded: a case drives the
  **real shipped panel** against an absent design-toolkit and asserts the notice names **all**
  declared entries — the (real artifact × degrade condition) cell no fixture panel reaches. The
  versioned-sibling cache glob is exercised with no root override, so it is not dead code.

- **AC-9** — the SHADOW drift tripwire (`docs/namespaces.md` rule 5) still fires for the
  design-toolkit-shipped panel names this change registers, **whether or not design-toolkit is
  installed** — tested by membership in the declared set, not by file presence. Without this,
  registering the names silently retires the tripwire for exactly them: a consumer copy resolves
  DANGLING through the consumer-root clause and is in the effective registry, so it escapes ORPHAN
  too. Guarded by a selftest case run in the design-toolkit-absent configuration.

- **AC-4** — extension-file basenames for both reviewers are accepted
  (`.claude/second-shift/review-context/figma-faithful-reviewer.md` lints clean under
  `check-review-context.sh`), and `reviewers.remove` excludes either like any panel member (no
  REMOVE-UNKNOWN).

- **AC-5** — the never-selected and toolkit-absent dispositions are specified beside the Step 4b
  dead-reviewer contract and are distinct from `Dark (no output)`: note once in the round summary,
  never silent, never a red. Toolkit-absent detection is **in-session, pre-dispatch, at Routing** —
  it never reaches `code-review.mjs`, so it cannot collide with the `{result: null}` →
  `Dark (no output)` rule. The toolkit-absent disposition is keyed on **the dimension having been
  selected — by any row of the provider map, the no-provider default included** — never on
  `design.provider` being declared. The default row selects a reviewer with no provider key at all,
  so a presence-keyed condition would leave the commonest consumer (no provider, no design-toolkit)
  falling through every disposition — silently, which this AC forbids. The skill's clause and the
  lint's exemption are two halves of one degrade and must agree; the lint's is unconditional.

- **AC-6** — `plugins/dev-pipeline/skills/run-lean/SKILL.md` is unchanged.

- **AC-7** — no stage-file edits, no new reviewer agents, no `code-review.mjs` control-flow or
  model-table changes, and no lean-gate design-awareness. `code-review.mjs` and
  `check-model-tiers.sh` already carry the needed entries/resolution — verified unchanged, not
  re-added.

- **AC-8** — repo verification is green: `shellcheck` over all `*.sh`, `jq empty` over all `*.json`,
  and the full `*-selftest.sh` sweep.

## Design notes

**Verdicts table carries two rows, not one.** Only one fidelity reviewer is ever spawned in a given
repo, but the Verdicts first column is *parser input*: the DRIFT check compares the three
sub-registries as sets, so both labels must be present. The existing "only include rows for
reviewers that were spawned" rule already makes the table a template rather than a runtime claim.
The sed map already has `Design Faithful` → `design-faithful-reviewer` and gains
`Figma Faithful` → `figma-faithful-reviewer`.

**Which names are design-toolkit-shipped is a declared set in the lint**, not derived: when the
sibling root resolves empty there is nothing on disk to derive it from, and the exemption is exactly
the case that has to work without it.

**The config read is resolved once, not written cwd-relative.** Stage 8 read `"$SECOND_SHIFT_CONFIG"`;
the relocated copy keeps that override and anchors the default on `worktree` (the repo-under-review
path Pre-flight already supplies), matching what this same file documents for the `reviewers` read.
Both new keys fail *open* on an unreadable path — an unread `design.provider` takes the *key absent*
row, which is a legitimate state and therefore produces no not-selected note — so a cwd-relative
literal would route the wrong reviewer silently, and the Step 4c diagnostic would print default globs
for a config that was never opened.

**`a11y-reviewer`'s standalone trigger narrows, deliberately.** It moves from "the repo's web UI file
globs, e.g. `**/*.tsx` / `**/*.jsx`" (any depth) to `$WEB_COMPONENT_GLOBS` (default
`apps/web/**/*.{tsx,jsx}`) — the key and default Stage 8 already used. Sharing one trigger is the
point: the design-fidelity dimension is specified as spawning *alongside* `a11y-reviewer` on the same
surface, and two triggers that disagree would make "alongside" false. The cost, stated rather than
discovered: a consumer with FE at `src/**/*.tsx` and no `webComponentGlobs` key loses a11y routing it
had under standalone `/review-lead`, and fixes it by setting the key it would need for design-fidelity
anyway.

**`check-review-context.sh` needs no parallel change.** Its registry comes from
`_effective-registry.sh`, which extracts bare names from the same panel parenthetical by regex and
resolves no files — so AC-4 falls out of the panel edit. Verify, do not edit. The other
registry-script selftests carry their own inline fixture panels and need no updates.

**Scope honesty carried into the prose.** Both reviewers are design-blind by contract ("verifies the
abstraction is right, not that it matches an unseen design"). This dimension asserts design-system
discipline and copy-drift against a discoverable spec — not pixel match. The pixel loop stays with
the build session's self-verify artifact and the human reviewer.

**Blast radius.** The panel is shared by standalone `/review-lead`, `pr-revision`, review-lean, and
Stage 8 (until the wipe). From this change on, review-lead's copy of the routing is authoritative;
Stage 8's restated copy stays as-is during the coexistence window (its run-state trigger included)
and is deleted by the wipe.

## Testing

Per the tier map, the Routing/panel prose gets **no prose-presence guards**. The enforceable surface
is `check-reviewer-references-selftest.sh`:

- **present-toolkit** — a fixture plugin panel naming a design-toolkit-shipped reviewer, with
  `SECOND_SHIFT_DESIGN_TOOLKIT_ROOT` pointing at a fixture design-toolkit root that supplies the
  agent file → exit 0, no DANGLING.
- **absent-toolkit** — the same panel with `SECOND_SHIFT_DESIGN_TOOLKIT_ROOT` pointing at a
  non-existent path (the "plugin not installed" state) → exit 0, a printed notice, and no DANGLING
  line for those names.
- **real-root lockstep** — the existing case runs the shipped plugin root against an empty consumer;
  it is what catches the grown panel failing to resolve, and stays green.
