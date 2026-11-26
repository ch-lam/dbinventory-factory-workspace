// Émission des 26 CSV Oracle.
//
// Différence structurelle avec MSSQL, et elle commande tout ce fichier : les
// collectes Oracle n'émettent QUE LES DÉVIATIONS. oracle_sec_high_sys_privs est
// vide sur une base saine. pkg_dbinv_scoring en tire les verdicts conformes par
// anti-jointure contre deux TÉMOINS de collecte réussie :
//
//   * par instance : oracle_security_parameter  (une ligne par paramètre, émise
//     inconditionnellement pour toute base non-standby) ;
//   * par base     : oracle_security_profile    (les profils existent toujours).
//
// Une base absente de son témoin ne produit AUCUN constat -- volontairement :
// une collecte ratée ne doit pas être notée conforme. Le générateur doit donc
// produire les témoins pour toutes les entités, sans quoi le jeu de données
// serait silencieusement vide de constats Oracle.
//
// Deuxième piège : pdb_name n'a pas la même valeur selon la table. Les tables
// de sécurité portent 'NON CONTAINER' pour une base non-CDB (l'ETL le retraduit
// en db_name), tandis que oracle_size_usage et les métriques portent le nom que
// dim_database utilisera réellement. D'où les deux champs de dbEntities :
// pdbName pour la sécurité, dimName pour le reste.

import { writeCsv, fmtDate } from './csv.mjs';
import { markShare } from './estate.mjs';

const HOURS = 3600 * 1000;

// Paramètres d'initialisation évalués : [nom, valeur conforme, valeur en écart]
const PARAMS = [
   ['o7_dictionary_accessibility', 'ORACLE_PRM_O7_DICT_ACCESS', 'FALSE', 'TRUE'],
   ['remote_os_authent', 'ORACLE_PRM_REMOTE_OS_AUTHENT', 'FALSE', 'TRUE'],
   ['remote_os_roles', 'ORACLE_PRM_REMOTE_OS_ROLES', 'FALSE', 'TRUE'],
   ['os_roles', 'ORACLE_PRM_OS_ROLES', 'FALSE', 'TRUE'],
   ['utl_file_dir', 'ORACLE_PRM_UTL_FILE_DIR', '', '/tmp/oracle_files'],
   ['audit_trail', 'ORACLE_PRM_AUDIT_TRAIL', 'DB', 'NONE'],
   ['audit_sys_operations', 'ORACLE_PRM_AUDIT_SYS_OPERATIONS', 'TRUE', 'FALSE'],
   ['unified auditing', 'ORACLE_PRM_UNIFIED_AUDITING', 'TRUE', 'FALSE'],
   ['resource_limit', 'ORACLE_PRM_RESOURCE_LIMIT', 'TRUE', 'FALSE'],
   ['sec_case_sensitive_logon', 'ORACLE_PRM_SEC_CASE_SENSITIVE', 'TRUE', 'FALSE'],
   ['sec_max_failed_login_attempts', 'ORACLE_PRM_SEC_MAX_FAILED_LOGIN', '3', '10'],
   ['sec_return_server_release_banner', 'ORACLE_PRM_SEC_BANNER', 'FALSE', 'TRUE'],
   ['sec_protocol_error_trace_action', 'ORACLE_PRM_SEC_PROTO_ERR_TRACE', 'TRACE', 'NONE'],
   ['sec_protocol_error_further_action', 'ORACLE_PRM_SEC_PROTO_ERR_FURTHER', 'DELAY,3', 'CONTINUE'],
   ['_sys_logon_delay', 'ORACLE_PRM_SYS_LOGON_DELAY', '4', '0']
];

// Limites de profil : [ressource, règle, valeur conforme, valeur en écart]
const PROFILE_LIMITS = [
   ['FAILED_LOGIN_ATTEMPTS', 'ORACLE_PRF_FAILED_LOGIN_ATTEMPTS', '5', 'UNLIMITED'],
   ['PASSWORD_LIFE_TIME', 'ORACLE_PRF_PASSWORD_LIFE_TIME', '90', 'UNLIMITED'],
   ['PASSWORD_LOCK_TIME', 'ORACLE_PRF_PASSWORD_LOCK_TIME', '1', '0'],
   ['PASSWORD_GRACE_TIME', 'ORACLE_PRF_PASSWORD_GRACE_TIME', '5', '30'],
   ['PASSWORD_REUSE_MAX', 'ORACLE_PRF_PASSWORD_REUSE_MAX', 'UNLIMITED', '3'],
   ['PASSWORD_REUSE_TIME', 'ORACLE_PRF_PASSWORD_REUSE_TIME', '365', '10'],
   ['PASSWORD_VERIFY_FUNCTION', 'ORACLE_PRF_PASSWORD_VERIFY_FUNCTION', 'ORA12C_VERIFY_FUNCTION', 'NULL'],
   ['SESSIONS_PER_USER', 'ORACLE_PRF_SESSIONS_PER_USER', '10', 'UNLIMITED'],
   ['INACTIVE_ACCOUNT_TIME', 'ORACLE_PRF_INACTIVE_ACCOUNT_TIME', '120', 'UNLIMITED']
];

const PROFILES = ['DEFAULT', 'APP_PROFILE'];

// Comptes livrés et maintenus par Oracle : hors périmètre des règles de
// privilèges et de profil. C'est le périmètre de la norme, pas une dérogation.
const ORACLE_MANAGED = ['SYS', 'SYSTEM', 'DBSNMP', 'OUTLN', 'ORACLE_OCM', 'XDB', 'AUDSYS'];
const APP_USERS = ['APP_OWNER', 'APP_READER', 'BATCH_USER', 'ETL_USER', 'REPORT_USER'];

const SYS_PRIVS = ['SELECT ANY TABLE', 'ALTER SYSTEM', 'CREATE ANY PROCEDURE', 'GRANT ANY ROLE'];
const HIGH_ROLES = ['DBA', 'GSMADMIN_ROLE', 'EXP_FULL_DATABASE'];
const SENSITIVE_PKGS = ['UTL_FILE', 'UTL_HTTP', 'UTL_SMTP', 'DBMS_LOB'];

// ----------------------------------------------------------------- LMS
// Sortie du script d'Oracle sur l'usage des options et packs (oracle_lms.sql),
// sous sa forme réelle :
//   * non-CDB : une ligne par produit, grouping_id 0, con_id -1, sans conteneur ;
//   * CDB     : une ligne par produit ET par conteneur (CDB$ROOT, puis chaque
//               PDB), plus l'agrégat grouping_id 1 '--ALL--'.
// Les valeurs d'usage sont celles que le script produit vraiment.
//
// Ce que le jeu doit exercer (T_003 exige les deux verdicts de chaque règle) :
//   * des instances CPU avec une option en usage, d'autres avec un usage passé
//     de Diagnostics/Tuning, d'autres sans rien ;
//   * les bases SAP avec Advanced Compression et Partitioning en usage, hors
//     contrôle par leur licence ;
//   * Multitenant signalé sur CHAQUE CDB, comme le fait le script : l'ETL le
//     recompte, et une CDB 19c+ à 3 PDB au plus doit en ressortir conforme ;
//   * la base Standard Edition 2 avec Partitioning, qu'aucune licence ne couvre.
const LMS_OPTIONS = ['Partitioning', 'Advanced Compression', 'Diagnostics Pack', 'Tuning Pack',
                     'Real Application Testing', '.Database Gateway'];
const LMS_USAGE = { 4: 'CURRENT_USAGE', 2: 'PAST_USAGE', 1: 'NO_USAGE' };

function lmsRows ({ cid, estate, world, rngLms: rng }) {
   const dbs = estate.oracle.databases;
   const D = world.defects;
   const pool = dbs.filter(db => db.license !== 'SAP');
   const inUse = new Set(markShare(rng, pool, D.ORACLE_LMS_OPTION_IN_USE).filter(x => x.bad).map(x => x.item));
   const past = new Set(markShare(rng, pool, D.ORACLE_LMS_OPTION_PAST_USE).filter(x => x.bad).map(x => x.item));

   const rows = [];
   for (const db of dbs) {
      // Rang d'usage par produit pour la base : 4 actuel, 2 passé, 1 aucun.
      const rank = new Map(LMS_OPTIONS.map(p => [p, 1]));
      if (db.license === 'SAP') {
         rank.set('Advanced Compression', 4);
         rank.set('Partitioning', 4);
      }
      if (past.has(db)) {
         for (const p of rng.sample(['Diagnostics Pack', 'Tuning Pack'], rng.int(1, 2))) rank.set(p, 2);
      }
      if (inUse.has(db)) rank.set(rng.pick(LMS_OPTIONS), 4);
      if (db.edition === 'Standard Edition 2') rank.set('Partitioning', 4);
      const products = db.isCdb ? [...LMS_OPTIONS, 'Multitenant'] : LMS_OPTIONS;
      if (db.isCdb) rank.set('Multitenant', 4);

      const row = (grouping, conId, container, p, r) => ({
         collect_id: cid, grouping_id: grouping, con_id: conId, db_pdb_name: container,
         product_name: p, usage_detected: LMS_USAGE[r], last_sample_date: '20260830',
         first_usage_date: r > 1 ? '20250312' : null,
         last_usage_date: r === 4 ? '20260830' : r === 2 ? '20251015' : null,
         db_name: db.dbName, hostname: db.host.hostname
      });

      if (!db.isCdb) {
         for (const p of products) rows.push(row(0, -1, null, p, rank.get(p)));
         continue;
      }
      // CDB : Multitenant vit dans CDB$ROOT, les options dans la première PDB.
      for (const p of products) {
         rows.push(row(0, 1, 'CDB$ROOT', p, p === 'Multitenant' ? rank.get(p) : 1));
         db.pdbs.forEach((pdb, k) =>
            rows.push(row(0, 3 + k, pdb, p, p !== 'Multitenant' && k === 0 ? rank.get(p) : 1)));
         rows.push(row(1, null, '--ALL--', p, rank.get(p)));
      }
   }
   return rows;
}

export function emitOracle (ctx) {
   const { outDir, world, rng, estate, cid, snapshot } = ctx;
   const hosts = estate.oracle.hosts;
   const dbs = estate.oracle.databases;
   const D = world.defects;

   // Toutes les entités de grain DATABASE, à plat : c'est la population de
   // toutes les règles par base.
   const entities = dbs.flatMap(db => db.dbEntities.map(e => ({ db, ...e })));

   const flag = (list, rule) => {
      const m = new Map();
      for (const { item, bad } of markShare(rng, list, D[rule])) m.set(item, bad);
      return m;
   };

   // ------------------------------------------------------------- hosts
   writeCsv(outDir, 'oracle_hosts', hosts.map(h => ({
      collect_id: cid, environment: h.environment, license_type: h.license,
      hostname: h.hostname, num_cpus: h.numCpus, memory_gb: h.memoryGb, os_type: h.osType
   })));

   // ------------------------------------------------------------- databases
   writeCsv(outDir, 'oracle_databases', dbs.map(db => ({
      collect_id: cid, environment: db.environment, license_type: db.license,
      hostname: db.host.hostname, instance_name: db.sid, db_version: db.version,
      db_name: db.dbName, db_log_mode: 'ARCHIVELOG', db_role: 'PRIMARY',
      db_unique_name: db.dbName, db_charset: db.charset, db_edition: db.edition,
      rac_state: 'FALSE', sga: rng.int(4, 32), pga: rng.int(1, 8),
      asm_free: null, asm_total: null,
      easy_connect_tns: `${db.host.hostname}.${world.org.domain}:${db.port}/${db.dbName}`,
      database_type: db.isCdb ? 'CONTAINER' : 'NON_CONTAINER'
   })));

   // ------------------------------------------------------------- pdbs
   writeCsv(outDir, 'oracle_pdbs', dbs.filter(d => d.isCdb).flatMap(db =>
      db.pdbs.map(p => ({
         collect_id: cid, hostname: db.host.hostname, instance_name: db.sid,
         pdb_name: p, pdb_state: 'READ WRITE'
      }))));

   // ------------------------------------------------------------- users
   // Ordre des champs = ordre de la TABLE. Le script de collecte, lui, émet
   // db_name en 2e position : c'est le décalage corrigé dans cette branche.
   writeCsv(outDir, 'oracle_users', entities.flatMap(e =>
      [...ORACLE_MANAGED, ...APP_USERS].map(u => ({
         collect_id: cid, hostname: e.db.host.hostname, instance_name: e.db.sid,
         pdb_name: e.dimName, username: u,
         account_status: ORACLE_MANAGED.includes(u) && u !== 'SYS' && u !== 'SYSTEM'
            ? 'EXPIRED & LOCKED' : 'OPEN',
         db_name: e.db.dbName
      }))));

   // ------------------------------------------------------------- services
   writeCsv(outDir, 'oracle_services', entities.map(e => ({
      collect_id: cid, hostname: e.db.host.hostname, instance_name: e.db.sid,
      pdb_name: e.dimName, service_name: e.dimName.toLowerCase()
   })));

   // ------------------------------------------------------------- psu / lms / clients
   writeCsv(outDir, 'oracle_psu', dbs.map(db => ({
      collect_id: cid, db_name: db.dbName, db_version: db.version,
      psu_applied: db.version.split('.').slice(0, 2).join('.') + '.0.0.0'
   })));

   // Les tirages de l'ancienne émission LMS sont consommés à l'identique : les
   // retirer décalerait tout ce qui suit dans le flux Oracle (sauvegardes,
   // capacité, sécurité) et réécrirait la référence pour rien. L'usage des
   // options est désormais tiré dans son propre flux, rngLms.
   for (let n = 0; n < dbs.length * 3; n++) rng.chance(0.25);
   writeCsv(outDir, 'oracle_lms', lmsRows(ctx));

   writeCsv(outDir, 'oracle_client_version', dbs.filter(() => rng.chance(0.6)).map(db => ({
      collect_id: cid, db_name: db.dbName, db_version: db.version,
      environment: db.environment, pdb_name: db.dbEntities[0].dimName,
      client_version: rng.pick(['19.3.0.0.0', '19.13.0.0.0', '12.2.0.1.0']),
      client_driver: 'jdbcthin', username: 'APP_OWNER',
      client_host: `app-${db.environment.toLowerCase()}-01`,
      service_name: db.dbName.toLowerCase(), failover_type: 'NONE', failover_method: 'NONE'
   })));

   // ------------------------------------------------------------- dataguard
   // Écrit dans l'ordre de la TABLE : le script de collecte place aujourd'hui
   // protection_mode en 4e position, ce qui est le second décalage corrigé ici.
   // Un échantillon de taille fixe plutôt qu'un tirage par base : à 25 bases et
   // 25 % de chances, une exécution sur deux ne produisait aucune ligne, et un
   // fichier vide n'aurait rien montré de Data Guard en démonstration.
   const dgCandidates = dbs.filter(db => db.environment === 'PRD');
   writeCsv(outDir, 'oracle_dataguard', rng.sample(dgCandidates, Math.min(3, dgCandidates.length))
      .map(db => ({
         collect_id: cid, primary_db: db.dbName, standby_db: `${db.dbName}_STB`,
         pdb_list_impacted: db.isCdb ? db.pdbs.join(' ') : 'NA',
         service_list_impacted: db.dbName.toLowerCase(),
         protection_mode: 'MaxPerformance'
      })));

   // ------------------------------------------------------------- backup (RMAN)
   const bkBad = flag(dbs, 'ORACLE_BACKUP_FRESHNESS_SLA');
   const backups = [];
   for (const db of dbs) {
      const lateHours = bkBad.get(db) ? rng.int(60, 300) : rng.int(2, 20);
      const start = new Date(snapshot.getTime() - lateHours * HOURS);
      backups.push({
         collect_id: cid, db_name: db.dbName, environment: db.environment,
         backup_type: 'DB INCR', status: 'COMPLETED',
         start_time: fmtDate(start), end_time: fmtDate(new Date(start.getTime() + 40 * 60 * 1000)),
         elapsed_time: 40
      });
      backups.push({
         collect_id: cid, db_name: db.dbName, environment: db.environment,
         backup_type: 'ARCHIVELOG', status: 'COMPLETED',
         start_time: fmtDate(new Date(snapshot.getTime() - 2 * HOURS)),
         end_time: fmtDate(new Date(snapshot.getTime() - 2 * HOURS + 5 * 60 * 1000)),
         elapsed_time: 5
      });
   }
   writeCsv(outDir, 'oracle_backup', backups);

   // ------------------------------------------------------------- capacité
   // size_mb dans oracle_size_usage, somme des segments dans
   // oracle_size_usage_seg : deux fichiers, une seule vérité. Les deux doivent
   // rester cohérents, la saturation étant le rapport de l'un sur l'autre.
   const tsList = [];
   for (const e of entities) {
      const names = ['SYSTEM', 'SYSAUX', 'UNDOTBS1', 'TEMP',
                     ...Array.from({ length: rng.int(1, 5) }, (_, k) => `DATA${k + 1}`)];
      for (const name of names) tsList.push({ e, name });
   }
   const tsCapBad = flag(tsList.filter(t => t.name.startsWith('DATA')), 'ORACLE_STORAGE_PCT_USED');
   const sizeRows = [], segRows = [];
   for (const t of tsList) {
      const sizeMb = rng.int(1024, 262144);
      const pct = tsCapBad.get(t) ? rng.int(91, 99) : rng.int(5, 75);
      sizeRows.push({
         collect_id: cid, db_name: t.e.db.dbName, pdb_name: t.e.dimName,
         tablespace_name: t.name, size_mb: sizeMb
      });
      segRows.push({
         collect_id: cid, db_name: t.e.db.dbName, pdb_name: t.e.dimName,
         tablespace_name: t.name, sum_segment_mb: Math.round(sizeMb * pct / 100)
      });
   }
   writeCsv(outDir, 'oracle_size_usage', sizeRows);
   writeCsv(outDir, 'oracle_size_usage_seg', segRows);

   // ------------------------------------------------------------- métriques
   // Plus de métriques CPU/mémoire : la collecte les tirait d'AWR (Diagnostics
   // Pack), non licenciable en Standard Edition 2. Leurs tirages sont consommés
   // à l'identique, comme ceux de l'ancienne émission LMS plus haut : les
   // retirer décalerait toute la sécurité qui suit dans le flux Oracle.
   for (let n = 0; n < entities.length * 6; n++) rng.next();

   // ============================================================== SÉCURITÉ
   // ------------------------------------------------------------- paramètres
   // TÉMOIN par instance : toutes les bases, tous les paramètres.
   const paramBad = new Map();
   for (const [, rule] of PARAMS.map(p => [p[0], p[1]])) paramBad.set(rule, flag(dbs, rule));
   const params = [];
   for (const db of dbs) {
      for (const [name, rule, ok, ko] of PARAMS) {
         params.push({
            collect_id: cid, db_name: db.dbName,
            parameter_value: paramBad.get(rule).get(db) ? ko : ok,
            parameter_name: name
         });
      }
      // Catalogué à active = 0 : collecté, jamais jugé. On l'émet quand même,
      // parce que la collecte réelle l'émet et que le témoin doit ressembler
      // à ce que produit la production.
      params.push({ collect_id: cid, db_name: db.dbName, parameter_value: '', parameter_name: 'pdb_os_credential' });
   }
   writeCsv(outDir, 'oracle_security_parameter', params);

   // ------------------------------------------------------------- profils
   // TÉMOIN par base.
   const limitPop = [];
   for (const e of entities) for (const p of PROFILES) limitPop.push({ e, profile: p });
   const limitBad = new Map();
   for (const [, rule] of PROFILE_LIMITS.map(p => [p[0], p[1]])) limitBad.set(rule, flag(limitPop, rule));
   const profiles = [];
   for (const lp of limitPop) {
      for (const [res, rule, ok, ko] of PROFILE_LIMITS) {
         profiles.push({
            collect_id: cid, db_name: lp.e.db.dbName, pdb_name: lp.e.pdbName,
            profile: lp.profile, resource_name: res,
            limit_value: limitBad.get(rule).get(lp) ? ko : ok
         });
      }
   }
   writeCsv(outDir, 'oracle_security_profile', profiles);

   // ------------------------------------------------------------- profil DEFAULT
   const defProfPop = entities.flatMap(e => APP_USERS.map(u => ({ e, user: u })));
   const defProfBad = flag(defProfPop, 'ORACLE_NO_DEFAULT_PROFILE');
   const defProf = [];
   for (const e of entities) {
      // Les comptes gérés par Oracle sont conformes par périmètre, quel que
      // soit leur profil : ils portent oracle_managed = 'Y'.
      for (const u of ORACLE_MANAGED) {
         defProf.push({ collect_id: cid, db_name: e.db.dbName, pdb_name: e.pdbName,
                        username: u, profile: 'DEFAULT', oracle_managed: 'Y' });
      }
   }
   for (const p of defProfPop) {
      defProf.push({ collect_id: cid, db_name: p.e.db.dbName, pdb_name: p.e.pdbName,
                     username: p.user,
                     profile: defProfBad.get(p) ? 'DEFAULT' : 'APP_PROFILE',
                     oracle_managed: 'N' });
   }
   writeCsv(outDir, 'oracle_sec_default_profile', defProf);

   // ------------------------------------------------------------- mots de passe par défaut
   // DÉVIATIONS SEULES, par instance : une ligne = un compte fautif.
   const pwdBad = flag(dbs, 'ORACLE_NO_DEFAULT_PASSWORD');
   writeCsv(outDir, 'oracle_sec_default_user_pwd', dbs.filter(db => pwdBad.get(db)).map(db => ({
      collect_id: cid, db_name: db.dbName, pdb_name: 'CONTAINER', username: 'DBSNMP'
   })));

   // ------------------------------------------------------------- privilèges
   // DÉVIATIONS SEULES, par base. Les comptes gérés par Oracle sont exclus par
   // l'ETL via oracle_sec_default_profile.oracle_managed = 'Y' : inutile de les
   // filtrer ici, mais les émettre ne créerait aucun constat.
   const sysPrivBad = flag(entities, 'ORACLE_HIGH_SYS_PRIVS_GRANT');
   writeCsv(outDir, 'oracle_sec_high_sys_privs', entities.filter(e => sysPrivBad.get(e))
      .flatMap(e => rng.sample(SYS_PRIVS, rng.int(1, 3)).map(p => ({
         collect_id: cid, db_name: e.db.dbName, pdb_name: e.pdbName,
         username: rng.pick(APP_USERS), privilege: p
      }))));

   const rolePrivBad = flag(entities, 'ORACLE_HIGH_ROLE_PRIVS_GRANT');
   writeCsv(outDir, 'oracle_sec_high_role_privs', entities.filter(e => rolePrivBad.get(e))
      .flatMap(e => rng.sample(HIGH_ROLES, rng.int(1, 2)).map(r => ({
         collect_id: cid, db_name: e.db.dbName, pdb_name: e.pdbName,
         username: rng.pick(APP_USERS), privilege: r
      }))));

   const tabPrivBad = flag(entities, 'ORACLE_HIGH_TAB_PRIVS_PUBLIC');
   writeCsv(outDir, 'oracle_sec_high_tab_privs', entities.filter(e => tabPrivBad.get(e))
      .flatMap(e => rng.sample(SENSITIVE_PKGS, rng.int(1, 3)).map(p => ({
         collect_id: cid, db_name: e.db.dbName, pdb_name: e.pdbName,
         username: 'PUBLIC', privilege: p
      }))));

   // ------------------------------------------------------------- audit
   const auditBad = flag(entities, 'ORACLE_AUDIT_CIS_POLICY_ON');
   writeCsv(outDir, 'oracle_security_audit_enable', entities.map(e => ({
      collect_id: cid, db_name: e.db.dbName, pdb_name: e.pdbName,
      audit_parameter: 'ORA_CIS_RECOMMENDATIONS',
      audit_activated: auditBad.get(e) ? 0 : 1
   })));

   // ------------------------------------------------------------- tablespaces
   // Le périmètre de la norme exempte SYSTEM, SYSAUX, TEMP% et UNDO% : les
   // écarts ne peuvent porter que sur les tablespaces applicatifs.
   const tsEncPop = tsList.filter(t => t.name.startsWith('DATA'));
   const tsEncBad = flag(tsEncPop, 'ORACLE_TABLESPACE_ENCRYPTED');
   writeCsv(outDir, 'oracle_security_tablespace', tsList.map(t => ({
      collect_id: cid, db_name: t.e.db.dbName, pdb_name: t.e.pdbName,
      tablespace_name: t.name,
      encrypted: t.name.startsWith('DATA') ? (tsEncBad.get(t) ? 'NO' : 'YES') : 'NO'
   })));

   // ------------------------------------------------------------- fichier de mots de passe
   // Conforme si et seulement si le seul membre est SYS.
   const pwfBad = flag(dbs, 'ORACLE_ADMIN_PWFILE_SYS_ONLY');
   const pwf = [];
   for (const db of dbs) {
      pwf.push({ collect_id: cid, db_name: db.dbName, username: 'SYS' });
      if (pwfBad.get(db)) {
         pwf.push({ collect_id: cid, db_name: db.dbName, username: rng.pick(['ADMINISTRATOR', 'OPS$ORACLE', 'DBA_USER']) });
      }
   }
   writeCsv(outDir, 'oracle_sec_admin_high_privs', pwf);

   // ------------------------------------------------------------- chiffrement réseau
   // Absence INVERSÉE : la collecte n'émet une ligne que lorsqu'un adaptateur de
   // chiffrement est actif, donc une instance sans ligne est NON conforme.
   const netBad = flag(dbs, 'ORACLE_NETWORK_ENCRYPTION_ON');
   writeCsv(outDir, 'oracle_sec_network_encryption', dbs.filter(db => !netBad.get(db)).map(db => ({
      collect_id: cid, db_name: db.dbName, sqlnet_encryption: 'AES256'
   })));

   // ------------------------------------------------------------- clients non chiffrés
   // La table de suivi n'existe que sur une base laissée en REQUESTED : le
   // collecteur y est donc chiffré, d'où le tirage parmi les bases conformes
   // ci-dessus. Quatre bases, quatre cas, pour exercer les deux polarités des
   // deux règles ET la fenêtre de 30 jours :
   //   0. des clients récents                       -> écarts clients
   //   1. un client récent et un client ancien      -> l'ancien ne compte pas
   //   2. des clients anciens seulement             -> conforme côté clients
   //   3. table vide                                -> conforme côté clients
   // Les quatre sont en écart sur le mode (REQUESTED). Tirage dans son propre
   // flux (rngNetAudit) : venu après coup, il ne décale aucun autre fichier.
   const na = ctx.rngNetAudit;
   const DAY = 24 * HOURS;
   const netAuditDbs = na.sample(dbs.filter(db => !netBad.get(db)), 4);
   const NA_USERS = ['APP_DPI', 'APP_LABO', 'BATCH_FACT', 'REPORTING'];
   const NA_PROGRAMS = ['JDBC Thin Client', 'w3wp.exe', 'sqlplus@srv-batch-01', 'Toad.exe'];
   const NA_OSUSERS = ['svc_app', 'svc_batch', 'jdupont'];
   const netAudit = [];
   const client = (db, pdb, ageMin, ageMax) => {
      const last = new Date(snapshot.getTime() - na.int(ageMin, ageMax) * DAY - na.int(1, 20) * HOURS);
      return {
         collect_id: cid, db_name: db.dbName, pdb_name: pdb, record_type: 'CLIENT',
         username: na.pick(NA_USERS),
         machine: `ws-${na.int(100, 999)}.${world.org.domain}`,
         program: na.pick(NA_PROGRAMS),
         osuser: na.pick(NA_OSUSERS),
         first_seen: fmtDate(new Date(last.getTime() - na.int(30, 200) * DAY)),
         last_seen: fmtDate(last),
         logon_count: String(na.int(1, 5000))
      };
   };
   netAuditDbs.forEach((db, i) => {
      const pdb = db.dbEntities[0].pdbName;
      netAudit.push({ collect_id: cid, db_name: db.dbName, pdb_name: pdb, record_type: 'AUDIT' });
      if (i === 0) for (let k = 0; k < 3; k++) netAudit.push(client(db, pdb, 0, 25));
      if (i === 1) { netAudit.push(client(db, pdb, 0, 25)); netAudit.push(client(db, pdb, 40, 80)); }
      if (i === 2) for (let k = 0; k < 2; k++) netAudit.push(client(db, pdb, 40, 80));
   });
   writeCsv(outDir, 'oracle_sec_net_enc_audit', netAudit);

   // ------------------------------------------------------------- SYS.USER$MIG
   // DÉVIATIONS SEULES : la présence de la table est l'écart.
   const migBad = flag(entities, 'ORACLE_NO_USERMIG_TABLE');
   writeCsv(outDir, 'oracle_sec_usermig_tbl_exist', entities.filter(e => migBad.get(e)).map(e => ({
      collect_id: cid, db_name: e.db.dbName, pdb_name: e.pdbName,
      owner: 'SYS', table_name: 'USER$MIG'
   })));
}
