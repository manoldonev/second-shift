# The context model

The layered taxonomy of everything the toolkit and its agents consume. A piece of context is placed by three properties — **consumer** (shell tools need machine-readable; agents take prose), **authority** (derived from code / decided by humans / observed empirically), and **cadence** (onboarding-time / accretive / per-run) — never by topic alone.

## The layers

| # | Layer | Home | Consumer | Cadence |
| --- | --- | --- | --- | --- |
| 0 | **Generic tooling** — pipeline machinery, review/intake protocols, this repo's docs | second-shift plugins (public) | tools + agents | versioned releases |
| 1 | **Static config** — tracker, topology, base branches, command truth table, reviewer deltas, gates | `.claude/second-shift.config.json` per consumer repo | tools first, agents second | onboarding-time |
| 2 | **Org/platform overlay** *(future — see below)* — knowledge shared across an organization's repos but not the world | a private plugin/skills repo | agents | slow accretive |
| 3 | **Repo dynamic context** — the repo's own knowledge (four sub-kinds below) | consumer repo; `CLAUDE.md` routes | agents | accretive |
| 4 | **Operator context** — personal memory, billing posture, permission mode, model config | `~/.claude` (user level) | harness | personal |
| 5 | **Run state** — pipeline state files, audit ledgers, plans/briefs/ledgers, mode env vars | `.claude/pipeline-state/`, `.claude/audit/`, plans dir | tools | per-run |

**The direction rule:** each layer may read downward (toward 5), never write upward. A run may cite an ADR; a plugin release never embeds one. (Historical example: agent-eval kits once lived under a consumer repo's `pipeline-state/` — layer 5's home — but are layer-0 tooling; they ship in plugin `evals/` dirs.)

## Layer 1 vs layer 3 — the litmus tests

- If two consumer repos would differ on a **value** (branch name, command string, path), it's **config** (layer 1).
- If they'd differ in **behavior**, it's a config-selected adapter or gate (layer 0 machinery, layer 1 switch).
- If it's **prose-shaped knowledge** — why, how, gotchas — it's layer 3 (or layer 2 if it's true of every repo in the org). Prose never goes in config; enumerable facts never go in knowledge docs.

## Layer 3: the four sub-kinds of repo dynamic context

| Sub-kind | Authority | Typical home | Staleness rule |
| --- | --- | --- | --- |
| **Decided** | binding human commitments | ADR dirs (e.g. `.cursor/decisions/`, `.project/decisions/`) | agents never re-litigate; only humans amend |
| **Structural** | derived from code | architecture docs, CLAUDE.md stack/module/convention sections | re-derivable; **code wins on conflict** |
| **Observed** | empirical | `findings.md`, domain-gotcha sections | cheap to append, pruned rarely |
| **Playbooks** | derived + curated | repo-local knowledge skills (`.claude/skills/`) | every claim cited to source; re-verify when the cited source moves |

**The plugin is agnostic to layer-3 shape.** The repo's `CLAUDE.md` is the *context router* — it declares where these sub-kinds live and their read-priority order (the proven pattern: code > decisions > architecture > reference > plans). Plugins read CLAUDE.md (the harness loads it) and follow the routing; they never hardcode a repo's doc layout. This is why one toolkit serves `.cursor/`-shaped and `.project/`-shaped repos without a config field.

Plugin agents additionally read the **extension files** documented in [`extension-points.md`](extension-points.md) (blocker-mutant lists, domain security rules, review context) — those are layer 3 exposed at fixed, documented paths precisely so layer-0 agents can consume them without knowing the repo's doc layout. Extensions are additive-only; disabling generic behavior happens in config (layer 1), where it's auditable.

## Layer 2: the org/platform overlay (future)

The named gap. Knowledge shared across an organization's repos but proprietary to it — platform-library conventions, internal SDK playbooks, shared infrastructure patterns, org-wide review rules. Without this layer it gets duplicated per repo (observed in the wild: the same platform-SDK playbook vendored near-identically in two sibling repos — the same disease this marketplace cures for tooling, one layer up).

Shape when it materializes: a **private plugin marketplace/repo** (e.g. `<org>-platform`) sitting between the public layer 0 and each repo's layer 3 — same distribution mechanics, same version discipline, different visibility. Consumer repos enable it alongside second-shift. Until then: author such knowledge in the repo where it's first needed, but mark it as overlay-shaped so it's liftable.

## Placement quick-reference

- Base branch, test command, sibling path → **1 (config)**
- "Our services must never hand-filter by tenant; the base class does it" → **2** if org-wide, else **3 decided/structural**
- "This eslint rule false-positives on X" → **3 observed** (findings)
- "How to verify changes locally in this repo" → **3 playbook** (knowledge skill)
- "How the pipeline claims a ticket" → **0** (plugin), tracker choice via **1**
- "Security reviewer runs opus here" → **1** (`reviewers.modelOverrides`)
- Per-ticket decision ledger → **5** (run state)
