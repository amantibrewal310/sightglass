# Design notes

Why the line is built the way it is. None of this is needed to use it — see the
[README](README.md) for that.

## The line must never change width

A status line that jitters is worse than none, because you stop reading it. Everything
below follows from that.

### Pad by codepoints, not bytes

Shell `printf` counts bytes. `%-24s` against a string holding `·` (2 bytes) or `…`
(3 bytes) pads two or three columns short, and every field after it slides.

So all formatting happens inside the single `jq` call the script already spawns — `jq`'s
`length` counts codepoints. This is the reason the script looks like a jq program wrapped
in four lines of bash rather than the other way round.

A related trap: bash treats tab as IFS-whitespace, so `IFS=$'\t' read -r a b c` collapses
runs of empty fields and shifts every later value into the wrong variable. An early
version split jq's `@tsv` output that way and rendered a phantom `spend 1%` segment built
from the cache value. Split on `\x1f` if you ever need this.

### Every glyph must be one cell wide

Unicode assigns each character an East Asian Width. Neutral and Narrow always occupy one
terminal cell; Wide always takes two; Ambiguous takes two under a CJK locale and one
otherwise.

| Glyph | Codepoint | Width | |
| --- | --- | --- | --- |
| `▰ ▱` | U+25B0, U+25B1 | Neutral | One cell everywhere. What the bar uses. |
| `█ ░` | U+2588, U+2591 | Ambiguous | Two cells under a CJK locale — a ten-column shear. |
| `━ ─` | U+2501, U+2500 | Ambiguous | Same hazard. |
| `⚡` | U+26A1 | Wide | Always two cells. This was the original bug. |

The first build used `⚡` as the cache marker. Ghostty draws it in two cells — correctly,
since U+26A1 has Emoji_Presentation — which knocked everything after it one column right.
`grapheme-width-method = legacy` would have drawn it in one, so the bug was invisible on
some setups and not others. Hence ASCII `cache`.

`·` and `…` are also Ambiguous and are still in use. `·` appears identically in every row
so it cannot shear anything relative to anything else; `…` sits inside a padded field, so
a CJK-locale user would see that one field run a column wide. Fixable by swapping it for
`..`, at the cost of looking worse for everyone else.

### Nothing may be conditional

A field that appears only sometimes forces a choice between reserving its columns —
leaving a hole whenever it is absent — and letting every field after it jump when it
shows up. Both are worse than always drawing it.

This bit twice. The reset countdown first rendered only past 60% and had to pick one of
those two failures; it is now unconditional. Then the *segments themselves* turned out to
be conditional on the payload carrying them: `rate_limits` rides on API response headers,
so it is missing at session start and after a window resets, and `prompt_cache` is missing
until the first request. The whole tail of the line vanished and reappeared. They are now
drawn either way, showing `-` until the numbers arrive.

### Watch the rounding at field boundaries

Token counts are abbreviated to six characters. The switch to megatokens happens at
999,500 rather than 1,000,000, because 999,999 divided into thousands rounds to `1000.0k`
— seven characters, which pushes every later column right by one. It shows up only in the
last five hundred tokens before the boundary.

## The update check

It runs at most once a day, detached, so the status line never waits on the network — a
render with the update URL pointed at a black hole still returns in 0.05s. The stamp file
is touched *before* the check is spawned, so a burst of turns cannot start a burst of
curls.

`auto` replaces the file with `mv`, never by truncating in place: bash reads a script
incrementally as it executes, so overwriting the bytes of a running script can corrupt the
run. A rename swaps the directory entry and leaves any running copy holding the old inode.
The download is checked for the right shebang, a plausible version string, and `bash -n`
before it is allowed to become the script.

`auto` is off by default. It is a supply-chain decision — a compromise of this repo would
reach every machine running it within a day, executing every turn — and it belongs to
whoever installs it.

## Things about Claude Code worth knowing

Observed against 2.1.272 by reading the binary; none of it is documented, so re-check
before relying on it.

**`padding` in `settings.json` is horizontal.** It lands as `paddingX` on the renderer's
box. There is no vertical equivalent, which is why `GAP_BELOW` works by appending a
newline: the renderer splits the command's output on newlines and draws a column, and its
telemetry counts `line_count`, so multi-line output is expected rather than tolerated.

**A plugin cannot set a status line.** The plugin manifest accepts a `settings` key and
`settings.statusLine` passes even `claude plugin validate --strict` — the schema is
`record(string, any)`, so validation proves nothing. Its description says only allowlisted
keys are applied, and the binary carries the filter:

```
["apiKeyHelper","awsAuthRefresh","awsCredentialExport","fileSuggestion",
 "gcpAuthRefresh","otelHeadersHelper","processWrapper","policyHelpers",
 "proxyAuthHelper","statusLine","subagentStatusLine"]
```

Every entry is a setting that executes a command. Sensible: otherwise installing any
plugin would silently earn it a shell command on every turn. So the plugin here ships the
script and a command that wires it up, rather than wiring itself up.

**ANSI escapes are written as `\u001b`, not literal ESC bytes.** A script carrying literal
ESC works fine locally and arrives colourless after any trip through a web page or a chat
client, which strip them silently. `jq` parses the escape form itself, so the published
file is entirely printable characters.
