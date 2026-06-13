#!/usr/bin/env bash
#
# kev-fleet.sh — run a command across a curated fleet of Tailscale hosts, in
# parallel, with per-host OS detection and an aggregated report. Backs the
# /fleet skill.
#
# Default action (no command given): sync the kev@kevdunn plugin on every host —
#   claude plugin marketplace update kevdunn   (git-pull the marketplace)
#   claude plugin update kev@kevdunn            (bump the installed plugin)
# so a plugin/skill change made on one host reaches all the others without
# visiting each. (A running Claude session on the host applies it next restart.)
#
# SAFETY: only hosts in the allowlist file are ever touched. The allowlist is
# $FLEET_HOSTS (default ~/.claude/fleet-hosts): one ssh target per line (a short
# Tailscale name, a MagicDNS name, or user@host); '#' comments and blank lines
# ignored. The local node and any offline host are skipped with a note.
#
# OS per host is read from `tailscale status --json`. Unix hosts (macOS/Linux)
# run the command under a login shell (`bash -lc`) so `claude` is on PATH;
# Windows hosts run it via their default Tailscale-SSH shell.
#
# Usage:
#   kev-fleet.sh                       # plugin sync on every allowlisted host
#   kev-fleet.sh -- <command...>       # run an arbitrary command on every host
#   kev-fleet.sh --hosts a,b -- <cmd>  # restrict to a subset (must be allowlisted)
#   kev-fleet.sh --list                # show resolved targets (os/state) and exit
#   kev-fleet.sh --init                # scaffold the allowlist from the tailnet
#   kev-fleet.sh --dry-run [...]       # print what would run; execute nothing
#
# Env: FLEET_HOSTS, TS_BIN (tailscale binary), SSH_OPTS.

set -uo pipefail   # deliberately NOT -e: per-host failures are handled, not fatal

FLEET_HOSTS="${FLEET_HOSTS:-$HOME/.claude/fleet-hosts}"
# accept-new = trust a new host's key on first contact (TOFU) but still refuse a
# CHANGED key — so a never-seen fleet host doesn't fail with "Host key
# verification failed" under BatchMode, while key-swap MITM is still caught.
SSH_OPTS="${SSH_OPTS:--o ConnectTimeout=10 -o BatchMode=yes -o StrictHostKeyChecking=accept-new}"

# Locate the tailscale CLI (PATH, then the macOS app bundle).
ts() {
  local bin="${TS_BIN:-}"
  if [[ -z "$bin" ]]; then
    if command -v tailscale >/dev/null 2>&1; then bin="tailscale"
    elif [[ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]]; then
      bin="/Applications/Tailscale.app/Contents/MacOS/Tailscale"
    else echo "ERROR: tailscale CLI not found (set TS_BIN)" >&2; return 127; fi
  fi
  "$bin" "$@"
}

# ---- arg parse ------------------------------------------------------------
mode="run"; dry=0; subset=""; no_self=0
cmd=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --list)    mode="list"; shift ;;
    --init)    mode="init"; shift ;;
    --dry-run) dry=1; shift ;;
    --no-self) no_self=1; shift ;;
    --hosts)   subset="$2"; shift 2 ;;
    --)        shift; cmd=("$@"); break ;;
    -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "ERROR: unknown arg '$1' (did you mean to put the command after '--'?)" >&2; exit 2 ;;
  esac
done

# ---- --init: scaffold an allowlist from the current tailnet ---------------
if [[ "$mode" == "init" ]]; then
  if [[ -f "$FLEET_HOSTS" ]]; then
    echo "# $FLEET_HOSTS already exists — printing candidates to stdout instead:" >&2
    dest="/dev/stdout"
  else
    mkdir -p "$(dirname "$FLEET_HOSTS")"; dest="$FLEET_HOSTS"
  fi
  tjson="$(mktemp)"; ts status --json > "$tjson" 2>/dev/null
  candidates="$(python3 - "$tjson" <<'PY'
import sys, json
d = json.load(open(sys.argv[1]))
for p in (d.get("Peer") or {}).values():
    os_ = p.get("OS", "") or ""
    if os_ == "iOS" or not p.get("Online"): continue
    print(f"# {p.get('HostName','')}    # {os_}")
PY
)"
  rm -f "$tjson"
  {
    echo "# kev-fleet allowlist — one ssh target per line (short name / MagicDNS / user@host)."
    echo "# Only listed hosts are ever touched by /fleet. Uncomment the ones you want."
    echo "# Candidates below = online, non-iOS tailnet nodes (excluding this one)."
    printf '%s\n' "$candidates"
  } > "$dest"
  [[ "$dest" != "/dev/stdout" ]] && echo "Wrote candidate allowlist to $FLEET_HOSTS — edit it (uncomment hosts) before running /fleet." >&2
  exit 0
fi

# ---- load + resolve the allowlist -----------------------------------------
if [[ ! -f "$FLEET_HOSTS" ]]; then
  echo "ERROR: no allowlist at $FLEET_HOSTS. Run 'kev-fleet.sh --init' to scaffold one." >&2
  exit 1
fi

# Emit one TSV row per allowlisted host: target<TAB>os<TAB>state
#   state ∈ {ok, offline, self, unknown}
resolve() {
  local tjson; tjson="$(mktemp)"; ts status --json > "$tjson" 2>/dev/null
  python3 - "$tjson" "$FLEET_HOSTS" "$subset" <<'PY'
import sys, json
data = json.load(open(sys.argv[1]))
allowfile, subset = sys.argv[2], (sys.argv[3] if len(sys.argv) > 3 else "")
def short(n): return (n or "").rstrip(".").split(".")[0].lower()
self_short = {short((data.get("Self") or {}).get("HostName")),
              short((data.get("Self") or {}).get("DNSName"))}
self_os = (data.get("Self") or {}).get("OS","") or ""
peers = {}
for p in (data.get("Peer") or {}).values():
    info = {"os": p.get("OS","") or "", "online": bool(p.get("Online"))}
    for k in (short(p.get("HostName")), short(p.get("DNSName"))):
        if k: peers[k] = info
allow = []
for line in open(allowfile):
    line = line.split("#", 1)[0].strip()
    if line: allow.append(line)
want = {h.strip().lower() for h in subset.split(",") if h.strip()} if subset else None
for target in allow:
    key = short(target.split("@", 1)[-1])
    if want is not None and key not in want and target.lower() not in want:
        continue
    if key in self_short:
        print(f"{target}\t{self_os}\tself")
    elif key in peers:
        i = peers[key]
        print(f"{target}\t{i['os']}\t{'ok' if i['online'] else 'offline'}")
    else:
        print(f"{target}\t\tunknown")
PY
  rm -f "$tjson"
}

mapfile -t rows < <(resolve)

# Always include the local node (run directly, no ssh) unless --no-self or a
# --hosts subset was given. If the allowlist already resolved a self row, keep
# it; otherwise inject one so /fleet updates this machine too.
if [[ "$no_self" != "1" && -z "$subset" ]]; then
  has_self=0
  if [[ ${#rows[@]} -gt 0 ]]; then
    for r in "${rows[@]}"; do IFS=$'\t' read -r _t _o s <<<"$r"; [[ "${s:-}" == "self" ]] && has_self=1; done
  fi
  if [[ "$has_self" == "0" ]]; then
    selfrow="$(printf '%s\tlocal\tself' "$(hostname -s)")"
    if [[ ${#rows[@]} -gt 0 ]]; then rows=( "$selfrow" "${rows[@]}" ); else rows=( "$selfrow" ); fi
  fi
fi

if [[ ${#rows[@]} -eq 0 ]]; then
  echo "No matching hosts in $FLEET_HOSTS${subset:+ (subset: $subset)}." >&2
  exit 1
fi

# ---- --list: show what we resolved and stop -------------------------------
if [[ "$mode" == "list" ]]; then
  printf '%-28s %-8s %s\n' "TARGET" "OS" "STATE"
  for r in "${rows[@]}"; do IFS=$'\t' read -r t o s <<<"$r"; printf '%-28s %-8s %s\n' "$t" "${o:-?}" "$s"; done
  exit 0
fi

# ---- decide the remote command --------------------------------------------
# Default action = a single plugin-sync command (no shell operators, so it runs
# under any remote shell — incl. older Windows PowerShell). 'marketplace update'
# git-pulls the marketplace AND bumps the installed plugin; the host applies it
# on its next Claude restart. Otherwise the verbatim command after '--'.
if [[ ${#cmd[@]} -eq 0 ]]; then
  remote='claude plugin marketplace update kevdunn'
  action="plugin sync (kev@kevdunn)"
else
  remote="${cmd[*]}"
  action="custom: $remote"
fi
echo "Fleet action — $action"

# ssh flattens its command args into ONE string for the remote shell, so we must
# pre-quote. Unix hosts run under a login shell (bash -lc) so `claude` is on PATH;
# %q makes the command survive the remote shell's re-parse as a single argument.
build_rexec() {   # $1 = os ; reads $remote ; echoes the remote command string
  if [[ "$1" == "windows" ]]; then printf '%s' "$remote"
  else printf 'bash -lc %q' "$remote"; fi
}

# ---- run, in parallel, capturing each host's output -----------------------
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
launched=()
for r in "${rows[@]}"; do
  IFS=$'\t' read -r target os state <<<"$r"

  # Local node: run the command directly, no ssh.
  if [[ "$state" == "self" ]]; then
    if [[ "$dry" == "1" ]]; then
      printf 'DRY\t%s\t(local) %s\n' "$target" "$remote" > "$tmp/$target.res"; continue
    fi
    ( out="$(bash -lc "$remote" 2>&1)"; rc=$?
      { printf 'done\t%s\t%s\t' "$target" "$rc"
        printf '%s' "$out" | tr '\n' '\037'; printf '\n'; } > "$tmp/$target.res"
    ) &
    launched+=("$!"); continue
  fi

  if [[ "$state" != "ok" ]]; then
    printf 'skip\t%s\t%s (%s)\n' "$target" "$state" "${os:-unknown os}" > "$tmp/$target.res"
    continue
  fi
  rexec="$(build_rexec "$os")"
  if [[ "$dry" == "1" ]]; then
    printf 'DRY\t%s\tssh %s %s %s\n' "$target" "$SSH_OPTS" "$target" "$rexec" > "$tmp/$target.res"
    continue
  fi
  ( out="$(ssh $SSH_OPTS "$target" "$rexec" 2>&1)"; rc=$?
    { printf 'done\t%s\t%s\t' "$target" "$rc"
      printf '%s' "$out" | tr '\n' '\037'   # fold newlines so it's one record
      printf '\n'; } > "$tmp/$target.res"
  ) &
  launched+=("$!")
done
for pid in "${launched[@]:-}"; do [[ -n "$pid" ]] && wait "$pid" 2>/dev/null; done

# ---- report ---------------------------------------------------------------
echo
ok=0; bad=0; skipped=0
for r in "${rows[@]}"; do
  IFS=$'\t' read -r target _os _state <<<"$r"
  res="$tmp/$target.res"; [[ -f "$res" ]] || continue
  label="$target"; [[ "${_state:-}" == "self" ]] && label="$target (local)"
  kind="$(cut -f1 "$res")"
  case "$kind" in
    skip) printf '  ⚪ %-26s %s\n' "$label" "$(cut -f3 "$res")"; ((skipped++)) ;;
    DRY)  printf '  · %-26s would run: %s\n' "$label" "$(cut -f3 "$res")" ;;
    done)
      rc="$(cut -f3 "$res")"
      body="$(cut -f4- "$res" | tr '\037' '\n')"
      tail3="$(printf '%s' "$body" | grep -v '^[[:space:]]*$' | tail -n 2 | sed 's/^/      /')"
      if [[ "$rc" == "0" ]]; then printf '  ✅ %-26s ok\n' "$label"; ((ok++))
      else printf '  ❌ %-26s exit %s\n' "$label" "$rc"; ((bad++)); fi
      [[ -n "$tail3" ]] && printf '%s\n' "$tail3"
      ;;
  esac
done
echo
[[ "$dry" == "1" ]] && { echo "(dry run — nothing executed)"; exit 0; }
echo "Fleet summary: ${ok} ok, ${bad} failed, ${skipped} skipped."
[[ "$bad" -gt 0 ]] && exit 1 || exit 0
