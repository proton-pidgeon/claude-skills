# SessionStart hook: ensure .claude/skills/ingest/SKILL.md is present and
# up to date in the current git repo. Idempotent. Safe to run any session.
#
# Native PowerShell equivalent of session-start-ingest-skill.sh. Targets
# Windows PowerShell 5.1+ and PowerShell 7+.
#
# Behavior:
#   - No-op outside a git working tree
#   - No-op if the repo contains .claude/no-ingest-skill (per-repo opt-out)
#   - Fetch upstream SKILL.md; if the content differs from the local copy
#     (or the local copy is missing), write the new content
#   - When a change is written, stage it. Auto-commit only if the working
#     tree is otherwise clean
#
# Configuration (env vars):
#   INGEST_SKILL_URL   override the upstream URL (default: GitHub raw)
#   INGEST_SKILL_QUIET set non-empty to suppress non-error stderr output

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Quiet = -not [string]::IsNullOrEmpty($env:INGEST_SKILL_QUIET)

function Write-Log {
    param([string]$Message)
    if (-not $Quiet) {
        [Console]::Error.WriteLine("[ingest-skill-hook] $Message")
    }
}

# ── 0. Bail fast if we're not in a git working tree ───────────────────────
$repoRoot = $null
try {
    $repoRoot = (& git rev-parse --show-toplevel 2>$null).Trim()
} catch { }
if ([string]::IsNullOrEmpty($repoRoot)) { exit 0 }

$relPath   = '.claude/skills/ingest/SKILL.md'
$skillPath = Join-Path $repoRoot $relPath
$skillUrl  = if ($env:INGEST_SKILL_URL) { $env:INGEST_SKILL_URL } else {
    'https://raw.githubusercontent.com/proton-pidgeon/claude-skills/main/ingest/SKILL.md'
}

# ── 1. Per-repo opt-out ───────────────────────────────────────────────────
if (Test-Path (Join-Path $repoRoot '.claude/no-ingest-skill')) { exit 0 }

# ── 2. Fetch upstream into a temp file ────────────────────────────────────
$tmp = [System.IO.Path]::GetTempFileName()
try {
    try {
        # -UseBasicParsing keeps this fast and avoids IE engine quirks on
        # Windows PowerShell 5.x. TimeoutSec is wall-clock.
        $null = Invoke-WebRequest -Uri $skillUrl -OutFile $tmp `
            -UseBasicParsing -TimeoutSec 10
    } catch {
        Write-Log "could not fetch $skillUrl; skipping ($($_.Exception.Message))"
        exit 0
    }

    if ((Get-Item $tmp).Length -eq 0) {
        Write-Log 'upstream returned an empty body; skipping'
        exit 0
    }

    # ── 3. Compare to local; no-op if identical ───────────────────────────
    if (Test-Path $skillPath) {
        $upstreamHash = (Get-FileHash -Path $tmp -Algorithm SHA256).Hash
        $localHash    = (Get-FileHash -Path $skillPath -Algorithm SHA256).Hash
        if ($upstreamHash -eq $localHash) { exit 0 }
    }

    # ── 4. Install / refresh ──────────────────────────────────────────────
    $dir = Split-Path $skillPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Move-Item -Path $tmp -Destination $skillPath -Force
    $tmp = $null  # signal "don't clean up" to the finally block
} finally {
    if ($tmp -and (Test-Path $tmp)) { Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue }
}

# ── 5. Stage; auto-commit only if working tree is otherwise clean ─────────
Push-Location $repoRoot
try {
    & git add -- $relPath | Out-Null

    $otherStaged = & git diff --cached --name-only | Where-Object { $_ -and $_ -ne $relPath }
    $unstaged    = & git diff --name-only | Where-Object { $_ }
    $untracked   = & git ls-files --others --exclude-standard | Where-Object { $_ -and $_ -ne $relPath }

    if (-not $otherStaged -and -not $unstaged -and -not $untracked) {
        $commitOut = & git commit -m 'Update /ingest skill via SessionStart hook' 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Log 'refreshed /ingest skill and committed'
        } else {
            Write-Log 'refreshed /ingest skill; auto-commit failed (signing or hooks?), leaving staged'
        }
    } else {
        Write-Log 'refreshed /ingest skill; staged but not committed (working tree not clean)'
    }
} finally {
    Pop-Location
}
