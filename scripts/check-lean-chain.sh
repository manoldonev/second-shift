#!/usr/bin/env bash
# check-lean-chain.sh — merge-boundary evidence gate for /dev-pipeline:run-lean PRs.
#
# A SIBLING of check-pipeline-chain.sh, deliberately not a mode of it (D-45): the two gates
# check different evidence sets. They no longer cover disjoint branch NAMESPACES — both lanes
# cut `<tracker.branchPrefix><key>` branches (#413) — so what keeps them disjoint is that both
# ask the same classifier which lane a PR belongs to.
#
# WHY THIS EXISTS. run-lean spends as few tokens as possible IN the run, which means almost
# every in-run record is written by the agent being checked. That is fine — as long as the
# binding evidence contract lives somewhere the agent cannot reach. This is that somewhere:
# a model-free check at the merge boundary, costing zero run tokens (D-47). It fails an
# applicable PR unless all of this evidence exists:
#   1. a committed lean spec carrying >= 1 numbered AC-n (the definition of done),
#   2. a committed verdict record reading `verdict=approve` (so a hand-typed local progress
#      line cannot reach a merge — only a committed, diffable artifact can),
#   3. a bot-authored `lean-claimed` comment on the linked issue, windowed at PR-open,
#   4. AUTHORSHIP (P10): the verdict record's run identity is NOT the build run's, and the
#      record names its own review session. The build run's identity AT THIS BOUNDARY is the
#      one carried in that bot claim comment — the only build-side record CI can see, because
#      the progress file is gitignored and never reaches a checkout. A verdict carrying the
#      same id means the session that wrote the code also wrote its own review, which is the
#      structural bias the separation exists to remove. A missing reconciliation key is
#      refused for the same reason a missing verdict is: nothing is checkable, and an
#      uncheckable claim must not read as a satisfied one.
#   5. FRESHNESS: the verdict covers the head being merged. The record is a static file, so
#      "an approve record exists" and "this code was approved" are different claims — a
#      review session commits its record and the branch then moves on, which is the ordinary
#      shape of the needs-work loop. Nothing but the record itself may have changed between
#      the commit carrying it and the PR head. TWO ARMS: the INFERRED one derives its anchor
#      from git (which commit carries the file — the record's prose cannot argue with that), and
#      the DECLARED one reads what the reviewer wrote. Inference binds the record to where it
#      was COMMITTED; the declaration binds it to what was REVIEWED. They come apart whenever
#      code lands between the review and the record's commit — the reviewer then commits an
#      honest record on top of a head it never read, and inference alone calls that fresh.
#
#      The declaration is keyed on `reviewed_patch_id`: the patch identity of the branch's own
#      diff against its base, excluding the record. WHAT IT COVERS — any commit landing after
#      the review, and any conflict resolution that altered a line during a rebase, both of
#      which move the id. WHAT IT DOES NOT — a rebase that replays the branch unchanged (the id
#      is invariant, and that is the point: SHA keying refused it, and in this fresh checkout
#      the pre-rebase object does not exist at all, so the refusal was unavoidable rather than
#      merely wrong), and a base change that reds the suite with no textual conflict. That last
#      one is CI's job: the reviewed content did not move, so the verdict stands, and the merged
#      result failing is a different claim. Conflating the two is what made SHA keying
#      over-strict. Records predating the key still gate on the `reviewed_head` SHA path.
#
#      PRECEDENCE (#403): when `reviewed_patch_id` is present the declared arm SUBSUMES the
#      inferred one — the inferred arm is not evaluated at all, rather than ANDed with it. A
#      merge from the configured base (GitHub's "Update branch" button) lands commits strictly
#      after the record's commit without touching the branch's own diff, which the inferred
#      arm's two-dot `git diff` cannot tell apart from a genuine change: every base-side file
#      registers as "changed after the verdict". The declared arm is immune to this (its anchor
#      is the branch's diff against the current base, not a commit range), so once it exists for
#      a record it is the sole freshness truth. Only records predating the key still run the
#      inferred arm.
#   6. THE INHERITANCE CHAIN (#375): if the verdict record declares `inherited_patch_id` — the
#      reviewed patch of the round whose coverage it inherits, so a fix round reads the delta
#      instead of the whole diff again — every LINK in that chain resolves to an earlier record
#      committed on this branch. What this boundary guarantees is then not "one review read this
#      tree" but "a CHAIN of independent reviews covered it", and an unverified link credits a
#      round with a tree it never read: a strictly weaker boundary, arrived at silently. Matched
#      by CONTENT (each declared identity against an earlier record's `reviewed_patch_id`),
#      never by commit SHA — a SHA link dies on a rebase, and this fresh checkout is exactly
#      where that is unrecoverable. Absence is the ordinary case: a round-1 record inherits
#      nothing, and neither does any record written before the key existed.
#   7. RATIFICATION (P9): if the run wrote an intent-gap record — a decision implementation
#      surfaced that the receipt did not cover — that record reads `ratified: yes` and cites
#      the operator comment that ratified it. Absence of a record is the ordinary case and is
#      printed, not silently skipped.
#   8. DESIGN EVIDENCE (#394): if the committed spec ARMS the design render lane — a `## Design`
#      section declaring at least one `RS-n` render state, with no explicit disarm — then a
#      render receipt is committed beside it, the verdict scores `fidelity: pass`, and the
#      receipt's `rendered_from` is the head's own render patch identity. Arming is derived from
#      the SPEC and never from config: `design.provider` lives in a gitignored file that no CI
#      checkout can see, so a config-keyed boundary check would be unarmed on every consumer.
#
#      SCOPED HONESTLY. This holds for the armed path only. A spec that never carries a
#      `## Design` section is indistinguishable here from honest unarmed work — the residual
#      defense is review-lean's blocker on an unjustified disarm in a provider repo, which is a
#      judgment this model-free gate cannot make.
#
# HONEST ALTITUDE: like its sibling, this is tamper-EVIDENCE, not proof. The agent writes
# artifacts 1 and 2. Forging one is easy; forging all three consistently, across a committed
# diff and a bot-authenticated tracker comment, is what this makes detectable. Harness
# attestation is lean-reconcile.sh's job (and #292's later).
#
# THREE OUTPUT CLASSES (#443). Reciting every arm on a passing run teaches nothing and buries the
# lines that matter; reciting none makes a gate that checked nothing indistinguishable from one
# that checked everything. So the recital splits three ways:
#   (a) SATISFIED, including VACUOUSLY satisfied — no output at all, on either stream, whether the
#       run ends green or red. The freshness precedence-skip and the no-inherited-coverage line
#       live here: the contract WAS verified, just by the other branch, and which branch verified
#       it is a source-reading question. Silence is unconditional and streamed, never buffered
#       until the verdict is known; a failing run's refusal already names the arm it came from.
#   (b) COULD NOT EVALUATE — exactly one line, on the green path. Mandatory rather than permitted:
#       an arm that quietly declines to run is the vacuous pass this gate refuses everywhere else.
#       Shape pinned below, identically to lean-evidence.sh's, because the successors to #443 emit
#       into this class and must not each invent one.
#   FAILURE output is unchanged — as loud and as specific as it ever was.
# There is deliberately NO verbose flag. An opt-in that restores the recital restores the problem,
# one CI job at a time, and a flag nobody sets is a code path nobody reads.
#
# NON-VACUOUS BY CONSTRUCTION. Applicability is the committed lean spec in the PR's own diff,
# keyed to the PR's own issue — and nothing else (#413). There is no branch-shaped arm: both
# lanes cut `<tracker.branchPrefix><key>` branches, so a namespace test would classify every
# staged PR as lean. Keying the artifact to the PR's issue is what stops the arm over-reaching
# in the other direction: a staged PR that merely edits some older ticket's lean spec resolves
# its own key, finds no spec for it, and stays with the pipeline gate. Selftest-fixture paths
# are excluded from the scan because fixtures are lean-shaped on purpose.
#
# The rule and its mirror image live in ONE place, plugins/dev-pipeline/skills/run-lean/
# lean-evidence.sh, which this gate and check-pipeline-chain.sh both delegate to. "No PR is
# applicable to both gates" therefore holds by construction rather than by two implementations
# agreeing about a namespace.
#
# CONSUMER PORTABILITY, and the delegation that follows from it (#359). This FILE stays
# second-shift-only: it reconciles against tracker COMMENTS, which a read-only tracker
# (`tracker.writes: false`) posts none of. But most of the evidence above needs no tracker at
# all, and that half now lives in plugin payload — `lean-evidence.sh`, beside lean-gate.sh —
# which a consumer's CI fetches at its pinned marketplace ref. This gate CALLS that file rather
# than holding a second copy of those arms:
#
#   delegated:  classification (applicability + issue key), evidence 2 (the verdict record),
#               evidence 4's PR-marker half, evidence 7 (ratification), and evidence 5's
#               DECLARED patch-id arm.
#   kept here:  evidence 1 (the spec), evidence 3 (the bot claim on the ISSUE), evidence 4's
#               claim-identity half, evidence 5's INFERRED and `reviewed_head` arms — legacy
#               paths for records predating the patch-id key — and evidence 6 and 8, which OR-1
#               parks outside the consumer core.
#
# THE IDENTITY ARMS ARE BOTH RUN, and that is deliberate rather than transitional. The payload
# reads the build identity from a bot marker on the PR, because that is the one write surface
# every adapter has; this gate additionally compares it against the bot claim on the ISSUE,
# which only a writing tracker has. Two independent sources for one fact make this boundary
# strictly stronger than the consumer core — an asymmetry to disclose, not to level down.
#
# Inputs (ALL via the environment — never spliced into a `run:` line; a PR body is
# attacker-controllable, and ci.yml documents this convention):
#   PIPELINE_BRANCH_PREFIX  required  e.g. "claude/second-shift-" — the ONE work-branch
#                                     namespace, and the anchor the delegated key derivation
#                                     strips. LEAN_BRANCH_PREFIX is retired (#413).
#   PR_HEAD_REF             required  the PR's head branch name
#   PR_BODY                 required-ish  the PR body (empty is legal; it just fails to resolve)
#   PR_CREATED_AT           required  ISO-8601; the PR-open observation point
#   PR_HEAD_SHA             required  the PR head commit the freshness check measures against.
#                                     NOT `HEAD`: on a pull_request event actions/checkout
#                                     resolves refs/pull/N/merge, so HEAD is merge(base, head)
#                                     and every base-side commit since the branch point would
#                                     read as "changed after the verdict".
#   PR_BASE_REF             required for the live diff, and for evidence 5's patch-id arm  the
#                                     PR's base branch. This is the base the patch identity is
#                                     measured from, and it is deliberately NOT reconciled
#                                     against the runtime config's baseBranch — CI cannot see
#                                     that file. The two agree whenever the PR targets the
#                                     configured base, which is the lane's contract; a PR
#                                     retargeted elsewhere reds here, which is fail-closed.
#   GH_REPO                 required for the live path  "<owner>/<repo>"
#   GH_TOKEN                required for the live path
#   LEAN_COMMENT_AUTHOR     optional  exact bot login; absent degrades to "any Bot author"
#
# Seams (zero-network selftest, the check-pipeline-chain.sh precedent):
#   ${GH:-gh}                  the CLI used for the comment fetch
#   --comments-file <path>     read the ISSUE comment trail from a JSON fixture
#   --diff-files-file <path>   read the PR's changed-file list from a newline-delimited fixture
#   LEAN_PR_COMMENTS_FILE      read the PR marker trail from a JSON fixture. An ENV seam, alone
#                              among the three, because it is not this script's input: it is
#                              forwarded verbatim to the delegated payload, and every real input
#                              this gate takes already arrives by environment.
#   LEAN_EVIDENCE               path to lean-evidence.sh, when it is not at the committed
#                              location below (a vendored fork, or a selftest driving a copy)
#
# Exit 0 = pass or not-applicable; 1 = evidence violation; 2 = usage/environment error.
set -uo pipefail

GH_CLI="${GH:-gh}"
COMMENTS_FILE=""
DIFF_FILES_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --comments-file)   COMMENTS_FILE="${2:-}"; shift 2 ;;
    --diff-files-file) DIFF_FILES_FILE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '2,173p' "$0"; exit 0 ;;
    *) echo "[lean-chain] unknown argument: $1" >&2; exit 2 ;;
  esac
done

fail()    { echo "[lean-chain] ✗ $1" >&2; exit 1; }
envfail() { echo "[lean-chain] $1" >&2; exit 2; }

# LOCKSTEP-BEGIN lean-output-dispositions
LEAN_OUTPUT_DISPOSITIONS='not-applicable reduced-strength postdated inert'
# LOCKSTEP-END lean-output-dispositions

# The class-(b) emitter, and the ONLY way this file writes on a green path. Shape:
#
#   [lean-chain]   · <arm>: <disposition> — <reason>
#
# STDOUT, one line, disposition drawn from the closed set above. `postdated` and `inert` have no
# call site here yet; they are the successors' and are declared now so the vocabulary is fixed
# rather than grown a word at a time by whoever emits next.
#
# An unknown disposition is an ENVIRONMENT error, not a printed line: a gate whose vocabulary can
# be widened at a call site has no closed vocabulary, and the reader that classifies these lines
# would silently start seeing a token it has no rule for.
inapplicable() { # inapplicable <arm> <disposition> <reason>
  case " $LEAN_OUTPUT_DISPOSITIONS " in
    *" $2 "*) : ;;
    *) envfail "internal: '$2' is not a class-(b) disposition (arm '$1'). The vocabulary is closed: $LEAN_OUTPUT_DISPOSITIONS." ;;
  esac
  echo "[lean-chain]   · $1: $2 — $3"
}

# The claim comment's stage token, plus the producer capability contract it also carries (#445).
# THIS FILE READS ONLY THE TAG — its claim arm below counts bot-authored claim comments, and a
# one-sided rename would empty that set and red every honest lean PR. The stamp key and the
# capability vocabulary are in the same block because they are one contract written by one
# producer (lean-gate.sh, the canonical side); the arm bound to a capability lives in the
# delegated payload, lean-evidence.sh. lean-reconcile.sh keeps an unbound copy of the tag: it is
# an operator-run reconciler rather than a merge-boundary gate.
# LOCKSTEP-BEGIN lean-producer-capabilities
LEAN_CLAIM_MARKER_TAG='lean-claimed'
# shellcheck disable=SC2034  # each reader binds a SUBSET of these; the block is one contract.
LEAN_CAPABILITY_KEY='capabilities'
# shellcheck disable=SC2034  # ditto — unused here is the point, not an oversight.
LEAN_CAPABILITIES='pr-marker'
# LOCKSTEP-END lean-producer-capabilities

# LOCKSTEP-BEGIN lean-chain-artifact-patterns
# The lean-marked name shapes, suffix-anchored. `*-lean.md` must never match the verdict
# record (`*-lean-verdict.md`) — that is why both are anchored at the END of the filename
# rather than matched as substrings. lean-gate.sh derives the same two names from config;
# here they are patterns, because CI has no access to the gitignored runtime config.
#
# `-lean-renders.md` (#394) is anchored for the same reason and with the same care: it must not
# end in `-lean.md`, or the artifact arm's FIRST-match spec scan would pick a render receipt and
# call it the spec.
#
# `-lean-intent-gap.md` is NOT here any more (#359): the ratification arm moved to
# lean-evidence.sh, which pins that suffix itself. Only the names this file still reads live
# here — an unread constant is a claim about coverage the code does not make.
LEAN_SPEC_SUFFIX='-lean.md'
LEAN_VERDICT_SUFFIX='-lean-verdict.md'
LEAN_RENDER_SUFFIX='-lean-renders.md'
# LOCKSTEP-END lean-chain-artifact-patterns

# Fixture paths are lean-shaped ON PURPOSE (the selftests below need lean-looking files), so
# they must never make a PR applicable. Anything under a fixtures dir is out of the scan.
is_fixture_path() {
  case "$1" in
    */fixtures/*|*-fixtures/*|fixtures/*) return 0 ;;
    *) return 1 ;;
  esac
}

# First `<key>: <token>` in a COMMITTED version of a file — the same first-match shape every
# other read of these records uses, against a blob instead of a working-tree path. It is the
# only way to reach a PRIOR round: the record path holds one round at a time, so every round
# but the newest exists solely in that path's git history.
record_key_at() { # record_key_at <key> <commit> <path>
  git -C "$REPO_ROOT" show "$2:$3" 2>/dev/null \
    | grep -oE "$1:[[:space:]]*[A-Za-z0-9._-]+" 2>/dev/null | head -n1 | sed -E "s/^$1:[[:space:]]*//"
}

# LOCKSTEP-BEGIN lean-inherited-key
# Any key of the verdict record, read from its HEADER BLOCK only. Record on stdin; prints
# nothing when the key is absent from that block.
#
# HEADER-ANCHORED, unlike the first-match reads elsewhere in this schema, and the asymmetry is
# the whole point. First-match-anywhere is safe for a key the writer ALWAYS emits with a
# meaningful value, because the authentic value wins the race against any prose below it. It is
# NOT safe for a key that can be ABSENT — a chain root wrote no inheritance, records predating a
# key carry none — because a race has no winner when one side never entered it: the first match
# in the file is then whatever the reviewer's own findings contain. Review prose about these
# features quotes these keys, so the triggering round is every review of a PR that touches them,
# not a crafted one. The value lands where a CLAIM OF COVERAGE (or of design fidelity) is read,
# which is the inverse of the property those keys exist to prove.
#
# The writer's half of the same fix emits both optional keys unconditionally and makes absence a
# written fact; this half covers the records that writer did not produce — a pre-#375 root
# record still sitting on an in-flight branch, which every chain walk on that branch reads
# through, and every record written before `fidelity:` existed.
#
# PARAMETERIZED rather than duplicated (#394). `fidelity:` needs exactly this anchoring for
# exactly this reason, and a second awk program spelled the same way would be a second thing to
# keep in lockstep across all three readers — the drift these markers exist to prevent, forked
# in the act of preventing it.
#
# The header block is the first run of `key: value` / `verdict=` lines, ending at the blank line
# the writer emits before the body. A record whose keys are NOT in that shape (the earliest
# records wrote `verdict=` as a bullet or a table cell) never opens the block, so nothing is
# extracted and the round reads as a root — fail-closed, and correct: those records predate
# inheritance entirely.
header_key() { # header_key <key>   (record on stdin)
  awk -v k="$1" '
    /^[A-Za-z_][A-Za-z0-9_]*[:=]/ { hdr = 1 }
    hdr && /^[[:space:]]*$/ { exit }
    hdr && $0 ~ "^" k ":[[:space:]]*[A-Za-z0-9._-]+" {
      sub("^" k ":[[:space:]]*", "")
      sub(/[^A-Za-z0-9._-].*$/, "")
      printf "%s", $0
      exit
    }
  '
}

# `inherited_patch_id` with the `none` sentinel normalized to empty — the shape every chain
# reader wants. The sentinel lives HERE and not in header_key because it is inheritance's, not
# the schema's: `fidelity: none` is not a value, so a generic reader that swallowed `none` would
# be silently lenient about a key whose enum never contains it.
inherited_key() { # inherited_key   (record on stdin)
  local v
  v="$(header_key inherited_patch_id)"
  [ "$v" = "none" ] || printf '%s' "$v"
}
# LOCKSTEP-END lean-inherited-key

# The header-anchored read against a COMMITTED version of the record — what a chain walk needs,
# since every round but the newest exists solely in that path's git history.
inherited_key_at() { # inherited_key_at <commit> <path>
  git -C "$REPO_ROOT" show "$1:$2" 2>/dev/null | inherited_key
}

# LOCKSTEP-BEGIN lean-design-armed
# Armed-ness exactly as the COMMITTED SPEC declares it. Spec on stdin; prints `armed`, or
# nothing at all.
#
# TWO READERS, which is why this is a marker block and not a private helper: check-lean-chain.sh
# must reach the same answer from a CI checkout that cannot see the runtime config at all (it is
# gitignored on every consumer, this repo included). A boundary that decided armed-ness
# differently from the gate would either wave an armed PR through with no evidence or red an
# honest unarmed one, and neither divergence is visible from either side alone.
#
# The shared predicate is deliberately the NARROW one — at least one `| RS-n |` render-state row
# and no explicit `Design: none` disarm. Everything else the gate checks about the section (a
# provider handoff link, the neither-form refusal, the reason on a disarm) is an AUTHORING error
# it refuses at milestone 1, so a spec that fails those never reaches a merge and the boundary
# never needs an opinion about it. Keeping the shared decision to what both sides can compute
# identically is what stops the two from drifting.
#
# The heading matches at any depth and case-folded (`## Design`, `### DESIGN`), and ANY heading
# closes the section — the flat rule a reader can predict, the same one jira_items_section uses.
# `#+[[:space:]]`, never `#{1,6}`: interval expressions are not portable across the awks this
# ships on, and the space is required because `##Design` is literal text to CommonMark.
design_armed() { # design_armed   (spec on stdin)
  awk '
    tolower($0) ~ /^#+[[:space:]]+design[[:space:]]*$/ { insec = 1; next }
    insec && /^#+[[:space:]]/ { insec = 0 }
    insec && tolower($0) ~ /^[[:space:]]*design:[[:space:]]*none([[:space:]]|$)/ { disarmed = 1; exit }
    insec && /^[[:space:]]*\|[[:space:]]*RS-[0-9]+[[:space:]]*\|/ { rows = 1 }
    END { if (rows && !disarmed) print "armed" }
  '
}
# LOCKSTEP-END lean-design-armed

# ---- (1) env constants: fail closed, never "exempt" -------------------------------------
# An unresolvable prefix must never degrade into "not applicable". Same posture as the
# sibling gate, for the same reason: a vacuous green is the worst outcome available here.
# There is exactly ONE prefix now (#413), and the pair that had to be held mutually
# non-prefix-matching is gone with the namespace that created it.
[[ -n "${PIPELINE_BRANCH_PREFIX:-}" ]] \
  || envfail "PIPELINE_BRANCH_PREFIX is unset or empty — refusing to run (the delegated key derivation strips it off the head ref). It is set at job level on pr-gates."
[[ -n "${PR_HEAD_REF:-}" ]] \
  || envfail "PR_HEAD_REF is unset or empty — nothing to classify."
[[ -n "${PR_CREATED_AT:-}" ]] \
  || envfail "PR_CREATED_AT is unset or empty — the PR-open observation point is unresolvable."
[[ -n "${PR_HEAD_SHA:-}" ]] \
  || envfail "PR_HEAD_SHA is unset or empty — the freshness check has nothing to measure the verdict against, and 'a verdict exists' is not 'this head was approved'. Set it on the pr-gates job."

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || envfail "not in a git repo — cannot resolve the committed artifacts."

# The delegated payload. Resolved from the REPO ROOT and not from this script's own directory:
# in CI the checkout IS the marketplace repo, so the committed path is the authority, and a
# `$HERE/..`-relative walk would silently resolve to a different tree in a worktree layout.
# Missing is fatal — a boundary that cannot reach half its evidence must not report a pass.
PAYLOAD="${LEAN_EVIDENCE:-$REPO_ROOT/plugins/dev-pipeline/skills/run-lean/lean-evidence.sh}"
[[ -f "$PAYLOAD" ]] \
  || envfail "the portable evidence payload is missing at '$PAYLOAD' — this gate delegates its verdict, identity, ratification and patch-id arms to it and cannot evaluate them alone. Set LEAN_EVIDENCE if it lives elsewhere."

# One invocation shape for every delegated call. The payload's own violation COUNT is read back
# through --violations-file and folded into this gate's total: collapsing "2 artifacts missing"
# into "1 delegated call failed" would drop the only quantity an operator triages by, and the
# combined line is the one a reader of the job log sees.
PAYLOAD_ARGS=()
[[ -n "${LEAN_PR_COMMENTS_FILE:-}" ]] && PAYLOAD_ARGS+=(--pr-comments-file "$LEAN_PR_COMMENTS_FILE")
# The ISSUE trail this gate already holds is the capability stamp's carrier (#445), so the payload
# is handed the same fixture rather than left to fetch a second copy. In the LIVE path there is no
# fixture and the payload fetches for itself — which is also the only path a consumer running the
# payload directly ever takes.
[[ -n "$COMMENTS_FILE" ]] && PAYLOAD_ARGS+=(--issue-comments-file "$COMMENTS_FILE")
[[ -n "$DIFF_FILES_FILE" ]] && PAYLOAD_ARGS+=(--diff-files-file "$DIFF_FILES_FILE")

delegate() { # delegate <arms...>   — runs the payload's `check` for the named arm set
  local countfile rc n
  countfile="$(mktemp -t leanev.XXXXXX)" || envfail "mktemp failed."
  bash "$PAYLOAD" check --key "$KEY" --arms "$1" --violations-file "$countfile" \
    "${PAYLOAD_ARGS[@]+"${PAYLOAD_ARGS[@]}"}"
  rc=$?
  n="$(cat "$countfile" 2>/dev/null)"
  rm -f "$countfile"
  # rc=2 is the payload's ENVIRONMENT error and propagates as this gate's: a check that could
  # not run must not be scored as either passing or violating.
  [[ "$rc" -eq 2 ]] && exit 2
  [[ -n "$n" ]] || n=0
  violations=$((violations + n))
  return 0
}

# ---- (2/3/4) classification, delegated ---------------------------------------------------
# Applicability, the artifact scan and the issue-key resolution all move to the payload (#359).
# NOT because they are cheap to move, but because a consumer's CI must reach the SAME answer
# from a committed config while this gate reaches it from job-level constants — and a boundary
# that classified differently from the one a consumer runs would make every cross-repo bug
# report unreproducible. The rules themselves (key from the branch suffix, else the body with
# `Closes` beating `Part of`; then a key-matched non-fixture lean spec in the diff) are
# documented at the payload.
CLASSIFY="$(bash "$PAYLOAD" classify "${PAYLOAD_ARGS[@]+"${PAYLOAD_ARGS[@]}"}")" || exit $?
APPLICABLE="$(printf '%s\n' "$CLASSIFY" | sed -n 's/^applicable=//p' | head -n1)"
# `trigger=` is deliberately NOT read back. It named the arm that classified the PR, and its only
# consumer was the `applicable via …` recital #443 silenced — a satisfied classification is class
# (a). The payload still emits it; the DECLINE path below is where an operator needs the detail,
# and that path builds its own reason from `key=` and `spec_in_diff=`.
KEY="$(printf '%s\n' "$CLASSIFY" | sed -n 's/^key=//p' | head -n1)"
LEAN_SPEC_IN_DIFF="$(printf '%s\n' "$CLASSIFY" | sed -n 's/^spec_in_diff=//p' | head -n1)"
[[ -n "$APPLICABLE" ]] \
  || envfail "the evidence payload returned no applicability verdict — refusing to guess. Output was: $CLASSIFY"

if [[ "$APPLICABLE" -eq 0 ]]; then
  # CLASS (b): the whole gate could not evaluate. ONE line, carrying what the payload resolved
  # inside its reason — a decline is otherwise indistinguishable from "never ran", and the
  # "a lean spec IS present and it is not yours" case is the one decline an operator argues with.
  DECLINE_NOTE=""
  [[ -n "$LEAN_SPEC_IN_DIFF" ]] \
    && DECLINE_NOTE=" A lean-marked spec IS present ($LEAN_SPEC_IN_DIFF) but it is not this PR's key — classified to the pipeline chain gate, not this one."
  inapplicable lean-chain not-applicable "non-lean change on head branch '$PR_HEAD_REF' — resolved key: ${KEY:-<none>} (branch namespace: $PIPELINE_BRANCH_PREFIX).$DECLINE_NOTE"
  exit 0
fi

# A lean PR on a branch outside the namespace, naming no issue. The payload classifies it
# applicable on purpose rather than declining — a PR both gates decline is the hole this
# boundary exists to close — so the refusal lands here, and it is a VIOLATION (rc=1) with a
# remedy, not an environment error.
[[ -n "$KEY" ]] \
  || fail "PR body carries no resolvable issue reference ('Closes #N' or 'Part of #N') and the head branch is outside '$PIPELINE_BRANCH_PREFIX', but this PR commits a lean spec. Add the reference."

violations=0
note_violation() { echo "[lean-chain]   ✗ $1" >&2; violations=$((violations + 1)); }

# ---- (5) evidence 1: a committed lean spec carrying >= 1 AC-n ----------------------------
SPEC=""
if [[ -n "$LEAN_SPEC_IN_DIFF" && -f "$REPO_ROOT/$LEAN_SPEC_IN_DIFF" ]]; then
  SPEC="$LEAN_SPEC_IN_DIFF"
else
  # Prefix-arm PRs need not have the spec in THIS diff (a resumed run may have committed it
  # earlier), so fall back to locating it in the tree by the pinned suffix + issue key.
  while IFS= read -r f; do
    is_fixture_path "$f" && continue
    case "$f" in *"$LEAN_VERDICT_SUFFIX") continue ;; esac
    case "$(basename "$f")" in *"-$KEY$LEAN_SPEC_SUFFIX") SPEC="${f#"$REPO_ROOT/"}"; break ;; esac
  done < <(find "$REPO_ROOT" -name "*$LEAN_SPEC_SUFFIX" -type f 2>/dev/null)
fi

if [[ -z "$SPEC" ]]; then
  note_violation "no committed lean spec (a file named *$LEAN_SPEC_SUFFIX for #$KEY). The spec IS the definition of done; without it nothing constrains the change."
else
  ac_count="$(grep -cE '(^|[^A-Za-z])AC-[0-9]+' "$REPO_ROOT/$SPEC" 2>/dev/null)" || ac_count=0
  if [[ "${ac_count:-0}" -lt 1 ]]; then
    note_violation "committed spec '$SPEC' carries no numbered AC-n criterion."
  fi
fi

# ---- (6) evidence 2: a committed verdict record reading verdict=approve ------------------
VERDICT=""
while IFS= read -r f; do
  is_fixture_path "${f#"$REPO_ROOT/"}" && continue
  case "$(basename "$f")" in *"-$KEY$LEAN_VERDICT_SUFFIX") VERDICT="${f#"$REPO_ROOT/"}"; break ;; esac
done < <(find "$REPO_ROOT" -name "*$LEAN_VERDICT_SUFFIX" -type f 2>/dev/null)

VERDICT_RUN_ID=""
VERDICT_SESSION_ID=""
VERDICT_REVIEWED_HEAD=""
VERDICT_REVIEWED_PATCH_ID=""
VERDICT_INHERITED_PATCH_ID=""
VERDICT_ROUNDS=""
verdict_value=""

# DELEGATED. The record's existence, its `verdict=approve` value, and the presence of both
# reconciliation keys are the payload's arm — a consumer gets exactly these refusals, in these
# words, from the same bytes.
delegate verdict

if [[ -n "$VERDICT" ]]; then
  # The same keys are ALSO read here, and that is not a duplicated ARM: evidence 4, 6 and 8
  # below need their VALUES, and those three arms stay on this side of the split (OR-1, and
  # the claim-identity half). Reading a value is not asserting one — every refusal about these
  # keys is emitted above.
  #
  # FIRST-MATCH, never a count over the whole file. `lean-gate.sh verdict --summary-file`
  # appends the reviewer's own prose below these keys, and review prose discusses verdicts:
  # the committed record for #237 carries `verdict=approve` on line 3 and again on line 9
  # inside a sentence about the previous round. A count-anywhere reader passes a record whose
  # authoritative first line says `needs-work`. Line-anchoring was rejected instead of this
  # because the earliest records write the key as a bullet or table cell, and an anchor would
  # reclassify already-merged evidence as unreadable. lean-gate.sh's record_verdict() is the
  # same read on the same file.
  verdict_value="$(grep -oE 'verdict=[A-Za-z-]+' "$REPO_ROOT/$VERDICT" 2>/dev/null | head -n1 | sed -E 's/^verdict=//')"
  # `session_id:` does not contain the substring `run_id:`, so the two extractions cannot
  # capture each other; head -n1 keeps the first occurrence of each, matching the shape
  # lean-gate.sh and lean-reconcile.sh read the same record with.
  VERDICT_RUN_ID="$(grep -oE 'run_id:[[:space:]]*[A-Za-z0-9._-]+' "$REPO_ROOT/$VERDICT" 2>/dev/null | head -n1 | sed -E 's/run_id:[[:space:]]*//')"
  VERDICT_SESSION_ID="$(grep -oE 'session_id:[[:space:]]*[A-Za-z0-9._-]+' "$REPO_ROOT/$VERDICT" 2>/dev/null | head -n1 | sed -E 's/session_id:[[:space:]]*//')"
  # Same first-match shape, same charset. No other key in the record contains the substring
  # `reviewed_head:`, so this extraction cannot capture one of theirs or be captured by it —
  # `reviewed_patch_id:` in particular is a different string, not an extension of this one.
  VERDICT_REVIEWED_HEAD="$(grep -oE 'reviewed_head:[[:space:]]*[A-Za-z0-9._-]+' "$REPO_ROOT/$VERDICT" 2>/dev/null | head -n1 | sed -E 's/reviewed_head:[[:space:]]*//')"
  VERDICT_REVIEWED_PATCH_ID="$(grep -oE 'reviewed_patch_id:[[:space:]]*[A-Za-z0-9._-]+' "$REPO_ROOT/$VERDICT" 2>/dev/null | head -n1 | sed -E 's/reviewed_patch_id:[[:space:]]*//')"
  # HEADER-ANCHORED, alone among the keys read here, because it is the only one the writer may
  # legitimately have nothing to say about. See `inherited_key` for why first-match cannot be
  # used on an optional key. (`inherited_patch_id:` and `reviewed_patch_id:` are also different
  # strings — neither contains the other — so the two extractions cannot capture each other's
  # value either way.)
  VERDICT_INHERITED_PATCH_ID="$(inherited_key < "$REPO_ROOT/$VERDICT")"
  VERDICT_ROUNDS="$(grep -oE 'rounds:[[:space:]]*[A-Za-z0-9._-]+' "$REPO_ROOT/$VERDICT" 2>/dev/null | head -n1 | sed -E 's/rounds:[[:space:]]*//')"
fi

# ---- (7) evidence 3: a bot-authored lean-claimed comment, windowed at PR-open ------------
if [[ -n "$COMMENTS_FILE" ]]; then
  [[ -f "$COMMENTS_FILE" ]] || envfail "--comments-file '$COMMENTS_FILE' does not exist."
  COMMENTS="$(cat "$COMMENTS_FILE")"
else
  [[ -n "${GH_REPO:-}" ]] || envfail "GH_REPO is unset — cannot fetch the comment trail."
  COMMENTS="$("$GH_CLI" api "repos/$GH_REPO/issues/$KEY/comments" --paginate 2>&1)" || {
    # A failed fetch is an ENVIRONMENT error, never a silent pass: fail-open here would waive
    # the whole gate on any rate limit or transient 5xx.
    echo "[lean-chain] comment fetch failed for issue #$KEY:" >&2
    printf '%s\n' "$COMMENTS" >&2
    exit 2
  }
fi
printf '%s' "$COMMENTS" | jq -e 'type == "array"' >/dev/null 2>&1 \
  || envfail "comment trail is not a JSON array — cannot reconcile."

# TRUST FILTER (load-bearing on a PUBLIC repo). Issue comments are writable by any account, so
# the raw trail is not the agent-written record this reasons about — an outsider could post a
# lean-claimed marker. `.user.type == "Bot"` is the filter, optionally narrowed by an exact
# login. Measured on the sibling gate: the pipeline bot posts with author_association
# CONTRIBUTOR, so an OWNER/MEMBER allowlist would filter out the bot itself.
#
# Windowing to PR-open makes the gate idempotent: pr-gates re-runs on every synchronize, and a
# LATER re-claim of the same issue must not retroactively red-line an already-green PR. A PR's
# created_at is immutable, so the window is stable across re-runs.
# shellcheck disable=SC2016  # $author/$at/$tag are jq variables, bound with --arg; shell must not expand them.
CLAIM_FILTER='
  [ .[]
    | select((.user.type // "") == "Bot")
    | select($author == "" or (.user.login // "") == $author)
    | select((.created_at // "") != "" and .created_at <= $at)
    | select((.body // "") | test("<!--[[:space:]]*stage:[[:space:]]*" + $tag + "[[:space:]]*-->"))
  ]'

CLAIMED="$(printf '%s' "$COMMENTS" | jq -r --arg author "${LEAN_COMMENT_AUTHOR:-}" --arg at "$PR_CREATED_AT" \
  --arg tag "$LEAN_CLAIM_MARKER_TAG" "$CLAIM_FILTER | length")"

# The build run's identity as CI can see it. Same filter as the count above — reading the id
# off a comment that did not pass the trust/window filter would let an outsider's marker (or a
# later re-claim) define what "the build run" means for this PR.
CLAIM_RUN_ID="$(printf '%s' "$COMMENTS" | jq -r --arg author "${LEAN_COMMENT_AUTHOR:-}" --arg at "$PR_CREATED_AT" \
  --arg tag "$LEAN_CLAIM_MARKER_TAG" \
  "$CLAIM_FILTER | map((.body // \"\") | capture(\"run_id:[[:space:]]*(?<r>[A-Za-z0-9._-]+)\").r? // \"\") | map(select(. != \"\")) | first // \"\"")"

# The build SESSION as CI can see it, when the claim carries one. `session_id:` does not
# contain the substring `run_id:`, so the capture above cannot have consumed it.
CLAIM_SESSION_ID="$(printf '%s' "$COMMENTS" | jq -r --arg author "${LEAN_COMMENT_AUTHOR:-}" --arg at "$PR_CREATED_AT" \
  --arg tag "$LEAN_CLAIM_MARKER_TAG" \
  "$CLAIM_FILTER | map((.body // \"\") | capture(\"session_id:[[:space:]]*(?<r>[A-Za-z0-9._-]+)\").r? // \"\") | map(select(. != \"\" and . != \"unset\")) | first // \"\"")"

if [[ "${CLAIMED:-0}" -lt 1 ]]; then
  # shellcheck disable=SC2016  # $tag is a jq variable, bound with --arg.
  any="$(printf '%s' "$COMMENTS" | jq -r --arg tag "$LEAN_CLAIM_MARKER_TAG" \
    '[ .[] | select((.body // "") | test("<!--[[:space:]]*stage:[[:space:]]*" + $tag + "[[:space:]]*-->")) ] | length')"
  if [[ "${any:-0}" -gt 0 ]]; then
    note_violation "found $any '$LEAN_CLAIM_MARKER_TAG' marker(s) on #$KEY, but none that are bot-authored AND at or before PR-open ($PR_CREATED_AT). An operator-posted claim is not evidence the harness ran."
  else
    note_violation "no bot-authored '$LEAN_CLAIM_MARKER_TAG' comment on #$KEY at or before PR-open ($PR_CREATED_AT). The run left no claim record."
  fi
fi

# ---- (8) evidence 4: the verdict was authored OUTSIDE the build session (P10) ------------
# TWO SOURCES, both run. The payload compares the verdict against the bot markers on the PR —
# the surface every adapter has — and is delegated first. This block then compares it against
# the bot claim on the ISSUE, which only a writing tracker has, so it cannot move to the
# payload and is what makes this boundary stronger than the consumer core rather than equal
# to it. Neither subsumes the other: a run could post a PR marker and no issue claim, or the
# reverse, and each source independently answers "whose session was this".
delegate identity

# Skipped when there is no verdict record at all — that is already a violation, and reporting
# "authorship unverifiable" on top of "no verdict" is noise. Skipped too when either key is
# absent: the payload already refused for exactly that, and restating it here would print one
# fact as two violations.
if [[ -n "$VERDICT" && -n "$VERDICT_RUN_ID" && -n "$VERDICT_SESSION_ID" ]]; then
  if [[ -z "$CLAIM_RUN_ID" ]]; then
    note_violation "the bot-authored lean-claimed comment on #$KEY carries no run_id, so the build run's identity is unknown and the verdict's independence is uncheckable."
  elif [[ "$VERDICT_RUN_ID" == "$CLAIM_RUN_ID" ]]; then
    note_violation "verdict record '$VERDICT' carries the BUILD run's identity ('$VERDICT_RUN_ID') — the session that wrote the code also wrote its own review verdict. The verdict must come from a separate review session carrying its own identity."
  elif [[ -n "$CLAIM_SESSION_ID" && "$VERDICT_SESSION_ID" == "$CLAIM_SESSION_ID" ]]; then
    # The STRONGER of the two comparisons, and the reason cmd_claim carries a session id at
    # all: run_id is agent-CHOSEN, so a build session determined to review itself need only
    # pick a second string, whereas the session id is harness-assigned.
    note_violation "verdict record '$VERDICT' names the BUILD session ('$VERDICT_SESSION_ID') as its author — a distinct run_id does not make it an independent review (P10)."
  else
    # TRANSITIONAL, and deliberately not a violation. Claim comments posted before the claim
    # writer carried a session id have none, and there is no remedy available: the comment
    # must fall inside the immutable PR-open window, so it cannot be re-posted for an open PR.
    # Refusing here would strand those PRs with no action that clears the gate. The run_id arm
    # above still applies to them, and lean-reconcile.sh makes the session comparison
    # out-of-band against the progress file, which is not window-bound.
    #
    # CLASS (b), not (a): only HALF the comparison ran, so the arm did not fully evaluate and
    # the boundary is weaker here than it reads. Exactly the disclosure `reduced-strength` names.
    [[ -n "$CLAIM_SESSION_ID" ]] \
      || inapplicable authorship reduced-strength "the claim comment on #$KEY carries no session_id (claimed before the writer emitted one, and the PR-open window makes it un-repostable), so only the run-id half of the authorship comparison was available."
  fi
fi

# ---- (9) evidence 5: the verdict covers the head being merged ----------------------------
# Skipped when there is no verdict record — already a violation, and "unverifiable freshness"
# on top of "no verdict" is noise. The tolerance is exactly one path, the record itself,
# because the review session commits nothing else (review-lean step 6).
#
# #374 AC-4/5/6: VACUITY. "Fresh" is a claim about an approve — a needs-work record is not
# stale or fresh, because there is nothing for either arm to be measured against: the record
# does not certify this code either way, regardless of what changed after it. Evaluating both
# arms anyway restates evidence 2's "not approve" finding twice more, in slightly different
# words, which is exactly the "one fact printed as three violations" defect this fix removes —
# observed live on a #372 round-2 build. So a non-approve value short-circuits here to ONE
# refusal naming it, before either arm's git/patch-id computation runs at all. An approve
# record is unaffected: both arms below evaluate exactly as they did before this change (AC-5).
if [[ -n "$VERDICT" && "$verdict_value" != "approve" ]]; then
  note_violation "verdict record '$VERDICT' reads 'verdict=${verdict_value:-<none>}', not 'verdict=approve' — freshness is undefined for a non-approve record, so the changed-files and patch-id/reviewed-head arms are not evaluated."
elif [[ -n "$VERDICT" ]]; then
  git -C "$REPO_ROOT" cat-file -e "$PR_HEAD_SHA^{commit}" 2>/dev/null \
    || envfail "PR_HEAD_SHA '$PR_HEAD_SHA' is not a commit in this checkout — the freshness check cannot run, and a check that cannot run must not report a pass."

  # PRECEDENCE (#403): a record declaring reviewed_patch_id defers to the DECLARED arm below,
  # exclusively — the inferred arm's two-dot diff (VERDICT_COMMIT..PR_HEAD_SHA) is not evaluated
  # at all. That diff counts every commit the base branch gained since the branch point as a
  # change to THIS branch: harmless on a rebase (the record stays the tip, so the diff is empty)
  # but a false positive on a merge from base — e.g. GitHub's "Update branch" button — which
  # lands commits strictly after the record's commit without touching the reviewed diff. The
  # declared arm already measures the right thing (this branch's own diff against its base,
  # excluding the record) and is unaffected by base-side commits, so running the inferred arm
  # too would either just restate the declared arm's verdict or, when a stale base-side file
  # slips past the exclusion, contradict it outright — the exact contradiction #403 was filed
  # over. Same one-way, never-AND-ed precedence as the reviewed_patch_id/reviewed_head choice
  # inside the declared arm itself. Records predating the key have no declared arm to defer to,
  # so the inferred arm stays their sole check.
  #
  # The skip is CLASS (a), not (b) (#443): freshness IS verified, by the declared arm, and which
  # of the two arms verified it is a source-reading question. It also fires on every record that
  # carries a reviewed_patch_id — that is to say on every ordinary green PR — so printing it was
  # the single largest source of the recital this silence removes.
  if [[ -z "$VERDICT_REVIEWED_PATCH_ID" ]]; then
    VERDICT_COMMIT="$(git -C "$REPO_ROOT" log -1 --format=%H -- "$VERDICT" 2>/dev/null)"
    if [[ -z "$VERDICT_COMMIT" ]]; then
      note_violation "verdict record '$VERDICT' is present in the tree but carries no commit — it was never committed to the branch, so nothing dates it against the code."
    else
      STALE="$(git -C "$REPO_ROOT" diff --name-only "$VERDICT_COMMIT" "$PR_HEAD_SHA" 2>/dev/null | grep -vxF "$VERDICT" || true)"
      if [[ -n "$STALE" ]]; then
        n_stale="$(printf '%s\n' "$STALE" | wc -l | tr -d ' ')"
        note_violation "verdict record '$VERDICT' approves $(git -C "$REPO_ROOT" rev-parse --short "$VERDICT_COMMIT"), but $n_stale file(s) changed between that commit and the PR head (e.g. $(printf '%s' "$STALE" | head -n1)). An approve for an earlier head is not an approve for this one — run another review round."
      fi
    fi
  fi

  # The DECLARED arm. Refused when absent for the same reason a missing verdict is: nothing is
  # checkable. Records written before this key existed are refused too — unlike the claim
  # comment's missing session_id above, a remedy IS available here (re-run the review round),
  # so a transitional pass would be a waiver rather than a kindness.
  #
  # `reviewed_patch_id` takes precedence over the `reviewed_head` SHA when present; the SHA path
  # below is what records predating that key gate on. The precedence is one-way and never
  # AND-ed: running both would re-impose the rebase refusal the patch-id exists to remove, since
  # this checkout holds no pre-rebase object to resolve the SHA against.
  if [[ -z "$VERDICT_REVIEWED_HEAD" ]]; then
    note_violation "verdict record '$VERDICT' carries no reviewed_head key, so nothing states which commit the review actually read. Re-run the review round on a dev-pipeline that writes it: '/dev-pipeline:review-lean <pr>'."
  elif [[ -n "$VERDICT_REVIEWED_PATCH_ID" ]]; then
    # DELEGATED. The patch-id computation — its base, its range and its exclusion of the record
    # — is the one part of freshness a consumer can run unchanged, and the one part that MUST
    # be byte-identical on both sides: two implementations that resolved the merge-base
    # differently would each call the other's honest record stale. The payload also owns the
    # empty-id guard, which is an ENVIRONMENT error there and propagates as one here.
    delegate freshness
  elif ! git -C "$REPO_ROOT" cat-file -e "$VERDICT_REVIEWED_HEAD^{commit}" 2>/dev/null; then
    note_violation "verdict record '$VERDICT' names reviewed_head $VERDICT_REVIEWED_HEAD, for which this checkout holds no commit — the branch was rebased or force-pushed after the review, so the reviewed code is not what is being merged. Re-run the review round."
  else
    DECLARED_STALE="$(git -C "$REPO_ROOT" diff --name-only "$VERDICT_REVIEWED_HEAD" "$PR_HEAD_SHA" 2>/dev/null | grep -vxF "$VERDICT" || true)"
    if [[ -n "$DECLARED_STALE" ]]; then
      n_declared="$(printf '%s\n' "$DECLARED_STALE" | wc -l | tr -d ' ')"
      note_violation "verdict record '$VERDICT' states it reviewed $(git -C "$REPO_ROOT" rev-parse --short "$VERDICT_REVIEWED_HEAD" 2>/dev/null), but $n_declared file(s) differ between that commit and the PR head (e.g. $(printf '%s' "$DECLARED_STALE" | head -n1)). The review read a different tree than the one being merged — run another review round."
    fi
  fi
fi

# ---- (10) evidence 6: every declared inheritance link resolves (#375) ---------------------
# Skipped when there is no verdict record — already a violation, and "unverifiable chain" on
# top of "no verdict" is noise. Absence of the key is the ordinary case and is CLASS (a) (#443):
# a round that inherits nothing covered the whole branch diff itself, which is a satisfied arm,
# not an unevaluated one.
if [[ -n "$VERDICT" ]]; then
  if [[ -n "$VERDICT_INHERITED_PATCH_ID" ]]; then
    # The record versions this branch committed, newest-first. Anchored at PR_HEAD_SHA for the
    # same reason evidence 5 is: on a pull_request event the checkout's HEAD is the MERGE ref,
    # so a bare `git log` would walk base-side history the PR never authored.
    CHAIN_VERSIONS="$(git -C "$REPO_ROOT" log --format=%H "$PR_HEAD_SHA" -- "$VERDICT" 2>/dev/null)"
    # The search starts strictly BELOW the commit carrying the record being read, and shrinks
    # past every hit, so the chain must run backwards through the record's history. Two things
    # ride on that: a branch reverted to a previously-reviewed tree carries an identity an
    # ancestor also carries, and an unbounded search would resolve that round to ITSELF; and
    # termination becomes structural, with no cycle counter to get wrong. A window that cannot
    # be anchored collapses to empty, which refuses — never to the full list, which would widen.
    CHAIN_HEAD_COMMIT="$(git -C "$REPO_ROOT" log -1 --format=%H "$PR_HEAD_SHA" -- "$VERDICT" 2>/dev/null)"
    CHAIN_REST=""
    CHAIN_PAST=0
    for c in $CHAIN_VERSIONS; do
      if [[ "$CHAIN_PAST" -eq 1 ]]; then CHAIN_REST="$CHAIN_REST $c"; continue; fi
      [[ "$c" == "$CHAIN_HEAD_COMMIT" ]] && CHAIN_PAST=1
    done
    CHAIN_VERSIONS="$CHAIN_REST"
    CHAIN_WANT="$VERDICT_INHERITED_PATCH_ID"
    CHAIN_ROUND="${VERDICT_ROUNDS:-?}"
    CHAIN_BROKEN=""
    while [[ -n "$CHAIN_WANT" ]]; do
      CHAIN_HIT=""
      CHAIN_REST=""
      for c in $CHAIN_VERSIONS; do
        if [[ -n "$CHAIN_HIT" ]]; then CHAIN_REST="$CHAIN_REST $c"; continue; fi
        if [[ "$(record_key_at reviewed_patch_id "$c" "$VERDICT")" == "$CHAIN_WANT" ]]; then CHAIN_HIT="$c"; fi
      done
      if [[ -z "$CHAIN_HIT" ]]; then
        CHAIN_BROKEN="round $CHAIN_ROUND declares inherited_patch_id ${CHAIN_WANT:0:12}, which matches no earlier verdict record committed on this branch — that round's inherited coverage is unverifiable, so nothing attests the part of the diff it did not read."
        break
      fi
      CHAIN_VERSIONS="$CHAIN_REST"
      CHAIN_ROUND="$(record_key_at rounds "$CHAIN_HIT" "$VERDICT")"; [[ -n "$CHAIN_ROUND" ]] || CHAIN_ROUND="?"
      CHAIN_WANT="$(inherited_key_at "$CHAIN_HIT" "$VERDICT")"
    done
    if [[ -n "$CHAIN_BROKEN" ]]; then
      note_violation "$CHAIN_BROKEN The remedy is a review round that reads the full diff."
    fi
  fi
fi

# ---- (11) evidence 7: no unratified intent-gap record (P9) -------------------------------
# A decision that surfaces during BUILD and is not in the receipt is not a failure — it is
# ordinary operation, and the intent-gap record is the channel it routes back through instead
# of becoming a silent choice. What must not happen is the merge landing while that decision
# is still the build run's own call. The record is a committed artifact for the same reason
# the verdict is: a local note nobody can diff is not evidence.
#
# The gate checks RATIFICATION and nothing else. It deliberately does not re-validate the
# record's disposition against the receipt's enum — that enum is single-sited in
# ledger-lint.sh, and a second copy here would be the duplicate machinery the lockstep
# manifest calls worse than none.
#
# ABSENCE IS LEGAL, and PRINTED. Most runs surface no gap, so "no record" is the common case
# rather than a missing artifact — but it is announced, so a reader of the log can tell
# "nothing surfaced" from "the arm never ran".
# DELEGATED in full: the record's location, its `ratified:` value and its `ratified_by:`
# citation are all committed-artifact reads with no tracker in them. P9's routing is identical
# for a consumer, so a second copy here would be the duplicate machinery the lockstep manifest
# calls worse than none.
delegate intent-gap

# ---- (12) evidence 8: armed design runs carry a fresh render receipt (#394) ---------------
# Skipped when there is no committed spec — already a violation, and "armed-ness unresolvable"
# on top of "no spec" is noise. Absence of arming is the ordinary case and is CLASS (a) (#443):
# a ticket that declares no design lane has nothing for this arm to check, and AC-4 requires that
# an ordinary unarmed PR produce no output at all.
if [[ -n "$SPEC" ]]; then
  if [[ "$(design_armed < "$REPO_ROOT/$SPEC")" == "armed" ]]; then
    RENDERS=""
    while IFS= read -r f; do
      is_fixture_path "${f#"$REPO_ROOT/"}" && continue
      case "$(basename "$f")" in *"-$KEY$LEAN_RENDER_SUFFIX") RENDERS="${f#"$REPO_ROOT/"}"; break ;; esac
    done < <(find "$REPO_ROOT" -name "*$LEAN_RENDER_SUFFIX" -type f 2>/dev/null)

    if [[ -z "$RENDERS" ]]; then
      note_violation "spec '$SPEC' arms the design render lane, but no render receipt (a file named *-$KEY$LEAN_RENDER_SUFFIX) is committed. The screenshots a fidelity verdict was scored against are not in this branch, so nothing here attests that any render happened."
    elif [[ -z "$VERDICT" ]]; then
      # CLASS (b): the arm is ARMED and applicable, but fidelity cannot be scored without a record
      # to read it from. The missing verdict is already a violation above; this line reports that
      # the design arm went unevaluated rather than passing, which is a different fact.
      inapplicable design-evidence not-applicable "the render receipt ($RENDERS) is committed, but there is no verdict record to score fidelity against — already reported above."
    else
      # HEADER-ANCHORED, like `inherited_patch_id` and for the same reason: `fidelity:` can be
      # absent (every record written before the key existed) and review prose discusses fidelity,
      # so a first-match-anywhere read would take its value from the reviewer's own findings.
      VERDICT_FIDELITY="$(header_key fidelity < "$REPO_ROOT/$VERDICT")"
      if [[ "$VERDICT_FIDELITY" != "pass" ]]; then
        note_violation "spec '$SPEC' arms the design render lane, but verdict record '$VERDICT' reads 'fidelity: ${VERDICT_FIDELITY:-<none>}', not 'fidelity: pass'. An armed ticket is approved only once a design-sighted review round scored its declared render states."
      else
        RENDERED_FROM="$(grep -oE 'rendered_from:[[:space:]]*[A-Za-z0-9._-]+' "$REPO_ROOT/$RENDERS" 2>/dev/null | head -n1 | sed -E 's/rendered_from:[[:space:]]*//')"
        if [[ -z "$RENDERED_FROM" ]]; then
          note_violation "render receipt '$RENDERS' carries no 'rendered_from:' key, so nothing states which tree it screenshotted — the receipt cannot be dated against the code being merged."
        else
          # The render binding: the branch's patch identity with BOTH self-referential artifacts
          # excluded — the verdict record (as evidence 5 excludes it) and the receipt itself,
          # which records this very value. lean-gate.sh's render_patch_id() computes the same
          # thing from the build side; the two must agree on base, range and exclusions or every
          # correct receipt reads stale.
          [[ -n "${PR_BASE_REF:-}" ]] \
            || envfail "spec '$SPEC' arms the design render lane, but PR_BASE_REF is unset or empty — the render binding cannot be recomputed without a base to measure from. Set it on the pr-gates job."
          CUR_RENDER_ID="$(git -C "$REPO_ROOT" diff "$(git -C "$REPO_ROOT" merge-base "origin/$PR_BASE_REF" "$PR_HEAD_SHA" 2>/dev/null)" \
            "$PR_HEAD_SHA" -- . ":(exclude)$VERDICT" ":(exclude)$RENDERS" 2>/dev/null \
            | git -C "$REPO_ROOT" patch-id --stable 2>/dev/null | cut -d' ' -f1)"
          if [[ -z "$CUR_RENDER_ID" ]]; then
            envfail "cannot compute this branch's render patch identity against origin/$PR_BASE_REF — the merge-base is unresolvable (fetch-depth: 0 is required), or the branch's diff excluding '$VERDICT' and '$RENDERS' is empty. A check that cannot run must not report a pass."
          elif [[ "$CUR_RENDER_ID" != "$RENDERED_FROM" ]]; then
            note_violation "render receipt '$RENDERS' records rendered_from ${RENDERED_FROM:0:12}, but this branch renders from ${CUR_RENDER_ID:0:12}. The approved fidelity was scored against screenshots of different code — re-render, commit the fresh receipt, and run another review round."
          fi
        fi
      fi
    fi
  fi
fi

# ---- (13) verdict -----------------------------------------------------------------------
if [[ "$violations" -gt 0 ]]; then
  echo "[lean-chain] ✗ $violations evidence artifact(s) missing for lean PR on #$KEY." >&2
  echo "[lean-chain]   The remedy is producing the missing artifact — there is no waiver." >&2
  exit 1
fi
