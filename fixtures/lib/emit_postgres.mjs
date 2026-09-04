// Émission des 10 CSV PostgreSQL.
//
// Ces fichiers étaient au départ un simple exercice de chargement : PostgreSQL
// n'avait aucun contrôle au catalogue, et le staging n'alimentait rien. Ce n'est
// plus vrai -- 9 contrôles et 20 règles jugent maintenant PostgreSQL sur les
// quatre domaines de score -- et l'émetteur a changé de métier : il ne suffit
// plus qu'il produise des lignes chargeables, il faut qu'il produise des ÉCARTS.
//
// Un contrôle qui ne peut pas rougir ne prouve rien. C'est le défaut qui a été
// trouvé sur la saturation Oracle : pct_used valait 0 sur 100 % des lignes et le
// contrôle était vert par construction. Chaque règle PostgreSQL a donc ici une
// part de population en écart, tirée de world.defects comme pour les deux autres
// moteurs, et non un rng.chance() posé au jugé.
//
// Trois pièges de forme, tous vérifiés contre les scripts de collecte :
//
//   * pas de collect_id -- les tables postgres_* n'en ont pas ; environnement et
//     licence sont injectés comme littéraux dans le SELECT du collecteur ;
//   * la collecte passe par COPY ... WITH (FORMAT csv, FORCE_QUOTE *), donc du
//     CSV RFC4180 réel, là où Oracle et MSSQL fabriquent leurs guillemets à la
//     main dans la requête ;
//   * get_info_postgres_security.sh IGNORE LES STANDBY. Les cinq CSV de sécurité
//     n'ont donc aucune ligne pour eux, et c'est reproduit ici : c'est ce qui
//     fait qu'une instance standby ne porte aucun constat SECURITY, et T_004
//     l'assert.

import { writeCsv } from './csv.mjs';
import { markShare } from './estate.mjs';

// Marqueurs d'absence propres à cette collecte : 'NA' pour un champ texte,
// 'NEVER' pour une validité de rôle, -1 pour un retard de réplication.
const NA = 'NA';

// Plafond du wraparound : 2^31. Une base saine tourne bien en dessous de
// autovacuum_freeze_max_age (200 M par défaut, soit ~9 % du plafond).
const XID_CEILING = 2147483648;

export function emitPostgres (ctx) {
   const { outDir, world, rng, estate } = ctx;
   const hosts = estate.postgres.hosts;
   const D = world.defects;

   // La sécurité n'est collectée que sur les primaires : c'est la population de
   // toutes les règles SECURITY, et le dénominateur de tous les markShare.
   const primaries = hosts.filter(h => h.role !== 'STANDBY');

   const flag = (list, rule) => {
      const m = new Map();
      for (const { item, bad } of markShare(rng, list, D[rule])) m.set(item, bad);
      return m;
   };

   // ------------------------------------------------------------- hosts
   const archiveOff = flag(hosts, 'PG_ARCHIVE_MODE_ON');
   const staleWal = flag(hosts, 'PG_BACKUP_FRESHNESS_SLA');

   writeCsv(outDir, 'postgres_hosts', hosts.map(h => ({
      hostname: h.hostname, environment: h.environment, license_type: h.license,
      pg_version: h.version, port: h.port,
      data_directory: '/var/lib/postgresql/data',
      start_time: '2026-08-14 06:12:31',
      max_connections: 100, shared_buffers_mb: rng.pick([1024, 2048, 4096]),
      wal_level: 'replica',
      archive_mode: archiveOff.get(h) ? 'off' : 'on',
      db_role: h.role
   })));

   // ------------------------------------------------------------- databases
   // xid_age : le tirage porte sur la base, pas sur l'hôte -- le wraparound est
   // un plafond par base. Les bases en écart passent au-dessus du seuil critique
   // (80 %), les autres restent dans la zone où tourne un autovacuum qui fait son
   // travail.
   const allDbs = hosts.flatMap(h => h.databases.map(d => ({ host: h, name: d })));
   const xidHot = flag(allDbs, 'PG_XID_WRAPAROUND');

   writeCsv(outDir, 'postgres_databases', allDbs.map(entry => ({
      hostname: entry.host.hostname, environment: entry.host.environment, datname: entry.name,
      owner: `${entry.name}_owner`, encoding: 'UTF8', collation: 'en_US.utf8',
      size_mb: rng.int(20, 40000), datconnlimit: -1,
      // 'NO', pas 'N' : le collecteur écrit CASE WHEN datistemplate THEN 'YES'
      // ELSE 'NO' END, et une fixture qui s'en écarte ne teste plus rien.
      is_template: 'NO',
      tablespace: 'pg_default',
      xid_age: xidHot.get(entry)
         ? rng.int(Math.round(XID_CEILING * 0.82), Math.round(XID_CEILING * 0.94))
         : rng.int(Math.round(XID_CEILING * 0.02), Math.round(XID_CEILING * 0.19))
   })));

   // ------------------------------------------------------------- replication
   // Une ligne par lien : vue du primaire (pg_stat_replication) et vue du
   // standby (pg_stat_wal_receiver), exactement les deux requêtes du collecteur.
   const standbys = hosts.filter(h => h.role === 'STANDBY');
   const replication = [];
   standbys.forEach((sb, i) => {
      const primary = sb.replicatesFrom || primaries[i % primaries.length];
      replication.push({
         hostname: primary.hostname, db_role: 'PRIMARY',
         peer_addr: `10.20.30.${40 + i}`, state: 'streaming', sync_state: 'async',
         lag_seconds: rng.int(0, 12)
      });
      replication.push({
         hostname: sb.hostname, db_role: 'STANDBY',
         peer_addr: primary.hostname, state: 'streaming', sync_state: NA,
         lag_seconds: rng.int(0, 12)
      });
   });
   writeCsv(outDir, 'postgres_replication', replication);

   // ------------------------------------------------------------- backup
   // archive_mode off => pg_stat_archiver n'a jamais rien archivé : les champs
   // texte valent 'NA' et le compteur 0, ce que le collecteur écrit via COALESCE.
   // Une instance en écart de fraîcheur archive, mais son dernier segment date.
   writeCsv(outDir, 'postgres_backup', hosts.map(h => {
      const on = !archiveOff.get(h);
      return {
         hostname: h.hostname, archive_mode: on ? 'on' : 'off',
         archived_count: on ? rng.int(100, 90000) : 0,
         last_archived_wal: on ? '000000010000002A000000B4' : NA,
         last_archived_time: on
            ? (staleWal.get(h) ? '2026-08-29 22:41:07' : '2026-09-02 04:11:07')
            : NA,
         failed_count: 0, last_failed_wal: NA, last_failed_time: NA
      };
   }));

   // ------------------------------------------------------------- extensions
   writeCsv(outDir, 'postgres_extensions', hosts.flatMap(h =>
      h.databases.flatMap(d => ['plpgsql', 'pg_stat_statements'].map(x => ({
         hostname: h.hostname, datname: d, extname: x,
         extversion: x === 'plpgsql' ? '1.0' : '1.10'
      })))));

   // ------------------------------------------------------------- parameters
   // Les NEUF paramètres de la liste blanche du collecteur, pas trois. Deux
   // d'entre eux (log_hostname, log_min_duration_statement) ne sont jugés par
   // aucune règle : ils sont émis quand même, parce que c'est ce que la collecte
   // remonte et que leur passage sans rule_code dans le CASE de
   // load_findings_postgres_sec fait partie de ce qu'on veut exercer.
   const noSsl = flag(primaries, 'PG_PRM_SSL_ON');
   const md5Pwd = flag(primaries, 'PG_PRM_PASSWORD_ENCRYPTION');
   const noLogConn = flag(primaries, 'PG_PRM_LOG_CONNECTIONS');
   const noLogDisc = flag(primaries, 'PG_PRM_LOG_DISCONNECTIONS');
   const noLogStmt = flag(primaries, 'PG_PRM_LOG_STATEMENT');
   const oldTls = flag(primaries, 'PG_PRM_SSL_MIN_PROTOCOL');
   const noAudit = flag(primaries, 'PG_PRM_PGAUDIT_LOADED');

   writeCsv(outDir, 'postgres_security_parameter', primaries.flatMap(h => [
      { parameter_name: 'ssl', parameter_value: noSsl.get(h) ? 'off' : 'on' },
      { parameter_name: 'password_encryption', parameter_value: md5Pwd.get(h) ? 'md5' : 'scram-sha-256' },
      { parameter_name: 'log_connections', parameter_value: noLogConn.get(h) ? 'off' : 'on' },
      { parameter_name: 'log_disconnections', parameter_value: noLogDisc.get(h) ? 'off' : 'on' },
      { parameter_name: 'log_statement', parameter_value: noLogStmt.get(h) ? 'none' : 'ddl' },
      { parameter_name: 'ssl_min_protocol_version', parameter_value: oldTls.get(h) ? 'TLSv1' : 'TLSv1.2' },
      { parameter_name: 'shared_preload_libraries', parameter_value: noAudit.get(h) ? 'pg_stat_statements' : 'pg_stat_statements,pgaudit' },
      { parameter_name: 'log_hostname', parameter_value: 'off' },
      { parameter_name: 'log_min_duration_statement', parameter_value: '1000' }
   ].map(p => ({ hostname: h.hostname, ...p }))));

   // ------------------------------------------------------------- roles
   // postgres et monitoring sont hors périmètre des règles par construction :
   // les écarts portent sur des rôles surnuméraires, ajoutés seulement sur les
   // hôtes tirés. Un rôle applicatif ordinaire par base complète la population.
   const extraSuper = flag(primaries, 'PG_ROLE_NO_EXTRA_SUPERUSER');
   const bypassRls = flag(primaries, 'PG_ROLE_NO_BYPASSRLS');
   const extraRepl = flag(primaries, 'PG_ROLE_REPLICATION_LIMITED');

   const role = (o) => ({
      rolsuper: 'N', rolcreaterole: 'N', rolcreatedb: 'N', rolcanlogin: 'Y',
      rolreplication: 'N', rolbypassrls: 'N', rolconnlimit: -1, rolvaliduntil: 'NEVER', ...o
   });

   writeCsv(outDir, 'postgres_security_roles', primaries.flatMap(h => {
      const rows = [
         role({ rolname: 'postgres', rolsuper: 'Y', rolcreaterole: 'Y', rolcreatedb: 'Y', rolreplication: 'Y', rolbypassrls: 'Y' }),
         role({ rolname: 'monitoring', rolconnlimit: 5 }),
         ...h.databases.map(d => role({ rolname: `${d}_owner` }))
      ];
      if (extraSuper.get(h)) rows.push(role({ rolname: 'dba_legacy', rolsuper: 'Y', rolcreaterole: 'Y', rolcreatedb: 'Y' }));
      if (bypassRls.get(h)) rows.push(role({ rolname: 'etl_loader', rolbypassrls: 'Y' }));
      if (extraRepl.get(h)) rows.push(role({ rolname: 'barman_stream', rolreplication: 'Y' }));
      return rows.map(r => ({ hostname: h.hostname, ...r }));
   }));

   // ------------------------------------------------------------- memberships
   // Collecte de déviations : une base saine ne produit rien. Les appartenances
   // à pg_monitor et pg_read_all_data sont émises parce que le collecteur les
   // remonte, mais aucune règle ne les juge -- elles vérifient qu'une ligne non
   // jugée ne fabrique pas de constat.
   const memProgram = flag(primaries, 'PG_MEMBER_NO_SERVER_PROGRAM');
   const memFiles = flag(primaries, 'PG_MEMBER_NO_SERVER_FILES');
   const memWrite = flag(primaries, 'PG_MEMBER_NO_WRITE_ALL_DATA');

   writeCsv(outDir, 'postgres_sec_role_members', primaries.flatMap(h => {
      const rows = [{ role_name: 'monitoring', member_of: 'pg_monitor' }];
      if (memProgram.get(h)) rows.push({ role_name: 'dba_legacy', member_of: 'pg_execute_server_program' });
      if (memFiles.get(h)) rows.push({ role_name: 'etl_loader', member_of: 'pg_read_server_files' });
      if (memWrite.get(h)) rows.push({ role_name: 'etl_loader', member_of: 'pg_write_all_data' });
      if (h.databases.length) rows.push({ role_name: `${h.databases[0]}_owner`, member_of: 'pg_read_all_data' });
      return rows.map(r => ({ hostname: h.hostname, ...r }));
   }));

   // ------------------------------------------------------------- pg_hba
   const hbaTrust = flag(primaries, 'PG_HBA_NO_TRUST');
   const hbaWeak = flag(primaries, 'PG_HBA_NO_WEAK_METHOD');

   writeCsv(outDir, 'postgres_security_hba_rules', primaries.flatMap(h => {
      const rows = [
         { line_number: 85, rule_type: 'local', database: 'all', user_name: 'all', address: NA, auth_method: 'peer' },
         { line_number: 100, rule_type: 'host', database: 'all', user_name: 'monitoring', address: '10.20.30.0/24', auth_method: 'scram-sha-256' },
         { line_number: 110, rule_type: 'host', database: 'all', user_name: 'all', address: '10.20.0.0/16', auth_method: 'scram-sha-256' }
      ];
      if (hbaWeak.get(h)) rows.push({ line_number: 118, rule_type: 'host', database: 'all', user_name: 'all', address: '10.21.0.0/16', auth_method: 'md5' });
      if (hbaTrust.get(h)) rows.push({ line_number: 125, rule_type: 'host', database: 'all', user_name: 'all', address: '127.0.0.1/32', auth_method: 'trust' });
      return rows.map(r => ({ hostname: h.hostname, ...r }));
   }));

   // ------------------------------------------------------------- PUBLIC privs
   // grantee vaut TOUJOURS 'PUBLIC' : le collecteur écrit ce littéral et filtre
   // sur a.grantee = 0, l'oid de PUBLIC. La version précédente de cette fixture
   // y mettait le nom du propriétaire de la base, ce qui ne pouvait correspondre
   // à aucune ligne réelle -- et aurait rendu PG_PUBLIC_NO_CREATE toujours vert.
   const pgDbs = primaries.flatMap(h => h.databases.map(d => ({ host: h, name: d })));
   const publicCreate = flag(pgDbs, 'PG_PUBLIC_NO_CREATE');

   writeCsv(outDir, 'postgres_sec_db_privs', pgDbs.flatMap((entry) => {
      const privs = ['CONNECT', 'TEMPORARY'];
      if (publicCreate.get(entry)) privs.push('CREATE');
      return privs.map(p => ({
         hostname: entry.host.hostname, datname: entry.name,
         grantee: 'PUBLIC', privilege_type: p
      }));
   }));
}
