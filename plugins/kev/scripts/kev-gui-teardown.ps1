#requires -version 5.1
<#
.SYNOPSIS
  Windows port of kev-gui-teardown.sh — tear down ONLY the VS Code instance the
  current Claude Code session is running inside (as opened by code-gui.ps1), from
  within that very session. Backs the /gui-teardown slash command on Windows.

.DESCRIPTION
  The session runs in VS Code's integrated terminal on the logged-in desktop, so
  we act on VS Code directly. A synchronous teardown would kill Claude mid-reply,
  so the first invocation resolves context, spawns a DETACHED hidden worker that
  waits a few seconds (letting Claude stream its reply), then tears down.

  ── HOW IT TARGETS JUST THIS INSTANCE ─────────────────────────────────────────
  code-gui.ps1 launches each repo as its own VS Code instance with a unique
  --user-data-dir ($GUI_DATA_ROOT\<repo>). That path is an explicit per-instance
  marker in the main process's command line. We derive this repo's user-data-dir
  from the session's working directory + GUI_DATA_ROOT, find the main 'Code.exe'
  (no --type=<...> flag) whose command line contains it, and quit just it
  (graceful CloseMainWindow, then a forced tree-kill if it lingers). Other repos'
  instances are untouched.

  This keys off --user-data-dir rather than walking the shell's process ancestry
  (as the macOS kev-gui-teardown.sh does) because Windows ConPTY frequently breaks
  the shell -> window parent link, making an ancestry walk unreliable.

    - Match found -> isolated instance: quit just that main process.
    - No match    -> legacy/shared window: close the window whose title matches
                     this repo; if none, fall back to quitting VS Code app-wide.

  Self-contained: ships with the kev@kevdunn plugin, no repo checkout required.

  ── STATUS: UNVERIFIED ON WINDOWS ─────────────────────────────────────────────
  Authored on macOS; needs a real Windows run before it is trusted (CommandLine
  visibility via CIM, CloseMainWindow on the main process, detached survival).

  Tunable (env): TEARDOWN_DELAY (seconds before teardown, default 5);
  GUI_DATA_ROOT (must match code-gui.ps1; default $USERPROFILE\.vscode-gui).
#>
[CmdletBinding()]
param(
  [string] $Repo,
  [string] $DataRoot,
  [int]    $Delay = $(if ($env:TEARDOWN_DELAY) { [int]$env:TEARDOWN_DELAY } else { 5 }),
  [switch] $Run   # internal: the detached worker re-invokes the script with -Run
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$marker = 'code-gui-keepawake'   # must match the launcher (code-gui.ps1)
$self   = $PSCommandPath

# Resolve the workspace folder + data root (the instance key) while we still have
# the session's cwd; the detached worker reuses them via -Repo / -DataRoot.
if (-not $Repo) {
  $top = (& git rev-parse --show-toplevel 2>$null)
  if ($LASTEXITCODE -eq 0 -and $top) { $Repo = Split-Path -Leaf $top }
  else { $Repo = Split-Path -Leaf (Get-Location).Path }
}
if (-not $DataRoot) {
  $DataRoot = if ($env:GUI_DATA_ROOT) { $env:GUI_DATA_ROOT } else { Join-Path $env:USERPROFILE '.vscode-gui' }
}
$userData = Join-Path $DataRoot $Repo

function Get-CodeProcesses {
  Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -in @('Code.exe', 'Code - Insiders.exe') }
}
function Test-IsMain { param($Proc) $Proc.CommandLine -and ($Proc.CommandLine -notmatch '--type=') }
function Get-ThisInstanceMain {
  param([string] $UserData)
  Get-CodeProcesses | Where-Object {
    (Test-IsMain $_) -and $_.CommandLine.ToLower().Contains($UserData.ToLower())
  }
}
function Test-AnyCodeMain { @(Get-CodeProcesses | Where-Object { Test-IsMain $_ }).Count -gt 0 }

# ── First invocation: schedule a detached worker, return immediately ─────────
if (-not $Run) {
  $found = @(Get-ThisInstanceMain -UserData $userData).Count -gt 0
  Start-Process -FilePath 'powershell.exe' `
    -ArgumentList '-NoProfile', '-WindowStyle', 'Hidden', '-File', $self,
                  '-Run', '-Repo', $Repo, '-DataRoot', $DataRoot, '-Delay', $Delay `
    -WindowStyle Hidden | Out-Null
  if ($found) {
    Write-Host "Teardown scheduled in ${Delay}s (detached): quitting just this VS Code"
    Write-Host "instance (repo '$Repo'). Other repos' windows stay open. Session ends then."
  } else {
    Write-Host "Teardown scheduled in ${Delay}s (detached). Couldn't pinpoint this repo's"
    Write-Host "isolated instance ('$Repo') — will try closing its window, else quit VS Code"
    Write-Host "app-wide. This session ends then."
  }
  exit 0
}

# ── Detached worker ──────────────────────────────────────────────────────────
Start-Sleep -Seconds $Delay

function Stop-CodeProcess {
  param([int] $ProcId)
  try { (Get-Process -Id $ProcId -ErrorAction Stop).CloseMainWindow() | Out-Null } catch { }
  for ($i = 0; $i -lt 8; $i++) {
    if (-not (Get-Process -Id $ProcId -ErrorAction SilentlyContinue)) { return }
    Start-Sleep -Seconds 1
  }
  & taskkill.exe /PID $ProcId /T /F 2>$null | Out-Null   # /T kills the whole tree
}

$mains = @(Get-ThisInstanceMain -UserData $userData)
if ($mains.Count -gt 0) {
  foreach ($m in $mains) { Stop-CodeProcess -ProcId $m.ProcessId }   # isolated: quit just it
} else {
  $byTitle = @(Get-Process -Name 'Code', 'Code - Insiders' -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowTitle -and $_.MainWindowTitle -like "*$Repo*" })
  if ($byTitle.Count -gt 0) {
    foreach ($p in $byTitle) { Stop-CodeProcess -ProcId $p.Id }       # legacy/shared: close our window
  } else {
    foreach ($m in @(Get-CodeProcesses | Where-Object { Test-IsMain $_ })) {
      Stop-CodeProcess -ProcId $m.ProcessId                           # last resort: app-wide
    }
  }
}

# Release the keep-awake assertion code-gui.ps1 started — ONLY if no VS Code
# instance remains, so other still-open code-gui windows keep the display awake.
if (-not (Test-AnyCodeMain)) {
  try {
    Get-CimInstance Win32_Process -Filter "Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -and $_.CommandLine -like "*$marker*" } |
      ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
  } catch { }
}
