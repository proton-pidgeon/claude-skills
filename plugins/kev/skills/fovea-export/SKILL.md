---
name: fovea-export
description: Export a book from the local Fovea library by title and save it into Kevin's personal OneDrive Documents/Books folder. Use when Kevin asks to export, save, pull, or send a Fovea book to OneDrive, or names a book he wants out of Fovea as a file.
---

# Fovea → OneDrive export

Export books from the local Fovea service with the `fovea` MCP server tools and
save them to Kevin's personal OneDrive Books folder.

**Requirements:** the `fovea` MCP server (registered with Claude Code on the Mac
Studio, where the Fovea service and the OneDrive folder live). If the `fovea`
tools are not available in this session, say so and stop — this skill only
works on the Studio.

**Destination (always, unless Kevin names a different folder in the request):**
`/Users/k3v/Library/CloudStorage/OneDrive-Personal/Documents/Books`
(the same folder as `~/OneDrive/Documents/Books`; it syncs to his personal
OneDrive automatically).

## Steps

1. **Resolve the title.** Call `resolve_title` with the name Kevin gave —
   partial and fuzzy names are fine.
   - One strong candidate → use it.
   - Several plausible candidates → show Kevin title + author for each and
     ask which one. Never guess between different books.
   - No candidates → say so, and offer the closest titles from `list_titles`.
2. **Check for an existing export.** List the destination folder. If a file
   for this book (matching title, `.md` or `.pdf`) is already there and Kevin
   didn't ask to refresh/re-export it, tell him it's already exported (name +
   size) and stop.
3. **Export.** Call `export_book` with the chosen `book_id` and `out_dir` set
   to the destination above.
   - `format: "markdown"` by default.
   - `format: "pdf"` only when Kevin asks for PDF — warn him first that the
     server renders it and the export can take a few minutes.
   - `format: "obsidian"` only when Kevin explicitly asks for Obsidian.
4. **Verify and report.** Confirm the returned `path` is inside the
   destination folder and `bytes` > 0. Report one line: book title, format,
   file name, size — e.g. "Exported *Tractatus Logico-Philosophicus*
   (Markdown, 412 KB) to OneDrive/Documents/Books."

## If a tool returns an authentication error

The MCP server talks to Fovea as the paired device `vesper-ai`. Pairing is
normally already done. If calls fail with an auth error, re-pair once, then
retry the export once:

1. In `/Users/k3v/code-local/fovea/mcp-server`, run `uv run fovea-mcp-pair`
   (it calls pair-init and prompts for a 6-digit code).
2. Read the fresh code from the service log:
   `grep "PAIRING CODE for 'vesper-ai'" ~/Library/Application\ Support/Fovea/logs/service.*.log | tail -1`
   (codes expire in 5 minutes).
3. Give the code to the CLI, then retry the export.

If it still fails, stop and report the exact error — do not loop retries.

## Rules

- Export only. Never delete or rename files already in the Books folder, and
  never change anything in the Fovea library itself.
- Always pass `out_dir` explicitly — never rely on the tool's default
  download folder.
