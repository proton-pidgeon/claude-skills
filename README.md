# claude-skills — Kev's Claude Code marketplace & cross-surface sync

A single source of truth that keeps [Claude Code](https://claude.com/claude-code) in
sync across every surface: **CLI + Desktop** on many hosts, and **claude.ai cloud**
(web + mobile). It's both a **plugin marketplace** and the **sync machinery** around it.

## ⚡ Quick install — run on each host, then restart Claude Code

**macOS / Linux** (and Windows via Git Bash):

```bash
curl -fsSL https://raw.githubusercontent.com/proton-pidgeon/claude-skills/main/install/install.sh | bash
```

**Windows (native PowerShell):**

```powershell
irm https://raw.githubusercontent.com/proton-pidgeon/claude-skills/main/install/install.ps1 | iex
```

Installs the `kev` plugin, merges shared settings, and clones the `~/claude-memory` vault.
Per-host secrets are **not** synced — re-run the telegram-notify setup (`~/.claude/.telegram`)
and add any MCP tokens locally. Details below.

## The two-camp model (why this is split the way it is)

| Camp | Surfaces | Persistence | How it's reached |
|---|---|---|---|
| **Filesystem** | CLI + Desktop | share the same `~/.claude/` per host | plugin install + git-synced memory + session hooks |
| **Cloud** | web + mobile | ephemeral sandbox; **ignores `~/.claude`** | repo-committed `SessionStart` hook clones resources ([`cloud/`](cloud/)) |

Git is the only substrate that reaches both. So: skills/commands/agents/hooks ship as a
**plugin**; memory lives in a **git-synced vault** (`claude-memory`); cloud gets a
committed bootstrap hook.

## Install a host (CLI + Desktop)

One idempotent line — installs the plugin, merges shared preferences, and clones your
memory vault:

```bash
curl -fsSL https://raw.githubusercontent.com/proton-pidgeon/claude-skills/main/install/install.sh | bash
```

(Windows native PowerShell: `install/install.ps1`.) Then restart Claude Code.

> **Windows note:** the plugin's sync hooks (`hooks.json`) invoke `bash`, so on
> macOS/Linux — or Windows with **Git for Windows** on PATH — they work as-is. For a pure
> Windows host, `install.ps1` also installs **native-PowerShell sync hooks**
> (`kev-sync-{pull,push}.ps1`, fetched into `~\.claude\` and wired into `settings.json`),
> so memory sync works without bash. The two are idempotent, so a Windows host that has
> both bash and PowerShell can run both harmlessly (the second pull/push is a no-op).

Prefer to do it by hand? `/plugin marketplace add proton-pidgeon/claude-skills` then
`/plugin install kev@kevdunn`.

## What's in the `kev` plugin

| Type | Items |
|---|---|
| Skills | `/ingest` (design docs → specs/tasks), `/implement` (autonomously build a `tasks/` backlog via worktree-isolated parallel agents), `/shannon` (Keygraph pentester wrapper), `/understand` (deep-review a repo → on-screen briefing + durable project memory), `/peggy` (onboard a local service into the Peggy gateway) |
| Commands | `/telegram` (notify via your bot) |
| Agents | `arch-infrastructure-reviewer`, `ux-design-reviewer` |
| Hooks | fully-automatic memory sync (see below) |

## Memory sync (fully automatic)

Your operational memory lives in the **`claude-memory`** vault (a git repo you can open
as an Obsidian vault). Each host points Claude's `autoMemoryDirectory` at its local clone
(`~/claude-memory` by default), and the plugin's hooks keep it in sync:

- **SessionStart** → `git pull --rebase --autostash` the vault (+ refresh the marketplace clone).
- **SessionEnd** → commit + push memory changes, conflict-safe. On an unresolvable
  rebase conflict it aborts the push, leaves your work intact, and fires a **Telegram
  alert** so you can merge by hand.

Scripts: [`plugins/kev/scripts/`](plugins/kev/scripts/). The memory directory is read
from `autoMemoryDirectory` — one source of truth, no hard-coded paths.

## Cloud (web + mobile)

See [`cloud/`](cloud/). Commit `cloud/settings.json` into a repo's `.claude/` (or add the
one-liner to your cloud Environment setup script) and cloud sessions will clone the
skills + memory at startup. Skills injection is solid; cloud memory is best-effort —
verify it on a live session.

## Secrets — never synced

`.credentials.json`, `~/.claude/.telegram`, `.session-config.json`, and MCP tokens stay
per host. Shared settings (`install/settings.shared.json`) deliberately **exclude**
permission-bypass flags and host-specific plugins — set those per machine.

## Repo layout

```
.
├── .claude-plugin/marketplace.json     # marketplace manifest (name: kevdunn)
├── plugins/kev/                        # the plugin
│   ├── .claude-plugin/plugin.json
│   ├── skills/{ingest,implement,shannon,understand,peggy}/SKILL.md
│   ├── commands/telegram.md
│   ├── agents/{arch-infrastructure,ux-design}-reviewer.md
│   ├── hooks/hooks.json                # SessionStart/SessionEnd sync
│   └── scripts/kev-sync-{pull,push}.{sh,ps1}   # bash + native-PowerShell sync
├── install/
│   ├── install.sh / install.ps1        # per-host bootstrap
│   └── settings.shared.json            # portable preferences (jq-merged)
├── cloud/                              # claude.ai cloud bootstrap
│   ├── settings.json  bootstrap-cloud.sh  README.md
├── scripts/  per-repo/                 # legacy ingest-only hook (superseded by the plugin)
└── README.md
```
