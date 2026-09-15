#!/usr/bin/env bash
# Always-on context / token / rate-limit / cache status line for Claude Code.
# Reads the status line JSON payload on stdin.
#
# https://github.com/amantibrewal310/sightglass
#
# All rendering happens inside jq on purpose: bash printf pads by BYTES, so any
# field holding a multi-byte glyph would be mis-padded. jq's `length` counts
# codepoints, which is what actually lines the columns up.
#
SIGHTGLASS_VERSION=1.3.0
if [ "${1:-}" = "--version" ]; then echo "sightglass $SIGHTGLASS_VERSION"; exit 0; fi

# Column widths - tune these two if the line is too wide for your terminal.
MODEL_W=12
DIR_W=20

# Bar glyphs. U+25B0/U+25B1 are East-Asian-width "Neutral", i.e. exactly one
# cell in every terminal. Block elements (U+2588) and box drawing (U+2501) are
# "Ambiguous" and render double-width under a CJK locale, which would shear the
# whole layout. Keep any replacement Neutral.
BAR_FILL=${BAR_FILL:-$'▰'}
BAR_EMPTY=${BAR_EMPTY:-$'▱'}
BAR_CELLS=${BAR_CELLS:-10}

# Blank lines above/below the line. The renderer splits the command output on
# newlines and draws a column, so this is the only way to get vertical space:
# `padding` in settings.json maps to paddingX, which is horizontal only.
# Set to 0 to drop these segments entirely. Rate limits are absent from the
# payload on raw API keys, and `cache` on a session that has made no request.
SHOW_LIMITS=${SHOW_LIMITS:-1}
SHOW_CACHE=${SHOW_CACHE:-1}

# Update checking. "notify" shows a marker when a newer version exists; "auto"
# also replaces this file with it; "off" never touches the network.
#
# "auto" means this repo can put code on your machine that runs every turn.
# That is why it is not the default - it is a supply-chain decision, and it
# should be yours. "notify" costs one request a day and changes nothing.
UPDATE_CHECK=${UPDATE_CHECK:-notify}
UPDATE_INTERVAL=${UPDATE_INTERVAL:-86400}
UPDATE_URL=${UPDATE_URL:-https://raw.githubusercontent.com/amantibrewal310/sightglass/main/sightglass.sh}

GAP_ABOVE=${GAP_ABOVE:-0}
GAP_BELOW=${GAP_BELOW:-1}

SELF=$0
STATE=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
STAMP=$STATE/.sightglass-checked
LATEST=$STATE/.sightglass-latest

# a > b, comparing dotted numeric versions; prints "y" or nothing
newer() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    na = split(a, x, "."); nb = split(b, y, ".")
    n = na > nb ? na : nb
    for (i = 1; i <= n; i++) {
      if (x[i] + 0 > y[i] + 0) { print "y"; exit }
      if (x[i] + 0 < y[i] + 0) { exit }
    }
  }'
}

# Runs detached so the status line never waits on the network.
check_for_update() {
  tmp=$(mktemp "$SELF.XXXXXX") || return 0
  if ! curl -fsSL --max-time 10 "$UPDATE_URL" -o "$tmp" 2>/dev/null; then rm -f "$tmp"; return 0; fi
  head -1 "$tmp" | grep -q '^#!/usr/bin/env bash' || { rm -f "$tmp"; return 0; }
  v=$(sed -n 's/^SIGHTGLASS_VERSION=//p' "$tmp" | head -1)
  case $v in ''|*[!0-9.]*) rm -f "$tmp"; return 0 ;; esac
  printf '%s' "$v" > "$LATEST" 2>/dev/null || true
  if [ "$UPDATE_CHECK" = auto ] && [ "$(newer "$v" "$SIGHTGLASS_VERSION")" = y ] && bash -n "$tmp" 2>/dev/null; then
    chmod +x "$tmp"
    mv "$tmp" "$SELF"            # rename, not truncate: a running copy keeps its inode
    return 0
  fi
  rm -f "$tmp"
}

upd=""
if [ "$UPDATE_CHECK" != off ] && [ -d "$STATE" ]; then
  [ -f "$LATEST" ] && upd=$(cat "$LATEST" 2>/dev/null)
  if [ ! -f "$STAMP" ] || [ -n "$(find "$STAMP" -mmin +$((UPDATE_INTERVAL / 60)) 2>/dev/null)" ]; then
    : > "$STAMP" 2>/dev/null || true   # stamp first, so every turn does not spawn a check
    ( check_for_update >/dev/null 2>&1 & ) >/dev/null 2>&1
  fi
  [ -n "$upd" ] && [ "$(newer "$upd" "$SIGHTGLASS_VERSION")" = y ] || upd=""
fi

out=$(jq -j --argjson mw "$MODEL_W" --argjson dw "$DIR_W" \
          --arg fill "$BAR_FILL" --arg empty "$BAR_EMPTY" --argjson cells "$BAR_CELLS" \
          --argjson lim "$SHOW_LIMITS" --argjson cache "$SHOW_CACHE" \
          --arg upd "$upd" '
  # ---- padding / truncation helpers (codepoint-based) ----
  def spaces($n): if $n > 0 then " " * $n else "" end;
  def rpad($w): . + spaces($w - length);
  def lpad($w): spaces($w - length) + .;
  def trunc($w): if length > $w then .[:$w-1] + "…" else . end;
  # Elide a path from the left, cutting at a "/" so components stay whole.
  def elide($w):
    if length <= $w then .
    else .[(length-$w+1):] as $tail
      | ($tail | index("/")) as $i
      | "…" + (if $i == null then $tail else $tail[$i:] end)
    end;

  # ---- fixed-decimal formatting (jq has no printf) ----
  def zeros($n): if $n > 0 then "0" * $n else "" end;
  def fixed($d):
    (. * pow(10; $d) | round | tostring) as $s
    | ($s | length) as $L
    | if $d == 0 then $s
      elif $L <= $d then "0." + zeros($d - $L) + $s
      else $s[:$L-$d] + "." + $s[$L-$d:] end;
  # Caps at 6 chars. The M cutoff is 999500, not 1000000: at 999999 the k branch
  # would round to "1000.0k" (7 chars) and shove every later column right by one.
  def fmttok:
    if . >= 999500 then (. / 1000000 | fixed(2)) + "M"
    elif . >= 1000 then (. / 1000    | fixed(1)) + "k"
    else (floor | tostring) end;

  # ---- countdown to a reset timestamp (epoch SECONDS) ----
  def countdown($t):
    ($t - now) as $d
    | if $d <= 0 then "now"
      else ($d / 3600 | floor) as $h
         | (($d % 3600) / 60 | floor) as $m
         | if $h >= 24 then "\($h / 24 | floor)d\($h % 24)h"
           elif $h > 0 then "\($h)h" + (if $m < 10 then "0" else "" end) + "\($m)m"
           else "\($m)m" end
      end;

  # ---- colors ----
  def red: "\u001b[31m"; def yel: "\u001b[33m"; def grn: "\u001b[32m";
  def cyn: "\u001b[36m"; def dim: "\u001b[2m";  def rst: "\u001b[0m";
  def sep: " " + dim + "·" + rst + " ";
  def heat($p): if $p >= 80 then red elif $p >= 60 then yel else grn end;

  # ---- one rate-limit segment, always the same width ----
  #      Drawn even when the payload omits the window: rate_limits comes and
  #      goes (it rides on response headers), and a segment that disappears
  #      drags everything after it left.
  #      The countdown is unconditional. Showing it only past some threshold
  #      means either reserving its columns (a hole while quiet) or letting
  #      everything after it jump when the threshold is crossed. Always-on
  #      costs a few columns and is the only option that does neither.
  def limit($label; $raw; $reset):
    if $raw == null then
      sep + dim + $label + " " + ("-" | lpad(4)) + " in " + ("-" | rpad(6)) + rst
    else ([[$raw, 0] | max, 100] | min | round) as $p
      | (($p | tostring) + "%" | lpad(4)) as $ptxt
      | (if $reset == null then " " + dim + "in " + ("-" | rpad(6)) + rst
         else " " + dim + "in " + (countdown($reset) | rpad(6)) + rst end) as $rtxt
      | sep + heat($p) + $label + " " + $ptxt + rst + $rtxt
    end;

  # ---- gather ----
  (.model.display_name // "?" | sub(" \\(1M context\\)$"; " 1M") | trunc($mw) | rpad($mw)) as $model
  | (.workspace.current_dir // ""
     | (if startswith(env.HOME) then "~" + .[(env.HOME | length):] else . end)
     | elide($dw) | rpad($dw)) as $dir
  | (.context_window.total_input_tokens  // 0) as $used
  | (.context_window.context_window_size // 0) as $win
  | ([[(.context_window.used_percentage // 0), 0] | max, 100] | min | round) as $pct
  | (.cost.total_cost_usd // 0) as $cost
  | ([$pct * $cells / 100 | floor, $cells] | min) as $nfill

  # ---- render ----
  | dim + $model + " " + "·" + " " + $dir + rst
  + " " + heat($pct)
  + (if $nfill > 0 then $fill * $nfill else "" end)
  + (if $cells - $nfill > 0 then $empty * ($cells - $nfill) else "" end)
  + " " + (($pct | tostring) + "%" | lpad(4)) + rst
  + " " + dim + ($used | fmttok | lpad(6)) + "/" + ($win | fmttok | rpad(6)) + rst
  + sep + dim + (("$" + ($cost | fixed(2))) | lpad(8)) + rst
  + (if $lim == 0 then "" else
       limit("5h"; .rate_limits.five_hour.used_percentage; .rate_limits.five_hour.resets_at)
     + limit("7d"; .rate_limits.seven_day.used_percentage; .rate_limits.seven_day.resets_at)
     + (if .rate_limits.spend_limit == null then ""
        else limit("spend"; .rate_limits.spend_limit.used_percentage; .rate_limits.spend_limit.resets_at)
        end)
     end)
  + (if $cache == 0 then "" else
       sep + dim + "cache" + rst + " "
     + (if (.prompt_cache.hit_ratio // null) == null then dim + ("-" | lpad(4)) + rst
        else (.prompt_cache.hit_ratio * 100 | round) as $h
          | (if .prompt_cache.warm then cyn else dim end) + (($h | tostring) + "%" | lpad(4)) + rst
        end)
     end)
  + (if $upd == "" then "" else sep + yel + "update " + $upd + rst end)
' 2>/dev/null) || out=""

blanks() { i=0; while [ "$i" -lt "${1:-0}" ]; do printf '\n'; i=$((i + 1)); done; }

blanks "$GAP_ABOVE"
printf '%s' "$out"
blanks "$GAP_BELOW"
