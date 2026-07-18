#!/usr/bin/env bash
# preflight.sh — classify the CDP connection state before any MCP call.
#
# Usage:  preflight.sh [--port N] [--host H] [--target-url URL]
#
# Exit codes double as the state machine:
#   0  HEALTHY        CDP reachable and (if --target-url given) a matching tab exists
#   1  TUNNEL_DOWN    cannot reach the host at all
#   2  PORT_CLOSED    host reachable, CDP port not answering
#   3  WRONG_CHROME   CDP answering, but no tab matches the target URL
#   4  USAGE          bad arguments / missing dependency
#
# Read-only. Launches nothing, kills nothing.

set -uo pipefail

PORT=9222
HOST=127.0.0.1
TARGET_URL=""

while [ $# -gt 0 ]; do
  case "$1" in
    --port)       PORT="${2:-}"; shift 2 ;;
    --host)       HOST="${2:-}"; shift 2 ;;
    --target-url) TARGET_URL="${2:-}"; shift 2 ;;
    -h|--help)    sed -n '2,18p' "$0"; exit 4 ;;
    *) echo "preflight: unknown argument: $1" >&2; exit 4 ;;
  esac
done

command -v curl >/dev/null 2>&1 || { echo "preflight: curl not found" >&2; exit 4; }

BASE="http://${HOST}:${PORT}"

emit() {
  # emit STATE "human line" ["remediation line"]
  echo "STATE=$1"
  echo "$2"
  [ $# -ge 3 ] && echo "FIX: $3"
}

# --- 1. Is the CDP port answering at all? -----------------------------------
VERSION_JSON="$(curl -fsS --max-time 4 "${BASE}/json/version" 2>/dev/null)"
CURL_RC=$?

if [ $CURL_RC -ne 0 ]; then
  # Distinguish "host unreachable" from "host up, port closed".
  # A refused connection means we reached the host's TCP stack.
  ERRTEXT="$(curl -sS --max-time 4 "${BASE}/json/version" 2>&1 >/dev/null)"

  case "$ERRTEXT" in
    *"Connection refused"*)
      emit PORT_CLOSED \
        "Reached ${HOST} but nothing is listening on port ${PORT}." \
        "Chrome is not running with --remote-debugging-port=${PORT}, or it is bound to a different interface. Launch it via launch-chrome.sh."
      exit 2
      ;;
    *"Couldn't connect"*|*"Failed to connect"*|*"Could not resolve"*|*"timed out"*|*"Timeout"*)
      if [ "$HOST" = "127.0.0.1" ] || [ "$HOST" = "localhost" ]; then
        emit PORT_CLOSED \
          "Nothing listening on ${HOST}:${PORT} (local)." \
          "Chrome is not running with CDP enabled, or your tunnel/port-forward to the remote host is not established on this port."
        exit 2
      fi
      emit TUNNEL_DOWN \
        "Cannot reach ${HOST} at all (${ERRTEXT})." \
        "Bring the tunnel up, or re-establish the forward, e.g. ssh -L ${PORT}:127.0.0.1:${PORT} <host>"
      exit 1
      ;;
    *)
      emit TUNNEL_DOWN \
        "Could not reach ${BASE}/json/version (${ERRTEXT})." \
        "Check the tunnel/forward first, then whether Chrome is running with CDP enabled."
      exit 1
      ;;
  esac
fi

BROWSER_LINE="$(printf '%s' "$VERSION_JSON" | tr ',' '\n' | grep -i '"Browser"' | head -1 | cut -d: -f2- | tr -d '"' | sed 's/^ *//')"
[ -z "$BROWSER_LINE" ] && BROWSER_LINE="unknown build"

# --- 2. If a target URL was named, confirm a matching tab exists -------------
if [ -n "$TARGET_URL" ]; then
  LIST_JSON="$(curl -fsS --max-time 4 "${BASE}/json/list" 2>/dev/null)"
  if [ -z "$LIST_JSON" ]; then
    emit WRONG_CHROME \
      "CDP is answering (${BROWSER_LINE}) but /json/list returned nothing." \
      "Open the app in this Chrome instance, then re-run preflight."
    exit 3
  fi

  # Match on origin (scheme://host[:port]) so paths and query strings don't
  # cause false negatives.
  ORIGIN="$(printf '%s' "$TARGET_URL" | sed -E 's#^([a-zA-Z]+://[^/]+).*#\1#')"

  if printf '%s' "$LIST_JSON" | grep -Fq "$ORIGIN"; then
    emit HEALTHY "CDP healthy on ${BASE} (${BROWSER_LINE}); a tab matching ${ORIGIN} is open."
    exit 0
  fi

  OPEN_ORIGINS="$(printf '%s' "$LIST_JSON" \
    | tr ',' '\n' | grep -i '"url"' \
    | sed -E 's/.*"url" *: *"([^"]*)".*/\1/' \
    | sed -E 's#^([a-zA-Z]+://[^/]+).*#\1#' \
    | grep -v '^devtools://' | sort -u | paste -sd' ' -)"

  emit WRONG_CHROME \
    "CDP is answering (${BROWSER_LINE}) but no tab matches ${ORIGIN}. Open origins: ${OPEN_ORIGINS:-none}" \
    "You are likely attached to a different Chrome instance or profile than the one running the app. Confirm which Chrome owns port ${PORT}, or open ${TARGET_URL} in this instance."
  exit 3
fi

emit HEALTHY "CDP healthy on ${BASE} (${BROWSER_LINE})."
exit 0
