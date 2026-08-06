# lean review verdict — #394

verdict=needs-work
run_id: review-394-1
session_id: d9d12f80-c3cd-4f3a-9950-6f45f0949368
rounds: 1
pr: #404
reviewed_head: 156d3234036be558eabb927c507b266848a1d6bd
reviewed_patch_id: d83eea4fba63f1a6fca12fe4df50164b3707c0c8
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown

## Round 1 — `lean/second-shift-394` (PR #404)

Range read: `ab12060..156d323` (chain root — the whole branch diff, 17 files). Verdict
**needs-work**: 9/9 ACs satisfied, 2 blockers outside the AC set, 3 warnings.

Verification re-run from this checkout, not taken on report: `shellcheck` rc=0, `jq empty`
rc=0, and the full `*-selftest.sh` sweep **without `SKIP_STRESS`** and under
`env -u CLAUDE_CODE_SESSION_ID` rc=0 (59 suites green, incl. `lean-gate-selftest`,
`check-lean-chain-selftest`, `lean-reconcile-selftest`, `scenario-liveness` 73/0).
`pr-gates` red is the expected pre-review state — its only violation is
`no committed verdict record`, and the new arm printed
`· spec declares no armed design render lane — design evidence not applicable` on this
branch's own run, which is the boundary arm executing live.

### Findings

| # | Class | Where | Finding |
| --- | --- | --- | --- |
| B1 | blocker | `lean-gate.sh:1320-1322` | An `&` anywhere in a declared route, state or output path is replaced by the **matched placeholder** on bash ≥ 5.2 — the harness renders the wrong view and every other assertion still passes. |
| B2 | blocker | commit trailers (all three) | `Changelog: none.` on a change that adds a blocking gate, a new milestone-1 refusal for existing `design.provider` consumers, and a new reviewer flag. The release notes render nothing. |
| W1 | warning | `lean-gate.sh` `design_was_armed` | The mid-run-disarm lock lives in the uncommitted machine-local progress file, so "the one escape this design must not leave open" is closed only within one worktree on one machine. |
| W2 | warning | PR body + `156d323` message | "Every operator on `check-lean-chain.sh` and `lean-reconcile.sh` … is byte-for-byte where it was" is true only inside the swept window. |
| W3 | warning | `run-lean/SKILL.md` | The 60-line cap was met by unwrapping prose, not by cutting it: 60 → 42 lines while the file grew 575 → 972 words. |

---

#### B1 — blocker. `&` in a placeholder value is spliced back as the placeholder (bash ≥ 5.2)

`cmd_3_render` substitutes each value with bash pattern replacement:

```sh
ecmd="${ecmd//\{route\}/$(shquote "$r_route")}"
ecmd="${ecmd//\{state\}/$(shquote "$r_state")}"
ecmd="${ecmd//\{out\}/$(shquote "$png")}"
```

Since bash 5.2, `patsub_replacement` is **on by default**: an unescaped `&` in the
replacement string expands to the text the pattern matched. `shquote` quotes for the
*shell*; it does nothing about the *replacement* layer above it.

Reproduced through the real gate (not a probe), same fixture, same spec, two interpreters —
spec rows `| RS-2 | prospects?tab=new&sort=asc | filters & sort expanded | AC-1 |`:

```
########## /opt/homebrew/bin/bash (5.3.9)
[lean-gate] milestone-3: render RS-2 (prospects?tab=new&sort=asc » filters & sort expanded) »
  bash …/stub.sh --route 'prospects?tab=new{route}sort=asc' --state 'filters {state} sort expanded' --out '…/RS-2.png'
STUB-RECEIVED route=[prospects?tab=new{route}sort=asc] state=[filters {state} sort expanded]

########## /bin/bash (3.2.57)
[lean-gate] milestone-3: render RS-2 (prospects?tab=new&sort=asc » filters & sort expanded) »
  bash …/stub.sh --route 'prospects?tab=new&sort=asc' --state 'filters & sort expanded' --out '…/RS-2.png'
STUB-RECEIVED route=[prospects?tab=new&sort=asc] state=[filters & sort expanded]
```

macOS system bash (3.2) is correct; every modern Linux and every homebrew bash is not. The
repo's own `lint-and-selftests` job runs on ubuntu (bash 5.2.x) beside its dedicated
`selftests (macos, bash 3.2)` job, so this is a live platform split, not a hypothetical.

Why it is blocker-class rather than a nit:

- **It is failure class (2), reinstated.** The render exits 0; the PNG is non-empty; two rows
  still hash differently (they were shot at different wrong states); the collision detector is
  silent; the manifest is written and committed. The manifest records the **declared** route
  and state, so it is honest about intent and silently wrong about what was captured — which
  also disarms the reviewer's step-5b hash-verify, since the hashes agree on the wrong
  screenshot. Nothing in the gate, the receipt, the boundary or the review protocol can see it.
- **It is the very defect this PR narrates fixing.** The `shquote` block and the docs' new
  "Placeholders appear UNQUOTED in the template" bullet were added because a two-word state
  arrived as two arguments. The quoting contract the docs now assert is not kept on the
  majority interpreter.
- **The trigger is ordinary.** `{route}` is documented as "the app-relative leaf below your
  feature mount path"; a query string (`?tab=new&sort=asc`) is a routine leaf. A state is
  human prose, where `&` is ordinary punctuation.

Remedy is at the substitution layer, not in `shquote` — `\&` is the literal-escape on 5.2+
and a literal backslash-ampersand on 3.2, so escaping is itself version-split. Splitting on
the placeholder avoids the replacement layer entirely and is bash-3.2 safe:

```sh
subst() { # subst <template> <placeholder> <replacement>
  local t="$1" p="$2" r="$3" out=""
  while case "$t" in *"$p"*) true ;; *) false ;; esac; do
    out="$out${t%%"$p"*}$r"; t="${t#*"$p"}"
  done
  printf '%s' "$out$t"
}
```

Guard it where the AC already looks: the `(dr2a)` stub call-log assertion is the right
oracle — it asserts the exact substituted pair. One RS row carrying `&` in both route and
state, asserted through that same log, kills this and would have killed it on the ubuntu lane
today.

#### B2 — blocker. `Changelog: none.` on a consumer-visible, migration-bearing change

All three commits carry `Changelog: none.`:

```
156d323 fix(dev-pipeline): keep the chain gate's mutation ordinals where they were   Changelog: none.
9482a1a feat(dev-pipeline): the lean lane gates design live-render fidelity          Changelog: none.
cbcce96 docs(dev-pipeline): spec for the lean lane's design live-render gate         Changelog: none.
```

`derive-release.sh`'s `render_bullet` normalizes case, trailing whitespace and a trailing
period, and drops any block that is entirely the no-op word — so `none.` renders **nothing**.
This release will carry one bare subject line for a change that:

- adds a **blocking** milestone-3 render lane on the shared 3-attempt budget;
- adds a **milestone-1 refusal** that reds *every* lean run in any repo with `design.provider`
  configured until each ticket's spec grows a `## Design` section (`design_state()` returns
  `error:` on a configured provider with no section — a behavior break for existing consumers,
  and per the memory of consumer state that is not a hypothetical population);
- adds `--fidelity` to the `review-lean` write command, defaulting fail-closed;
- adds a `{state}` placeholder to `design.liveRender.command`;
- supersedes `docs/live-render.md`'s `extraLanes` wiring recipe that consumers were told to use.

CLAUDE.md scopes the opt-out precisely: "Use `Changelog: none` when nothing is
consumer-visible." Every bullet above is consumer-visible, and the first two carry a migration
obligation with no home to be written in. This is the same class as #401 round 1 and #384
round 1: a trailer that ships wrong, that CI's presence-only
`check-changelog-trailer.sh` cannot red on, and that is only fixable by rewriting history.

The remedy is #401's shape — one accurate block on the **last** commit, bare `Changelog: none.`
on the in-progress ones — with a `Migration:` line naming the `## Design` requirement. While
rewriting, settle the bump level explicitly: `feat:` derives a **minor**, and a gate that reds
previously-green runs for configured consumers has a `BREAKING CHANGE:` argument. I am not
ruling on it; it should be a decision in the fix round rather than a default nobody chose —
which is, exactly, D-8's own principle.

#### W1 — the mid-run-disarm lock is machine-local

The spec calls mid-run disarm "the one escape this design must not leave open" (AC-2), and
`design_was_armed()` closes it by grepping `| milestone-3 | armed |` out of
`$MAIN_ROOT/$STATE_DIR/<issue>-lean-progress.md` — uncommitted, machine-local, and absent in a
fresh worktree or on a second machine. A resumed run elsewhere reads no lock and accepts the
disarm; the merge boundary then reads a disarmed spec, which its own header concedes is
"indistinguishable here from honest unarmed work".

This is consistent with the file's declared trust posture (local records are tamper-evidence,
not integrity) and the residual — review-lean's unjustified-disarm blocker — is both stated
and now shipped. So this is a warning about the **strength of the claim**, not the design: the
lock is a within-worktree guard, and (dl2)/(dl3)/(dl5) prove exactly that much. Worth one
clause in the spec or the in-code comment so a later reader does not inherit "cannot be
escaped" as a load-bearing property.

#### W2 — the mutation-ordinal claim is stronger than what holds

The PR body and `156d323`'s message both say every operator on `check-lean-chain.sh` and
`lean-reconcile.sh` "is byte-for-byte where origin/main had it". Enumerating each operator's
matched-line list from `tools/mutation-operators.tsv` against `ab12060` and `HEAD`:

- `lean-reconcile.sh` — all six operators unmoved. Claim holds.
- `check-lean-chain.sh` — ordinals **1–2 hold** on every operator, which is the whole swept
  window at `K_BUDGET=2`. But ordinal 3+ did move on `cmp-eq`, `cmp-z` and `logic`: the new
  `lean-design-armed` block introduced two prose sites (`Armed-ness` matches `-ne`;
  `` `| RS-n |` `` matches `-n `) that displaced the previous ordinals 3–4.

Nothing swept moved, no baseline row is wrong, and CI proves it — the PR-scoped sweep reports
survivors exactly equal to the baseline set, with `check-lean-chain.sh::cmp-z::2` (the
`sed -n '2,Np'` help-range mutant `156d323` went back for) **killed**. The verification is
sound; only the sentence overreaches. The accurate form is "no ordinal inside the swept window
moved"; the stronger claim would break the moment anyone raises `MUTATION_SWEEP_K`, and the
next reader re-deriving it will find the difference and not know which half to trust.

AC-9 is scored satisfied on the CI sweep's actual survivor set, not on this sentence.

#### W3 — the 60-line cap was met by unwrapping

`run-lean/SKILL.md` goes 60 → **42** lines while growing 880 → 972 words (`prose-budget.sh`:
575 → 972, its baseline row now the largest relative miss in the dev-pipeline block). The cap
is an anti-process-accretion forcing function; measured as `wc -l` over lines with no length
bound, it stops being one — this diff added a checklist clause to steps 4, 6 and 8 and came
out 18 lines *under*.

Two things keep it off the blocker list: AC-8 named the re-flow **up front** rather than
amending to match what shipped, and the file was already partly unwrapped before this diff
(the tracker-delta blockquote, the post-approve rule, the Resume paragraph), so this continues
a trend rather than starting one. But the cap now asserts nothing, and the next change will
have even more room. Either bind a line length alongside it or re-express the cap in the units
`prose-budget.sh` already measures.

---

### Per-AC scoring — 9/9 satisfied

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 milestone-1 arming forms | **satisfied** | `(dz1)` no-section red, `(dz2)` explicit-empty green, `(dz5)` bare `Design: none` refused, `(dz6)` missing handoff link, `(dz7)` neither-form. The AND→OR executioner is real: `(dz3)` reads the **same armed spec** through `$CFG` (no design axis) and requires a silent unarmed pass, and `(dz4)` reads it back through `$DCFG` and requires `design lane ARMED`. Under an OR reading `(dz3)` reds — the mutant is genuinely killed, not merely described. |
| AC-2 disarm state-lock | **satisfied** | `(dl1)` the `\| milestone-3 \| armed \|` row is written by a **passing** armed evaluation; `(dl2)`/`(dl3)` the disarm reds at milestone 1 *and* 3; `(dl4)` zero `\| attempt \|` lines, so arming spends no budget; `(dl5)` the identical disarm passes with no armed record, which is what makes `(dl2)`/`(dl3)` turn on the lock rather than the wording. Scope caveat in W1. |
| AC-3 the render pass | **satisfied** | Every enumerated clause lands: `(dr1)` 2 rows / 2 calls / 2 non-empty PNGs + red-until-committed; `(dr2b)` a **recomputed** sha256 matches its manifest cell; `(dr3)` identical-hash collision; `(dr4)` zero-byte; `(dr5)` nonzero exit + no manifest; `(dr6)`/`(dr6b)` `{state}` required only on a non-default row, with the positive half asserting the run *reaches* the render; `(dr7)` missing `{out}`; `(dr8)`/`(dr9)` `check-ignore` driven red **and** green; `(dr10)` foreign `cwd`; `(dr11)` duplicate RS id. `(dr2a)` asserts the substituted pairs from the stub's own call log. Scored by its letter — B1 is a defect the AC's clause list does not reach, not an unmet clause. |
| AC-4 idempotence | **satisfied** | `(di1)` a committed receipt re-runs with the call count unchanged; `(di1b)` deleting one PNG **pre-verdict** re-renders, so the receipt alone is not yet the evidence; `(di2)` post-approve passes on `rendered_from` with the whole PNG directory deleted. The three together pin the asymmetry rather than just the happy arm. |
| AC-5 the verdict key | **satisfied** | `(fd1)` enum; `(fd2)` unconditional emission of the default; `(fd4)` `fail` × `approve` refused at the writer; `(fd5)` armed run refuses the default; `(fd5b)` passes on a header-scored `pass`; `(fd6)` unarmed tolerates absence; `(fd7)` unarmed refuses a non-`not-applicable` value. `(fd3)` is the load-bearing one — it puts `fidelity: pass` in the record's **body via `--summary-file`**, the production path a reviewer's findings actually arrive through, and requires the armed refusal anyway. |
| AC-6 the boundary arm | **satisfied** | `(W1)` vacuity guard first; `(W2)` armed-with-no-receipt; `(W2b)` the `-lean-renders.md` suffix does not shadow the `*-lean.md` first-match spec scan; `(W3)` no fidelity; `(W4)` happy path with both exclusions asserted together; `(W5)` stale `rendered_from` under a **fresh** verdict, with the negative assertion that no other freshness arm fired; `(W6)` disarmed leaves it not-applicable. Plus live evidence: this PR's own `pr-gates` run printed the not-applicable note. |
| AC-7 scenario legs | **satisfied** | Seven `(lean-design-*)` legs, `scenario-liveness` 73 passed / 0 failed here. They compose rather than restate: `budget` walks `1114` to `rc=4` while asserting armed=1 / attempts=4; `render` reds then greens on the same evaluation; `verdict` runs `1/0/1` across unscored → scored → stale; `terminal` reaches the milestone-5 write with every PNG deleted **and** asserts nothing re-rendered; `nv` is an explicit non-vacuity leg. |
| AC-8 docs | **satisfied** | Both named out-of-section stale assertions are gone — the "no Stage-5 and no `design.liveRender` key" pointer is rewritten to the two-lane split, and the unqualified "Failure is non-blocking" bullet is now the per-lane posture bullet. `docs/config-schema.md` and the JSON schema both state the split and `{state}`. `run-lean/SKILL.md` is 42 ≤ 60 (see W3). The review-lean 5b step, its four design blockers, and review-lead's pixel-loop sentence all land. A `Changelog:` trailer **is** present on the branch — B2 is about what it says, which this clause does not constrain. |
| AC-9 mutation | **satisfied** | Verified against CI's actual sweep, not the claim: survivors are `lean-gate.sh::{cmp-eq::1, default::1, default::2}`, `check-lean-chain.sh::{cmp-eq::1, cmp-eq::2, cmp-z::1, default::1, default::2}`, `lean-reconcile.sh::{6}` — every one a baseline row, none absent, and `check-lean-chain.sh::cmp-z::2` killed. `lean-gate.sh::default::2` re-keyed to the `${CURL:-curl}` Seams comment and re-baselined in the same diff; independently confirmed by enumerating the `default` operator on both revisions — new ordinal 2 is the comment, ordinal 3 is the displaced `GH_CLI="${GH:-gh}"`, exactly as the row states. `retro-corpus.sh`'s citation is corrected. Both lockstep rows plus the new `lean-design-armed` row are green. Wording caveat in W2. |

### What is genuinely good here

The two-patch-identity asymmetry is the part that would be easiest to get wrong and is right:
the manifest **inside** `reviewed_patch_id` so a verdict binds to the evidence it scored, and
**outside** `rendered_from` so committing that evidence — and the reviewer committing on top of
it — does not invalidate it. The post-approve arm dropping the PNG-byte dependency is the same
insight applied once more, and `(di2)` + `(lean-design-terminal)` prove the livelock is closed
from both the unit and the composed direction. `(fd3)` and `(W5)`/`(dm1)` are the two cases a
weaker suite would not have written: one drives the header-anchoring through the real
`--summary-file` path, the other constructs the single tree where the receipt is the *only*
stale artifact and asserts the other freshness arms stay silent.

### To clear round 2

1. Fix B1 at the substitution layer and add the `&`-bearing RS row to the `(dr2a)` call-log
   assertion.
2. Rewrite the trailers for B2 — one accurate `Changelog:` block with a `Migration:` line on
   the last commit, and settle the bump level explicitly.
3. W1–W3 are optional; if W1 is left as-is, soften the "one escape this design must not leave
   open" phrasing so the next reader does not inherit it as a guarantee.

Everything else is inherited by this record. A new review context scores round 2 — not this
one resumed.
