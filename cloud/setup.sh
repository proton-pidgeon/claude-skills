#!/usr/bin/env bash
# Cloud ENVIRONMENT setup-script helper. Runs ONCE at environment build (cached, as root,
# before any Claude Code session starts — so .env vars like KEV_MEM_TOKEN are NOT yet
# available here, and additionalContext can't be emitted from here).
#
# Its ONLY job: install the global SessionStart hook into the sandbox's ~/.claude/settings.json
# so every cloud session (any repo, account-wide) fires bootstrap-cloud.sh. ALL real work —
# cloning skills, cloning the private memory vault with KEV_MEM_TOKEN, and emitting memory as
# additionalContext — happens in that hook, at session-shell time, where the token IS readable.
#
# This is why cloning was removed from this script: env vars don't reach the build-time setup
# script, only the session shell. Keep clone/token logic in bootstrap-cloud.sh, not here.

set -uo pipefail
log(){ echo "[kev-setup] $*" >&2; }

HOOK_CMD="curl -fsSL --max-time 20 https://raw.githubusercontent.com/proton-pidgeon/claude-skills/main/cloud/bootstrap-cloud.sh | bash"
SETTINGS="${HOME:-/root}/.claude/settings.json"
mkdir -p "$(dirname "$SETTINGS")"

# Merge our SessionStart hook into any existing ~/.claude/settings.json (create if absent).
# Idempotent: if a hook already runs bootstrap-cloud.sh, we don't add a duplicate.
if command -v jq >/dev/null 2>&1; then
  [ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
  tmp="$(mktemp)"
  jq --arg cmd "$HOOK_CMD" '
    .hooks.SessionStart = (
      (.hooks.SessionStart // [])
      | if any(.[]?; (.hooks // []) | any(.command? == $cmd)) then .
        else . + [{matcher:"startup|resume", hooks:[{type:"command", command:$cmd, timeout:60}]}]
        end
    )
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS" \
    && log "installed global SessionStart hook -> $SETTINGS" \
    || { log "ERROR: jq merge failed; settings left unchanged"; rm -f "$tmp"; }
else
  # No jq: only write a fresh file. Don't blindly overwrite an existing settings.json.
  if [ ! -f "$SETTINGS" ]; then
    cat > "$SETTINGS" <<EOF
{
  "hooks": {
    "SessionStart": [
      { "matcher": "startup|resume",
        "hooks": [ { "type": "command", "command": "$HOOK_CMD", "timeout": 60 } ] }
    ]
  }
}
EOF
    log "installed global SessionStart hook (no jq) -> $SETTINGS"
  else
    log "WARN: jq missing and $SETTINGS exists; not overwriting. Add the SessionStart hook manually."
  fi
fi

log "done (skills + memory are pulled by the hook at session start, not here)"
