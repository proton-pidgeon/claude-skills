#!/usr/bin/env bash
# SessionStart hook: ensure .claude/skills/ingest/SKILL.md is present and
# up to date in the current git repo. Idempotent. Safe to run any session.
#
# Cross-OS: works on macOS, Linux, Claude Cloud sandbox, and Git Bash on
# Windows. For native PowerShell, use the .ps1 sibling.
#
# Behavior:
#   - No-op outside a git working tree
#   - No-op if the repo contains .claude/no-ingest-skill (per-repo opt-out)
#   - Fetch upstream SKILL.md; if the content differs from the local copy
#     (or the local copy is missing), write the new content
#   - When a change is written, stage it. Auto-commit only if the working
#     tree is otherwise clean — never pollute a feature branch mid-work.
#
# Configuration (env vars):
#   INGEST_SKILL_URL   override the upstream URL (default: GitHub raw)
#   INGEST_SKILL_QUIET set non-empty to suppress non-error stderr output

set -euo pipefail

# ── 0. Bail fast if we're not in a git working tree ───────────────────────
if ! git rev-parse --git-dir >/dev/null 2>&1; then
    exit 0
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
REL_PATH=".claude/skills/ingest/SKILL.md"
SKILL_PATH="$REPO_ROOT/$REL_PATH"
SKILL_URL="${INGEST_SKILL_URL:-https://raw.githubusercontent.com/proton-pidgeon/claude-skills/d239288cb9efb5bfb6d9f9b06bc126d75b7ac675/plugins/kev/skills/ingest/SKILL.md}"

# ── 1. Per-repo opt-out ───────────────────────────────────────────────────
if [ -f "$REPO_ROOT/.claude/no-ingest-skill" ]; then
    exit 0
fi

log() {
    [ -n "${INGEST_SKILL_QUIET:-}" ] && return 0
    echo "[ingest-skill-hook] $*" >&2
}

# ── 2. Fetch upstream into a temp file ────────────────────────────────────
TMP=$(mktemp 2>/dev/null || mktemp -t ingest-skill)
trap 'rm -f "$TMP"' EXIT

if ! curl -fsSL --max-time 10 "$SKILL_URL" -o "$TMP" 2>/dev/null; then
    log "could not fetch $SKILL_URL; skipping"
    exit 0
fi

# Guard against empty / suspiciously small responses
if [ ! -s "$TMP" ]; then
    log "upstream returned an empty body; skipping"
    exit 0
fi

# ── 3. Compare to local; no-op if identical ───────────────────────────────
if [ -f "$SKILL_PATH" ] && cmp -s "$TMP" "$SKILL_PATH"; then
    exit 0
fi

# ── 4. Install / refresh ──────────────────────────────────────────────────
mkdir -p "$(dirname "$SKILL_PATH")"
mv "$TMP" "$SKILL_PATH"
trap - EXIT

cd "$REPO_ROOT"
git add -- "$REL_PATH"

# ── 5. Auto-commit only if the working tree is otherwise clean ────────────
other_staged=$(git diff --cached --name-only | grep -vxF "$REL_PATH" || true)
unstaged=$(git diff --name-only || true)
untracked=$(git ls-files --others --exclude-standard | grep -vxF "$REL_PATH" || true)

if [ -z "$other_staged" ] && [ -z "$unstaged" ] && [ -z "$untracked" ]; then
    if git commit -m "Update /ingest skill via SessionStart hook" >/dev/null 2>&1; then
        log "refreshed /ingest skill and committed"
    else
        log "refreshed /ingest skill; auto-commit failed (signing or hooks?), leaving staged"
    fi
else
    log "refreshed /ingest skill; staged but not committed (working tree not clean)"
fi
