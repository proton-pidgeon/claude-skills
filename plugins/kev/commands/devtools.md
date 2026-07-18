---
description: Remotely debug a running web app through Chrome DevTools — attach to a real logged-in session or a clean one, then read console errors and failed requests directly.
---

Use the `remote-debug` skill.

Arguments (all optional): `$ARGUMENTS`

Interpret them as:
- an app URL to debug (e.g. `http://localhost:5173/checkout`)
- a mode hint — `clean` or `attach`
- a port — `--port 9333`
- a symptom description in prose

If no mode is given, infer it from the symptom per the skill's mode table: bugs
behind a login go to `attach`, everything else to `clean`. State the chosen mode
and why in one line before launching.

Always run the preflight before any DevTools MCP call, and do not proceed on any
state other than `HEALTHY`.
