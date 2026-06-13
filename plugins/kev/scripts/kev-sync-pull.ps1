# SessionStart hook (kev plugin) — native PowerShell port of kev-sync-pull.sh, for
# Windows hosts without Git-for-Windows bash on PATH. Pull the latest memory vault.
# Best-effort and non-blocking — a sync hiccup must never break the session.
#
# Memory directory is resolved from `autoMemoryDirectory` in ~\.claude\settings.json
# (single source of truth), falling back to ~\claude-memory. Cloud sessions bootstrap
# differently, so this host-sync is skipped when CLAUDE_CODE_REMOTE=true.
#
# install.ps1 copies this script to ~\.claude\ and wires it into settings.json as a
# SessionStart hook. See kev-sync-push.ps1 for the SessionEnd counterpart.

$ErrorActionPreference = 'SilentlyContinue'

# Skip on cloud — cloud surfaces clone resources via the committed per-repo hook.
if ($env:CLAUDE_CODE_REMOTE -eq 'true') { exit 0 }

$claudeHome = if ($env:CLAUDE_HOME) { $env:CLAUDE_HOME } else { Join-Path $HOME '.claude' }
$settings   = Join-Path $claudeHome 'settings.json'

# Resolve the memory directory from autoMemoryDirectory, with ~ expansion.
$memDir = $null
if (Test-Path $settings) {
    try { $memDir = (Get-Content -Raw $settings | ConvertFrom-Json).autoMemoryDirectory } catch {}
}
if (-not $memDir) { $memDir = '~/claude-memory' }
$memDir = $memDir -replace '^~[/\\]', ($HOME.TrimEnd('\') + '\') -replace '/', '\'

# Pull the memory vault (rebase to keep history linear; autostash any local edits).
if (Test-Path (Join-Path $memDir '.git')) {
    git -C $memDir pull --rebase --autostash --quiet 2>$null
    if ($LASTEXITCODE -ne 0) { git -C $memDir rebase --abort 2>$null }
    # MEMORY.md is derived from per-file frontmatter — rebuild it so the session
    # starts with an index matching the freshly pulled files. The change stays
    # uncommitted; the SessionEnd push hook commits it.
    $indexer = Join-Path $PSScriptRoot 'kev-memory-index.mjs'
    if ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path $indexer)) {
        node $indexer $memDir 2>$null
    }
}

# NOTE: plugin/marketplace CODE is intentionally NOT auto-pulled here — updating plugin
# code is a deliberate act (`claude plugin marketplace update kevdunn` + restart). Only
# the data-only memory vault syncs automatically. Mirrors kev-sync-pull.sh.
exit 0
