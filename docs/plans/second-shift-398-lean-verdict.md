# lean review verdict — #398

verdict=needs-work
run_id: review-398-1
session_id: 3344aa21-451e-461a-af6c-b50679b4b84a
rounds: 1
pr: #407
reviewed_head: d35ecdb1ccf4b03a38baa8aceec879b50e34df18
reviewed_patch_id: 7a97e089c1e0bd8fe47bdb09178712f7589587c4
inherited_patch_id: none
inherited_from_verdict: none
model: unknown

## Round 1 — full branch diff (`ca79bbf..d35ecdb`, 3 files)

Range from `lean-gate.sh delta 398`: FULL — nothing verifiable to inherit, root round.

Reviewers dispatched via `code-review.mjs`: maintainability, scope-completeness, security,
performance. All four returned. Trivial-inert routing would have selected only the first two;
security and performance were added because in this repo `plugins/**/skills/**` prose IS the
product's execution surface, and both returned clean with no surface to assess. Complexity,
test-coverage, db, pipeline, unit-test-mutation not selected (no trigger). a11y and the
design-fidelity dimension not routed: no changed path matched the web-component surface.

### Findings

| # | Severity | Location | Finding |
| --- | --- | --- | --- |
| 1 | **Blocker** | commit `d35ecdb`, message body | The trailer reads `Changelog: none — internal doc consistency fix, no consumer-visible behavior change.` That is **not** the no-op form. `derive-release.sh`'s `render_bullet` normalizes a trailer block by case-folding and stripping trailing whitespace and **one** trailing period, then suppresses it only when the whole block equals `none`. This block does not, so it renders as an indented bullet body under the release-note entry. Reproduced by feeding the real commit body through the production `extract_trailers` and `render_bullet` awk programs verbatim: output is the literal line `  none — internal doc consistency fix, no consumer-visible behavior change.` `check-changelog-trailer.sh` asserts presence only (`grep -cE '^Changelog:'`), so no lane reds on it and the bad bullet reaches `CHANGELOG.md` at release time. This is the same defect flagged on the #401 round. Fix: rewrite the trailer on the commit to the bare `Changelog: none.` — a message-only rewrite, so the patch is unchanged and this round's coverage carries over. |
| 2 | Warning | `run/tools/tracker/README.md:43`, and `docs/plans/second-shift-398-lean.md:14-15` | AC-2 requires leaving `"lean-gate.sh … branches at exactly **three** sites"` unchanged on the grounds that it is correct, and the spec commits that as verified fact. It is not: the sentence was written in #365 (`312a0b4`), when the file's four `[ "$TRACKER_TYPE" = "jira" ]` conditionals grouped into three lane-operation sites (entry note, claim, exit×2). #376 (`d5b3fa5`) added a fifth conditional at `lean-gate.sh:775` — `check_pause_and_ask`'s early return — which is a milestone-3 gate check, not entry/claim/exit. So the count is stale by one under exactly the same convention that made it right, and by exactly the drift mechanism this PR exists to remove. The neighboring `lean-reconcile.sh` "exactly **one**" is the same class and was already flagged as W2 on the #388 verdict record; it has gone 0→3 conditionals since. **Not a blocker and not fixable here** — AC-2 positively mandates the sentence be untouched, so no implementation satisfying this spec could have fixed it. Route to a follow-up issue covering both sentences. |

Suppressed (below threshold): security — new spec doc scanned for embedded credentials, none
present, no executable surface (confidence 30).

### Acceptance criteria

| AC | Score | Evidence |
| --- | --- | --- |
| **AC-1** | satisfied | Both sites drop the count and keep the pointer: `README.md:24-25` now reads "the lean lane's adapter-sensitive operations follow it"; `jira/README.md:14` reads "The lean lane's adapter-sensitive operations are tabulated in `../README.md`". A repo-wide grep for `adapter-sensitive` across `*.md`/`*.sh`/`*.mjs` returns no surviving prose count of lane operations outside the plan/verdict archive. Neither sentence can now disagree with the table. |
| **AC-2** | satisfied (by its letter) | The diff is two lines, at `README.md:24` and `jira/README.md:14`; `README.md:43` is byte-unchanged, and the paragraph still separates gate branch sites from the lane operation table below it. Scored on the letter — the accuracy of the sentence it preserves is finding 2, outside the AC set. |
| **AC-3** | satisfied | Diff touches three Markdown files and nothing else — no `.sh`, `.mjs`, CI workflow, or selftest. `lint-and-selftests` pass (7m40s); `selftests (macos, bash 3.2)` pass (10m41s). `pr-gates` is red on one violation only — "no committed verdict record" — which is the expected pre-review state, cleared by this record. |
| **AC-4** | satisfied (by its letter) | `d35ecdb` carries a `Changelog:` line, which is all AC-4 asks. The defect is in the trailer's *form*, not its presence, so it is carried as blocker 1 rather than scored here. |

### Verdict

`needs-work` — one blocker. The prose fix itself is right, and the reasoning for dropping the
count rather than bumping it to four is the durable choice: it removes the coupling instead of
re-pinning it, so the next row addition cannot restale these two sentences. The blocker is the
commit trailer, and its remedy does not touch the patch.
