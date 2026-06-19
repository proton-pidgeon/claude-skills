#!/usr/bin/env bash
#
# kev-host.sh — report THIS host's identity + light stats, then probe Tailscale
# reachability from here to every OTHER host in the fleet allowlist. Backs the
# /host skill. Read-only: it inspects the local machine and sends tailscale
# pings; it changes nothing.
#
# Identity:  hostname, Tailscale name + IP, OS + version, arch, current user.
# Stats:     uptime, load average, CPU count, memory used/total, root-disk used/total.
# Reach:     for each allowlisted peer (≠ self), `tailscale ping` it and report
#            reachable (direct/relay + latency) or not, annotated with the
#            tailnet's own online/offline view. Hosts the coordinator marks
#            offline are reported without a (pointless, slow) ping.
#
# Allowlist: $FLEET_HOSTS (default ~/.claude/fleet-hosts) — same file /fleet uses,
#            one target per line (short name / MagicDNS / user@host); '#' comments
#            and blanks ignored. No allowlist → the reachability section is skipped.
#
# Env: FLEET_HOSTS, TS_BIN (tailscale binary), PING_TIMEOUT (default 5s).

set -uo pipefail

FLEET_HOSTS="${FLEET_HOSTS:-$HOME/.claude/fleet-hosts}"
PING_TIMEOUT="${PING_TIMEOUT:-5s}"

# Locate the tailscale CLI (PATH, then the macOS app bundle). Empty = not found.
TS_RESOLVED=""
ts() {
  if [[ -z "$TS_RESOLVED" ]]; then
    if [[ -n "${TS_BIN:-}" ]]; then TS_RESOLVED="$TS_BIN"
    elif command -v tailscale >/dev/null 2>&1; then TS_RESOLVED="tailscale"
    elif [[ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]]; then
      TS_RESOLVED="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    else return 127; fi
  fi
  "$TS_RESOLVED" "$@"
}

# Human-format a byte count as GiB (one decimal).
gib() { awk -v b="${1:-0}" 'BEGIN{ printf "%.1f", b/1073741824 }'; }
pct() { awk -v a="${1:-0}" -v b="${2:-1}" 'BEGIN{ if(b<=0){print "?"}else{printf "%d", (a/b)*100} }'; }
# Format a duration in seconds as "Nd Hh Mm".
fmt_dur() {
  local s="${1:-0}" d h m
  d=$(( s/86400 )); s=$(( s%86400 )); h=$(( s/3600 )); s=$(( s%3600 )); m=$(( s/60 ))
  local out=""
  (( d > 0 )) && out+="${d}d "
  out+="${h}h ${m}m"
  printf '%s' "$out"
}

uname_s="$(uname -s 2>/dev/null || echo unknown)"
host_short="$(hostname -s 2>/dev/null || hostname 2>/dev/null || echo '?')"
cur_user="${USER:-$(id -un 2>/dev/null || echo '?')}"
arch="$(uname -m 2>/dev/null || echo '?')"

# ---- Tailscale identity ----------------------------------------------------
ts_self="(tailscale CLI not found)"; ts_ip=""
ts_status_json=""
if ts_status_json="$(ts status --json 2>/dev/null)"; then
  ts_self="$(printf '%s' "$ts_status_json" | python3 -c '
import sys, json
d = json.load(sys.stdin); s = d.get("Self") or {}
print((s.get("DNSName","") or s.get("HostName","") or "").rstrip(".").split(".")[0] or "?")
' 2>/dev/null || echo '?')"
  ts_ip="$(ts ip -4 2>/dev/null | head -1)"
fi

# ---- OS / stats (per platform) ---------------------------------------------
os_name="?"; uptime_s=0; load="?"; ncpu="?"
mem_used=0; mem_total=0; disk_used=0; disk_total=0
now="$(date +%s)"

if [[ "$uname_s" == "Darwin" ]]; then
  os_name="$(sw_vers -productName 2>/dev/null || echo macOS) $(sw_vers -productVersion 2>/dev/null) (Darwin $(uname -r 2>/dev/null))"
  ncpu="$(sysctl -n hw.ncpu 2>/dev/null || echo '?')"
  load="$(sysctl -n vm.loadavg 2>/dev/null | tr -d '{}' | awk '{printf "%s %s %s", $1,$2,$3}')"
  boot="$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/{ sec = \([0-9][0-9]*\).*/\1/p')"
  [[ -n "$boot" ]] && uptime_s=$(( now - boot ))
  mem_total="$(sysctl -n hw.memsize 2>/dev/null || echo 0)"
  # used ≈ (active + wired + compressed) pages * pagesize
  pagesize="$(sysctl -n hw.pagesize 2>/dev/null || echo 4096)"
  mem_used="$(vm_stat 2>/dev/null | awk -v ps="$pagesize" '
    /Pages active/      {gsub(/\./,"",$3); a=$3}
    /Pages wired/       {gsub(/\./,"",$4); w=$4}
    /Pages occupied by compressor/ {gsub(/\./,"",$5); c=$5}
    END{ printf "%d", (a+w+c)*ps }')"
elif [[ "$uname_s" == "Linux" ]]; then
  if [[ -r /etc/os-release ]]; then
    os_name="$(. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Linux} (kernel $(uname -r))")"
  else os_name="Linux (kernel $(uname -r 2>/dev/null))"; fi
  ncpu="$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo '?')"
  load="$(cut -d' ' -f1-3 /proc/loadavg 2>/dev/null || echo '?')"
  uptime_s="$(awk '{printf "%d", $1}' /proc/uptime 2>/dev/null || echo 0)"
  mem_total="$(awk '/MemTotal/{printf "%d", $2*1024}' /proc/meminfo 2>/dev/null || echo 0)"
  mem_avail="$(awk '/MemAvailable/{printf "%d", $2*1024}' /proc/meminfo 2>/dev/null || echo 0)"
  mem_used=$(( mem_total - mem_avail ))
else
  os_name="$uname_s (uname -r $(uname -r 2>/dev/null))"
fi

# Disk usage (POSIX df -k). On macOS the sealed system volume is mounted at / and
# only ~12 GB — the meaningful figure is the Data volume, so prefer it when present.
disk_path="/"
[[ "$uname_s" == "Darwin" && -d /System/Volumes/Data ]] && disk_path="/System/Volumes/Data"
read -r disk_total disk_used <<<"$(df -k "$disk_path" 2>/dev/null | awk 'NR==2{printf "%d %d", $2*1024, $3*1024}')"
disk_total="${disk_total:-0}"; disk_used="${disk_used:-0}"

# ---- print identity + stats ------------------------------------------------
printf '\n%s\n' "HOST — ${host_short}"
printf '\n%s\n' "Identity"
printf '  %-12s %s\n' "Hostname"  "$host_short"
printf '  %-12s %s\n' "Tailscale" "${ts_self}${ts_ip:+  ($ts_ip)}"
printf '  %-12s %s\n' "OS"        "$os_name  $arch"
printf '  %-12s %s\n' "User"      "$cur_user"

printf '\n%s\n' "Stats"
printf '  %-12s %s\n' "Uptime" "$(fmt_dur "$uptime_s")"
printf '  %-12s %s  (%s CPUs)\n' "Load" "$load" "$ncpu"
if (( mem_total > 0 )); then
  printf '  %-12s %s / %s GiB  (%s%%)\n' "Memory" "$(gib "$mem_used")" "$(gib "$mem_total")" "$(pct "$mem_used" "$mem_total")"
else
  printf '  %-12s %s\n' "Memory" "(unavailable)"
fi
if (( disk_total > 0 )); then
  printf '  %-12s %s / %s GiB  (%s%%)  %s\n' "Disk" "$(gib "$disk_used")" "$(gib "$disk_total")" "$(pct "$disk_used" "$disk_total")" "$disk_path"
fi

# ---- reachability to the other fleet hosts ---------------------------------
printf '\n%s\n' "Reachability  (from $host_short)"

if [[ "$ts_self" == "(tailscale CLI not found)" ]]; then
  printf '  %s\n' "⚠ tailscale CLI not found — cannot probe peers (set TS_BIN)."
  echo; exit 0
fi
if [[ ! -f "$FLEET_HOSTS" ]]; then
  printf '  %s\n' "no fleet allowlist at $FLEET_HOSTS — skipping peer checks (run /fleet --init)."
  echo; exit 0
fi

# Resolve allowlisted peers (excluding self) with the tailnet's online view.
# NB: pass the status JSON via a temp file, not stdin — the heredoc IS stdin here.
ts_json_tmp="$(mktemp)"; printf '%s' "$ts_status_json" > "$ts_json_tmp"
peers="$(python3 - "$ts_json_tmp" "$FLEET_HOSTS" <<'PY'
import sys, json
data = json.load(open(sys.argv[1])); allowfile = sys.argv[2]
def short(n): return (n or "").rstrip(".").split(".")[0].lower()
self_short = {short((data.get("Self") or {}).get("HostName")),
              short((data.get("Self") or {}).get("DNSName"))}
peers = {}
for p in (data.get("Peer") or {}).values():
    online = bool(p.get("Online"))
    for k in (short(p.get("HostName")), short(p.get("DNSName"))):
        if k: peers[k] = online
for line in open(allowfile):
    line = line.split("#", 1)[0].strip()
    if not line: continue
    key = short(line.split("@", 1)[-1])
    if key in self_short: continue
    if key in peers:   state = "online" if peers[key] else "offline"
    else:              state = "unknown"
    print(f"{key}\t{state}")
PY
)"
rm -f "$ts_json_tmp"

if [[ -z "${peers//[$'\t\n ']/}" ]]; then
  printf '  %s\n' "no other hosts in the allowlist."
  echo; exit 0
fi

reach_ok=0; reach_bad=0
while IFS=$'\t' read -r key state; do
  [[ -z "$key" ]] && continue
  if [[ "$state" == "offline" ]]; then
    printf '  ❌ %-24s offline (per tailnet) — not probed\n' "$key"; ((reach_bad++)); continue
  fi
  out="$(ts ping --c 1 --until-direct=false --timeout "$PING_TIMEOUT" "$key" 2>&1)"
  if printf '%s' "$out" | grep -q "pong"; then
    lat="$(printf '%s' "$out" | grep -oE 'in [0-9.]+ms' | head -1)"
    if printf '%s' "$out" | grep -qi "DERP"; then path="relay"; else path="direct"; fi
    note=""; [[ "$state" == "unknown" ]] && note="  [not in tailnet status]"
    printf '  ✅ %-24s pong %s %s%s\n' "$key" "$path" "${lat:-?}" "$note"; ((reach_ok++))
  else
    printf '  ❌ %-24s unreachable (%s)\n' "$key" "$(printf '%s' "$out" | tail -1 | cut -c1-50)"; ((reach_bad++))
  fi
done <<<"$peers"

printf '\n%s\n' "Reachable: ${reach_ok} ok, ${reach_bad} unreachable."
exit 0
