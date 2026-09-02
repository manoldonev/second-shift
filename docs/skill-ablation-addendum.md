# Skill-vs-bare-session ablation — addendum: substrate, challenger, attribution rubric

**This file EXTENDS the frozen protocol; it does not amend it.** Registered 2026-09-01, before any
result from #746, #747 or #748 exists. Every rule below is additive: it fixes something
[`docs/skill-ablation-pre-registration.md`](skill-ablation-pre-registration.md) left open or does
not contain at all. Where a frozen rule already governs, **the frozen rule wins**, and each place
that could be read as a conflict says so explicitly and defers.

`docs/skill-ablation-pre-registration.md` is **not edited**. It carries exactly one commit,
`8d5d0897`, and [`docs/skill-ablation.md`](skill-ablation.md):6-11 makes that unedited history the
thing #644's AC-1 was scored on. New rules go in new files; this is the first of them. The ordering
stays checkable:

```bash
git log --oneline -- docs/skill-ablation-pre-registration.md   # exactly one commit, first
git log --oneline -- docs/skill-ablation-addendum.md           # this file, later
```

## Why this exists

#671 has three arms, and each one changes an input to a comparison that was already fixed and
scored: arm 1 (#746) changes C1's **substrate**, arm 2a (#747) changes C2's **challenger**, and arm
2b (#748) needs an **attribution method the frozen protocol does not contain at all** — greps for
`attribut`, `localis`, `per-line` and `line-level` across the pre-registration and
`docs/skill-ablation.md` return only M4's unrelated "commits attributed to the bot identity" and the
prose at `docs/skill-ablation.md`:191 stating the delta is "not localisable to particular lines from
this evidence".

A substrate, challenger or rubric fixed *after* results exist is a post-hoc rubric — the failure
mode `docs/skill-ablation-pre-registration.md`:16 names as the reason a pre-registration exists at
all. So they are fixed here, first, and the arms that consume them are blocked behind this file.

## What this file must never contain

**No results, and no arm output.** Every number below is a *pin* (a commit, a line range, a path, a
count of units) or a *threshold fixed before its arm runs*. None is an outcome.

A few measured facts appear. Every one of them is about the **apparatus** — what the harness does,
not what an arm found — was taken before any arm ran, and is labelled and re-runnable from the
command printed beside it. They are here because the tickets asked for the apparatus to be settled
in writing, and an apparatus claim nobody measured is the thing this file exists to prevent.

There is **no mechanical oracle** for this rule — nothing greps this file for result-shaped content,
and none is built: a report about machinery growth should not grow machinery to land. A reviewer
eyeballs for stray figures and verdicts, deliberately, rather than assuming a gate did it.

---

## A — Arm 1 (#746): the `build-lean` re-run's substrate

### The registered substrate

**Gate and skills absent from the working tree; the installed plugin cache present on disk and
readable by the session's tool allowlist.**

That is what a real downstream machine looks like: a consumer has the kit installed under
`~/.claude/plugins/cache/`, and does not have it in its repository. It is also the **strongest
honest version of the bare arm** — nothing is hidden that a real session could reach — which is what
makes a miss conclusive rather than an artifact of a starved setup.

**The cache path is not guessed — it is resolved.** The layout is
`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`, and the run records the concrete path
it used, from:

```bash
claude plugin list --json | jq -r '.[].path'
# e.g. /Users/<user>/.claude/plugins/cache/second-shift/dev-pipeline/12.2.1
```

The version segment moves with every release, so the arm records the resolved path and the version
it ran against rather than inheriting either from this file. What is registered is that the path is
**present and inside the session's tool allowlist** — not which version happens to be installed.

### Exactly which paths are absent, and by what means

Removed from the working tree, and nothing else:

| path | why |
| --- | --- |
| `plugins/` (whole tree) | every `SKILL.md`, every `agents/*.md`, **and** `plugins/dev-pipeline/skills/build-lean/lean-gate.sh` with the rest of `plugins/dev-pipeline/tools/`. The gate is the whole point: §1's ablated run covered M1–M3 by citing `lean-gate.sh:2663`, `:890`, `:1852` by line. |
| `.claude-plugin/` | the marketplace manifest. Not load-bearing for discovery (see the measurement below), removed so the tree contains no marketplace surface at all. |

**By what means: a throwaway `git clone` of this repository**, checked out at the sample's pinned
base commit, with those two paths deleted from the working tree and left as unstaged deletions. The
arm is read-only and commits nothing.

Two alternatives the ticket named are rejected, and recorded so they are not re-proposed:

- **Deleting the skill files in a live checkout** — rejected. Destructive to the operator's real
  work, and it makes the deletion visible to `git status` in a tree the lane may be using.
- **A synthetic layout omitting `plugins/` entirely** — rejected. The C1 samples are second-shift
  tickets; the repository's own code has to be present for #636 and #647 to be implementable at all.
  A synthetic layout would change *what is being planned*, not just what is available to plan with.

### Measured: an intact `plugins/` tree does not leak skill DISCOVERY

The ticket asks whether a stray `.claude-plugin` manifest or an otherwise-intact `plugins/` tree
still lets the session discover local skill definitions after the SKILL files are removed, "since
that would silently change what the arm measures."

**Measured 2026-09-01, in a checkout of this repository with `plugins/` FULLY intact — every
`SKILL.md` and every agent contract present — and `.claude-plugin/marketplace.json` present:**

```bash
read -r -d '' PROMPT <<'EOF'
Answer with exactly two lines and nothing else. No preamble, no explanation.

Line 1 must be exactly `AVAILABLE:yes` or `AVAILABLE:no` — is a built-in skill or slash command
named `code-review` available for you to invoke in THIS session?

Line 2 must be exactly `SECONDSHIFT:yes` or `SECONDSHIFT:no` — is ANY skill from the second-shift
plugin family (build-lean, review-lean, run-lean, review-lead, intake, plan-interview,
mutation-review, doctor, local-dev-refresh, onboard) available to you as a SKILL you could invoke
in THIS session? Do NOT count files you could read from disk; count only skills actually loaded
and invocable.
EOF
printf '%s' "$PROMPT" | env -u CLAUDE_CODE_SESSION_ID -u CLAUDECODE \
  -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_BRIDGE_SESSION_ID \
  -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_SSE_PORT \
  -u CLAUDE_EFFORT -u CLAUDE_PID \
  claude -p --model opus --setting-sources '' --allowedTools Read
# -> AVAILABLE:yes
# -> SECONDSHIFT:no
```

`--setting-sources ''` suppresses the settings that enable plugins, so **neither an intact
`plugins/` tree nor a `.claude-plugin` manifest causes local skill definitions to be discovered as
skills.** This is measured at the maximum: if a tree with every SKILL file present discovers
nothing, a tree with them deleted discovers nothing.

The consequence for the construction is precise, and it cuts both ways:

- The leak the frozen protocol tripped over is a **file-reading** leak, not a discovery one. §1's
  confounded run *read* `SKILL.md` with `Read`/`Grep`; it never had the skill loaded. So removing
  the files is still **required** — reading is the leak.
- But removing them is **sufficient**. No extra step — unsetting the marketplace, stripping
  `.claude/settings.json`, disabling plugins — is needed to prevent discovery, and none is
  registered. Recorded so #746 does not spend a round re-deriving it, and so a reviewer can
  repudiate it by re-running one command.

### What is deliberately KEPT, and the bias each carries

| kept | why | direction of bias |
| --- | --- | --- |
| the installed plugin cache, readable | a consumer machine has it; hiding it would starve the arm | **advantages bare** — it can walk to the kit if it thinks to |
| `CLAUDE.md` | the frozen protocol keeps it in both arms and marks what it mandates non-discriminating (`docs/skill-ablation-pre-registration.md`:34) | frozen; not this file's to change |
| `.claude/second-shift.config.json` | an onboarded consumer has a committed one; here it is gitignored, so it is **copied in** from the operator's checkout | advantages bare |
| `.claude/settings.json`, `.claude/SECOND-SHIFT.md`, `.claude/second-shift.lock.json`, `.claude/lean-overrides.tsv` | a consumer onboarded by `/second-shift:onboard` has these | advantages bare |
| `docs/`, `scripts/`, `tools/`, `tests/`, `schema/`, `.github/` | the repository's own code and docs, not the kit | advantages bare |

Every bias runs the same way — toward bare covering **more**. That is deliberate and it is what
makes the arm's negative result strong. It is also exactly why the outcome reading below is not
symmetric, and why a *positive* result triggers a second arm rather than a cut.

### The pinned checkouts

The frozen protocol says the bare arm runs "at the base commit the work starts from"
(`c1-build/prompt-template.txt`:2-3) and never records which commit that is. Two implementers
cannot build the identical checkout from that. Fixed now:

| id | ticket | PR | base commit — the checkout |
| --- | --- | --- | --- |
| C1-a | #636 | 654 | `dfd68a47402acb9f77530e3e086dd42760749709` |
| C1-b | #647 | 657 | `b657907f52011c06afad34fc026fbbaeca8ae88a` |

Derivation of record — the parent of the branch's own first commit:

```bash
git fetch origin "refs/pull/$PR/head:refs/probe/$PR"
first=$(git rev-list "refs/probe/$PR" ^"$(git merge-base "refs/probe/$PR" origin/main)" | tail -1)
git rev-parse "${first}^"
```

`git merge-base` agrees with this on both branches, because neither carries a base merge
(`git log --merges` over each branch's own range is empty) — but the first-commit-parent form is the
one registered, because it stays correct if a future re-run picks a sample that does.

**`gh pr view --json baseRefOid` is NOT the answer and must not be used.** For PR 657 it returns
`02439277`, the base ref's tip at merge time — not the commit the branch was cut from. An
implementer using it builds a different checkout from one using the form above, which is precisely
the failure this pin exists to close.

### Provenance is scored per covered item — new, and load-bearing

The frozen scoring rule (`docs/skill-ablation-pre-registration.md`:104-109) scores each of M1–M10
`covered` or `absent`, with no partial credit. That rule is unchanged and governs.

**Added:** every item scored `covered` also records its **source**, one of:

| source | means |
| --- | --- |
| `cache` | the plan cites a path under `~/.claude/plugins/cache/`, or quotes gate/skill text that exists only there |
| `tree` | the plan cites a file in the working tree |
| `unaided` | neither — the plan names the artifact without citing a source for it |

This is what makes the arm readable at all. The substrate deliberately leaves the cache reachable,
so a bare arm may cover an item by *walking to the kit*. Without provenance, "bare covered M1" and
"bare read `build-lean/SKILL.md` out of the cache" are the same row — and telling those two apart is
the entire question arm 1 was filed to answer.

### Outcome reading, fixed now — including a conflict the parent tickets carry

**The tie-break, declared before any result.** #671 arm 1 reads *"If bare still covers M1–M3 there,
the cut is safe and self-contained."* #745's AC-2 reads *"a bare arm that still **misses** M1–M3
proves the cut safe."* Those point in opposite directions, and choosing between them after seeing a
result would be the post-hoc rubric this file exists to prevent.

**The frozen rule breaks the tie, because it is the one neither ticket may amend.**
`docs/skill-ablation-pre-registration.md`:44 defines `cut-to-delta` as *"the surface is cut to the
part that demonstrably differs from bare"* — so an item bare **covers** is cut-eligible, and an item
bare **misses** is kept. #671's phrasing is the one consistent with it.

What AC-2's clause is right about is the **bias argument**, not the outcome rule: because the
substrate is maximal, a *miss* cannot be blamed on starvation. That is recorded as the substrate's
rationale, and it is not an outcome rule.

| A1-max result on M1–M3 | registered reading |
| --- | --- |
| all three `absent`, both samples | the §1 caveat is **confirmed**. `build-lean`'s prose keeps M1–M3; the cut that #644 recorded and declined to execute stays blocked for those items, now on measurement rather than on suspicion. |
| any of the three `covered`, provenance `unaided`, both samples | that item is **cut-eligible** in the consumer shape. The §1 caveat is lifted for it. |
| any of the three `covered`, provenance `cache` or `tree` | **inconclusive** on its own — the coverage may be this repository's own accumulated artifacts rather than general competence. Triggers **A1-min** below. |
| the two samples disagree on an item | that item is `undetermined` and is **not** cut-eligible. n=2 is the frozen sample size; a split at n=2 is not a result. |

### A1-min — the conditional sensitivity arm, registered NOW

§1's sensitivity run had to be disclosed as **post-hoc** (`docs/skill-ablation.md`:56-58). This one
is registered before its trigger can be observed, so it never has to be.

**Trigger:** any of M1–M3 scores `covered` with provenance `cache` or `tree` in A1-max.

**Construction:** identical to A1-max, additionally removing from the working tree the artifacts
that are *instances of the very things being scored* — a plan that has read a directory of committed
lean specs can name a spec file, a ledger and a worktree with no general competence at all:

- `docs/plans/` — the committed `second-shift-*-lean.md` specs (17 of them at this file's own base, `8200f1c3`; the count moves with every lane run), plus this study's own evidence tree
- `.claude/SECOND-SHIFT.md`, `.claude/second-shift.lock.json`, `.claude/lean-overrides.tsv`
- the single `.claude/settings.json` allow entry naming `lean-gate.sh` by literal path

`.claude/second-shift.config.json` and `CLAUDE.md` **stay** — a consumer has both, and the frozen
protocol pins the second.

**Registered reading:** an item of M1–M3 is cut-eligible only if it is `covered` in **both** A1-max
and A1-min. Covered in A1-max and absent in A1-min means the coverage was the repository's own
artifacts, the item is kept, and that is reported as the finding rather than as a failed arm.

---

## B — Arm 2a (#747): the `/code-review` challenger

#644's scope item 2 named the built-in `/code-review`; what ran was a plugin-free session on a
generic prompt. The departure is declared at `docs/skill-ablation.md`:108-136. This registers the
comparator it named.

### The invocation, exact

```bash
printf '%s' '/code-review max <branch>' | env -u CLAUDE_CODE_SESSION_ID -u CLAUDECODE \
  -u CLAUDE_CODE_ENTRYPOINT -u CLAUDE_CODE_CHILD_SESSION -u CLAUDE_CODE_BRIDGE_SESSION_ID \
  -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN -u CLAUDE_CODE_SSE_PORT \
  -u CLAUDE_EFFORT -u CLAUDE_PID \
  claude -p --model opus --setting-sources '' --allowedTools "Read,Grep,Glob,Bash" \
    --output-format stream-json --verbose
```

**`--output-format stream-json --verbose` is a CAPTURE flag pair and nothing else.** The command,
the model tier (`--model opus`), the effort (`max`), the allowlist (`Read,Grep,Glob,Bash`) and the
`env -u` set are byte-identical to the form this arm was first registered with. It changes what is
*recorded*, not what is *run*, so every bias argument registered in the three subsections below —
model tier, effort, and tool allowlist — holds verbatim. Why it is needed, and what it is asserted
to capture, is the next subsection.

**No new harness is needed and no second-shift plugin is loaded.** Measured 2026-09-01, under the
frozen bare-arm recipe and in a tree with `plugins/` fully intact, that invocation shape answers
`AVAILABLE:yes` / `SECONDSHIFT:no` — the built-in survives `--setting-sources ''`, and the kit does
not come with it. The command and its output are printed in §A above; it is one probe, re-runnable.

### Why the capture flags are there — the defect they answer

**The built-in does not always answer on stdout.** It may instead route its finding set to a
structured report tool, and a stdout-only capture discards it. It does this
**non-deterministically**: measured 2026-09-02, all three registered C2 samples run under the
pre-amendment form verbatim — same command, model tier, effort and allowlist:

| sample | rc | stdout | capture mode | findings recoverable from stdout |
| --- | --- | --- | --- | --- |
| C2-a (`cfba102`) | 0 | 3188 B | report tool | **0 of 15** |
| C2-b (`f8f7c14`) | 0 | 2897 B | report tool | **0 of 12** |
| C2-c (`642a6b1`) | 0 | 17326 B | stdout | 15 of 15, as a valid JSON array |

C2-a's stdout opens `I filed the 15 verified findings via the report tool.` and closes offering to
re-file them; what it carries is the residue that session volunteered *in addition to* the filed
set — explicitly material "the filed report doesn't" carry. C2-b is the same shape at 12 findings.
C2-c emitted `Findings below, ranked most-severe first` followed by a parseable 15-element array.

Uniform loss would fail loudly. This does not: a scorer reading the corpus as captured grades C2-c
on 15 findings and C2-a / C2-b on a handful of volunteered scraps, and records the difference as a
property of the challenger.

**Disposition of those three outputs: discarded for scoring**, retained as the defect measurement
above and nothing else. #747 re-runs all three under the amended capture, so one capture mode spans
the corpus and the samples are comparable by construction rather than by argument.

### Validation of the recipe — superseded, and by what

**The claim this subsection used to carry is withdrawn.** It recorded that, measured 2026-09-01,
the invocation was run end-to-end against a throwaway two-commit repository and "completed and
reported findings". That is true and it is not sufficient: a two-commit diff yields a prose answer,
so the validating measurement never exercised the report-tool path that two of the three real
samples take. Fixture fidelity is what produced the false green, which is why the replacement below
runs against a pinned sample clone rather than a hand-built fixture — and why it *replaces* the
two-commit run rather than being added alongside it.

<!-- MEASUREMENT-PLACEHOLDER -->

### Model tier — `--model opus`

Matching the frozen recipe (`docs/skill-ablation-pre-registration.md`:28). The reason is registered
rather than assumed: a weaker challenger can only **depress** the challenger's score, and a depressed
challenger's failure mode is a false `keep` — the incumbent surviving on a soft bar, which is the one
outcome the frozen decision rule is built to refuse.

### Effort — `max`, and why not `ultra`

`max` is **the strongest available effort**, which is what the ticket asks for. `ultra` is nominally
higher and is **not available to this arm**: it is a multi-agent review that runs in the cloud, is
user-triggered and separately billed, cannot be launched by a session, and takes a GitHub PR target
rather than a pinned local range. Registering `ultra` would register a recipe that cannot be run.

The bias is recorded in the same direction as the model tier: if `max` understates what the built-in
could do, it understates the **challenger**, whose failure mode is a false `keep`.

### The tool allowlist, wider than the frozen bare arm's

The frozen recipe's allowlist is optional and bracketed, `[--allowedTools "Read,Grep,Glob"]`. This
arm registers `Read,Grep,Glob,Bash`, because `/code-review` resolves its own target range and needs
`git`. Same direction of bias again: a wider allowlist can only help the challenger.

### Target pinning, and the pre-run assertion

The arm must review **the head the oracle scored**, not the PR as it stands today — all three
samples are long since merged, so `/code-review <PR#>` would review the wrong thing. The frozen
sample is unchanged; only its base is added, because a range needs one:

| id | PR | reviewed head (frozen) | base of the range |
| --- | --- | --- | --- |
| C2-a | 654 | `cfba10220fced059a2fd3032b58d7075ffd538f4` | `dfd68a47402acb9f77530e3e086dd42760749709` |
| C2-b | 657 | `f8f7c142919507a58acbc268596c1127b4fa1ae0` | `b657907f52011c06afad34fc026fbbaeca8ae88a` |
| C2-c | 660 | `642a6b13d94aaab9b2de4e84edd4e8fa79f54d8a` | `bf231bdc48c5a6d2d4af4f24aa5bf4c1b93b2194` |

**Construction:** a throwaway clone; the default branch **hard-reset to the pinned base**, and
`<branch>` created at the pinned head. Resetting the base branch is what makes the built-in's own
base resolution land on the pinned commit instead of today's `main`.

**The base resolution is silent, and it does fall back — measured, not assumed.** In the
2026-09-01 end-to-end run the target branch had no upstream and the repository had no `main`; the
built-in reported that it had reviewed *"the diff … `HEAD~1`"*. It did not fail, and it did not
warn beyond that line. An arm whose base branch is missing or is at today's tip therefore reviews a
**silently different range** and still returns a plausible report — which is the class of error §2
had to disclose after the fact, arriving here through a different door.

**Pre-run assertion — a run that fails it does not count and is re-built, not scored:**

```bash
test "$(git rev-parse main)"     = "<pinned base>"
test "$(git rev-parse <branch>)" = "<pinned head>"
```

**Post-run assertion, from the same measurement:** the report states the range it reviewed. That
statement must name the pinned base, and a run whose report names any other range is discarded — the
pre-run assertion pins what the repository looks like, and only the report says what the built-in
actually did with it.

### The output shape, and how it maps onto the frozen metric

The frozen C2 arm was told to end with a section headed exactly `BLOCKERS`
(`c2-review/prompt-template.txt`:7-10). **The built-in does not do that, and must not be forced
to.** Measured 2026-09-01 in the end-to-end run: `/code-review` emits its own **ranked findings
list**, most-severe first, with no blocker / non-blocker split, and with severity carried in the
prose of each finding rather than in the structure ("retained at low severity", "demoted rather
than dropped").

So the mapping has to be registered, or #747 will be choosing which findings count as blockers
*after* seeing whether they hit — which is the post-hoc rubric this file exists to prevent.

**Registered mapping: every finding the built-in reports is in the challenger's finding set.** No
severity filter, no demotion, no scorer judgment about which ones "were really blockers". The
frozen hit rule then applies to that set unchanged — same mechanism and same consequence against
each of the five ground-truth blockers.

**"Reports" spans both sinks, because the built-in uses both.** Under the amended capture the
challenger's finding set is the **union** of two things the stream carries:

1. the **report tool's input** — the findings the session filed, recorded as the `tool_use` block's
   payload; and
2. the findings in the **final assistant text** — the residue a session volunteers in addition to
   the filed set, and, on a sample that files nothing, the whole of it.

That union is then **deduplicated on same mechanism and same consequence**. The predicate is the
frozen hit rule's own, quoted rather than invented, so the merge introduces **no new scorer
judgment**: a pair the hit rule would call one finding against a ground-truth blocker is one
finding here too. Nothing is dropped for being in only one sink, and nothing is counted twice for
being in both.

This is a refinement of the sentence above it, not a replacement. Both directions of the mapping's
registered bias below apply to the union exactly as they applied to the stdout set — the union is
strictly larger, so it moves recall and the false-blocker count the same way, only further.

Both consequences are registered, because this mapping is not free in one direction:

- It **maximizes recall**, which advantages the challenger — the safe direction, whose failure mode
  is a false cut of the incumbent rather than a false `keep`.
- It also **maximizes the false-blocker count**, which the frozen table consults only at 5/5 (`no
  more than the lane's own round-1 records raised` → `delete`; `more` → `cut-to-delta`). So the
  mapping can hold C2 at `cut-to-delta` on a perfect-recall run. That is the honest reading of a
  challenger that reports everything it notices, and fixing it now is what stops the alternative —
  a severity filter chosen after the fact, tuned until the count lands on the wanted side.

### Forbidden flags

`--comment`, `--fix`, `--post` and the `ultra` level are **forbidden**. The arm reads; it writes
nothing to the PR, the tree or any external surface.

### Scoring — frozen, and the one thing this arm can move

The frozen C2 metric, hit rule and threshold table
(`docs/skill-ablation-pre-registration.md`:123-161) are **unchanged and govern**. This arm changes
the challenger, not the metric: the same three samples, the same five ground-truth blockers, the
same "same mechanism and same consequence" hit rule, the same oracle already committed under
`docs/plans/skill-ablation/c2-review/`.

Registered consequences, before the run:

- A challenger score of 5/5 with no more false blockers than the lane's own round-1 records raised
  moves C2 from `cut-to-delta` to **`delete`**, per the frozen table. That verdict is reachable and
  is registered as reachable.
- **If the challenger scores BELOW the bare arm's 4/5**, then the directional argument recorded at
  `docs/skill-ablation.md`:131-136 — that `/code-review` should recall at least as much as a bare
  prompt — is **falsified**, and it is reported as falsified rather than quietly dropped. §4 already
  records that argument as `unverifiable`; this is the run that can verify it.
- In that case both numbers are reported and **the governing recall for C2's verdict is the higher
  of the two**. The burden of proof is on the skill, so the fair test is the strongest challenger
  observed — and fixing that now is what stops the weaker number being chosen after the fact because
  it flatters the incumbent.
- Exit either way: a measured `review-lean`-vs-`/code-review` basis for `docs/skill-ablation.md` §4,
  or an explicit no-basis record. §4 currently carries neither.

---

## C — Arm 2b (#748): the attribution rubric

### Method

**Leave-one-out ablation** over `review-lean`'s SKILL, re-run against the **C2-a** sample
(#654 @ `cfba102`), scoring whether the ground-truth blocker disappears. C2-a is the sample the bare
arm **missed** (`docs/skill-ablation.md`:152-159), which is why it is the one that can localise
anything: it is the 0.20.

The ground-truth blocker, quoted from the frozen sample so the hit rule has a fixed subject: *the
gate-bucket enumerator's command-position class omits keyword-preceded calls, so a live refusal site
sits outside the denominator the guard claims is its output.*

### Subject pin

`plugins/dev-pipeline/skills/review-lean/SKILL.md` at **`8d5d0897c3b57ea0d5349787edfd86c3e4ee46ff`**
— **127 lines**. Not the current head, which is **188 lines** at this branch's base `8200f1c3`.

The pinned commit is the one the pre-registration itself was committed in, which is what makes it
the measured file rather than a nearby one. The lines added since are **unmeasured**, and are
recorded as unmeasured rather than silently cut or kept. The count at head moves with every merge —
`docs/skill-ablation.md` repeats "127" at :31, :188, :192, :275 and :299, and 127 is right only
about the pinned commit — which is why the subject is pinned by **commit**, never by line count.

### The unit enumeration — 17, derived here rather than asserted

The ablation unit is the **finest** one, and explicitly **not** the markdown `##` heading: at the
pinned commit the file has only two of those, so ablating by heading is a 2-run study that localises
no finer than a 73-line block — which would leave the cut as unexecutable as #644 left it.

| unit | lines @ `8d5d0897` | what it claims | reach |
| --- | --- | --- | --- |
| U-P | 1–23 (preamble) | the session's purpose, `G`'s location, the jira tracker delta | not-reached |
| U-1 | 26–28 | export a review identity | not-reached |
| U-2 | 29–30 | `gh pr view` to resolve the head branch and issue key | not-reached |
| U-3 | 31–37 | check out the PR head by branch name, not detached | not-reached |
| U-4 | 38–47 | `bash G delta` — the range this round must READ | not-reached |
| U-5 | 48–55 | **Review**: `review-lead`, prior findings, per-`AC-n` scoring, `approve` iff no blockers, do not soften | **in-reach** |
| U-5b | 56–66 | design fidelity on an armed run | not-reached |
| U-5c | 67–76 | a voided round is handed back | not-reached |
| U-6 | 77–85 | write the record via `bash G verdict` | not-reached |
| U-7 | 86–89 | commit and push the record, last on the branch | not-reached |
| U-8 | 90–96 | post the findings as one PR comment | not-reached |
| R-1 | 100–107 | never end a turn with uncollected work | not-reached |
| R-2 | 108–109 | one identity per review round | not-reached |
| R-3 | 110–114 | **inheritance narrows what you READ, never what you must find; read wider whenever the delta looks misleading** | **in-reach** |
| R-4 | 115–116 | **approve on the diff, not the spec's promises; an unmet `AC-n` is a blocker** | **in-reach** |
| R-5 | 117–121 | the four design blockers on an armed run | not-reached |
| R-6 | 122–127 | review the patch you will name | not-reached |

**Ten numbered checklist steps** (`1`, `2`, `3`, `4`, `5`, `5b`, `5c`, `6`, `7`, `8` — a naive
`^[0-9]\+\.` grep finds only eight, because `5b.` and `5c.` do not match it), **six non-negotiable
rule bullets**, and **the preamble** = **17 units**. The ticket's "roughly 17" is exactly 17.

Ablating a unit means deleting exactly its line range. **U-P is the one exception:** its lines 1–4
are YAML frontmatter — the file's identity, not instruction prose — and are retained; ablating U-P
removes lines 6–22.

### The reach classification is a REGISTERED PREDICTION, not an exemption

This is the rubric's load-bearing decision, so it is fixed before any run and stated plainly.

Most of `review-lean`'s units make claims about **producing lane artifacts** — export an identity,
call the gate, commit the record through the bot, post the comment. A metric whose outcome is
"did the review find this defect" cannot reach those. Under a naive reading, every one of them
would ablate cleanly, score "no effect", and license cutting the entire mechanical half of the
skill. That would be a catastrophic false cut, and it is the single most likely way this study goes
wrong.

So: **a `not-reached` unit is never cut-eligible on this evidence.** It is recorded the way
`docs/skill-ablation.md` §4 records an unmeasured skill — `not-reached — no basis` — and routed to a
successor owed a different metric. It is *not* recorded as `no-effect`.

But the classification is a **prediction**, and a prediction that is never tested is an assumption
wearing a label. So **all 17 units are ablated**, not just the three in-reach ones, and a
`not-reached` unit that *does* change the outcome is a falsification of this table — recorded as a
surprise, promoted to in-reach, and reported as the more interesting result.

Three of the seventeen are classified `in-reach`. Five of the fourteen `not-reached` calls are
**sample- or harness-conditional**, and are recorded as such so a different sample can re-classify
them without re-opening the table:

- **U-5b and R-5** govern design fidelity, and C2-a is not an armed run — verified, not assumed:
  `git show cfba102:docs/plans/second-shift-636-lean.md` contains no occurrence of the string
  `Design` at all. On an armed sample both become in-reach.
- **U-3, U-4 and R-6** concern which checkout and which range the round reads. The harness pins both
  identically in every arm, so removing their text cannot change what any arm sees here.

### The harness, and the confound it carries

Each run is a **one-shot piped prompt, read-only**, in a throwaway clone at `cfba102`: the ablated
SKILL text, then the frozen `c2-review/prompt-template.txt`, then the diff. Same `env -u` recipe,
`--setting-sources ''`, no plugins loaded. Nothing is committed, no gate is called, no round is
spent.

**Registered confound, stated now rather than discovered later: `review-lead` is not loaded in any
arm.** U-5 names it as "the implementation" of the review, and it is a separate skill this study
never loads. This study therefore attributes **within `review-lean`'s prose, holding `review-lead` absent in every arm
including the control**. It cannot attribute anything *to* `review-lead`, and a unit that matters
only because it routes to `review-lead` will read as `no-effect` here. Any cut list this arm emits
inherits that limitation and must restate it.

### The control, and the void condition

**Control:** the full 127-line text, same harness, **n=3**.

**Void condition:** if the control does not reproduce the C2-a ground-truth blocker in **at least 2
of 3** runs, the study is **void for this construction**. #748 then records "no attribution possible
under this construction" and **does not proceed to the ablation runs** — no localisation is
manufactured from a control that could not find the thing being localised.

**Fallback, fixed now so a void is not a dead end:**

1. Re-run the control **with `review-lead` available** — the kit arm as it actually runs. If that
   reproduces the finding, the unit set gains an 18th, coarse unit: `review-lead` as a whole,
   explicitly not localised any finer, and the study proceeds with it.
2. If neither control reproduces it, the arm exits **`no basis`** and says so. That is a real
   result — it says the 0.20 is not reproducible outside the lane — and it is reported, not retried
   until it passes.

### What counts as "this unit produced the finding"

A unit `U` is scored **`carrier`** iff **both**:

1. the control reproduces the ground-truth blocker at its majority (≥2 of 3), **and**
2. the `U`-ablated arm fails to reproduce it at its majority (≤1 of 3),

where "reproduce" is the **frozen C2 hit rule** verbatim: the finding names the **same mechanism and
the same consequence**; naming the same file with a different defect is a miss
(`docs/skill-ablation-pre-registration.md`:147-152). Every near-miss is quoted verbatim in the
report and adjudicated there, so a reader can repudiate the call rather than take it on trust.

### Replicates

| arm | runs | why |
| --- | --- | --- |
| control | 3 | the majority rule needs an odd n, and the control is what every other arm is read against |
| each `in-reach` unit | 3 | these are where a real effect is expected |
| each `not-reached` unit | 1 | a falsification probe of the classification. A single run that **keeps** the finding confirms the prediction cheaply |

**Escalation, fixed now:** a `not-reached` unit whose single run **loses** the finding escalates to
n=3. Any arm whose valid runs split (1-of-3 or 2-of-3) escalates to **n=5**, and the majority of the
five governs. Nothing is called on a split.

That is **26 runs before any escalation** — 3 control, 3×3 in-reach, 14×1 not-reached — and the
asymmetry is the reason it is 26 rather than 54. Registered so the arm's cost is a fixed
consequence of the design rather than a discovery made halfway through it.

### Indeterminate runs

A run that errors, is truncated, refuses, or emits no `BLOCKERS` section is **`indeterminate`**. It
is recorded verbatim with its failure mode and **re-run once**. A second indeterminate at the same
arm leaves that arm short a valid run, and:

**an arm with fewer than 2 valid runs is `undetermined`, and is never scored `no-effect`.**

Absence of a run is not evidence of no effect.

### The exit threshold — "produced nothing either arm did differently"

A unit is **`no-effect`** iff **both**:

1. the ground-truth blocker is reproduced at the arm's majority — removing the unit did not lose the
   finding; **and**
2. the arm's blocker **set** is otherwise indistinguishable from the control's: no other blocker the
   control raised is lost, and no blocker is gained that **no** control run raised.

Clause 2 is why the threshold is a set comparison and not a single bit. A unit that suppresses false
blockers is doing work; scoring it inert because the one ground-truth finding survived would cut the
thing that keeps the arm honest — and the frozen metric already counts false blockers alongside
recall for exactly that reason (`docs/skill-ablation-pre-registration.md`:132-133).

**Cut eligibility:** only an `in-reach` unit scored `no-effect` across all its valid runs is
cut-eligible. And even then **#748 emits a cut LIST, never a cut** — every deletion is a further
successor of #671, per the `docs/skill-ablation.md` §5 precedent separating a verdict from its
execution.

### The frozen decision rule does not descend to units

`docs/skill-ablation-pre-registration.md`:47 fixes: *"Absence of evidence yields `cut-to-delta`,
never `keep`."*

That rule governs **a comparison's verdict**, and C2 has already reached its verdict under it. It is
**not** a rule about units, and it is registered here that it does not descend to them: **no unit is
cut because the study produced no evidence about it.** Reading it otherwise would cut fourteen of
seventeen units on nothing — which is the guessing this arm exists to replace.

---

## What gets recorded regardless of outcome

For each arm: the substrate or invocation actually used, the date, the arm id, every pinned commit,
and — for every unit or item left standing — why the evidence did not reach it. A surface kept
because a metric could not see it is recorded as `not-reached — no basis`, never as a pass.

## Where the results go

Not here. Each arm reports into `docs/skill-ablation.md` — a registration co-located with the
results it scores is not a registration.
