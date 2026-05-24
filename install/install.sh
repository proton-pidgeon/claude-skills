#!/usr/bin/env bash
# Bootstrap a host (CLI + Desktop) for Kev's synced Claude Code setup.
#
# Quick-install (single line, no clone needed):
#   curl -fsSL https://raw.githubusercontent.com/proton-pidgeon/claude-skills/main/install/install.sh | bash
#
# Idempotent. What it does:
#   1. Adds the `kevdunn` marketplace and installs the `kev` plugin
#      (skills: ingest, shannon; command: telegram; agents: arch + ux reviewers;
#       plus the fully-automatic memory-sync hooks).
#   2. Deep-merges install/settings.shared.json into ~/.claude/settings.json
#      (timestamped backup first; your host-only keys are preserved).
#   3. Clones the memory vault (default proton-pidgeon/claude-memory) to the path
#      named by autoMemoryDirectory (default ~/claude-memory) so memory syncs everywhere.
#   4. Reminds you which secrets are per-host and never synced.
#
# Env overrides:
#   CLAUDE_HOME        (default $HOME/.claude)
#   KEV_REPO_RAW_BASE  (default https://raw.githubusercontent.com/proton-pidgeon/claude-skills/main)
#   KEV_MEMORY_REPO    (default proton-pidgeon/claude-memory)

set -euo pipefail

REPO_RAW_BASE="${KEV_REPO_RAW_BASE:-https://raw.githubusercontent.com/proton-pidgeon/claude-skills/main}"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
SETTINGS="$CLAUDE_HOME/settings.json"
MEMORY_REPO="${KEV_MEMORY_REPO:-proton-pidgeon/claude-memory}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"

say()  { echo "→ $*"; }
warn() { echo "⚠ $*" >&2; }

command -v git  >/dev/null 2>&1 || { warn "git is required"; exit 1; }
command -v curl >/dev/null 2>&1 || { warn "curl is required"; exit 1; }
command -v claude >/dev/null 2>&1 || { warn "claude CLI not found on PATH"; exit 1; }
HAVE_JQ=1; command -v jq >/dev/null 2>&1 || HAVE_JQ=0

mkdir -p "$CLAUDE_HOME"

# ── 1. Marketplace + plugin ────────────────────────────────────────────────
say "Adding marketplace + installing the kev plugin"
claude plugin marketplace add proton-pidgeon/claude-skills 2>/dev/null \
  || claude plugin marketplace update kevdunn 2>/dev/null || true
claude plugin install kev@kevdunn 2>/dev/null \
  || claude plugin update kev@kevdunn 2>/dev/null || true

# ── 2. Merge shared settings ───────────────────────────────────────────────
say "Merging shared preferences into $SETTINGS"
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"

SHARED_TMP="$(mktemp)"
trap 'rm -f "$SHARED_TMP"' EXIT
if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/settings.shared.json" ]; then
  cp "$SCRIPT_DIR/settings.shared.json" "$SHARED_TMP"
else
  curl -fsSL --max-time 15 "$REPO_RAW_BASE/install/settings.shared.json" -o "$SHARED_TMP"
fi

if [ "$HAVE_JQ" = "1" ]; then
  TMP="$(mktemp)"
  # Deep-merge: shared wins for keys it defines (so preferences propagate); nested
  # objects (env, enabledPlugins) union; host-only keys preserved. Drop _comment.
  jq -s '.[0] * (.[1] | del(._comment))' "$SETTINGS" "$SHARED_TMP" > "$TMP" && mv "$TMP" "$SETTINGS"
  say "Settings merged"
else
  warn "jq not found — skipped settings merge. Install jq and re-run, or merge install/settings.shared.json by hand."
fi

# ── 3. Memory vault ────────────────────────────────────────────────────────
if [ "$HAVE_JQ" = "1" ]; then
  MEM_DIR="$(jq -r '.autoMemoryDirectory // "~/claude-memory"' "$SETTINGS" 2>/dev/null || echo "~/claude-memory")"
else
  MEM_DIR="~/claude-memory"
fi
case "$MEM_DIR" in
  "~")   MEM_DIR="$HOME" ;;
  "~/"*) MEM_DIR="$HOME/${MEM_DIR#"~/"}" ;;
esac

if [ -d "$MEM_DIR/.git" ]; then
  say "Memory vault present at $MEM_DIR — pulling latest"
  git -C "$MEM_DIR" pull --rebase --autostash --quiet 2>/dev/null || true
else
  say "Cloning memory vault $MEMORY_REPO -> $MEM_DIR"
  if git clone "https://github.com/$MEMORY_REPO.git" "$MEM_DIR" 2>/dev/null \
     || { command -v gh >/dev/null 2>&1 && gh repo clone "$MEMORY_REPO" "$MEM_DIR" 2>/dev/null; }; then
    say "Memory vault cloned"
  else
    warn "Could not clone $MEMORY_REPO (missing or no access). Create it, then re-run. autoMemoryDirectory is set to $MEM_DIR."
  fi
fi

# ── 4. Per-host secrets reminder ───────────────────────────────────────────
echo
echo "✓ Bootstrap complete. Restart Claude Code to load the plugin and hooks."
echo
echo "Per-host secrets are NEVER synced — set these on each machine:"
echo "  • Telegram alerts:   run the telegram-notify setup, then creds live in ~/.claude/.telegram"
echo "  • MCP server tokens: add to ~/.claude.json or environment (never committed)"
echo
echo "Memory lives in: $MEM_DIR  (open it as an Obsidian vault for a GUI)."
echo "It syncs automatically on session start (pull) and session end (push)."
