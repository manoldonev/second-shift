# Plan — #133: a11y-reviewer prose is React/JSX/Tailwind-shaped

## Context / problem framing

`plugins/review-toolkit/agents/a11y-reviewer.md` states its rules in React/JSX/Tailwind idiom. On an Angular or Vue consumer the rules describe markup that does not appear in the diff under review, so a model pattern-matching the literal examples may under-flag `<div (click)="…">` (it does not read as `<div onClick>`) or hunt for Tailwind class names a plain-CSS repo never emits.

This is the softer half of #105. #132 fixed the hard-blocking half (the Stage-8 dispatch trigger) so the reviewer now *fires* on a non-React FE; this issue is about it being *useful* once it does. The WCAG substance is already framework-neutral — accessible names, contrast ratios, landmarks, heading order, focus visibility all land regardless of stack. Only the phrasing presumes a stack.

The repo has already solved this problem once. `plugins/review-toolkit/agents/maintainability-reviewer.md` line 16 carries a **stack-neutral** preamble; `db-reviewer.md` (line 12/14) and `pipeline-reviewer.md` (line 12/14) carry a fuller variant — an "X-agnostic" clause in the `description:` frontmatter, an intent-not-syntax preamble, and a *Repo stack context (load first)* block with a conservative-inference fallback that lowers confidence. `a11y-reviewer` is the outlier. The fix is to mirror the house idiom, not to invent a new one.

## Assumptions

- The rewrite is prose-only. No rule is added, removed, or weakened — every WCAG check present today survives with identical severity.
- Plain HTML is the correct neutral vocabulary: JSX, Angular templates, and Vue SFCs all compile to it, and ARIA/CSS are defined against it.
- The per-reviewer extension seam (`.claude/second-shift/review-context/a11y-reviewer.md`, line 28) is where framework-specific idiom belongs, so the base agent need not enumerate frameworks — only stop presuming one.
- No automated check asserts prose neutrality; per the repo's CLAUDE.md verification list (shellcheck / jq / `*-selftest.sh`), agent `.md` content is not exercised by CI. This is a read-and-judge change with a grep-able floor.

## Decision Ledger

| D-n | Decision | Provenance | Rationale |
| --- | --- | --- | --- |
| D-1 | Mirror the existing house stack-neutral idiom rather than invent a formulation | codebase-derived | `maintainability-reviewer.md:16` is the de facto house style; `db-reviewer.md:12` and `pipeline-reviewer.md:12` extend it. A fresh formulation drifts the reviewer crew and costs a second cleanup. |
| D-2 | Replace the `tsx` code block with a concept-first rule plus one plain-HTML example | codebase-derived | The issue offered "three dialects or prose-only"; both rejected. Plain HTML is what all three dialects compile to, so one neutral example stays concrete without presuming a stack. Enumerating React+Angular+Vue triples an agent prompt for dialects the repo cannot keep current, against the house idiom of stating intent. |
| D-3 | Broaden the primitives-library `e.g.` list across ecosystems; do not cut it | codebase-derived | `scaffold-review-context.sh` never emits a primitives/stack section and `check-review-context.sh` asserts none, so a consumer may declare nothing. Cutting the list trades a React bias for a blind spot. |
| D-4 | Scope is whole-file neutrality, not the six rows in the issue's table | codebase-derived | The table is illustrative. `htmlFor` (line 73), the props/spread vocabulary (66–67), and `className` (57) are uncited React-isms in the same file; a row-by-row implementer would leave residue. |
| D-5 | No lint/selftest is added to assert prose neutrality | deferred | A prose-neutrality linter is a general problem across all 17 reviewer agents, not a #133 deliverable. A grep-able negative token list serves as this change's verification floor. |

## Affected files/modules

- `plugins/review-toolkit/agents/a11y-reviewer.md` — the only edit target (116 lines).

Read-only reference (not edited):

- `plugins/review-toolkit/agents/maintainability-reviewer.md` — precedent preamble (line 16).
- `plugins/review-toolkit/agents/db-reviewer.md` — precedent description clause + stack-context block (lines 3, 12, 14).
- `plugins/review-toolkit/agents/pipeline-reviewer.md` — same pattern (lines 3, 12, 14).
- `plugins/review-toolkit/skills/reviewer-baseline/SKILL.md` — shared severity/output contract, referenced by the agent at line 44; explicitly not touched.

## Reuse inventory

- `plugins/review-toolkit/agents/maintainability-reviewer.md:16` — reuse the stack-neutral preamble wording as the template for a11y's own.
- `plugins/review-toolkit/agents/db-reviewer.md:3` — reuse the `description:` frontmatter "X-agnostic — the concrete Y comes from review-context.md" clause shape.
- `plugins/review-toolkit/agents/db-reviewer.md:14` — reuse the *Repo stack context (load first)* block shape, including the conservative-inference-and-say-so fallback.
- The existing per-reviewer extension block already at `a11y-reviewer.md:28` is reused as-is (no change).

No new helpers introduced.

## Implementation steps

1. **Frontmatter `description:`** — add the stack-agnostic clause in the `db-reviewer.md:3` shape, so the dispatch-time description no longer reads React-only. Keep the existing primitives-library-aware sentence.
2. **Opening preamble (after line 14)** — add the stack-neutral paragraph mirroring `maintainability-reviewer.md:16`: checks stated as *intent*, applied in the vocabulary of the repo's actual FE stack, never flagging the absence of a mechanic a stack does not have.
3. **Repo stack context block (line 16–18)** — promote the existing weak "Repo context (load if present)" into the `db-reviewer.md:14` *load first* shape, naming the FE stack dimensions (framework + template syntax, styling system, primitives library) and carrying the conservative-inference fallback that lowers confidence. Leave the per-reviewer extension block (line 28) unchanged.
4. **Primitives-library list (line 21)** — broaden the `e.g.` beyond React (per D-3) to span ecosystems, and preserve line 26's graceful degradation verbatim.
5. **Keyboard operability rule (lines 50–61)** — restate as "a non-native element carrying a click/tap handler" in HTML/ARIA terms (`role`, a `tabindex` making it focusable, a keyboard handler, or a real `<button>`). Replace the `tsx` block with a plain-HTML BAD/GOOD pair (per D-2), dropping `onClick`, `className`, and `tabindex={0}`.
6. **Primitives-wrapper deviations (lines 63–68)** — restate `asChild`-style forwarding and props/spread vocabulary in neutral terms: a wrapper that drops the library's attribute-forwarding escape hatch, however that library spells it (per D-4).
7. **Accessible names (lines 70–74)** — replace `htmlFor` with the HTML `for` attribute, noting the React spelling parenthetically (per D-4).
8. **Reduced motion (lines 86–90)** — lead with `prefers-reduced-motion` as the rule; mention utility-class variants as one way a stack may express it.
9. **Focus visibility (lines 98–101)** — state in CSS-property terms (`outline` removed without a visible `:focus-visible` replacement), noting the Tailwind spellings (`outline-none`, `focus-visible:`) parenthetically as one stack's form.
10. **Whole-file sweep** — re-read the result end to end as an Angular / plain-CSS consumer and confirm no remaining rule requires translating a React idiom before it can be applied.

## Test strategy

Verify-after (prose/infra refactor — no behavior change in executable code). There is no unit-test surface: config `commands.second-shift.unitTestScope` is `null`, so the mutation gate does not apply and no `*.spec.*` file is in scope.

The substantive check is a read-and-judge pass (step 10) with a grep-able floor: the React/Tailwind-only tokens must not appear as the *statement* of a rule. The repo-wide selftest + shellcheck + jq sweep confirms nothing else regressed (the agent `.md` is not executed by any of them, so a green sweep is a no-regression signal, not evidence for this change).

## Acceptance-criteria traceability

The issue carries no `## Acceptance Criteria` heading, so the Stage-1 intent snapshot is empty and this table has no rows.

| AC ID | Criterion (short) | Step(s) | Test(s) |
| --- | --- | --- | --- |

Definition of done (from intake decisions, not an AC snapshot): reading the resulting file as an Angular or plain-CSS consumer, no rule requires translating a React/Tailwind idiom before it can be applied — concretely, `onClick`, `className`, `tabindex={0}`, `htmlFor`, `asChild`, `outline-none`, `focus:outline-none`, and the Tailwind variant `focus-visible:` do not appear as the statement of a rule, only (where useful) as an explicitly labeled example of one framework's spelling. CSS `:focus-visible` and `prefers-reduced-motion` are framework-neutral and stay.

## Verification commands

```bash
# Repo verification sweep (CLAUDE.md):
find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181
find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty
find . -name '*-selftest.sh' -type f -print0 | xargs -0 -n1 -I{} env SKIP_STRESS=1 bash {}

# Grep-able floor for this change — each hit must be an explicitly labeled
# per-framework example, never the statement of a rule:
grep -nE 'onClick|className|tabindex=\{0\}|htmlFor|asChild|outline-none|focus-visible:' \
  plugins/review-toolkit/agents/a11y-reviewer.md
```

## Risks / rollback notes

- **Over-genericization risk:** stripping concrete examples can make an agent prompt vaguer and *lower* review quality. Mitigated by keeping one concrete plain-HTML example (D-2) rather than going prose-only, and by preserving every rule's severity tier.
- **React consumers must not regress:** the existing consumers are React/Tailwind. Every neutral restatement keeps the React spelling reachable (parenthetically or as a labeled example), so a React diff is judged exactly as before.
- **Rollback:** single-file prose change, no code paths touched — `git revert` of the one commit fully restores prior behavior.

## Out-of-scope

- A prose-neutrality lint or selftest for reviewer agents (D-5 — general problem across all 17 agents; would need its own issue).
- The other 16 reviewer agents, including any React-shaped prose they may carry.
- `reviewer-baseline` (shared severity/output contract) — referenced, never modified.
- The Stage-8 dispatch trigger — already fixed in #132.
- Any change to WCAG rule substance, severity tiers, or the What-NOT-to-Flag list's meaning.
