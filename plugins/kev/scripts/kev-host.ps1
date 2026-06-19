<#
  kev-host.ps1 - report THIS host's identity + light stats, then probe Tailscale
  reachability from here to every OTHER host in the fleet allowlist. Windows port of
  kev-host.sh, behaviour-for-behaviour. Backs the /host skill on native Windows.

  Read-only: inspects the local machine and sends tailscale pings; changes nothing.

  Identity:  hostname, Tailscale name + IP, OS + version, arch, current user.
  Stats:     uptime, CPU load %, logical CPU count, memory used/total, system-drive used/total.
  Reach:     for each allowlisted peer (<> self), `tailscale ping` it and report reachable
             (direct/relay + latency) or not, annotated with the tailnet online/offline view.

  Allowlist: $env:FLEET_HOSTS (default ~/.claude/fleet-hosts) - same file /fleet uses.
  Env: FLEET_HOSTS, TS_BIN (tailscale.exe), PING_TIMEOUT (default 5s).
#>

$ErrorActionPreference = 'SilentlyContinue'

$FleetHosts  = if ($env:FLEET_HOSTS) { $env:FLEET_HOSTS } else { Join-Path $HOME '.claude\fleet-hosts' }
$PingTimeout = if ($env:PING_TIMEOUT) { $env:PING_TIMEOUT } else { '5s' }

# Locate tailscale.exe: TS_BIN, then PATH, then the default install dir.
$TsBin = $null
if ($env:TS_BIN) { $TsBin = $env:TS_BIN }
elseif (Get-Command tailscale -ErrorAction SilentlyContinue) { $TsBin = 'tailscale' }
elseif (Test-Path "$env:ProgramFiles\Tailscale\tailscale.exe") { $TsBin = "$env:ProgramFiles\Tailscale\tailscale.exe" }
function Ts { if ($TsBin) { & $TsBin @args } }

function Gib([double]$bytes) { '{0:N1}' -f ($bytes / 1GB) }
function Pct([double]$a, [double]$b) { if ($b -le 0) { '?' } else { '{0:N0}' -f (($a / $b) * 100) } }
function FmtDur([timespan]$t) {
  $out = ''
  if ($t.Days -gt 0) { $out += "$($t.Days)d " }
  $out += "$($t.Hours)h $($t.Minutes)m"; $out
}

$hostShort = $env:COMPUTERNAME
$curUser   = $env:USERNAME
$arch      = $env:PROCESSOR_ARCHITECTURE

# ---- Tailscale identity ----------------------------------------------------
$tsSelf = '(tailscale CLI not found)'; $tsIp = ''; $tsStatus = $null
if ($TsBin) {
  $raw = Ts status --json 2>$null
  if ($raw) {
    try { $tsStatus = $raw | ConvertFrom-Json } catch { $tsStatus = $null }
    if ($tsStatus) {
      $dns = $tsStatus.Self.DNSName; if (-not $dns) { $dns = $tsStatus.Self.HostName }
      $tsSelf = ($dns -replace '\.$','').Split('.')[0]
      if (-not $tsSelf) { $tsSelf = '?' }
    }
  }
  $tsIp = (Ts ip -4 2>$null | Select-Object -First 1)
}

# ---- OS / stats ------------------------------------------------------------
$os   = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
$cs   = Get-CimInstance Win32_ComputerSystem  -ErrorAction SilentlyContinue
$osName  = if ($os) { "$($os.Caption) (build $($os.Version))" } else { 'Windows' }
$ncpu    = if ($cs) { $cs.NumberOfLogicalProcessors } else { '?' }
$uptime  = if ($os) { (Get-Date) - $os.LastBootUpTime } else { [timespan]::Zero }
$cpuLoad = (Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue |
            Measure-Object -Property LoadPercentage -Average).Average
$memTotal = if ($os) { $os.TotalVisibleMemorySize * 1KB } else { 0 }
$memFree  = if ($os) { $os.FreePhysicalMemory   * 1KB } else { 0 }
$memUsed  = $memTotal - $memFree

$sysDrive = ($env:SystemDrive)  # e.g. 'C:'
$disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$sysDrive'" -ErrorAction SilentlyContinue
$diskTotal = if ($disk) { [double]$disk.Size } else { 0 }
$diskUsed  = if ($disk) { [double]$disk.Size - [double]$disk.FreeSpace } else { 0 }

# ---- print identity + stats ------------------------------------------------
"`nHOST - $hostShort`n"
"Identity"
"  {0,-12} {1}" -f 'Hostname',  $hostShort
"  {0,-12} {1}" -f 'Tailscale', ($tsSelf + $(if ($tsIp) { "  ($tsIp)" } else { '' }))
"  {0,-12} {1}" -f 'OS',        "$osName  $arch"
"  {0,-12} {1}" -f 'User',      $curUser
"`nStats"
"  {0,-12} {1}" -f 'Uptime', (FmtDur $uptime)
"  {0,-12} {1}%  ({2} CPUs)" -f 'CPU load', $(if ($null -ne $cpuLoad) { [int]$cpuLoad } else { '?' }), $ncpu
if ($memTotal -gt 0) {
  "  {0,-12} {1} / {2} GiB  ({3}%)" -f 'Memory', (Gib $memUsed), (Gib $memTotal), (Pct $memUsed $memTotal)
} else { "  {0,-12} {1}" -f 'Memory', '(unavailable)' }
if ($diskTotal -gt 0) {
  "  {0,-12} {1} / {2} GiB  ({3}%)  {4}" -f 'Disk', (Gib $diskUsed), (Gib $diskTotal), (Pct $diskUsed $diskTotal), $sysDrive
}

# ---- reachability to the other fleet hosts ---------------------------------
"`nReachability  (from $hostShort)"
if (-not $TsBin) { "  WARNING tailscale CLI not found - cannot probe peers (set TS_BIN).`n"; return }
if (-not (Test-Path $FleetHosts)) { "  no fleet allowlist at $FleetHosts - skipping peer checks (run /fleet --init).`n"; return }

function Short([string]$n) { if (-not $n) { '' } else { ($n -replace '\.$','').Split('.')[0].ToLower() } }

# tailnet online view, keyed by short name
$peerOnline = @{}
$selfShort  = @( (Short $tsStatus.Self.HostName), (Short $tsStatus.Self.DNSName) )
if ($tsStatus -and $tsStatus.Peer) {
  foreach ($p in $tsStatus.Peer.PSObject.Properties.Value) {
    foreach ($k in @((Short $p.HostName), (Short $p.DNSName))) {
      if ($k) { $peerOnline[$k] = [bool]$p.Online }
    }
  }
}

$okN = 0; $badN = 0
foreach ($line in Get-Content $FleetHosts) {
  $t = ($line -split '#',2)[0].Trim()
  if (-not $t) { continue }
  $key = Short ($t -split '@',2)[-1]
  if ($selfShort -contains $key) { continue }

  if ($peerOnline.ContainsKey($key) -and -not $peerOnline[$key]) {
    "  XX  {0,-24} offline (per tailnet) - not probed" -f $key; $badN++; continue
  }
  $state = if ($peerOnline.ContainsKey($key)) { 'online' } else { 'unknown' }
  $out = (Ts ping --c 1 --until-direct=false --timeout $PingTimeout $key 2>&1) -join "`n"
  if ($out -match 'pong') {
    $lat  = if ($out -match 'in ([0-9.]+ms)') { $matches[1] } else { '?' }
    $path = if ($out -match 'DERP') { 'relay' } else { 'direct' }
    $note = if ($state -eq 'unknown') { '  [not in tailnet status]' } else { '' }
    "  OK  {0,-24} pong $path in $lat$note" -f $key; $okN++
  } else {
    $tail = ($out -split "`n" | Select-Object -Last 1)
    "  XX  {0,-24} unreachable ($($tail.Substring(0,[Math]::Min(50,$tail.Length))))" -f $key; $badN++
  }
}
"`nReachable: $okN ok, $badN unreachable."
