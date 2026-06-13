---
name: daemonize
description: Install and verify durable user LaunchAgents that keep a home-Mac service running while logged in — following Kev's convention of a `com.<svc>.service` agent (RunAtLoad + KeepAlive) plus, for Peggy-fronted services, a paired `com.peggy.register.<svc>` agent. Use when the user runs `/daemonize`, or asks to "make this service start at login / survive logout", "install a LaunchAgent for this", "keep this app running", "set up the launchd plist", or "persist this service". Local macOS only; uses user agents (no sudo), loads them, and verifies the service is actually serving and survives a restart.
---

# /daemonize — install & verify a durable LaunchAgent (pair) for a home service

Take a service in the current working directory from "I run it by hand" to "it's up
whenever I'm logged in, and re-registers with Peggy on its own." The deliverable: the
LaunchAgent plist(s) written to `~/Library/LaunchAgents`, loaded, and **verified actually
serving** — not just "the file exists."

This mirrors the persistence pattern used across Kev's stack (`[[peggy-gateway]]`): a pair
of **user** LaunchAgents matching an app's "up while logged in" lifecycle — `com.<svc>.service`
runs the app, `com.peggy.register.<svc>` runs `peggy register`. User agents need no sudo
(unlike a system LaunchDaemon).

## Operating rules

- **User agents, not system daemons.** Write to `~/Library/LaunchAgents`; load into the
  per-user GUI domain (`gui/$(id -u)`). No sudo. (The WireGuard tunnel is the one exception
  — it's a system daemon, out of scope here.)
- **Verify it serves, not just loads.** A loaded agent that crash-loops or binds the wrong
  address is still broken. Confirm the process is up, the port is listening, and — for Peggy
  — `peggy list` shows it.
- **Don't kickstart blindly over in-flight work.** `kickstart -k` kills whatever the agent
  is currently running. If the service could be mid-task (e.g. a long pipeline run), check
  before restarting or warn the user. `[[agora-restart-check-active-run]]`.
- **Single-line commands only** — no `\` continuations or heredocs in commands the user runs.

## Step 1 — Gather the facts

Determine, from the repo / the user / `[[peggy-gateway]]` conventions:

- **Service slug** `<svc>` (kebab-case; usually the repo name).
- **Launch command** — the exact argv that runs the service (absolute paths; e.g. a venv
  binary, `node dist/server.js`, a `uv run …`). Prefer the real binary over a wrapper when
  possible — uv/script wrappers can orphan their child on restart, leaving a stale process
  holding the port (`[[stoa-engine-orphan-restart]]`).
- **Working directory**, and any **environment** the service needs. LaunchAgents do **not**
  inherit your shell env or `.env` — pass required vars via `EnvironmentVariables` (or have
  the program load its own `.env`). Note offline/cache flags the service needs (e.g.
  `HF_HUB_OFFLINE=1` for MLX services that wedge on Hub checks).
- **Port** and whether the service must bind the **home 6PN address** (Peggy requirement —
  never `0.0.0.0`).
- **Peggy-fronted?** If it's reachable through the gateway, it also needs the
  `com.peggy.register.<svc>` agent (`peggy register <name> <port>` / the project's register
  command). If it's local-only, skip that half.

## Step 2 — Write the plist(s)

Write `~/Library/LaunchAgents/com.<svc>.service.plist` with: `Label`, `ProgramArguments`
(absolute argv), `WorkingDirectory`, `RunAtLoad` = true, `KeepAlive` = true,
`StandardOutPath`/`StandardErrorPath` (a log path under `~/Library/Logs/<svc>` or the repo),
and `EnvironmentVariables` for anything the service needs.

For a Peggy-fronted service, also write `com.peggy.register.<svc>.plist` running the
register command (RunAtLoad + KeepAlive so it re-registers after a gateway redeploy wipes
registrations — the 30–90s heartbeat brings it back).

Don't clobber an existing plist without showing the diff first.

## Step 3 — Load and (re)start

- Load: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.<svc>.service.plist`
  (fall back to `launchctl load -w <plist>` on older macOS). Repeat for the register agent.
- If it was already loaded and you changed it: `launchctl bootout gui/$(id -u)/com.<svc>.service`
  then bootstrap again (or `kickstart -k`, mindful of the in-flight-work rule).

## Step 4 — Verify (the actual deliverable)

- **Agent is up:** `launchctl print gui/$(id -u)/com.<svc>.service` — check it's running with
  a sane PID and last exit code 0 (not a crash loop).
- **Port is listening and ONE process holds it:** confirm exactly one PID owns the port
  (`lsof -nP -iTCP:<port> -sTCP:LISTEN`). Two = the orphan-on-restart bug; clean up the stale
  one. Confirm it's bound to the 6PN address if Peggy-fronted, not `0.0.0.0`.
- **It answers:** hit a health/root path locally.
- **Peggy sees it:** `peggy list` shows `<svc>` (for gateway-fronted services).
- **Survives a restart:** `launchctl kickstart -k gui/$(id -u)/com.<svc>.service` and re-check
  it comes back clean (skip or warn if work could be in flight).

## Step 5 — Report

State what was written (the plist path[s]), that it loaded, and the verification result:
PID up, port listening (single owner), 6PN bind confirmed, `peggy list` entry present.
Call out anything that needed a workaround (env vars the agent must carry, a wrapper swapped
for a direct binary, a stale orphan cleaned up).

## Principles

- **"Done" means serving, not "file written."** The verify step is the point.
- **No-sudo by default.** User agents match the logged-in lifecycle; reach for a system
  daemon only when something must run before login (rare, out of scope).
- **Respect in-flight work.** A restart is destructive to whatever's running — confirm.
- **The agent is its own environment.** It won't inherit your shell; carry env explicitly.

## Distribution / maintenance (for the skill author)

Ships in the `kev` plugin of `proton-pidgeon/claude-skills` (marketplace `kevdunn`); reaches
other hosts on `/plugin marketplace update kevdunn` (+ restart). Pairs with `[[skill-peggy]]`
(onboarding) and `/peggy-doctor` (diagnosis). See `[[claude-sync-architecture]]`.
