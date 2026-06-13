#!/usr/bin/env bash
#
# kev-gui-teardown.sh — tear down the VS Code GUI instance that the current
# Claude Code session is running inside (as opened by code-gui.sh), from within
# that very session. Backs the /gui-teardown slash command.
#
# The Claude session runs in VS Code's integrated terminal, which is inside the
# logged-in Aqua session — so we can quit VS Code directly (no sudo / launchctl
# asuser bridge). But a synchronous quit would kill Claude mid-command before it
# could reply, so we spawn a DETACHED worker (orphaned to launchd, survives VS
# Code dying) that waits a few seconds first, letting Claude stream its reply to
# the user before the window — and this session — goes away.
#
# Self-contained: ships with the kev@kevdunn plugin, no repo checkout required.
#
# Tunable (env): TEARDOWN_DELAY — seconds to wait before quitting (default 5).

set -euo pipefail

uid="$(id -u)"
self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
delay="${TEARDOWN_DELAY:-5}"

# First invocation: schedule a detached worker and return immediately so the
# session can finish replying. The worker re-invokes us with --run.
if [[ "${1:-}" != "--run" ]]; then
  nohup sh -c "sleep $delay; exec \"$self\" --run" >/dev/null 2>&1 </dev/null &
  disown 2>/dev/null || true   # drop from the job table too, so VS Code closing
                               # the terminal can't take the worker down with it
  echo "VS Code teardown scheduled in ${delay}s (detached); this session ends then."
  exit 0
fi

# --- detached worker -------------------------------------------------------

# Release the desktop-awake assertion code-gui.sh started (best-effort).
pkill -U "$uid" -f 'caffeinate -dim -t' 2>/dev/null || true

# Quit VS Code: ask politely first (saves state), then force any survivors so a
# teardown never hangs on a dialog or a TCC-blocked Apple Event.
/usr/bin/osascript -e 'tell application "Visual Studio Code" to quit' >/dev/null 2>&1 || true

for _ in 1 2 3 4 5; do
  pgrep -U "$uid" -f '/Visual Studio Code.app/' >/dev/null 2>&1 || break
  sleep 1
done

if pgrep -U "$uid" -f '/Visual Studio Code.app/' >/dev/null 2>&1; then
  pkill -U "$uid" -f '/Visual Studio Code.app/' 2>/dev/null || true
fi
