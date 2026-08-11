# #494 — milestone 1's fix budget is spent by the call the checklist tells you to make

`build-lean`'s step 3 orders `bash G 1 <issue>` to learn where step 4 must write the spec. At that
moment the spec cannot exist, so the call reds — and `lean-gate.sh:1673` routes that red through
`fail_milestone`, which charges it against the 3-attempt fix budget `attempt_count()` reads. The
#490 run reached its first real fix on milestone 1 with one attempt left, having hit no problem.

The budget exists to bound _fix loops_. Charging artifact absence to it makes the bound tightest on
exactly the runs that need it most, and makes `attempt` lines unreadable as a difficulty signal for
the retro corpus.

## Design

Per the pre-flight receipt (`.claude/pipeline-state/494-ledger.md`), which is binding:

- **D-1** takes AC-3's **first** branch: **cap the absent kind**. Milestone 1's `-f` absence appends
  a distinct `| milestone-1 | absent | <reason>` line, shaped so it cannot match `attempt_count()`'s
  fixed-string `| milestone-1 | attempt |` pattern, and bounded by its own counter. Every _content_
  failure (no `AC-n`, a `design_state` error, the mid-run-disarm lock, an unresolved
  `pause-and-ask`) keeps appending `attempt` and keeps the 3/`rc=4` fix budget. No new subcommand.
  This is an application of the existing `| milestone-3 | armed |` precedent (`lean-gate.sh:1646`),
  not a new mechanism.
- **D-2** sets the absent kind's own bound at **10 calls, hard-stop `rc=4`** — ~2.5× the honest
  ceiling (#490 spent 2; a resume in a fresh worktree adds 1–2; `cmd_all`'s `PRECHECK=1` pre-pass
  records nothing). `rc=4` is reused rather than a new code so `build-lean`'s existing hard-stop
  handling covers it with no new operator path.
- **D-5**: the exhaustion line is named `absent-exhausted`, **never** `absent-budget-exhausted` —
  selftest case `(c2)` counts the substring `budget-exhausted`, so the longer name would silently
  inflate it.
- **D-7** scopes this to **milestone 1 only**. Milestone 4's identical `[ -f "$rec" ]` absence
  (`:2380`) is untouched, per the ticket's own Out of scope. The helper is written generically and
  applied at one call site; existing case `(c1)` — which drives milestone 4 — staying green is the
  evidence that the scoping held.
- **D-6** adds AC-6: `build-lean/SKILL.md:36` documents one hard stop, and a second,
  differently-bounded one that the contract does not mention is the same lie-by-omission class this
  ticket fixes.
- **OR-1** (does milestone 4 carry the same defect?) takes the ticket's stated default —
  milestone 1 only — flagged rather than silently scoped out. Reversing it later is one call-site
  swap plus the `(c1)` re-expectation it forces.

Design: none — this repo configures no `design.provider`.

## Acceptance criteria

- **AC-1** — a milestone-1 evaluation that fails **solely** because the spec file is absent records a
  `| milestone-1 | absent | <reason>` line, distinct from the `| milestone-1 | attempt | <reason>`
  line an evaluation that failed on the spec's _content_ (no `AC-n`, a `design_state` error, the
  mid-run-disarm lock, an unresolved `pause-and-ask`) still records.
- **AC-2** — the absent kind does not increment the count `attempt_count()` returns, while every
  content failure still does. A run cannot reach `rc=4` by asking where the spec goes.
- **AC-3** — the absent kind is itself capped at 10 calls; the 11th returns `rc=4` and records
  `| milestone-1 | absent-exhausted | <n> calls`. Below the cap it returns `1`, exactly as
  `fail_milestone` does, so `build-lean`'s retry handling is unchanged.
- **AC-4** — `build-lean` step 3's `bash G 1 <issue>` remains the path-printing call and becomes
  free: the absent message still names `$SPEC_REL`, so following the checklist literally spends no
  fix budget and the SKILL text needs no move.
- **AC-5** — `lean-gate-selftest.sh` covers: an absent-spec evaluation appends `absent` lines and
  leaves `attempt_count()`'s number at 0; a milestone-1 _content_ failure still appends an `attempt`
  line and its 4th red still returns `rc=4`; the absent cap of AC-3 is exercised at its boundary;
  and `absent-exhausted` does not inflate the `budget-exhausted` count case `(c2)` reads. Existing
  case `(c1)` keeps passing.
- **AC-6** — `plugins/dev-pipeline/skills/build-lean/SKILL.md`'s fix-attempt rule names the second
  hard stop, so the contract does not document one bound while the gate enforces two.

## Out of scope

- **Milestones 2–5**, per the ticket and D-7. Milestone 4's identical absence predicate is
  recorded as OR-1, not fixed here.
- **The budget size itself.** 3 is not under review; this is about what counts against it.
- **The word "committed"** in the absent message (D-4): `cmd_1` has no git-tracked check, so the
  wording is aspirational — but correcting it is not this ticket's scope.

## Verification

- `find . -name '*.sh' -type f -print0 | xargs -0 shellcheck -e SC1091,SC2015,SC2181`
- `bash tools/run-selftests.sh --exclude tools/install-topology-selftest.sh`
- `bash tools/mutation-sweep.sh --mode pr` — with D-8's caveat: `lean-gate.sh`'s `default` class is
  at its 2-per-class quota (both prose sites, `:123`/`:124`), and every generic class's first two
  sites sit above the edits here, so a green sweep proves the count and the labels and never the
  identity of the new code. Each new assertion is hand-probed instead.
- A `tools/mutation-catalog.tsv` row for the central regression — routing absence back through
  `fail_milestone` — as the direct analogue of the existing `lean-gate-zerolane-milestone` row,
  which pins the same "the attempt counter is charged to a milestone that did not fail" defect.
