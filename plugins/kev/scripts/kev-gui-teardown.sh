#!/usr/bin/env bash
#
# kev-gui-teardown.sh — tear down ONLY the VS Code window/instance that the
# current Claude Code session is running inside (as opened by code-gui.sh),
# from within that very session. Backs the /gui-teardown slash command.
#
# The Claude session runs in VS Code's integrated terminal, inside the logged-in
# Aqua session — so we can act on VS Code directly (no sudo / launchctl asuser).
# But a synchronous teardown would kill Claude mid-command before it could reply,
# so we spawn a DETACHED worker (orphaned to launchd, survives VS Code dying)
# that waits a few seconds first, letting Claude stream its reply to the user
# before its window — and this session — goes away.
#
# "Only this window" — how:
#   code-gui.sh launches each repo as its own VS Code instance (separate
#   --user-data-dir → separate Electron main process). We walk this process's
#   ancestry up to that main process and quit just it (a plain SIGTERM — no
#   Accessibility needed), leaving other repos' instances untouched.
#
#   Legacy / shared instances: if several windows share one main process (e.g.
#   older windows opened before per-repo isolation), we can't quit just ours at
#   the process level, so we close our window by title via Accessibility
#   (System Events) — leaving the instance and its sibling windows running.
#
#   If we can't pinpoint our instance at all, we fall back to quitting VS Code
#   app-wide (the original behaviour).
#
# Self-contained: ships with the kev@kevdunn plugin, no repo checkout required.
#
# Tunable (env): TEARDOWN_DELAY — seconds to wait before tearing down (default 5).

set -euo pipefail

uid="$(id -u)"
self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
delay="${TEARDOWN_DELAY:-5}"

# Walk up the process ancestry from $1 to the nearest VS Code MAIN process (the
# per-instance Electron root — ".../MacOS/Code", NOT a "Code Helper"). Echoes its
# PID, or nothing if no VS Code ancestor is found.
resolve_main() {
  local pid="$1" cmd ppid i=0
  while [[ -n "$pid" && "$pid" != "0" && "$pid" != "1" && "$i" -lt 25 ]]; do
    cmd="$(ps -o command= -p "$pid" 2>/dev/null || true)"
    [[ -z "$cmd" ]] && break
    case "$cmd" in
      *"Code Helper"*) : ;;  # a helper process — keep climbing
      *"/Visual Studio Code.app/Contents/MacOS/Code"*) echo "$pid"; return 0 ;;
    esac
    ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
    pid="$ppid"; i=$((i + 1))
  done
  return 0
}

# Count window (renderer) processes belonging to the main PID in $1.
count_windows() {
  ps -ax -o ppid=,command= 2>/dev/null \
    | awk -v m="$1" '$1 == m && index($0, "--type=renderer") > 0' \
    | wc -l | tr -d ' '
}

# --- first invocation: schedule, then return so the session can finish replying.
if [[ "${1:-}" != "--run" ]]; then
  main_pid="$(resolve_main "$$")"
  workspace="$(basename "$PWD")"
  win_count=0
  [[ -n "$main_pid" ]] && win_count="$(count_windows "$main_pid")"

  # The worker is reparented to launchd and loses this ancestry, so pass the
  # resolved context forward via the environment.
  nohup env TEARDOWN_MAIN="${main_pid:-}" TEARDOWN_WS="$workspace" TEARDOWN_NWIN="$win_count" \
    sh -c "sleep $delay; exec \"$self\" --run" >/dev/null 2>&1 </dev/null &
  disown 2>/dev/null || true   # drop from the job table too, so VS Code closing
                               # the terminal can't take the worker down with it

  if [[ -z "$main_pid" ]]; then
    echo "Teardown scheduled in ${delay}s (detached). Couldn't pinpoint this"
    echo "window's VS Code instance — falling back to quitting VS Code app-wide."
    echo "This session ends then."
  elif [[ "$win_count" -le 1 ]]; then
    echo "Teardown scheduled in ${delay}s (detached): quitting just this VS Code"
    echo "instance (window '$workspace'). This session ends then."
  else
    echo "Teardown scheduled in ${delay}s (detached): closing just this window"
    echo "('$workspace'); $((win_count - 1)) other window(s) in this VS Code"
    echo "instance stay open. This session ends then."
  fi
  exit 0
fi

# --- detached worker -------------------------------------------------------

main="${TEARDOWN_MAIN:-}"
ws="${TEARDOWN_WS:-}"
nwin="${TEARDOWN_NWIN:-0}"

# Quit one VS Code instance by PID: ask politely (SIGTERM saves state), then
# force any survivor so teardown never hangs. No Accessibility needed.
quit_instance() {
  local m="$1"
  kill -TERM "$m" 2>/dev/null || true
  for _ in 1 2 3 4 5 6 7 8; do
    kill -0 "$m" 2>/dev/null || return 0
    sleep 1
  done
  kill -KILL "$m" 2>/dev/null || true
}

# Close one VS Code window by title via Accessibility, leaving the instance and
# its sibling windows alive. Returns non-zero if no matching window / AX denied.
close_window_ax() {
  local title="$1"
  /usr/bin/osascript >/dev/null 2>&1 <<OSA || return 1
tell application "System Events"
  if not (exists process "Code") then error "no Code process"
  tell process "Code"
    set matches to (every window whose name is "$title")
    if (count of matches) is 0 then set matches to (every window whose name contains "$title")
    if (count of matches) is 0 then error "no matching window"
    perform action "AXPress" of (first button of (item 1 of matches) whose description is "close button")
  end tell
end tell
OSA
}

# Quit VS Code app-wide (original behaviour) — last-resort fallback.
quit_app_wide() {
  /usr/bin/osascript -e 'tell application "Visual Studio Code" to quit' >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5; do
    pgrep -U "$uid" -f '/Visual Studio Code.app/' >/dev/null 2>&1 || break
    sleep 1
  done
  if pgrep -U "$uid" -f '/Visual Studio Code.app/' >/dev/null 2>&1; then
    pkill -U "$uid" -f '/Visual Studio Code.app/' 2>/dev/null || true
  fi
}

if [[ -z "$main" ]]; then
  quit_app_wide
elif [[ "$nwin" -le 1 ]]; then
  quit_instance "$main"          # our window is this instance's only one
else
  close_window_ax "$ws" || true  # shared instance: close just our window
fi

# Release the desktop-awake assertion code-gui.sh started — but ONLY if no VS
# Code remains, so other still-open code-gui windows keep the display awake.
if ! pgrep -U "$uid" -f '/Visual Studio Code.app/Contents/MacOS/Code' >/dev/null 2>&1; then
  pkill -U "$uid" -f 'caffeinate -dim -t' 2>/dev/null || true
fi
