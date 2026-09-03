// Génère le jeu de données de démonstration : les 56 CSV de collecte et les
// trois fichiers .lst de périmètre, à partir de world.json.
//
//   node fixtures/generate.mjs [dossier_de_sortie]
//   Défaut : fixtures/out
//
// Le résultat est reproductible au caractère près pour une graine donnée. Ce
// n'est pas un confort : le fichier de résultats attendus compare des comptes
// exacts, et un jeu qui bouge d'une exécution à l'autre le rendrait ininterprétable.
//
// Aucune dépendance npm, comme tests/apex_page_test.mjs -- le dépôt n'a pas de
// package.json et ce fichier doit rester copiable tel quel.

import { readFileSync, writeFileSync, mkdirSync, readdirSync, rmSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { makeRng } from './lib/rng.mjs';
import { collectId } from './lib/csv.mjs';
import { CONTRACT } from './lib/contract.mjs';
import { buildEstate } from './lib/estate.mjs';
import { emitOracle } from './lib/emit_oracle.mjs';
import { emitMssql } from './lib/emit_mssql.mjs';
import { emitPostgres } from './lib/emit_postgres.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const outDir = resolve(process.argv[2] || join(HERE, 'out'));

const world = JSON.parse(readFileSync(join(HERE, 'world.json'), 'utf8'));

// Un flux aléatoire par étage, dérivé de la même graine, plutôt qu'un flux
// unique partagé. Avec un flux unique, ajouter une ligne dans l'émetteur Oracle
// décalait tous les tirages MSSQL en aval : le jeu restait reproductible, mais
// le moindre changement réécrivait la totalité des fichiers et le diff du
// fichier de résultats attendus devenait illisible. Ici, une modification reste
// contenue dans son moteur.
const rng = makeRng(world.seed);
const rngOracle = makeRng(world.seed + 101);
const rngMssql = makeRng(world.seed + 202);
const rngPostgres = makeRng(world.seed + 303);

// Les dates sont lues en UTC : sans le 'T00:00:00Z', Node les interpréterait
// dans le fuseau de la machine et le jeu produit ne serait plus le même selon
// l'endroit d'où on le génère.
const collectDate = new Date(`${world.collectDate}T00:00:00Z`);
const snapshot = new Date(`${world.snapshotDate}T00:00:00Z`);
const cid = collectId(collectDate);

const estate = buildEstate(world, rng);
const base = { outDir, world, estate, cid, snapshot };

// On repart d'un dossier propre : un CSV laissé par une génération précédente,
// pour une table qu'on n'écrit plus, serait chargé sans que rien ne le signale.
if (existsSync(outDir)) rmSync(outDir, { recursive: true });
mkdirSync(outDir, { recursive: true });

emitOracle({ ...base, rng: rngOracle });
emitMssql({ ...base, rng: rngMssql });
emitPostgres({ ...base, rng: rngPostgres });

// ---------------------------------------------------------------- périmètre
// Format attendu par les collecteurs, et régénéré par gen_collect_lists.sh
// depuis les tables *_collect_list :
//   oracle   : ENVIRONMENT;LICENCE_TYPE;host:port/service
//   mssql    : ENVIRONMENT;LICENCE_TYPE;host:port
//   postgres : ENVIRONMENT;LICENCE_TYPE;host:port
// Une entrée inactive s'écrit COMMENTÉE, pas absente : la ligne porte une
// décision (« on connaît cette instance et on ne la collecte pas ») qu'une
// simple absence perdrait.
function writeLst (name, header, lines) {
   writeFileSync(join(outDir, name), [header, ...lines].join('\n') + '\n', 'utf8');
   return lines.length;
}

const oraLst = estate.oracle.databases.map(db =>
   `${db.environment};${db.license};${db.host.hostname}.${world.org.domain}:${db.port}/${db.dbName}`);
// Deux entrées volontairement désactivées, pour que la démo montre ce que
// signifie une ligne commentée dans le périmètre.
oraLst[oraLst.length - 1] = `#${oraLst[oraLst.length - 1]}`;

const msLst = estate.mssql.instances.map(i =>
   `${i.host.environment};${i.license};${i.host.fqdn}:${i.port}`);
msLst[msLst.length - 1] = `#${msLst[msLst.length - 1]}`;

const pgLst = estate.postgres.hosts.map(h =>
   `${h.environment};${h.license};${h.hostname}:${h.port}`);

writeLst('oracle_database_lists.lst', '#ENVIRONMENT;LICENCE_TYPE;EZCONNECT', oraLst);
writeLst('mssql_database_lists.lst', '#ENVIRONMENT;LICENCE_TYPE;SQLSERVER_NAME:PORT', msLst);
writeLst('postgres_database_lists.lst', '#ENVIRONMENT;LICENCE_TYPE;HOST:PORT', pgLst);

// ---------------------------------------------------------------- contrôle
// Chaque table du contrat doit avoir SON fichier, même vide : les loaders font
// un LOAD inconditionnel sous WHENEVER SQLERROR EXIT FAILURE, donc une absence
// ne dégrade pas le chargement, elle l'interrompt.
const expected = Object.keys(CONTRACT);
const written = readdirSync(outDir).filter(f => f.endsWith('.csv')).map(f => f.replace(/\.csv$/, ''));
const missing = expected.filter(t => !written.includes(t));
const extra = written.filter(t => !expected.includes(t));
if (missing.length) {
   console.error(`ERREUR: ${missing.length} fichier(s) attendu(s) non produit(s) : ${missing.join(', ')}`);
   process.exit(1);
}
if (extra.length) {
   console.error(`ERREUR: fichier(s) hors contrat : ${extra.join(', ')}`);
   process.exit(1);
}

// ---------------------------------------------------------------- résumé
const counts = {};
let total = 0;
for (const t of expected) {
   const n = readFileSync(join(outDir, `${t}.csv`), 'utf8').split('\n').filter(l => l !== '').length;
   counts[t] = n;
   total += n;
}
const by = (p) => expected.filter(t => CONTRACT[t].engine === p).reduce((s, t) => s + counts[t], 0);

console.log(`Parc      : ${world.org.name} (${world.org.domain}), graine ${world.seed}`);
console.log(`Collecte  : ${cid}   snapshot ${world.snapshotDate}`);
console.log(`Oracle    : ${estate.oracle.hosts.length} hôtes, ${estate.oracle.databases.length} bases, `
          + `${estate.oracle.databases.reduce((n, d) => n + d.dbEntities.length, 0)} entités de grain DATABASE`);
console.log(`MSSQL     : ${estate.mssql.hosts.length} hôtes, ${estate.mssql.instances.length} instances, `
          + `${estate.mssql.instances.reduce((n, i) => n + i.databases.length, 0)} bases`);
console.log(`PostgreSQL: ${estate.postgres.hosts.length} hôtes, `
          + `${estate.postgres.hosts.reduce((n, h) => n + h.databases.length, 0)} bases`);
console.log(`Lignes    : oracle ${by('oracle')}, mssql ${by('mssql')}, postgres ${by('postgres')} — total ${total}`);
console.log(`Sortie    : ${outDir}  (${expected.length} CSV + 3 .lst)`);
