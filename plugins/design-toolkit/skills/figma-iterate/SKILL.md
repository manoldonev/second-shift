---
name: figma-iterate
description: Fast interactive Figma-to-code iteration for a consumer FE repo iterating quickly in alpha — takes Figma node URL(s) + optional override notes and produces a structurally faithful implementation via the figma-faithful discipline, resolving any Figma/reality discrepancies at one batched confirmation instead of blocking. Interactive-only; leaves the tree dirty (never commits); no ticket/reviewer ceremony. Requires the figma design provider (config `design.provider: "figma"`).
---

You are iterating on an FE screen or component from a Figma design, fast. The UX is moving
quickly (alpha) and there is no ticket — the user hands you a node link (and maybe some notes
on what Figma got wrong) and wants a faithful implementation without the dev-pipeline ceremony.

This skill is a **thin interactive fast-path over [`figma-faithful`](../figma-faithful/SKILL.md)**.
It reuses that skill's entire fidelity discipline — token extraction, layout-context reading,
real-component resolution, self-verify — and changes only two things: an **interactive-only
guard**, and a **single batched discrepancy checkpoint** in place of the plan-reviewer gate.
Everything not called out as a delta below is figma-faithful's protocol, unchanged. Read that
skill; this one does not restate it.

## Usage

```
/design-toolkit:figma-iterate <figma-node-url> [more urls...] [ — override notes] [review]
```

- `<figma-node-url>` — one or more "Copy link to selection" URLs (space-separated).
- `— override notes` — free text after an em-dash / on a new line: what Figma got wrong or what
  to do instead. Authoritative over Figma (Delta A). Optional.
- `review` — opt into a post-implementation `figma-faithful-reviewer` pass. Optional.

Examples:

```
/design-toolkit:figma-iterate https://figma.com/…?node-id=42-7 — tighten the header gap to 16
/design-toolkit:figma-iterate <url-a> <url-b> — Figma still shows the old CTA copy; use "Save changes"
/design-toolkit:figma-iterate <url> review
```

Interactive session only — see the guard below.

## When to use / when not

**Use** when: the UX is iterating fast, no ticket exists, and the user invokes this directly
with one or more Figma node links (optionally with override notes because Figma may be stale).

**Do not use** for:

- Autonomous pipeline runs — that is `figma-faithful` dispatched through the dev-pipeline
  (Stage 5). This skill rejects a non-interactive context (see the guard).
- Shaping a still-undecided feature / producing a formal spec — that is
  [`figma-faithful-spec`](../figma-faithful-spec/SKILL.md).
- A claude-design (non-Figma) repo — that is [`design-faithful`](../design-faithful/SKILL.md).

## Interactive-only guard (hard rule, not a doc note)

The batched discrepancy checkpoint below is load-bearing: this skill's whole value is that it
**asks** instead of blocking or silently guessing. If the session cannot ask the user, that
value is gone and the skill must not degrade to auto-answering its own confirmation.

**Concrete signal, checked before anything else:** the checkpoint runs on `AskUserQuestion`. If
that tool is unavailable or errors, or this skill is running as a Workflow/pipeline-dispatched
subagent (no human is on the other end of the question), the context is non-interactive —
**reject and stop before step 1**, before any Figma reads or code changes. This mirrors the
dev-pipeline "a missing ready-for-dev label is a strict reject-and-stop" idiom: fail fast, do
not improvise. Point the caller at `figma-faithful` (via the pipeline) for the autonomous path.

## Inputs

1. **One or more Figma node URLs** — a per-screen "Copy link to selection" URL is ideal; a
   section / "DEV-READY" link gets the same metadata → name-match → drill-into-child handling as
   figma-faithful's "Resolve the node" step. Never screenshot a whole section.
2. **Optional override notes** (free text) — what Figma got wrong or what to do instead. These
   are authoritative over Figma (see Delta A). Absent is fine.
3. **Optional `review` flag** — opt in to a post-implementation fidelity review (see No ceremony).

## Provider gate

Same as figma-faithful: this skill reads the design via the **figma design provider** (config
`design.provider: "figma"`). Tolerate **both** `mcp__figma__*` and `mcp__plugin_figma_figma__*`
tool namespaces. If neither is reachable the capability is not enabled — say so and stop; do not
guess values off a screenshot. (See figma-faithful's "Figma capability" section — not restated.)

## Fidelity protocol — figma-faithful by reference, two deltas

Follow figma-faithful's mandated sequence verbatim: **Resolve the node → Handle sparse dumps →
Extract tokens → Layout context (sibling spacing & placement) → Translate → Resolve components →
Mirror the analog**, then **Implement → Self-verify** after the checkpoint. Load its design-tokens
reference (`.claude/second-shift/design-tokens/*.md`) the same way. Its hard rules (no eyeballing,
no raw literals where a token exists, measure gaps between elements, Figma hierarchy = markup
hierarchy, reuse the real component, a sparse dump blocks) all apply here unchanged.

Only two things differ:

### Delta A — precedence policy

The skill never silently deviates from Figma; it **matches it, asks, or maps-and-notes**. When
sources conflict:

1. **User override notes beat Figma.** That is their entire purpose — Figma may be stale, and the
   user told you the current truth. Implement the note, record it in the checkpoint's discrepancy
   table so the deviation from Figma is visible, not silent.
2. **Figma beats current code for structure** — hierarchy, component identity, layout, placement.
   A structural mismatch against the existing file is a finding to fix, not a precedent to match
   (figma-faithful's existing stance).
3. **Code reality beats Figma only for mechanical mapping** — a token/variant/component that does
   not exist in the repo. This is figma-faithful's normal mapped-and-noted behavior: map to the
   nearest real token/component, **note it in the token table**, no confirmation needed. Mapped is
   never silent; it is written down.

### Delta B — one batched checkpoint replaces the plan-reviewer gate

Still produce figma-faithful's **translation plan** artifact (completed token table incl. the
inter-block gap rows, resolved-component list, placement decision, chosen analog, file list).
But instead of dispatching `figma-faithful-plan-reviewer`, present it to the user as **ONE
accept-or-edit checkpoint**, and attach a **discrepancy table** collected while working through
the sequence:

| Source A | Source B | What differs | Recommendation |
| --- | --- | --- | --- |
| Figma `gap 24px` | Your note "tighten to 16" | block gap | follow your note |
| Figma label "Submit" | Code renders "Save" | button copy | follow Figma |
| Figma `#3b82f6` | No palette token | off-scale color | map to `primary.500` (nearest) |

Everything figma-faithful would surface as an **Open Question** (unresolved component, TBD copy,
off-scale value that became a named constant, stale-looking Figma vs code) lands here as a row —
**nothing is deferred past this checkpoint**. Resolve each row per-item — *follow Figma / follow
my note / skip this element* — via `AskUserQuestion`.

Batching mechanics: per-item discrepancy confirmations are lightweight picks, **not** material
design decisions, so the interviewing-baseline ≤2-material-questions-per-turn rule does not
apply — the tool's native cap of 4 questions per call governs; chunk into multiple calls if there
are more than 4 rows. What this skill *does* borrow from `intake-toolkit:interviewing-baseline`
(where installed) is only: **recommendation-first** option ordering (the grounded default is the
first option), and **never re-ask** a row the user already resolved.

**No mid-implementation pinging.** Once the checkpoint is accepted, run Implement → Self-verify
straight through without further questions — unless implementation uncovers a genuinely new
blocking ambiguity (e.g. verbatim copy still missing), which reopens a single targeted question.

## No ceremony

No tracker interaction, no branch management (work in the current branch/worktree as-is), no
reviewer dispatch by default. Fidelity is gated by the checkpoint (before) and figma-faithful's
live-render self-verify (after), not by a review panel.

**Opt-in `review`:** when the invocation includes `review`, after implementation dispatch the
[`design-toolkit:figma-faithful-reviewer`](../../agents/figma-faithful-reviewer.md) agent on the
**uncommitted working-tree diff** — instruct it explicitly to compute its diff with
`git add -N . && git diff HEAD` instead of its default `BASE..HEAD`. This skill never commits, so
the agent's default `BASE..HEAD` would diff against an empty/unrelated tree and mis-report a clean
pass; the intent-to-add (`git add -N`) surfaces newly created files (exactly where untokenized
literals land) so they are not invisible to the reviewer.

## Exit contract

The working tree is left **dirty** — this skill never commits. The user eyeballs the running app
and owns the commit. Surface, alongside the implementation:

1. the **completed token table** (all columns filled, including the step-3b inter-block gap rows),
2. the **discrepancy-resolution table** — each row and how it was resolved at the checkpoint,
3. the **files changed**,
4. the **live-render verify result** (pass, or `render-verify-unavailable` with a detail).
