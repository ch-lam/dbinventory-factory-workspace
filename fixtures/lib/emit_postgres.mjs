// Émission des 10 CSV PostgreSQL.
//
// PostgreSQL n'a AUCUN contrôle ni règle au catalogue : les 32 contrôles et 70
// règles sont tous Oracle ou MSSQL. Ces fichiers ne produisent donc aucun
// constat et aucun score -- ils alimentent le staging, que la page 40 lit
// directement, sans passer par le modèle dimensionnel.
//
// Ce que ces fichiers valident quand même, et c'est la raison de les écrire :
// la pipeline PostgreSQL a été écrite sans jamais être exercée. Un chargement
// propre de bout en bout est le premier test qu'elle reçoit.
//
// Deux différences de forme avec les autres moteurs :
//   * pas de collect_id -- les tables postgres_* n'en ont pas ; environnement
//     et licence sont injectés comme littéraux dans le SELECT du collecteur ;
//   * la collecte passe par COPY ... WITH (FORMAT csv, FORCE_QUOTE *), donc du
//     CSV RFC4180 réel, là où Oracle et MSSQL fabriquent leurs guillemets à la
//     main dans la requête.

import { writeCsv } from './csv.mjs';

// Marqueurs d'absence propres à cette collecte : 'NA' pour un champ texte,
// 'NEVER' pour une validité de rôle, -1 pour un retard de réplication.
const NA = 'NA';

export function emitPostgres (ctx) {
   const { outDir, rng, estate } = ctx;
   const hosts = estate.postgres.hosts;

   writeCsv(outDir, 'postgres_hosts', hosts.map(h => ({
      hostname: h.hostname, environment: h.environment, license_type: h.license,
      pg_version: h.version, port: h.port,
      data_directory: '/var/lib/postgresql/data',
      start_time: '2026-08-14 06:12:31',
      max_connections: 100, shared_buffers_mb: rng.pick([1024, 2048, 4096]),
      wal_level: 'replica', archive_mode: rng.chance(0.5) ? 'on' : 'off',
      db_role: 'PRIMARY'
   })));

   writeCsv(outDir, 'postgres_databases', hosts.flatMap(h =>
      h.databases.map(d => ({
         hostname: h.hostname, environment: h.environment, datname: d,
         owner: `${d}_owner`, encoding: 'UTF8', collation: 'en_US.utf8',
         size_mb: rng.int(20, 40000), datconnlimit: -1, is_template: 'N',
         tablespace: 'pg_default'
      }))));

   writeCsv(outDir, 'postgres_replication', hosts.filter(() => rng.chance(0.4)).map(h => ({
      hostname: h.hostname, db_role: 'PRIMARY',
      peer_addr: '10.20.30.40', state: 'streaming', sync_state: 'async',
      lag_seconds: rng.int(0, 12)
   })));

   writeCsv(outDir, 'postgres_backup', hosts.map(h => {
      const on = rng.chance(0.6);
      return {
         hostname: h.hostname, archive_mode: on ? 'on' : 'off',
         archived_count: on ? rng.int(100, 90000) : 0,
         last_archived_wal: on ? '000000010000002A000000B4' : NA,
         last_archived_time: on ? '2026-09-01 04:11:07' : NA,
         failed_count: 0, last_failed_wal: NA, last_failed_time: NA
      };
   }));

   writeCsv(outDir, 'postgres_extensions', hosts.flatMap(h =>
      h.databases.flatMap(d => ['plpgsql', 'pg_stat_statements'].map(x => ({
         hostname: h.hostname, datname: d, extname: x,
         extversion: x === 'plpgsql' ? '1.0' : '1.10'
      })))));

   writeCsv(outDir, 'postgres_security_parameter', hosts.flatMap(h => [
      { hostname: h.hostname, parameter_name: 'ssl', parameter_value: rng.chance(0.6) ? 'on' : 'off' },
      { hostname: h.hostname, parameter_name: 'log_connections', parameter_value: 'on' },
      { hostname: h.hostname, parameter_name: 'password_encryption', parameter_value: 'scram-sha-256' }
   ]));

   writeCsv(outDir, 'postgres_security_roles', hosts.flatMap(h => [
      { hostname: h.hostname, rolname: 'postgres', rolsuper: 'Y', rolcreaterole: 'Y',
        rolcreatedb: 'Y', rolcanlogin: 'Y', rolreplication: 'Y', rolbypassrls: 'Y',
        rolconnlimit: -1, rolvaliduntil: 'NEVER' },
      { hostname: h.hostname, rolname: 'monitoring', rolsuper: 'N', rolcreaterole: 'N',
        rolcreatedb: 'N', rolcanlogin: 'Y', rolreplication: 'N', rolbypassrls: 'N',
        rolconnlimit: 5, rolvaliduntil: 'NEVER' },
      ...h.databases.map(d => ({
         hostname: h.hostname, rolname: `${d}_owner`, rolsuper: 'N', rolcreaterole: 'N',
         rolcreatedb: 'N', rolcanlogin: 'Y', rolreplication: 'N', rolbypassrls: 'N',
         rolconnlimit: -1, rolvaliduntil: 'NEVER'
      }))
   ]));

   writeCsv(outDir, 'postgres_sec_role_members', hosts.flatMap(h =>
      h.databases.map(d => ({
         hostname: h.hostname, role_name: `${d}_owner`, member_of: 'pg_read_all_stats'
      }))));

   writeCsv(outDir, 'postgres_security_hba_rules', hosts.flatMap(h => [
      { hostname: h.hostname, line_number: 85, rule_type: 'local', database: 'all',
        user_name: 'all', address: NA, auth_method: 'peer' },
      { hostname: h.hostname, line_number: 100, rule_type: 'host', database: 'all',
        user_name: 'monitoring', address: '10.20.30.0/24', auth_method: 'scram-sha-256' },
      { hostname: h.hostname, line_number: 110, rule_type: 'host', database: 'all',
        user_name: 'all', address: '10.20.0.0/16', auth_method: rng.chance(0.25) ? 'trust' : 'scram-sha-256' }
   ]));

   writeCsv(outDir, 'postgres_sec_db_privs', hosts.flatMap(h =>
      h.databases.flatMap(d => ['CONNECT', 'TEMPORARY'].map(p => ({
         hostname: h.hostname, datname: d, grantee: `${d}_owner`, privilege_type: p
      })))));
}
