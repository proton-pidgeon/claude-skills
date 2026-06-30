---
name: periplous
description: Drive the Períplous Canvas LMS tool for a single course — map a course's structure (assignments, recordings, subtitles, Zoom surface), download a lecture's subtitle (.vtt) file, or submit an artifact the user provides to an assignment. Use when the user runs `/periplous`, or asks to "map my course", "what does this assignment accept", "find/get the subtitles for <lecture day>", "pull the captions for <lecture>", or "submit my assignment for <day>". Mapping and subtitle fetch are read-only and safe to run from anywhere including Dispatch; submission is interactive-only and must never be auto-confirmed, especially over Dispatch.
---

# /periplous — map a Canvas course and run its two recurring chores

Períplous is Kev's read-only reconnaissance tool for a **single Canvas course**, plus a
narrowly-scoped actor that does exactly two things on the map it produces: fetch a lecture's
subtitle file, and submit an artifact the user hands it. This skill is the operator's playbook
for driving the `periplous` CLI from Cowork (and, for the read-only verbs, from Dispatch).

```
periplous map   ──▶ CourseMap (assignments + recordings + subtitles + Zoom-surface verdict)
periplous get   ──▶ download a lecture's .vtt          (read-only, Dispatch-safe)
periplous submit──▶ submit a user-supplied artifact    (interactive gate, desktop-only)
```

The repo (design + implementation) is at `proton-pidgeon/periplous`, locally expected at
`~/code-local/periplous`. The `periplous` command is on PATH.

## The one rule that overrides everything else

**Períplous transports artifacts the user authored; it never generates coursework, and it
never submits without the user seeing the preview and confirming.** Do not generate, complete,
paraphrase, or "improve" assignment content under any framing. Do not attempt to bypass,
auto-fill, or script past the submission confirmation gate. If asked to, refuse and explain.
This mirrors the project's own `docs/08-ethics-and-scope.md` — read it if there's any doubt.

## Preflight — confirm the tool is usable (do this first, every session)

1. **CLI present:** `command -v periplous` and `periplous --version`. If missing, the tool
   isn't installed on this host — stop and tell the user to install it (`pipx install` from
   `~/code-local/periplous`, or `pip install -e .`). Do not try to run the Python source by hand.
2. **Token available:** the course's token must be reachable (env var named in config, e.g.
   `PERIPLOUS_TOKEN`, or the macOS Keychain entry). Never print, echo, or log the token.
3. **Config / course known:** confirm which course is meant. Prefer a named course from
   `periplous.toml` (`--course <name>`); fall back to `--course-id <id> --base-url <url>`
   only if the user supplies them. If neither is resolvable, ask which course — don't guess.
4. **Institution reality (first run):** `periplous config check --course <name>` reports the
   user's role and whether the token is self-serviceable and how long it lasts (some
   institutions cap student tokens at ≤120 days or disable self-service). Surface this; don't
   try to work around an institutional control.

## Verb 1 — map (read-only reconnaissance)

```
periplous map --course <name>            # uses periplous.toml
periplous map --course-id <id> --base-url https://<school>.instructure.com
```

Useful flags: `--deep` (fetch all page/announcement bodies — heavier, throttle-aware),
`--refresh` (bypass the SQLite cache), `--format both` (default; JSON map + markdown survey).

After running, surface to the user, in plain language:
- the **assignments table** with each assignment's `submission_types` (this answers "what does
  it accept?" — `online_upload` / `online_text_entry` / `online_url`, or "not automatable"),
- the **recordings/subtitles** found and where they live,
- the **ZoomSurface verdict** (`api_files` / `api_links` / `lti_opaque` / `not_found`), which
  tells you up front whether subtitles are reachable by API or need the browser fallback,
- the **unresolved** gaps, verbatim, with their suggested actions — never paper over a gap.

Map is pure observation; it's always safe to run, re-run, and run from Dispatch.

## Verb 2 — get subtitle (read-only download)

```
periplous get subtitle --course <name> --day 2025-09-15
periplous get subtitle --course <name> --day "Lecture 5" --out ./subs
```

Reads the existing CourseMap, finds the subtitle for that lecture day, and writes the `.vtt`
locally (default `./subtitles/<course>-<day>.vtt`). Report the saved path and source.

- If the map has **no subtitle** for that day, relay the relevant `unresolved` gap and its
  suggested action rather than failing blankly. If no map exists yet, run `map` first.
- If the subtitle is marked **`needs_browser`** (an `lti_opaque` Zoom surface with no
  API-reachable `.vtt`), do **not** silently fail. Tell the user it requires the opt-in browser
  fallback (`periplous get subtitle --via-browser ...`, per the repo's `docs/09`), which is
  attended and desktop-oriented — don't launch it unprompted, and never as part of submission.

This verb only downloads; it changes nothing in Canvas and is **Dispatch-safe**. "Get me the
captions for last Tuesday's lecture" from the phone is the ideal use.

## Verb 3 — submit (interactive, gated, desktop-only)

```
periplous submit --course <name> --day 2025-09-15 --file ./out/ps3.pdf
periplous submit --course <name> --assignment 987 --text-file ./out/answer.md
periplous submit --course <name> --day 2025-09-22 --url https://github.com/me/repo
```

The artifact is **always supplied by the user** for this specific call (`--file` / `--text` /
`--text-file` / `--url`). The CLI validates the artifact kind against the assignment's
`submission_types` and the extension against `allowed_extensions`, then prints a preview and
**blocks for confirmation** (the user types the assignment name). There is no `--yes`/`--force`,
by design.

Your job around the CLI:
- Make sure the user has actually pointed at an artifact they authored. If they ask you to
  *produce* the submission content, refuse (see the rule above) — you may help them get a file
  to a submittable format, but the substance must be theirs.
- Let the CLI's interactive gate run; relay the preview faithfully; do not type the
  confirmation on the user's behalf.
- After a successful submit, report the receipt the CLI emits (submission id, `submitted_at`,
  attempt, state). The CLI also writes a local receipt file — mention where.

### Submission over Dispatch — refuse to auto-confirm

Dispatch is an away-from-keyboard, fire-and-forget surface with no completion notifications and
parallel task execution — exactly the conditions the gate exists to protect against. If a
**submission** is requested via Dispatch (or any non-interactive context where you cannot
guarantee the human is watching the gate):
- run up to the preview, **surface the preview and the due-time warning**, and
- tell the user to confirm the submission at the desktop. **Do not** confirm it for them and
  **do not** treat a chat "yes" as the gate. Retrieval verbs (map, get) are fine over Dispatch;
  submission is not.

## Exit codes (for reporting, the CLI defines these)

`0` ok · `2` partial map (gaps present) · `3` auth/token problem · `4` throttled past budget ·
`5` artifact/type mismatch on submit · `6` user declined at the confirmation gate. Translate
these into plain language for the user rather than just echoing the number.

## Guardrails — refuse these

- **No content generation for a submission**, under any framing (drafting, "improving",
  filling in, paraphrasing into an answer). Transport only.
- **No bypassing the submission gate** — no `--yes`, no scripted confirmation, no auto-confirm
  over Dispatch, no "submit all" / looping over days / scheduling submissions.
- **No evading institutional controls.** If the school restricts tokens or API use, report it;
  don't route around it. A technical path is not permission.
- **No token leakage.** Never print/echo/log the access token or put it in a URL.
- **No multi-student or at-scale scraping.** One course, one user, the two chores. That's it.

## Principles

- **The repo is the source of truth.** `~/code-local/periplous/docs/` (esp. `06-tool-design.md`
  and `08-ethics-and-scope.md`) defines the contract; this skill is the playbook, not the spec.
  If the CLI's `--help` disagrees with this file, trust the CLI and tell the user.
- **Read-only is free; writes are deliberate.** Map and get can run anytime, anywhere. Submit
  is a single, attended, confirmed act — keep it that way.
- **Surface gaps honestly.** A partial map with explicit unresolved entries is the correct
  output, not something to smooth over.
