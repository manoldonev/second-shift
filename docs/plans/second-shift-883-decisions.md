# Pre-flight receipt — #883: figma-faithful's live-render verify is mandatory

Interviewed 2026-09-22. The ticket body states the change; every decision below is grounded in it
or in the skill file. First unattended run of the shrunk scheduler (#881 D-3, run 1).

## Decision Ledger

| ID | Decision | Resolution | Provenance | Kind |
| --- | --- | --- | --- | --- |
| D-1 | Scope of the edit | `plugins/design-toolkit/skills/figma-faithful/SKILL.md` only: step 9 and the worked example. No script, no config, no other skill (#883 body) | codebase-derived | fact |
| D-2 | What "mandatory" means when nothing can render | The skill never silently skips: the output contract gains a fifth item — render evidence per screen, or the explicit line `could not render: <why>` (#883 body) | codebase-derived | fact |
| D-3 | Render rounds per screen | Up to three: render, open the image, compare with the frame, fix what differs (#883 body; matches the shrink design's build prompt) | codebase-derived | fact |
| D-4 | What counts as "not done" | An error page, a login page or a spinner in the render (#883 body) | codebase-derived | fact |
| D-5 | Existing references to the conditional wording elsewhere | `docs/live-render.md` and the render-receipt gate describe the old lane's render step and are #881's to change; this ticket does not touch them | codebase-derived | fact |

## Open Regions

No open regions — every decision in scope is ratified.

## Surface Inventory

| ID | Surface | Disposition |
| --- | --- | --- |
| S-1 | Step 9 of the skill as an implementer reads it | decided (D-1) |
| S-2 | The output contract list at the end of step 9 | decided (D-2) |
| S-3 | The worked example section | decided (D-3) |
| S-4 | `docs/live-render.md` and the gate's render receipt | out-of-scope — #881 rewrites the lane's render machinery |

## Checks

- `find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181`
- `find . -name '*.json' -type f -print0 | xargs -0 -n1 jq empty`
- `bash scripts/check-lockstep-pairs.sh`
