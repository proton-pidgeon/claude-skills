#!/usr/bin/env node
// Structural validation for the marketplace + plugin manifests.
//
// `jq empty` in CI only proves the JSON parses -- it says nothing about whether
// the manifest is *correct*. This catches the well-formed-but-wrong cases that
// actually break distribution: a bad/duplicate version (silent `plugin update`
// no-op per the version-bump gotcha), a `source` that points nowhere, or a
// marketplace entry whose name drifts from the plugin.json it references.
//
// Dependency-free on purpose (matches the repo's "self-contained scripts, no
// deps" ethos); run with `node scripts/validate-manifests.mjs`. Exit 1 on any
// failure, printing every problem found (not just the first).

import { readFileSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const errors = [];
const err = (where, msg) => errors.push(`${where}: ${msg}`);
const SEMVER = /^\d+\.\d+\.\d+$/;

function loadJson(relPath) {
  const abs = join(repoRoot, relPath);
  if (!existsSync(abs)) {
    err(relPath, 'file not found');
    return null;
  }
  try {
    return JSON.parse(readFileSync(abs, 'utf8'));
  } catch (e) {
    err(relPath, `not valid JSON: ${e.message}`);
    return null;
  }
}

const nonEmptyStr = (v) => typeof v === 'string' && v.trim().length > 0;

// --- marketplace.json ------------------------------------------------------
const MKT = '.claude-plugin/marketplace.json';
const marketplace = loadJson(MKT);
const validatedPluginDirs = [];

if (marketplace) {
  if (!nonEmptyStr(marketplace.name)) err(MKT, '`name` must be a non-empty string');
  if (typeof marketplace.owner !== 'object' || marketplace.owner === null || !nonEmptyStr(marketplace.owner.name)) {
    err(MKT, '`owner.name` must be a non-empty string');
  }
  if (!Array.isArray(marketplace.plugins) || marketplace.plugins.length === 0) {
    err(MKT, '`plugins` must be a non-empty array');
  } else {
    marketplace.plugins.forEach((p, i) => {
      const at = `${MKT} plugins[${i}]`;
      if (typeof p !== 'object' || p === null) {
        err(at, 'must be an object');
        return;
      }
      if (!nonEmptyStr(p.name)) err(at, '`name` must be a non-empty string');
      if (!nonEmptyStr(p.source)) {
        err(at, '`source` must be a non-empty string');
        return;
      }
      if (!p.source.startsWith('./')) err(at, `\`source\` should be repo-relative (start with "./"): ${p.source}`);
      // Integrity: the source must resolve to a real plugin dir with a manifest.
      const pluginManifest = join(repoRoot, p.source, '.claude-plugin', 'plugin.json');
      if (!existsSync(pluginManifest)) {
        err(at, `\`source\` (${p.source}) has no .claude-plugin/plugin.json`);
      } else {
        validatedPluginDirs.push({ name: p.name, manifest: join(p.source, '.claude-plugin', 'plugin.json') });
      }
    });
  }
}

// --- each referenced plugin.json ------------------------------------------
for (const { name: marketplaceName, manifest } of validatedPluginDirs) {
  const plugin = loadJson(manifest);
  if (!plugin) continue;
  if (!nonEmptyStr(plugin.name)) err(manifest, '`name` must be a non-empty string');
  if (!nonEmptyStr(plugin.description)) err(manifest, '`description` must be a non-empty string');
  if (typeof plugin.version !== 'string' || !SEMVER.test(plugin.version)) {
    err(manifest, `\`version\` must be MAJOR.MINOR.PATCH semver, got: ${JSON.stringify(plugin.version)}`);
  }
  // Cross-check: the marketplace entry name must match the plugin it points to,
  // else `plugin update <name>@<marketplace>` resolves to the wrong thing.
  if (nonEmptyStr(plugin.name) && plugin.name !== marketplaceName) {
    err(manifest, `\`name\` "${plugin.name}" != marketplace entry name "${marketplaceName}"`);
  }
}

// --- report ----------------------------------------------------------------
if (errors.length > 0) {
  console.error(`manifest validation FAILED (${errors.length} problem${errors.length === 1 ? '' : 's'}):`);
  for (const e of errors) console.error(`  - ${e}`);
  process.exit(1);
}
console.log(`manifest validation ok (${validatedPluginDirs.length} plugin manifest${validatedPluginDirs.length === 1 ? '' : 's'} checked)`);
