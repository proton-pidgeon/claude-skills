---
allowed-tools: Bash(bash ~/.claude/plugins/marketplaces/kevdunn/plugins/kev/scripts/kev-gui-teardown.sh:*), Bash(powershell -NoProfile -ExecutionPolicy Bypass -File ~/.claude/plugins/marketplaces/kevdunn/plugins/kev/scripts/kev-gui-teardown.ps1:*)
description: Tear down the VS Code GUI instance this Remote Control session runs in
---

Tear down **only the VS Code window/instance** that this Claude Code session is
running inside — the one opened by `code-gui.sh` (macOS) or `code-gui.ps1`
(Windows) and driven over Remote Control — and release the keep-awake assertion
(only if no other VS Code instance remains).

This only makes sense when the session is hosted in the VS Code GUI on a
logged-in desktop (the code-gui flow). Closing the hosting window ends this very
session, so it is the last thing that happens.

How it targets just this instance:

- **macOS** — each repo is opened as its own VS Code instance (own
  `--user-data-dir`). The script walks its own process ancestry up to this
  instance's main process and quits just it; other repos' windows are untouched.
  Legacy shared windows fall back to closing this window by title via
  Accessibility (System Settings → Privacy & Security → Accessibility), and an
  unresolvable case falls back to quitting VS Code app-wide.
- **Windows** — same isolation, but the instance is identified by its
  `--user-data-dir` path in the main `Code.exe` command line (ConPTY makes an
  ancestry walk unreliable). Legacy/shared windows fall back to closing the
  window by title, then to an app-wide quit.

**Pick the script for this platform**, run exactly it, then stop:

- macOS / Linux desktop:

  ```bash
  bash ~/.claude/plugins/marketplaces/kevdunn/plugins/kev/scripts/kev-gui-teardown.sh
  ```

- Windows:

  ```bash
  powershell -NoProfile -ExecutionPolicy Bypass -File ~/.claude/plugins/marketplaces/kevdunn/plugins/kev/scripts/kev-gui-teardown.ps1
  ```

The script schedules the teardown a few seconds out in a detached process (so
this reply reaches the user before VS Code and the session quit). After it
returns, tell the user the teardown is scheduled and the session will end
momentarily, then do **not** run any further commands.

To change the delay, the user can prefix the command with `TEARDOWN_DELAY=<secs>`
(default 5).
