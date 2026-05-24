# Cloud surfaces (claude.ai/code web + mobile)

Cloud sessions run in ephemeral sandboxes that **do not read your `~/.claude`** — no
personal plugins, skills, or memory. They only see what's **committed into the repo**
plus what a repo-committed `SessionStart` hook pulls in. This folder bridges that gap.

## How it works

`bootstrap-cloud.sh` runs at session start (only when `CLAUDE_CODE_REMOTE=true`) and:

1. **Skills + commands (reliable):** clones `claude-skills` and copies the `kev`
   plugin's skills/commands into the session's `.claude/`, so `/ingest`, `/shannon`,
   `/telegram` etc. are available.
2. **Memory (best-effort):** clones the `claude-memory` vault and (a) sets
   `CLAUDE_COWORK_MEMORY_PATH_OVERRIDE` for the session and (b) injects an
   `@import` of `MEMORY.md` into the project `CLAUDE.md` inside a marked block.

### Private memory vault — set `KEV_MEM_TOKEN`

The vault is private, and cloud's built-in git auth only covers the working repo. To let
the bootstrap clone it, add a **fine-grained GitHub token** (repo `claude-memory`,
Contents: Read — add Write only if you want cloud→memory push-back) as an Environment
variable named `KEV_MEM_TOKEN`. The script authenticates with it and then scrubs the token
from the clone's git config. Without the token, the memory step simply no-ops.

> ⚠️ **Verify the memory path on a real cloud session.** Cloud memory behaviour is
> the least certain part of this design; the skills bootstrap is solid. If the env
> override isn't honoured, the `CLAUDE.md` import fallback still surfaces the memory.

## Using it — two options

**Per repo (simplest):** copy `cloud/settings.json` to that repo's `.claude/settings.json`
(or merge its `hooks.SessionStart` entry into an existing one) and commit. Every cloud
session on that repo will bootstrap automatically.

**Cloud Environment (account-wide):** in claude.ai/code → Environment settings, add the
one-line `curl … | bash` from `cloud/settings.json` to the **setup script**, so it runs
without per-repo committing. Set `KEV_MEM_TOKEN` (above) so the private vault can be pulled.

## What stays out of cloud

Secrets are never cloned. Memory write-back from cloud is opt-in and needs a token
provided via the cloud Environment's env vars.
