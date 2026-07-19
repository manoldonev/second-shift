#!/usr/bin/env bash
# scaffold-review-context.sh — write a starter .claude/second-shift/review-context.md from
# HUMAN-CONFIRMED section content gathered during /second-shift:onboard. It is a formatter
# with two mechanical guards, NOT a generator of policy:
#
#   1. NEVER regenerate. If review-context.md already exists, refuse — the file is the
#      consumer's, not ours to overwrite.
#   2. NEVER emit a TODO-bodied / empty heading. A present-but-hollow section reads as a
#      policy declaration reviewers quote back (worse than an honest absence), and the
#      section lint would fail it at preflight. Every block must carry real content.
#
# It does NOT invent section bodies (detect.sh detects tracker/topology/pkg-manager/lanes —
# not stack/ORM), and it deliberately does NOT validate heading names against the catalog:
# that is check-review-context-sections.sh's job (run it after), keeping section names in
# exactly one place. In particular it never fabricates a `## Maturity stage` body — a
# maturity declaration is a severity waiver and must be the repo's real posture, supplied by
# the human, or omitted.
#
# USAGE:  scaffold-review-context.sh <repo-root> [--title "<repo name>"]  < blocks
#   stdin = one or more H2 blocks, e.g.
#     ## Stack
#     Next.js app router, BullMQ workers, Postgres + pgvector.
#
#     ## Maturity stage
#     Pre-auth MVP: no ownership parameter or tenant guards exist yet.
#   Writes <repo-root>/.claude/second-shift/review-context.md and prints its path.
set -euo pipefail

ROOT=""; TITLE=""
while [ $# -gt 0 ]; do
    case "$1" in
        --title) TITLE="${2:-}"; shift 2 ;;
        -*)      echo "scaffold-review-context: unknown flag '$1'" >&2; exit 2 ;;
        *)       ROOT="$1"; shift ;;
    esac
done
[ -n "$ROOT" ] || { echo "scaffold-review-context: usage: scaffold-review-context.sh <repo-root> [--title NAME] < blocks" >&2; exit 2; }
[ -d "$ROOT" ] || { echo "scaffold-review-context: repo root not found: $ROOT" >&2; exit 2; }
[ -n "$TITLE" ] || TITLE="$(basename "$(cd "$ROOT" && pwd)")"

DEST_DIR="$ROOT/.claude/second-shift"
DEST="$DEST_DIR/review-context.md"
# Guard 1: never regenerate.
if [ -f "$DEST" ]; then
    echo "scaffold-review-context: $DEST already exists — refusing to overwrite (edit it by hand)." >&2
    exit 1
fi

INPUT="$(cat)"
[ -n "$(printf '%s' "$INPUT" | tr -d '[:space:]')" ] || { echo "scaffold-review-context: no section blocks on stdin — nothing to scaffold." >&2; exit 2; }

# Parse stdin into H2 blocks; guard 2: reject any block whose body is empty / placeholder.
# Emitted to a temp buffer first so a rejected block writes nothing.
BUF="$(mktemp)"; trap 'rm -f "$BUF"' EXIT
BAD=""
current=""; body_has_content=0; block_body=""
flush() {
    [ -z "$current" ] && return 0
    if [ "$body_has_content" -eq 0 ]; then
        BAD="$BAD$current
"
    else
        {
            printf '## %s\n' "$current"
            printf '%s\n\n' "$block_body"
        } >> "$BUF"
    fi
}
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        '## '*)
            flush
            current="${line#'## '}"
            current="$(printf '%s' "$current" | sed -e 's/[[:space:]]*$//')"
            body_has_content=0; block_body="" ;;
        '#'*)   : ;;  # ignore H1 / deeper — the H1 title is emitted by us
        *)
            if [ -n "$current" ]; then
                block_body="${block_body:+$block_body
}$line"
                # real content = a non-blank line that is not a whole-line/prefix placeholder.
                # ERE mirrors check-review-context-sections.sh emit_headings() VERBATIM
                # (case-insensitive here = at least as strict) — change them together, so the
                # scaffold can never write a body the section lint then REDs as empty.
                if printf '%s' "$line" | grep -qE '[^[:space:]]' \
                   && ! printf '%s' "$line" | grep -qiE '^[[:space:]]*((TODO|TBD|FIXME)([[:space:]:.-].*)?|_+TBD_+|<[^>]*>|\((TODO|fill)[^)]*\)|…|\.\.\.)[[:space:]]*$'; then
                    body_has_content=1
                fi
            fi ;;
    esac
done <<< "$INPUT"
flush

if [ -n "$BAD" ]; then
    echo "scaffold-review-context: refusing — these sections have an empty/TODO body (write real content or omit the heading):" >&2
    printf '%s' "$BAD" | grep -v '^$' | sed 's/^/  ## /' >&2
    exit 1
fi
[ -s "$BUF" ] || { echo "scaffold-review-context: no valid section blocks after filtering — nothing written." >&2; exit 1; }

mkdir -p "$DEST_DIR"
{
    printf '# Review context — %s\n\n' "$TITLE"
    printf '<!-- Section names must match the catalog exactly — see docs/extension-points.md\n'
    printf '     "Authoring the review-context surface". Lint: check-review-context-sections.sh -->\n\n'
    cat "$BUF"
} > "$DEST"
# Trim the trailing blank line the per-block spacing leaves.
printf '%s\n' "$(cat "$DEST")" > "$DEST"

echo "scaffold-review-context: wrote $DEST"
