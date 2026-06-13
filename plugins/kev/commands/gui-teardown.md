---
allowed-tools: Bash(bash ~/.claude/plugins/marketplaces/kevdunn/plugins/kev/scripts/kev-gui-teardown.sh:*)
description: Tear down the VS Code GUI instance this Remote Control session runs in
---

Tear down **only the VS Code window** that this Claude Code session is running
inside — the one opened by `code-gui.sh` and driven over Remote Control — and
release the caffeinate assertion keeping the Mac awake (only if no other VS Code
windows remain).

This only makes sense when the session is hosted in VS Code on a Mac desktop
(the code-gui.sh flow). Closing the hosting window ends this very session, so it
is the last thing that happens.

How it targets just this window:

- **Isolated instance** (repos opened by the current `code-gui.sh`, which gives
  each repo its own VS Code instance): the script walks its own process
  ancestry up to this instance's main process and quits just it — other repos'
  windows are untouched. No Accessibility permission needed.
- **Shared instance** (older windows that share one VS Code process): it closes
  just this window by title via Accessibility (System Events), leaving sibling
  windows running. Requires VS Code to have Accessibility access (System
  Settings → Privacy & Security → Accessibility). A window with unsaved files
  may show a save prompt.
- If the hosting instance can't be pinpointed, it falls back to quitting VS Code
  app-wide.

Run exactly this, then stop:

```bash
bash ~/.claude/plugins/marketplaces/kevdunn/plugins/kev/scripts/kev-gui-teardown.sh
```

The script schedules the teardown a few seconds out in a detached process (so
this reply reaches the user before VS Code and the session quit). After it
returns, tell the user the teardown is scheduled and the session will end
momentarily, then do **not** run any further commands.

To change the delay, the user can prefix the command with `TEARDOWN_DELAY=<secs>`
(default 5).
