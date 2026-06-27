#!/usr/bin/env bash
# notebooklm_push.sh — submit a research report to notebooklm-bridge and poll to completion.
# Thin curl client; all NotebookLM machinery lives in the bridge on the home Mac.
#
# Usage:
#   notebooklm_push.sh --file <report.md> --title "<title>" [--instructions "<style>"]
#
# Reads creds from ~/.claude/.notebooklm:
#   NOTEBOOKLM_BRIDGE_URL="https://<peggy-host>/notebooklm"   # no trailing slash
#   NOTEBOOKLM_BEARER_TOKEN="<token>"
#
# Exit codes: 0 = DONE; 2 = bad usage/creds; 3 = submit failed; 4 = job FAILED_*; 5 = timeout.

set -euo pipefail

CONFIG="${HOME}/.claude/.notebooklm"
POLL_INTERVAL="${NOTEBOOKLM_POLL_INTERVAL:-12}"   # seconds
POLL_MAX="${NOTEBOOKLM_POLL_MAX:-100}"            # ~20 min at 12s

die() { echo "notebooklm-push: $*" >&2; exit "${2:-1}"; }

# ---- args ----
FILE="" ; TITLE="" ; INSTRUCTIONS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --file)         FILE="${2:-}"; shift 2 ;;
    --title)        TITLE="${2:-}"; shift 2 ;;
    --instructions) INSTRUCTIONS="${2:-}"; shift 2 ;;
    *) die "unknown argument: $1" 2 ;;
  esac
done

[ -n "$FILE" ] || die "missing --file" 2
[ -f "$FILE" ] || die "report file not found: $FILE" 2
[ -n "$TITLE" ] || die "missing --title" 2

# ---- creds ----
[ -f "$CONFIG" ] || die "missing $CONFIG — create it with NOTEBOOKLM_BRIDGE_URL and NOTEBOOKLM_BEARER_TOKEN" 2
# shellcheck disable=SC1090
source "$CONFIG"
: "${NOTEBOOKLM_BRIDGE_URL:?set NOTEBOOKLM_BRIDGE_URL in $CONFIG}"
: "${NOTEBOOKLM_BEARER_TOKEN:?set NOTEBOOKLM_BEARER_TOKEN in $CONFIG}"
BASE="${NOTEBOOKLM_BRIDGE_URL%/}"

command -v jq >/dev/null 2>&1 || die "jq is required" 2
command -v curl >/dev/null 2>&1 || die "curl is required" 2

# ---- build JSON body safely (jq handles escaping of markdown) ----
BODY="$(jq -n \
  --arg title "$TITLE" \
  --rawfile markdown "$FILE" \
  --arg instr "$INSTRUCTIONS" \
  '{title: $title, markdown: $markdown}
   + (if $instr == "" then {} else {audio_instructions: $instr} end)
   + {source_label: "deep-research"}')"

# ---- submit ----
SUBMIT="$(curl -fsS -X POST "${BASE}/reports" \
  -H "Authorization: Bearer ${NOTEBOOKLM_BEARER_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$BODY" 2>/dev/null)" || die "submit failed (is the bridge up and the session valid? a 503 means re-login on the Mac)" 3

JOB_ID="$(printf '%s' "$SUBMIT" | jq -r '.job_id // empty')"
[ -n "$JOB_ID" ] || die "submit returned no job_id: $SUBMIT" 3
echo "submitted — job ${JOB_ID}; generating Audio Overview (this takes a few minutes)…"

# ---- poll ----
n=0
while [ "$n" -lt "$POLL_MAX" ]; do
  sleep "$POLL_INTERVAL"
  n=$((n+1))
  RESP="$(curl -fsS "${BASE}/reports/${JOB_ID}" \
    -H "Authorization: Bearer ${NOTEBOOKLM_BEARER_TOKEN}" 2>/dev/null)" || { echo "  (poll $n: transient error, retrying)"; continue; }

  STATE="$(printf '%s' "$RESP" | jq -r '.state // "UNKNOWN"')"
  STAGE="$(printf '%s' "$RESP" | jq -r '.stage // ""')"

  case "$STATE" in
    DONE)
      NB="$(printf '%s' "$RESP" | jq -r '.notebook_url // empty')"
      AU="$(printf '%s' "$RESP" | jq -r '.audio_url // empty')"
      echo "done."
      echo "notebook: ${NB}"
      [ -n "$AU" ] && echo "audio:    ${BASE}${AU}"
      exit 0 ;;
    FAILED_*)
      KIND="$(printf '%s' "$RESP" | jq -r '.error.kind // "unknown"')"
      MSG="$(printf '%s' "$RESP" | jq -r '.error.message // "no message"')"
      echo "failed at stage ${STAGE} (${STATE} / ${KIND}): ${MSG}" >&2
      exit 4 ;;
    *)
      echo "  (poll $n: ${STATE}${STAGE:+ / $STAGE})" ;;
  esac
done

die "timed out after ~$((POLL_INTERVAL*POLL_MAX))s waiting for the podcast (job ${JOB_ID} may still finish; poll it later)" 5
