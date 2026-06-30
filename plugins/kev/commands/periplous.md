---
allowed-tools: Bash(periplous:*), Bash(command -v periplous:*), Bash(periplous --version:*), Bash(periplous map:*), Bash(periplous get:*), Bash(periplous config:*), Bash(ls:*), Bash(cat:*), Read
description: Drive the Períplous Canvas tool for one course — map it, fetch a lecture's subtitles, or submit a user-supplied artifact (interactive)
argument-hint: "map <course> | subtitle <course> <day> | submit <course> <day> <artifact>  (empty = help)"
---

Trigger for the `periplous` skill — driving Kev's read-only Canvas course mapper plus its
two narrow actions (subtitle fetch, gated artifact submission). The skill holds the full logic
and also fires on natural language ("map my course", "get the captions for Lecture 5").

**If `$ARGUMENTS` is empty**, show this help text (do not run anything):

```
/periplous — map a Canvas course and run its two recurring chores

  /periplous map <course>                 Read-only recon: assignments + recordings +
                                           subtitles + Zoom-surface verdict + gaps
  /periplous subtitle <course> <day>      Download a lecture's .vtt  (read-only)
  /periplous submit <course> <day> <art>  Submit an artifact YOU provide (interactive gate)

  <course>  a named course in periplous.toml (e.g. intro-whatever)
  <day>     a lecture day: 2025-09-15  or  "Lecture 5"
  <art>     --file PATH | --text-file PATH | --url URL  (the work must be yours)

Read-only verbs (map, subtitle) are safe from anywhere, including Dispatch.
Submission is interactive and desktop-only: the CLI prints a preview and makes you
type the assignment name to confirm. It is never auto-confirmed, never over Dispatch.

Natural language works too (web/mobile):
  "map my <course>"     "what does Tuesday's assignment accept?"
  "get the subtitles for Lecture 5 in <course>"

First time: run  /periplous  then  periplous config check --course <name>  to see
your role and whether your token is self-serviceable / how long it lasts.
```

**If `$ARGUMENTS` is provided**, invoke the `periplous` skill to do the work. Parse the first
token as the verb:

1. `map <course>` (or any "map …" phrasing) → run the **map** verb: read-only reconnaissance,
   then surface the assignments table (with `submission_types`), recordings/subtitles, the
   ZoomSurface verdict, and any unresolved gaps verbatim.
2. `subtitle <course> <day>` (or "get/fetch captions/subtitles …") → run the **get subtitle**
   verb and report the saved `.vtt` path. If it's `needs_browser`, tell the user it requires
   the opt-in, attended browser fallback — don't launch it unprompted.
3. `submit <course> <day> <artifact>` → run the **submit** verb. The artifact must be supplied
   by the user; never generate submission content. Let the CLI's interactive confirmation gate
   run — relay the preview, do not type the confirmation yourself. **If this is reached over
   Dispatch or any unattended context, do not auto-confirm:** surface the preview and tell the
   user to confirm at the desktop.

Always run preflight first (per the skill: `command -v periplous`, `periplous --version`, token
present, course resolvable). Do not re-implement the CLI's logic here — defer to the `periplous`
skill, and if the CLI's `--help` disagrees with the skill, trust the CLI and say so.
