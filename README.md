# claude-skills

A collection of skills for [Claude Code](https://claude.com/claude-code), with cross-OS hooks that automatically install them into every git repo you work in.

Currently shipped:

- **`/ingest`** — turn design docs into `specs/` and `tasks/` scaffolding ([`ingest/SKILL.md`](ingest/SKILL.md))

---

## How it works

When you open a Claude Code session inside any git repo, a `SessionStart` hook fires a small script that:

1. Fetches the latest `SKILL.md` from this GitHub repo
2. Compares it to the local copy at `<repo>/.claude/skills/ingest/SKILL.md`
3. Writes the new content if they differ (or the file is missing)
4. Auto-commits the change — but only if your working tree is otherwise clean, so it never pollutes a feature branch mid-work

Once `SKILL.md` is committed, it travels with the repo to Claude in the cloud — no further setup needed there.

---

## Install (per local machine)

Pick the line for your OS. Each installer is idempotent — run again any time to refresh.

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/proton-pidgeon/claude-skills/main/install/install.sh | bash
```

Requires `bash`, `curl`, `git`, and either `jq` or `python3` (for editing `settings.json` safely).

### Windows (native PowerShell)

```powershell
irm https://raw.githubusercontent.com/proton-pidgeon/claude-skills/main/install/install.ps1 | iex
```

Requires PowerShell 5.1+ and `git` on PATH.

### Git Bash on Windows

Use the macOS/Linux installer above — it installs the bash hook, and Claude Code on Windows can run bash if Git for Windows is on PATH.

---

## What the installer does

Writes the OS-specific session-start script to `~/.claude/scripts/`:

| OS                | Script                                                 |
|-------------------|--------------------------------------------------------|
| macOS / Linux     | `~/.claude/scripts/session-start-ingest-skill.sh`      |
| Windows           | `~/.claude/scripts/session-start-ingest-skill.ps1`     |

Adds a `SessionStart` entry to `~/.claude/settings.json` (creating the file if missing). A backup `settings.json.bak.<timestamp>` is written next to it before any edits.

The installer also removes any prior hook entries whose command path references `session-start-ingest-skill` — so it's safe to run after relocating scripts or after a previous broken setup.

---

## Claude in the cloud

There are two independent ways cloud sessions can pick this up; you can use either or both.

**Option A — passive (recommended):** once the local hook has installed `.claude/skills/ingest/SKILL.md` into a repo and you've committed it, cloud sessions for that repo see it automatically. No cloud-side install needed.

**Option B — per-repo auto-refresh:** if you want cloud sessions to pull the latest `SKILL.md` from this repo on every session start (not just whatever was committed last), copy [`per-repo/settings.json`](per-repo/settings.json) into the target repo at `.claude/settings.json`:

```bash
mkdir -p .claude
curl -fsSL https://raw.githubusercontent.com/proton-pidgeon/claude-skills/main/per-repo/settings.json \
  -o .claude/settings.json
git add .claude/settings.json && git commit -m "Auto-refresh /ingest skill on session start"
```

This makes the hook fetch and run the bash script directly from GitHub raw at session start — no local install required for cloud or any other machine.

---

## Per-repo opt-out

To skip the skill installation in a specific repo:

```bash
mkdir -p .claude && touch .claude/no-ingest-skill
```

The hook checks for this marker and exits silently.

---

## Configuration

Both the installer and the session-start scripts respect these environment variables:

| Variable                       | Purpose                                                         |
|--------------------------------|-----------------------------------------------------------------|
| `INGEST_SKILL_URL`             | Override the upstream `SKILL.md` URL (e.g. point at a fork)     |
| `INGEST_SKILL_REPO_RAW_BASE`   | Override the raw base URL the installer fetches scripts from    |
| `INGEST_SKILL_QUIET`           | Set non-empty to suppress non-error hook output                 |
| `CLAUDE_HOME`                  | Override the `~/.claude` install location                       |

---

## Repo layout

```
.
├── ingest/
│   └── SKILL.md                          # the skill itself
├── scripts/
│   ├── session-start-ingest-skill.sh     # bash hook (mac/linux/cloud/git-bash)
│   └── session-start-ingest-skill.ps1    # PowerShell hook (windows native)
├── install/
│   ├── install.sh                        # mac/linux/cloud installer
│   └── install.ps1                       # windows installer
├── per-repo/
│   └── settings.json                     # optional .claude/settings.json template
└── README.md
```
