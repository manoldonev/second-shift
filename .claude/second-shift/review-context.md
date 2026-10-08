# Review context — second-shift

<!-- Section names must match the catalog exactly — see docs/extension-points.md
     "Authoring the review-context surface". Lint: check-review-context-sections.sh -->

## Stack
- Shell-first: shipped logic is bash plus a few `.mjs` Workflow scripts driving `jq`, `gh`, `git` and the `claude` CLI; the product surface is Markdown skills and agents with JSON manifests. No package manager, no runtime service.
- Checks: `shellcheck -e SC1091,SC2015,SC2181`, `jq empty` on every JSON, `tools/run-selftests.sh`. CI is model-free: `jq` + `gh`, no API-billed calls.
- Read Claude Code's native outputs (`permission_denials`, `total_cost_usd` in `claude -p` JSON) rather than building home-grown telemetry or parsing transcripts.


## Maturity stage
- Solo maintainer on a public, user-owned repo. What is enforced and what is only visible: `docs/pipeline-manifesto.md` (trust boundary).
- This repo consumes itself as a smoke test.
- Harness-internal changes are made by hand, not through the lane: a hand-authored PR with no decision record is normal here.
- Cost is change tax (how often unrelated PRs are forced to touch a file) and consumer rounds, not line count.


## Architectural invariants & deliberate deviations
- Untouchable: review in a separate session, and never self-merge. A PR that weakens either is Critical regardless of size.
- Capability scaffolding (prose telling the model how to work, stage choreography) is meant to shrink; removing it is expected. Adjudication scaffolding (a check the build did not run, a baseline it did not write, a verdict bound to a head it cannot move) must not be weakened. Lean in a run is not lean in enforcement.
- Evidence ladder, strongest first: re-execution > reconciliation > committed record > tracker record > local record > prose claim. A local record is tamper-evident at best.
- A new mechanism (script, contract, transport, supervision layer) earns its place only by deleting a bigger one; wiring an existing tested mechanism into a new call site is fine. A new committed artifact replaces a prose claim or a weaker record, never sits beside it.
- Deliberately absent: the milestone gate and stage choreography, the mutation sweep and its registers, the committed verdict-record lane, and the config keys configVersion 3 removed (`gates`, `stageParams`, `grillWaivers`, `topology`).
- `scripts/check-fail-open-shapes.sh` is the remaining cover for fail-open and comparison lines; a new fail-open shape is a real finding.
- `run.sh`: the header's "Rules every line below keeps" bind every change. Every exit prints `terminal: <slug>` and wrappers route on it, so renaming a slug or moving it to another exit code is a consumer-visible break, not a refactor.
- Config reads fail closed: a present but unparseable config refuses (`env-config-unparseable`), never falls back to defaults. Zero configured checks is red unless `commands.<key>.allowUnverified` declares it.
- Anyone can comment on a public issue, so a claim marker is trusted only from a Bot or the scheduler's own account. A configured bot that cannot be resolved refuses (`env-bot`); it never writes as the operator.
- The lane never releases the claimed label; the unclaim workflow does, on close.
- Release artifacts are derived at release time, every `plugins/**` change carries a `Changelog:` trailer, every checked-in script is exercised by a selftest, and a `run.sh` behavior change lands with a `run-selftest.sh` case that fails without it: `CLAUDE.md`.
- Plugin content is never vendored into consumer repos; the presence check is the only exception.


## Intentional complexity
- Reviewer transport (schema-free explorer, sentinel, in-script parse, the `structured-emitter` fallback, the emit deadline) is kept on measured evidence. Do not re-propose schema-forced single dispatch; remove a mitigation only with an ablation showing it is no longer needed.
- Reviewer agent files stay even when rarely dispatched: their names are reader keys in `plugins/review-toolkit/scripts/section-catalog.txt`, which consumers' review-context files are written against.
- The bot claim swap is three steps (add, confirm, remove) so there is never a moment with no label.
- `run.sh`'s slug and exit-code taxonomy and its env seams (`RUN_CLAUDE`, `RUN_GH`, `RUN_WORKTREE_ROOT`) exist for wrapper routing and fake injection in tests.
- Canary/template file pairs carry LOCKSTEP markers checked by `scripts/check-lockstep-pairs.sh`; the duplication is deliberate.
- `runtime-shim-lib.mjs` is named off the selftest discovery glob on purpose.


## Convention-required structure
- Plugin layout: `plugins/<name>/.claude-plugin/plugin.json`, `skills/<name>/SKILL.md`, `agents/*.md`.
- Selftests are discovered by the `*-selftest.sh` glob; no registration.
- Some scripts are covered under a differently-named suite (`claim-issue.sh` by `claim-selftest.sh`, `check-frozen-files.sh` by `derive-release-selftest.sh`); do not flag a missing same-named suite.


## Naming & structure conventions
- Record and PR forms are exact strings, never paraphrased: the claim marker `<!-- stage: lean-claimed -->` (not `stage: claimed`), PR body line 1 `built-by: second-shift run <id>`, the record commit subject `docs: decision record for #<n>`.
- Slug prefixes: `usage-*` is argv, `env-*` is the environment (exit 2); exit 3 is resumable. Full table: the `run.sh` header.
