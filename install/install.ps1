# Installs the /ingest skill SessionStart hook for native Windows.
#
# Quick-install (no clone required):
#
#   irm https://raw.githubusercontent.com/proton-pidgeon/claude-skills/main/install/install.ps1 | iex
#
# What it does:
#   1. Downloads scripts/session-start-ingest-skill.ps1 to ~/.claude/scripts/
#   2. Idempotently adds a SessionStart hook entry to ~/.claude/settings.json
#      (creating the file if missing), removing any prior entries that
#      pointed at the legacy script location (including WSL /mnt/c paths).
#
# Env var overrides:
#   $env:INGEST_SKILL_REPO_RAW_BASE  e.g. https://raw.githubusercontent.com/<you>/claude-skills/main
#   $env:CLAUDE_HOME                 e.g. D:\custom\.claude (defaults to ~\.claude)

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$RepoRawBase = if ($env:INGEST_SKILL_REPO_RAW_BASE) {
    $env:INGEST_SKILL_REPO_RAW_BASE
} else {
    'https://raw.githubusercontent.com/proton-pidgeon/claude-skills/main'
}
$ClaudeHome  = if ($env:CLAUDE_HOME) { $env:CLAUDE_HOME } else { Join-Path $HOME '.claude' }
$ScriptsDir  = Join-Path $ClaudeHome 'scripts'
$ScriptPath  = Join-Path $ScriptsDir 'session-start-ingest-skill.ps1'
$Settings    = Join-Path $ClaudeHome 'settings.json'

if (-not (Test-Path $ScriptsDir)) {
    New-Item -ItemType Directory -Path $ScriptsDir -Force | Out-Null
}

Write-Host "→ Fetching session-start-ingest-skill.ps1"
Invoke-WebRequest -Uri "$RepoRawBase/scripts/session-start-ingest-skill.ps1" `
    -OutFile $ScriptPath -UseBasicParsing -TimeoutSec 15

# Command form used in settings.json. -NoProfile keeps startup fast and
# avoids the user's profile altering behavior; -File runs the script and
# exits with its exit code.
$HookCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$ScriptPath`""

# ── Merge into settings.json ──────────────────────────────────────────────
if (-not (Test-Path $Settings)) {
    Write-Host "→ Creating $Settings"
    '{}' | Set-Content -Path $Settings -Encoding UTF8
}

# Snapshot first
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
Copy-Item -Path $Settings -Destination "$Settings.bak.$stamp" -Force

$data = Get-Content -Raw -Path $Settings | ConvertFrom-Json

# PSCustomObject helpers: ensure a key exists with a default value.
function Set-IfMissing($obj, $key, $default) {
    if (-not ($obj.PSObject.Properties.Name -contains $key)) {
        $obj | Add-Member -NotePropertyName $key -NotePropertyValue $default -Force
    }
}

Set-IfMissing $data 'hooks' ([pscustomobject]@{})
Set-IfMissing $data.hooks 'SessionStart' @()

# Normalize to a real array; ConvertFrom-Json may return a single object
# for length-1 arrays.
$starts = @($data.hooks.SessionStart)

# Strip any existing entries that reference our script (legacy or current).
$cleaned = @()
foreach ($bucket in $starts) {
    $bucketHooks = @($bucket.hooks)
    $kept = $bucketHooks | Where-Object {
        ($_.command -as [string]) -notmatch 'session-start-ingest-skill'
    }
    $kept = @($kept)
    if ($kept.Count -gt 0) {
        $bucket.hooks = $kept
        $cleaned += $bucket
    }
}

# Find the matcher == "*" bucket; create it if absent.
$target = $cleaned | Where-Object { $_.matcher -eq '*' } | Select-Object -First 1
if (-not $target) {
    $target = [pscustomobject]@{ matcher = '*'; hooks = @() }
    $cleaned += $target
}

$target.hooks = @($target.hooks) + [pscustomobject]@{
    type    = 'command'
    command = $HookCommand
    timeout = 30
}

$data.hooks.SessionStart = $cleaned

# -Depth must be deep enough for nested hook structures. Trailing newline
# keeps diffs clean.
($data | ConvertTo-Json -Depth 32) + "`n" | Set-Content -Path $Settings -Encoding UTF8

Write-Host ""
Write-Host "✓ Installed."
Write-Host "  Script:   $ScriptPath"
Write-Host "  Settings: $Settings"
Write-Host ""
Write-Host "Open a new Claude Code session inside any git repo — the /ingest"
Write-Host "skill will be fetched into .claude\skills\ingest\SKILL.md and"
Write-Host "auto-committed if the working tree is otherwise clean."
Write-Host ""
Write-Host "Per-repo opt-out:  New-Item .claude\no-ingest-skill -ItemType File"
