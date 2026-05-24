#!/usr/bin/env bash
# Cloud SessionStart hook for claude.ai/code (web + mobile).
# Cloud ignores ~/.claude, so this (run by a repo-committed .claude/settings.json
# SessionStart hook) brings Kev's resources into the ephemeral session:
#   - Skills + commands: copied into the project's .claude/  (side effects -> stderr)
#   - Memory: the private vault is cloned with KEV_MEM_TOKEN and its contents are emitted
#     as SessionStart `additionalContext` (injected straight into the model context).
# Only the final JSON goes to real stdout; everything else goes to stderr.

set -uo pipefail
exec 3>&1 1>&2          # logs -> stderr; fd 3 holds the real stdout for the JSON result

[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0

PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
RES="${KEV_RES_DIR:-/tmp/kev-resources}"
MEM="${KEV_MEM_DIR:-/tmp/claude-memory}"
SKILLS_REF="${KEV_PIN_REF:-d239288cb9efb5bfb6d9f9b06bc126d75b7ac675}"
SKILLS_URL="https://github.com/proton-pidgeon/claude-skills.git"
MEM_PATH="proton-pidgeon/claude-memory.git"

# 1) Skills + commands -> project .claude/
if [ ! -d "$RES/.git" ]; then
  git clone "$SKILLS_URL" "$RES" 2>/dev/null && git -C "$RES" checkout -q "$SKILLS_REF" 2>/dev/null || true
fi
if [ -d "$RES/plugins/kev/skills" ]; then
  mkdir -p "$PROJ/.claude/skills" "$PROJ/.claude/commands"
  cp -R "$RES"/plugins/kev/skills/. "$PROJ/.claude/skills/" 2>/dev/null || true
  cp -R "$RES"/plugins/kev/commands/. "$PROJ/.claude/commands/" 2>/dev/null || true
  echo "[kev-cloud] linked skills + commands into $PROJ/.claude"
fi

# 2) Clone the private memory vault with the token (scrub token from the clone afterward)
if [ ! -d "$MEM/.git" ] && [ -n "${KEV_MEM_TOKEN:-}" ]; then
  if git clone --depth 1 "https://x-access-token:${KEV_MEM_TOKEN}@github.com/${MEM_PATH}" "$MEM" 2>/dev/null; then
    git -C "$MEM" remote set-url origin "https://github.com/${MEM_PATH}" 2>/dev/null || true
  fi
fi

# 3) Emit memory as SessionStart additionalContext (JSON on real stdout = fd 3)
if [ -f "$MEM/MEMORY.md" ]; then
  CTX="$( { echo "# Your synced Claude memory (private claude-memory vault)"; echo; echo "## MEMORY.md (index)"; cat "$MEM/MEMORY.md"; echo; for f in "$MEM"/*.md; do b="$(basename "$f")"; [ "$b" = "MEMORY.md" ] && continue; echo "## $b"; cat "$f"; echo; done; } )"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg c "$CTX" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}' >&3
  else
    CTX="$CTX" python3 -c 'import json,os;print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":os.environ["CTX"]}}))' >&3
  fi
  echo "[kev-cloud] injected memory as additionalContext"
else
  echo "[kev-cloud] no memory (token missing or clone failed); skills still linked"
fi
exit 0
