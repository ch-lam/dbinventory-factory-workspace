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

function cell (value, field, table, rowNo) {
   if (value === null || value === undefined || value === '') return '';

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
   return `"${s}"`;
}

// rows : tableau d'objets, dont les clés sont les noms de colonnes du contrat.
export function writeCsv (outDir, table, rows) {
   const spec = CONTRACT[table];
   if (!spec) throw new Error(`table hors contrat : ${table}`);

   const lines = [];
   rows.forEach((row, i) => {
      for (const k of Object.keys(row)) {
         if (!spec.fields.some(f => f.name === k)) {
            throw new Error(`${table} ligne ${i + 1} : champ « ${k} » absent du contrat`
                          + ` (colonnes omises du CSV : ${spec.omitted.join(', ') || 'aucune'})`);
         }
      }
      lines.push(spec.fields.map(f => cell(row[f.name], f, table, i + 1)).join(','));
   });

   const path = join(outDir, `${table}.csv`);
   mkdirSync(dirname(path), { recursive: true });
   // Un fichier vide reste un fichier : les loaders font un LOAD inconditionnel
   // et WHENEVER SQLERROR EXIT FAILURE ferait échouer toute la session sur une
   // absence. Quatre des CSV d'une collecte réelle sont d'ailleurs vides.
   writeFileSync(path, lines.length ? lines.join('\n') + '\n' : '', 'utf8');
   return lines.length;
}
