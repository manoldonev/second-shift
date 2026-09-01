## Blocking finding, first — the corpus is not in this checkout

Before any plan is worth reading, one fact about the base commit (`2b4c150 consumer repository at pinned base, kit not present`):

| Ticket's five in-scope files | Present here? |
| --- | --- |
| `scripts/check-lean-chain.sh` | **yes** |
| `plugins/dev-pipeline/skills/build-lean/lean-gate.sh` | no |
| `plugins/dev-pipeline/skills/build-lean/lean-evidence.sh` | no |
| `plugins/dev-pipeline/tools/operator-override.sh` | no |
| `plugins/dev-pipeline/skills/run-lean/orchestrate-lean.sh` | no |

`plugins/` is absent from the commit entirely — 429 tracked files, none under it. Corroborating evidence, not just a missing directory:

- The **precedent register itself is already red at base**: 11 of the 15 rows in `scripts/fail-open-sites.tsv` name `plugins/...` files, and `check-fail-open-shapes.sh:127` reds each as *"dispositioned file does not exist — the row is stale."*
- `OVERRIDE_GATES` occurs nowhere in the tree except one historical line in `docs/plans/second-shift-613-lean-verdict.md:130` — so **AC-5 and AC-6 have no ground truth to check against here**.
- `scenario-liveness-selftest.sh` (AC-10) is absent too.
- Of the one present file, my measurement matches the ticket on `note_violation` (18 call sites + 1 definition) but **not** on `fail`: this tree has **one** call site (`:475`), not two.

An installed copy of the kit exists at `~/.claude/plugins/cache/second-shift/dev-pipeline/12.2.3`, but it is a *published older version*, not the ticket's base tree — the ticket names `orchestrate-lean.sh:764/:923/:982` as the success-path `terminal … 0` calls, and in the cached 1044-line copy those lines are a comment, `terminal review-session-failed 1`, and `terminal review-dark 5`. It is not a faithful stand-in, and edits there would not be in the repo anyway.

Building the register against `check-lean-chain.sh` alone is the one outcome the ticket explicitly forbids: *"A register claiming to cover the merge boundary while classifying `check-lean-chain.sh`'s two `fail()` sites and delegating the rest would be exactly the vacuous coverage this slice exists to prevent."* So this is a genuine blocker, not a caveat — **I need the `plugins/` tree restored at the ticket's base commit before step 3 below.** My recommendation: restore the kit into this checkout (or point me at the correct base ref); do not proceed on the degraded corpus.

The plan below is what I will execute once the corpus is whole. Everything through P2 is doable today.

---

## Plan of record

### P0 — Corpus resolution *(me; blocking)*
Not a file: a recorded answer to the above. If the kit is restored, I re-run every measurement in the ticket from scratch and treat the ticket's numbers as claims to verify, not inputs (the `fail`-site discrepancy is why). Outcome is written into P2's Decision Ledger as a dated provenance row.

### P1 — Branch *(me)*
`claude/second-shift-636-gate-classification` off `main`, per `branchPrefix` in `.claude/second-shift.config.json`. No release artifacts touched at any point (`plugin.json` versions, `CHANGELOG.md`, `marketplace.json` are release-derived; `check-frozen-files.sh` reds a feature PR that edits them).

### P2 — The lean spec: `docs/plans/second-shift-636-lean.md` *(me; first commit)*
This is the plan-of-record artifact the repo itself requires — `check-lean-chain.sh:495` reds if no `*-lean.md` for the issue is committed, and `:499` reds if it carries no numbered `AC-n`. Contents:

- Restatement of AC-1…AC-10 as numbered criteria.
- **Decision Ledger** (`ledger-lint`-clean, each row with real provenance — settled-at-intake rows cite the ticket):
  - D-1 names: guard `scripts/check-gate-buckets.sh`, register `scripts/gate-buckets.tsv` — beside the precedent pair in `scripts/`, and deliberately *not* "classes", which `tools/gate-ablation-classes.tsv` already owns.
  - D-2 key format: adopt `path::name` from `docs/prose-blocker-triage.tsv` unchanged (intake-settled).
  - D-3 = OR-1 default: `envfail` dispositioned **one row per class**, leaning on AC-4's covered-count printing. Flagged as `reversible-default-and-flag`.
  - D-4 = OR-2 default: `unwired` is indefinitely legal per AC-6.
  - D-5: AC-7 wiring goes in `lint-and-selftests` (`.github/workflows/ci.yml:17`), beside `check-lockstep-pairs.sh` (`:143`) and `check-eval-model-identity.sh` (`:149`) — not `pr-gates` (`:228`).
  - D-6: `prose-blockers.sh check` stays unwired. AC-7 identifies this guard as the living coverage guard #610 D-9 was waiting on; it does not ask me to wire the census, and doing so would pull in the out-of-scope agent-contract widening.
  - D-7: the P0 corpus provenance.
- **Open Regions** dispositioned (both `reversible-default-and-flag`, neither `pause-and-ask` — so milestone 1 does not stop).
- **Design: none**, with the disarm reason (no rendered surface).

### P3 — The denominator measurement *(me; no committed artifact)*
Write the enumerator's shape rules, run `--list`, and capture the output. The rows in P5 are written **from that output**, never from the ticket's counts. Per-file primitives to enumerate, each re-measured: `lean-gate.sh` → `fail_milestone` / `envfail` / `ticket_refuse` / `fail_obligation` / `block_milestone`; `check-lean-chain.sh` → `note_violation` + `fail`; `lean-evidence.sh` → its own measured set (the ticket does not name it — I measure it, and any primitive I find that the ticket omits is reported, not silently dropped); `operator-override.sh` → `envfail`; `orchestrate-lean.sh` → `terminal` with **any** exit argument, zero included.

### P4 — `scripts/check-gate-buckets.sh` *(me)*
Modelled on `check-fail-open-shapes.sh` line for line, because that is the pattern of record.

- **Header** stating: why the register exists; that `--list` output **is** the denominator; the closed enum; every self-exclusion by name (helper *definitions* matching their own shape, as the precedent does at `:68`, plus the guard and its selftest carrying the shapes as data); and the out-of-scope residual — the ~19 `scripts/`+`tools/` CI guards and the `.mjs` workflow gates (AC-8).
- `--list` prints `file⇥line⇥text` and checks nothing (AC-2).
- Three independent reds, each its own `fail` (AC-2): enumerated site with no row; anchor matching nothing in its file (drift); row covering zero live sites.
- Closed-enum validation `gates-llm | gates-signal | gates-process | not-a-gate`, unknown value = error; `not-a-gate` rows require a stated reason (AC-1).
- Covered-site count printed per row, `hits > 0` semantics as the precedent (AC-4).
- **AC-5, register-internal**: `gates-llm` / `gates-signal` / `not-a-gate` rows must have an empty yield cell; a row whose yield cell names an `OVERRIDE_GATES` value must be `gates-process`.
- **AC-6, form check**: every `gates-process` yield cell is either a known `OVERRIDE_GATES`/`OVERRIDE_SCOPES` value or matches `^unwired — .+`.
- Exit code = violation count (doctor convention).
- Anchors compared through `ENVIRON`, never `awk -v`, for the escape reason at the precedent's `:135-137`.

### P5 — `scripts/gate-buckets.tsv` *(me)*
Header block carrying the column contract, the "count is not the contract" statement, the residual and the exclusions (AC-8 lives in both files, as the precedent does). Columns: `enforcer_key (path::name)` ⇥ `disposition` ⇥ `anchor` ⇥ `yield` ⇥ `why`. One row per enumerated site, except the D-3 `envfail` classes. Every `why` names the mechanism — a red lane is an objective signal, a self-approval check is a fabrication defense — not "looks fine".

### P6 — `scripts/check-gate-buckets-selftest.sh` *(me)*
Glob-discovered by `tools/run-selftests.sh`; no registration. Same-stem, same-directory, so **no `tools/mutation-pair-map.tsv` row is owed**. Arms, each on a fixture tree in `mktemp`: all-green; unclassified site; anchor drift; orphan row; unknown disposition; AC-5 violation (a `gates-signal` row carrying a yield); AC-6 form violation; `--list` prints and exits 0 without checking. Written to actually kill mutants — `mutation-sweep-pr` will mutate this guard diff-scoped.

### P7 — CI wiring *(me)* — `.github/workflows/ci.yml`
One step in `lint-and-selftests`, after the capability-parity step (~`:157`), with a comment saying why this register needs an explicit invocation (its selftest proves the guard works, never runs it against the real register — the same reason given at `:151-155`).

### P8 — `docs/pipeline-manifesto.md` *(me)* — AC-9
The bucket list at *"Where a gate may yield to a present human"* gains `gates-signal` between `gates-llm` and `gates-process`, plus a one-line pointer to `scripts/gate-buckets.tsv`. Principle only; no restatement of the enforcement (P5). If the added prose duplicates the register header verbatim I wrap both in `LOCKSTEP-BEGIN` markers rather than leaving two drifting copies — never a prose-presence grep.

### P9 — Obligation reconciliation *(me)* — AC-10
Each obligation gets a recorded outcome in the spec, including "none owed, and here is why" — a silent skip is indistinguishable from a miss:
- `tools/gate-ablation-classes.tsv`: a row per new refusal *reason*. Expected none — this slice adds no lean-gate milestone refusal — recorded as such with the reasoning.
- `scripts/fail-open-sites.tsv`: any `| grep -q` shape my enumerator introduces gets a row; I will prefer shapes that need none. (Note: this file's pre-existing staleness is P0's problem, not mine to paper over.)
- `plugins/dev-pipeline/skills/build-lean/scenario-liveness-selftest.sh`: extended per verdict path touched, with a non-vacuity case. If the final diff touches no verdict path, that is recorded with its reason rather than claimed as satisfied.
- `tools/selftest-suite-timings.tsv`: a row only if the new suite lands at/above threshold (`check-sweep-bound.sh` reds an untabled slow suite nightly).
- `tools/mutation-catalog.tsv`: a row if and only if it names a regression class it alone catches.

### P10 — Local verification *(me; before push)*
`shellcheck` over changed scripts (CI recipe flags); `SKIP_STRESS=1 bash tools/run-selftests.sh --full --exclude tools/install-topology-selftest.sh`; the new guard against the real tree; `check-lockstep-pairs.sh`; `check-fail-open-shapes.sh`; `check-guard-budget.sh origin/main`; and a demonstration that each of the three reds fires independently.

### P11 — Commits *(me)*
Honest conventional verb — `feat(guards):`, since a new enforcement capability is a minor bump and `chore:` would silently downgrade the release. Trailers:
- **`Guard-mass:`** — required. A new `check-*.sh` plus a new `*-selftest.sh` both count as guard mass (`check-guard-budget.sh:39-43`), so the PR reds without it.
- **`Changelog:`** — `Changelog: none` unless the diff reaches `plugins/**`.

### P12 — PR *(me)*
Body carries `Part of #605` and `Closes #636` (`check-lean-chain.sh:475` reds otherwise), the `--list` denominator count, the per-arm red demonstrations, and the residual statement.

### P13 — Review verdict record *(NOT me)*
`docs/plans/second-shift-636-lean-verdict.md`, written by an independent review session (`/dev-pipeline:review-lean <pr>`) carrying its own `run_id`/`session_id`. `check-lean-chain.sh` reds if the build run authored it (`:636`, `:641`), if it is uncommitted (`:697`), stale against the head (`:702`), or missing `reviewed_head` (`:717`). I cannot produce this artifact — that is the point of it.

### P14 — Merge *(maintainer / branch protection)*
Green `lint-and-selftests`, `pr-gates`, `mutation-sweep-pr`, `selftests-bash32`; squash. Versions and `CHANGELOG.md` are written later by `scripts/derive-release.sh` on the release PR, never here.

---

**What I need from you:** restore `plugins/` at the ticket's base (or give me the ref that has it). If you'd rather I proceed against the single present file, say so explicitly and I'll do it — but the register would then cover one of five files, and I'd be shipping the vacuous coverage the ticket was written to prevent. Not writing any code until you answer.
