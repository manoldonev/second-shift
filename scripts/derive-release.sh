#!/usr/bin/env bash
# derive-release.sh — derive plugin versions, the CHANGELOG section, and release metadata
# from conventional commits + changed paths since the last release tag (#119).
#
# The single source of release derivation: the release-PR workflow
# (.github/workflows/release-pr.yml) and the publish workflow
# (.github/workflows/release-publish.yml) are thin shells around this script.
# Deterministic bash+git+jq only (model-free CI); bash-3.2-safe (no mapfile, no
# associative arrays). Covered by scripts/derive-release-selftest.sh.
#
# Modes:
#   derive-release.sh manifest        JSON manifest of the derivation to stdout
#   derive-release.sh apply           write plugin.json bumps + marketplace.json version +
#                                     CHANGELOG section + pinned-ref doc example, then print
#                                     the release PR body (markdown) to stdout.
#                                     Prints "NOTHING_TO_RELEASE" and exits 0 when no plugin
#                                     changed since the last tag.
#   derive-release.sh release-notes   the GitHub Release body (What-breaks + upgrade recipe)
#
# Derivation rules (issue #119 + its DE decisions comment):
#   - Commit list: <last-tag>..HEAD, excluding subjects matching '^release: ' (the release
#     PR's own squash commits are never counted — explicit, not incidental to tag position).
#   - Changed plugins per commit: from paths under plugins/<name>/, never the commit scope.
#   - Bump level: '!' type suffix or a 'BREAKING CHANGE:' body line -> major; feat -> minor;
#     else patch. Per-plugin level = max across its commits; release level = max across
#     changed plugins, applied to the previous marketplace version.
#   - Cutover/max rule: derived version = max(bump(version-at-tag, level), committed version)
#     so a main that is already hand-bumped ahead never goes backwards.
#   - Changelog: trailers are extracted GREP-ANYWHERE, never via git interpret-trailers: the
#     squash body is a COMMIT_MESSAGES concatenation, and git recognizes trailers only in the
#     final paragraph, so a mid-body 'Changelog:' line must still count. Every '^Changelog:'
#     line opens a block; indented lines continue it; blocks are collected in order.
#     'Changelog: none' counts as trailer-present but renders nothing.
#   - The unreleased CHANGELOG section (a '## vX.Y.Z (in progress)' heading, or a previously
#     generated '## vX.Y.Z' whose tag does not exist yet) is absorbed: its hand-written
#     per-plugin prose is preserved verbatim, its PR references are treated as already
#     covered (no double-counting), and re-running apply is idempotent.
set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || { echo "not in a git repo" >&2; exit 2; }

MODE="${1:-manifest}"
shift $(( $# > 0 ? 1 : 0 ))

LAST_TAG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag) LAST_TAG="${2:?--tag requires a value}"; shift 2 ;;
    *) echo "derive-release: unknown arg $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$LAST_TAG" ]]; then
  LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || true)"
fi
if [[ -z "$LAST_TAG" ]]; then
  echo "derive-release: no release tag found (first release must be cut manually)" >&2
  exit 2
fi

MARKETPLACE=".claude-plugin/marketplace.json"
CHANGELOG="CHANGELOG.md"
PIN_EXAMPLE_DOC="docs/onboarding.md"

PREV_VERSION="$(git show "$LAST_TAG:$MARKETPLACE" 2>/dev/null | jq -r '.metadata.version // empty')"
[[ -n "$PREV_VERSION" ]] || { echo "derive-release: cannot read metadata.version at $LAST_TAG" >&2; exit 2; }

SCRATCH="$(mktemp -d -t derive-release.XXXXXX)"
trap 'rm -rf "$SCRATCH"' EXIT

# ---------- semver helpers (bash 3.2) ----------

bump_ver() { # bump_ver <x.y.z> <level 1|2|3>
  local a b c
  IFS=. read -r a b c <<EOF
$1
EOF
  case "$2" in
    3) echo "$((a + 1)).0.0" ;;
    2) echo "$a.$((b + 1)).0" ;;
    *) echo "$a.$b.$((c + 1))" ;;
  esac
}

ver_max() { # ver_max <a> <b> -> the greater semver
  local a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<EOF
$1
EOF
  IFS=. read -r b1 b2 b3 <<EOF
$2
EOF
  if (( a1 > b1 )) || { (( a1 == b1 )) && (( a2 > b2 )); } \
     || { (( a1 == b1 )) && (( a2 == b2 )) && (( a3 >= b3 )); }; then
    echo "$1"
  else
    echo "$2"
  fi
}

level_name() { case "$1" in 3) echo major ;; 2) echo minor ;; *) echo patch ;; esac; }

# ---------- commit scan ----------
# Records: $SCRATCH/commits.tsv  sha<TAB>level<TAB>pr<TAB>plugins(space-sep)<TAB>subject
# Trailer blocks (blank-line separated): $SCRATCH/trailer-<sha>
# Breaking prose: $SCRATCH/breaking-<sha>

extract_trailers() { # stdin: full body -> stdout: blocks separated by blank lines
  awk '
    /^Changelog:/ { if (inblk) print ""; inblk = 1; sub(/^Changelog:[ \t]*/, ""); if ($0 != "") print; next }
    inblk && /^[ \t]+[^ \t]/ { sub(/^[ \t]+/, ""); print; next }
    inblk { inblk = 0; print "" }
  '
}

extract_breaking() { # stdin: full body -> stdout: BREAKING CHANGE prose (to blank line)
  awk '
    /^BREAKING CHANGE:/ { inblk = 1; sub(/^BREAKING CHANGE:[ \t]*/, ""); if ($0 != "") print; next }
    inblk && /^[ \t]*$/ { inblk = 0; next }
    inblk { sub(/^[ \t]+/, ""); print }
  '
}

: > "$SCRATCH/commits.tsv"
for sha in $(git log --reverse --format=%H "$LAST_TAG..HEAD"); do
  subject="$(git log -1 --format=%s "$sha")"
  case "$subject" in "release: "*) continue ;; esac

  plugins="$(git show --name-only --format= "$sha" | sed -n 's|^plugins/\([^/]*\)/.*|\1|p' | sort -u | tr '\n' ' ')"
  plugins="${plugins% }"
  [[ -n "$plugins" ]] || continue

  body="$(git log -1 --format=%b "$sha")"

  level=1
  if printf '%s' "$subject" | grep -qE '^[a-z]+(\([^)]*\))?!:'; then
    level=3
  elif printf '%s\n' "$body" | grep -qE '^BREAKING CHANGE:'; then
    level=3
  elif printf '%s' "$subject" | grep -qE '^feat(\([^)]*\))?:'; then
    level=2
  fi

  pr="$(printf '%s' "$subject" | grep -oE '\(#[0-9]+\)[[:space:]]*$' | grep -oE '[0-9]+' || true)"

  printf '%s\t%s\t%s\t%s\t%s\n' "$sha" "$level" "$pr" "$plugins" "$subject" >> "$SCRATCH/commits.tsv"
  printf '%s\n' "$body" | extract_trailers > "$SCRATCH/trailer-$sha"
  printf '%s\n' "$body" | extract_breaking > "$SCRATCH/breaking-$sha"
done

CHANGED_PLUGINS="$(cut -f4 "$SCRATCH/commits.tsv" | tr ' ' '\n' | sort -u | grep -v '^$' || true)"

if [[ -z "$CHANGED_PLUGINS" ]]; then
  if [[ "$MODE" == "apply" ]]; then echo "NOTHING_TO_RELEASE"; exit 0; fi
  if [[ "$MODE" == "manifest" ]]; then
    jq -n --arg tag "$LAST_TAG" --arg prev "$PREV_VERSION" \
      '{previousTag: $tag, previousVersion: $prev, releaseVersion: null, plugins: {}, prs: []}'
    exit 0
  fi
fi

# ---------- per-plugin aggregation ----------
# $SCRATCH/plugver.tsv: name<TAB>oldVer(at tag)<TAB>newVer<TAB>levelNum

RELEASE_LEVEL=1
: > "$SCRATCH/plugver.tsv"
for p in $CHANGED_PLUGINS; do
  manifest="plugins/$p/.claude-plugin/plugin.json"
  old_ver="$(git show "$LAST_TAG:$manifest" 2>/dev/null | jq -r '.version // empty')"
  cur_ver="$(jq -r '.version // empty' "$manifest" 2>/dev/null)"
  plevel=1
  while IFS=$'\t' read -r _sha lvl _pr plugs _subj; do
    case " $plugs " in *" $p "*) (( lvl > plevel )) && plevel=$lvl ;; esac
  done < "$SCRATCH/commits.tsv"
  (( plevel > RELEASE_LEVEL )) && RELEASE_LEVEL=$plevel

  if [[ -z "$old_ver" ]]; then
    # New plugin since the tag — its committed version is authoritative.
    new_ver="${cur_ver:-0.1.0}"
    old_ver="(new)"
  else
    new_ver="$(bump_ver "$old_ver" "$plevel")"
    # Max rule: never go backwards vs a hand-bumped committed version (cutover).
    [[ -n "$cur_ver" ]] && new_ver="$(ver_max "$new_ver" "$cur_ver")"
  fi
  printf '%s\t%s\t%s\t%s\n' "$p" "$old_ver" "$new_ver" "$plevel" >> "$SCRATCH/plugver.tsv"
done

RELEASE_VERSION="$(bump_ver "$PREV_VERSION" "$RELEASE_LEVEL")"
CUR_MARKET_VERSION="$(jq -r '.metadata.version // empty' "$MARKETPLACE" 2>/dev/null)"
[[ -n "$CUR_MARKET_VERSION" ]] && RELEASE_VERSION="$(ver_max "$RELEASE_VERSION" "$CUR_MARKET_VERSION")"

# ---------- manifest mode ----------

if [[ "$MODE" == "manifest" ]]; then
  PLUGINS_JSON="{}"
  while IFS=$'\t' read -r name old new lvl; do
    PLUGINS_JSON="$(jq -n --argjson acc "$PLUGINS_JSON" --arg n "$name" --arg o "$old" --arg w "$new" --arg l "$(level_name "$lvl")" \
      '$acc + {($n): {old: $o, new: $w, level: $l}}')"
  done < "$SCRATCH/plugver.tsv"

  PRS_JSON="[]"
  while IFS=$'\t' read -r sha lvl pr plugs subj; do
    tr_json="$(jq -R -s 'split("\n\n") | map(select(. != "" and . != "\n")) | map(rtrimstr("\n"))' < "$SCRATCH/trailer-$sha")"
    br="$(cat "$SCRATCH/breaking-$sha")"
    no_trailer=true
    [[ -s "$SCRATCH/trailer-$sha" ]] && no_trailer=false
    PRS_JSON="$(jq -n --argjson acc "$PRS_JSON" --arg sha "$sha" --arg subj "$subj" --arg pr "$pr" \
      --arg plugs "$plugs" --arg lvl "$(level_name "$lvl")" --argjson tr "$tr_json" --arg br "$br" --argjson nt "$no_trailer" \
      '$acc + [{sha: $sha, subject: $subj, prNumber: (if $pr == "" then null else ($pr | tonumber) end),
                plugins: ($plugs | split(" ")), level: $lvl, changelog: $tr,
                breaking: (if $br == "" then null else $br end), noTrailer: $nt}]')"
  done < "$SCRATCH/commits.tsv"

  jq -n --arg tag "$LAST_TAG" --arg prev "$PREV_VERSION" --arg rel "$RELEASE_VERSION" \
    --argjson plugins "$PLUGINS_JSON" --argjson prs "$PRS_JSON" \
    '{previousTag: $tag, previousVersion: $prev, releaseVersion: $rel, plugins: $plugins, prs: $prs}'
  exit 0
fi

# ---------- shared rendering helpers (apply + release-notes) ----------

render_bullet() { # render_bullet <sha> <subject> <pr> -> markdown bullet with trailer prose
  local sha="$1" subj="$2" pr="$3" suffix=""
  [[ -n "$pr" ]] && suffix=" (#$pr)"
  printf -- '- **%s**%s\n' "$subj" "$suffix"
  if [[ -s "$SCRATCH/trailer-$sha" ]]; then
    # Render every non-"none" block as indented bullet body.
    awk 'BEGIN { RS = "" } $0 != "none" { n = split($0, lines, "\n"); for (i = 1; i <= n; i++) print "  " lines[i] }' \
      "$SCRATCH/trailer-$sha"
  fi
  if [[ -s "$SCRATCH/breaking-$sha" ]]; then
    printf '  **BREAKING:** %s\n' "$(tr '\n' ' ' < "$SCRATCH/breaking-$sha" | sed 's/ $//')"
  fi
}

# ---------- absorb the unreleased CHANGELOG section ----------
# The absorb source is the FIRST '## vX.Y.Z' section whose tag does not exist (covers both
# the hand-written '(in progress)' form and a previously generated, still-unreleased one).

ABSORB_FILE="$SCRATCH/absorbed"   # section content without its '## ' heading
: > "$ABSORB_FILE"
ABSORB_HEADING=""
if [[ -f "$CHANGELOG" ]]; then
  first_heading="$(grep -n '^## ' "$CHANGELOG" | head -1 || true)"
  if [[ -n "$first_heading" ]]; then
    line_no="${first_heading%%:*}"
    heading_text="${first_heading#*:}"
    ver_in_heading="$(printf '%s' "$heading_text" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
    if [[ -n "$ver_in_heading" ]] && ! git rev-parse -q --verify "refs/tags/$ver_in_heading" >/dev/null; then
      ABSORB_HEADING="$heading_text"
      awk -v start="$line_no" 'NR > start { if (/^## /) exit; print }' "$CHANGELOG" > "$ABSORB_FILE"
    fi
  fi
fi

COVERED_PRS="$(grep -oE '#[0-9]+' "$ABSORB_FILE" 2>/dev/null | sort -u || true)"

pr_covered() { # pr_covered <n> -> 0 if the absorbed prose already references PR #n
  [[ -n "$1" ]] || return 1
  printf '%s\n' "$COVERED_PRS" | grep -qx "#$1"
}

# Split absorbed content into per-plugin chunks keyed by the backticked plugin name.
# Chunk body files: $SCRATCH/absorb-<plugin>; content before the first '### ' is kept as-is.
ABSORB_PREFIX="$SCRATCH/absorb-prefix"
awk -v dir="$SCRATCH" '
  /^### / {
    name = ""
    if (match($0, /`[^`]+`/)) name = substr($0, RSTART + 1, RLENGTH - 2)
    if (name != "") { out = dir "/absorb-" name; next }
  }
  { if (out != "") print >> out; else print >> (dir "/absorb-prefix") }
' "$ABSORB_FILE" 2>/dev/null || true

# ---------- render the generated CHANGELOG section ----------

SECTION="$SCRATCH/section.md"
{
  printf '## v%s\n' "$RELEASE_VERSION"
  if [[ -s "$ABSORB_PREFIX" ]]; then
    awk '{ lines[NR] = $0 } END { s = 1; n = NR; while (s <= n && lines[s] ~ /^[[:space:]]*$/) s++; while (n >= s && lines[n] ~ /^[[:space:]]*$/) n--; for (i = s; i <= n; i++) print lines[i] }' \
      "$ABSORB_PREFIX"
  fi
  while IFS=$'\t' read -r name old new _lvl; do
    printf '\n### `%s` %s → %s\n\n' "$name" "$old" "$new"
    if [[ -s "$SCRATCH/absorb-$name" ]]; then
      # Preserved hand-written prose (trim trailing blank lines; portable awk, not GNU sed).
      awk '{ lines[NR] = $0 } END { s = 1; n = NR; while (s <= n && lines[s] ~ /^[[:space:]]*$/) s++; while (n >= s && lines[n] ~ /^[[:space:]]*$/) n--; for (i = s; i <= n; i++) print lines[i] }' \
        "$SCRATCH/absorb-$name"
    fi
    while IFS=$'\t' read -r sha _l pr plugs subj; do
      case " $plugs " in *" $name "*) ;; *) continue ;; esac
      pr_covered "$pr" && continue
      render_bullet "$sha" "$subj" "$pr"
    done < "$SCRATCH/commits.tsv"
  done < "$SCRATCH/plugver.tsv"
} > "$SECTION"

# ---------- What-breaks assembly (release notes + PR body preview) ----------

WHAT_BREAKS="$SCRATCH/what-breaks.md"
{
  found=0
  while IFS=$'\t' read -r sha _lvl pr _plugs subj; do
    ref=""
    [[ -n "$pr" ]] && ref=" (#$pr)"
    has_breaking=0
    has_migration=0
    [[ -s "$SCRATCH/breaking-$sha" ]] && has_breaking=1
    grep -q 'Migration:' "$SCRATCH/trailer-$sha" 2>/dev/null && has_migration=1
    if [[ "$has_breaking" -eq 1 ]]; then
      printf -- '- **%s**%s — %s\n' "$subj" "$ref" "$(tr '\n' ' ' < "$SCRATCH/breaking-$sha" | sed 's/ $//')"
      found=1
    elif [[ "$has_migration" -eq 1 ]]; then
      printf -- '- **%s**%s:\n' "$subj" "$ref"
      found=1
    fi
    if [[ "$has_migration" -eq 1 ]]; then
      awk 'BEGIN { RS = "" } /Migration:/ { n = split($0, lines, "\n"); for (i = 1; i <= n; i++) print "  " lines[i] }' \
        "$SCRATCH/trailer-$sha"
    fi
  done < "$SCRATCH/commits.tsv"
  [[ "$found" -eq 0 ]] && echo "Nothing breaks."
} > "$WHAT_BREAKS"

UPGRADE_RECIPE="$SCRATCH/recipe.md"
cat > "$UPGRADE_RECIPE" <<EOF
## Upgrade recipe

One PR per consumer repo: bump the settings \`ref\` AND \`.claude/second-shift.lock.json\` together to \`v$RELEASE_VERSION\`, then:

\`\`\`bash
claude plugin marketplace update second-shift
# reinstall the plugins your repo uses, then re-run your validation gates
\`\`\`

\`/second-shift:onboard\` resolves \`releases/latest\` — this Release is the publish step.
EOF

# ---------- release-notes mode ----------

if [[ "$MODE" == "release-notes" ]]; then
  printf '## What breaks / what to do\n\n'
  cat "$WHAT_BREAKS"
  printf '\n'
  cat "$UPGRADE_RECIPE"
  exit 0
fi

# ---------- apply mode ----------

if [[ "$MODE" != "apply" ]]; then
  echo "derive-release: unknown mode '$MODE' (manifest|apply|release-notes)" >&2
  exit 2
fi

# 1. plugin.json bumps
while IFS=$'\t' read -r name _old new _lvl; do
  manifest="plugins/$name/.claude-plugin/plugin.json"
  [[ -f "$manifest" ]] || continue
  tmp="$SCRATCH/plugin.json"
  jq --arg v "$new" '.version = $v' "$manifest" > "$tmp" && cat "$tmp" > "$manifest"
done < "$SCRATCH/plugver.tsv"

# 2. marketplace.json lockstep version
tmp="$SCRATCH/marketplace.json"
jq --arg v "$RELEASE_VERSION" '.metadata.version = $v' "$MARKETPLACE" > "$tmp" && cat "$tmp" > "$MARKETPLACE"

# 3. CHANGELOG: drop the absorbed section, insert the generated one before the first '## '.
tmp="$SCRATCH/changelog.new"
if [[ -n "$ABSORB_HEADING" ]]; then
  # Remove the absorbed section (its heading line through the line before the next '## ').
  awk -v hd="$ABSORB_HEADING" '
    $0 == hd { drop = 1; next }
    drop && /^## / { drop = 0 }
    !drop { print }
  ' "$CHANGELOG" > "$SCRATCH/changelog.stripped"
else
  cp "$CHANGELOG" "$SCRATCH/changelog.stripped"
fi
awk -v section="$SECTION" '
  !inserted && /^## / { while ((getline line < section) > 0) print line; print ""; inserted = 1 }
  { print }
  END { if (!inserted) { while ((getline line < section) > 0) print line } }
' "$SCRATCH/changelog.stripped" > "$tmp"
cat "$tmp" > "$CHANGELOG"

# 4. Pinned-ref doc example (the single pin site — docs/onboarding.md).
if [[ -f "$PIN_EXAMPLE_DOC" ]]; then
  sed -E "s|(\"ref\":[[:space:]]*\")v[0-9]+\.[0-9]+\.[0-9]+(\")|\1v$RELEASE_VERSION\2|" "$PIN_EXAMPLE_DOC" > "$SCRATCH/pin.doc" \
    && cat "$SCRATCH/pin.doc" > "$PIN_EXAMPLE_DOC"
fi

# 5. Release PR body to stdout.
printf '# release: v%s\n\n' "$RELEASE_VERSION"
printf 'Derived from `%s..HEAD` by `scripts/derive-release.sh` (re-derived on every push to main; this branch is bot-owned and force-pushed — land human edits after the last feature merge).\n\n' "$LAST_TAG"
printf '## Version bumps\n\n'
printf '| Plugin | %s | This release | Level |\n| --- | --- | --- | --- |\n' "$LAST_TAG"
while IFS=$'\t' read -r name old new lvl; do
  printf '| `%s` | %s | **%s** | %s |\n' "$name" "$old" "$new" "$(level_name "$lvl")"
done < "$SCRATCH/plugver.tsv"
printf '| marketplace | %s | **%s** | %s |\n' "$PREV_VERSION" "$RELEASE_VERSION" "$(level_name "$RELEASE_LEVEL")"
printf '\n## What breaks / what to do (preview)\n\n'
cat "$WHAT_BREAKS"
NO_TRAILER_LINES="$SCRATCH/no-trailer.md"
: > "$NO_TRAILER_LINES"
while IFS=$'\t' read -r sha _lvl pr _plugs subj; do
  if [[ ! -s "$SCRATCH/trailer-$sha" && ! -s "$SCRATCH/breaking-$sha" ]]; then
    ref=""
    [[ -n "$pr" ]] && ref=" (#$pr)"
    pr_covered "$pr" && continue
    printf -- '- %s%s\n' "$subj" "$ref" >> "$NO_TRAILER_LINES"
  fi
done < "$SCRATCH/commits.tsv"
if [[ -s "$NO_TRAILER_LINES" ]]; then
  printf '\n## Subject-only entries (no `Changelog:` trailer)\n\nThese merged without a trailer — add migration prose here if any is needed:\n\n'
  cat "$NO_TRAILER_LINES"
fi
cat <<'EOF'

## Human checklist (resolve before merge)

- [ ] Migration prose reviewed/edited in the CHANGELOG section (edit AFTER the last feature merge — re-derives force-push this branch).
- [ ] Section catalog (`plugins/review-toolkit/scripts/section-catalog.txt`): if this release changes it, check known-consumer `review-context.md` headings and list any newly-flagging heading in the What-breaks body (rename = `deprecated-alias-of:` row, never a bare deletion).
- [ ] Plugin renames: if any, recorded in the marketplace.json `renames` map and disclosed in the Release notes.
- [ ] Major bump with a schema change: `docs/migrations/vN-to-vN+1.md` exists (CI gates this).
EOF
