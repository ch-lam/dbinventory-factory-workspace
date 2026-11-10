#!/usr/bin/env node
// =============================================================================
// compare-compiler-metadata.cjs — what changes between two APEXLang compilers
//
// Run it when SQLcl (or the VS Code extension) brings a new APEXLang compiler.
// It answers the three questions a compiler upgrade raises for this repository:
//
//   1. Is apexlang/assets/component-attributes.json still true? Oracle ships it
//      for one build only, and the offline audit fails as soon as the build
//      changes (COMPILER_TRUTH_COMPONENT_ATTRIBUTES_STALE). It may be
//      re-stamped only if no property or enum value it relies on disappeared.
//      Any such regression makes this script exit 1.
//   2. Which DEFAULT values changed? A property left out of the .apx takes the
//      compiler's default: a changed default can change the application without
//      a single line of the .apx changing. Check each one against the .apx and
//      against what the instance actually stored after import.
//   3. What did the new compiler ADD? It accepts it, an older APEX instance may
//      not know it. Do not use it while the instance lags behind the compiler.
//
// Usage (from anywhere):
//   node .agents/skills/apex/compare-compiler-metadata.cjs --old <jar> --new <jar>
// <jar> is an apexlang-compiler.jar, or any home query-valid-props.mjs accepts.
// Keep the previous SQLcl around (renamed) until this has been run.
// =============================================================================
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execFileSync } = require('child_process');

const SKILL_DIR = path.join(__dirname, 'apexlang');
const CURATED = path.join(SKILL_DIR, 'assets', 'component-attributes.json');

function arg(name) {
  const i = process.argv.indexOf(name);
  return i > 0 ? process.argv[i + 1] : undefined;
}
const oldJar = arg('--old'), newJar = arg('--new');
if (!oldJar || !newJar) {
  console.error('Usage: compare-compiler-metadata.cjs --old <compiler jar or home> --new <compiler jar or home>');
  process.exit(2);
}

// The full normalized compiler map, as the audit itself sees it.
function dumpMap(jar, label) {
  const out = path.join(os.tmpdir(), `apexlang-map-${label}-${process.pid}.json`);
  const json = execFileSync(process.execPath,
    ['tools/query-valid-props.mjs', '--compiler-oracle-home', jar, '--json'],
    { cwd: SKILL_DIR, maxBuffer: 256 * 1024 * 1024, stdio: ['ignore', 'pipe', 'ignore'] });
  fs.writeFileSync(out, json);
  const map = JSON.parse(json);
  fs.unlinkSync(out);
  return map;
}
const m1 = dumpMap(oldJar, 'old'), m2 = dumpMap(newJar, 'new');
const curated = JSON.parse(fs.readFileSync(CURATED, 'utf8'));
console.log(`old compiler: ${m1.compilerTruth.buildID} (${m1.compilerTruth.metadataHash})`);
console.log(`new compiler: ${m2.compilerTruth.buildID} (${m2.compilerTruth.metadataHash})`);
console.log(`component-attributes.json stamped for: ${curated.compilerProvenance.buildID}\n`);

// ── 1. The curated subset ────────────────────────────────────────────────────
// APEXLang flattens the compiler's "attributes" level, so a curated property is
// looked up by name across every component type, as the audit does.
function byName(m) {
  const res = new Map();
  for (const c of m.componentTypes) for (const props of Object.values(c.groups || {})) for (const p of props) {
    if (!res.has(p.propertyName)) res.set(p.propertyName, []);
    res.get(p.propertyName).push(p);
  }
  return res;
}
const N1 = byName(m1), N2 = byName(m2);
const hasEnum = (N, name, v) => (N.get(name) || []).some(p => (p.lov?.values || []).some(x => x.name === v));
const regressions = [], neither = [];
let nProps = 0, nEnums = 0;
for (const [kind, subs] of Object.entries(curated.components)) {
  for (const [sub, spec] of Object.entries(subs)) {
    for (const [group, g] of Object.entries(spec)) {
      if (!g || typeof g !== 'object' || Array.isArray(g)) continue;
      const names = new Set([...(g.allowedProperties || []), ...(g.requiredProperties || []),
        ...Object.keys(g.propertyEnums || {}), ...Object.keys(g.enforcedValues || {})]);
      for (const name of names) {
        nProps++;
        const where = `${kind}.${sub}.${group}.${name}`;
        if (!N1.has(name) && !N2.has(name)) { neither.push(where); continue; }
        if (N1.has(name) && !N2.has(name)) { regressions.push(`property gone: ${where}`); continue; }
        for (const v of g.propertyEnums?.[name] || []) {
          if (typeof v !== 'string') continue;
          nEnums++;
          if (hasEnum(N1, name, v) && !hasEnum(N2, name, v)) regressions.push(`enum value gone: ${where} = ${v}`);
        }
      }
    }
  }
}
console.log(`1. Curated subset: ${nProps} properties, ${nEnums} enum values checked`);
console.log(`   regressions: ${regressions.length}`);
regressions.forEach(x => console.log(`     ${x}`));
console.log(`   in neither compiler (plugin settings, outside compiler metadata): ${neither.length}`);

// ── 2 and 3. Per component type, same property id ─────────────────────────────
const types = m => new Map(m.componentTypes.map(c => [c.componentTypeId, c]));
const T1 = types(m1), T2 = types(m2);
const flat = c => {
  const r = new Map();
  for (const [g, ps] of Object.entries(c.groups || {})) for (const p of ps) r.set(`${g}.${p.propertyName}`, p);
  return r;
};
const defaults = [], added = [], removed = [];
for (const [id, c2] of T2) {
  const label = `${c2.singular}#${id}${c2.parentComponentType ? ' <- ' + c2.parentComponentType : ''}`;
  const c1 = T1.get(id);
  if (!c1) { added.push(`${label}: new component type`); continue; }
  const f1 = flat(c1), f2 = flat(c2);
  for (const [k, p2] of f2) {
    const p1 = f1.get(k);
    if (!p1) { added.push(`${label}: ${k}`); continue; }
    if (JSON.stringify(p1.defaultValue) !== JSON.stringify(p2.defaultValue)) {
      defaults.push(`${label}: ${k}  ${JSON.stringify(p1.defaultValue)} -> ${JSON.stringify(p2.defaultValue)}`);
    }
    const v1 = new Set((p1.lov?.values || []).map(v => v.name));
    const newValues = (p2.lov?.values || []).map(v => v.name).filter(v => !v1.has(v));
    if (newValues.length) added.push(`${label}: ${k} = ${newValues.join(', ')}`);
  }
  for (const k of f1.keys()) if (!f2.has(k)) removed.push(`${label}: ${k}`);
}
for (const [id, c1] of T1) if (!T2.has(id)) removed.push(`${c1.singular}#${id}: component type`);

console.log(`\n2. Default values changed: ${defaults.length}  (an omitted property follows them)`);
defaults.forEach(x => console.log(`     ${x}`));
console.log(`\n3. Added by the new compiler: ${added.length}  (unknown to an older APEX instance)`);
added.forEach(x => console.log(`     ${x}`));
console.log(`\n   Removed by the new compiler: ${removed.length}`);
removed.forEach(x => console.log(`     ${x}`));

if (regressions.length) {
  console.log('\nDo NOT re-stamp component-attributes.json: fix or drop the entries above first.');
  process.exit(1);
}
console.log(`\ncomponent-attributes.json may be re-stamped for ${m2.compilerTruth.buildID} (${m2.compilerTruth.metadataHash}).`);
