# kev-fleet.ps1 — native-PowerShell port of kev-fleet.sh. Runs a command across a
# curated fleet of Tailscale hosts, in parallel, with per-host OS detection and an
# aggregated report. Backs the /fleet skill on a Windows host that has no bash.
#
# Default action (no command given): sync the kev@kevdunn plugin on every host —
#   claude plugin marketplace update kevdunn
# so a plugin/skill change made on one host reaches all the others.
#
# SAFETY: only hosts in the allowlist file are ever touched. The allowlist is
# $env:FLEET_HOSTS (default ~\.claude\fleet-hosts): one ssh target per line (a short
# Tailscale name, a MagicDNS name, or user@host); '#' comments and blank lines
# ignored. The local node and any offline host are skipped with a note.
#
# Parity notes vs the .sh:
#  - Uses ConvertFrom-Json instead of python3 (no python dependency on Windows).
#  - ASCII status markers ([OK]/[XX]/[--]) instead of emoji — Windows consoles.
#  - Parallelism via Start-Job (works on Windows PowerShell 5.1 and PS7+).
#  - Unix hosts run under `bash -lc`; Windows hosts run via their default SSH shell;
#    the local node runs directly (cmd /c) with no ssh.
#
# Usage:
#   kev-fleet.ps1                          # plugin sync on every allowlisted host
#   kev-fleet.ps1 -- <command...>          # run an arbitrary command on every host
#   kev-fleet.ps1 --hosts a,b -- <cmd>     # restrict to a subset (must be allowlisted)
#   kev-fleet.ps1 --list                   # show resolved targets (os/state) and exit
#   kev-fleet.ps1 --init                   # scaffold the allowlist from the tailnet
#   kev-fleet.ps1 --dry-run [...]          # print what would run; execute nothing
#
# Env: FLEET_HOSTS, TS_BIN (tailscale binary), SSH_OPTS (space-separated).

$ErrorActionPreference = 'Continue'   # per-host failures are handled, not fatal

$FleetHosts = if ($env:FLEET_HOSTS) { $env:FLEET_HOSTS } else { Join-Path $HOME '.claude\fleet-hosts' }
# accept-new = trust a new host's key on first contact (TOFU) but still refuse a
# CHANGED key, so a never-seen fleet host doesn't fail under BatchMode.
$SshOpts = if ($env:SSH_OPTS) {
  $env:SSH_OPTS -split '\s+' | Where-Object { $_ }
} else {
  @('-o','ConnectTimeout=10','-o','BatchMode=yes','-o','StrictHostKeyChecking=accept-new')
}

# ---- locate the tailscale CLI (env, PATH, then the Windows install dir) -----
function Get-TsBin {
  if ($env:TS_BIN) { return $env:TS_BIN }
  $cmd = Get-Command tailscale -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $candidates = @(
    (Join-Path ${env:ProgramFiles} 'Tailscale\tailscale.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Tailscale\tailscale.exe')
  )
  foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
  Write-Error 'tailscale CLI not found (set $env:TS_BIN)'; exit 127
}
function Invoke-Ts { param([string[]]$TsArgs) & (Get-TsBin) @TsArgs }

function Get-Short { param([string]$n)
  if (-not $n) { return '' }
  return ($n.TrimEnd('.') -split '\.')[0].ToLower()
}

# ---- arg parse --------------------------------------------------------------
$mode = 'run'; $dry = $false; $subset = ''; $noSelf = $false
$cmd = @()
$i = 0
while ($i -lt $args.Count) {
  switch ($args[$i]) {
    '--list'    { $mode = 'list'; $i++ }
    '--init'    { $mode = 'init'; $i++ }
    '--dry-run' { $dry = $true; $i++ }
    '--no-self' { $noSelf = $true; $i++ }
    '--hosts'   { $subset = $args[$i+1]; $i += 2 }
    '--'        { if ($i+1 -lt $args.Count) { $cmd = @($args[($i+1)..($args.Count-1)]) }; $i = $args.Count }
    { $_ -in '-h','--help' } {
      Get-Content $PSCommandPath | Select-Object -Skip 1 -First 38 |
        ForEach-Object { $_ -replace '^#\s?','' }
      exit 0
    }
    default {
      Write-Error "unknown arg '$($args[$i])' (did you mean to put the command after '--'?)"; exit 2
    }
  }
}

# ---- --init: scaffold an allowlist from the current tailnet -----------------
if ($mode -eq 'init') {
  $toStdout = Test-Path $FleetHosts
  if ($toStdout) {
    Write-Error "# $FleetHosts already exists - printing candidates to stdout instead:"
  } else {
    New-Item -ItemType Directory -Force -Path (Split-Path $FleetHosts) | Out-Null
  }
  $data = Invoke-Ts @('status','--json') | ConvertFrom-Json
  $lines = @(
    '# kev-fleet allowlist - one ssh target per line (short name / MagicDNS / user@host).'
    '# Only listed hosts are ever touched by /fleet. Uncomment the ones you want.'
    '# Candidates below = online, non-iOS tailnet nodes (excluding this one).'
  )
  if ($data.Peer) {
    foreach ($p in $data.Peer.PSObject.Properties.Value) {
      $os = if ($p.OS) { $p.OS } else { '' }
      if ($os -eq 'iOS' -or -not $p.Online) { continue }
      $lines += "# $($p.HostName)    # $os"
    }
  }
  if ($toStdout) { $lines | ForEach-Object { Write-Output $_ } }
  else {
    Set-Content -Path $FleetHosts -Value $lines -Encoding ascii
    Write-Error "Wrote candidate allowlist to $FleetHosts - edit it (uncomment hosts) before running /fleet."
  }
  exit 0
}

# ---- load + resolve the allowlist -------------------------------------------
if (-not (Test-Path $FleetHosts)) {
  Write-Error "no allowlist at $FleetHosts. Run 'kev-fleet.ps1 --init' to scaffold one."
  exit 1
}

# Resolve each allowlisted host to a row: @{Target; OS; State}
#   State in {ok, offline, self, unknown}
function Resolve-Fleet {
  $data = Invoke-Ts @('status','--json') | ConvertFrom-Json
  $selfHost = $data.Self
  $selfShort = @(@((Get-Short $selfHost.HostName), (Get-Short $selfHost.DNSName)) | Where-Object { $_ })
  $selfOs = if ($selfHost.OS) { $selfHost.OS } else { '' }

  $peers = @{}
  if ($data.Peer) {
    foreach ($p in $data.Peer.PSObject.Properties.Value) {
      $info = @{ os = $(if ($p.OS) { $p.OS } else { '' }); online = [bool]$p.Online }
      foreach ($k in @((Get-Short $p.HostName), (Get-Short $p.DNSName))) {
        if ($k) { $peers[$k] = $info }
      }
    }
  }

  $allow = @()
  foreach ($line in Get-Content $FleetHosts) {
    $clean = ($line -split '#',2)[0].Trim()
    if ($clean) { $allow += $clean }
  }
  $want = $null
  if ($subset) { $want = @($subset -split ',' | ForEach-Object { $_.Trim().ToLower() } | Where-Object { $_ }) }

  $rows = @()
  foreach ($target in $allow) {
    $key = Get-Short (($target -split '@',2)[-1])
    if ($null -ne $want -and ($key -notin $want) -and ($target.ToLower() -notin $want)) { continue }
    if ($key -in $selfShort) {
      $rows += [pscustomobject]@{ Target = $target; OS = $selfOs; State = 'self' }
    } elseif ($peers.ContainsKey($key)) {
      $info = $peers[$key]
      $rows += [pscustomobject]@{ Target = $target; OS = $info.os; State = $(if ($info.online) { 'ok' } else { 'offline' }) }
    } else {
      $rows += [pscustomobject]@{ Target = $target; OS = ''; State = 'unknown' }
    }
  }
  return $rows
}

# @() coerces to an array for 0/1/many rows. NB: do NOT also `return ,$rows` from
# Resolve-Fleet — the comma-wrap plus this @() double-nests the rows into a single
# System.Object[] element, which breaks --list and the run loop on multi-host fleets.
$rows = @(Resolve-Fleet)

# Always include the local node (run directly, no ssh) unless --no-self or a
# --hosts subset was given.
if (-not $noSelf -and -not $subset) {
  $hasSelf = @($rows | Where-Object { $_.State -eq 'self' }).Count -gt 0
  if (-not $hasSelf) {
    $selfRow = [pscustomobject]@{ Target = ($env:COMPUTERNAME).ToLower(); OS = 'local'; State = 'self' }
    $rows = @($selfRow) + $rows
  }
}

if ($rows.Count -eq 0) {
  $msg = "No matching hosts in $FleetHosts"
  if ($subset) { $msg += " (subset: $subset)" }
  Write-Error "$msg."
  exit 1
}

# ---- --list: show what we resolved and stop ---------------------------------
if ($mode -eq 'list') {
  '{0,-28} {1,-8} {2}' -f 'TARGET','OS','STATE'
  foreach ($r in $rows) {
    $o = if ($r.OS) { $r.OS } else { '?' }
    '{0,-28} {1,-8} {2}' -f $r.Target, $o, $r.State
  }
  exit 0
}

# ---- decide the remote command ----------------------------------------------
if ($cmd.Count -eq 0) {
  $remote = 'claude plugin marketplace update kevdunn'
  $action = 'plugin sync (kev@kevdunn)'
} else {
  $remote = ($cmd -join ' ')
  $action = "custom: $remote"
}
Write-Output "Fleet action: $action"

# Build the remote command string. Unix hosts run under a login shell so `claude`
# is on PATH; the remote is single-quoted (with embedded single-quotes escaped) so
# it survives the remote shell's re-parse. Windows hosts get the verbatim command.
function Build-Rexec { param([string]$os, [string]$remoteCmd)
  if ($os -eq 'windows') { return $remoteCmd }
  $escaped = $remoteCmd -replace "'", "'\''"
  return "bash -lc '$escaped'"
}

# ---- run, in parallel, capturing each host's output -------------------------
$jobs = @()
$dryResults = @()
foreach ($r in $rows) {
  $target = $r.Target; $os = $r.OS; $state = $r.State

  if ($state -eq 'self') {
    if ($dry) { $dryResults += [pscustomobject]@{ Target=$target; Kind='DRY'; Text="(local) $remote"; State=$state }; continue }
    $jobs += Start-Job -Name $target -ScriptBlock {
      param($target, $remote)
      $out = (& cmd /c $remote 2>&1 | Out-String); $rc = $LASTEXITCODE
      [pscustomobject]@{ Target=$target; RC=$rc; Output=$out }
    } -ArgumentList $target, $remote
    continue
  }

  if ($state -ne 'ok') {
    $osLabel = if ($os) { $os } else { 'unknown os' }
    $dryResults += [pscustomobject]@{ Target=$target; Kind='skip'; Text="$state ($osLabel)"; State=$state }
    continue
  }

  $rexec = Build-Rexec -os $os -remoteCmd $remote
  if ($dry) {
    $dryResults += [pscustomobject]@{ Target=$target; Kind='DRY'; Text="ssh $($SshOpts -join ' ') $target $rexec"; State=$state }
    continue
  }
  $jobs += Start-Job -Name $target -ScriptBlock {
    param($target, $sshOpts, $rexec)
    $out = (& ssh @sshOpts $target $rexec 2>&1 | Out-String); $rc = $LASTEXITCODE
    [pscustomobject]@{ Target=$target; RC=$rc; Output=$out }
  } -ArgumentList $target, $SshOpts, $rexec
}

$jobResults = @{}
if ($jobs.Count -gt 0) {
  $jobs | Wait-Job | Out-Null
  foreach ($j in $jobs) {
    $res = Receive-Job $j
    if ($res) { $jobResults[$res.Target] = $res }
    Remove-Job $j -Force
  }
}

# ---- report -----------------------------------------------------------------
Write-Output ''
$ok = 0; $bad = 0; $skipped = 0
foreach ($r in $rows) {
  $target = $r.Target
  $label = if ($r.State -eq 'self') { "$target (local)" } else { $target }

  $d = $dryResults | Where-Object { $_.Target -eq $target } | Select-Object -First 1
  if ($d) {
    if ($d.Kind -eq 'skip') { '  [--] {0,-26} {1}' -f $label, $d.Text; $skipped++ }
    elseif ($d.Kind -eq 'DRY') { '  .. {0,-26} would run: {1}' -f $label, $d.Text }
    continue
  }

  if ($jobResults.ContainsKey($target)) {
    $res = $jobResults[$target]
    $rc = $res.RC
    $tail = ($res.Output -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 2)
    if ($rc -eq 0) { '  [OK] {0,-26} ok' -f $label; $ok++ }
    else { '  [XX] {0,-26} exit {1}' -f $label, $rc; $bad++ }
    foreach ($t in $tail) { '      ' + $t }
  }
}
Write-Output ''
if ($dry) { Write-Output '(dry run - nothing executed)'; exit 0 }
Write-Output "Fleet summary: $ok ok, $bad failed, $skipped skipped."
if ($bad -gt 0) { exit 1 } else { exit 0 }
