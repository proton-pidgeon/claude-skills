#!/usr/bin/env bash
# launch-chrome.sh — start Chrome with CDP enabled, in the requested mode.
#
# Usage:
#   launch-chrome.sh --mode clean   [--port N] [--url URL]
#   launch-chrome.sh --mode attach  [--port N] [--url URL]
#
#   clean   Disposable profile. No cookies, no session. Reproducible.
#   attach  Preserve the real logged-in session:
#             - if CDP is already answering on --port, do nothing (attach as-is)
#             - else copy the live profile to a scratch dir and launch from the copy
#
# SECURITY: always binds CDP to 127.0.0.1. CDP is unauthenticated — anyone who
# can reach the port has full control of the browser and its logged-in sessions.
# Reach it remotely over a tunnel/port-forward, never by binding a public address.
#
# Exit codes: 0 launched or already attached; 1 error; 2 user action required.

set -uo pipefail

MODE=""
PORT=9222
URL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    --url)  URL="${2:-}";  shift 2 ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "launch-chrome: unknown argument: $1" >&2; exit 1 ;;
  esac
done

case "$MODE" in
  clean|attach) ;;
  *) echo "launch-chrome: --mode must be 'clean' or 'attach'" >&2; exit 1 ;;
esac

# --- locate Chrome -----------------------------------------------------------
find_chrome() {
  local c
  for c in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "$HOME/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "$(command -v google-chrome 2>/dev/null)" \
    "$(command -v google-chrome-stable 2>/dev/null)" \
    "$(command -v chromium 2>/dev/null)" \
    "$(command -v chromium-browser 2>/dev/null)"
  do
    [ -n "$c" ] && [ -x "$c" ] && { printf '%s' "$c"; return 0; }
  done
  return 1
}

CHROME="$(find_chrome)" || { echo "launch-chrome: could not find a Chrome/Chromium binary" >&2; exit 1; }

# --- locate the live profile directory (parent of 'Default') -----------------
find_user_data_dir() {
  local d
  for d in \
    "$HOME/Library/Application Support/Google/Chrome" \
    "$HOME/.config/google-chrome" \
    "$HOME/.config/chromium"
  do
    [ -d "$d" ] && { printf '%s' "$d"; return 0; }
  done
  return 1
}

CDP_UP=0
curl -fsS --max-time 3 "http://127.0.0.1:${PORT}/json/version" >/dev/null 2>&1 && CDP_UP=1

COMMON_FLAGS=(
  "--remote-debugging-port=${PORT}"
  "--remote-debugging-address=127.0.0.1"
  "--no-first-run"
  "--no-default-browser-check"
)

# ============================================================================
# MODE: clean
# ============================================================================
if [ "$MODE" = "clean" ]; then
  if [ "$CDP_UP" -eq 1 ]; then
    echo "NOTE: something is already serving CDP on port ${PORT}."
    echo "FIX: choose a different --port for a clean instance, or stop the existing one."
    exit 2
  fi

  PROFILE_DIR="${TMPDIR:-/tmp}/kev-devtools-clean-${PORT}"
  mkdir -p "$PROFILE_DIR" || { echo "launch-chrome: cannot create ${PROFILE_DIR}" >&2; exit 1; }

  echo "MODE=clean"
  echo "PROFILE=${PROFILE_DIR}"
  "$CHROME" "${COMMON_FLAGS[@]}" --user-data-dir="$PROFILE_DIR" ${URL:+"$URL"} \
    >/dev/null 2>&1 &
  echo "PID=$!"
  echo "Launched clean Chrome with CDP on 127.0.0.1:${PORT}."
  exit 0
fi

# ============================================================================
# MODE: attach
# ============================================================================

# Case 1 — CDP already live. Attach as-is; touch nothing.
if [ "$CDP_UP" -eq 1 ]; then
  echo "MODE=attach"
  echo "ATTACHED=existing"
  echo "CDP already live on 127.0.0.1:${PORT}; attaching to the running Chrome. Nothing launched."
  exit 0
fi

# Case 2 — Chrome may be running without CDP. Cannot enable the port on a live
# process, and must never point --user-data-dir at a locked live profile.
LIVE_DIR="$(find_user_data_dir)" || {
  echo "launch-chrome: no existing Chrome profile found; use --mode clean instead." >&2
  exit 1
}

SNAPSHOT="${TMPDIR:-/tmp}/kev-devtools-session-${PORT}"

echo "MODE=attach"
echo "SOURCE_PROFILE=${LIVE_DIR}"
echo "SNAPSHOT=${SNAPSHOT}"

rm -rf "$SNAPSHOT" 2>/dev/null
mkdir -p "$SNAPSHOT" || { echo "launch-chrome: cannot create ${SNAPSHOT}" >&2; exit 1; }

# Copy only what carries the session. Copying the whole profile is slow and
# drags along caches and lock files.
if [ -d "${LIVE_DIR}/Default" ]; then
  mkdir -p "${SNAPSHOT}/Default"
  for f in Cookies "Cookies-journal" "Login Data" "Local Storage" "Session Storage" \
           Preferences "Secure Preferences" "Web Data" IndexedDB; do
    if [ -e "${LIVE_DIR}/Default/${f}" ]; then
      cp -R "${LIVE_DIR}/Default/${f}" "${SNAPSHOT}/Default/" 2>/dev/null
    fi
  done
fi
[ -e "${LIVE_DIR}/Local State" ] && cp "${LIVE_DIR}/Local State" "${SNAPSHOT}/" 2>/dev/null

# Remove any copied lock artifacts so the snapshot starts clean.
rm -f "${SNAPSHOT}/SingletonLock" "${SNAPSHOT}/SingletonCookie" "${SNAPSHOT}/SingletonSocket" 2>/dev/null

echo "SNAPSHOT_TAKEN_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)"

"$CHROME" "${COMMON_FLAGS[@]}" --user-data-dir="$SNAPSHOT" ${URL:+"$URL"} \
  >/dev/null 2>&1 &
echo "PID=$!"

cat <<'EOF'
Launched Chrome from a snapshot of the live profile, with CDP on 127.0.0.1:9222
(or the port you specified).

Caveats:
  - The snapshot froze the session at copy time. If the real browser refreshes
    its token, this copy goes stale and you will see 401s that look like app
    bugs. Re-run this script to re-snapshot rather than debugging the 401.
  - Some sites bind sessions to a device/profile fingerprint and will force a
    re-login in the copy. If that happens, quit the real Chrome and relaunch it
    on the real profile with the CDP flag instead (costs the user their tabs —
    ask first).
EOF
exit 0
