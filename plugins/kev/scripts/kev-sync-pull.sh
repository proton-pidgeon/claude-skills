#!/usr/bin/env bash
# SessionStart hook (kev plugin): pull the latest memory vault and refresh the
# marketplace clone. Best-effort and non-blocking — never fails the session.
#
# Memory directory is resolved from the `autoMemoryDirectory` setting in
# ~/.claude/settings.json (single source of truth), falling back to ~/claude-memory.
# Cloud sessions bootstrap differently (see the cloud per-repo template), so this
# host-sync is skipped when CLAUDE_CODE_REMOTE=true.

set -uo pipefail   # deliberately NOT -e: a sync hiccup must never break the session

QUIET="${KEV_SYNC_QUIET:-}"
log() { [ -n "$QUIET" ] && return 0; echo "[kev-sync] $*" >&2; }

# Skip on cloud — cloud surfaces clone resources via the committed per-repo hook.
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] && exit 0

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
SETTINGS="$CLAUDE_HOME/settings.json"

# Resolve the memory directory from autoMemoryDirectory, with ~ expansion.
MEM_DIR=""
if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
  MEM_DIR="$(jq -r '.autoMemoryDirectory // empty' "$SETTINGS" 2>/dev/null)"
fi
MEM_DIR="${MEM_DIR:-$HOME/claude-memory}"
case "$MEM_DIR" in
  "~")   MEM_DIR="$HOME" ;;
  "~/"*) MEM_DIR="$HOME/${MEM_DIR#"~/"}" ;;
esac

# Pull the memory vault (rebase to keep history linear; autostash any local edits).
if [ -d "$MEM_DIR/.git" ]; then
  if git -C "$MEM_DIR" pull --rebase --autostash --quiet 2>/dev/null; then
    log "memory vault up to date ($MEM_DIR)"
  else
    git -C "$MEM_DIR" rebase --abort 2>/dev/null || true
    log "memory pull skipped (offline or needs manual merge): $MEM_DIR"
  fi
fi

# Refresh the marketplace clone so the next session sees latest skills/agents/commands.
# (Plugin changes apply on restart.) Pull the clone directly to avoid spawning claude.
MKT_DIR="$CLAUDE_HOME/plugins/marketplaces/kevdunn"
[ -d "$MKT_DIR/.git" ] && git -C "$MKT_DIR" pull --rebase --quiet 2>/dev/null || true

exit 0
