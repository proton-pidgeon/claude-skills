# Cloud surfaces (claude.ai/code web + mobile)

Cloud sessions run in ephemeral sandboxes that **do not read your `~/.claude`** — no
personal plugins, skills, or memory. They only see what's **committed into the repo**
plus what a repo-committed `SessionStart` hook pulls in. This folder bridges that gap.

## How it works

`bootstrap-cloud.sh` runs at session start (only when `CLAUDE_CODE_REMOTE=true`) and:

1. **Skills + commands:** clones `claude-skills` (pinned) and copies the `kev`
   plugin's skills/commands into the session's `.claude/`, so `/ingest`, `/shannon`,
   `/telegram` etc. are available.
2. **Memory:** clones the `claude-memory` vault with `KEV_MEM_TOKEN`, then emits the
   vault's contents (the `MEMORY.md` index plus every fact file) as SessionStart
   **`additionalContext`** — text injected straight into the model's context. This does
   **not** rely on `$HOME`, env-var persistence, the auto-memory subsystem, or writing
   into your repo. Only the resulting JSON goes to stdout; all logs go to stderr.

> **Must run as a SessionStart hook, not the setup script.** `additionalContext` only
> works from a per-session hook (the setup script runs once at build time as root, with
> no session context — that's why pointing memory env-vars there does nothing).

### Private memory vault — set `KEV_MEM_TOKEN`

The vault is private, and cloud's built-in git auth only covers the working repo. To let
the bootstrap clone it, add a **fine-grained GitHub token** (repo `claude-memory`,
Contents: Read — add Write only if you want cloud→memory push-back) as an Environment
variable named `KEV_MEM_TOKEN`. The script authenticates with it and then scrubs the token
from the clone's git config. Without the token, the memory step simply no-ops.

## Using it

**Commit `cloud/settings.json` as the repo's `.claude/settings.json`** (or merge its
`hooks.SessionStart` entry into an existing one). Every cloud session on that repo then
runs the hook, which injects skills + memory. This is the reliable path.

**Account-wide via the setup script:** the build-time setup script can't inject context
itself, but it *can* drop the hook into the working tree so each session fires it —
e.g. `mkdir -p "$CLAUDE_PROJECT_DIR/.claude"` then `curl -fsSL <pinned cloud/settings.json> -o "$CLAUDE_PROJECT_DIR/.claude/settings.json"`
(only if the repo doesn't already ship its own). Either way, set `KEV_MEM_TOKEN` (above).

Verify on a real session: ask *"what do you remember about me?"*.

## What stays out of cloud

Secrets are never cloned. Memory write-back from cloud is opt-in and needs a token
provided via the cloud Environment's env vars.
