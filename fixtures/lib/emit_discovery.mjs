// Écriture des deux fichiers de discovery, et du script de décisions de triage.
//
// Les deux fichiers passent par writeCsv comme les 56 autres, sous le contrôle
// du contrat, alors qu'ils n'ont ni le même séparateur ni les mêmes guillemets.
// Les écrire à côté du contrat aurait été plus court — et aurait retiré au
// chargement du fichier Linux, qui est positionnel, la seule protection qu'il a.

import { writeFileSync } from 'node:fs';
import { join } from 'node:path';
import { writeCsv } from './csv.mjs';

// Les décisions de triage ne sont pas des données de collecte : ce sont des
// décisions humaines, qui s'appliquent APRÈS le chargement et par l'API réelle.
// La résolution se fait par clé naturelle et par `select into` : si la discovery
// n'a pas produit l'entité, no_data_found arrête la chaîne, plutôt que de livrer
// un jeu amputé de ses cas IGNORED dont check_baseline signalerait l'écart trois
// étapes plus loin, sans en dire la cause.
function triageSql (triage) {
   const q = (s) => `'${String(s).replace(/'/g, "''")}'`;
   const out = [
      '-- Décisions de triage du jeu de démonstration.',
      '-- Généré par fixtures/lib/emit_discovery.mjs — ne pas éditer à la main.',
      'whenever sqlerror exit failure rollback',
      'set define off',
      'set serveroutput on',
      'declare',
      '   l_id number;',
      'begin'
   ];

   for (const t of triage) {
      if (t.level === 'INSTANCE') {
         out.push(
            '   select di.disc_instance_id into l_id',
            '     from disc_instance di',
            '     join disc_host dh on dh.disc_host_id = di.disc_host_id',
            `    where dh.platform = ${q(t.platform)}`,
            `      and lower(dh.hostname) = lower(${q(t.hostname)})`,
            `      and di.instance_name = ${q(t.instance)};`);
      } else {
         out.push(
            '   select dh.disc_host_id into l_id',
            '     from disc_host dh',
            `    where dh.platform = ${q(t.platform)}`,
            `      and lower(dh.hostname) = lower(${q(t.hostname)});`);
      }
      out.push(
         `   pkg_dbinv_discovery.set_triage(${q(t.level)}, l_id, 'IGNORED', ${q(t.note)});`,
         '');
   }

   out.push(
      '   commit;',
      `   dbms_output.put_line('Triage : ${triage.length} decision(s) appliquee(s).');`,
      'exception',
      '   when no_data_found then',
      '      raise_application_error(-20100,',
      "         'Une entite de triage du jeu de demonstration est absente de la discovery : '",
      "         || 'le chargement a-t-il bien eu lieu ?');",
      'end;',
      '/',
      'exit');
   return out.join('\n') + '\n';
}

export function emitDiscovery ({ outDir, discovery }) {
   const nMssql = writeCsv(outDir, 'discovery_mssql_inst', discovery.mssqlRows);
   const nLinux = writeCsv(outDir, 'discovery_linux_engines', discovery.linuxRows);

   writeFileSync(join(outDir, 'discovery_triage.sql'), triageSql(discovery.triage), 'utf8');

   return { mssql: nMssql, linux: nLinux, triage: discovery.triage.length };
}
