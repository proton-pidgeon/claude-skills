#!/usr/bin/env bash
# Cloud SessionStart bootstrap for claude.ai/code (web + mobile).
#
# Cloud sandboxes do NOT read your ~/.claude (no personal plugins/skills/memory),
# so this script — invoked by a repo-committed .claude/settings.json SessionStart
# hook — pulls Kev's resources into the ephemeral session. No-op outside cloud.
#
# Reliable: links the plugin's skills + commands into the session.
# Best-effort: exposes the memory vault's MEMORY.md as session context
#   (cloud memory semantics vary — verify on a real cloud session).

set -uo pipefail
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0   # cloud only

PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
SKILLS_REPO="${KEV_SKILLS_REPO:-https://github.com/proton-pidgeon/claude-skills.git}"
MEM_REPO="${KEV_MEMORY_REPO_URL:-https://github.com/proton-pidgeon/claude-memory.git}"
RES="/tmp/kev-resources"
MEM="/tmp/claude-memory"

log() { echo "[kev-cloud] $*" >&2; }

# ── 1. Skills + commands (reliable) ────────────────────────────────────────
[ -d "$RES/.git" ] || git clone --depth 1 "$SKILLS_REPO" "$RES" 2>/dev/null || true
if [ -d "$RES/plugins/kev/skills" ]; then
  mkdir -p "$PROJ/.claude/skills"
  cp -R "$RES"/plugins/kev/skills/* "$PROJ/.claude/skills/" 2>/dev/null || true
  log "linked skills into $PROJ/.claude/skills"
fi
if [ -d "$RES/plugins/kev/commands" ]; then
  mkdir -p "$PROJ/.claude/commands"
  cp -R "$RES"/plugins/kev/commands/* "$PROJ/.claude/commands/" 2>/dev/null || true
fi

# ── 2. Memory (best-effort — verify on a live cloud session) ───────────────
[ -d "$MEM/.git" ] || git clone --depth 1 "$MEM_REPO" "$MEM" 2>/dev/null || true
if [ -f "$MEM/MEMORY.md" ]; then
  # (a) Try pointing auto-memory at the cloned vault for this session.
  if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
    echo "CLAUDE_COWORK_MEMORY_PATH_OVERRIDE=$MEM" >> "$CLAUDE_ENV_FILE" 2>/dev/null || true
  fi
  # (b) Fallback: inject an import of the memory index into the project CLAUDE.md,
  #     inside a clearly-marked managed block so it is obvious and easy to drop.
  CM="$PROJ/CLAUDE.md"
  MARK_BEGIN="<!-- kev-memory:begin (cloud session import) -->"
  MARK_END="<!-- kev-memory:end -->"
  if [ -f "$CM" ] && grep -qF "$MARK_BEGIN" "$CM" 2>/dev/null; then
    : # already injected this session
  else
    {
      echo ""
      echo "$MARK_BEGIN"
      echo "@/tmp/claude-memory/MEMORY.md"
      echo "$MARK_END"
    } >> "$CM" 2>/dev/null || true
    log "injected memory import into $CM"
  fi
fi
exit 0
