# Sightglass

> **sightglass** — the transparent tube on a vessel through which the fill level is read
> at a glance.

An always-on status line for Claude Code. The built-in context indicator only appears
once you are nearly out of room; this keeps it on screen, with tokens, rate limits and
prompt-cache hit rate, in columns that never move.

```
Opus 5 1M    · ~/src/parser         ▰▰▰▱▱▱▱▱▱▱  32% 320.6k/1.00M  ·   $23.34 · 5h   4% in 2h29m  · 7d  90% in 1d13h  · cache  98%
Sonnet 5     · /tmp                 ▱▱▱▱▱▱▱▱▱▱   3%   5.0k/200.0k ·    $0.50 · 5h 100% in 0m     · 7d   7% in 5d18h  · cache  40%
Haiku 4.5    · ~/src/hub-ui         ▰▰▰▰▰▰▰▰▰▰ 100%  1.00M/1.00M  · $1234.56 · 5h  61% in 59m    · 7d  30% in 1d14h  · cache   7%
```

Needs `bash` and `jq`. No Node, no plugin, one subprocess per refresh.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/amantibrewal310/sightglass/main/install.sh | bash
```

That is the whole thing. It checks for `jq`, drops the script in `~/.claude`, and adds
the `statusLine` key to `settings.json` without touching anything else — backing the file
up first, and asking before replacing a status line you already have. Re-run it to update.

It appears in your next session.

<details>
<summary>Rather not pipe a URL into bash</summary>

Read it first — it is 80 lines: [`install.sh`](install.sh). Or do it by hand:

```sh
curl -fsSL https://raw.githubusercontent.com/amantibrewal310/sightglass/main/sightglass.sh \
  -o ~/.claude/sightglass.sh
chmod +x ~/.claude/sightglass.sh
```

Then add to `~/.claude/settings.json`, keeping everything else in the file:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/sightglass.sh",
    "padding": 0
  }
}
```
</details>

<details>
<summary>As a plugin</summary>

```
/plugin marketplace add amantibrewal310/sightglass
/plugin install sightglass@sightglass
/sightglass:install
```

The plugin bundles the script and a command that wires it up. It cannot set the status
line by itself — `statusLine` is on Claude Code's denylist for plugin-contributed
settings, along with every other setting that executes a command.
</details>

## Reading it

- `Opus 5 1M` — model, with `(1M context)` shortened
- `~/src/parser` — working directory, elided from the left at a `/`
- `▰▰▰▱▱▱▱▱▱▱  32%` — context used; green under 60%, amber to 79, red at 80+
- `320.6k/1.00M` — tokens against the window
- `$23.34` — session cost
- `5h   4% in 2h29m` — five-hour limit and when it resets
- `7d  90% in 1d13h` — seven-day limit; `spend` also appears on gateway accounts
- `cache  98%` — prompt-cache hit rate, cyan when the cache is warm

Rate-limit segments show `-` until the numbers arrive: they ride on API response headers,
so they are missing at session start, after a window resets, and always on a raw API key.
Every field is fixed width, so nothing moves when a number grows or a segment has no data.

## Options

Set in the environment, or edit the defaults at the top of the script.

| | Default | |
| --- | --- | --- |
| `MODEL_W` | `12` | Columns for the model name |
| `DIR_W` | `20` | Columns for the directory |
| `BAR_CELLS` | `10` | Bar length |
| `BAR_FILL` / `BAR_EMPTY` | `▰` `▱` | Bar glyphs — keep any replacement East-Asian-width Neutral |
| `SHOW_LIMITS` | `1` | `0` drops the rate-limit segments |
| `SHOW_CACHE` | `1` | `0` drops the cache segment |
| `GAP_ABOVE` / `GAP_BELOW` | `0` `1` | Blank lines around the line. `padding` in settings.json is horizontal only |

The line is 129 columns. `MODEL_W=10 DIR_W=14` brings it to ~119.

## Updating

Re-run the installer; it overwrites in place.

```sh
curl -fsSL https://raw.githubusercontent.com/amantibrewal310/sightglass/main/install.sh | bash
bash ~/.claude/sightglass.sh --version
```

For the plugin, `/plugin update sightglass` then `/sightglass:install` — your status line
runs the copy in `~/.claude`, not the plugin's.

## Uninstall

```sh
curl -fsSL https://raw.githubusercontent.com/amantibrewal310/sightglass/main/install.sh | bash -s -- --uninstall
```

## Notes

Why every glyph is one cell wide, why the padding happens inside `jq`, and the rest of
the reasoning: **https://claude.ai/artifact/GAiCaBcVFyorjgBvebz3fi**

Built against Claude Code 2.1.272. Runs on the bash 3.2 that ships with macOS.

## License

CC0 1.0 — public domain.
