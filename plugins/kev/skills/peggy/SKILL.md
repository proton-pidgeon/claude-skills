---
name: peggy
description: Onboard a locally-hosted service into Peggy — expose an app running on the home Mac at a public, Google-authenticated HTTPS URL (e.g. https://peggy.fly.dev/<name>/) over Fly's WireGuard mesh, with no open ports and no client VPN. Use when the user runs `/peggy`, or asks to "onboard/expose/publish this service via Peggy", "put this app behind Peggy", "register this with the gateway", or "make this reachable from my phone through Peggy". Handles 6PN binding, path-prefix correctness, registration via the `peggy` CLI (or SDK/LaunchDaemon), and fail-closed verification.
---

# /peggy — onboard a service into the Peggy gateway

Take the service in (or named from) the current working directory and make it reachable
at a **public, authenticated HTTPS URL** through **Peggy**, Kev's personal edge gateway —
without opening a home port, renting an IP, or putting a VPN on any client.

```
browser ──HTTPS──▶ peggy.fly.dev  (Caddy + oauth2-proxy: Google auth, allowlist)
        ──6PN WireGuard──▶ your service on the home Mac
```

The deliverable: the service is registered with Peggy, reachable at `https://<gateway>/<name>/`,
protected by edge auth that **cannot be bypassed**, and verified fail-closed.

## Authoritative source — read it first, do not trust this file's values

Peggy's repo ships the canonical contract at **`ONBOARDING.md`** (this Peggy is at
`~/code-local/peggy/ONBOARDING.md`; if absent, ask the user for the Peggy repo path).
Its **"Deployment facts"** table is the single source of truth for the live values
(gateway hostname, routing mode, home-machine 6PN address, registrar address, allowlist).
**Read that block at runtime and use those values** — they can change and this skill must
not hardcode them. The values below are the *current* deployment, shown only to orient you:

| Fact | Current value (verify against ONBOARDING.md) |
|---|---|
| Gateway hostname | `peggy.fly.dev` |
| Routing | path-based → `https://peggy.fly.dev/<name>/` |
| Home machine | the Mac that is the Fly WireGuard peer (`mac-daddy`) |
| Home 6PN address | `fdaa:3e:60bd:a7b:9016:9c37:ac65:d902` |
| Registrar (mesh-only) | `peggy.internal:8080` |
| CLI | `peggy` (on PATH at `/opt/homebrew/bin/peggy`) |
| Auth | Google OAuth, allowlist e.g. `kevdunn@gmail.com` |

## Preflight — confirm Peggy can actually reach a service

Run these and resolve any failure before changing the service:

1. **CLI present:** `command -v peggy` (and `peggy --help`). If missing, the gateway/CLI
   isn't installed on this host — stop and tell the user.
2. **WireGuard tunnel up:** `wg show fly0` must list the peer. If down, bring it up
   (`wg-quick up fly0`); without it the registrar (`peggy.internal:8080`) is unreachable.
3. **Home 6PN address:** take it from ONBOARDING.md's facts table, or derive it from the
   `Address =` line of the `fly0` WireGuard config, or `fly ssh console --app peggy -C "printenv FLY_PRIVATE_IP"` for the gateway side.
4. **On the right host:** only the home Mac (the WireGuard peer) can be a backend. A
   service on any other machine is not reachable — confirm you're operating there.
5. **Allowlist:** the user's Google account must be on the gateway allowlist, or they
   won't be able to load the service after sign-in. (Widening the allowlist is the gateway
   owner's job — do not attempt it.)

## The four contract requirements — apply them to this service

Work through each against the current project; make the minimal change needed.

1. **Pick a valid name.** Lowercase, `^[a-z0-9][a-z0-9-]{0,30}$`; `oauth2` and `ping` are
   reserved. Default to the repo/app name, kebab-cased. The service will live at `/<name>/`.

2. **Bind to the 6PN address, never `0.0.0.0`/`::`.** The gateway reaches the service over
   IPv6 6PN, so it must listen on `[<home-6pn>]:<PORT>`. Either configure the app to bind
   that address, or front it with a forwarder (leaves the app on localhost):
   ```
   socat TCP6-LISTEN:<PORT>,bind=[<home-6pn>]:<PORT>,fork,reuseaddr TCP4:127.0.0.1:<PORT>
   ```
   Binding `0.0.0.0`/`::` exposes it to the whole home LAN — refuse to do that.

3. **Cope with the path prefix.** Peggy serves the app at `/<name>/` and **strips** the
   prefix before proxying (`/<name>/foo` arrives as `/foo`), passing `X-Forwarded-Prefix: /<name>`.
   - If the framework honors `X-Forwarded-Prefix` (Spring Boot `ForwardedHeaderFilter`,
     many proxy-aware stacks), prefixing is automatic — prefer this.
   - Otherwise set the base path explicitly so absolute links/assets resolve under
     `/<name>`: Flask `APPLICATION_ROOT`, Django `FORCE_SCRIPT_NAME=/<name>`, Vite/CRA
     `base: '/<name>/'`, Next.js `basePath: '/<name>'`, or a `--root-path`/`--base-path` flag.
   Detect the stack from the repo and make the right change; this is the most common cause
   of a "loads but CSS/links 404" failure.

4. **Do not implement auth.** Every proxied request is already authenticated and on the
   allowlist. Read identity from the headers the gateway injects — trust them:
   `X-Auth-Request-User`, `X-Auth-Request-Email` (key per-user logic off the email),
   `X-Forwarded-Prefix`. Keep the app's own routes off `/oauth2/*`.

## Register (choose by how long-lived the service is)

The registrar reaps a service ~90s after its last heartbeat, so registration must be kept
alive. The backend is derived from the caller's own 6PN source — you cannot point a route
at another host.

- **A — Interactive / while developing:** `peggy register --name <name> --port <PORT>`
  (registers + heartbeats in the foreground; Ctrl-C unregisters). `peggy list` to check,
  `peggy unregister <name>` to remove. `--once` registers without heartbeat (reaped in ~90s,
  test-only).
- **B — From the service's own code (Go, if you own it):** `go client.New("").RegisterAndHeartbeat(ctx, "<name>", <PORT>)`
  (add `replace peggy/cli => <peggy-repo>/cli` to `go.mod`, or copy the single dependency-free
  `cli/client/client.go`). Non-Go: hit the mesh-only HTTP API — `POST /v1/services
  {"name","port"}` then `PUT /v1/services/<name>/heartbeat` every 30s at `http://peggy.internal:8080`.
- **C — Persistent across reboots (always-on):** install a LaunchDaemon from
  `examples/com.peggy.register.plist` in the Peggy repo (set `<NAME>`/`<PORT>`); launchd keeps
  it registered and re-registers after a gateway restart. Use this for a service meant to stay up.

Pick B or C for anything beyond a dev session; recommend C for always-on apps.

## Verify (always do this; report the results)

1. **Fail-closed** — from an unauthenticated client: `curl -I https://<gateway>/<name>/`
   **must** return **302** to `/oauth2/start`. If it returns 200 or the app's content,
   **STOP** — auth was bypassed; do not consider it shipped.
2. **Reachability** — `peggy list` shows the service with the right port and home 6PN backend.
3. **Browser** — open `https://<gateway>/<name>/`, sign in as an allowlisted Google account,
   confirm the app loads and its links/assets resolve (if they 404, revisit the path-prefix step).

## Guardrails — refuse these

- No unauthenticated/"public" routes. Auth is injected by the gateway, is not configurable,
  and must not be bypassed — do not add a bypass or a second unauthenticated entry.
- Never bind the service to `0.0.0.0`/`::`.
- No reserved names (`oauth2`, `ping`) or names outside `^[a-z0-9][a-z0-9-]{0,30}$`.
- Do not widen the allowlist or touch the Caddy admin API — those belong to the gateway owner.

## Troubleshooting (full table in Peggy's ONBOARDING.md)

- **404** at the URL → not registered or reaped (no heartbeat) → re-register; use option B/C.
- **502** → gateway can't reach the service over 6PN → confirm it's bound to the 6PN address
  (not just localhost) and the port matches.
- **Loads but CSS/links 404** → path-prefix issue → enable `X-Forwarded-Prefix` or set the
  app base path to `/<name>` (contract item 3).
- **`peggy` can't reach the registrar** → WireGuard down (`wg show fly0`) or the scoped
  `peggy.internal` resolver missing → bring the tunnel up; fallback `--addr "[<gateway-6pn>]:8080"`.

## Principles

- **The ONBOARDING.md in the Peggy repo is the contract** — read its live facts; this skill
  is the operator's playbook, not the source of truth for deployment values.
- **Fail-closed or not done.** A service that returns its content to an unauthenticated
  `curl` is a failure, not a success — always run verification step 1.
- **Smallest change to the service.** Prefer a `socat` 6PN forwarder + a base-path setting
  over invasive rewrites; don't restructure the app to onboard it.
- **Persistence matters.** A bare `peggy register` dies with the terminal; for anything
  real, wire option B (in-code) or C (LaunchDaemon) so it survives reboots and gateway restarts.
