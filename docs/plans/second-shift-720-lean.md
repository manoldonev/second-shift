# second-shift #720 — milestone 4 stops re-checking what the merge boundary already checks

Pure deletion. `cmd_4` carries six refusal sites that re-ask a question
`lean-evidence.sh` — run by `pr-gates` and by every consumer's merge boundary — already
refuses. The scheduler's routing needs three local answers from milestone 4: absent (rc 5),
not-approve (rc 1), identity (rc 6). Nothing here adds a check, moves one into another file,
or widens one.

## Base measurements

The ticket's figures were taken against the rev-4 draft's head. Re-derived at this branch's
base, `origin/main` = `630b1f8`:

| Figure | Ticket | At `630b1f8` | Why it moved |
| --- | --- | --- | --- |
| `grep -cE '(fail\|block)_milestone 4[ ]'` | 19 | **21** | #708/#729 added two armed-path panel sites, both keepers |
| `grep -c 'fail_milestone 4 "'` (the `(ac1)` pin) | — | **20**, sig `11112255555555555566` | same |
| `wc -l` of `lean-gate.sh` + `lean-gate-selftest.sh` | 13,703 | **14,401** (5,922 + 8,479) | ordinary growth since the draft |
| distinct `pass`/`fail` ids in `lean-gate-selftest.sh` | "542/520" | **561** distinct ids | the draft's basis is not reconstructible; an id-set delta is used instead |

## The six sites deleted (`lean-gate.sh`, line numbers at `630b1f8`)

| Site | Class | Refused at the boundary by |
| --- | --- | --- |
| `:4536` verdict record carries no `run_id` | 5 | `arm_verdict` |
| `:4539` verdict record carries no `session_id` | 5 | `arm_verdict` |
| `:4647` INFERRED patch-stale (`git diff <verdict-commit> HEAD`) | 5 | `arm_freshness` |
| `:4737` verdict record carries no `reviewed_patch_id` | 5 | `arm_freshness` |
| `:4742` patch identity uncomputable | 2 | `arm_freshness` (`envfail`) |
| `:4752` DECLARED patch-stale | 5 | `arm_freshness` |

Kept, unchanged: absent `:4527`, not-approve `:4530`, `reviewed_head` `:4547` (the boundary
refuses no record for its absence, so this is not a duplicate), identity `:4571`/`:4576`,
uncommitted `:4598`/`:4605`, chain `:4631`, the seven fidelity/render sites `:4688`–`:4714`.

Three helpers become unreachable once both stale arms go and are deleted with them:
`contribution_delta`, `contribution_summary`, `contribution_state`. `lean-evidence.sh` keeps
its own copies — it is the reader that still needs them. `branch_patch_id` and
`render_patch_id` stay: `cmd_verdict` and milestone 3 still call them.

## Acceptance criteria

- **AC-1** `grep -cE '(fail|block)_milestone 4[ ]' plugins/dev-pipeline/skills/build-lean/lean-gate.sh`
  = **15** (base 21). The suite's own completeness pin `(ac1)` reads **14** `fail_milestone 4 "`
  sites with class signature `11112555555566` (base 20 / `11112255555555555566`) — the same fact,
  counted by the guard that owns it. *Mutant:* one duplicate left → 16/15; one keeper deleted → 14/13.
- **AC-2** The distinct-id set of `lean-gate-selftest.sh`
  (`grep -oE '(pass|fail) "\([^)]*\)' | sed -E 's/^(pass|fail) "//' | sort -u`) at head equals
  the base set minus **exactly** these, and gains none:

  | Deleted id | Why |
  | --- | --- |
  | `(j3)`, `(j3b)`, `(u2)`, `(v4)`, `(v5)`, `(vb2)`, `(t2)` | listed in the ticket; each pins a deleted site |
  | `(vb-baseline)`, `(vb1)`, `(vb3)`, `(vb4)` | the ticket's discretionary set. **Deleted** — the fail-open path they pin lives inside the two stale arms, so it does not survive. `lean-evidence-selftest.sh` `(s2)`/`(s4)` keep the boundary's copy of it covered. |
  | `(u3)`, `(v0)`, `(v1)`, `(v2)`, `(v3)`, `(v3a)`, `(v4-fixture)`, `(vb-fixture)`, `(vb0)`, `(vb4a)` | not listed, but mechanically forced: each is a non-vacuity or fixture guard **for** a deleted case, and `(u3)`/`(v1)`/`(v2)`/`(v3)` additionally grep the pass line's `patch-id` text, which the deletion removes. `(x1)` already pins that the real writer stamps `reviewed_patch_id`. |
  | `(v5-fixture)` → renamed `(v6-fixture)` | it guards the `CFG_NOBASE` fixture, which `(v6)` still needs |

  **`(v6)` is KEPT, against the ticket's list.** It drives `bash "$GATE" verdict … --verdict approve`
  — `cmd_verdict`, the writer, not `cmd_4` — and asserts the writer refuses an unresolvable base
  rather than omitting the key. That arm is a keeper, and after this change it is the *only* thing
  standing between a key-less record and the merge boundary. Deleting its pin would drop live
  coverage of a surviving site, which is the botch AC-3 exists to catch.
- **AC-3** `(j1)` still pins rc 5, `(n1)`/`(n2)` (the milestone-4 pair) rc 6, `(j2)` rc 1 —
  unchanged and green. `(u1)` (`reviewed_head` absent, rc 5) likewise.
- **AC-4** `bash tools/gate-ablation.sh check` byte-identical to base; `bash scripts/check-gate-buckets.sh`
  green with its six now-orphaned rows removed. `tools/gate-ablation-classes.tsv` keeps **both**
  `m4/verdict-keys` and `m4/patch-stale` rows — the table reads history, not the current gate, and
  `m4/verdict-keys` still has a live site (`reviewed_head`). Only column 6 (`earn_your_keep`, which
  `gate-ablation.awk` does not read) is amended, so the generated block cannot move.
- **AC-5** `lean-gate.sh` + `lean-gate-selftest.sh` at head ≤ **14,151** (base 14,401 − 250).
  `git diff --quiet origin/main -- plugins/dev-pipeline/skills/build-lean/lean-evidence.sh` and
  `-- scripts/check-lean-chain.sh` both exit 0. *Mutant:* any edit to either.
- **AC-6** `plugins/dev-pipeline/skills/build-lean/scenario-liveness-selftest.sh` loses legs 5, 7
  and 7b and the head-declaring half of leg 6, and keeps leg 3d `(lean-taxonomy)` and leg 4
  `(lean-authorship)` green. CLAUDE.md's rule cuts both ways: a deleted gate contract shrinks the
  liveness scenario, and leaving those legs in place would assert a contract that no longer exists.
- **AC-7** Doc updates, AC-scoped: `plugins/dev-pipeline/skills/build-lean/SKILL.md` step 8 and its
  "Any CONTENT pushed after an approve" rule no longer claim milestone 4 compares
  `reviewed_patch_id` against this branch's patch; `docs/testing.md`'s verdict-record-key lockstep
  entry no longer cites deleted cases; `docs/testing.md`'s never-fired-points section records this
  deletion the way it records #642's.
- **AC-8** `bash tools/mutation-sweep.sh --mode pr --base origin/main` table in the PR body; no
  `anchor drift`.

## Decision Ledger

No pre-flight ledger exists for this ticket. These are the calls this build made against the
issue text, each forced by the code at the current head rather than chosen.

| id | Decision | Resolution | Provenance |
| --- | --- | --- | --- |
| D-1 | The ticket's AC-1 target of 13 | Re-derived to 15 — 21 sites at base, minus the same six. | codebase-derived |
| D-2 | The ticket's AC-5 base of 13,703 | Re-derived to 14,401. | codebase-derived |
| D-3 | `(vb-baseline)`/`(vb1)`/`(vb3)`/`(vb4)` — "delete with the arm they pin, or keep if the path survives; state which" | Deleted: the path does not survive. | codebase-derived |
| D-4 | `(v6)`, listed for deletion | **DEPARTURE — kept.** It pins `cmd_verdict`, not `cmd_4`; no milestone-4 site backs it, and deleting it would remove coverage of a surviving arm. | codebase-derived |
| D-5 | Ten unlisted companion ids | Deleted with the cases they exist for; each named in AC-2. | codebase-derived |
| D-6 | `scenario-liveness-selftest.sh`, unmentioned by the ticket | In scope (AC-6): its legs 5/6/7/7b assert the deleted arms and go red otherwise. | codebase-derived |
| D-7 | `m4/patch-stale`'s classes row | Kept, per the file's own "reads history, not the current gate" rule; `earn_your_keep` amended. | codebase-derived |
