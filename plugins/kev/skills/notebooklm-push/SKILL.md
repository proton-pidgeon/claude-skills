---
name: notebooklm-push
description: Send a finished research report to Google NotebookLM and generate an Audio Overview (podcast), via the Rhapsode bridge on the home Mac (fronted by Peggy). Use when the user runs `/notebooklm`, or asks to "send this to NotebookLM", "make a podcast of this report", "push this report to NotebookLM", "turn this into an Audio Overview", or "create a notebook from this report". Defaults to the most recent research report in the session; accepts a file path or pasted markdown as an argument. Works on every Claude surface: MCP tools (`notebooklm_*`) when the Rhapsode connector is available — including cloud sessions with no credentials file — and a curl helper script when it is not. Handles preflight, async submit + poll, and honest failure surfaces (stale Google session, upstream changes).
---

# notebooklm-push — report → NotebookLM notebook + podcast

Take a finished research report (typically a `deep-research` output) and get it into Google
NotebookLM as a **fresh notebook with the report as a source and an Audio Overview (podcast)**
generated from it. Works from any Claude surface: `/notebooklm` in Claude Code, or natural
language on web/mobile.

```
report markdown ──▶ Rhapsode bridge (home Mac, behind Peggy) ──▶ NotebookLM
                     submit → job id → poll → notebook URL + audio
```

This skill is a **thin client** over the bridge. All the unstable, session-bound NotebookLM
machinery lives server-side on the Mac; this skill only makes authenticated calls, which is why
it works from a phone with no browser and no Google cookies on the client.

## Pick the path first: MCP tools, else the script

The bridge has two front doors. **Check for the MCP tools before anything else** — if tools named
`notebooklm_submit_report`, `notebooklm_get_job` etc. are available in this session, the Rhapsode
connector is attached and that is the path to use.

| | Use when | Why |
|---|---|---|
| **MCP tools** (preferred) | `notebooklm_*` tools are present | The connector carries its own auth, so this works in a **cloud session** where no `~/.claude/.notebooklm` can exist. Returns richer results: server-supplied `guidance` on failure, and a **signed audio link that needs no credentials**. |
| **Helper script** (fallback) | No MCP tools, but `~/.claude/.notebooklm` exists | Local Claude Code / a real shell. Same bridge, same job, older door. |

If neither is available, stop and tell the user how to fix it (attach the connector, or create the
credentials file below). Do not improvise a third path.

### Via MCP tools

1. Optionally `notebooklm_health` first — if `auth.state` isn't `fresh`, warn up front that a
   re-login on the Mac is likely needed rather than letting the user wait for a failure.
2. `notebooklm_submit_report` with `{title, markdown}` (plus optional `audio_instructions`,
   `source_label`). Returns a `job_id` immediately.
3. Poll `notebooklm_get_job`, or call `notebooklm_wait_for_job` to block for up to ~2 minutes.
   **Generation normally takes 5–15 minutes**, so a `RUNNING` return is expected, not a failure.
   Either call again or tell the user it's still working and stop — the bridge pushes the result to
   Kev's Telegram when it lands, so nobody has to sit and watch.
4. On `DONE`, give the user the `notebook_url` **and** the `audio_url`. That audio link is signed
   and needs no credentials — it opens straight in a browser or on a phone, so hand it over as-is.

`notebooklm_submit_report` is idempotent on (title, markdown): resubmitting an identical document
returns the existing job with `deduplicated: true` rather than making a second notebook. If that
happens, say so instead of reporting it as fresh work.

**`notebooklm_delete_notebook` is destructive** — it permanently removes a notebook from Kev's
Google account. Confirm with the user before calling it, always.

## Why a service (don't try to run notebooklm-py here)

`notebooklm-py` has no official Google API — it drives a logged-in browser session that must
live on a real host. Do **not** attempt to invoke it directly from a Claude sandbox, install
it, or handle Google cookies. The only correct path is calling the bridge. If the bridge is
unreachable, report that — don't fall back to anything local.

## Configuration — for the script path only

The MCP connector carries its own auth and needs none of this. For the **helper-script** path,
credentials live in **`~/.claude/.notebooklm`** (gitignored, created by the user once):

```
NOTEBOOKLM_BRIDGE_URL="https://<peggy-host>/notebooklm"   # no trailing slash
NOTEBOOKLM_BEARER_TOKEN="<token>"
```

Never print, echo, or commit the token. If the file is missing or either value is empty **and**
there are no MCP tools, stop and tell the user to create it (show the two lines above), then halt —
do not proceed.

## Resolve the report

In order:
1. Empty argument or `last` → the **most recent research report** in this session (latest
   deep-research artifact). If there is none, say so and stop.
2. A readable file path → that file's contents.
3. Otherwise → treat the argument as report markdown directly.

Derive the **notebook title** from the report's first `# H1` line (strip the `#`). If there is
no H1, use the first non-empty line, truncated to ~200 chars.

## Fallback path — the helper script

Only when there are no MCP tools. All HTTP is done by `scripts/notebooklm_push.sh` (curl-based:
submit, then poll). Invoke it; do not reimplement the calls inline.

```bash
bash ${CLAUDE_PLUGIN_ROOT}/scripts/notebooklm_push.sh --file <path-to-report.md> --title "<title>"
# or, for pasted text, the command writes a temp file first and passes --file
# optional: --instructions "<audio style>"  (omit to use the bridge's house style)
```

The script:
1. Sources `~/.claude/.notebooklm`; fails clearly if creds are missing.
2. `POST {BRIDGE_URL}/reports` with the bearer token and `{title, markdown}` → expects `202`
   with a `job_id` and `poll_url`.
3. Polls `GET {BRIDGE_URL}/reports/{job_id}` every ~12s until the state is terminal.
4. On `DONE` → prints `notebook_url` and an `audio_url`.
5. On any `FAILED_*` → prints the stage and error message and exits non-zero.

Surface its output to the user plainly. On success, give the **clickable notebook URL** and
note the **podcast** is downloadable at the audio URL (same bearer).

## Interpreting failures — prefer the bridge's own words

**If the response carries a `guidance` field, use it.** The bridge knows why a job failed, so it
now says what to do about it, and its answer is authoritative over anything below. It also returns
`retryable` — honour that rather than guessing. MCP responses always carry both.

The table below is a **fallback** for the script path, which doesn't surface `guidance`:

| State / kind | What to tell the user |
|--------------|-----------------------|
| `503` on submit / `FAILED_AUTH` / `auth_stale` | The NotebookLM Google session on the Mac has expired. Someone must run `./re-auth.sh` on the host; this can't be fixed remotely. |
| `FAILED_UPSTREAM` / `endpoint_changed` | NotebookLM changed internally; `notebooklm-py` likely needs an upgrade on the host. Point to the bridge's conformance check. |
| `FAILED_UPSTREAM` / `rate_limited` | Throttled. Wait a bit and resend. |
| `FAILED_UPSTREAM` / `generation_failed` | The Audio Overview was refused/aborted. Retry, optionally simpler instructions. |
| `FAILED_TIMEOUT` / `timeout` | A stage ran over budget (host asleep or upstream slow). Retry. |
| `FAILED_INTERNAL` / `internal` | Bridge-side bug (disk/DB). Check host logs. |
| `FAILED_INTERNAL` / `interrupted` | The bridge restarted mid-job. Markdown is never stored at rest, so it can't resume — submit again. |

Don't retry automatically on `FAILED_AUTH` or `FAILED_INTERNAL` — those need a human.

One more MCP-only failure worth naming: `notebooklm_submit_report` rejects documents over
**150,000 characters**, because the model has to type the whole thing into the tool call and a
silently truncated document produces a confidently wrong podcast. If that fires, send a curated
brief instead of the whole corpus — or use the script path, which streams the file.

## Preflight (quick, before submitting)

1. Are the `notebooklm_*` MCP tools available? If yes, use them and skip step 2.
2. Otherwise `test -f ~/.claude/.notebooklm` and both vars non-empty — else stop with setup
   instructions.
3. Optional health check: `notebooklm_health`, or `GET {BRIDGE_URL}/healthz` (unauthenticated). If
   `status` is `degraded` with `auth.state: stale`, warn the user up front that a re-login is likely
   needed, but you may still submit (the bridge will `503` cleanly if so).

## Guardrails — refuse these

- Never run or install `notebooklm-py` locally, or handle Google cookies/session files.
- Never print or commit `NOTEBOOKLM_BEARER_TOKEN`.
- Never fall back to a non-bridge path if the bridge is down — report the outage instead.
- Don't claim success until the bridge reports `DONE` with a real notebook URL and a non-trivial
  audio file (the bridge verifies size; trust its terminal state, not a guess).
- Never call `notebooklm_delete_notebook` without explicit confirmation — it is irreversible.

## Composition

Pairs with `deep-research`: research a topic → report artifact → `/notebooklm` (or "send it
to NotebookLM") → notebook + podcast. The two are independent; this skill only needs the
report markdown and the bridge.
