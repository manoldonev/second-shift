#!/usr/bin/env bash
# check-review-context-sections.sh — lint the NAMED SECTIONS (H2 headings) inside a
# consumer's .claude/second-shift/review-context.md and review-context/<reviewer>.md files
# against the machine-readable section catalog (section-catalog.txt, sibling). This is the
# in-file counterpart to check-review-context.sh (which lints file BASENAMES): it closes the
# "silent inside the file" gap where a renamed or emptied section silently degrades the
# reviewer that keys on it.
#
# TWO TARGETS (#1032). The catalog's optional fourth column names the file a section lives in:
# review-context.md (the default, which also covers the per-reviewer review-context/<reviewer>.md)
# or intake-context.md, which /intake-toolkit:intake reads. A heading is checked only against its
# own file's sections, and a target's sections count toward coverage only when its file is there.
# A reader that is not a reviewer — the /intake session — is declared in the catalog as a
# `reader:` token, so the coverage line names it instead of dropping it.
#
# SCOPE: H2 headings only (`^## `). H1 title lines (`^# `) are NEVER linted — a repo's
# per-reviewer files legitimately open with `# <reviewer> — <repo>` — and H3+ headings are
# section content (subsection structure), not sections. Fenced code lines are never headings.
#
# VENUES / MODES (severity by venue — the approved #67 ladder):
#   (default, no flag)  mid-run posture: alias hits + present-but-empty catalog sections
#                       print as WARN; novel + missing suppressed (unless --verbose). Exit 0
#                       ALWAYS — mid-run never blocks on a pre-existing heading.
#   --preflight         pre-work gate: alias hits + present-but-empty catalog sections are
#                       ERRORS (non-zero exit); novel headings WARN; missing = coverage INFO.
#                       Also prints the one-line coverage summary (exit-neutral).
#   --report            informational: prints ONLY the one-line coverage summary. Exit 0
#                       ALWAYS (coverage can never contribute to the exit code — asserted by
#                       the selftest). Feeds the #34 doctor --report bundle.
#   --verbose           modifier (any mode): also surface INFO (novel + missing sections).
#
# ESCAPE HATCH (mirrors EP-3 .known-extensions): a heading listed in
# .claude/second-shift/.known-sections (one per line) OR as a `section:<name>` line in
# .claude/second-shift/.known-extensions is recognized-and-intentional — never flagged.
# Additive-only, auditable in the repo.
#
# ROOT RESOLUTION (env overrides win, for hermetic selftests — mirrors check-review-context.sh):
#   PLUGIN root    = $SECOND_SHIFT_PLUGIN_ROOT  or  $SCRIPT_DIR/..   (catalog = $SCRIPT_DIR/section-catalog.txt)
#   CONSUMER root  = $1  or  $SECOND_SHIFT_REPO_ROOT  or  dirname(git --git-common-dir)
#   config         = $SECOND_SHIFT_CONFIG  or  <consumer>/.claude/second-shift.config.json
# Missing review-context.md, review-context/ dir AND intake-context.md = clean (surface unused).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="${SECOND_SHIFT_PLUGIN_ROOT:-$SCRIPT_DIR/..}"
SKILL="$PLUGIN_ROOT/skills/review-lead/SKILL.md"
CATALOG="${SECOND_SHIFT_SECTION_CATALOG:-$SCRIPT_DIR/section-catalog.txt}"

MODE="default"; VERBOSE=0; CONSUMER_ARG=""
for arg in "$@"; do
    case "$arg" in
        --preflight) MODE="preflight" ;;
        --report)    MODE="report" ;;
        --verbose)   VERBOSE=1 ;;
        -*)          echo "check-review-context-sections: unknown flag '$arg'" >&2; exit 2 ;;
        *)           CONSUMER_ARG="$arg" ;;
    esac
done

if [ -n "$CONSUMER_ARG" ]; then
    CONSUMER_ROOT="$CONSUMER_ARG"
elif [ -n "${SECOND_SHIFT_REPO_ROOT:-}" ]; then
    CONSUMER_ROOT="$SECOND_SHIFT_REPO_ROOT"
else
    CONSUMER_ROOT="$(dirname "$(git rev-parse --git-common-dir 2>/dev/null || echo .)")"
fi

SS_DIR="$CONSUMER_ROOT/.claude/second-shift"
SHARED="$SS_DIR/review-context.md"
RC_DIR="$SS_DIR/review-context"
INTAKE_CTX="$SS_DIR/intake-context.md"
CONFIG="${SECOND_SHIFT_CONFIG:-$CONSUMER_ROOT/.claude/second-shift.config.json}"

# Surface unused → clean, whatever the mode.
if [ ! -f "$SHARED" ] && [ ! -d "$RC_DIR" ] && [ ! -f "$INTAKE_CTX" ]; then
    if [ "$MODE" = "report" ]; then
        echo "context-coverage: no review-context surface (clean)"
    else
        echo "check-review-context-sections: clean (no review-context surface)"
    fi
    exit 0
fi

[ -f "$CATALOG" ] || { echo "check-review-context-sections: ERROR — section catalog not found at $CATALOG" >&2; exit 2; }

# ---- Parse the catalog -------------------------------------------------------
# A section is keyed by "<target>/<name>": the same heading in two files is two sections.
# ACTIVE_NAMES: newline list of active "<target>/<name>" keys.
# READERS:      "<target>/<name><TAB>readers" per active section.
# ALIASES:      "<target>/<alias><TAB>canonical" per deprecated-alias-of row.
# READER_TOKENS: newline list of declared non-reviewer reader tokens (`reader:` lines).
ACTIVE_NAMES=""; READERS=""; ALIASES=""; READER_TOKENS=""
trim_ws() { printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }
while IFS='|' read -r c_name c_readers c_status c_file; do
    name="$(trim_ws "$c_name")"
    [ -z "$name" ] && continue
    case "$name" in \#*) continue ;; esac
    case "$name" in
        reader:*)
            tok="$(trim_ws "${name#reader:}")"
            [ -n "$tok" ] && READER_TOKENS="$READER_TOKENS$tok
"
            continue ;;
    esac
    readers="$(trim_ws "$c_readers")"
    status="$(trim_ws "$c_status")"
    target="$(trim_ws "$c_file")"; target="${target:-review-context.md}"
    case "$target" in
        review-context.md|intake-context.md) ;;
        *) echo "check-review-context-sections: WARN — unknown file '$target' for section '$name' in catalog" >&2; continue ;;
    esac
    case "$status" in
        deprecated-alias-of:*)
            canonical="${status#deprecated-alias-of:}"
            ALIASES="$ALIASES$target/$name	$canonical
" ;;
        active|"")
            ACTIVE_NAMES="$ACTIVE_NAMES$target/$name
"
            READERS="$READERS$target/$name	$readers
" ;;
        *) echo "check-review-context-sections: WARN — unknown status '$status' for section '$name' in catalog" >&2 ;;
    esac
done < "$CATALOG"

# ---- Escape hatch: recognized off-catalog headings ---------------------------
KNOWN=""
KS_FILE="$SS_DIR/.known-sections"
if [ -f "$KS_FILE" ]; then
    while IFS= read -r line; do
        line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
        [ -z "$line" ] && continue
        case "$line" in \#*) continue ;; esac
        KNOWN="$KNOWN$line
"
    done < "$KS_FILE"
fi
KE_FILE="$SS_DIR/.known-extensions"
if [ -f "$KE_FILE" ]; then
    while IFS= read -r line; do
        case "$line" in
            section:*)
                s="${line#section:}"
                s="$(printf '%s' "$s" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
                [ -n "$s" ] && KNOWN="$KNOWN$s
" ;;
        esac
    done < "$KE_FILE"
fi

is_known() { [ -n "$KNOWN" ] && printf '%s\n' "$KNOWN" | grep -Fxq "$1"; }
is_active() { printf '%s\n' "$ACTIVE_NAMES" | grep -Fxq "$1"; }   # $1 = "<target>/<name>"
alias_target() { printf '%s\n' "$ALIASES" | awk -F'\t' -v a="$1" '$1==a{print $2; exit}'; }

# ---- Walk both homes, emit "heading<TAB>empty|nonempty" per H2 heading --------
# Sections are H2 ONLY: an H3+ heading is section CONTENT (it structures the body and
# marks the enclosing H2 non-empty), never a section itself — `## Stack` organized into
# `### Frontend` / `### Backend` is one present section, not three findings. Lines inside
# ``` / ~~~ code fences are never headings (a quoted `## Maturity stage` example must not
# trip the alias gate); a fence in a section body counts as real content. Single-level
# fences only — a fence nested inside another fence re-toggles.
# The placeholder ERE is mirrored VERBATIM (case-insensitively) in onboard's
# scaffold-review-context.sh guard — change them together.
emit_headings() {  # $1 = file
    awk '
      /^[[:space:]]*(```|~~~)/ {
        fence = !fence;
        if (prevh != "") seen=1;   # fenced example/code in a body is real content
        next;
      }
      fence { if (prevh != "") seen=1; next; }
      /^##[[:space:]]/ {
        if (prevh != "") print prevh "\t" (seen ? "nonempty" : "empty");
        h=$0; sub(/^##[[:space:]]+/,"",h); sub(/[[:space:]]+$/,"",h);
        prevh=h; seen=0;
        next;
      }
      /^#[[:space:]]/ {
        if (prevh != "") print prevh "\t" (seen ? "nonempty" : "empty");
        prevh="";   # H1 — never linted; ends the current section
        next;
      }
      {
        if (prevh != "") {
          l=$0;
          # real content = a non-blank line that is not a whole-line/prefix placeholder
          if (l ~ /[^[:space:]]/ && l !~ /^[[:space:]]*((TODO|TBD|FIXME)([[:space:]:.-].*)?|_+TBD_+|<[^>]*>|\((TODO|fill)[^)]*\)|…|\.\.\.)[[:space:]]*$/) seen=1;
        }
      }
      END { if (prevh != "") print prevh "\t" (seen ? "nonempty" : "empty"); }
    ' "$1"
}

# Each home is "<target><TAB><path>": its headings are checked against that target's sections.
HOMES=""; TARGETS_PRESENT=""
if [ -f "$SHARED" ] || [ -d "$RC_DIR" ]; then TARGETS_PRESENT="review-context.md
"; fi
[ -f "$SHARED" ] && HOMES="review-context.md	$SHARED"
if [ -d "$RC_DIR" ]; then
    while IFS= read -r f; do HOMES="$HOMES
review-context.md	$f"; done < <(find "$RC_DIR" -maxdepth 1 -type f -name '*.md' | sort)
fi
if [ -f "$INTAKE_CTX" ]; then
    HOMES="$HOMES
intake-context.md	$INTAKE_CTX"
    TARGETS_PRESENT="${TARGETS_PRESENT}intake-context.md
"
fi

# Accumulators (newline lists).
PRESENT=""       # "<target>/<name>" active sections present with non-empty body
EMPTY_HITS=""    # "name<TAB>file" active names present but empty-bodied
ALIAS_HITS=""    # "alias<TAB>canonical<TAB>file"
NOVEL=""         # "heading<TAB>file"

while IFS='	' read -r target home; do
    [ -z "$home" ] && continue
    [ -f "$home" ] || continue
    while IFS='	' read -r heading body; do
        [ -z "$heading" ] && continue
        if is_active "$target/$heading"; then
            if [ "$body" = "empty" ]; then
                EMPTY_HITS="$EMPTY_HITS$heading	$home
"
            else
                PRESENT="$PRESENT$target/$heading
"
            fi
        elif tgt="$(alias_target "$target/$heading")" && [ -n "$tgt" ]; then
            ALIAS_HITS="$ALIAS_HITS$heading	$tgt	$home
"
        elif is_known "$heading"; then
            :   # recognized-and-intentional — never flagged
        else
            NOVEL="$NOVEL$heading	$home
"
        fi
    done < <(emit_headings "$home")
done < <(printf '%s\n' "$HOMES")

# ---- Effective registry (for coverage: don't nag about removed reviewers) -----
# shellcheck source=_effective-registry.sh
. "$SCRIPT_DIR/_effective-registry.sh"
EFFECTIVE=""
if [ -f "$SKILL" ]; then
    EFFECTIVE="$(compute_effective_registry "$SKILL" "$CONFIG" 2>/dev/null || true)"
fi
reader_effective() {  # $1 = reader token; true if 'all', a declared non-reviewer token, or in the effective registry (or registry unknown)
    [ "$1" = "all" ] && return 0
    [ -n "$READER_TOKENS" ] && printf '%s\n' "$READER_TOKENS" | grep -Fxq "$1" && return 0
    [ -z "$EFFECTIVE" ] && return 0
    printf '%s\n' "$EFFECTIVE" | grep -Fxq "$1"
}

# ---- Coverage computation (exit-neutral) -------------------------------------
# A section counts PRESENT only when its exact active name appears with a non-empty body
# (alias-named or empty-bodied ⇒ absent: the reviewer that keys on the exact name finds
# nothing). Degraded readers = readers of absent sections, filtered to the effective set plus
# the declared non-reviewer tokens. Only the sections of a target whose file is there count: a
# repo with no intake-context.md has declared no knowledge source, which degrades nothing.
coverage_line() {
    local total=0 present_n=0 absent_readers="" degraded=""
    while IFS='	' read -r name readers; do
        [ -z "$name" ] && continue
        printf '%s' "$TARGETS_PRESENT" | grep -Fxq "${name%%/*}" || continue
        total=$((total+1))
        if printf '%s\n' "$PRESENT" | grep -Fxq "$name"; then
            present_n=$((present_n+1))
        else
            # absent — collect its effective readers (the `all` sentinel expands to the
            # whole effective registry so the line carries concrete reviewer names).
            local IFS_OLD="$IFS"; IFS=','
            for r in $readers; do
                r="$(printf '%s' "$r" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
                [ -z "$r" ] && continue
                if [ "$r" = "all" ]; then
                    if [ -n "$EFFECTIVE" ]; then absent_readers="$absent_readers$EFFECTIVE
"; else absent_readers="$absent_readers""all-reviewers
"; fi
                elif reader_effective "$r"; then
                    absent_readers="$absent_readers$r
"
                fi
            done
            IFS="$IFS_OLD"
        fi
    done < <(printf '%s' "$READERS")
    degraded="$(printf '%s' "$absent_readers" | grep -v '^$' | sort -u | paste -sd ',' - 2>/dev/null || true)"
    if [ -z "$degraded" ]; then
        echo "context-coverage: ${present_n}/${total} catalog sections present; no degraded readers"
    else
        echo "context-coverage: ${present_n}/${total} catalog sections present; degraded readers: ${degraded}"
    fi
}

# ---- Emit findings + decide exit ---------------------------------------------
RC=0
emit_alias() {
    while IFS='	' read -r al tgt file; do
        [ -z "$al" ] && continue
        local rel="${file#"$CONSUMER_ROOT"/}"
        local msg="ALIAS: \"## $al\" in $rel is a drifted spelling of the catalog section \"## $tgt\" — rename the heading \"## $al\" to \"## $tgt\" in $rel"
        if [ "$MODE" = "preflight" ]; then echo "$msg" >&2; RC=1; else echo "check-review-context-sections: WARN — $msg" >&2; fi
    done < <(printf '%s' "$ALIAS_HITS")
}
emit_empty() {
    while IFS='	' read -r name file; do
        [ -z "$name" ] && continue
        local rel="${file#"$CONSUMER_ROOT"/}"
        local msg="EMPTY-SECTION: \"## $name\" in $rel has an empty/TODO body — a reviewer that keys on it gets nothing (treated as absent). Fill it in or delete the heading."
        if [ "$MODE" = "preflight" ]; then echo "$msg" >&2; RC=1; else echo "check-review-context-sections: WARN — $msg" >&2; fi
    done < <(printf '%s' "$EMPTY_HITS")
}
emit_novel() {
    while IFS='	' read -r heading file; do
        [ -z "$heading" ] && continue
        local rel="${file#"$CONSUMER_ROOT"/}"
        local msg="OFF-CATALOG: \"## $heading\" in $rel is not a catalog section — fine if intentional; add it to .claude/second-shift/.known-sections to silence this."
        if [ "$MODE" = "preflight" ] || [ "$VERBOSE" = "1" ]; then echo "check-review-context-sections: WARN — $msg" >&2; fi
    done < <(printf '%s' "$NOVEL")
}

case "$MODE" in
    report)
        coverage_line
        exit 0 ;;   # coverage NEVER contributes to the exit code
    preflight)
        emit_alias
        emit_empty
        emit_novel
        coverage_line   # exit-neutral informational line
        if [ "$RC" -eq 0 ]; then echo "check-review-context-sections: preflight OK (no alias/empty-section blockers)"; fi
        exit "$RC" ;;
    default)
        emit_alias      # WARN only (RC untouched in non-preflight)
        emit_empty      # WARN only
        emit_novel      # suppressed unless --verbose
        [ "$VERBOSE" = "1" ] && coverage_line
        echo "check-review-context-sections: OK (mid-run advisory; use --preflight for the gate, --report for coverage)"
        exit 0 ;;
esac
