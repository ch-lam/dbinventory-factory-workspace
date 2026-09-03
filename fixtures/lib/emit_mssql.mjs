// Émission des 20 CSV MSSQL.
//
// Les collectes MSSQL émettent une ligne SENTINELLE par entité même quand tout
// va bien ('NoOrphanedUser', 'nogroup', 'no_permission'). C'est ce qui permet à
// pkg_dbinv_scoring d'en tirer un verdict conforme par simple merge, sans
// anti-jointure. Reproduire ces sentinelles n'est donc pas cosmétique : sans
// elles, une instance saine ne produirait aucun constat et serait notée sur
// zéro item, exactement comme une instance jamais collectée.

import { writeCsv, fmtDate } from './csv.mjs';
import { markShare } from './estate.mjs';

const HOURS = 3600 * 1000;
const DAYS = 24 * HOURS;

// Les options sp_configure évaluées, et la valeur attendue par la règle.
// 'default trace enabled' et 'clr strict security' attendent 1, les autres 0.
const CONFIG_OPTIONS = [
   ['Ad Hoc Distributed Queries', 'MSSQL_CFG_ADHOC_DIST_QUERIES', 0],
   ['clr enabled', 'MSSQL_CFG_CLR_ENABLED', 0],
   ['clr strict security', 'MSSQL_CFG_CLR_STRICT_SECURITY', 1],
   ['cross db ownership chaining', 'MSSQL_CFG_CROSS_DB_CHAINING', 0],
   ['Database Mail XPs', 'MSSQL_CFG_DATABASE_MAIL_XPS', 0],
   ['default trace enabled', 'MSSQL_CFG_DEFAULT_TRACE', 1],
   ['Ole Automation Procedures', 'MSSQL_CFG_OLE_AUTOMATION', 0],
   ['remote access', 'MSSQL_CFG_REMOTE_ACCESS', 0],
   ['remote admin connections', 'MSSQL_CFG_REMOTE_ADMIN_CONN', 0],
   ['scan for startup procs', 'MSSQL_CFG_SCAN_STARTUP_PROCS', 0],
   ['xp_cmdshell', 'MSSQL_CFG_XP_CMDSHELL', 0]
];

const AUDIT_GROUPS = ['AUDIT_CHANGE_GROUP', 'FAILED_LOGIN_GROUP', 'SUCCESSFUL_LOGIN_GROUP'];

export function emitMssql (ctx) {
   const { outDir, world, rng, estate, cid, snapshot } = ctx;
   const instances = estate.mssql.instances;
   const allDbs = instances.flatMap(i => i.databases);
   const D = world.defects;

   // Un helper par règle : rend une Map entité -> booléen « en écart ».
   const flag = (list, rule) => {
      const m = new Map();
      for (const { item, bad } of markShare(rng, list, D[rule])) m.set(item, bad);
      return m;
   };

   // ------------------------------------------------------------- hosts
   const authBad = flag(instances, 'MSSQL_AUTH_WINDOWS_ONLY');
   writeCsv(outDir, 'mssql_hosts', instances.map(i => ({
      collect_id: cid,
      collect_target: i.host.fqdn,
      collect_port: i.port,
      environment: i.host.environment,
      license_type: i.license,
      hostname: i.serverName,
      mssql_edition: i.edition,
      mssql_product_version: i.build,
      collation: i.collation,
      is_clustered: 0,
      // activenodename porte ComputerNamePhysicalNetBIOS, que SERVERPROPERTY
      // renvoie sur TOUTE machine et pas seulement sur un nœud de cluster. La
      // colonne est d'ailleurs NOT NULL : émis vide, il partait en ORA-01400 et
      // les 65 lignes d'hôtes étaient rejetées.
      // clusternode1 et clusternode2, eux, sont bien toujours vides — le
      // collecteur émet deux champs constants (CHAR(34)+CHAR(34)).
      activenodename: i.host.short.toUpperCase(),
      clusternode1: null, clusternode2: null,
      parallel_threshold: 5, max_dop: 0,
      min_memory: 0, max_memory: i.host.memoryGb * 1024 - 2048,
      xp_cmdshell_enabled: 0,
      num_cpus: i.host.numCpus,
      memory_gb: i.host.memoryGb,
      os_type: i.host.osType,
      // install_date est le seul champ MSSQL en YYYYMMDD (CONVERT ..., 112)
      install_date: '20210315',
      service_account: `${world.org.adDomain}/svc_sql`,
      // 1 = authentification Windows seule = conforme
      is_integrated_security_only: authBad.get(i) ? 0 : 1
   })));

   // ------------------------------------------------------------- databases
   const backupBad = flag(allDbs.filter(d => !d.isSystem), 'MSSQL_BACKUP_FRESHNESS_SLA');
   const dbRow = (d) => {
      // tempdb n'est jamais sauvegardée : pas de date, donc pas de constat de
      // fraîcheur -- c'est le comportement réel, et load_fact_backup l'écarte
      // par son « hours_since_backup is not null ».
      if (d.name === 'tempdb') return { full: null, diff: null, log: null };
      const lateHours = backupBad.get(d) ? rng.int(60, 400) : rng.int(1, 20);
      const full = new Date(snapshot.getTime() - lateHours * HOURS);
      return {
         full,
         diff: new Date(full.getTime() + 6 * HOURS),
         log: new Date(snapshot.getTime() - rng.int(1, 4) * HOURS)
      };
   };
   const dbDates = new Map(allDbs.map(d => [d, dbRow(d)]));

   writeCsv(outDir, 'mssql_databases', allDbs.map(d => {
      const b = dbDates.get(d);
      return {
         collect_id: cid,
         collect_target: d.instance.host.fqdn,
         collect_port: d.instance.port,
         environment: d.instance.host.environment,
         license_type: d.instance.license,
         hostname: d.instance.serverName,
         database_id: d.databaseId,
         database_name: d.name,
         database_state: 'ONLINE',
         recovery_model: d.isSystem ? 'SIMPLE' : 'FULL',
         compatibility_level: parseInt(d.instance.build, 10) * 10,
         collation: d.instance.collation,
         last_backup_date: b.full ? fmtDate(b.full) : null,
         last_backup_diff_date: b.diff ? fmtDate(b.diff) : null,
         last_backup_log_date: b.log ? fmtDate(b.log) : null,
         create_date: '2021-03-15 09:12:00',
         is_mirroring_enabled: 0,
         owner: 'sa',
         agtype: null, agname: null
      };
   }));

   // ------------------------------------------------------------- files
   // pct_used = 100 * size_mb / max_size, et SEULEMENT quand max_size > 0.
   // Un fichier en croissance illimitée porte max_size = -1 et ne produit
   // aucun constat de capacité : c'est le cas le plus fréquent en vrai.
   const capBad = flag(allDbs, 'MSSQL_STORAGE_PCT_USED');
   const files = [];
   for (const d of allDbs) {
      const capped = capBad.get(d) || rng.chance(0.35);
      const maxSize = capped ? rng.int(4096, 65536) : -1;
      const size = capped
         ? Math.round(maxSize * (capBad.get(d) ? rng.int(91, 99) : rng.int(10, 70)) / 100)
         : rng.int(64, 8192);
      files.push({
         collect_id: cid, collect_target: d.instance.host.fqdn, hostname: d.instance.serverName,
         database_name: d.name, file_id: 1, type_desc: 'ROWS', name: `${d.name}_data`,
         physical_name: `D:/MSSQL/DATA/${d.name}.mdf`,
         size_mb: size, growth_percent: 0, growth_mb: 64, max_size: maxSize
      });
      files.push({
         collect_id: cid, collect_target: d.instance.host.fqdn, hostname: d.instance.serverName,
         database_name: d.name, file_id: 2, type_desc: 'LOG', name: `${d.name}_log`,
         physical_name: `L:/MSSQL/LOG/${d.name}.ldf`,
         size_mb: Math.max(16, Math.round(size / 8)), growth_percent: 10, growth_mb: 0, max_size: -1
      });
   }
   writeCsv(outDir, 'mssql_files', files);

   // ------------------------------------------------------------- backup history
   const backups = [];
   for (const d of allDbs) {
      const b = dbDates.get(d);
      if (!b.full) continue;
      backups.push({
         collect_id: cid, collect_target: d.instance.host.fqdn, hostname: d.instance.serverName,
         database_name: d.name,
         backup_start_date: fmtDate(new Date(b.full.getTime() - 20 * 60 * 1000)),
         backup_finish_date: fmtDate(b.full),
         backup_type: 'Full',
         backup_size: rng.int(50, 40000) * 1024 * 1024
      });
   }
   writeCsv(outDir, 'mssql_backup', backups);

   // ------------------------------------------------------------- configoptions
   const cfgBad = new Map();
   for (const [name, rule] of CONFIG_OPTIONS) cfgBad.set(name, flag(instances, rule));
   const cfg = [];
   for (const i of instances) {
      for (const [name, , expected] of CONFIG_OPTIONS) {
         const bad = cfgBad.get(name).get(i);
         const value = bad ? (expected === 1 ? 0 : 1) : expected;
         cfg.push({
            collect_id: cid, collect_target: i.host.fqdn, servername: i.serverName,
            name, config_value: value, run_value: value
         });
      }
   }
   writeCsv(outDir, 'mssql_security_configoptions', cfg);

   // ------------------------------------------------------------- registryinfo
   const hideBad = flag(instances, 'MSSQL_REG_HIDE_INSTANCE');
   const forceBad = flag(instances, 'MSSQL_REG_FORCE_ENCRYPTION');
   const logBad = flag(instances, 'MSSQL_REG_NUM_ERRORLOG_FILES');
   const portBad = flag(instances, 'MSSQL_REG_TCP_PORT');
   const reg = [];
   for (const i of instances) {
      const put = (name, value) => reg.push({
         collect_id: cid, collect_target: i.host.fqdn, servername: i.serverName, name, value
      });
      put('Hide Instance', hideBad.get(i) ? 0 : 1);
      put('ForceEncryption', forceBad.get(i) ? 0 : 1);
      put('NumErrorlogFiles', logBad.get(i) ? rng.int(4, 12) : rng.int(13, 30));
      // La règle maison attend 1433 -- l'inverse du benchmark CIS, seule règle
      // classée HOUSE_CONFLICT du catalogue.
      put('TCP Port', portBad.get(i) ? rng.pick([49172, 55000, 51433]) : 1433);
   }
   writeCsv(outDir, 'mssql_security_registryinfo', reg);

   // ------------------------------------------------------------- dbproperties
   const autoCloseBad = flag(allDbs, 'MSSQL_DBPROP_AUTO_CLOSE_OFF');
   const trustBad = flag(allDbs.filter(d => d.name !== 'msdb'), 'MSSQL_DBPROP_TRUSTWORTHY_OFF');
   writeCsv(outDir, 'mssql_security_dbproperties', allDbs.map(d => ({
      collect_id: cid, collect_target: d.instance.host.fqdn, servername: d.instance.serverName,
      db_name: d.name,
      is_auto_close_on: autoCloseBad.get(d) ? 1 : 0,
      // msdb a besoin de TRUSTWORTHY pour Database Mail et l'Agent : la règle
      // l'exempte elle-même, donc la valeur réelle y est 1 sans être un écart.
      is_trustworthy_on: d.name === 'msdb' ? 1 : (trustBad.get(d) ? 1 : 0)
   })));

   // ------------------------------------------------------------- auditlevel
   const auditBad = flag(instances, 'MSSQL_AUDIT_LEVEL_LOGIN_FAILURES');
   writeCsv(outDir, 'mssql_security_auditlevel', instances.map(i => ({
      collect_id: cid, collect_target: i.host.fqdn, servername: i.serverName,
      auditlevel: auditBad.get(i) ? rng.pick(['None', 'Successful']) : rng.pick(['All', 'Failed'])
   })));

   // ------------------------------------------------------------- encryption
   // Le périmètre de la norme exempte les bases système et les éditions
   // Express/Developer, qui n'embarquent pas TDE. On n'émet donc les écarts
   // que sur les bases utilisateur d'instances qui pourraient chiffrer.
   const encCandidates = allDbs.filter(d => !d.isSystem && !d.instance.isFreeEdition);
   const encBad = flag(encCandidates, 'MSSQL_ENC_STRONG_ALGORITHM');
   writeCsv(outDir, 'mssql_security_encryption', allDbs.map(d => ({
      collect_id: cid, collect_target: d.instance.host.fqdn, servername: d.instance.serverName,
      db_name: d.name, key_type: 'DATABASE ENCRYPTION KEY', key_name: `DEK_${d.name}`,
      algorithm_desc: encBad.get(d) ? rng.pick(['RC4', 'DES', 'RC2']) : 'AES_256'
   })));

   // ------------------------------------------------------------- groups
   const grpBad = flag(instances, 'MSSQL_GROUP_NO_LOCAL_PERMISSION');
   writeCsv(outDir, 'mssql_security_groups', instances.map(i => (
      grpBad.get(i)
         ? { collect_id: cid, collect_target: i.host.fqdn, servername: i.serverName,
             localgroupname: `${i.host.short.toUpperCase()}/SQLAdmins`,
             permission_name: 'CONTROL SERVER', state_desc: 'GRANT' }
         // sentinelle : aucun groupe local ne porte de permission
         : { collect_id: cid, collect_target: i.host.fqdn, servername: i.serverName,
             localgroupname: 'nogroup', permission_name: 'nogroup', state_desc: 'nogroup' }
   )));

   // ------------------------------------------------------------- guestconnect
   const guestBad = flag(allDbs.filter(d => !d.isSystem), 'MSSQL_GUEST_NO_CONNECT');
   writeCsv(outDir, 'mssql_security_guestconnect', allDbs.map(d => (
      guestBad.get(d)
         ? { collect_id: cid, collect_target: d.instance.host.fqdn, servername: d.instance.serverName,
             db_name: d.name, permission_name: 'CONNECT', state_desc: 'GRANT' }
         : { collect_id: cid, collect_target: d.instance.host.fqdn, servername: d.instance.serverName,
             db_name: d.name, permission_name: 'no_permission', state_desc: 'no_permission' }
   )));

   // ------------------------------------------------------------- logins
   // Deux règles partitionnent la population sur is_sysadmin : un sysadmin est
   // jugé sur l'expiration du mot de passe, un login ordinaire sur la politique.
   // 'sa' et 'monitoring' sont conformes par construction dans les deux cas.
   const sysadmins = [], regulars = [];
   for (const i of instances) {
      sysadmins.push({ inst: i, name: `adm_${i.host.short.replace(/-/g, '')}` });
      regulars.push({ inst: i, name: `app_${i.host.short.replace(/-/g, '')}` });
   }
   const expBad = flag(sysadmins, 'MSSQL_LOGIN_SYSADMIN_EXPIRATION');
   const polBad = flag(regulars, 'MSSQL_LOGIN_POLICY_CHECKED');
   const secLogins = [];
   for (const i of instances) {
      const base = { collect_id: cid, collect_target: i.host.fqdn, servername: i.serverName,
                     access_method: 'SQL_LOGIN', is_disabled: 0, create_date: '2021-03-15 09:12:00' };
      secLogins.push({ ...base, login_name: 'sa', principal_id: 1, is_sysadmin: 1,
                       is_policy_checked: 0, is_expiration_checked: 0 });
      secLogins.push({ ...base, login_name: 'monitoring', principal_id: 2, is_sysadmin: 0,
                       is_policy_checked: 0, is_expiration_checked: 0 });
   }
   for (const s of sysadmins) {
      secLogins.push({ collect_id: cid, collect_target: s.inst.host.fqdn, servername: s.inst.serverName,
                       login_name: s.name, principal_id: 10, is_sysadmin: 1,
                       is_policy_checked: 1, access_method: 'SQL_LOGIN',
                       is_expiration_checked: expBad.get(s) ? 0 : 1, is_disabled: 0,
                       create_date: '2021-03-15 09:12:00' });
   }
   for (const r of regulars) {
      secLogins.push({ collect_id: cid, collect_target: r.inst.host.fqdn, servername: r.inst.serverName,
                       login_name: r.name, principal_id: 11, is_sysadmin: 0,
                       is_policy_checked: polBad.get(r) ? 0 : 1, access_method: 'SQL_LOGIN',
                       is_expiration_checked: 1, is_disabled: 0,
                       create_date: '2021-03-15 09:12:00' });
   }
   writeCsv(outDir, 'mssql_security_logins', secLogins);

   // ------------------------------------------------------------- sa
   // La collecte est clé sur le sid 0x01, pas sur le nom : la règle continue
   // donc de fonctionner une fois le compte renommé comme elle le demande.
   const saNameBad = flag(instances, 'MSSQL_SA_RENAMED');
   const saDisBad = flag(instances, 'MSSQL_SA_DISABLED');
   writeCsv(outDir, 'mssql_security_sa', instances.map(i => ({
      collect_id: cid, collect_target: i.host.fqdn, servername: i.serverName,
      login_name: saNameBad.get(i) ? 'sa' : `adm_${i.host.short.replace(/-/g, '')}_root`,
      is_disabled: saDisBad.get(i) ? 0 : 1
   })));

   // ------------------------------------------------------------- orphanedusers
   const orphBad = flag(allDbs.filter(d => !d.isSystem), 'MSSQL_NO_ORPHANED_USER');
   writeCsv(outDir, 'mssql_security_orphanedusers', allDbs.map(d => ({
      collect_id: cid, collect_target: d.instance.host.fqdn, servername: d.instance.serverName,
      db_name: d.name,
      user_name: orphBad.get(d) ? `orph_${d.name.toLowerCase()}` : 'NoOrphanedUser'
   })));

   // ------------------------------------------------------------- public permission
   const pubBad = flag(allDbs.filter(d => !d.isSystem), 'MSSQL_PUBLIC_DEFAULT_PERMISSION');
   writeCsv(outDir, 'mssql_sec_pubperm', allDbs.map(d => (
      pubBad.get(d)
         ? { collect_id: cid, collect_target: d.instance.host.fqdn, servername: d.instance.serverName,
             db_name: d.name, username: 'public', permission_name: 'SELECT', state_desc: 'GRANT' }
         : { collect_id: cid, collect_target: d.instance.host.fqdn, servername: d.instance.serverName,
             db_name: d.name, username: 'public',
             permission_name: 'OnlyDefaultPermission', state_desc: 'OnlyDefaultPermission' }
   )));

   // ------------------------------------------------------------- server audit
   const audBad = flag(instances, 'MSSQL_SRVAUDIT_ACTION_GROUP_ON');
   const srvAudit = [];
   for (const i of instances) {
      const bad = audBad.get(i);
      for (const g of AUDIT_GROUPS) {
         srvAudit.push({
            collect_id: cid, collect_target: i.host.fqdn, servername: i.serverName,
            auditname: 'Audit-Serveur', auditenabled: bad ? 0 : 1,
            writelocation: 'FILE', auditspecificationname: 'Spec-Serveur',
            auditspecificationenabled: bad ? 0 : 1,
            auditactionname: g, audited_result: 'SUCCESS AND FAILURE'
         });
      }
   }
   writeCsv(outDir, 'mssql_security_sqlserveraudit', srvAudit);

   // ------------------------------------------------------------- inventaire pur
   // Ces trois tables ne portent aucune règle : elles alimentent dim_account et
   // les écrans d'inventaire.
   const users = [];
   for (const d of allDbs) {
      if (d.isSystem) continue;
      for (const u of ['app_user', 'reader', 'dbo']) {
         users.push({
            collect_id: cid, collect_target: d.instance.host.fqdn, instance_name: d.instance.serverName,
            database_name: d.name, name: u, groupname: u === 'dbo' ? 'db_owner' : 'db_datareader',
            loginname: u === 'dbo' ? 'sa' : `app_${d.instance.host.short.replace(/-/g, '')}`,
            defaultdbname: d.name, defaultschemaname: 'dbo', principalid: 5, sid: '0x2A'
         });
      }
   }
   writeCsv(outDir, 'mssql_users', users);

   writeCsv(outDir, 'mssql_logins', instances.map(i => ({
      collect_id: cid, collect_target: i.host.fqdn, instance_name: i.serverName,
      loginname: `app_${i.host.short.replace(/-/g, '')}`,
      accountcreationdate: '2021-03-15 09:12:00', lasttimeaccountmodified: '2025-11-02 14:20:00',
      passwordlastsettime: '2025-11-02 14:20:00', defaultdatabase: 'master', defaultlanguage: 'us_english',
      isdisabledchecked: 0, ispolicychecked: 1, isexpirationchecked: 1, isexpired: 0,
      daysuntilexpiration: 120, islocked: 0, ismustchange: 0, lockouttime: null,
      badpasswordcount: 0, badpasswordtime: null, historylength: 0,
      loginsid: '0x2A', logintype: 'SQL_LOGIN', hasserverrole: 'public'
   })));

   writeCsv(outDir, 'mssql_loginwoperm', instances.filter(i => rng.chance(0.15)).map(i => ({
      collect_id: cid, collect_target: i.host.fqdn, instance_name: i.serverName,
      loginname: `legacy_${i.host.short.replace(/-/g, '')}`, type_desc: 'SQL_LOGIN',
      is_disabled: 1, db_perms: 0, srv_perms: 0,
      modify_date: '2023-05-11 08:00:00', scandate: fmtDate(snapshot)
   })));

   writeCsv(outDir, 'mssql_validatelogin', instances.filter(i => rng.chance(0.10)).map(i => ({
      collect_id: cid, collect_target: i.host.fqdn, servername: i.serverName,
      sid: '0x2B', login: `stale_${i.host.short.replace(/-/g, '')}`, is_disabled: 1,
      modify_date: '2023-05-11 08:00:00', scandate: fmtDate(snapshot)
   })));
}
