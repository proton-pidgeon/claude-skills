---
name: peggy-doctor
description: Diagnose a misbehaving service behind the Peggy gateway by matching the symptom against the known edge-gotcha catalog (gateway-wide 404s / WireGuard tunnel, lapsed registration, SSE hangs, blank PWA icons, PATCH/DELETE 502s, bare-prefix .txt downloads, proxy-auth logout dead-ends, CSRF/ACL 403s) and proposing the documented fix. Use when the user runs `/peggy-doctor`, or asks "why is my Peggy service broken/404ing/hanging", "this app works on LAN but not through peggy.fly.dev", "the home-screen icon is blank", "my PATCH returns 502", or otherwise reports a Peggy-fronted service misbehaving. Read-only diagnosis; it does not redeploy the gateway without asking.
---

# /peggy-doctor — diagnose a Peggy-fronted service against the gotcha catalog

A service that works on the LAN but misbehaves through `https://peggy.fly.dev/<name>/`
has almost always hit one of a small set of **edge gotchas** — none of which are visible
in the service itself. This skill takes the symptom, walks the catalog, confirms the
cause with a targeted probe, and proposes the documented fix. See `[[peggy-gateway]]` and
its child memories for the canonical write-ups.

## Operating rules

- **Diagnose first, change nothing risky.** Read state and run probes freely. Do **not**
  redeploy the gateway, edit `.peggy.env`, or restart the WireGuard daemon (needs sudo)
  without telling the user what you found and what the fix will do.
- **Symptom-driven.** Start from what the user observed and use the triage tree to narrow
  fast — don't run the whole catalog blindly.
- **Edge 302 proves nothing about the Mac.** A `302 → /oauth2/start` comes from oauth2-proxy
  at the Fly edge; it says the gateway is up, not that the home service is reachable. The
  Fly gateway (`fdaa:3e:60bd::1`) does **not** answer ICMP — never use `ping6` to judge
  tunnel health. Use auth-exempt HTTP paths instead (e.g. `/fovea/icons/icon-192.png` → 200,
  `/lobe/api/v1/hls/x.m3u8` → 405).
- **Single-line commands only** (no `\` continuations / heredocs in commands the user runs).

## Step 1 — Capture the symptom and scope

Pin down two things before touching the catalog:

- **What's failing** — total outage, one service, one route, one HTTP method, an icon, a
  stream, a login affordance?
- **Scope** — is it **every** service under `peggy.fly.dev` or **just one**? This single
  fact splits the two most common root causes (tunnel vs registration).

Quick orienting probes (read-only):
- `ifconfig | grep -q fdaa:3e:60bd && echo "6PN up" || echo "6PN DOWN"` — is the home tunnel up?
- `peggy list` — which services are currently registered (90s heartbeat TTL).
- `curl -sI https://peggy.fly.dev/<svc>/` — healthy unauthenticated probe is **302**, not 200.

## Step 2 — Triage tree → catalog

Match the symptom to the entry, confirm with the probe, then propose the fix.

### A. Every service 404s (whole gateway dark) → WireGuard tunnel down
`[[peggy-wireguard-boot-race]]`. All `com.peggy.register.*` agents log `context deadline
exceeded`; `ifconfig` shows no `fdaa:` address. On reboot the one-shot
`com.peggy.wireguard` daemon can lose the DNS race.
- **Confirm:** no 6PN address; `peggy list` empty/erroring.
- **Fix (needs sudo, ask first):** `sudo launchctl kickstart -k system/com.peggy.wireguard`
  → registrars repopulate routes within ~a minute. Logs: `/var/log/peggy-wireguard.err`.
- **Second failure mode (no reboot):** tunnel looks healthy (6PN present, recent `wg show`
  handshake) but **TCP to any 6PN addr times out** mid-day, or the daemon is UNLOADED.
  Re-bootstrapping doesn't fix it — do a clean rebuild: `sudo /usr/local/sbin/claude-wg restart`.

### B. One service 404s, others fine → registration lapsed / bad bind
- **Confirm:** `peggy list` is missing that service; check its `com.peggy.register.<svc>`
  LaunchAgent is loaded and the app process is up.
- **Fix:** restart the register agent (`launchctl kickstart -k gui/$(id -u)/com.peggy.register.<svc>`);
  ensure the service **binds the home 6PN address, never `0.0.0.0`**. Verify reachability
  from the gateway itself: `fly ssh console --app peggy -C "curl -s http://[<mac-6pn>]:<port>/healthz"`.

### C. SSE / streaming hangs with no error (especially on iOS) → missing 2KB preamble
`[[peggy-sse-priming]]`. The HTTP/2 edge + client read buffer withholds a streamed body
until it fills; a short reply never reaches the threshold → reader sees nothing, no error.
- **Confirm:** streams fine on direct LAN/Tailscale (HTTP/1.1) but hangs through Peggy.
- **Fix:** server `yield`s a ~2KB SSE **comment** preamble (`: padding…`) as the very first
  bytes; emit the first real frame before slow work; iOS clients parse the **raw byte stream**,
  not `URLSession.AsyncBytes.lines`.

### D. PATCH/DELETE → 502 EOF, upstream logged 200, mutation didn't happen → forward_auth strips body
`[[peggy-patch-body-eof]]`. Caddy `forward_auth`'s subrequest breaks PATCH/DELETE body
buffering; upstream gets `Content-Length: N` with 0 bytes.
- **Confirm:** upstream access log shows 200 but data didn't move; `flyctl logs -a peggy
  --no-tail | grep EOF` shows `reverseproxy.statusError`; repro works direct-to-upstream,
  fails only through Peggy.
- **Fix:** add a **POST mirror** for the mutation route and have the Peggy-fronted client
  call POST. Keep PATCH for direct API clients. Default write endpoints to POST.

### E. Blank home-screen icon after "Add to Home Screen" → icon outside the exempt allowlist
`[[peggy-pwa-icon-allowlist]]`. The installer fetches icons without the Google cookie; only
a fixed path set is auth-exempt (`/icons/*`, `manifest.webmanifest`, `favicon.ico`,
`apple-touch-icon*`). Anything else 302s → installer gets HTML → blank glyph.
- **Confirm:** `curl -sI https://peggy.fly.dev/<svc>/<icon-path>` returns 302 instead of
  `200 image/png`.
- **Fix:** serve icons under `/icons/...` (or canonical `apple-touch-icon*` names) and point
  `manifest.icons[].src` there. No gateway change needed — conform the app's paths.

### F. iOS Chrome offers a `<svc>.txt` download for the bare URL → trailing-slash 308 missing
`[[peggy-trailing-slash-308]]`. Should be automatic (registrar `683a1ce`).
- **Confirm:** `curl -sI https://peggy.fly.dev/<svc>` should be **308** with `location:
  /<svc>/`. If it's 404, the registrar rolled back or a deploy failed.
- **Fix:** the user types/links the trailing slash as a stopgap; the real fix is restoring
  the registrar template (gateway-owner task).

### G. In-app "Sign out" dead-ends (proxy-auth onboarded app) → logout points at disabled OAuth
`[[peggy-gateway]]` onboarding gotcha. An app switched to trust the edge still has its own
login/logout UI; `/logout` → `/login` → 503 "OAuth not configured".
- **Fix:** point "Sign out" at the gateway session **`/oauth2/sign_out?rd=<url-encoded app
  root>`** (origin-root, not prefixed); make the app's `/login`·`/logout` redirect to the
  app root instead of rendering the disabled flow.

### H. 403 the user shouldn't get → per-identity ACL, owner-only default
`[[peggy-gateway]]` ACL. Any service **not** in `PEGGY_MENU_ACL` is reachable only by
`OWNER_EMAIL`. Adding a new service defaults to owner-only.
- **Confirm:** `fly ssh console --app peggy -C "grep header_regexp /etc/caddy/sites/<svc>.caddy"`
  shows the allowed-email regex.
- **Fix (gateway-owner):** grant via `PEGGY_MENU_ACL` in `.peggy.env` → `bash scripts/render.sh`
  → `fly deploy .peggy/render` (positional working-dir, not `--config`).

### I. Login 403 "Unable to find a valid CSRF token" → stale cookie, not a service problem
Fresh tab / clear `peggy.fly.dev` site data. No service-side change.

## Step 3 — Report

Lead with the **single most likely cause** and the evidence that points to it, then give the
**exact fix** (commands or the code/route change), and note whether it's a service-side fix
(the user can do it now) or a **gateway-owner task** (sudo / `.peggy.env` / `fly deploy`).
If two catalog entries fit, say which probe disambiguates them. If nothing in the catalog
matches, say so plainly and fall back to first principles (tunnel → registration → route →
method → client buffering) rather than forcing a fit.

## Principles

- **The cause is one layer away from the symptom.** Upstream-200-but-no-mutation, edge-302-
  but-still-broken, builds-fine-export-dies — name the layer, don't trust the surface.
- **Confirm before prescribing.** Each catalog entry has a probe; run it.
- **Know what you may touch.** Service-side fixes are fair game; tunnel restarts and gateway
  redeploys are sudo/owner tasks — surface them, get the nod.

## Distribution / maintenance (for the skill author)

Ships in the `kev` plugin of `proton-pidgeon/claude-skills` (marketplace `kevdunn`); reaches
other hosts on `/plugin marketplace update kevdunn` (+ restart). The catalog mirrors the
`peggy-*` memory files — when a new edge gotcha is discovered and saved to the vault, add a
matching triage entry here. See `[[claude-sync-architecture]]`.
