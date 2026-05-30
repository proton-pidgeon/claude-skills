#!/usr/bin/env bash
# SessionEnd hook (kev plugin): commit and push memory-vault changes, conflict-safe.
# Best-effort and non-blocking. On an unresolvable rebase conflict it aborts the
# push, leaves the working tree untouched, and fires a Telegram alert (if configured)
# so the conflict can be merged by hand — this is the safety valve for fully-automatic
# multi-host sync.
#
# Memory directory is resolved from `autoMemoryDirectory` (see kev-sync-pull.sh).
# Skipped on cloud (CLAUDE_CODE_REMOTE=true) — cloud write-back is opt-in elsewhere.

set -uo pipefail

QUIET="${KEV_SYNC_QUIET:-}"
log() { [ -n "$QUIET" ] && return 0; echo "[kev-sync] $*" >&2; }

notify_telegram() {
  # Self-contained: source local (gitignored) creds and hit the Bot API directly.
  local tg="${CLAUDE_HOME:-$HOME/.claude}/.telegram"
  [ -f "$tg" ] || return 0
  # shellcheck disable=SC1090,SC1091
  . "$tg" 2>/dev/null || return 0
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ -n "${TELEGRAM_CHAT_ID:-}" ] || return 0
  curl -fsS --max-time 10 \
    "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$1" >/dev/null 2>&1 || true
}

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] && exit 0

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
SETTINGS="$CLAUDE_HOME/settings.json"

MEM_DIR=""
if command -v jq >/dev/null 2>&1 && [ -f "$SETTINGS" ]; then
  MEM_DIR="$(jq -r '.autoMemoryDirectory // empty' "$SETTINGS" 2>/dev/null)"
fi
MEM_DIR="${MEM_DIR:-$HOME/claude-memory}"
case "$MEM_DIR" in
  "~")   MEM_DIR="$HOME" ;;
  "~/"*) MEM_DIR="$HOME/${MEM_DIR#"~/"}" ;;
esac

[ -d "$MEM_DIR/.git" ] || exit 0

HOST="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo unknown)"
STAMP="$(date -u +%FT%TZ 2>/dev/null || date)"

# Stage and commit only if there is something to commit.
if [ -n "$(git -C "$MEM_DIR" status --porcelain 2>/dev/null)" ]; then
  git -C "$MEM_DIR" add -A 2>/dev/null || true
  git -C "$MEM_DIR" commit -m "memory: auto-sync from $HOST $STAMP" --quiet 2>/dev/null || true
fi

# Nothing to push (no local commits ahead)? Done.
if ! git -C "$MEM_DIR" log '@{upstream}..HEAD' --oneline 2>/dev/null | grep -q .; then
  exit 0
fi

# Rebase onto remote, then push. On conflict: abort, keep working tree, alert.
if git -C "$MEM_DIR" pull --rebase --autostash --quiet 2>/dev/null; then
  if git -C "$MEM_DIR" push --quiet 2>/dev/null; then
    log "memory pushed from $HOST"
  else
    log "memory push failed (offline?); will retry next session"
  fi
else
  git -C "$MEM_DIR" rebase --abort 2>/dev/null || true
  log "MEMORY SYNC CONFLICT in $MEM_DIR — manual merge needed"
  notify_telegram "⚠️ Claude memory sync conflict on ${HOST}. Auto-rebase failed; resolve manually in ${MEM_DIR} (your local commit is intact, not yet pushed)."
fi

exit 0
