# SessionEnd hook (kev plugin) — native PowerShell port of kev-sync-push.sh, for Windows
# hosts without Git-for-Windows bash on PATH. Commit + push memory-vault changes,
# conflict-safe. Best-effort and non-blocking. On an unresolvable rebase conflict it
# aborts the push, leaves the working tree untouched, and fires a Telegram alert (if
# configured) so the conflict can be merged by hand — the safety valve for fully-automatic
# multi-host sync.
#
# Memory directory is resolved from `autoMemoryDirectory` (see kev-sync-pull.ps1).
# Skipped on cloud (CLAUDE_CODE_REMOTE=true).

$ErrorActionPreference = 'SilentlyContinue'

function Send-TelegramAlert($text) {
    # Self-contained: read local (gitignored) creds from <CLAUDE_HOME>\.telegram (KEY=value,
    # optionally `export`-prefixed / quoted) and hit the Bot API directly.
    $claudeHome = if ($env:CLAUDE_HOME) { $env:CLAUDE_HOME } else { Join-Path $HOME '.claude' }
    $tg = Join-Path $claudeHome '.telegram'
    if (-not (Test-Path $tg)) { return }
    $tok = $null; $chat = $null
    foreach ($line in (Get-Content $tg)) {
        if ($line -match '^\s*(?:export\s+)?TELEGRAM_BOT_TOKEN\s*=\s*(.+?)\s*$') { $tok  = $matches[1].Trim('"', "'") }
        if ($line -match '^\s*(?:export\s+)?TELEGRAM_CHAT_ID\s*=\s*(.+?)\s*$')   { $chat = $matches[1].Trim('"', "'") }
    }
    if (-not $tok -or -not $chat) { return }
    try {
        Invoke-RestMethod -Method Post -TimeoutSec 10 `
            -Uri "https://api.telegram.org/bot$tok/sendMessage" `
            -Body @{ chat_id = $chat; text = $text } | Out-Null
    } catch {}
}

if ($env:CLAUDE_CODE_REMOTE -eq 'true') { exit 0 }

$claudeHome = if ($env:CLAUDE_HOME) { $env:CLAUDE_HOME } else { Join-Path $HOME '.claude' }
$settings   = Join-Path $claudeHome 'settings.json'

$memDir = $null
if (Test-Path $settings) {
    try { $memDir = (Get-Content -Raw $settings | ConvertFrom-Json).autoMemoryDirectory } catch {}
}
if (-not $memDir) { $memDir = '~/claude-memory' }
$memDir = $memDir -replace '^~[/\\]', ($HOME.TrimEnd('\') + '\') -replace '/', '\'

if (-not (Test-Path (Join-Path $memDir '.git'))) { exit 0 }

$hostName = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { 'unknown' }
$stamp    = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

# MEMORY.md is derived from per-file frontmatter — rebuild it before committing
# so what lands upstream is canonical (direct index edits get reconciled away).
function Update-MemoryIndex {
    $indexer = Join-Path $PSScriptRoot 'kev-memory-index.mjs'
    if ((Get-Command node -ErrorAction SilentlyContinue) -and (Test-Path $indexer)) {
        node $indexer $memDir 2>$null
    }
}
Update-MemoryIndex

# Stage and commit only if there is something to commit.
if (git -C $memDir status --porcelain 2>$null) {
    git -C $memDir add -A 2>$null
    git -C $memDir commit -m "memory: auto-sync from $hostName $stamp" --quiet 2>$null
}

# Nothing to push (no local commits ahead)? Done.
if (-not (git -C $memDir log '@{upstream}..HEAD' --oneline 2>$null)) { exit 0 }

# Rebase onto remote, then push. On conflict: abort, keep working tree, alert.
git -C $memDir pull --rebase --autostash --quiet 2>$null
if ($LASTEXITCODE -eq 0) {
    # The rebase may have brought in new/changed memory files — regenerate so the
    # pushed index reflects them, folding any change into a follow-up commit.
    Update-MemoryIndex
    if (git -C $memDir status --porcelain 2>$null) {
        git -C $memDir add -A 2>$null
        git -C $memDir commit -m "memory: regenerate index after rebase ($hostName)" --quiet 2>$null
    }
    git -C $memDir push --quiet 2>$null
} else {
    git -C $memDir rebase --abort 2>$null
    Send-TelegramAlert "WARNING: Claude memory sync conflict on $hostName. Auto-rebase failed; resolve manually in $memDir (your local commit is intact, not yet pushed)."
}
exit 0
