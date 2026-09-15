#!/usr/bin/env bash
# Sightglass installer. Safe to re-run; that is also how you update.
#
#   curl -fsSL https://raw.githubusercontent.com/amantibrewal310/sightglass/main/install.sh | bash
#
# Env:
#   SIGHTGLASS_REF    git ref to install from (default: main)
#   SIGHTGLASS_FORCE  1 to replace an existing statusLine without asking
#   CLAUDE_CONFIG_DIR Claude Code config dir (default: ~/.claude)
set -eu

REPO=amantibrewal310/sightglass
REF=${SIGHTGLASS_REF:-main}
DIR=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
SCRIPT=$DIR/sightglass.sh
SETTINGS=$DIR/settings.json
URL=https://raw.githubusercontent.com/$REPO/$REF/sightglass.sh

b=$(printf '\033[1m'); dim=$(printf '\033[2m'); grn=$(printf '\033[32m')
red=$(printf '\033[31m'); yel=$(printf '\033[33m'); rst=$(printf '\033[0m')
say()  { printf '%s\n' "$*"; }
ok()   { printf '%s  ok%s  %s\n' "$grn" "$rst" "$*"; }
warn() { printf '%s warn%s %s\n' "$yel" "$rst" "$*"; }
die()  { printf '%s fail%s %s\n' "$red" "$rst" "$*" >&2; exit 1; }

if [ "${1:-}" = "--uninstall" ]; then
  [ -f "$SETTINGS" ] && {
    cp "$SETTINGS" "$SETTINGS.bak"
    jq 'del(.statusLine)' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
    ok "removed statusLine from $SETTINGS ${dim}(backup: $SETTINGS.bak)$rst"
  }
  rm -f "$SCRIPT" && ok "removed $SCRIPT"
  say ""; say "Gone. Takes effect in your next session."
  exit 0
fi

say ""
say "${b}Sightglass${rst} ${dim}· an always-on status line for Claude Code${rst}"
say ""

command -v jq >/dev/null 2>&1 || die "jq is required.
       macOS:  brew install jq
       Debian: sudo apt install jq
       Then re-run this installer."
command -v curl >/dev/null 2>&1 || die "curl is required."
[ -d "$DIR" ] || die "$DIR does not exist. Run Claude Code once first."

if [ -f "$SETTINGS" ] && ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
  die "$SETTINGS is not valid JSON. Fix it and re-run; nothing has been changed."
fi

tmp=$(mktemp)
trap 'rm -f "$tmp" "$tmp.settings"' EXIT
curl -fsSL "$URL" -o "$tmp" || die "could not download $URL"
[ -s "$tmp" ] || die "downloaded an empty file from $URL"
head -1 "$tmp" | grep -q '^#!/usr/bin/env bash' || die "$URL did not look like the script"

mv "$tmp" "$SCRIPT"
chmod +x "$SCRIPT"
trap 'rm -f "$tmp.settings"' EXIT
ok "installed $SCRIPT ${dim}($("$SCRIPT" --version))$rst"

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

existing=$(jq -r '.statusLine.command // empty' "$SETTINGS")
want="bash $SCRIPT"
if [ -n "$existing" ] && [ "$existing" != "$want" ]; then
  warn "you already have a status line:"
  say  "      ${dim}$existing${rst}"
  if [ "${SIGHTGLASS_FORCE:-}" = "1" ]; then
    say "      ${dim}SIGHTGLASS_FORCE=1 — replacing it${rst}"
  elif [ -r /dev/tty ]; then
    printf '      replace it? [y/N] '
    read -r reply < /dev/tty 2>/dev/null || { reply=n; printf '\n'; }
    case "$reply" in [yY]*) ;; *) say ""; say "Left it alone. $SCRIPT is installed if you want to wire it up by hand."; exit 0 ;; esac
  else
    say ""
    die "not replacing it without confirmation. Re-run with SIGHTGLASS_FORCE=1 to overwrite."
  fi
fi

cp "$SETTINGS" "$SETTINGS.bak"
jq --arg cmd "$want" \
   '.statusLine = {type: "command", command: $cmd, padding: 0}' \
   "$SETTINGS" > "$tmp.settings"
jq -e . "$tmp.settings" >/dev/null || die "refusing to write invalid JSON; $SETTINGS untouched."
mv "$tmp.settings" "$SETTINGS"
ok "wired into $SETTINGS ${dim}(backup: $SETTINGS.bak)$rst"

say ""
say "  ${dim}$(printf '{"model":{"display_name":"Opus 5 (1M context)"},"workspace":{"current_dir":"%s"},"context_window":{"total_input_tokens":320600,"context_window_size":1000000,"used_percentage":32},"cost":{"total_cost_usd":23.34}}' "$PWD" | GAP_BELOW=0 bash "$SCRIPT")${rst}"
say ""
say "Done. It appears in your next session."
say "${dim}Uninstall: curl -fsSL https://raw.githubusercontent.com/$REPO/$REF/install.sh | bash -s -- --uninstall${rst}"
