---
name: fleet
description: Run a command across a curated fleet of the user's Tailscale-connected hosts (macOS, Linux, Windows) in parallel over SSH, with per-host OS detection and an aggregated pass/fail report. The default action with no command is to sync the kev@kevdunn plugin on every host (`claude plugin marketplace update kevdunn`), so a skill/plugin change made on one machine reaches all the others. Use when the user runs `/fleet`, or asks to "update the plugin/skills on all my hosts", "sync my machines", "push the latest plugin to my other computers", "run <command> on all my hosts", or "what does <command> output across the fleet". Local CLI/Desktop only; needs Tailscale SSH and an allowlist of target hosts.
---

# /fleet — run a command across the Tailscale host fleet

Fan a single command out to every host in a curated allowlist, over Tailscale SSH, in
parallel, and report one consolidated pass/fail summary. With **no command**, the default
action **syncs the `kev@kevdunn` plugin** on each host — the exact friction that prompted
this: after landing a plugin/skill change, every machine still needs
`claude plugin marketplace update kevdunn` before it sees the new version. `/fleet` does that
everywhere at once — including the local host (run directly, no ssh).

It's backed by the script `kev-fleet.sh`, which does the host resolution, OS detection,
parallel SSH, and reporting deterministically.

## Operating rules

- **Allowlist only.** Only hosts listed in `$FLEET_HOSTS` (default `~/.claude/fleet-hosts`)
  are ever contacted. The local node and any offline host are skipped automatically. Never
  bypass the allowlist to SSH arbitrary tailnet nodes (iOS devices, someone else's box).
- **No hangs.** SSH runs with `BatchMode=yes` + a connect timeout, so an unreachable or
  auth-refusing host fails fast and is reported — it never blocks the others or prompts.
- **Report honestly.** Relay the per-host result as-is: ✅ ok, ❌ exit code + the error tail,
  ⚪ skipped (self/offline). A host-side problem (Tailscale SSH not enabled, wrong remote
  user) is the host's to fix — surface it, don't paper over it.
- **Confirm destructive custom commands.** The default plugin-sync is safe and idempotent.
  But a custom command (`/fleet -- <cmd>`) runs on *every* host — if it mutates state,
  confirm the command and the target set with the user before running (preview with
  `--dry-run` / `--list`).

## How to invoke the script

It ships with the plugin at:

```
~/.claude/plugins/marketplaces/kevdunn/plugins/kev/scripts/kev-fleet.sh
```

Pick the invocation from what the user asked:

- **Sync the plugin everywhere (default):**
  `bash <script>` — runs `claude plugin marketplace update kevdunn` on each host.
- **Run an arbitrary command everywhere:**
  `bash <script> -- <command...>` — everything after `--` is the command. Unix hosts run it
  under a login shell (so `claude` and friends are on PATH); Windows hosts run it via their
  default Tailscale-SSH shell.
- **The local host is included by default** — it runs the command directly (no ssh), so
  `/fleet` updates this machine too. Add `--no-self` to act on the remote hosts only.
- **Restrict to a subset:** add `--hosts a,b` (the names must already be in the allowlist).
  A subset targets exactly the named hosts — the local node is not auto-added.
- **Preview without running:** `--dry-run` prints the exact command per host.
- **See the resolved targets:** `--list` shows each allowlisted host with its OS and state
  (ok / offline / self / unknown).
- **First-run setup:** `--init` scaffolds `~/.claude/fleet-hosts` from the current tailnet
  (online, non-iOS peers, commented out for the user to uncomment).

## First run / no allowlist

If the script reports there's no allowlist, run `--init` to scaffold one from the tailnet,
then tell the user to edit `~/.claude/fleet-hosts` — uncomment the hosts they want, and use
`user@host` for any host whose remote username differs from the local one (a bare hostname
defaults to the local username, which Windows hosts often reject). Confirm with `--list`
before the first real run.

## Interpreting and reporting results

After running, summarize for the user:
- Which hosts updated/ran successfully, and the key line of output (e.g. "Successfully
  updated marketplace: kevdunn", a `claude --version`, the command's result).
- Which were skipped and why (offline — note last-seen; self only if `--no-self` was passed).
- The local host appears as `<name> (local)` and runs directly without ssh.
- Which **failed**, with the cause and the fix: `Connection refused` → Tailscale SSH/sshd not
  enabled on that host; `Permission denied (publickey…)` → wrong remote user, add `user@` to
  its allowlist line. These are host config, not script faults.

## Caveats to know

- **Targets must accept Tailscale SSH** (`tailscale up --ssh`) or run an sshd reachable over
  the tailnet; otherwise the connection is refused.
- **Remote username:** a bare hostname uses the local username. Put `user@host` in the
  allowlist when they differ (common for Windows hosts).
- **A running Claude session applies the plugin update on its next restart** — `/fleet`
  bumps the installed plugin on disk; it doesn't hot-reload a live session on that host.
- **Custom commands with shell operators** (`&&`, `|`) run fine inside the unix login shell;
  on Windows they depend on that host's default shell (modern PowerShell / cmd handle `&&`).

## Principles

- **Allowlist is the safety boundary.** Explicit, curated, never bypassed.
- **Fail fast and visibly.** Better to report "host X refused" than to hang the fleet.
- **The default is the common case.** Plugin sync needs no arguments; everything else is opt-in.

## Distribution / maintenance (for the skill author)

Ships in the `kev` plugin of `proton-pidgeon/claude-skills` (marketplace `kevdunn`); reaches
other hosts on `/plugin marketplace update kevdunn` (+ restart) — which is exactly what this
skill automates across the fleet. The allowlist (`~/.claude/fleet-hosts`) is per-user config,
not plugin code, so it is not synced by the plugin. See `[[claude-sync-architecture]]`.
