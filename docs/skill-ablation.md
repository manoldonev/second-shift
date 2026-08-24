# Skill-vs-bare-session ablation — results and verdicts

**Measured 2026-08-24.** #644, parent #284. The thresholds this report is scored against were fixed
in [`docs/skill-ablation-pre-registration.md`](skill-ablation-pre-registration.md) before any result
existed; that file has not been edited since. Raw arm outputs are under
[`docs/plans/skill-ablation/`](plans/skill-ablation/), one file per session, verbatim.

**The pre-registration names `docs/skill-ablation/`; the evidence landed at
`docs/plans/skill-ablation/`, and the pre-registration was deliberately NOT corrected.** It has
exactly one commit, `f174f1f`, and keeping it that way is worth more than a right path inside it —
a pre-registration edited after results exist is not one. The relocation is recorded here instead.

They sit under `docs/plans/` deliberately. `scripts/check-fail-open-shapes.sh` excludes that path as
"the run-artifact archive: … never executed, so a shape in it is quoted shell, not a call site", and
a verbatim session transcript quoting `| grep -q` is exactly that. Filing the evidence where the
existing exclusion already reaches costs no guard edit and no new selftest case; adding a second
excluded directory would have cost both. A report on machinery growth should not grow machinery to
land.

```bash
git log --format='%h %ad %s' --date=short -- docs/skill-ablation-pre-registration.md  # one commit, first
git log --format='%h %ad %s' --date=short -- docs/plans/skill-ablation/               # all later
```

## Verdicts

| # | surface | metric | result | verdict |
| --- | --- | --- | --- | --- |
| 1 | `build-lean` SKILL (48 lines) | mandated-artifact coverage | bare covers 3 of 9 discriminating items | **cut-to-delta** |
| 1b | the five milestone gates | *inherited* — `docs/gate-ablation.md` | 66% of firings adjudicated `unchanged`; all six keep-earners re-run at the merge boundary | inherited, not re-collected |
| 2 | `review-lean` SKILL (127 lines) | recall of ground-truth blockers | bare **4 of 5**, and found 2 real defects the lane's own review missed | **cut-to-delta** |
| 3 | `plan-interview` + `interviewing-baseline` (312 lines) | recall of operator-ratified decisions | bare **6 of 20** | **keep** |
| — | `intake-orchestrator` (711 lines) | — | not reached by any metric here | **not adjudicated** |

No comparison exits `undetermined`. **This slice executes no deletion**, and §5 states why that is
the evidence-supported action rather than a flinch.

---

## 1 — `build-lean` and the milestone gates

### The confound the registered protocol did not anticipate, and what was done about it

The registered protocol put a bare session in the repository worktree. **In this repository the
kit's own prose is a file in that worktree**, and both bare sessions read it: the C1 plans cite
`bash G entry <N>`, `ledger-carry-forward.sh`, "4-column plan rows" and "the disarm state-locks the
moment milestone 3 arms" — vocabulary that exists nowhere but `build-lean/SKILL.md`. Under the
registered scoring that run covers **9 of 9** discriminating items, which the registered threshold
reads as `delete`.

That number measures a session that read the skill, not a bare one. So a **disclosed, post-hoc
sensitivity run** was added: the same tickets, the same prompt, in a checkout with every
`plugins/**/SKILL.md` and `plugins/**/agents/*.md` deleted and all other code — `lean-gate.sh`
included — left in place.

| item | registered run | ablated run | in both ablated? |
| --- | --- | --- | --- |
| M1 committed spec with numbered `AC-n` | ✓ | ✓ | ✓ |
| M2 Decision Ledger with provenance | ✓ | ✓ | ✓ |
| M3 lane worktree on a lane branch | ✓ | ✓ | ✓ |
| M4 commits under the bot identity | ✓ | ✗ ✗ | ✗ |
| M6 ready PR with `Closes #N` | ✓ | ✓ / ✗ | ✗ |
| M7 cost block from the progress record | ✓ | ✗ ✗ | ✗ |
| M8 PR marker carrying the run identity | ✓ | ✗ ✗ | ✗ |
| M9 review authored outside the session | ✓ | ✓ / ✗ | ✗ |
| M10 close-out | ✓ | ~ / ✗ | ✗ |

(M5, the `Changelog:` trailer, is mandated by `CLAUDE.md` and was registered as non-discriminating.)

**The verdict taken is the conservative one — `cut-to-delta`, not the `delete` the registered
threshold licenses.** Refusing to execute a deletion on evidence that the thing being deleted was
sitting in front of the arm is not rubric-loosening; it never lets an incumbent survive on a soft
bar, it only declines to act on a measurement that has been shown to be measuring something else.

### What the ablated run actually shows

The three items bare still covers, it covers by reading `lean-gate.sh` — the ablated sessions cite
`lean-gate.sh:2663`, `:890`, `:1852` by line and derive the spec path, the ledger schema and the
worktree from the gate's own code. One of them even noticed the ablation ("if the deleted
`SKILL.md` files red the suite…").

So the finding is structural, and it is the more interesting half:

> **The enforcement machinery teaches the process.** Where a gate reads an artifact, a session
> re-derives the obligation from the gate's source without the prose. The prose earns its keep only
> where no gate is readable — M4, M6, M7, M8, M9, M10.

### The caveat that bounds the cut, and blocks executing it here

This repository is the canary, so `lean-gate.sh` is *tree source*. **In a consumer repo it is an
installed plugin, not a file in the working tree**, and a bare session there re-derives none of
M1–M3. Generalising "bare rediscovers the spec, the ledger and the worktree" to consumers is
unwarranted from this evidence, and cutting those three items would strip shipped function to tidy
the dogfood canary — the exact consumer-capability trap #642 was warned off.

**Successor — #671, arm 1.** Re-run C1's ablated arm in a consumer-shaped checkout (kit installed,
not in tree) to localise the cut. Until that exists, the cut is recorded and not executed.

---

## 2 — `review-lean` vs. a bare session review

Ground truth: blockers the lane's own round-1 record raised, the branch then fixed, and round 2
verified closed — defects that reached the PR *and* changed what shipped.

| sample | ground-truth blockers | bare found | detail |
| --- | --- | --- | --- |
| C2-a #654 | 1 | **0** | miss on mechanism |
| C2-b #657 | 2 | **2** | both, same mechanism and consequence |
| C2-c #660 | 2 | **2** | both, one near-verbatim |
| | **5** | **4** | recall **0.80** |

Registered threshold: 4/5 → `cut-to-delta`.

### The one miss, and why it is scored a miss

On #654 the lane's blocker was that the enumerator's command-position class **omits
keyword-preceded calls**, so `else envfail …` at `lean-gate.sh:420` sits outside the denominator.
The bare session found a *different* hole in the same guard — refusal sites that use **no declared
primitive at all** (`require_ticket_still_open → exit 7`) — with the same consequence and a
different mechanism. The registered rule says same file plus different defect is a miss, so it is
scored a miss. It is also a finding the lane's review did not make.

### What bare found that three rounds of lane review did not

On #660 the bare session raised two blockers absent from the lane's round-1, round-2 and round-3
records. One is live on `main` today. `build-lean/SKILL.md:32` says, in one sentence:

> …asserts milestone 5 — **which a MERGED PR satisfies as well as an open one** (#642), so
> close-out stays reachable after a merge — … But **leave the claimed label alone**: **milestone 5
> requires an open PR**, so review is still in flight and the label is correct.

A merged PR satisfies milestone 5, and milestone 5 requires an open PR. This is the checklist a
build session executes, and the contradiction survived a three-round independent review of the very
PR that introduced it. A bare session found it in seven minutes.
Filed as **#670**; not fixed here, being outside this slice's AC set.

### Recorded separately, as registered

P10 independence — the verdict is authored by a session that is not the build session — is a
property of the **lane**, and no bare-arm review can exhibit or refute it. `cut-to-delta` here
addresses the skill's 127 lines of prose. It says nothing about the separate-session boundary,
which this slice did not measure and does not touch.

**Successor — #671, arm 2.** The delta is not localisable to particular lines from this evidence.
Measuring which of the 127 lines carries it is the follow-up; until then no line is cut.

---

## 3 — `plan-interview` / `interviewing-baseline`

Reference set: the `user-answered` rows of three committed lean-spec Decision Ledgers — decisions an
operator answered and a build consumed, so an external party validated them as load-bearing.

| sample | reference rows | bare recalled |
| --- | --- | --- |
| C3-a #650 | 7 | 1 |
| C3-b #643 | 7 | 1 |
| C3-c #597 | 6 | 4 |
| | **20** | **6** — recall **0.30** |

Registered threshold: < 10/20 → **`keep`**.

**The confounds all run toward bare, which is what makes this robust.** The kit arm's 100% is
inadmissible by registration and is not used. The issue bodies handed to the bare arm are the
*current* ones, amended after the interviews, so some reference answers were already in the text it
read. And it still recalled fewer than a third.

### The delta, named

Bare surfaced 11–14 decisions per ticket, heavily codebase-anchored and frequently sharper than the
reference — that `.claude/pipeline-state/` is gitignored so every committed figure is a
transcription; that `: > "$log"` destroys the prior launch's transcript; that a third candidate
mechanism made a whole causal story irrelevant. Its misses are not random:

> The bare arm surfaces **design** decisions. The kit's elicitation surfaces **scope-boundary**
> decisions — what lands first, whether an item may share this PR, whether this session may amend a
> frozen criterion, what the filing rule is. Nine of the fourteen reference rows bare missed are
> that class, and five of those are `DEPARTURE` rows: the interview's job of saying *this is not in
> this slice*.

That is the surviving delta, and it is what `keep` is keeping.

### Not adjudicated

`intake-orchestrator`, 711 lines and the largest skill in the tree, produces **decomposition**, not
a ledger. This metric does not reach it. It is recorded as unmeasured rather than credited with a
pass, and filed as **#672** — the highest-value target for the next slice.

### Rows no pre-flight session could reach

Three of the twenty reference rows record decisions surfaced *after* execution began — a
contradiction found by doing the audit, a blocker from review round 1, and the refusal that
contradiction exposed. A pre-flight arm cannot recall those. Recall over the 17
pre-flight-discoverable rows is **6/17 = 0.35**, still well under the registered 0.50 threshold, so
the verdict does not move. Reported as a sensitivity, not a
re-scoring: the registered denominator is 20 and it governs.

---

## 4 — P6 bases (AC-4)

`docs/pipeline-manifesto.md` P6 obliges a *re-measured* basis rather than an inherited one. Twenty-six
skills ship. **Three surfaces were measured, covering four of them. The other twenty-two were not, and
none may be credited with a pass.**

| skill | lines | measured | basis | date |
| --- | --- | --- | --- | --- |
| `dev-pipeline/build-lean` | 48 | C1 | cut-to-delta; carries M4/M6/M7/M8/M9/M10, where no gate is readable | 2026-08-24 |
| `dev-pipeline/review-lean` | 127 | C2 | cut-to-delta; bare recall 0.80 on ground-truth blockers, delta not yet localised | 2026-08-24 |
| `intake-toolkit/plan-interview` + `interviewing-baseline` | 312 | C3 | **keep**; bare recall 0.30, delta is the scope-boundary/DEPARTURE class | 2026-08-24 |
| `intake-toolkit/intake-orchestrator` | 711 | — | **unmeasured — no basis** | — |
| `intake-toolkit/intake-interviewer` | 279 | — | **unmeasured — no basis** | — |
| `review-toolkit/review-lead` | 446 | — | **unmeasured — no basis** | — |
| `second-shift/onboard` | 472 | — | **unmeasured — no basis** | — |
| `dev-pipeline/pr-revision` | 385 | — | **unmeasured — no basis** | — |
| `design-toolkit/figma-faithful` | 300 | — | **unmeasured — no basis** | — |
| the remaining 16 | — | — | **unmeasured — no basis** | — |

The measured surfaces total **487 lines of 4,951**. That ratio, not any single verdict, is this
report's headline: **90% of the shipped product still has no re-measured basis against the current
model generation.**

---

## 5 — Why no deletion is executed

The ticket's reversible default is delete-in-slice when the deletion is self-contained. Neither
surviving cut qualifies, and the reasons are evidence, not caution:

- **C1's cut is not self-contained.** Its basis is that a session re-derives M1–M3 from tree-source
  `lean-gate.sh`. That is false in a consumer repo, where the gate is an installed plugin. Executing
  it would strip shipped function on a repo-local artefact.
- **C2's cut is not localisable.** Recall 0.80 says the 127 lines are at best a tie; it does not say
  which lines carry the 0.20. Cutting by guess would be the thing this slice exists to stop.
- **C3 is a `keep`.**

So AC-5 is satisfied vacuously — no deletion, therefore no orphan — and it is recorded that way
rather than as a green sweep that proves something it does not. The successors are filed: **#670** (a live
self-contradiction in a shipped checklist, found by the bare arm), **#671** (localise both cuts) and
**#672** (`intake-orchestrator`, 711 unmeasured lines).
