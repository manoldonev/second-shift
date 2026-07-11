#!/usr/bin/env bash
# install-gh-bot.sh — provision the dev-pipeline gh bot wrapper on a new machine.
#
# The dev-pipeline / pr-revision skills require
# $HOME/.config/<consumer-repo-dir-basename>/gh-as-bot.sh for all GitHub write
# operations (Bot Identity section in SKILL.md) — the SAME path claim-issue.sh
# derives as its GH_BOT default, so creator and consumer stay consistent. The
# basename comes from the consumer repo root (SECOND_SHIFT_REPO_ROOT, else the
# main checkout via `git rev-parse --git-common-dir`). This script is the one-shot
# machine bootstrap: it installs the GitHub App private key, discovers the
# installation ID, writes the wrapper, and smoke-tests it.
#
# GitHub App identity + wrapper path resolve from second-shift.config.json when
# present (tracker.bot.app.{clientId,appName,privateKeyFilename,installationId}
# and tracker.bot.wrapperPath), falling back to the acme defaults below so a
# config-less checkout is unchanged. --client-id / --installation-id still win over
# both (explicit-flag precedence). Onboarding a different repo's bot app is now a
# config edit, not a script edit.
#
# Usage:
#   bash install-gh-bot.sh <path-to-private-key.pem>   # first install on a machine
#   bash install-gh-bot.sh                              # re-run: key already installed,
#                                                       # regenerate wrapper + smoke test
#
# Options:
#   --client-id <id>          Override the GitHub App client ID (JWT issuer)
#   --installation-id <id>    Skip API discovery and pin the installation ID
#
# The private key is downloaded from the App settings page
# (https://github.com/settings/apps/acme-dev-pipeline → "Generate a private key";
# keys are additive — a new key does not invalidate keys on other machines).
# The source key file is MOVED into ~/.config/acme/ (chmod 600), so nothing
# secret is left behind in e.g. ~/Downloads.

set -euo pipefail

# GitHub App defaults: acme-dev-pipeline (App ID 3218891, bot acme-dev-pipeline[bot]).
# Overridden per-repo by tracker.bot.app.* in second-shift.config.json (below).
CLIENT_ID="Iv23linWw3EWmAuuAiZP"
INSTALLATION_ID=""
APP_NAME="acme-dev-pipeline"
KEY_FILENAME="acme-dev-pipeline.private-key.pem"

# Consumer-repo config dir basename — kept in lockstep with claim-issue.sh's GH_BOT
# default so the wrapper this script WRITES is the one the pipeline READS.
_root="${SECOND_SHIFT_REPO_ROOT:-}"
if [[ -z "$_root" ]]; then
  _common="$(git rev-parse --git-common-dir 2>/dev/null || true)"
  [[ -n "$_common" ]] && _root="$(dirname "$(cd "$_common" && pwd)")"
fi
if [[ -z "$_root" ]]; then
  echo "[install-gh-bot] cannot resolve the consumer repo root — run from inside the repo, or set SECOND_SHIFT_REPO_ROOT" >&2
  exit 2
fi
REPO_BASENAME="$(basename "$_root")"

# Config overlay: read the bot app identity + wrapper path from the consumer config
# when it exists ($SECOND_SHIFT_CONFIG wins, else <root>/.claude/second-shift.config.json).
# jq '// empty' leaves each default untouched when the key is absent.
_cfg="${SECOND_SHIFT_CONFIG:-$_root/.claude/second-shift.config.json}"
WRAPPER_OVERRIDE=""
if [[ -f "$_cfg" ]] && command -v jq >/dev/null; then
  _v() { jq -r "$1 // empty" "$_cfg" 2>/dev/null; }
  _t="$(_v '.tracker.bot.app.clientId')";           [[ -n "$_t" ]] && CLIENT_ID="$_t"
  _t="$(_v '.tracker.bot.app.installationId')";      [[ -n "$_t" ]] && INSTALLATION_ID="$_t"
  _t="$(_v '.tracker.bot.app.appName')";             [[ -n "$_t" ]] && APP_NAME="$_t"
  _t="$(_v '.tracker.bot.app.privateKeyFilename')";  [[ -n "$_t" ]] && KEY_FILENAME="$_t"
  _t="$(_v '.tracker.bot.wrapperPath')";             [[ -n "$_t" ]] && WRAPPER_OVERRIDE="${_t/#\~/$HOME}"
fi

CONFIG_DIR="$HOME/.config/$REPO_BASENAME"
KEY_DEST="$CONFIG_DIR/$KEY_FILENAME"
# tracker.bot.wrapperPath, when set, relocates the wrapper AND its config dir so
# install (writer) and claim-issue.sh (reader) agree on the same explicit path —
# the derivation that was wrong once (canary catch). KEY_DEST stays beside the wrapper.
if [[ -n "$WRAPPER_OVERRIDE" ]]; then
  WRAPPER="$WRAPPER_OVERRIDE"
  CONFIG_DIR="$(dirname "$WRAPPER")"
  KEY_DEST="$CONFIG_DIR/$KEY_FILENAME"
else
  WRAPPER="$CONFIG_DIR/gh-as-bot.sh"
fi

KEY_SRC=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --client-id) CLIENT_ID="$2"; shift 2 ;;
    --installation-id) INSTALLATION_ID="$2"; shift 2 ;;
    -h|--help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "[install-gh-bot] unknown option: $1" >&2; exit 2 ;;
    *)
      [[ -n "$KEY_SRC" ]] && { echo "[install-gh-bot] unexpected extra argument: $1" >&2; exit 2; }
      KEY_SRC="$1"; shift ;;
  esac
done

for dep in gh jq openssl curl; do
  command -v "$dep" >/dev/null || { echo "[install-gh-bot] missing dependency: $dep" >&2; exit 2; }
done

# ---------------------------------------------------------------- key install --

if [[ -z "$KEY_SRC" ]]; then
  [[ -f "$KEY_DEST" ]] || {
    echo "[install-gh-bot] no key argument and no key at $KEY_DEST" >&2
    echo "[install-gh-bot] download one from https://github.com/settings/apps/$APP_NAME and pass its path" >&2
    exit 2
  }
  echo "[install-gh-bot] using already-installed key at $KEY_DEST"
else
  [[ -f "$KEY_SRC" ]] || { echo "[install-gh-bot] key file not found: $KEY_SRC" >&2; exit 2; }
  openssl rsa -in "$KEY_SRC" -check -noout >/dev/null 2>&1 \
    || { echo "[install-gh-bot] $KEY_SRC is not a valid RSA private key" >&2; exit 2; }
  mkdir -p "$CONFIG_DIR"
  if [[ "$(cd "$(dirname "$KEY_SRC")" && pwd)/$(basename "$KEY_SRC")" != "$KEY_DEST" ]]; then
    mv "$KEY_SRC" "$KEY_DEST"
  fi
  chmod 600 "$KEY_DEST"
  echo "[install-gh-bot] key installed at $KEY_DEST (mode 600)"
fi

# ------------------------------------------------------- installation discovery --

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

mint_jwt() {
  local now header payload sig
  now=$(date +%s)
  header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
  payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "$((now - 60))" "$((now + 540))" "$CLIENT_ID" | b64url)
  sig=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign "$KEY_DEST" -binary | b64url)
  printf '%s.%s.%s' "$header" "$payload" "$sig"
}

if [[ -z "$INSTALLATION_ID" ]]; then
  echo "[install-gh-bot] discovering installation ID via GitHub API..."
  jwt=$(mint_jwt)
  installations=$(curl -sf \
    -H "Authorization: Bearer $jwt" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    https://api.github.com/app/installations) \
    || { echo "[install-gh-bot] JWT auth failed — wrong key or client ID?" >&2; exit 1; }
  count=$(jq 'length' <<<"$installations")
  if [[ "$count" -ne 1 ]]; then
    echo "[install-gh-bot] expected exactly 1 installation, found $count:" >&2
    jq -r '.[] | "  id=\(.id) account=\(.account.login)"' <<<"$installations" >&2
    echo "[install-gh-bot] re-run with --installation-id <id>" >&2
    exit 1
  fi
  INSTALLATION_ID=$(jq -r '.[0].id' <<<"$installations")
  echo "[install-gh-bot] installation ID: $INSTALLATION_ID ($(jq -r '.[0].account.login' <<<"$installations"))"
fi

# ---------------------------------------------------------------- wrapper write --

cat > "$WRAPPER" <<WRAPPER_EOF
#!/usr/bin/env bash
# gh-as-bot.sh — run gh as ${APP_NAME}[bot] (GitHub App installation token).
# Used by the dev-pipeline / pr-revision skills for all GitHub write operations.
# Generated by install-gh-bot.sh — re-run that script to regenerate; do not hand-edit.
#
# App: https://github.com/apps/$APP_NAME
# Client ID used as JWT issuer (GitHub-recommended over numeric App ID).
set -euo pipefail

CLIENT_ID="$CLIENT_ID"
INSTALLATION_ID="$INSTALLATION_ID"
KEY="$KEY_DEST"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

now=\$(date +%s)
header=\$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)
payload=\$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' "\$((now - 60))" "\$((now + 540))" "\$CLIENT_ID" | b64url)
sig=\$(printf '%s.%s' "\$header" "\$payload" | openssl dgst -sha256 -sign "\$KEY" -binary | b64url)
jwt="\$header.\$payload.\$sig"

token=\$(curl -sf -X POST \\
  -H "Authorization: Bearer \$jwt" \\
  -H "Accept: application/vnd.github+json" \\
  -H "X-GitHub-Api-Version: 2022-11-28" \\
  "https://api.github.com/app/installations/\$INSTALLATION_ID/access_tokens" \\
  | jq -r .token)

if [[ -z "\$token" || "\$token" == "null" ]]; then
  echo "[gh-as-bot] failed to mint installation token" >&2
  exit 1
fi

GH_TOKEN="\$token" exec gh "\$@"
WRAPPER_EOF
chmod +x "$WRAPPER"
echo "[install-gh-bot] wrapper written to $WRAPPER"

# ------------------------------------------------------------------ smoke test --

echo "[install-gh-bot] smoke test: listing repos accessible to the installation..."
repos=$("$WRAPPER" api /installation/repositories --jq '[.repositories[].full_name] | join(", ")') \
  || { echo "[install-gh-bot] smoke test FAILED — wrapper could not authenticate" >&2; exit 1; }
echo "[install-gh-bot] OK — bot has access to: $repos"
echo "[install-gh-bot] done. The dev-pipeline Bot Identity prerequisite is satisfied."
