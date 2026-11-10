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
// Aucune dépendance npm, comme le test navigateur de l'appli (apex/.../tests/apex_page_test.mjs) -- le dépôt n'a pas de
// package.json et ce fichier doit rester copiable tel quel.

import { readFileSync, writeFileSync, mkdirSync, readdirSync, rmSync, existsSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { makeRng } from './lib/rng.mjs';
import { collectId, fileNameOf } from './lib/csv.mjs';
import { CONTRACT } from './lib/contract.mjs';
import { buildEstate } from './lib/estate.mjs';
import { emitOracle } from './lib/emit_oracle.mjs';
import { emitMssql } from './lib/emit_mssql.mjs';
import { emitPostgres } from './lib/emit_postgres.mjs';
import { buildDiscovery } from './lib/discovery.mjs';
import { emitDiscovery } from './lib/emit_discovery.mjs';
import { emitApplications } from './lib/emit_applications.mjs';

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
// La discovery a son propre flux, pour la meme raison : ajouter un hote
// sauvage ne doit pas decaler un seul tirage des trois emetteurs de
// collecte, sinon la reference se reecrit en entier pour rien.
const rngDiscovery = makeRng(world.seed + 404);
// L'usage des options Oracle (LMS) a le sien : il est venu après coup, et le
// tirer dans le flux Oracle aurait réécrit toute la sécurité Oracle en aval.
const rngLms = makeRng(world.seed + 505);

// Les dates sont lues en UTC : sans le 'T00:00:00Z', Node les interpréterait
// dans le fuseau de la machine et le jeu produit ne serait plus le même selon
// l'endroit d'où on le génère.
const collectDate = new Date(`${world.collectDate}T00:00:00Z`);
const snapshot = new Date(`${world.snapshotDate}T00:00:00Z`);
const cid = collectId(collectDate);

const estate = buildEstate(world, rng);
// Apres buildEstate, et sans jamais toucher au flux partage : la discovery
// LIT le parc, elle ne participe pas a sa construction.
const discovery = buildDiscovery(world, estate, rngDiscovery);
const base = { outDir, world, estate, cid, snapshot };

// On repart d'un dossier propre : un CSV laissé par une génération précédente,
// pour une table qu'on n'écrit plus, serait chargé sans que rien ne le signale.
if (existsSync(outDir)) rmSync(outDir, { recursive: true });
mkdirSync(outDir, { recursive: true });

emitOracle({ ...base, rng: rngOracle, rngLms });
emitMssql({ ...base, rng: rngMssql });
emitPostgres({ ...base, rng: rngPostgres });
const discoveryCounts = emitDiscovery({ outDir, discovery });
// Le registre applicatif n'est pas une collecte : il ne produit aucun CSV et
// n'entre pas dans le contrat. Il sort un script, joué après l'ETL.
const appCounts = emitApplications({ outDir, world, estate });

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
// La comparaison porte sur les NOMS DE FICHIER : deux tables de discovery ne
// portent pas le nom de leur fichier, parce que c'est le loader de production
// qui decide de celui-ci.
const expected = Object.keys(CONTRACT);
const expectedFiles = expected.map(fileNameOf);
const written = readdirSync(outDir).filter(f => f.endsWith('.csv'));
const missing = expectedFiles.filter(f => !written.includes(f));
const extra = written.filter(f => !expectedFiles.includes(f));
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
   const lines = readFileSync(join(outDir, fileNameOf(t)), 'utf8').split('\n').filter(l => l !== '');
   // L'en-tete n'est pas une ligne de donnees : le compter fausserait le total
   // et, plus tard, la mesure de staging de la reference.
   const n = lines.length - (CONTRACT[t].format?.header ? 1 : 0);
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
console.log(`Découverte: ${discoveryCounts.mssql} instance(s) MSSQL, ${discoveryCounts.linux} hôte(s) Linux, `
          + `${discoveryCounts.triage} décision(s) de triage`);
console.log(`Registre  : ${appCounts.applications} application(s), ${appCounts.links} rattachement(s), `
          + `${appCounts.groups} groupe(s), ${appCounts.contacts} contact(s), `
          + `${appCounts.documents} document(s), ${appCounts.sources} dépôt(s)`);
console.log(`Lignes    : oracle ${by('oracle')}, mssql ${by('mssql')}, postgres ${by('postgres')}, `
          + `discovery ${by('discovery')} — total ${total}`);
console.log(`Sortie    : ${outDir}  (${expected.length} CSV + 3 .lst + 2 .sql)`);
