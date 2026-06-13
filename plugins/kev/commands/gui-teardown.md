---
allowed-tools: Bash(bash ~/.claude/plugins/marketplaces/kevdunn/plugins/kev/scripts/kev-gui-teardown.sh:*)
description: Tear down the VS Code GUI instance this Remote Control session runs in
---

Tear down the VS Code GUI instance that this Claude Code session is running
inside — the one opened by `code-gui.sh` and driven over Remote Control — and
release the caffeinate assertion keeping the Mac awake.

This only makes sense when the session is hosted in VS Code on a Mac desktop
(the code-gui.sh flow). Quitting VS Code ends this very session, so it is the
last thing that happens.

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
