#!/usr/bin/env node
// kev plugin: regenerate the memory vault's MEMORY.md index from each memory
// file's frontmatter. MEMORY.md is DERIVED — the per-file frontmatter is the
// source of truth, which removes the index as a multi-host merge-conflict
// surface (the old failure mode: every session on every host edited the same
// index lines).
//
// Frontmatter fields used (all single-line; description may be `>`/`>-` folded):
//   name:        slug (fallback: filename without .md)
//   description: the text after the em-dash in the index line
//   metadata:
//     title:     display title for the index link (fallback: name)
//     section:   "## <section>" the entry lives under (fallback: "Other")
//     parent:    name/filename slug of the entry this nests under
//     order:     number; entries sort by (order, name); sections by min order
//
// Usage: node kev-memory-index.mjs <memory-dir>
// Best-effort: exits 0 unless the dir is unusable; writes only on change.

import { readdirSync, readFileSync, writeFileSync, existsSync } from 'node:fs';
import { join, basename } from 'node:path';

const SIZE_WARN_BYTES = 24000; // the harness truncates the index near 24.4KB

const memDir = process.argv[2];
if (!memDir || !existsSync(memDir)) {
  console.error(`[kev-memory-index] memory dir not found: ${memDir}`);
  process.exit(1);
}

function unquote(v) {
  v = v.trim();
  if (v.length >= 2 && v[0] === "'" && v.endsWith("'")) {
    return v.slice(1, -1).replace(/''/g, "'");
  }
  if (v.length >= 2 && v[0] === '"' && v.endsWith('"')) {
    return v.slice(1, -1).replace(/\\"/g, '"');
  }
  return v;
}

// Minimal frontmatter reader for the constrained shape this vault uses.
function parseFrontmatter(text) {
  const lines = text.split(/\r?\n/);
  if (lines[0] !== '---') return null;
  const fm = { metadata: {} };
  let inMeta = false;
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i];
    if (line === '---') return fm;
    let m;
    if ((m = line.match(/^(\w[\w-]*):\s*(.*)$/))) {
      inMeta = m[1] === 'metadata';
      if (!inMeta) {
        let val = m[2];
        if (val === '>' || val === '>-' || val === '') {
          // folded block scalar: join the following more-indented lines
          const parts = [];
          while (i + 1 < lines.length && /^\s+\S/.test(lines[i + 1])) {
            parts.push(lines[++i].trim());
          }
          val = parts.join(' ');
        }
        fm[m[1]] = unquote(val);
      }
    } else if (inMeta && (m = line.match(/^\s+(\w[\w-]*):\s*(.*)$/))) {
      fm.metadata[m[1]] = unquote(m[2]);
    }
  }
  return null; // unterminated frontmatter
}

const entries = [];
for (const f of readdirSync(memDir)) {
  if (!f.endsWith('.md') || f === 'MEMORY.md' || f === 'README.md') continue;
  let fm;
  try {
    fm = parseFrontmatter(readFileSync(join(memDir, f), 'utf8'));
  } catch {
    continue;
  }
  if (!fm) continue; // not a memory file (no frontmatter)
  const slug = basename(f, '.md');
  entries.push({
    file: f,
    slug,
    name: fm.name || slug,
    title: fm.metadata.title || fm.name || slug,
    description: fm.description || '',
    section: fm.metadata.section || 'Other',
    parent: fm.metadata.parent || null,
    order: Number.isFinite(parseFloat(fm.metadata.order))
      ? parseFloat(fm.metadata.order)
      : 9999,
  });
}

const bySlug = new Map();
for (const e of entries) {
  bySlug.set(e.slug, e);
  bySlug.set(e.name, e);
}

// Attach children to parents; everything else is top-level in its section.
const roots = [];
for (const e of entries) {
  const parent = e.parent && bySlug.get(e.parent);
  if (parent && parent !== e) (parent.children ??= []).push(e);
  else roots.push(e);
}

const cmp = (a, b) => a.order - b.order || a.name.localeCompare(b.name);
const sections = new Map();
for (const e of roots) {
  if (!sections.has(e.section)) sections.set(e.section, []);
  sections.get(e.section).push(e);
}
const sectionOrder = [...sections.entries()].sort((a, b) => {
  if (a[0] === 'Other') return 1;
  if (b[0] === 'Other') return -1;
  const min = (es) => Math.min(...es.map((e) => e.order));
  return min(a[1]) - min(b[1]) || a[0].localeCompare(b[0]);
});

const out = [];
out.push('# Memory Index');
out.push('');
out.push('<!-- GENERATED FILE — DO NOT EDIT DIRECTLY. This index is rebuilt from each');
out.push('     memory file\'s frontmatter (description + metadata.{title,section,parent,order})');
out.push('     by the kev plugin sync hooks on every session start/end; direct edits here');
out.push('     are overwritten. To add/update an entry, edit the memory file itself:');
out.push('     description: = the index line text after the em-dash. New files without');
out.push('     metadata.section land under "## Other" until categorized. -->');
for (const [section, secEntries] of sectionOrder) {
  out.push('');
  out.push(`## ${section}`);
  for (const e of secEntries.sort(cmp)) {
    out.push(`- [${e.title}](${e.file}) — ${e.description}`);
    for (const c of (e.children ?? []).sort(cmp)) {
      out.push(`  - [${c.title}](${c.file}) — ${c.description}`);
    }
  }
}
out.push('');
const content = out.join('\n');

const indexPath = join(memDir, 'MEMORY.md');
const bytes = Buffer.byteLength(content, 'utf8');
const prev = existsSync(indexPath) ? readFileSync(indexPath, 'utf8') : '';
if (content !== prev) {
  writeFileSync(indexPath, content);
  console.error(`[kev-memory-index] regenerated MEMORY.md (${entries.length} entries, ${bytes} bytes)`);
}
if (bytes > SIZE_WARN_BYTES) {
  console.error(`[kev-memory-index] WARNING: MEMORY.md is ${bytes} bytes (harness truncates near 24.4KB) — trim long description: fields`);
}
process.exit(0);
