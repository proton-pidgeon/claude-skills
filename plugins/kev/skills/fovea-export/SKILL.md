---
name: fovea-export
description: Export a book from the local Fovea library by title and save it into a folder for that book inside Kevin's personal OneDrive Documents/Books folder. Use when Kevin asks to export, save, pull, or send a Fovea book to OneDrive, or names a book he wants out of Fovea as a file.
---

# Fovea → OneDrive export

Export books from Kevin's Fovea library with the `fovea` MCP server tools and
save them into a per-book folder inside his personal OneDrive Books folder on
this machine.

**Requirements:** the `fovea` MCP server installed and paired on this host (it
runs on the Mac Studio and the fleet hosts ravenz-node, alienlap, and bb-mm,
each paired as its own Fovea device). If the `fovea` tools are not available
in this session, say so and stop.

## Destination — this host's OneDrive Books folder, then a folder for the book

First find this host's Books folder — use the first of these that fits the
machine you are running on:

- **Mac Studio:** `/Users/k3v/Library/CloudStorage/OneDrive-Personal/Documents/Books`
- **Windows (ravenz-node, alienlap):** `%USERPROFILE%\OneDrive\Documents\Books` —
  the personal OneDrive root is the plain `OneDrive` folder, NOT
  `OneDrive - Colostate` or any other org folder. If `Documents` exists but
  `Books` does not, create `Books`.
- **Any other Mac:** `~/Library/CloudStorage/OneDrive-Personal/Documents/Books`
  if that OneDrive folder exists.
- **No OneDrive on this host** (e.g. bb-mm): export to `~/Downloads/fovea`
  instead, and state plainly in your report that the file went to Downloads
  because this host has no OneDrive.

The export destination is a **folder for the book inside Books**:
`Books/<book title>/`. Name it with the book's full title exactly as
`resolve_title` returns it, replacing any characters that are illegal in
folder names (`/ \ : * ? " < > |`) with `_` and trimming trailing dots or
spaces. Create the folder if it doesn't exist. All formats exported for the
same book live together in that book's folder. (The no-OneDrive fallback
keeps `~/Downloads/fovea` as the destination, with the same per-book folder
inside it.)

Never save exports anywhere else unless Kevin names a different folder in the
request.

## Steps

1. **Resolve the title.** Call `resolve_title` with the name Kevin gave —
   partial and fuzzy names are fine.
   - One strong candidate → use it.
   - Several plausible candidates → show Kevin title + author for each and
     ask which one. Never guess between different books.
   - No candidates → say so, and offer the closest titles from `list_titles`.
2. **Check for an existing export.** Look in the book's folder (create the
   folder name in your head from the resolved title, as above). If a file
   for this book (matching title, `.md` or `.pdf`) is already there and Kevin
   didn't ask to refresh/re-export it, tell him it's already exported (name +
   size) and stop. A matching file sitting loose directly in Books (from an
   older export) counts as already exported too — mention where it is.
3. **Export.** Create the book's folder if needed, then call `export_book`
   with the chosen `book_id` and `out_dir` set to the book's folder.
   - `format: "markdown"` by default.
   - `format: "pdf"` only when Kevin asks for PDF — warn him first that the
     server renders it and the export can take a few minutes.
   - `format: "obsidian"` only when Kevin explicitly asks for Obsidian.
4. **Verify and report.** Confirm the returned `path` is inside the book's
   folder and `bytes` > 0. Report one line: book title, format,
   file name, size, and where it landed — e.g. "Exported *Tractatus
   Logico-Philosophicus* (Markdown, 412 KB) to
   OneDrive/Documents/Books/Tractatus Logico-Philosophicus/."

## If a tool returns an authentication error

The MCP server talks to Fovea as this host's paired device (`vesper-ai` on
the Studio, `fovea-ravenz` on ravenz-node, `fovea-alienlap` on alienlap,
`fovea-bbmm` on bb-mm). Pairing is normally already done. If calls fail with
an auth error, re-pair once with this host's device name, then retry:

1. In this host's `mcp-server` directory (Studio:
   `/Users/k3v/code-local/fovea/mcp-server`; Windows:
   `%USERPROFILE%\code-local\fovea\mcp-server`; bb-mm:
   `/Users/me/code-local/fovea/mcp-server`), run
   `uv run fovea-mcp-pair --device-name <this host's device name> --base-url http://kevs-mac-studio.tail46ac84.ts.net:8421`
   (on the Studio itself the base URL can stay the default localhost). It
   calls pair-init and prompts for a 6-digit code.
2. The code is written to the Fovea service log **on the Studio**:
   `grep "PAIRING CODE for '<device name>'" ~/Library/Application\ Support/Fovea/logs/service.*.log | tail -1`
   (codes expire in 5 minutes).
3. Give the code to the CLI, then retry the export.

If it still fails, stop and report the exact error — do not loop retries.

## Rules

- Export only. Never delete or rename files already in the destination
  folder, and never change anything in the Fovea library itself.
- Always pass `out_dir` explicitly — never rely on the tool's default
  download folder (except for the no-OneDrive fallback above, where Downloads
  is the explicit choice).
- One folder per book inside Books; every export of that book goes in its
  folder, never loose in Books itself.
