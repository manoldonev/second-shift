# lean review verdict — #445

verdict=approve
run_id: review-445-1
session_id: bfb5fea5-2638-4a56-9a4d-12053229c7cb
rounds: 1
pr: #471
reviewed_head: 626977323727e5e1323df80d467bbee5fdd11437
reviewed_patch_id: e4a15ae5de8a4e3cd59143cd730ef1a3baf9a086
inherited_patch_id: none
inherited_from_verdict: none
fidelity: not-applicable
model: unknown
capabilities: pr-marker

## Verdict: approve — round 1

Reviewed the whole branch diff (`b1a4c0d..6269773`, 12 files, +663/−35). Round 1, nothing to
inherit.

The mechanism is sound and — unusually — it is proven on a corpus run rather than only on
fixtures. This PR's own `pr-gates` job (run 31367541762) reports:

```
[lean-evidence]   · identity: inert — no bot-authored 'lean-claimed' comment on #445 carries a
'capabilities:' stamp, so this run's producer predates the stamp and cannot be shown to ship
'pr-marker'. …
```

The claim comment on #445 was posted by the pre-token producer, so the bound arm degraded exactly
as AC-1 specifies, on a live PR, while every other arm kept gating (the run still reds on the
missing verdict record). That is the failure this ticket exists to close, observed closing itself.

### Findings

| # | Severity | Where | Finding |
| --- | --- | --- | --- |
| 1 | warning | `scripts/check-lean-chain-selftest.sh:1233` | Duplicate case id `(Y5)`. The new pre-token delegation case and the pre-existing "an unreachable evidence payload is an environment error" case at :1292 both label themselves `(Y5)`; every other id in that file appears exactly once. Case ids are the addressing scheme `tools/mutation-catalog.tsv` rows and PR bodies anchor on — this PR's own body says "`(Y5)` through the delegating boundary", which now names two things. One-character rename. No guard is weakened. |
| 2 | note | `scripts/check-lean-chain.sh:388` / `lean-evidence.sh:426` | The live path pays two identical `GET /repos/{repo}/issues/{key}/comments` calls — the boundary fetches the claim trail for its own claim arm at :534, the payload fetches it again for the stamp. The forward at :388 only fires when a fixture is present, and the boundary's own fetch happens after `PAYLOAD_ARGS` is built, so this is not free to collapse. Documented in-file as deliberate. Recording it so the next person does not read it as an oversight. |

No blockers.

### AC scoring

| AC | Score | Evidence |
| --- | --- | --- |
| AC-1 — no stamp ⇒ every bound arm `inert` via class (b), zero violations | satisfied | `(ad1)`, `(Y5@1229)`, `(lr5)`; and the live `pr-gates` line quoted above. All fixture cases run on `markers-none.json`, which violates whenever the arm evaluates, so rc=0 can only mean a decline. |
| AC-2 — stamp declaring the capability ⇒ enforces as before | satisfied | `(ad2)` (rc=1, `no bot-authored`, no `inert`), `(ad4)`. Structurally: 27 pre-existing `check-lean-chain-selftest.sh` cases were re-based onto stamped trails rather than left to pass by declining. |
| AC-3 — stamp not declaring it ⇒ `inert`, not a violation | satisfied | `(ad3)`, which asserts the stamped set (`capabilities: design-render`) appears in the reason — a gate testing only "some stamp exists" reds here. |
| AC-4 — stamp on claim comment AND verdict record; lockstep row binds the spelling | satisfied | `(pc1)` (claim), `(pc2)` (record), `(pc3)` (closed-vocabulary refusal, driven through a sandboxed copy of production bytes). Two `verbatim` rows, `lean-producer-capabilities-{evidence,chain}`, one canonical writer with two readers per the `lean-inherited-key-*` precedent. `lint-and-selftests` green ⇒ the lockstep check passes on all three copies. This very record is the first real-corpus exercise of the D-7 write. |
| AC-5 — a fixture pins the pre-token generation | satisfied | Three, at each tier: `claim-unstamped.json` (per-tool), `comments-pretoken.json` (delegating boundary), `LR_CLAIM_PRETOKEN` (liveness scenario). |
| AC-6 — contributor paragraph in `docs/testing.md` | present, not scored | Explicitly non-scored by the spec; repo convention forbids prose-presence guards. Paragraph is at `docs/testing.md:167`. |
| AC-7 — jira consumers not capability-bound | satisfied | `[ "$TRACKER_TYPE" = "github" ] || return 0` at `lean-evidence.sh:462`, guarded by `(ad7)` on the violating marker trail so it cannot pass by declining. The reasoning — a read-only tracker writes no claim comment, so binding would disarm the strongest boundary arm permanently rather than transitionally — is correct and is the right call. Scoring it as an AC rather than leaving it a silent narrowing was the right disposition. |
| AC-8 — unreadable claim trail declines, never exits on an environment error | satisfied | `(ad6)` asserts rc=0, one class-(b) line, and the reason naming `GH_REPO is unset`. The three unreadable paths (no seam + no repo, failed fetch, non-array response) all land on the same named decline. This is the one non-`exit 2` fetch in the file and it says why on the line. |
| AC-9 — pre-existing enforcing cases still exercise the enforcing path | satisfied | Verified independently rather than taken from the PR body. `ev`/`ev_cfg` default to `claim-stamped.json`, so every case above the `(ad)` block keeps enforcing; the four direct-invocation cases were each checked — `(ab4)` got the seam, `(cc2)`'s stub now routes on the endpoint (serving one file to both trails would have turned it into a green proving nothing about the fetch it is named for), `(cc1)` refuses before any arm runs, `(dd*)` do not reach identity. On the boundary side `(N1)` and `(Y1)`–`(Y4)` all run on the now-stamped `comments-good.json`. `(Z1)`/`(Z2)` assert `identity: postdated` literally, which pins D-6's ordering: a capability gate evaluated before `since:` would print `inert` there and red them. `(lr4)` moved onto a stamped trail and its after-side now excludes both `postdated` and `inert`. The three unstamped claim trails still in `scenario-liveness-selftest.sh` (:1060, :1535, :1745) feed `lean_gate 5`, the producer's own mark milestone — no boundary arm runs against them. |

### Design fidelity

`not-applicable`. The spec declares no `## Design` section and the change is entirely shell gate
logic, CI permissions prose and selftests — no rendered surface exists.

### What was checked beyond the ACs

- **Spec integrity.** `docs/plans/second-shift-445-lean.md` was committed in `cf64c24` and never
  touched again — no post-hoc amendment to match the diff.
- **Frozen files.** No `plugin.json` version, no `CHANGELOG.md`, no `marketplace.json`. Every
  commit carries a `Changelog:` trailer.
- **`shellcheck -e SC1091,SC2015,SC2181`** clean on all seven changed shell files.
- **Suites, cold, `env -u CLAUDE_CODE_SESSION_ID -u RUN_ID`:** `lean-evidence-selftest.sh`,
  `lean-gate-selftest.sh`, `check-lean-chain-selftest.sh` all green locally. CI: ubuntu
  `lint-and-selftests` pass, `selftests (macos, bash 3.2)` pass, `mutation-sweep-pr` pass with
  43 verdicts actually computed (not a zero-verdict rc=0) and no baseline-absent survivor.
- **Live-path plumbing.** `GH_REPO` is exported at both step envs in `.github/workflows/ci.yml`
  and in the consumer template, and both grant `issues: read`, so the payload's own fetch resolves
  rather than silently landing on the `unreadable` decline. Confirmed empirically: this PR's arm
  reported state `none`, not `unreadable` — the fetch succeeded and found an unstamped trail.
- **Reader/writer author filters.** `lean-evidence.sh` reads the stamp under `LEAN_MARKER_AUTHOR`
  while `check-lean-chain.sh` filters its claim arm under `LEAN_COMMENT_AUTHOR`. Neither is set in
  either workflow, so both degrade identically to "any Bot"; and a divergence would only ever arm
  the arm more, never less. Not a finding.
- **The non-circularity argument holds.** The stamp rides the one artifact every github producer
  generation writes. The two rejected carriers are rejected on evidence, not preference: the PR
  marker *is* the artifact the bound arm demands, so its absence is indistinguishable from a
  producer that cannot write it; and the verdict record would let the reviewed party soften a
  build-side arm.
- **Degrade direction.** Every new path degrades toward declining — unknown vocabulary token is an
  environment error at both writer and reader, everything else is `inert`. Nothing new can turn an
  honest run red.
