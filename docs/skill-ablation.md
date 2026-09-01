# Skill-vs-bare-session ablation — results and verdicts

**Measured 2026-08-24**, with §1's arm-1 re-measurement added **2026-09-01** (#746). #644, parent #284. The thresholds this report is scored against were fixed
in [`docs/skill-ablation-pre-registration.md`](skill-ablation-pre-registration.md) before any result
existed; that file has not been edited since. Raw arm outputs are under
[`docs/plans/skill-ablation/`](plans/skill-ablation/), one file per session, verbatim.

**The pre-registration names `docs/skill-ablation/`; the evidence landed at
`docs/plans/skill-ablation/`, and the pre-registration was deliberately NOT corrected.** It has
exactly one commit, `f174f1f`, and keeping it that way is worth more than a right path inside it —
a pre-registration edited after results exist is not one. The relocation is recorded here instead.

They sit under `docs/plans/` deliberately. `scripts/check-fail-open-shapes.sh` excludes that path as
"the run-artifact archive: … never executed, so a shape in it is quoted shell, not a call site", and
a verbatim session transcript quoting a piped `grep -q` is exactly that. Filing the evidence where the
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
| 1 | `build-lean` SKILL (48 lines) | mandated-artifact coverage | on a consumer-shaped substrate bare covers **3 and 4 of 9** (#746); **no item is cut-eligible** | **cut-to-delta, empty cut** |
| 1b | the five milestone gates | *inherited* — `docs/gate-ablation.md` | 66% of firings adjudicated `unchanged`; all six keep-earners re-run at the merge boundary | inherited, not re-collected |
| 2 | `review-lean` SKILL (127 lines) | recall of ground-truth blockers | bare† **4 of 5**, and found 2 real defects the lane's own review missed | **cut-to-delta** |
| 3 | `plan-interview` + `interviewing-baseline` (312 lines) | recall of operator-ratified decisions | bare **6 of 20** | **keep** |
| — | `intake-orchestrator` (711 lines) | — | not reached by any metric here | **not adjudicated** → #672 |
| — | `intake-interviewer` (279 lines) | — | registered in scope; no sample ran its path | **not adjudicated** → #672 |

† **Comparison 2 ran a bare session, not the built-in `/code-review` the ticket names.** The
departure is declared in §2 with its direction of bias; the verdict is unaffected, the
`/code-review` comparison is unmeasured, and it is routed to #671 arm 2.

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

**Successor — #671, arm 1. Run, and reported below.**

### Arm 1 (#746) — re-measured where the gate is not tree source

**Measured 2026-09-01**, on the substrate
[`docs/skill-ablation-addendum.md`](skill-ablation-addendum.md) §A registers. Same two samples, same
prompt, same frozen scoring rule. Four arms × two samples; the realised substrate, the invocation and
the per-session provenance counts are in
[`c1-build/consumer-substrate.md`](plans/skill-ablation/c1-build/consumer-substrate.md), the per-item
scores in [`c1-build/scoring.tsv`](plans/skill-ablation/c1-build/scoring.tsv), and the transcripts are
committed verbatim as `c1-build/consumer-<arm>-<n>-plan.md`.

| arm | kit in the working tree | kit in the object store | `docs/plans/` | bare covers (of 9) |
| --- | --- | --- | --- | --- |
| A1-max — *registered* | no | **yes** | yes | 9 / 9 |
| A1-min — *registered, conditional* | no | **yes** | no | 9 / 9 |
| A1-sealed — *post-hoc* | no | no | yes | 3 / 4 |
| A1-sealed-min — *post-hoc* | no | no | no | 1 / 0 |

**The registered pair cannot answer, and the reason is a construction defect, not a result.**
Deleting `plugins/` from the working tree leaves the whole kit readable with
`git show HEAD:plugins/dev-pipeline/skills/build-lean/SKILL.md`, and all four registered-arm sessions
read it there — none of them read anything from the plugin cache. Every item they cover is therefore
provenance `tree`, which `docs/skill-ablation-addendum.md`:201-222 already reads as **inconclusive**;
A1-min was the registered remedy for `tree` provenance and inherits the same hole. So both registered
arms are reported in full and neither licenses a cut. Two disclosed post-hoc arms — the kit removed
from history as well as from the tree — are what carry the finding, labelled exactly as the sensitivity
run above is.

**The cut list (AC-6).** Applying the registered reading — an item bare **covers** is cut-eligible,
an item bare **misses** is kept; a split at n=2 is `undetermined`; and A1-min's rule that coverage
surviving only where the repository's own artifacts are present is the repository's competence, not
the session's:

| M-item | sealed 636 / 647 | sealed-min 636 / 647 | disposition |
| --- | --- | --- | --- |
| M1 committed spec with numbered `AC-n` | ✓ / ✓ | ✗ / ✗ | **inside the delta — kept** |
| M2 Decision Ledger with provenance | ✓ / ✓ | ✗ / ✗ | **inside the delta — kept** |
| M3 lane worktree on a lane branch | ✗ / ✓ | ✗ / ✗ | **undetermined** — not cut-eligible |
| M4 commits under the bot identity | ✗ / ✗ | ✗ / ✗ | **inside the delta — kept** |
| M6 ready PR with summary, spec link, `Closes #N` | ✗ / ✗ | ✗ / ✗ | **inside the delta — kept** |
| M7 cost block from the progress record | ✗ / ✗ | ✗ / ✗ | **inside the delta — kept** |
| M8 PR marker carrying the run identity | ✗ / ✗ | ✗ / ✗ | **inside the delta — kept** |
| M9 review authored outside the session | ✓ / ✓ | ✓ / ✗ | **undetermined** — not cut-eligible |
| M10 close-out | ✗ / ✗ | ✗ / ✗ | **inside the delta — kept** |

**Nothing is cut-eligible.** C1's verdict stays `cut-to-delta` — the frozen table makes `keep`
unavailable — but the delta is now measured to be the whole 48-line surface, so the cut it names is
**empty**. That is the strongest statement the frozen threshold permits, and it is a stronger result
than the caveat it replaces: §1 suspected M1–M3 would not survive a consumer checkout, and the
measurement says neither those three nor the other six do.

M1 and M2 are the interesting rows. Bare names a committed spec and a Decision Ledger whenever
`docs/plans/` is present — it is reading this repository's own 17 committed lean specs and citing
`scripts/check-lean-chain.sh`'s requirements by line — and names neither when they are gone. That is
exactly the A1-min hypothesis, confirmed on the sealed pair.

**Nothing read the prose.** All four sealed sessions had the installed cache inside their allowlist;
they walked to `lean-gate.sh` and `orchestrate-lean.sh` and **not one opened
`build-lean/SKILL.md`**, though one listed the directory it sits in. §1's structural finding holds on
this substrate and sharpens: a session re-derives obligations from a gate it can *read*, and an
installed plugin's gate is reachable — but the prose is not what it reaches for.

**Two apparatus findings, reported and not acted on.**

- The frozen recipe's bracketed `--allowedTools "Read,Grep,Glob"` does not restrict the tool surface
  under `claude -p`; Bash is available and every arm here is Bash-dominated. The check is one command
  (`consumer-substrate.md`, "The bracketed `--allowedTools` … is inert"). This binds §1's already-scored
  runs too.
- **The same object-store leak reached §1's own sensitivity run.** Its ablated arm for #647 recovered
  `build-lean/SKILL.md` with `git show HEAD:` — the confound that run was added to remove. Re-scoring
  §1 is outside #746's scope, so it is named here rather than corrected:

  ```bash
  jq -r 'select(.message.content)|.message.content[]?|select(.type=="tool_use")
         |((.input.command // .input.file_path // .input.pattern)|tostring)' \
    ~/.claude/projects/-private-tmp-ablation-644-wt-abl-647/*.jsonl | grep 'git show HEAD:'
  ```

**The cut stays unexecuted, and now on measurement.** #671's arm 1 was filed to localise it; the
localisation returns an empty cut list, so there is nothing for a successor to delete.

---

## 2 — `review-lean` vs. a bare session review

### Departure — the comparator is not the one the ticket names

Issue #644's scope item 2 reads **"`review-lean` vs. the built-in `/code-review`"**. That is not
what ran. Each arm was a plugin-free session given the generic instruction at
[`c2-review/prompt-template.txt:5`](plans/skill-ablation/c2-review/prompt-template.txt) — *"Review
this change as you would any PR you were asked to review before merge"* — with no review skill,
built-in or otherwise, invoked. The substitution entered at registration time: the
pre-registration's own comparison-2 heading already reads "vs. a bare session review", and neither
it nor this report flagged the rename against the ticket, so nothing in the branch recorded that a
named comparator had been swapped: at the reviewed head `f7505dc`, `grep -rn code-review` across
the pre-registration, this report, the evidence directory and the spec returned **zero** matches.
That is how the substitution stayed invisible, and it is what this section exists to end.
Raised as blocker B1 of PR 673 round 1 and
declared here, in the spec's Decision Ledger (`D-7`), and in the PR body. The pre-registration is
**not** edited — for the reason given at the top of this file, and because its single-commit
history is what AC-1 is scored on.

**What the 0.80 is, and what it is not.** The measurement stands exactly as taken: a bare session
recalled 4 of the 5 ground-truth blockers, over the pre-registered sample, scored by the
pre-registered rule. It is a **bare-vs-kit** recall, and that is how §4 now titles it. It is **not**
a `/code-review`-vs-`review-lean` result, and the claim that it is `review-lean`'s P6 basis of
record *for the comparison the ticket named* is withdrawn. That comparison is **unmeasured**.

**Direction of the bias, and why the verdict does not move.** A prompt-only session is the weaker
comparator: `/code-review` carries its own review scaffolding, so it should recall at least as much
as the bare arm did. The substitution can therefore only have *depressed* the challenger's score —
its failure mode is a false `keep`, never a false cut. C2 cut anyway, at 0.80 against a registered
3/5–4/5 `cut-to-delta` band. The verdict is unaffected; the title of the number was wrong, and only
that. Routed to **#671, arm 2** — see *Recorded separately* below.

### Result

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
records. **Both are live on `main` today**, and both are now filed. `build-lean/SKILL.md:32` says,
in one sentence:

> …asserts milestone 5 — **which a MERGED PR satisfies as well as an open one** (#642), so
> close-out stays reachable after a merge — … But **leave the claimed label alone**: **milestone 5
> requires an open PR**, so review is still in flight and the label is correct.

A merged PR satisfies milestone 5, and milestone 5 requires an open PR. This is the checklist a
build session executes, and the contradiction survived a three-round independent review of the very
PR that introduced it. A bare session found it in seven minutes.
Filed as **#670**; not fixed here, being outside this slice's AC set.

The second is `docs/config-schema.md:22–33`, which still asserts that a verify lane's reserved exit
`3` "applies to the fixed `lint`/`typecheck`/`test` keys and to every `extraLanes` entry". One grep
falsifies it: `lane_failure_class` in `lean-gate.sh:3783` has exactly **one** caller — `typecheck`,
at `:3856` — after #660's lane demotion. It survived that PR's three review rounds and its full
panel, and surfaced only here. Filed as **#674**; also outside this slice's AC set. This paragraph
corrects an earlier count of "one" in this section: the bare arm's escape rate on #660 is two of
two, not one of two.

### Recorded separately, as registered

P10 independence — the verdict is authored by a session that is not the build session — is a
property of the **lane**, and no bare-arm review can exhibit or refute it. `cut-to-delta` here
addresses the skill's 127 lines of prose. It says nothing about the separate-session boundary,
which this slice did not measure and does not touch.

**Successor — #671, arm 2.** The delta is not localisable to particular lines from this evidence.
Measuring which of the 127 lines carries it is the follow-up; until then no line is cut. That arm
also carries the comparator declared above: `review-lean` against the built-in `/code-review`, on
the same three samples and the same oracle, which this slice did not measure.

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

**`intake-interviewer` (279 lines) exits with no verdict, and this is the record of it.** The
ticket's scope item 3 names it alongside `plan-interview`, and the pre-registration declares it "in
scope insofar as it produces the same artifact". That premise holds — it does emit a Decision
Ledger, in the five-column receipt shape, per the `interviewing-baseline` contract. What did not
hold is the sample. C3 handed each arm an **already-filed issue body** (#650, #643, #597) and scored
recall against the `user-answered` rows of committed *lean-spec* ledgers — the four-column plan
ledger `plan-interview` produces at pre-flight. An issue body is `intake-interviewer`'s **output**,
not its input, and no sample ran its path: an unstructured bug report or rough idea taken to an
issue-ready body plus a receipt-shape ledger. C3 therefore measured the surface downstream of it and
never the surface itself. So it reaches **no verdict and no measured basis**: not a `keep`, not a
`cut-to-delta`, and explicitly not a pass by association with `plan-interview`. Raised as blocker
B2 of PR 673 round 1; declared here, in the spec's Decision Ledger (`D-8`), and in the PR body.
**Successor: #672**, whose
body was extended by operator amendment on 2026-08-24 to cover `intake-interviewer` on the same
terms as `intake-orchestrator` — whatever adjudication method lands there covers both, and each
exits with either a measured basis or an explicit no-basis record, never silence.

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

**The protocol is extended, not amended, by
[`docs/skill-ablation-addendum.md`](skill-ablation-addendum.md).** Two of the rows below are owed a
re-measurement that the frozen pre-registration does not describe — `build-lean`'s basis is
repo-local (§1), and `review-lean`'s is a bare-session recall rather than the `/code-review`
comparison the ticket named, with its delta unlocalised (§2). The addendum fixes the substrate
(#746), the challenger invocation (#747) and the attribution rubric (#748) that those arms consume,
before any of them runs. Read it alongside this table: it is where the terms of the next
measurement live, and it contains no results.

| skill | lines | measured | basis | date |
| --- | --- | --- | --- | --- |
| `dev-pipeline/build-lean` | 48 | C1 + #746 arm 1 | **cut-to-delta with an empty cut** — re-measured on the consumer-shaped substrate (§1): bare covers 3–4 of 9, no item is cut-eligible, M3 and M9 `undetermined` at n=2. The repo-local basis is retired | 2026-09-01 |
| `dev-pipeline/review-lean` | 127 | C2 | cut-to-delta; **bare-session** recall 0.80 on ground-truth blockers — not the ticket's `/code-review` comparison, which is unmeasured (→ #671 arm 2); delta not yet localised | 2026-08-24 |
| `intake-toolkit/plan-interview` + `interviewing-baseline` | 312 | C3 | **keep**; bare recall 0.30, delta is the scope-boundary/DEPARTURE class | 2026-08-24 |
| `intake-toolkit/intake-orchestrator` | 711 | — | **unmeasured — no basis**; no metric here reaches decomposition → successor **#672** | — |
| `intake-toolkit/intake-interviewer` | 279 | — | **unmeasured — no basis**; registered in scope, no sample exercised its path → successor **#672** (§3) | — |
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
  it would strip shipped function on a repo-local artefact. **Settled by #746 (§1, 2026-09-01):**
  re-measured on the consumer-shaped substrate, no M-item is cut-eligible. The cut list is empty, so
  there is no deletion for a successor to execute — the reason it stays unexecuted is now a
  measurement rather than a caution.
- **C2's cut is not localisable.** Recall 0.80 says the 127 lines are at best a tie; it does not say
  which lines carry the 0.20. Cutting by guess would be the thing this slice exists to stop.
- **C3 is a `keep`.**

So AC-5 is satisfied vacuously — no deletion, therefore no orphan — and it is recorded that way
rather than as a green sweep that proves something it does not. The successors are filed:

- **#670** — a live self-contradiction in a shipped checklist, found by the bare arm.
- **#674** — the config schema's exit-3 claim against a one-caller dispatcher, the second escaped
  blocker from the same arm.
- **#671** — localise both cuts, and run the comparator the ticket named (`/code-review`) that §2
  declares this slice did not. **Arm 1 (#746) is done** — see §1; it returns an empty cut list. Arms
  2a (#747) and 2b (#748) are outstanding.
- **#672** — `intake-orchestrator` (711 lines) and, by the operator's 2026-08-24 amendment,
  `intake-interviewer` (279 lines): 990 unmeasured lines, each owed a basis or an explicit
  no-basis record.
