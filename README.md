# Sightglass

> **sightglass** — the transparent tube on a vessel through which the fill level is read
> at a glance.

Claude Code hides its context indicator until you are nearly out of room. This puts the
number on screen permanently — alongside tokens, rate limits and prompt-cache hit rate —
in columns that do not move.

```
Opus 5 1M      · ~/Work/Experiments       ▰▱▱▱▱▱▱▱▱▱  14% 140.5k/1.00M  ·    $5.83 · 5h  78% in 3h09m  · 7d  88% in 1d19h  · cache  97%
Sonnet 5       · /tmp                     ▱▱▱▱▱▱▱▱▱▱   3%   5.0k/200.0k ·    $0.00
Haiku 4.5      · ~/src/hub-ui             ▰▰▰▰▰▰▰▰▰▰ 100%  1.00M/1.00M  · $1234.56 · 5h 100% in 0m     · 7d   5%           · cache   7%
Opus 4.8 1M    · ~/src/parser             ▰▰▰▰▱▱▱▱▱▱  42% 420.0k/1.00M  ·   $88.40 · 5h  61% in 59m    · 7d  30%           · spend  95% in 2d23h  · cache  83%
```

Four sessions with nothing in common — different models, paths, windows, costs, limits.
Every column lands in the same cell.

## Install

Needs `bash` and `jq`. Nothing else: no Node, no plugin, one subprocess per refresh.

### Let Claude Code do it

Paste this into any Claude Code session:

```text
Install the Sightglass status line for Claude Code.

1. Download https://raw.githubusercontent.com/amantibrewal310/sightglass/main/sightglass.sh
   to ~/.claude/sightglass.sh and make it executable.
2. Read ~/.claude/settings.json. If it already has a "statusLine" key, show me what it is
   and ask before replacing it. Otherwise add this key, leaving every other key untouched:
   {"statusLine": {"type": "command", "command": "bash ~/.claude/sightglass.sh", "padding": 0}}
3. Confirm the file is still valid JSON, check that jq is on my PATH, and tell me plainly
   if it is not. It takes effect in my next session.
```

### Or by hand

```sh
curl -fsSL https://raw.githubusercontent.com/amantibrewal310/sightglass/main/sightglass.sh \
  -o ~/.claude/sightglass.sh
chmod +x ~/.claude/sightglass.sh
```

Then add this to `~/.claude/settings.json`, keeping whatever else is already in the file:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/sightglass.sh",
    "padding": 0
  }
}
```

It takes effect in your next session.

### Or as a plugin

```
/plugin marketplace add amantibrewal310/sightglass
/plugin install sightglass@sightglass
/sightglass:install
```

The plugin bundles the script and a command that wires it up for you. It cannot set the
status line by itself — `statusLine` is on Claude Code's denylist for plugin-contributed
settings, along with every other setting that executes a command (`apiKeyHelper`,
`processWrapper`, `proxyAuthHelper` and friends). That is a sensible boundary: otherwise
installing any plugin would silently earn it a shell command on every turn. So the
plugin route still ends in an explicit, user-initiated write to your own settings file.

## Reading the line

Claude Code pipes a JSON payload to the status-line command on every turn. Each segment
names the field it reads, so you can drop any of them or add one the payload already
carries.

| Segment | Source field | Notes |
| --- | --- | --- |
| `Opus 5 1M` | `model.display_name` | `(1M context)` is shortened to `1M` to reclaim ten columns |
| `~/src/parser` | `workspace.current_dir` | Elided from the left at a `/`, so path components stay whole |
| `▰▰▰▰▱▱▱▱▱▱  42%` | `context_window.used_percentage` | Green below 60%, amber to 79, red at 80+ |
| `420.0k/1.00M` | `context_window.total_input_tokens` | Input plus cache-read and cache-write tokens |
| `$88.40` | `cost.total_cost_usd` | Right-aligned on the decimal point |
| `5h 61% in 59m` | `rate_limits.five_hour` | Countdown is unconditional, so the segment never changes width |
| `7d 30% in 1d14h` | `rate_limits.seven_day` | Same treatment. `spend` also appears on gateway accounts |
| `cache 83%` | `prompt_cache.hit_ratio` | Cyan when warm, grey when cold; hidden until the first request |

`rate_limits` rides on API response headers and is not always in the payload — it can be
missing at session start and after a window resets. The segments are therefore drawn
either way, showing `-` until the numbers arrive, so nothing downstream moves. On a raw
API key they never arrive at all; set `SHOW_LIMITS=0` to drop them.

## Tuning

Set these in the environment, or edit the defaults at the top of the script.

| Variable | Default | |
| --- | --- | --- |
| `MODEL_W` | `12` | Columns reserved for the model name |
| `DIR_W` | `20` | Columns reserved for the directory |
| `BAR_CELLS` | `10` | Bar length; `20` gives 5% resolution |
| `BAR_FILL` | `▰` | Filled cell — keep it East-Asian-width Neutral |
| `BAR_EMPTY` | `▱` | Empty cell |
| `SHOW_LIMITS` | `1` | Set `0` to drop the rate-limit segments |
| `SHOW_CACHE` | `1` | Set `0` to drop the cache segment |
| `GAP_ABOVE` | `0` | Blank lines above the line |
| `GAP_BELOW` | `1` | Blank lines below the line |

The line is 129 columns and stays there: every field is fixed width, so nothing
downstream moves when a number grows. `MODEL_W=10 DIR_W=14` brings it to ~119.

`padding` in `settings.json` is horizontal only — it maps to `paddingX` in the renderer.
For vertical breathing room use `GAP_BELOW`: the renderer splits the command output on
newlines and draws a column, so a trailing blank line is the only way to get it.

## Why the columns hold

A status line that jitters is worse than none — you stop reading it. Three things have to
be true, and two of them are easy to get wrong.

**Pad by codepoints, not bytes.** Shell `printf` counts bytes. `%-24s` against a string
holding `·` or `…` pads two or three columns short, and every field after it slides. All
formatting therefore happens inside the single `jq` call the script already spawns —
`jq`'s `length` counts codepoints.

**Every glyph must be one cell wide.** Unicode assigns each character an East Asian
Width. Neutral and Narrow always occupy one terminal cell; Wide always takes two;
Ambiguous takes two under a CJK locale and one otherwise.

| Glyph | Codepoint | Width | |
| --- | --- | --- | --- |
| `▰ ▱` | U+25B0 · U+25B1 | Neutral | Exactly one cell everywhere. What the bar uses. |
| `█ ░` | U+2588 · U+2591 | Ambiguous | Two cells under a CJK locale — a ten-column shear. |
| `━ ─` | U+2501 · U+2500 | Ambiguous | Same hazard. |
| `⚡` | U+26A1 | Wide | Always two cells. This was the original bug. |

**Nothing may be conditional.** A field that appears only sometimes forces a choice
between reserving its columns — leaving a hole whenever it is absent — and letting every
field after it jump when it shows up. Both are worse than just always drawing it, which
is why the rate-limit reset countdown is unconditional rather than appearing at some
threshold.

**Watch the rounding at field boundaries.** Token counts are abbreviated to six
characters. The switch to megatokens happens at 999,500 rather than 1,000,000, because
999,999 divided into thousands rounds to `1000.0k` — seven characters, which pushes every
later column right by one. It only shows up in the last five hundred tokens before the
boundary.

One more, invisible: the ANSI colors are written as `` escapes and let `jq` produce
the control bytes. A script with literal ESC bytes in it works fine locally and arrives
colorless after any trip through a web page or a chat client, which silently strip them.

## Updating

Check what you are running:

```sh
bash ~/.claude/sightglass.sh --version
```

Installed by hand or by prompt — re-run the same `curl`. It overwrites in place and
`settings.json` needs no change.

Installed as a plugin:

```
/plugin marketplace update sightglass
/plugin update sightglass
/sightglass:install
```

The third step is not redundant. The plugin ships the script, but your status line runs
the copy at `~/.claude/sightglass.sh`, so updating the plugin refreshes the bundled copy
and not yours. Pointing `settings.json` straight at the plugin directory would remove the
step, but that path carries the version number and would break on every update.

## Compatibility

Built against Claude Code 2.1.272 on macOS. The script avoids `mapfile` and other bash 4
builtins, so it runs on the bash 3.2 that ships with macOS.

## License

CC0 1.0 — public domain. Take it, change it, no attribution wanted.
