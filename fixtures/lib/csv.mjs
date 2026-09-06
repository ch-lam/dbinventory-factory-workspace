// Écriture des CSV de collecte, sous le contrôle de CONTRACT.
//
// Le chargement SQLcl est POSITIONNEL et sans en-tête : un champ de trop ou de
// trop peu ne produit pas une erreur lisible, il décale silencieusement toutes
// les colonnes suivantes -- c'est exactement le défaut qui traîne depuis des
// mois dans oracle_users, où account_status contient des noms d'utilisateurs.
// Ce module refuse donc d'écrire une ligne qui ne correspond pas au contrat,
// plutôt que de produire un fichier qui se chargera « sans erreur ».
//
// Conventions reproduites depuis une collecte réelle archivée :
//   * toute valeur non vide est encadrée de guillemets, y compris les nombres ;
//   * une valeur vide s'écrit sans rien du tout (",,"), jamais ("""") -- le
//     finalize_lst des collecteurs supprime les guillemets vides par sed ;
//   * séparateur ",", fin de ligne LF, pas de BOM, pas d'en-tête ;
//   * les dates sont en 'YYYY-MM-DD HH24:MI:SS', format posé par ALTER SESSION
//     dans les loaders.
//
// Ces conventions sont celles des 56 CSV de collecte, et elles restent le
// DÉFAUT. Les deux fichiers de discovery n'ont pas le même producteur et donc
// pas le même format : Export-Csv de PowerShell écrit un en-tête et charge par
// nom, detect_db_engines.sh écrit une ligne ';' sans guillemets ni en-tête et
// charge positionnellement. Une table du contrat peut donc porter un objet
// `format`, dont chaque propriété absente reprend la convention ci-dessus.
// Écrire ces deux fichiers À CÔTÉ du contrat aurait été plus court, et aurait
// justement retiré au chargement positionnel la seule protection qu'il a.

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { CONTRACT } from './contract.mjs';

export function fmtDate (d) {
   const p = (n, w = 2) => String(n).padStart(w, '0');
   return `${d.getUTCFullYear()}-${p(d.getUTCMonth() + 1)}-${p(d.getUTCDate())} `
        + `${p(d.getUTCHours())}:${p(d.getUTCMinutes())}:${p(d.getUTCSeconds())}`;
}

export function fmtDay (d) {
   const p = (n) => String(n).padStart(2, '0');
   return `${d.getUTCFullYear()}-${p(d.getUTCMonth() + 1)}-${p(d.getUTCDate())}`;
}

// COLL_ID_YYYYMMDD : exactement 16 caractères, la largeur de la colonne.
export function collectId (d) {
   const p = (n) => String(n).padStart(2, '0');
   return `COLL_ID_${d.getUTCFullYear()}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}`;
}

export const DEFAULT_FORMAT = { delimiter: ',', quoted: true, header: false };

function formatOf (spec) {
   return { ...DEFAULT_FORMAT, ...(spec.format || {}) };
}

function cell (value, field, table, rowNo, fmt) {
   if (value === null || value === undefined || value === '') {
      // Sans guillemets, un champ vide est indiscernable d'un champ absent, et
      // le producteur réel n'en écrit jamais : detect_db_engines.sh écrit '-'.
      // Le refuser ici évite un décalage que le chargement ne signalerait pas.
      if (!fmt.quoted) {
         throw new Error(`${table} ligne ${rowNo}, champ ${field.name} : valeur vide interdite `
                       + `dans un fichier sans guillemets (le producteur écrit '-')`);
      }
      return '';
   }

   let s = value instanceof Date ? fmtDate(value) : String(value);

   // Un guillemet dans une valeur est impossible à écrire ici : les collecteurs
   // le suppriment à la source (REPLACE(x,'"','')) parce que le sed du
   // finalize_lst détruirait tout échappement RFC4180. On refuse plutôt que
   // d'inventer une convention que le chargement ne connaît pas.
   if (s.includes('"')) {
      throw new Error(`${table} ligne ${rowNo}, champ ${field.name} : guillemet interdit dans « ${s} »`);
   }
   if (/[\r\n]/.test(s)) {
      throw new Error(`${table} ligne ${rowNo}, champ ${field.name} : saut de ligne interdit`);
   }
   if (field.type === 'varchar2' && field.len && s.length > field.len) {
      throw new Error(`${table} ligne ${rowNo}, champ ${field.name} : ${s.length} caractères > ${field.len}`);
   }
   // Sans guillemets, le séparateur dans une valeur décale la ligne entière et
   // le chargement positionnel n'y verra rien. C'est la raison pour laquelle le
   // fichier Linux sépare en ';' : ora_sids y liste des SID séparés par ','.
   if (!fmt.quoted && s.includes(fmt.delimiter)) {
      throw new Error(`${table} ligne ${rowNo}, champ ${field.name} : séparateur `
                    + `« ${fmt.delimiter} » interdit dans « ${s} » (fichier sans guillemets)`);
   }
   return fmt.quoted ? `"${s}"` : s;
}

// rows : tableau d'objets, dont les clés sont les noms de colonnes du contrat.
// Le nom du fichier est un contrat de PRODUCTION, pas un choix du jeu de
// test : load_info_discovery.sh attend discovery_mssql.csv pour la table
// discovery_mssql_inst. Le contrat porte donc l'écart explicitement plutôt que
// de plier l'un des deux.
export function fileNameOf (table) {
   const spec = CONTRACT[table];
   if (!spec) throw new Error(`table hors contrat : ${table}`);
   return spec.fileName || `${table}.csv`;
}

export function writeCsv (outDir, table, rows) {
   const spec = CONTRACT[table];
   if (!spec) throw new Error(`table hors contrat : ${table}`);
   const fmt = formatOf(spec);

   const lines = [];
   if (fmt.header) {
      // Un en-tete porte des NOMS de colonnes, pas des valeurs : ni la
      // longueur declaree ni le type ne s'y appliquent (editiongratuite fait
      // 15 caracteres pour une colonne qui en accepte 10).
      lines.push(spec.fields
         .map(f => (fmt.quoted ? `"${f.name}"` : f.name))
         .join(fmt.delimiter));
   }
   rows.forEach((row, i) => {
      for (const k of Object.keys(row)) {
         if (!spec.fields.some(f => f.name === k)) {
            throw new Error(`${table} ligne ${i + 1} : champ « ${k} » absent du contrat`
                          + ` (colonnes omises du CSV : ${spec.omitted.join(', ') || 'aucune'})`);
         }
      }
      lines.push(spec.fields.map(f => cell(row[f.name], f, table, i + 1, fmt)).join(fmt.delimiter));
   });

   const path = join(outDir, fileNameOf(table));
   mkdirSync(dirname(path), { recursive: true });
   // Un fichier vide reste un fichier : les loaders font un LOAD inconditionnel
   // et WHENEVER SQLERROR EXIT FAILURE ferait échouer toute la session sur une
   // absence. Quatre des CSV d'une collecte réelle sont d'ailleurs vides.
   writeFileSync(path, lines.length ? lines.join('\n') + '\n' : '', 'utf8');
   // On rend le nombre de LIGNES DE DONNEES : l'en-tete eventuel n'en est pas
   // une, et un appelant qui compte des entites n'a pas a savoir qu'il existe.
   return rows.length;
}
