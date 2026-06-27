---
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/notebooklm_push.sh:*), Bash(test -f ~/.claude/.notebooklm:*), Bash(source ~/.claude/.notebooklm:*), Bash(ls:*), Bash(cat:*), Read
description: Send a research report to Google NotebookLM and generate an Audio Overview (podcast)
argument-hint: "[report file path | \"last\" | pasted text]  (empty = most recent report)"
---

Send a research report into Google NotebookLM via the **notebooklm-bridge** service, which
creates a fresh notebook, adds the report as a source, and generates an Audio Overview
(podcast). This command is the Claude Code trigger for the `notebooklm-push` skill — the
skill holds the full logic and also fires on natural language ("send this to NotebookLM").

**If `$ARGUMENTS` is empty**, show this help text (do not run anything):

```
/notebooklm — push a research report to NotebookLM as a podcast

  /notebooklm                 Use the most recent research report in this session
  /notebooklm last            Same as above (explicit)
  /notebooklm <file.md>       Push a specific report file
  /notebooklm <pasted text>   Push pasted report markdown

Setup (first time): create ~/.claude/.notebooklm with:
  NOTEBOOKLM_BRIDGE_URL="https://<your-peggy-host>/notebooklm"
  NOTEBOOKLM_BEARER_TOKEN="<token>"

Natural language also works (web/mobile too):
  "send this report to NotebookLM"
  "make a podcast of this in NotebookLM"

Audio Overviews take a few minutes — this polls until ready and returns a
notebook link + downloadable MP3.
```

**If `$ARGUMENTS` is provided**, invoke the `notebooklm-push` skill to do the work. Resolve
the report to send as follows, in order:

1. If `$ARGUMENTS` is empty or exactly `last` → use the **most recent research report
   artifact** produced in this session (the latest deep-research output). If none exists in
   the session, say so and stop.
2. If `$ARGUMENTS` names a readable file → use that file's contents as the report.
3. Otherwise → treat `$ARGUMENTS` itself as the report markdown.

Then follow the `notebooklm-push` skill: preflight credentials, derive the title from the
report's H1, submit to the bridge, poll until terminal, and report the notebook URL + audio.
Do not re-implement the HTTP logic here — defer to the skill and its
`scripts/notebooklm_push.sh` helper.
