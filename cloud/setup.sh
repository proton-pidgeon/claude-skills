#!/usr/bin/env bash
# Cloud ENVIRONMENT setup-script helper. Runs at environment build (cached, applies to
# every container/repo using this environment). Mirrors the proven ingest-skill pattern:
# write files into .claude/ that cloud reads. Needs KEV_MEM_TOKEN (read-only PAT) as an
# environment variable for the private memory vault.
#   Skills/commands -> .claude/skills, .claude/commands   (cloud discovers)
#   Memory          -> .claude/rules/kev-memory.md         (cloud loads as context)

set -uo pipefail
PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
RES="${KEV_RES_DIR:-/tmp/kev-resources}"
MEM="${KEV_MEM_DIR:-/tmp/claude-memory}"
SKILLS_REF="6e700702f65e7b4dc6d279ee181d26e236390bd4"  # main@#10 — includes ingest/shannon/understand/peggy
log(){ echo "[kev-setup] $*" >&2; }

# Skills + commands (the mechanism your ingest skill already proved works in cloud)
if [ ! -d "$RES/.git" ]; then git clone "https://github.com/proton-pidgeon/claude-skills.git" "$RES" 2>/dev/null && git -C "$RES" checkout -q "$SKILLS_REF" 2>/dev/null || true; fi
mkdir -p "$PROJ/.claude/skills" "$PROJ/.claude/commands" "$PROJ/.claude/rules"
cp -R "$RES"/plugins/kev/skills/. "$PROJ/.claude/skills/" 2>/dev/null || true
cp -R "$RES"/plugins/kev/commands/. "$PROJ/.claude/commands/" 2>/dev/null || true
log "skills + commands -> $PROJ/.claude"

# Memory: clone the private vault, write the index + facts as an auto-loaded context rule
if [ -n "${KEV_MEM_TOKEN:-}" ] && [ ! -d "$MEM/.git" ]; then
  if git clone --depth 1 "https://x-access-token:${KEV_MEM_TOKEN}@github.com/proton-pidgeon/claude-memory.git" "$MEM" 2>/dev/null; then
    git -C "$MEM" remote set-url origin "https://github.com/proton-pidgeon/claude-memory.git" 2>/dev/null || true
  fi
fi
if [ -f "$MEM/MEMORY.md" ]; then
  # Prefer .claude/CLAUDE.md (canonical, definitely loaded) when the repo doesn't ship
  # its own; otherwise fall back to .claude/rules/ so we never clobber the repo's CLAUDE.md.
  MEMOUT="$PROJ/.claude/CLAUDE.md"
  [ -f "$MEMOUT" ] && MEMOUT="$PROJ/.claude/rules/kev-memory.md"
  { echo "# Kev's synced Claude memory (auto-loaded context)"; echo; echo "## MEMORY.md (index)"; cat "$MEM/MEMORY.md"; echo; for f in "$MEM"/*.md; do b="$(basename "$f")"; [ "$b" = "MEMORY.md" ] && continue; echo "## $b"; cat "$f"; echo; done; } > "$MEMOUT"
  log "memory -> $MEMOUT"
else
  log "no memory (KEV_MEM_TOKEN missing or clone failed); skills still installed"
fi

# Keep injected files out of git status (local-only, never committed)
if [ -d "$PROJ/.git" ]; then
  EX="$PROJ/.git/info/exclude"; mkdir -p "$(dirname "$EX")"; touch "$EX"
  for p in ".claude/CLAUDE.md" ".claude/rules/kev-memory.md"; do grep -qxF "$p" "$EX" 2>/dev/null || echo "$p" >> "$EX"; done
  for d in "$RES"/plugins/kev/skills/*/; do [ -d "$d" ] || continue; n=".claude/skills/$(basename "$d")/"; grep -qxF "$n" "$EX" 2>/dev/null || echo "$n" >> "$EX"; done
  for f in "$RES"/plugins/kev/commands/*; do [ -e "$f" ] || continue; n=".claude/commands/$(basename "$f")"; grep -qxF "$n" "$EX" 2>/dev/null || echo "$n" >> "$EX"; done
fi
log "done"
