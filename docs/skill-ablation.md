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
| 2 | `review-lean` SKILL (127 lines) | recall of ground-truth blockers | bare† **4 of 5**; the built-in `/code-review` also **4 of 5** (#747), missing a different one | **cut-to-delta** |
| 3 | `plan-interview` + `interviewing-baseline` (312 lines) | recall of operator-ratified decisions | bare **6 of 20** | **keep** |
| — | `intake-orchestrator` (711 lines) | — | not reached by any metric here | **not adjudicated** → #672 |
| — | `intake-interviewer` (279 lines) | — | registered in scope; no sample ran its path | **not adjudicated** → #672 |

† **Comparison 2 ran a bare session, not the built-in `/code-review` the ticket names.** The
departure is declared in §2 with its direction of bias; the verdict is unaffected. The
`/code-review` comparison itself was run as #671 arm 2a and is reported in §2 — same 4/5, missing a
different blocker.

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

**M6's four `absent` cells, quoted.** The frozen rule
(`docs/skill-ablation-pre-registration.md`:109) requires that a plan naming "a PR" without
`ready`/`Closes` score M6 `absent` **and that the wording be quoted in the report**. M6 is *"a
**ready** (non-draft) PR carrying summary, spec link, `Closes #N`"* (`:95`), scored whole —
partial credit is unavailable — so two of these four name `Closes` and still miss. The wordings, so
a reader can adjudicate rather than take the cell on trust:

- **sealed 636** (`consumer-sealed-636-plan.md`:95-96), the body of its "P12 — PR *(me)*" step:

  > Body carries `Part of #605` and `Closes #636` (`check-lean-chain.sh:475` reds otherwise), the
  > `--list` denominator count, the per-arm red demonstrations, and the residual statement.

  `Closes #636` named; **no spec link and no ready/non-draft**. `absent`.

- **sealed-min 636** (`consumer-sealed-min-636-plan.md`:72):

  > **13. PR.** Body carries `Part of #605` and `Closes #<this ticket>`; the residual restated for
  > the reviewer; OR-1 and OR-2 recorded as the reversible defaults taken (one row per `envfail`
  > class; `unwired` permitted indefinitely) with the measurement from step 1 backing OR-1. **You**
  > review and merge.

  Same shape — `Closes` named, spec link and ready/non-draft absent. `absent`.

- **sealed 647** (`consumer-sealed-647-plan.md`:72):

  > **9. PR** `claude/second-shift-647` → `main`. Body flags the Open Region resolution explicitly,
  > as the ticket asks.

  Names a PR and nothing the item asks for. `absent`.

- **sealed-min 647** (`consumer-sealed-min-647-plan.md`:28), a row of its artifact table:

  > ```
  > | 6 | PR | — | Body flagging the Open Region resolution and the AC-1/2/3 upstream status | me — **blocked, no remote** |
  > ```

  Same, and the step is marked blocked. `absent`.

The two near-misses are the reason the clause exists: without the wording on the page, a reader
cannot tell them from the clean misses, and both readings score the same cell. For contrast, the
`covered` cells name every leg — `bare-ablated-636-plan.md`:83 (*"Body carries `Closes #636`, links
`docs/plans/second-shift-636-lean.md` … Not a draft"*) and `bare-636-plan.md`:94 (*"A **ready,
non-draft** PR containing: summary, spec link, `Closes #<N>` …"*).

M1 and M2 are the interesting rows. Bare names a committed spec and a Decision Ledger whenever
`docs/plans/` is present — it reads this repository's own committed lean specs and cites
`scripts/check-lean-chain.sh`'s requirements by line — and names neither when they are gone. That is
exactly the A1-min hypothesis, confirmed on the sealed pair.

The corpus in front of those sessions was **126** committed lean specs at `dfd68a47` and **127** at
`b657907f`. No session read anything close to all of it: the per-session counts under `docs/plans/`
are 0 to 5 (`consumer-substrate.md`, "What each arm actually read"). Both figures are re-derivable
at the pinned bases, and neither moves with a later lane run the way a count taken at this arm's own
base would.

```bash
git ls-tree -r --name-only dfd68a47 -- docs/plans/ | grep -cE 'second-shift-[0-9]+-lean\.md$'   # 126
git ls-tree -r --name-only b657907f -- docs/plans/ | grep -cE 'second-shift-[0-9]+-lean\.md$'   # 127
```

**Nothing read the prose — in the three sealed sessions that looked.** All four had the installed
cache inside their allowlist; **three** walked into it, and **not one of those opened
`build-lean/SKILL.md`**, though sealed 636 listed the directory it sits in. Sealed 636 read
`lean-gate.sh`, `lean-evidence.sh` and `orchestrate-lean.sh`; sealed 647 read `lean-gate.sh`,
`orchestrate-lean.sh` and a doctor fixture; sealed-min 647 read `lean-gate.sh` only.

**The fourth, sealed-min 636, never referenced the cache at all** — 0 reads under it
(`consumer-substrate.md`, "What each arm actually read") — and its own transcript records
`lean-gate.sh` and `orchestrate-lean.sh` as **absent** and declares the work blocked on
materialising the kit (`consumer-sealed-min-636-plan.md`:7-13, :19). It is evidence for a different
proposition and is not counted toward this one: the finding needs a session that reached the cache
and chose the gate over the prose, and that session never reached the cache.

So §1's structural finding holds on this substrate, on **3 of 4** sealed sessions, and sharpens: a
session re-derives obligations from a gate it can *read*, and an installed plugin's gate is
reachable — but the prose is not what it reaches for. The fourth is the case that did not look at
all, and it is reported as that rather than folded into the three.

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
record *for the comparison the ticket named* is withdrawn. That comparison was **unmeasured** until
arm 2a; it is measured below, and it does not change the verdict.

**Direction of the bias, and what the measurement did to it.** A prompt-only session is the weaker
comparator: `/code-review` carries its own review scaffolding, so it should recall at least as much
as the bare arm did. The substitution can therefore only have *depressed* the challenger's score —
its failure mode is a false `keep`, never a false cut. C2 cut anyway, at 0.80 against a registered
3/5–4/5 `cut-to-delta` band. Arm 2a ran the named comparator and the argument **survives, at
equality rather than with room to spare**: the challenger also scored 4/5. What the argument did
not anticipate is that the two arms miss *different* blockers, so neither dominates — see below.

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

### Arm 2a (#747) — the challenger the ticket named, measured

The built-in `/code-review` at effort `max`, run 2026-09-03 on the three frozen samples at their
frozen heads, under the invocation
[`docs/skill-ablation-addendum.md`](skill-ablation-addendum.md) §B registered before any of it ran.
Transcripts: [`c2-review/codereview-<pr>-review.md`](plans/skill-ablation/c2-review/), one per
session, each carrying its realised invocation and the session's output verbatim.

| sample | ground-truth blockers | bare found | `/code-review` found |
| --- | --- | --- | --- |
| C2-a #654 | 1 | **0** | **1** |
| C2-b #657 | 2 | **2** | **2** |
| C2-c #660 | 2 | **2** | **1** |
| | **5** | **4** — recall **0.80** | **4** — recall **0.80** |

**The two arms are not nested.** The challenger recalls the #654 blocker the bare arm missed — the
enumerator's command-position class omitting keyword-preceded calls — naming the class, citing the
live `lean-gate.sh:420` `else envfail` site by line, and confirming it by execution. It then misses
#660's B2, which the bare arm hit. Same score, disjoint misses; the union of the two arms is 5/5 and
neither arm reaches it alone. That is a fact about *these two comparators*, and it is recorded, not
scored: the frozen metric asks about one challenger at a time, and no registered rule reads a union.

**Governing recall: 0.80** — the higher of the two, per §B's registered rule, which here is also
both. Registered threshold, unchanged: 3/5 or 4/5 → **`cut-to-delta`**. The verdict does not move.

#### The one miss, quoted and adjudicated

#660's B2 is *"AC-3's fixture-per-reason is unsatisfied for `m5/identity-stamp`"* — the reason has
no behavioral case, and its only coverage is the static `(ac1b)` site count, which greps call sites
textually and can never observe that a failed identity stamp records `absent` and charges zero
attempts.

Nothing in the challenger's 34-finding set names that. The nearest three, quoted verbatim from the
transcript so the call can be repudiated:

> The genuine evidence for AC-3 lives only in the selftest.
> — finding 21

That is the **opposite** claim: it asserts the selftest carries AC-3's evidence, where the oracle's
blocker is that for one of the six reasons it does not.

> `(ac1)`'s "all 18 milestone-4 failure sites carry an explicit class" is no longer true of the file
> it inspects, and its companion `(ac1b)` cannot detect the regression its own comment names.
> — finding 28

Same file as the oracle's blocker, and the same complaint about `(ac1b)` being a textual count. But
the defect is a different one: a verdict-absent site moved to `block_milestone 4 "…" 5` sitting
outside `(ac1)`'s grep, plus regex gaps in `(ac1b)`. It says nothing about a reason lacking a
fixture. Same file, different defect — the registered rule scores that a miss.

> Neither AC-8 nor the absent-verb widening is composed by any scenario leg…
> — finding 27

About `scenario-liveness-selftest.sh`'s composition, and it explicitly concedes the `--pr-file`
fixtures do execute the path (*"never execute outside a `--pr-file` fixture"*), which is the
converse of B2's claim that `m5/identity-stamp` has no fixture case at all.

#### Recorded separately, not folded into recall

Per the registered rule, blockers the challenger raises that no round of the lane's own review
raised are recorded here and excluded from recall. Across the three samples the challenger reported
**84 findings** (31 / 19 / 34), each sample's total being its sinks merged for duplicates. **Nine**
correspond to a finding some lane round made, enumerated below so each of the nine is checkable —
the *complement* is not, and the enumeration should not be read as making it so. Only C2-c's
arithmetic is visible in its transcript (32 findings through the report tool + 13 on stdout = 45
raw, 11 merges → 34); C2-a and C2-b carry 14 and 12 JSON findings with the rest in prose across 2
and 5 `result` bodies, so 31 and 19 cannot be re-derived without redoing that merge judgment, which
is recorded nowhere but in the totals themselves.

| sample | challenger finding | lane round it matches |
| --- | --- | --- |
| C2-a | command-position class omits keywords | #654 r1 blocker (the ground truth) |
| C2-a | `gate-buckets.tsv:67` anchor is a prefix of row 68 | #654 r1 finding 3 (Warning) |
| C2-b | seed writes an unignored untracked file | #657 r1 B1 (ground truth) |
| C2-b | tracked project-scope `Bash(gh:*)` | #657 r1 B2 (ground truth) |
| C2-b | the `wt == MAIN_ROOT` guard is redundant with never-clobber and untested | #657 r1 W2 |
| C2-c | the absent-verb demotion skipped `cmd_close_out` | #660 r1 B1 (ground truth) |
| C2-c | milestone 3 concludes `green gate` over a lane that went red | #660 r2 W1 |
| C2-c | the manifest was re-cut to a disjoint record set | #660 r1 W1 |
| C2-c | `docs/testing.md`'s never-fired table disagrees with the report | #660 r1 W1 |

The remaining **75** appear in no round. Two of them re-find the bare arm's own escapes
independently — `build-lean/SKILL.md:32`'s self-contradiction (**#670**) and
`docs/config-schema.md`'s exit-3 claim (**#674**), both filed off the bare arm and both since
fixed — which corroborates that escape set rather than extending it.

**These 75 are recorded as *raised*, not as *confirmed live*, and that is a weaker record than the
bare arm's two.** The predecessor verified both of its escapes against `main` and filed them; 75 is
past the point where that is this slice's work, and verifying them is in no AC here. What the count
is good for is the direction it points, and the frozen table does not consult it at all at 4/5:
false blockers are read only on a 5/5 run. The ledger row that reads AC-6 this way (D-14) was
written in the **results** commit rather than the pinned one — after the count was known, and in the
direction that reduces this slice's work. Disclosed here so the next reader sees the move instead of
inheriting it.

#### Apparatus, and three things the registration did not anticipate

All three captures exited `0` and classified `COMPLETE` under `tools/classify-capture.sh` — §B's
whole scoring precondition — so all three were scored; none was discarded and re-run.

**Stderr was empty on two of the three; C2-b's was not.** It carried `Background tasks still running
after 600s; terminating. Set CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 to wait indefinitely.`
([recorded with the transcript](plans/skill-ablation/c2-review/codereview-657-review.md)) — the
harness stopped waiting on delegated subagents at its ceiling, and C2-b is the only capture of the
three that reached one. It moves no score: exit 0 and `COMPLETE` both held. What it bears on is how
completely C2-b's set can be read, and that matters because C2-b is also the smallest of the three
(**19**, against 31 and 34). Its own transcript records the apparatus failing and then recovering —
`result` 1 of 5 opens *"subagent result delivery was broken in this environment (only the
conventions angle could report back)"*, `result` 2 records that *"the delivery failure resolved
itself — their results arrived as task notifications"* with all 10 finder angles back, and `result`
5 closes *"The review is complete and the ranking stands"*. So the ceiling fired after the session
had declared itself done rather than mid-review, and what it truncated is whatever a still-running
task would have added past that point; nothing here measures how much. **Read C2-b's 19 as a floor**
rather than a settled total, and read the 31 / 19 / 34 spread with that asymmetry in it.

**The capture mode inverted between runs of the same three samples.** The 2026-09-02 measurement
that motivated the amended capture found C2-a and C2-b routing to the report tool and C2-c printing
to stdout. This run is the exact reverse: C2-a and C2-b made **no** `ReportFindings` call and put
their finding sets on stdout, while C2-c filed **32** findings through the report tool and put 13 on
stdout. Under the pre-amendment stdout-only form this run would have lost 19 of C2-c's 32. The
non-determinism §B registered is real, it is not sample-keyed, and the amended capture is what makes
the corpus comparable.

**A session can emit more than one `result` event, and the primary finding set was in the first.**
The three captures carry 2, 5 and 2 `result` events; on all three the main finding set is in
`result` 1, with later events adding material as delegated subagents reported back late. §B's
mapping names "the findings in the final assistant text", which taken literally would discard the
first result's whole array — the very loss mode the amendment exists to close. The finding set was
therefore taken as the union over **every** `result` body plus the report payload, deduplicated on
the frozen hit rule's own predicate. That resolves in the registered bias direction (it can only
enlarge the challenger's set), and it is recorded here rather than folded in silently. §B is **not**
edited: amending a registration with results in hand is what it exists to prevent.

**§B's post-run assertion is unevaluable, as #777 predicted.** It requires the report to state the
range it reviewed; none of the three does, and silence is not "any other range", so no run is
discarded on it. The range was established independently instead. On C2-a it is positively confirmed:
the pinned range is exactly 4 commits over 6 files, and the session reports *"All four commits are
scoped `(dev-pipeline)` but the branch touches zero `plugins/` files (verified: ci.yml, 2 docs, 3
scripts)"* — a byte-exact description of the pinned range — while citing three files
(`gate-buckets.tsv`, `ci.yml`, `pipeline-manifesto.md`) that lie outside `HEAD~1..HEAD`. On C2-b and
C2-c it cannot be confirmed the same way, and does not need to be: each branch's first commit adds
only the lean spec, so `HEAD~1..HEAD` and the pinned range differ by nothing but that file's initial
version.

**The file-reading leak, measured rather than assumed.** The clones keep `plugins/` in the working
tree, because §B registers no removal and the files under review *are* the kit
(`docs/plans/second-shift-747-lean.md` D-1). One subagent `Bash` call on C2-a read 13 lines of
`review-lean/SKILL.md`; C2-b and C2-c made none. That read bears on nothing in C2-a's finding set,
which is entirely about `scripts/check-gate-buckets.sh` and its register.

### Recorded separately, as registered

P10 independence — the verdict is authored by a session that is not the build session — is a
property of the **lane**, and no bare-arm review can exhibit or refute it. `cut-to-delta` here
addresses the skill's 127 lines of prose. It says nothing about the separate-session boundary,
which this slice did not measure and does not touch.

**Successor — #671, arm 2.** The delta is not localisable to particular lines from this evidence.
Measuring which of the 127 lines carries it is the follow-up (**#748**); until then no line is cut.
The comparator half of that arm is **discharged**: arm 2a above ran `review-lean` against the
built-in `/code-review` on the same three samples and the same oracle, and the verdict held at
`cut-to-delta`. The disjoint-miss result sharpens what #748 has to localise — the delta is not "the
lines that beat a bare prompt", since a scaffolded challenger scores the same 0.80 while missing
somewhere else entirely.

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
repo-local (§1), and `review-lean`'s was a bare-session recall rather than the `/code-review`
comparison the ticket named, with its delta unlocalised (§2). The addendum fixes the substrate
(#746), the challenger invocation (#747) and the attribution rubric (#748) that those arms consume,
before any of them runs. Arms 1 and 2a have since run against it; 2b has not. Read it alongside this
table: it is where the terms of the next measurement live, and it contains no results.

| skill | lines | measured | basis | date |
| --- | --- | --- | --- | --- |
| `dev-pipeline/build-lean` | 48 | C1 + #746 arm 1 | **cut-to-delta with an empty cut** — re-measured on the consumer-shaped substrate (§1): bare covers 3–4 of 9, no item is cut-eligible, M3 and M9 `undetermined` at n=2. The repo-local basis is retired | 2026-09-01 |
| `dev-pipeline/review-lean` | 127 | C2 + #747 arm 2a | **cut-to-delta** on two independent challengers: bare-session recall 0.80, and the built-in `/code-review` at effort `max` also **0.80** — the comparison #644 named, now measured (§2). The two miss different blockers, so neither dominates and the union is 5/5. Delta still not localised → **#748** | 2026-09-03 |
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
  declares this slice did not. **Arm 1 (#746) is done** — see §1; it returns an empty cut list.
  **Arm 2a (#747) is done** — see §2; the named comparator scores the same 0.80 and the verdict
  holds. Arm 2b (#748) is outstanding.
- **#672** — `intake-orchestrator` (711 lines) and, by the operator's 2026-08-24 amendment,
  `intake-interviewer` (279 lines): 990 unmeasured lines, each owed a basis or an explicit
  no-basis record.
