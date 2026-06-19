---
name: host
description: Report the host the current Claude session is running on — its identity (hostname, Tailscale name + IP, OS/version, arch, user), light system stats (uptime, load, CPU count, memory used/total, disk used/total), and a Tailscale reachability probe from here to every OTHER host in the fleet allowlist (direct/relay + latency, or unreachable). Use when the user runs `/host`, or asks "which host am I on", "where is this running", "what machine is this", "stats for this box", "can this host reach my other machines", or "is <host> reachable from here". Local CLI/Desktop only; reachability needs Tailscale. Read-only — inspects the local machine and sends tailscale pings, changes nothing.
---

# /host — who am I, how am I doing, and who can I reach

Answer three things about the machine this Claude session is running on, in one shot:

1. **Identity** — hostname, Tailscale name + IP, OS + version, architecture, current user.
2. **Light stats** — uptime, load average, CPU count, memory used/total, root-disk used/total.
3. **Reachability** — from *this* node, `tailscale ping` every *other* host in the fleet
   allowlist and report whether it answers (direct vs. relay path + latency) or not,
   annotated with the tailnet coordinator's own online/offline view.

It's backed by `kev-host.sh` (macOS/Linux) and `kev-host.ps1` (Windows) — behaviour-for-
behaviour ports that gather the same fields and emit the same report. The script is
**read-only**: it inspects the local machine and sends tailscale pings; it changes nothing.

## How to invoke

Pick the implementation by the OS of the host you're on (this skill runs *locally*, on
whatever machine the session is on — it does not ssh anywhere to gather stats):

```
# macOS / Linux (or Windows with Git Bash on PATH):
bash ~/.claude/plugins/marketplaces/kevdunn/plugins/kev/scripts/kev-host.sh
# native Windows (no bash):
powershell -File ~\.claude\plugins\marketplaces\kevdunn\plugins\kev\scripts\kev-host.ps1
```

macOS ships bash 3.2 but the script needs no bash-4 features, so the system `bash` is fine
(no need for Homebrew bash). Just run it and relay the report. No arguments.

## What it reads

- **Tailscale**: `tailscale status --json` for identity + each peer's online state, and
  `tailscale ping` for the actual node-to-node probe. The script finds the CLI on `PATH`,
  then the macOS app bundle (`/Applications/Tailscale.app/...`); override with `TS_BIN`.
- **Fleet allowlist**: the same `~/.claude/fleet-hosts` file `/fleet` uses (one target per
  line; `#` comments and blanks ignored). The reachability section probes every uncommented
  entry that isn't this host. No allowlist → that section is skipped with a hint to run
  `/fleet --init`.

## Reading the reachability lines

- `✅ <host>  pong direct 79ms` — reachable over a direct Tailscale path.
- `✅ <host>  pong relay 120ms` — reachable, but only via a DERP relay (no direct path;
  usually NAT/firewall between the two nodes — works, just higher latency).
- `❌ <host>  offline (per tailnet) — not probed` — the coordinator marks it offline, so the
  script skips the (slow, pointless) ping. The host is down or off the tailnet.
- `❌ <host>  unreachable (...)` — the coordinator thinks it's online but the ping from
  *here* failed within the timeout (`PING_TIMEOUT`, default 5s) — a real path problem
  between this node and that one.

A `[not in tailnet status]` note means the allowlist names a host the coordinator doesn't
currently see as a peer (renamed/expired key), yet it still answered a ping.

## When to reach for it

- The user is on one of several machines (Mac Studio, the Windows boxes) and asks **which
  one** this session is on, or wants a quick health read of it.
- Diagnosing fleet connectivity from a *specific* node's perspective — `/host` probes
  outward from where it runs, which `/fleet --list` (coordinator's view) does not.

## Distribution

Ships in the `kev` plugin of `proton-pidgeon/claude-skills` (marketplace `kevdunn`); reaches
other hosts on `claude plugin marketplace update kevdunn` (+ restart) — i.e. via `/fleet`.
The allowlist (`~/.claude/fleet-hosts`) is per-user config, not plugin code, so it is not
synced by the plugin; each host has its own. See `[[claude-sync-architecture]]`.
