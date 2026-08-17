# lean review verdict — #348

verdict=needs-work
run_id: review-348-4
session_id: 56d1044d-6e65-48e4-8882-59c5a90088bf
rounds: 4
pr: #568
reviewed_head: f59de2f48c742369630ca36dd4634f76f6daef4c
reviewed_patch_id: 2402f48229b934a34c6fe8d6532f7ec435ff93b4
inherited_patch_id: bd8238bc7c30327dcb23098683a8239da9bcbf55
inherited_from_verdict: da021d77254c387742efab7bc7eac5e949622bc1
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 4 over the delta `da021d7..HEAD` (1 commit, `f59de2f`, 44 files, +362/−186), inheriting
rounds 1–3 by reference to the committed round-3 record. Read wider than the range wherever the
delta looked misleading: all four orphan-check kinds whole-tree, the deleted-tool-name
discriminator whole-tree, every mutation register cross-checked against the surviving tree, and
the caller claims each rewritten comment makes.

**All six round-3 findings are closed, each verified against the code rather than taken from the
PR body.**

| Round-3 finding | Verified how |
| --- | --- |
| Blocker 1 — the abort bundle asserted a section its producer could not emit | Ran the reviewer's own repro **and a second case**: `state_excerpt()` now prefers `*-lean-progress.md` **by class**, tails it, and still selects newest-within-class when two lean records exist. The mtime-inversion in the fixture is load-bearing, so neither new case is the vacuous outer-guard shape. |
| Blocker 2 + warning 3 — the `$schema`-rendered config layer | Zero staged-lane vocabulary left in **any** schema `description` (`jq` over every `description` string: no `Stage N`, no `statectl`/`verifyctl`, no "both lanes"). The two surviving hits in `docs/{config-schema,extending}.md` are past-tense, which this spec's own discriminator licenses as class (a). EP-6/7/8 carry the `INERT since #348` banner in the schema now, not only in `extending.md`. |
| Warning 4 — the stage-keyed worked example | Rewritten: each of the four blocks is labelled LIVE (with its surviving reader) or INERT (with its §). |
| Nits 5, 6 | Closed. `config-lint.sh`'s runtime message is reframed on the real actor; `doctor/SKILL.md` names `lean-gate`. |

The AC-1 amendment is exactly true at this head — I re-ran all four kinds myself:

| Kind | Result at `f59de2f` |
| --- | --- |
| 1 — path into the deleted tree | the seven declared classes and no eighth |
| 2 — `/dev-pipeline:run` literal | every hit in the three declared exemptions or the historical plan corpus |
| 3 — relative-link resolution | unchanged from round 3; nothing in this delta moves a link |
| 4 — bare `/dev-pipeline` invocation | **no shipped artifact instructs it** — every remaining hit is `plugins/dev-pipeline/…` path noise or the spec's own description of the check |

The **whole-tree discriminator sweep** the spec now commits to (`statectl`/`verifyctl` by tool
name) returns no present-tense claim about a live mechanism outside the declared keep-classes. I
spot-verified the three sharpest rewritten claims against the code rather than reading them:
`resolve-worktrees-dir.sh`'s "one live caller today" (exactly `preflight.sh:219`),
`is-inert-diff.sh`'s "the ONLY runtime caller" (exactly `preflight.sh:358`), and
`intake-readroot-selftest.sh`'s MOOT recording (`non-main-base-autonomous` survives only in
`state-schema.md`'s bannered row and `CHANGELOG.md`). All three hold. The `cost-tracking-setup.md`
rewrite was checked against `pipeline-cost-block.sh` line by line — the `--stateless` CLI surface,
the `exit 2` on a missing `--sessions`, the no-`cost-log.jsonl` claim and the `build-lean` step-7
call site are all as documented.

**The two blockers below are new, and both are this delta's own.** One is a red lane the delta
introduced; the other is a machine-readable register three rounds have scored clean.

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | **Blocker** | `plugins/intake-toolkit/skills/intake/SKILL.md:54,56`, `plugins/intake-toolkit/skills/plan-interview/SKILL.md:61`, `plugins/audit-toolkit/skills/audit-history/SKILL.md:37` / **outside the AC set** | **CI is red at this head, and this commit caused it.** `lint-and-selftests` fails at step 14, `namespace direction check (docs/namespaces.md rule 3)`, with `::error::rule 3(a): a toolkit references the dev-pipeline: namespace`. The kind-4 fix replaced the bare `/dev-pipeline <issue>` form with the namespaced `/dev-pipeline:run-lean` / `:review-lean` — correct under namespaces rule 1 — but three of the four sites are inside **toolkit** plugins, where rule 3(a) bans the `dev-pipeline:` token outright with no exemption mechanism. Provenance is unambiguous: `git grep 'dev-pipeline:'` over the four toolkit roots returns **0 hits at the merge-base `33e6187`**, **0 at round 3's reviewed head `da021d7`**, and **4 at `f59de2f`**. The pre-namespacing form passed only because it carried no colon. Two things are owed, not one: the four lines (name the lane without the plugin prefix — the surrounding toolkit prose already does), **and the spec's kind-4 clause**, whose committed remedy is "replace with the namespaced form" with no rule-3(a) carve-out. Left as written, the next deletion re-derives the same red. Note the branch already edits this guard's block in `ci.yml` (the 3(b) pattern comment) and still tripped 3(a). |
| 2 | **Blocker** | `tools/mutation-baseline.tsv:27,38` / **AC-2** | **Two orphan `catalog::` baseline rows name guards this branch deleted.** `catalog::plan-lint-dup-traceability` and `catalog::verifyctl-targetrepos` point at catalog ids that existed at the merge-base (`tools/mutation-catalog.tsv:51,56` at `33e6187`, keyed on `skills/run/tools/plan-lint.sh` and `skills/run/verifyctl.sh`) and that **this branch removed**. The branch's `catalog::` baseline diff is empty — no `catalog::` row was touched in either direction. AC-2's letter is "No baseline, exclusion, pair-map, slow-suite or catalog row references a deleted guard; every re-keyed row lands in this same diff." These are the exception. **They will never self-heal, which is why the round owns them rather than the nightly:** `mutation-sweep.sh:1892` explicitly exempts `catalog::` from the "baseline row's guard no longer resolves" warn (a catalog row's guard is indirect), and `sid_guard()` returns *empty* for an id with no catalog row, so under the nightly's sharded run `swept_this_run ""` is false and no warn fires either. Unsharded, the surviving arm mislabels them "now KILLED", pointing the operator at the wrong remedy. Remedy: drop both rows in this diff, as the deleted guards' own generic rows already were. |
| 3 | Nit | `plugins/second-shift/skills/doctor/tools/doctor.sh:63-77` | The `--report` state excerpt widened from a four-field `jq` whitelist (`{ticketKey,status,currentStage,failureContext}`) to a raw `tail -n 40` of the newest progress record, inside a **paste-ready** bundle whose header states it "never pastes an UNredacted config". The excerpt is a separate section from the redacted-config one, so the contract is not literally broken, and the progress rows are gate-authored markers — but one row is not: `lean-gate.sh:2979` appends `check-frozen-files.sh`'s captured `$out` verbatim as `milestone-2 \| advisory \| …`. Bounded today (that output is this repo's own guard, and `:111` tells the user to review before posting), which is why this is a nit and not a warning. Worth one line of comment saying the excerpt is deliberately unredacted, so a future widening of what lands in a progress row is a visible decision. |

**Triaged away, and recorded here so a fifth round inherits the disposition.** The scope gate
returned `block` on two items. The first is finding 1 above, independently confirmed. The second —
that `docs/pipeline-manifesto.md`'s P1/P2 note records the pin **by reference** to `74562a0`'s
`Migration:` trailer rather than as the literal `v5.2.2` — is **not a finding**. The committed spec
pre-authorizes it in an open region at lines 19–23: "The concrete release literal is recorded in
the PR body and on the issue **at merge** (AC-3, ledger D-9/D-18) — writing a version literal today
would be stale and would contaminate the ablation's staged arm with post-pin improvements." AC-3's
own text puts the literal in the PR body (present: `v5.2.2`) and on the issue at merge (a declared
merge precondition), never in the manifesto. This is the **third consecutive round** the gate has
raised it — round 1 *prescribed* the pointer as its own remedy, round 2 accepted it, round 3
declined to re-open it. The gate scores against the issue body; the committed spec plus its D-9/D-18
ledger rows are the definition of done, and they settle it.

## Acceptance criteria

| AC | Verdict | Evidence |
| --- | --- | --- |
| **AC-1** — sweep green, shellcheck/jq clean, orphan check (all four kinds) | **satisfied** | Scored by AC-1's own named oracles, all green at `f59de2f`: `run all selftests` pass, `shellcheck` pass, `validate JSON` pass, and `selftests (macos, bash 3.2)` pass 5m51s. I re-ran all four orphan kinds myself (table above) and the discriminator sweep whole-tree. **The rule-3(a) red is a different step and a different guard**, named in none of AC-1's clauses — so it is a blocker *outside* the AC set (finding 1), not an AC-1 miss. Recording it that way rather than folding it in keeps the AC honest in both directions: the sweep genuinely is green, and the lane genuinely is red. |
| **AC-2** — no register row names a deleted guard | **unsatisfied** | Finding 2. Every other clause holds, and I re-derived the one the PR body argues rather than inheriting it: for each operator in `tools/mutation-operators.tsv` I extracted `doctor.sh`'s matched-site sequence at `da021d7` and at `f59de2f` — `detector` (2 sites) and `default` (12) are byte-identical, `logic` ordinals 1 and 2 sit at lines 28 and 56 **at both revisions** (the new sites land below), and the shifted `cmp-z` sequence is moot because `doctor.sh` carries no `cmp-z` baseline row. **No generic row needs re-baselining** — the PR body's conclusion is right. (Its stated counts differ slightly from mine — `logic` 57→59 here, not 63→66 — but the conclusion is independent of the count.) `mutation-sweep-pr` is green at this head with 50 verdicts computed, a real green rather than the zero-verdict shape. |
| **AC-3** — keep list, demotion register, D-3 override, pin in the body | **satisfied** | Unchanged from round 3. The pin literal `v5.2.2` is in the PR body with its re-confirm-at-merge caveat; the at-merge half is a declared merge precondition, which AC-3's wording licenses. See the triage note above. |
| **AC-4** — frozen-files green; breaking verb; `Changelog:` + `Migration:` | **satisfied** | `frozen files guard` and `changelog trailer guard` both pass at this head. PR title is `feat(dev-pipeline)!: …` — the load-bearing surface under squash merge. Nothing in this delta touches it. |
| **AC-5** — `capability-parity-check.sh` green, coverage clause vacuous | **satisfied** | Re-run by me at this head, not inherited: `note: … /skills/run/stages does not exist — the coverage clause is vacuous (expected once #348 has landed)` then `OK — 37 capability row(s)`. That note **is** the pass. |
| **AC-6** — every doc naming deleted machinery updated in the same diff | **satisfied** | The class rounds 1–3 chased is closed at the config layer, and my whole-tree discriminator sweep finds no present-tense claim about a live mechanism outside the four declared keep-classes. The three toolkit SKILL.md edits in finding 1 are *correctly* updated as documents — the defect there is that the chosen wording violates a different guard, which is why finding 1 sits outside the AC set rather than reopening AC-6. |
| **AC-7** — `visualCapture` retirement follows the dead-key pattern | **satisfied** | Unchanged; nothing in the delta touches it. `check-config-shadowing.sh`'s header, which round 3 found contradicting the spec's D-17 table, now states the two different reasons three rows left `CHECKS`, and matches the table. |

## Design fidelity

`not-applicable`. The spec disarms with `Design: none — no design.provider is configured for this
repo, and the diff has no UI surface`. Re-verified at this head rather than inherited: `design` and
`stageParams.webComponentGlobs` are both `null` in the effective config, and this delta is
`.md`/`.json`/`.sh`/`.tsv` only with no UI surface. The disarm is justified.

## Panel

Five reviewers selected, five returned — **no dark reviewer, no coverage gap**. `maintainability`,
`complexity`, `test-coverage` and `security` returned clean approves; `scope-completeness` returned
`block` (triaged above: one confirmed, one settled). Lineup reduced per the prior-round rule —
`db-reviewer`, `pipeline-reviewer` and `unit-test-mutation-reviewer` were not triggered (no DB, no
queue surface, no co-located specs). `a11y-reviewer` and the design-fidelity dimension were not
routed: no changed path matched `stageParams.webComponentGlobs` (unset ⇒ default
`apps/web/**/*.{tsx,jsx}`). Both blockers in this record are the lead's own, found before the panel
returned and confirmed independently by it in the first case.
