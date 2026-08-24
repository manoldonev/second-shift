# lean review verdict — #644

verdict=approve
run_id: review-644-2
session_id: 6e150695-54b4-4ace-bb9e-446ebe018c5b
rounds: 2
pr: #673
reviewed_head: ce36dffda67568dabbd2d2629afe43b4480916c1
reviewed_patch_id: 082f21180eae963d91b9c3213a04b461cdb18aa4
inherited_patch_id: b8a6e7a2e944f96986bb8b098b3a82239a502fd0
inherited_from_verdict: 1ce1bd77b5f9be073b15bbfa16f21bf2645f9748
fidelity: not-applicable
model: unknown
capabilities: pr-marker

## Round 2 — `approve`

**Panel:** maintainability, scope-completeness — trivial-inert routing (all three changed files are
Markdown outside `.claude/`). Both returned, **none dark**. Maintainability `approve`, zero findings.
`scope-completeness` returned `request-changes` with two `major` findings and one `minor` — all three
are residuals of operator-ruled departures, not defects in the delta; see *Warnings*.

**Range:** `bash G delta 644` printed `1ce1bd7..HEAD`, inheriting the coverage of patch `b8a6e7a2e944`.
One commit (`ce36dff`), docs-only, 3 files, +96/−12. Reviewed from a checkout of the head branch;
head re-checked immediately before this record (remote, local and `gh pr view` all `ce36dff`) and unmoved.

**Both round-1 blockers are discharged, and I verified each by execution rather than by reading the
declaration.**

**B1 — the swapped comparator — closed.** The departure is now declared in `docs/skill-ablation.md` §2
(a dedicated *Departure* subsection), in the c2 evidence README, in spec ledger row `D-7`, and in the
PR body; §4's row is retitled to a **bare-session** recall and the P6-basis-of-record framing is
withdrawn at `:128`. I checked for residue of the withdrawn claim: `grep` for "one is live" returns
nothing anywhere under `docs/`, and no surface still frames the 0.80 as the ticket's comparison.

*The round-1 fix's own disclosed self-falsification is genuinely cured, not hedged.* The first draft
wrote "`grep -rn code-review` … returns nothing", a sentence made false by its own landing. The
amendment pins it to the head it was true at, and the pin is checkable: at `f7505dc`,
`git grep code-review` over the pre-registration, the report, the evidence directory and the spec
returns **zero** matches (rc=1); at `ce36dff` the same grep returns 11 across 3 files. The claim is
now true as written and stays true. I also confirmed the `--force-with-lease` was that amendment and
nothing else: `1ce1bd7` (the round-1 record) is an unmodified ancestor of the head, the branch's ten
commits below the tip are byte-identical, and only the tip was replaced.

**B2 — `intake-interviewer`'s silent exit — closed, and closed the way that makes it scoreable.**
Round 1's objection was that #672 named a *different* skill, so naming it as successor would have been
a re-assertion. The fix instead states **why the metric could not reach the surface**, and that reason
verifies at source: `intake-interviewer/SKILL.md` mandates the ledger in the **receipt shape (five
columns)**, whereas C3 scored `user-answered` rows of four-column *lean-spec* plan ledgers — so C3
measured the surface downstream of it. §4's row, §3's paragraph, the verdicts table and `D-8` all carry
the no-basis exit plus successor.

**The successor attestations verify independently on the tracker, by the authorship test rather than
by their labels.** #672's scope extension to `intake-interviewer` is **operator-authored** —
`userContentEdits` shows both edits by `manoldonev`, the extension at 2026-08-24T20:45:07Z. #671's
arm-2 scope extension is honestly self-labelled "recorded by the #644 build session; not an
operator-authored edit", and is ratified by an operator comment on #671. #674 is operator-filed and
its premise holds: `lane_failure_class` is defined at `lean-gate.sh:3783` with exactly **one** caller,
`typecheck` at `:3856`, against a `docs/config-schema.md:22–33` that still claims four lanes.

**Mechanical evidence re-run at this head, not inherited.** Pre-registration untouched: `f174f1f` is
still the branch's first commit and the *only* commit touching it, and it is absent from the delta —
AC-1's substrate is intact. Every one of the branch's ten commits carries a `Changelog:` trailer.
The Decision Ledger lints clean (`ledger-lint: 10 ledger row(s): OK`), every row is four-column, and
the new rows' provenance is correct: `D-7`/`D-8`/`D-9` `user-answered` (each traceable to a tracker
artifact I verified), `D-10` `codebase-derived` — correctly *not* `user-answered`, since the operator
ruled that it be recorded while the substance was the run's own call. The evidence tree carries all 29
artifacts and c2's `scoring.tsv` shows 4 HIT / 1 MISS = the reported 0.80.

**CI at this head:** `lint-and-selftests` green, `mutation-sweep-pr` green. `pr-gates` is red at
**exactly one step** — step 7, lean chain reconciliation — and the log names the reason as this very
record: "verdict record reads 'verdict=needs-work', not 'verdict=approve'". Steps 3–6 (frozen files,
changelog trailer, guard budget, pipeline chain) all pass, so there is no second red hiding behind the
expected one.

### Per-AC scoring

| AC | Verdict | Basis |
| --- | --- | --- |
| AC-1 — pre-registration lands before any result, naming metric / sample / scoring rule / thresholds | **satisfied** | Re-verified at this head: `f174f1f` is the branch's first commit and its only commit; untouched by the delta. |
| AC-2 — each comparison over exactly its pre-registered sample, raw outputs + prompts + scoring committed | **satisfied** | Evidence tree complete (29 artifacts, all three arms with prompts + scoring + raw outputs). The path departure round 1 raised as W5 now carries ledger row `D-10` as a DEPARTURE; the AC is not amended to match, and it is a departure of location, not of coverage. |
| AC-3 — a verdict per comparison, citing the losing arm's evidence by path, none `undetermined` | **satisfied** | Three verdicts, none `undetermined`. Round 1's W2 (no verdict cites its losing arm by path) is partly improved — §2's new Departure section cites `c2-review/prompt-template.txt` by path — and otherwise unchanged; carried as a warning, not escalated. |
| AC-4 — every surface left standing records its re-measured P6 basis and date | **satisfied** (was the round-1 blocker) | `intake-interviewer` now records an explicit no-basis exit with its reason and successor #672, which is precisely the second of the two discharges round 1 prescribed. Scored on round 1's own reading of AC-4, under which an explicit `unmeasured — no basis` record is an acceptable form and the defect was a registered-in-scope surface vanishing without a successor. |
| AC-5 — any deletion leaves the sweep green with no orphans | **satisfied (vacuous)** | Still no deletion in the delta; §5 gives the evidence reason. Recorded as vacuous rather than as a green sweep proving something it does not. |
| AC-6 — `Changelog:` trailer, `Migration:` if a shipped skill is removed | **satisfied** | Trailer on all ten commits, including `ce36dff`. No shipped skill removed, so no `Migration:` owed. |

**6 of 6 satisfied.** No blockers.

### Warnings

| # | Location | Finding |
| --- | --- | --- |
| W1 | issue #644 scope item 2 | **The ticket's named `/code-review` comparison ships unmeasured.** The scope gate is right that declaration is not implementation — the comparison the ticket names is not in this diff. It is not a blocker here because the remedy was an operator ruling, carried as `user-answered` ledger row `D-7` and ratified on the tracker by an operator comment on #671, and because the direction-of-bias argument is sound: a prompt-only challenger is the weaker one, so the substitution could only depress the challenger's score and its failure mode is a false `keep`, never a false cut. C2 cut anyway. The verdict cannot move; the *title* of the number was what was wrong, and that is now fixed. Recorded here so the merge boundary sees the departure rather than inheriting it silently. |
| W2 | issue #644 scope item 3 | **`intake-interviewer` ships unmeasured**, same shape as W1: honest and complete record, ticket-named measurement absent from the diff, deferred by operator-authored amendment to #672. |
| W3 | `docs/skill-ablation.md` §4 | **The P6 bases live only in a central table; no `SKILL.md` points at them.** `grep -rn skill-ablation plugins/` returns zero, so `build-lean`, `review-lean` and `plan-interview` are individually silent about their own basis — the next generation change finds it only if it already knows this document exists. A one-line pointer in each of the three surviving skills would make AC-4's stated purpose self-executing. Not a scope miss; AC-4 does not specify where the record lives. |
| W4 | carried from round 1, unaddressed | W3 (the registered false-blocker tally is still never reported, against a pre-registration that promised "every near-miss adjudicated"), W4 (§1's mechanism claim is one session's generalised to both — all three cited line numbers are `bare-ablated-647`'s), and W6 (the 4,951 denominator counts 3 review-toolkit test fixtures; the shipped total is 4,881). None were in scope for this round's discharge and none are escalated. |
| W5 | PR body | "Eight bare sessions … committed verbatim" still undercounts: **ten** bare outputs are committed, and `bare-arm-timings.tsv` carries eight rows. The two missing are the C1 ablated sensitivity runs — the two that carry comparison 1's headline number, and so the two whose cost is most worth recording. A PR-body-only defect costs no round. |

### Strengths

- **The self-falsifying claim was fixed by pinning it to the head it was true at, not by softening it.** The tempting repair is to delete the sentence or hedge it into vagueness. Pinning keeps the claim falsifiable *and* makes it permanently true — and it is the only repair that survives the sentence being a file in the tree it greps. I could check it in both directions, which is the point.
- **B2's discharge names the mechanism, not just a successor.** Round 1 rejected #672 because it named a different skill. The fix's answer — an issue body is `intake-interviewer`'s output, not its input, and the reference set is the wrong ledger shape — is a claim about *why the metric structurally could not reach the surface*, and it verifies at source. That converts a deferral from an assertion into a finding.
- **The corrections are complete rather than local.** W1's "one → both" fix propagated to §2, the c2 README, §5's successor list and the PR body, with no residue anywhere; and `D-10` took `codebase-derived` rather than borrowing the operator's authority for a call the run actually made itself. Both are places where a smaller, self-serving edit was available and was not taken.
- **The pre-registration is still one commit and still untouched**, under direct pressure to edit it — which is what keeps AC-1 meaningful and is the whole reason a pre-registration is worth reading.

**Ready to merge?** Yes — 0 blockers, 6 of 6 ACs satisfied. Two ticket-named comparisons ship
deliberately unmeasured under verified operator rulings with named, operator-ratified successors
(#671 arm 2, #672); both are recorded above as warnings so the departure is visible at the merge
boundary rather than inherited in silence.
