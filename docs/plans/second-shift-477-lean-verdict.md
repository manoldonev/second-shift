# lean review verdict — #477

verdict=approve
run_id: review-477-1
session_id: a71035d8-ec4e-43a1-b766-9e32c363ba03
rounds: 1
pr: #481
reviewed_head: b80065f36846ed10a03b30508f927fd59cbca543
reviewed_patch_id: 2818310647718b0af702ab44e097fba7d3ec9abb
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

Round 1 over the full branch diff (`3849ef5..HEAD`, 9 files, +533/-103) — no verifiable prior
round to inherit, so nothing is carried by reference.

Panel: security, performance, maintainability, complexity, test-coverage, scope-completeness.
All six returned `approve` with zero findings; none went dark. a11y + design-fidelity were not
routed — no changed path matches `stageParams.webComponentGlobs` (default
`apps/web/**/*.{tsx,jsx}`); the diff is shell, skill prose, docs, JSON fixtures and a TSV.

The deliverable here is the AC-1 oracle, so the review's weight went into probing it rather than
into re-reading prose. Ten hand-mutants against `config-grill.sh` and five against the oracle
itself, the latter run from an isolated copy of `tools/` whose baseline was confirmed green first
(a mutated selftest run from the scratchpad reds all 75 cases on `$HERE/config-grill.sh` not
existing — that is a broken harness, not a score).

## Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | Warning | `config-grill-selftest.sh:767-778` | Control 4 ("comment immunity") does not fail when either mechanism it names is removed. |
| 2 | Warning | `config-grill-selftest.sh:726-735` | The function-body closure arm has no sentinel, despite "one per capture arm". |
| 3 | Suggestion | `config-grill-selftest.sh:686-708` | `+=`, heredoc and `printf -v` string construction escape the closure. Latent only. |
| 4 | Suggestion | `docs/onboarding.md:251`, `config-grill.sh:288,470` | "executable `tools/mutation-sweep.sh`" overstates a contract that tests `-f` and runs `bash`. |

**1 — Control 4 is vacuous against its own mechanism.** The spec says it "pins the design as
call-site-scoped rather than a whole-file grep". Two mutations say otherwise, each leaving all
eight oracle checks green:

- deleting the comment strip (`| grep -vE '^[[:space:]]*(#|$)'`, line 705) — the control's own
  mutant still passes, because the comment it injects (`# Read-only, no network, bash-3.2 safe.`)
  sits nowhere near a call site or a pulled assignment, so it is out of the corpus for a reason
  unrelated to the strip;
- replacing the entire awk capture with `corpus="$(cat "$src")"` — i.e. degrading the oracle to
  exactly the whole-file grep the control claims to forbid. AC-1 stays green because the comment
  strip (still present) removes the five comment-borne banned tokens on the first loop pass.

Neither is an unmet AC: the oracle enumerates via static call-site scan today and enforces AC-1
today. It is the *control* that cannot fail, in the one place the spec argues most explicitly that
it can.

**2 — Two sentinels, three arms.** The corpus grows through a direct call-site literal, a
`NAME=` assignment, and a `name() {` function body. Control 2 covers the first two. Deleting the
function-body pull (line 701) leaves every check green, silently dropping `waiver_hint()`'s
sentence — appended to nearly every remediation — from the corpus. Confirmed live today: a banned
token injected into that body IS caught.

**3 — Latent enumeration gaps.** `xmsg+=" …"`, a `$(cat <<EOF …)` heredoc, and `printf -v` each
carry a banned token into an emitted string and each survives. No such construction exists in
`config-grill.sh`, so nothing is currently uncovered — worth one line at the assertion naming the
idioms the closure supports, so a future edit cannot open the gap silently.

**4 — "executable" is stronger than the contract.** `lean-gate.sh:2349` and `config-grill.sh:274`
both test `-f`, and the gate invokes `bash "$sweep"`; a non-executable sweep runs. The consumer
doc is the place this matters — a reader can conclude a non-executable file is skipped.

**Upgrade note, not a finding.** A consumer with `unitTestScope` *and* `testFile` set and no sweep
previously produced no mutation finding at all, and now produces an unwaived
`T4.mutation-plumbing` FAIL. D-20's id continuity protects consumers who already carried the
finding, not this population. This is the ticket's intended message, and the remediation is honest
that silencing it needs both `gates.mutation: false` and a null scope — recorded so the upgrade
behavior is a conscious one.

## Acceptance criteria

**AC-1 — satisfied.** The universal assertion exists in `config-grill-selftest.sh`, passes, and is
live rather than decorative. Seven independent hand-mutants against `config-grill.sh`, all killed:
a brand-new `add_finding` / `add_unadopted` / `add_noteval` call site (so enumeration is not
anchored to the sites that happen to exist), a token on the `mut_gates=` indirect literal, on the
`pr=` literal inside `t2_key`, on the `t2_key` benefit argument forwarded into `$pr`, and inside
`waiver_hint()`'s body. Control 1 reports 14/14 distinct call sites and does fail — dropping
`add_noteval` from the capture arm reports 7 uncaptured. Control 2's indirect sentinel and control
3's indirect mutant both fail when the variable-closure arm is removed.

**AC-3 — satisfied.** Both onboard sites are reworded and `plugins/second-shift/skills/onboard/SKILL.md`
now carries zero matches for `[Ss]tage[ -][0-9]`, `stages/[0-9]`, `visualCapture`, `visual capture`
or `screenshot`. Question 4 elicits the repo-carried sweep with its invocation, its rc semantics
and its SKIPPED-when-absent behavior, and frames `gates.mutation` / `unitTestScope` as
rollback-lane keys that buy no sweep. The provenance + re-onboard carry-forward clause keeps its
mechanical force ("overwriting one is a silent config deletion that `config-lint` still passes")
while dropping the staged-gate naming, and the old provenance literal is pinned nowhere in the
tree. Emitted config shape unchanged: `testFile` and `unitTestScope` are still emitted as explicit
`null`, still carried forward on a re-onboard.

**AC-4 — satisfied.** `T4.mutation-plumbing.$REPO_ID` is byte-identical across the semantic change.
`T4.testfile-plumbing` and `T2.visualCaptureTriggerGlobs` are gone, with a `for gone in …`
negative control asserting neither can return, and no dangling reference to either id survives
anywhere outside `config-lint`/`check-config-shadowing`, which are #348's. `T4.design-liverender`
keeps its predicate (`-n "$DESIGN_PROVIDER" && -z "$DESIGN_LR"`) and the three
`T1.extension-points` proposals keep theirs; only the naming moved. The new
`T1.mutation-sweep.$REPO_ID` advisory rides in `unadopted[]`, and the suite pins the tier's whole
contract: it never leaks into `findings[]`, it is silent with no `test` lane and silent when the
repo carries a sweep, it fires alongside the finding, and *both* waiver directions leave the other
row standing. The declaration halves are pinned separately with the other confounder neutralized —
`unitTestScope` set under `gates.mutation: false`, and each `gates` state under a null scope — plus
the combined case asserting exactly one finding, and `gates: false` + null scope as the silent
off-switch.

**AC-8 — satisfied.** Enumeration is a static call-site scan with the deny-list documented at the
assertion and no per-finding exemptions; `T2.webComponentGlobs` and `T2.formatGlob` pass untouched.
Re-points all verified: the grill's trigger-2 negative control and the waiver UNwaived control are
re-keyed off the deleted ids, `doctor-selftest.sh`'s pinned literal is now
`T4.mutation-plumbing.app` with the same fixture still producing one unwaived finding and rc=1,
both doctor fixtures' waiver reasons are reworded to the seam, and the `lockstep-manifest.tsv`
DROPPED entry drops its `triggerGlobs` restatement while keeping the reasoning for the two that
remain. `docs/onboarding.md` carries the sweep CLI contract with all four clauses — invocation
shape, rc semantics, absent-is-a-printed-skip, deterministic/no-model-call. See finding 4 on one
word of that contract. The scope reviewer's note that the re-baseline obligation is vacuous here
holds: no `mutation-baseline.tsv` row exists for any guard this diff edits.

## Verification

Run from the reviewed head, `env -u CLAUDE_CODE_SESSION_ID`:

- `shellcheck -e SC1091,SC2015,SC2181` clean on `config-grill.sh`, `config-grill-selftest.sh`,
  `doctor-selftest.sh`.
- `config-grill-selftest.sh` — all green, oracle block included (14/14 closure, both sentinels,
  AC-1, both mutants, comment immunity).
- `doctor-selftest.sh` — all green, with the re-pointed `T4.mutation-plumbing.app` literal.
- The grill against the dogfood repo and its real config: zero findings, no new advisory — the
  canary carries `tools/mutation-sweep.sh`, so neither tier fires and this change does not red it.
- CI on the head: `lint-and-selftests`, `mutation-sweep-pr`, and `selftests (macos, bash 3.2)` all
  pass. `pr-gates` is red pre-handoff by construction — it is the absent verdict record.

**Design fidelity: not-applicable.** The spec disarms with `Design: none — the change is shell,
selftest and docs text; no rendered surface, no route`. Justified rather than assumed: the repo's
config declares no `design` block, so there is no provider to make the disarm suspicious, and the
diff touches no rendered surface.

**Verdict: approve.** No blockers. The four findings above are warnings and suggestions about the
strength of the oracle's controls and one word of consumer prose; none of them leaves an
acceptance criterion unmet, and none is worth a round.
