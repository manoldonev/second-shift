# lean review verdict — #359

verdict=approve
run_id: review-359-3
session_id: 6004acc2-fe30-45f7-a1c4-797da9b5651d
rounds: 3
pr: #430
reviewed_head: d8afaf2a5ab0be32a3b081448b86ca55051ee2f6
reviewed_patch_id: 6783b0a8d790e853c888756e9d1c2b3f83d4f90c
inherited_patch_id: 3818c4fc81ae77ce9c2dcf94e9c0050e914ccf07
inherited_from_verdict: 09f24ae5b5abfd2c9d591cc8883904d52b734c9f
fidelity: not-applicable
model: unknown

## Round 3 — `approve`

Range read: `3b9c810..HEAD` — the **full** branch diff, all 19 files, +2245/−186. `delta` printed
`FULL range — nothing verifiable to inherit`: the rebase moved the base out from under round 2's
`reviewed_patch_id`, so no narrower reading was available and **nothing was inherited by
reference**. The header's `inherited_patch_id` records the chain link to round 2's record, not a
range this round declined to read. Rounds 1 and 2 were read first from the committed record,
before the delta. Panel: security, performance, maintainability, complexity, test-coverage,
scope-completeness — all six returned, none dark, **zero findings** at or above the confidence
threshold.

Round 3 exists because the base moved: #429 and #422 landed, the branch was rebased with five
hand-resolved conflicts, and main was then merged again for #433. That is not the
"replays the branch unchanged" carve-out, so the round-2 approve was correctly voided. The
substantive question this round owes is therefore narrow and specific: **did the five conflict
resolutions preserve what rounds 1 and 2 approved, and did they resolve in the right direction?**
Each was checked by reconstructing the branch's contribution before and after the rebase and
diffing the two.

### Findings

| # | Sev | Where | Finding |
| --- | --- | --- | --- |
| 1 | Note | `plugins/dev-pipeline/skills/run/scenario-liveness-selftest.sh:945` | The `lean_seed_unattested()` run-id cache seed the rebase added is **not observed by any case**: removing exactly that line (probe P2, `diff`-confirmed to touch line 945 and nothing else) leaves the suite green. The line is correct and its own comment's claim — that the missing attestation row is then the only difference between the two seeded states — is true. But the PR body goes one word further and calls it "what the `(lean-entry)` leg depends on"; the leg does not depend on it. Defensive fixture parity, not coverage. No commit owed. |
| 2 | Note | PR body, "One commit beyond the rebase" | `b1855cc` fixed `(m1c)` on this branch; main fixed the same case independently in #433, and the `d8afaf2` merge took **main's** version whole. `git diff 3b9c810..HEAD -- lean-gate-selftest.sh` now contains no `(m1c)` hunk at all — the commit is real history but contributes nothing to the merged tree. The section reads as if it still does. Body-only; its fix is not a commit. |
| 3 | Note (carried) | `scripts/check-lean-chain.sh:369` | Round 1's unkilled defensive guard, declared left-as-recorded and unchanged. Still a note. |

Round 2's finding 3 (the sibling whole-file `grep` loop in the template selftest's step-env
check) is unchanged and stays a pre-existing note; it was not required to be strengthened.

### The five conflict resolutions, each checked

| Conflict | Resolution | Verified how |
| --- | --- | --- |
| `lean-gate-selftest.sh` — `(ea1)`-`(ea12)` beside `(pm1)`-`(pm7)` | both kept whole | branch's added case set is `(pm1)`-`(pm7)` + `(k)/(m)/(m2)/(q)/(r)`, unchanged from round 2; suite green, 3.2 green |
| `scenario-liveness-selftest.sh` — same add-vs-add | both kept whole | suite green under `/bin/bash` 3.2.57 and in CI's macos lane |
| `lockstep-manifest.tsv`, `mutation-catalog.tsv` | appended | branch's added rows are **byte-identical** to round 2's; only the hunk offsets moved |
| `SKILL.md` integrity line | branch's rewrite taken, main's `runs the rest` correction folded in | the two patches differ in exactly that phrase; file is 43 lines, inside the 60-line cap |
| the three lean helpers in `scenario-liveness-selftest.sh` | `unset RUN_ID GH_BOT` + main's **pinned** `CLAUDE_CODE_SESSION_ID` | **probe P1**: dropping the pin — which is what this branch's own pre-rebase resolution did — reds the suite (`rc=15`). The resolution is not merely plausible, it is the only one that works |

The merge itself (`d8afaf2`, "Update branch") is handled correctly by the declared patch-id arm
rather than tolerated: `merge-base(origin/main, HEAD)` is `3b9c810`, so the measured range is the
branch's own diff and base-side commits cannot move the hash. The gate's own comment at
`check-lean-chain.sh:600` predicted exactly this case.

### AC scoring — `docs/plans/second-shift-359-lean.md`

Every AC scored against the whole spec from a full-range read; nothing inherited.

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 payload selftest | **satisfied** | `lean-evidence-selftest.sh`, 466 lines, cases `(a)`-`(cc2)`. Each of the nine enumerated assertions maps to a named case: missing verdict `(g)`, run_id collision `(k)`, session_id collision `(l)`, zero markers under github `(m)`, non-Bot marker `(n)`, `ratified: no` `(w)`, `ratified: yes` with no URL `(x)`, absent/mismatched `reviewed_patch_id` `(r)`/`(s)`, non-lean branch `(b)`. One-fact-one-violation is `(h)` + `(h2)`. Hermetic (fixture seams only), green in the 65/65 sweep and under bash 3.2.57. |
| AC-2 template selftest | **satisfied** | 404-names-the-path, network-stays-WARN, violation-is-FAIL, non-lean-not-applicable, `fetch-depth: 0`, all six step-env vars. The scope clause is armed and block-scoped: I ran the suite's own `awk '/^permissions:/{f=1;next} f&&/^[^ ]/{f=0} f'` against the template and it returns exactly `contents: read` / `issues: read` / `pull-requests: read` and **zero** `: write` lines. |
| AC-3 delegation | **satisfied** | `check-lean-chain.sh` delegates classify + verdict + identity + intent-gap, and freshness on the declared-`reviewed_patch_id` branch only; the diff shows every replaced block **deleted**, not shadowed. `(Y1)` pins the no-bot-marker refusal, `(Y5)` pins an unreachable payload as `rc=2`. Confirmed **live, not just fixtured**: this head's `pr-gates` log interleaves `[lean-evidence]` lines inside the `[lean-chain]` run, including a real API-backed identity check. |
| AC-4 writer | **satisfied** | `cmd_mark` posts one bot marker carrying `run_id` + `session_id` + the stage token, is idempotent **by identity** (`(pm2)`), still posts for a second session `(pm3)`, is not suppressed by a prefix-matching id `(pm4)` or a human marker `(pm5)`, and skips under jira. `cmd_5` calls it on both adapter paths. Live: the boundary reported the verdict identity "distinct from all 1 bot marker(s) on this PR". |
| AC-5 config resolution | **satisfied** | `(z1)` config-derived, `(z3)` env-overrides-config, `(z2)` the pipeline-namespace exclusion, `(f)` the mutual non-prefix refusal. Both resolution paths driven. |
| AC-6 jira degrade | **satisfied** | `(aa1)` the reduced-strength line is printed, `(aa2)` a jira fixture with a missing verdict still exits 1 — both halves. |
| AC-7 mutation baseline | **satisfied** | Verified in **CI's enforcing lane on this exact head**, which is the authority a local run only approximates: `lint-and-selftests` green, 48 mutants, 0 cached, `lean-evidence 11/8/3 · lean-gate 15/12/3 · ci-check 10/5/5 · check-lean-chain 12/7/5`. My independent local run at `MUTATION_SWEEP_CACHE=0` reproduced all four triples exactly. All 16 survivor ids are baseline-present, zero unbaselined. The new `ci-check-evidence-path` catalog row is **killed** (it is absent from the survivor set while its sibling `ci-check-lint-path` is present), and the sibling's re-anchor is in the same diff. |
| AC-8 doc | **satisfied** | `SECOND-SHIFT.md` documents the arm, the required-status-check wiring, the fail-closed posture, all three read scopes with the replaces-wholesale rule, and the jira degrade; `SKILL.md` step 7 names the `mark` call; `lockstep-manifest.tsv` carries the `lean-pr-marker` row (writer↔reader) plus the `lean-branch-prefix` row and two argued DROPPED entries. `check-lockstep-pairs` 19/19. |
| AC-9 critic | **satisfied** | All **nine** commits carry a `Changelog:` trailer, checked per-commit rather than only via the grep-anywhere script. A scan of the full branch diff for consumer repo names, org names and company ticket-key shapes returns nothing; fixtures are `acme-*`. |

### Design fidelity

`not-applicable`. The spec's `## Design` section carries the explicit `Design: none — this is
shell/CI plumbing with no rendered surface` disarm, and the repo's committed config declares no
`design.provider` (`.design` is `null`), so the disarm is justified rather than convenient and
steps (i)-(iii) do not apply. Unchanged from rounds 1 and 2.

### Verification I ran (from this checkout of the PR head)

- Full **65-suite sweep, no `SKIP_STRESS`**, with `CLAUDE_CODE_SESSION_ID` / `RUN_ID` / `GH_BOT`
  unset — **65/65 `rc=0`**, per-suite exit codes captured individually, not read off a summary line.
- The five changed suites re-run under the system **`/bin/bash` 3.2.57** — 5/5 `rc=0`. CI's macos
  lane has since finished green on this head, which confirms rather than replaces it.
- **3 hand probes, 2 killed, 1 survivor recorded as finding 1** — each `cmp`-checked so an
  unchanged file would score PROBE INVALID rather than SURVIVED, and the tree verified clean after.
- `shellcheck -e SC1091,SC2015,SC2181` clean on all nine changed shell files; both YAML files
  parse; `check-lockstep-pairs` 19/19; `check-changelog-trailer` `rc=0`; `check-frozen-files`
  clean apart from its expected `.github/workflows/**` advisory.
- Uncached diff-scoped mutation sweep, 52 verdicts, `rc=0`, no RED (AC-7 row above).

### The boundary's own verdict on this head

`pr-gates` is **red, for exactly one reason**, and it is the reason this round exists: the
committed record still declares round 2's `reviewed_patch_id 3818c4fc81ae` while the branch now
hashes to `6783b0a8d790`. Every other arm passes in that same run — spec, delegated verdict, the
issue-side claim, the delegated PR-marker identity against a real bot marker, the inheritance
chain, and the ratified intent gap. `lint-and-selftests` and `selftests (macos, bash 3.2)` are
both green. Round 3's record is what clears the one red.

### Strengths

- The `SKILL.md` conflict was resolved on the axis that matters. Main edited the sentence for a
  count it had invalidated; this branch rewrote the same sentence for *where integrity lives*.
  Taking the rewrite whole and folding in main's correction is the resolution that loses neither,
  and it was checked against `lean-reconcile.sh`'s actual arm count rather than asserted.
- The helper conflict resolved **against** the branch's own earlier fix, and that was right.
  Unsetting `CLAUDE_CODE_SESSION_ID` and pinning it solve the same ambient-leak problem, but only
  pinning survives #422's attestation, which reads *that* session's ledger. Probe P1 turns that
  from a judgment call into a measured one: the branch's original resolution reds 15 legs.
- Every conflict resolution is stated in the PR body with its reasoning, including the two that
  needed judgment and the ten call sites that were re-audited as a consequence. That is what made
  this round a verification exercise instead of a re-review.
- The one commit added beyond the rebase was added for a reason the mutation lane made concrete —
  a guard whose paired suite is red scores as an unrunnable pair, which had left `lean-gate.sh` at
  `applied=0`. It now scores 15/12/3.
