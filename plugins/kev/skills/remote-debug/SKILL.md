---
name: remote-debug
description: Debug a running web app through Chrome DevTools remotely — attach Claude Code to a real logged-in Chrome session or a clean disposable one over a private tunnel, then read console errors, failed network requests, and DOM state instead of the user screenshotting them by hand. Use when the user runs `/devtools`, or asks to "debug this in the browser", "check the console", "why is the page erroring", "why is this request failing", "the page is blank/broken in Chrome", "inspect the network tab", or reports a front-end bug they would otherwise chase in DevTools by hand. Covers both pre-auth bugs (clean profile) and bugs that only reproduce when logged in (real session). Diagnosis-first; it does not edit application code unless asked.
---

# /devtools — remote Chrome DevTools debugging

Drives a real Chrome over the Chrome DevTools Protocol (CDP) via the
`chrome-devtools-mcp` server this plugin registers. The point is to stop
round-tripping screenshots of the console: read the errors, the failed requests,
and the DOM directly, form a hypothesis, and check it against source.

Companion to `/peggy-doctor`. **Peggy-doctor diagnoses the edge; this diagnoses
the page.** If a request never reaches the app, that's a gateway problem — hand
off. If it reaches the app and the app misbehaves, stay here.

## Operating rules

- **Preflight before any MCP call.** Always run `scripts/preflight.sh` (invoke with `bash`) first. An
  unclassified connection failure surfaces as a mysterious MCP timeout; the
  preflight turns it into one of four named states with a specific fix.
- **CDP is unauthenticated.** Anyone who can reach the port owns the browser and
  every session in it. Bind `127.0.0.1` and reach it over WireGuard/6PN or an SSH
  forward. **Never** bind `0.0.0.0` or a public interface, and never "fix" a
  connection problem by widening the bind — if a future session is tempted to,
  that is the bug, not the fix.
- **Scope every call.** Narrow to a route and a signal type ("console errors on
  `/checkout`") before invoking a tool. Unscoped calls dump full network
  waterfalls and DOM snapshots and will eat the context window.
- **Diagnose, don't drift.** Report the finding and the proposed fix. Only edit
  application code if the user asks.
- **Single-line commands** in anything handed to the user to run.
- **Invoke the scripts with `bash`** — they ship without the executable bit.

## Step 1 — Pick the mode

This is the first branch and it is decided from the symptom, not asked:

| Signal | Mode |
|---|---|
| Bug is behind a login; user says "when I'm logged in", "my session", "my account"; involves cookies/tokens/roles | **attach** |
| Anything else — public routes, first-load, build/bundle errors, pre-auth flows | **clean** |
| Bug reproduces only for a *specific* user's data | **attach** |
| Needs to be reproducible / shared / re-run later | **clean** |

State the chosen mode and the one-line reason before launching.

## Step 2 — Establish the session

```
bash ${CLAUDE_PLUGIN_ROOT}/skills/remote-debug/scripts/launch-chrome.sh --mode <clean|attach> [--port 9222] [--url <app-url>]
```

**clean** — disposable profile under `$TMPDIR`. Dedicated `--user-data-dir` is
non-negotiable: without it Chrome hands the URL to any already-running instance
and silently ignores the debugging flag.

**attach** — preserves the real session:
1. If CDP is already live on the port, attach as-is and launch nothing.
2. Otherwise snapshot the live profile's session files to a scratch dir and
   launch from the copy. You **cannot** enable the debugging port on an
   already-running Chrome process, and you must never point `--user-data-dir` at
   a live profile — it is lock-held and will refuse or corrupt.
3. If the copied session is rejected by the site (fingerprint-bound login), the
   fallback is quitting the real Chrome and relaunching it on the real profile
   with the flag. That costs the user their tabs — **ask before doing it.**

### Remote hosts

Keep the Chrome-side bind on loopback and forward the port:

`ssh -L 9222:127.0.0.1:9222 <host>`

This composes with an existing WireGuard/6PN path and exposes CDP to nothing.
Then point preflight and the MCP server at `127.0.0.1:9222` as usual.

## Step 3 — Preflight

```
bash ${CLAUDE_PLUGIN_ROOT}/skills/remote-debug/scripts/preflight.sh [--host H] [--port N] [--target-url URL]
```

Four states, each with its own remediation — do not proceed on anything but
`HEALTHY`:

| State | Exit | Means | Do |
|---|---|---|---|
| `HEALTHY` | 0 | CDP answering; target tab present if a URL was given | Proceed |
| `TUNNEL_DOWN` | 1 | Host unreachable | Bring up tunnel / re-establish forward |
| `PORT_CLOSED` | 2 | Host up, nothing on the port | Chrome not running, or running without CDP → Step 2 |
| `WRONG_CHROME` | 3 | CDP answering but no tab matches the app | Attached to a different instance/profile; the script lists the origins actually open |

`WRONG_CHROME` is the one that wastes the most time when unclassified — it looks
like the app is broken when you are simply attached to the wrong browser.

## Step 4 — The debug loop

Run it in this order and stop as soon as the cause is established:

1. **Reproduce** — navigate to the failing route; note what the user said should
   happen versus what does.
2. **Collect, scoped** — console errors and warnings first; then *failed* network
   requests only (non-2xx/3xx, aborted, CORS-blocked). Do not pull the full
   waterfall unless the failure is a timing or ordering problem.
3. **Hypothesize** — name one likely cause and the evidence for it.
4. **Verify against source** — find the code that produces the symptom. A console
   error tells you where it surfaced, rarely where it originated.
5. **Report** — symptom, root cause, evidence, proposed fix. Then stop.

If two collection passes produce nothing conclusive, say so and ask for a
narrower reproduction rather than escalating context spend.

## Known gotchas

- **The debugging flag is silently ignored** when another Chrome is running and
  no distinct `--user-data-dir` is passed. Symptom: `PORT_CLOSED` even though you
  "launched with the flag". Fix: dedicated profile dir (both scripts already do).
- **Snapshot staleness (attach mode).** The copy freezes the session at copy
  time. If the real browser refreshes its token, the copy 401s in a way that
  reads exactly like an app auth bug. On an unexplained 401 in attach mode,
  re-snapshot before debugging anything.
- **Port already owned.** `clean` mode refuses to launch onto an occupied port
  rather than silently attaching to a stranger's browser. Choose another port.
- **Blank page, empty console.** Usually the bundle 404'd or CSP blocked it —
  check failed network requests before assuming a runtime error.
- **Errors that vanish under `clean`.** That is a signal, not noise: the bug is
  session/state dependent. Re-run in `attach`.
- **Extension noise.** A real profile snapshot carries extensions, which inject
  their own console errors. Discount `chrome-extension://` frames before
  chasing them.
- **CDP reachable but every action times out.** Usually the page has a blocking
  modal dialog (`alert`/`confirm`/`beforeunload`) — CDP stalls until it is
  dismissed.

## Handoff to /peggy-doctor

Hand off when the evidence points at the edge rather than the app: requests
returning gateway-shaped failures (a 404 across *every* route, a 502 confined to
`PATCH`/`DELETE`, SSE connections that open and hang, a redirect to
`/oauth2/start` on something that should be auth-exempt). Those are documented
Peggy gotchas — do not chase them in the page.
