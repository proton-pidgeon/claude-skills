# Bootstrap a Windows host (CLI + Desktop) for Kev's synced Claude Code setup.
#
# Quick-install (single line, no clone needed):
#   irm https://raw.githubusercontent.com/proton-pidgeon/claude-skills/main/install/install.ps1 | iex
#
# Idempotent. What it does:
#   1. Adds the `kevdunn` marketplace and installs the `kev` plugin.
#   2. Deep-merges install/settings.shared.json into ~\.claude\settings.json
#      (timestamped backup first; your host-only keys preserved), and wires native
#      PowerShell memory-sync hooks so sync works without Git-for-Windows bash.
#   3. Clones the memory vault (proton-pidgeon/claude-memory) to the path named by
#      autoMemoryDirectory (default ~\claude-memory) so memory syncs across hosts.
#   4. Reminds you which secrets are per-host and never synced.
#
# Env overrides:
#   $env:CLAUDE_HOME        (default ~\.claude)
#   $env:KEV_REPO_RAW_BASE  (default raw GitHub main)
#   $env:KEV_MEMORY_REPO    (default proton-pidgeon/claude-memory)

[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$RepoRawBase = if ($env:KEV_REPO_RAW_BASE) { $env:KEV_REPO_RAW_BASE } else { 'https://raw.githubusercontent.com/proton-pidgeon/claude-skills/main' }
$ClaudeHome  = if ($env:CLAUDE_HOME) { $env:CLAUDE_HOME } else { Join-Path $HOME '.claude' }
$Settings    = Join-Path $ClaudeHome 'settings.json'
$MemoryRepo  = if ($env:KEV_MEMORY_REPO) { $env:KEV_MEMORY_REPO } else { 'proton-pidgeon/claude-memory' }

function Need($cmd) { if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { Write-Error "$cmd is required on PATH"; exit 1 } }
Need git; Need claude

if (-not (Test-Path $ClaudeHome)) { New-Item -ItemType Directory -Path $ClaudeHome -Force | Out-Null }

# Recursive deep-merge: $shared wins on scalars; nested objects union.
function Merge-Object($base, $shared) {
    foreach ($p in $shared.PSObject.Properties) {
        if ($p.Name -eq '_comment') { continue }
        $existing = $base.PSObject.Properties[$p.Name]
        if ($existing -and ($existing.Value -is [pscustomobject]) -and ($p.Value -is [pscustomobject])) {
            Merge-Object $existing.Value $p.Value
        } else {
            $base | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
        }
    }
}

# Add a hook $entry under hooks.$event in $data, idempotently. A hook whose command
# already contains $marker is left untouched (so re-running install.ps1 is a no-op).
function Add-PsHook($data, $event, $entry, $marker) {
    if (-not $data.PSObject.Properties['hooks']) {
        $data | Add-Member -NotePropertyName 'hooks' -NotePropertyValue ([pscustomobject]@{}) -Force
    }
    $hooks = $data.hooks
    $existing = if ($hooks.PSObject.Properties[$event]) { @($hooks.$event) } else { @() }
    foreach ($e in $existing) {
        foreach ($h in @($e.hooks)) {
            if ($h.command -and ($h.command -like "*$marker*")) { return }  # already wired
        }
    }
    $hooks | Add-Member -NotePropertyName $event -NotePropertyValue (@($existing) + $entry) -Force
}

# ── 1. Marketplace + plugin ────────────────────────────────────────────────
Write-Host "→ Adding marketplace + installing the kev plugin"
try { claude plugin marketplace add proton-pidgeon/claude-skills 2>$null } catch {}
try { claude plugin marketplace update kevdunn 2>$null } catch {}
try { claude plugin install kev@kevdunn 2>$null } catch { try { claude plugin update kev@kevdunn 2>$null } catch {} }

# ── 2. Merge shared settings ───────────────────────────────────────────────
Write-Host "→ Merging shared preferences into $Settings"
if (-not (Test-Path $Settings)) { '{}' | Set-Content -Path $Settings -Encoding UTF8 }
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
Copy-Item -Path $Settings -Destination "$Settings.bak.$stamp" -Force

$shared = (Invoke-WebRequest -Uri "$RepoRawBase/install/settings.shared.json" -UseBasicParsing -TimeoutSec 15).Content | ConvertFrom-Json
$data   = Get-Content -Raw -Path $Settings | ConvertFrom-Json
if (-not $data) { $data = [pscustomobject]@{} }
Merge-Object $data $shared

# ── 2b. Native PowerShell memory-sync hooks (Windows, no Git-bash needed) ───
# The plugin ships bash sync hooks (hooks.json) for macOS/Linux/Git-bash. On a pure
# Windows host those need bash on PATH; these .ps1 ports do not. We fetch them next to
# settings and wire equivalent SessionStart/SessionEnd hooks into settings.json. The bash
# and PowerShell hooks are both idempotent, so a Windows+Git-bash host running both is
# harmless (the second pull/push is a no-op).
$psExe = $null
if (Get-Command pwsh -ErrorAction SilentlyContinue) { $psExe = 'pwsh' }
elseif (Get-Command powershell -ErrorAction SilentlyContinue) { $psExe = 'powershell' }
if ($psExe) {
    $pullPath  = Join-Path $ClaudeHome 'kev-sync-pull.ps1'
    $pushPath  = Join-Path $ClaudeHome 'kev-sync-push.ps1'
    $indexPath = Join-Path $ClaudeHome 'kev-memory-index.mjs'
    try {
        (Invoke-WebRequest -Uri "$RepoRawBase/plugins/kev/scripts/kev-sync-pull.ps1" -UseBasicParsing -TimeoutSec 15).Content | Set-Content -Path $pullPath -Encoding UTF8
        (Invoke-WebRequest -Uri "$RepoRawBase/plugins/kev/scripts/kev-sync-push.ps1" -UseBasicParsing -TimeoutSec 15).Content | Set-Content -Path $pushPath -Encoding UTF8
        # MEMORY.md index regenerator (Node), resolved by the hooks via $PSScriptRoot.
        (Invoke-WebRequest -Uri "$RepoRawBase/plugins/kev/scripts/kev-memory-index.mjs" -UseBasicParsing -TimeoutSec 15).Content | Set-Content -Path $indexPath -Encoding UTF8
        $startEntry = [pscustomobject]@{
            matcher = 'startup|resume'
            hooks   = @([pscustomobject]@{ type = 'command'; command = "$psExe -NoProfile -ExecutionPolicy Bypass -File `"$pullPath`""; timeout = 60 })
        }
        $endEntry = [pscustomobject]@{
            hooks = @([pscustomobject]@{ type = 'command'; command = "$psExe -NoProfile -ExecutionPolicy Bypass -File `"$pushPath`""; timeout = 60 })
        }
        Add-PsHook $data 'SessionStart' $startEntry 'kev-sync-pull.ps1'
        Add-PsHook $data 'SessionEnd'   $endEntry   'kev-sync-push.ps1'
        Write-Host "  Native PowerShell sync hooks wired ($psExe)"
    } catch {
        Write-Warning "Could not install PowerShell sync hooks (will fall back to the plugin's bash hooks): $_"
    }
}

($data | ConvertTo-Json -Depth 32) + "`n" | Set-Content -Path $Settings -Encoding UTF8
Write-Host "  Settings merged"

# ── 3. Memory vault ────────────────────────────────────────────────────────
$memSetting = $data.PSObject.Properties['autoMemoryDirectory'].Value
if (-not $memSetting) { $memSetting = '~/claude-memory' }
$MemDir = $memSetting -replace '^~[/\\]', ($HOME.TrimEnd('\') + '\') -replace '/', '\'

if (Test-Path (Join-Path $MemDir '.git')) {
    Write-Host "→ Memory vault present at $MemDir — pulling latest"
    git -C $MemDir pull --rebase --autostash --quiet 2>$null
} else {
    Write-Host "→ Cloning memory vault $MemoryRepo -> $MemDir"
    try {
        git clone "https://github.com/$MemoryRepo.git" $MemDir 2>$null
    } catch {
        Write-Warning "Could not clone $MemoryRepo (missing or no access). Create it, then re-run. autoMemoryDirectory is set to $MemDir."
    }
}

# ── 4. Per-host secrets reminder ───────────────────────────────────────────
Write-Host ""
Write-Host "✓ Bootstrap complete. Restart Claude Code to load the plugin and hooks."
Write-Host ""
Write-Host "Per-host secrets are NEVER synced — set these on each machine:"
Write-Host "  • Telegram alerts:   run the telegram-notify setup; creds live in ~\.claude\.telegram"
Write-Host "  • MCP server tokens: add to ~\.claude.json or environment (never committed)"
Write-Host ""
Write-Host "Memory lives in: $MemDir  (open it as an Obsidian vault for a GUI)."
Write-Host "It syncs automatically on session start (pull) and session end (push)."
