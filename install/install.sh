#!/usr/bin/env bash
# Installs the /ingest skill SessionStart hook for macOS, Linux, Claude
# Cloud sandbox, or Git Bash on Windows.
#
# Quick-install (no clone required):
#
#   curl -fsSL https://raw.githubusercontent.com/proton-pidgeon/claude-skills/main/install/install.sh | bash
#
# What it does:
#   1. Downloads scripts/session-start-ingest-skill.sh to ~/.claude/scripts/
#   2. Idempotently adds a SessionStart hook entry to ~/.claude/settings.json
#      (creating the file if missing), removing any prior entries that
#      pointed at the legacy script location.
#
# Env var overrides:
#   INGEST_SKILL_REPO_RAW_BASE  e.g. https://raw.githubusercontent.com/<you>/claude-skills/main
#   CLAUDE_HOME                 e.g. /custom/.claude  (defaults to $HOME/.claude)

set -euo pipefail

REPO_RAW_BASE="${INGEST_SKILL_REPO_RAW_BASE:-https://raw.githubusercontent.com/proton-pidgeon/claude-skills/main}"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
SCRIPTS_DIR="$CLAUDE_HOME/scripts"
SCRIPT_PATH="$SCRIPTS_DIR/session-start-ingest-skill.sh"
SETTINGS_PATH="$CLAUDE_HOME/settings.json"

mkdir -p "$SCRIPTS_DIR"

echo "→ Fetching session-start-ingest-skill.sh"
curl -fsSL --max-time 15 "$REPO_RAW_BASE/scripts/session-start-ingest-skill.sh" -o "$SCRIPT_PATH"
chmod +x "$SCRIPT_PATH"

# ── Merge hook into settings.json ─────────────────────────────────────────
# The merge is JSON-aware. Prefers jq; falls back to python3. If neither
# is available we print the snippet for manual merge and exit non-zero.

# Build a marker that uniquely identifies our hook entry so we can find
# and replace it idempotently across runs.
HOOK_COMMAND="bash \"$SCRIPT_PATH\""

if [ ! -f "$SETTINGS_PATH" ]; then
    echo "→ Creating $SETTINGS_PATH"
    echo '{}' > "$SETTINGS_PATH"
fi

# Snapshot for safety
cp "$SETTINGS_PATH" "$SETTINGS_PATH.bak.$(date +%Y%m%d%H%M%S)"

merge_with_jq() {
    local tmp
    tmp=$(mktemp)
    jq --arg cmd "$HOOK_COMMAND" '
      # Ensure the hooks.SessionStart array exists
      .hooks //= {}
      | .hooks.SessionStart //= []

      # Strip any existing entries that reference our script (legacy or current).
      | .hooks.SessionStart |= (
          map(
            .hooks |= (map(select((.command // "") | test("session-start-ingest-skill"; "") | not)))
          )
          # Drop now-empty matcher buckets so we do not accumulate stubs
          | map(select((.hooks // []) | length > 0))
        )

      # Find a matcher == "*" bucket; create one if absent
      | (.hooks.SessionStart | map(.matcher == "*") | index(true)) as $i
      | if $i == null then
          .hooks.SessionStart += [{
            "matcher": "*",
            "hooks": [{"type": "command", "command": $cmd, "timeout": 30}]
          }]
        else
          .hooks.SessionStart[$i].hooks += [{"type": "command", "command": $cmd, "timeout": 30}]
        end
    ' "$SETTINGS_PATH" > "$tmp"
    mv "$tmp" "$SETTINGS_PATH"
}

merge_with_python() {
    HOOK_COMMAND="$HOOK_COMMAND" SETTINGS_PATH="$SETTINGS_PATH" python3 - <<'PY'
import json, os, sys
path = os.environ['SETTINGS_PATH']
cmd  = os.environ['HOOK_COMMAND']
with open(path, 'r', encoding='utf-8') as fh:
    data = json.load(fh)

hooks  = data.setdefault('hooks', {})
starts = hooks.setdefault('SessionStart', [])

# Strip any existing entries that reference our script (legacy or current).
new_starts = []
for bucket in starts:
    bucket_hooks = bucket.get('hooks', []) or []
    kept = [h for h in bucket_hooks if 'session-start-ingest-skill' not in (h.get('command') or '')]
    if kept:
        bucket['hooks'] = kept
        new_starts.append(bucket)
hooks['SessionStart'] = new_starts

# Find the matcher == "*" bucket
target = next((b for b in new_starts if b.get('matcher') == '*'), None)
if target is None:
    target = {'matcher': '*', 'hooks': []}
    new_starts.append(target)
target['hooks'].append({'type': 'command', 'command': cmd, 'timeout': 30})

with open(path, 'w', encoding='utf-8') as fh:
    json.dump(data, fh, indent=2)
    fh.write('\n')
PY
}

if command -v jq >/dev/null 2>&1; then
    echo "→ Merging hook with jq"
    merge_with_jq
elif command -v python3 >/dev/null 2>&1; then
    echo "→ Merging hook with python3"
    merge_with_python
else
    cat <<EOF >&2

⚠ Neither jq nor python3 is on PATH; cannot edit $SETTINGS_PATH safely.
  Manually add this to "hooks.SessionStart" (matcher "*"):

    { "type": "command", "command": "$HOOK_COMMAND", "timeout": 30 }

EOF
    exit 1
fi

echo
echo "✓ Installed."
echo "  Script:   $SCRIPT_PATH"
echo "  Settings: $SETTINGS_PATH"
echo
echo "Open a new Claude Code session inside any git repo — the /ingest"
echo "skill will be fetched into .claude/skills/ingest/SKILL.md and"
echo "auto-committed if the working tree is otherwise clean."
echo
echo "Per-repo opt-out:  touch .claude/no-ingest-skill"
