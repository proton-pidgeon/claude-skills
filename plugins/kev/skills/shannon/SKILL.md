---
name: shannon
description: Run Shannon (Keygraph's autonomous AI pentester) against a web app. Use when the user wants to launch a security scan, resume a Shannon workspace, check scan status, view logs, or stop a run. Shannon executes real exploits against the target — only use against systems the user owns or has written authorization to test.
---

# Shannon — autonomous AI pentester

Shannon is a standalone CLI from Keygraph that performs white-box pentesting: it reads a repo, identifies attack vectors, then actively exploits them against the running app. It runs in Docker and is installed via `npx @keygraph/shannon`.

## Critical safety rules

Before launching any scan, confirm with the user:

1. **Target ownership** — Shannon executes real exploits (SQLi, XSS, SSRF, auth bypass). The user must own the target or have explicit written authorization. If the URL looks like a third-party production system and authorization isn't already established in the conversation, ask before proceeding.
2. **Not production** — refuse to run against prod. Shannon can create users, modify data, trigger side effects. Staging/local/sandbox only.
3. **Cost/time awareness** — a full run is ~1–1.5 hours and ~$50 in API costs (Sonnet pricing). Mention this if the user seems unaware.

If any of these are unclear, ask before running `start`.

## Common invocations

The user typically points Shannon at a URL (`-u`) and a repo path (`-r`).

```bash
# Basic scan
npx @keygraph/shannon start -u <url> -r <repo-path>

# With config (auth, ROE, vuln class filters)
npx @keygraph/shannon start -u <url> -r <repo-path> -c <config.yaml>

# Named workspace (for resumability)
npx @keygraph/shannon start -u <url> -r <repo-path> -w <name>

# Custom output dir
npx @keygraph/shannon start -u <url> -r <repo-path> -o <out-path>

# Resume an interrupted/failed run — same -w name, URL must match original
npx @keygraph/shannon start -u <url> -r <repo-path> -w <existing-workspace>

# Inspect / control
npx @keygraph/shannon workspaces           # list all
npx @keygraph/shannon status                # current run state
npx @keygraph/shannon logs <workspace>      # tail logs for a workspace
npx @keygraph/shannon stop                  # stop current
npx @keygraph/shannon stop --clean          # stop + remove containers
npx @keygraph/shannon uninstall             # full teardown
npx @keygraph/shannon setup                 # re-run credential wizard
```

Temporal Web UI for live monitoring: `http://localhost:8233`.

## Local target gotcha

Docker can't reach `localhost` on the host. For local apps use `http://host.docker.internal:<port>` instead of `http://localhost:<port>`. Catch this and rewrite the URL if the user passes a localhost URL.

## Workspaces

- Auto-named like `<hostname>_shannon-<timestamp>` if `-w` is omitted.
- Stored at `~/.shannon/workspaces/` (npx mode).
- Resuming requires the same URL — Shannon rejects URL mismatches.
- Each agent's progress is git-checkpointed inside the workspace; a resumed run skips completed agents.

## Output

Final report lands at:
```
~/.shannon/workspaces/<workspace>/deliverables/comprehensive_security_assessment_report.md
```

Other useful paths inside the workspace: `session.json` (metrics), `workflow.log` (human-readable), `agents/` (per-agent logs), `prompts/` (prompt snapshots).

## Config file (`-c`)

Use a YAML config for: authenticated scans (form/SSO login + optional TOTP), restricting vuln classes, scoping rules (`avoid`/`focus` by url_path/subdomain/code_path/etc.), and report filters. Template lives at `configs/example-config.yaml` in the Shannon repo.

**Schema constraints (preflight will reject these):**
- `description` is hard-capped at **500 characters**. Keep target context tight; move long-form notes into `rules_of_engagement` (which has no documented limit). Validate before launching — a violation fails the workflow at `runPreflightValidation` after the worker image has already pulled.

**Any first-launch failure leaves a poisoned workspace.** Two rules compound:
1. `persistOrValidateRunScope` runs *before* config validation, so the workspace pins its scope (`vuln_classes`, `exploit`) on launch — even if preflight then errors. Re-running with different scope fails with `ScopeMismatchError`.
2. `loadResumeState` only allows resume when at least one agent has checkpointed. A workspace whose first launch died at preflight has no checkpoints and fails with `NoCheckpointsError` ("No agents completed successfully. Start a fresh run instead.").

**Practical rule:** if preflight (or any pre-agent activity) fails, the workspace is dead. Either `rm -rf ~/.shannon/workspaces/<name>` and re-run with the same `-w`, or use a new `-w` name. Don't try to recover by changing the config and re-running on the same workspace.

**`code_path` patterns must match real files in the repo.** Preflight rejects any `code_path` rule (in `rules.avoid` or `rules.focus`) that matches zero files/dirs. Don't add defensive "just in case" patterns. Before configuring `code_path` rules, verify they exist with `ls` or `find` against the actual repo. Patterns are relative to the repo root and accept globs (e.g., `web/node_modules/**`).

Common patterns:

```yaml
authentication:
  login_type: form
  login_url: "https://target/login"
  credentials:
    username: "..."
    password: "..."
    totp_secret: "..."   # optional, for 2FA
  login_flow:
    - "Type $username into the email field"
    - "Type $password into the password field"
    - "Click 'Sign In'"
  success_condition:
    type: url_contains
    value: "/dashboard"

# Limit scope
vuln_classes: [injection, xss, auth, authz, ssrf]   # all five by default
exploit: "false"   # skip exploitation phase, analysis only

# Subscription-plan rate-limit handling (Claude Code OAuth users)
pipeline:
  retry_preset: subscription
  max_concurrent_pipelines: 2
```

## When the user is just asking about Shannon

If the user is asking conceptual questions ("what does Shannon do", "how does it work"), answer from the architecture summary below — don't run the CLI:

- 5 phases: Pre-Recon (source scan) → Recon (attack surface map via browser) → Vuln Analysis (5 parallel agents, one per OWASP class) → Exploitation (parallel, "no exploit, no report" policy) → Reporting.
- Coverage: Injection, XSS, SSRF, Broken Auth, Broken Authz. Does **not** cover SCA, secrets, vulnerable libraries (Shannon Pro does).
- Each scan runs in an ephemeral `docker run --rm` worker container; target repo mounted read-only.
- Officially supported only with Claude models. Routing through proxies/non-Claude models is at the user's risk.

## Don't

- Don't try to run `setup` non-interactively — it's a wizard. If credentials need configuring, tell the user to run `! npx @keygraph/shannon setup` themselves.
- Don't claim the scan finished until you've seen `status` show completion or the deliverables file exists.
- Don't summarize or interpret findings without the user asking — the report itself is the deliverable.
