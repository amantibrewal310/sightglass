---
description: Wire the Sightglass status line into your Claude Code settings
---

Install or update the Sightglass status line for this user. Re-running this is the
supported way to pick up a new version.

1. Read `${CLAUDE_PLUGIN_ROOT}/sightglass.sh`.
2. Copy it to `~/.claude/sightglass.sh` and `chmod +x` it.
3. Read `~/.claude/settings.json`. If a `statusLine` key already exists, show the
   user what it is and ask before replacing it. Otherwise add this key, leaving
   every other key in the file untouched:

   ```json
   "statusLine": {
     "type": "command",
     "command": "bash ~/.claude/sightglass.sh",
     "padding": 0
   }
   ```

4. Verify the file is still valid JSON, then tell the user it takes effect in the
   next session. The script needs `bash` and `jq` — check `jq` is on PATH and say
   so plainly if it is not.
