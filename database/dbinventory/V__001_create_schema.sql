-- Oracle Database Schema for DBInventory
alter session set current_schema=dbinventory;

-- ============================================================
-- mssql_backup
-- ============================================================
create table mssql_backup (
   collect_id         varchar2(16) not null,
   collect_target     varchar2(50 char) not null,
   hostname           varchar2(50 char) not null,
   database_name      varchar2(100 char) not null,
   backup_start_date  date not null,
   backup_finish_date date not null,
   backup_type        varchar2(20 char) not null,
   backup_size        number(19) not null
);

comment on table mssql_backup is 'Raw MSSQL backup history collected daily from msdb.dbo.backupset (one row per backup operation).';
comment on column mssql_backup.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_backup.collect_target is 'Target of the collection.';
comment on column mssql_backup.hostname is 'Host name of the database server or instance.';
comment on column mssql_backup.database_name is 'Name of the database.';
comment on column mssql_backup.backup_start_date is 'Timestamp at which the backup started.';
comment on column mssql_backup.backup_finish_date is 'Timestamp at which the backup completed.';
comment on column mssql_backup.backup_type is 'Type of backup (e.g. FULL, DIFF/DIFFERENTIAL, LOG).';
comment on column mssql_backup.backup_size is 'Size of the backup, in bytes.';

-- ============================================================
-- mssql_backup_info_history
-- ============================================================
create table mssql_backup_info_history (
   collect_id         varchar2(16) not null,
   collect_target     varchar2(50 char) not null,
   scoring_result                  timestamp default on null systimestamp not null,
   cumulative_hours_between_backup number(10) not null
);

comment on table mssql_backup_info_history is 'Historical trend of the aggregated MSSQL backup freshness score, snapshotted at each daily scoring run.';
comment on column mssql_backup_info_history.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_backup_info_history.collect_target is 'Target of the collection.';
comment on column mssql_backup_info_history.scoring_result is 'Timestamp at which this scoring snapshot was taken.';
comment on column mssql_backup_info_history.cumulative_hours_between_backup is 'Cumulative number of hours elapsed between successive backups.';

-- ============================================================
-- mssql_backup_stats
-- ============================================================
create table mssql_backup_stats (
   collect_id         varchar2(16) not null,
   collect_target     varchar2(50 char) not null,
   hostname                        varchar2(50 char) not null,
   database_name                   varchar2(100 char) not null,
   recovery_model                  varchar2(20 char) not null,
   backup_type                     varchar2(20 char) not null,
   cumulative_hours_between_backup number(10) not null,
   nbrebu                          number(10) not null
);

comment on table mssql_backup_stats is 'Aggregated MSSQL backup statistics per database and backup type (average interval, number of backups).';
comment on column mssql_backup_stats.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_backup_stats.collect_target is 'Target of the collection.';
comment on column mssql_backup_stats.hostname is 'Host name of the database server or instance.';
comment on column mssql_backup_stats.database_name is 'Name of the database.';
comment on column mssql_backup_stats.recovery_model is 'Database recovery model (e.g. FULL, SIMPLE, BULK_LOGGED).';
comment on column mssql_backup_stats.backup_type is 'Type of backup (e.g. FULL, DIFF/DIFFERENTIAL, LOG).';
comment on column mssql_backup_stats.cumulative_hours_between_backup is 'Cumulative number of hours elapsed between successive backups.';
comment on column mssql_backup_stats.nbrebu is 'Number of backups considered in this aggregation.';

-- ============================================================
-- mssql_backup_summary
-- ============================================================
create table mssql_backup_summary (
   collect_id         varchar2(16) not null,
   collect_target     varchar2(50 char) not null,
   hostname             varchar2(50 char) not null,
   database_name        varchar2(100 char) not null,
   recovery_model       varchar2(100 char),
   backup_type          varchar2(20 char) not null,
   backup_start_date    date not null,
   previous_backup      date not null,
   hours_between_backup number(10) not null
);

comment on table mssql_backup_summary is 'Per-database MSSQL backup summary comparing the latest backup to the previous one, used to compute backup freshness.';
comment on column mssql_backup_summary.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_backup_summary.collect_target is 'Target of the collection.';
comment on column mssql_backup_summary.hostname is 'Host name of the database server or instance.';
comment on column mssql_backup_summary.database_name is 'Name of the database.';
comment on column mssql_backup_summary.recovery_model is 'Database recovery model (e.g. FULL, SIMPLE, BULK_LOGGED).';
comment on column mssql_backup_summary.backup_type is 'Type of backup (e.g. FULL, DIFF/DIFFERENTIAL, LOG).';
comment on column mssql_backup_summary.backup_start_date is 'Timestamp at which the backup started.';
comment on column mssql_backup_summary.previous_backup is 'Start date of the previous backup, used to compute the interval.';
comment on column mssql_backup_summary.hours_between_backup is 'Number of hours elapsed between this backup and the previous one.';

-- ============================================================
-- mssql_backup_temp
-- ============================================================
create table mssql_backup_temp (
   collect_id         varchar2(16) not null,
   collect_target     varchar2(50 char) not null,
   hostname           varchar2(50 char) not null,
   database_name      varchar2(100 char) not null,
   backup_start_date  date not null,
   backup_finish_date date not null,
   backup_type        varchar2(20 char) not null,
   backup_size        number(19) not null
);

comment on table mssql_backup_temp is 'Staging table used to land MSSQL backup data during the load process before it is merged into mssql_backup.';
comment on column mssql_backup_temp.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_backup_temp.collect_target is 'Target of the collection.';
comment on column mssql_backup_temp.hostname is 'Host name of the database server or instance.';
comment on column mssql_backup_temp.database_name is 'Name of the database.';
comment on column mssql_backup_temp.backup_start_date is 'Timestamp at which the backup started.';
comment on column mssql_backup_temp.backup_finish_date is 'Timestamp at which the backup completed.';
comment on column mssql_backup_temp.backup_type is 'Type of backup (e.g. FULL, DIFF/DIFFERENTIAL, LOG).';
comment on column mssql_backup_temp.backup_size is 'Size of the backup, in bytes.';

-- ============================================================
-- mssql_databases
-- ============================================================
create table mssql_databases (
   collect_id         varchar2(16) not null,
   collect_target     varchar2(50 char) not null,
   hostname              varchar2(100 char),
   database_id           number(5),
   database_name         varchar2(100 char),
   database_state        varchar2(100 char),
   recovery_model        varchar2(100 char),
   compatibility_level   varchar2(100 char),
   collation             varchar2(100 char),
   last_backup_date      varchar2(100 char),
   last_backup_diff_date varchar2(100 char),
   last_backup_log_date  varchar2(100 char),
   create_date           varchar2(100 char),
   is_mirroring_enabled  number(6),
   owner                 varchar2(100 char),
   agtype                varchar2(50 char),
   agname                varchar2(50 char)
);

comment on table mssql_databases is 'Inventory of MSSQL databases and their configuration, collected per instance.';
comment on column mssql_databases.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_databases.collect_target is 'Target of the collection.';
comment on column mssql_databases.hostname is 'Host name of the database server or instance.';
comment on column mssql_databases.database_id is 'Database ID as reported by sys.databases.';
comment on column mssql_databases.database_name is 'Name of the database.';
comment on column mssql_databases.database_state is 'Database state (e.g. ONLINE, OFFLINE, RESTORING).';
comment on column mssql_databases.recovery_model is 'Database recovery model (e.g. FULL, SIMPLE, BULK_LOGGED).';
comment on column mssql_databases.compatibility_level is 'Database compatibility level.';
comment on column mssql_databases.collation is 'Database or instance collation.';
comment on column mssql_databases.last_backup_date is 'Timestamp of the last full backup.';
comment on column mssql_databases.last_backup_diff_date is 'Timestamp of the last differential backup.';
comment on column mssql_databases.last_backup_log_date is 'Timestamp of the last transaction log backup.';
comment on column mssql_databases.create_date is 'Timestamp at which the database was created.';
comment on column mssql_databases.is_mirroring_enabled is 'Indicates whether database mirroring is enabled.';
comment on column mssql_databases.owner is 'Owner (schema) of the object.';
comment on column mssql_databases.agtype is 'Availability Group type the database belongs to, if any.';
comment on column mssql_databases.agname is 'Name of the Availability Group the database belongs to, if any.';

-- ============================================================
-- mssql_files
-- ============================================================
create table mssql_files (
   collect_id         varchar2(16) not null,
   collect_target     varchar2(50 char) not null,
   hostname       varchar2(100 char) not null,
   database_name  varchar2(100 char) not null,
   file_id        number(10) not null,
   type_desc      varchar2(20 char) not null,
   name           varchar2(100 char) not null,
   physical_name  varchar2(255 char) not null,
   size_mb        number(10) not null,
   growth_percent number(10) not null,
   growth_mb      number(10) not null,
   max_size       number(10) not null
);

comment on table mssql_files is 'Inventory of MSSQL database files (data and log) and their sizing/autogrowth settings.';
comment on column mssql_files.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_files.collect_target is 'Target of the collection.';
comment on column mssql_files.hostname is 'Host name of the database server or instance.';
comment on column mssql_files.database_name is 'Name of the database.';
comment on column mssql_files.file_id is 'File ID as reported by sys.database_files.';
comment on column mssql_files.type_desc is 'Type of the object as reported by the engine.';
comment on column mssql_files.name is 'Logical name of the database file.';
comment on column mssql_files.physical_name is 'Physical path of the database file on disk.';
comment on column mssql_files.size_mb is 'Size, in megabytes.';
comment on column mssql_files.growth_percent is 'Autogrowth increment expressed as a percentage, if configured that way.';
comment on column mssql_files.growth_mb is 'Autogrowth increment expressed in megabytes, if configured that way.';
comment on column mssql_files.max_size is 'Maximum size the file is allowed to grow to, in megabytes (-1/unlimited if unrestricted).';

-- ============================================================
-- mssql_hosts
-- ============================================================
-- drop table mssql_hosts;
create table mssql_hosts (
   collect_id         varchar2(16) not null,
   collect_target     varchar2(50 char) not null,
   hostname              varchar2(100 char),
   mssql_edition         varchar2(100 char),
   mssql_product_version varchar2(100 char),
   collation             varchar2(100 char),
   is_clustered          number(5),
   activenodename        varchar2(50 char) not null,
   clusternode1          varchar2(50 char),
   clusternode2          varchar2(50 char),
   parallel_threshold    number(10),
   max_dop               number(10),
   min_memory            number(10),
   max_memory            number(10),
   xp_cmdshell_enabled   number(10),
   num_cpus              number(6),
   memory_gb             number(6),
   os_type               varchar2(100 char),
   install_date          varchar2(10 char),
   service_account       varchar2(100 char)
);

comment on table mssql_hosts is 'Inventory of MSSQL instances/hosts and their engine, cluster and resource configuration.';
comment on column mssql_hosts.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_hosts.collect_target is 'Target of the collection.';
comment on column mssql_hosts.hostname is 'Host name of the database server or instance.';
comment on column mssql_hosts.mssql_edition is 'SQL Server edition (e.g. Enterprise, Standard).';
comment on column mssql_hosts.mssql_product_version is 'SQL Server product version.';
comment on column mssql_hosts.collation is 'Database or instance collation.';
comment on column mssql_hosts.is_clustered is 'Indicates whether the instance is part of a failover cluster.';
comment on column mssql_hosts.activenodename is 'Name of the cluster node currently hosting the active instance.';
comment on column mssql_hosts.clusternode1 is 'Name of the first configured cluster node.';
comment on column mssql_hosts.clusternode2 is 'Name of the second configured cluster node.';
comment on column mssql_hosts.parallel_threshold is 'Cost threshold for parallelism configured on the instance.';
comment on column mssql_hosts.max_dop is 'Maximum degree of parallelism configured on the instance.';
comment on column mssql_hosts.min_memory is 'Minimum server memory configured, in megabytes.';
comment on column mssql_hosts.max_memory is 'Maximum server memory configured, in megabytes.';
comment on column mssql_hosts.xp_cmdshell_enabled is 'Indicates whether the xp_cmdshell extended procedure is enabled.';
comment on column mssql_hosts.num_cpus is 'Number of CPUs available on the host.';
comment on column mssql_hosts.memory_gb is 'Amount of memory available on the host, in gigabytes.';
comment on column mssql_hosts.os_type is 'Operating system running on the host.';
comment on column mssql_hosts.install_date is 'Installation date of the instance, as an integer (YYYYMMDD).';
comment on column mssql_hosts.service_account is 'Windows account the SQL Server service runs as.';

-- ============================================================
-- mssql_logins
-- ============================================================
-- drop table mssql_logins;
create table mssql_logins (
   collect_id         varchar2(16) not null,
   collect_target     varchar2(50 char) not null,
   instance_name           varchar2(40 char) not null,
   loginname               varchar2(100 char) not null,
   accountcreationdate     varchar2(30 char) not null,
   lasttimeaccountmodified varchar2(30 char),
   passwordlastsettime     varchar2(30 char),
   defaultdatabase         varchar2(100 char),
   defaultlanguage         varchar2(50 char),
   isdisabledchecked       varchar2(30 char),
   ispolicychecked         varchar2(30 char),
   isexpirationchecked     varchar2(30 char),
   isexpired               varchar2(30 char),
   daysuntilexpiration     varchar2(30 char),
   islocked                varchar2(30 char),
   ismustchange            varchar2(30 char),
   lockouttime             varchar2(30 char),
   badpasswordcount        varchar2(30 char),
   badpasswordtime         varchar2(30 char),
   historylength           varchar2(30 char),
   loginsid                varchar2(200 char),
   logintype               varchar2(10 char),
   hasserverrole           varchar2(100 char)
);

comment on table mssql_logins is 'Inventory of MSSQL server logins and their password/account policy attributes, as reported by LOGINPROPERTY.';
comment on column mssql_logins.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_logins.collect_target is 'Target of the collection.';
comment on column mssql_logins.instance_name is 'Name of the database instance.';
comment on column mssql_logins.loginname is 'Name of the login being evaluated.';
comment on column mssql_logins.accountcreationdate is 'Timestamp at which the login was created.';
comment on column mssql_logins.lasttimeaccountmodified is 'Timestamp at which the login was last modified.';
comment on column mssql_logins.passwordlastsettime is 'Timestamp at which the login password was last changed.';
comment on column mssql_logins.defaultdatabase is 'Default database configured for the login.';
comment on column mssql_logins.defaultlanguage is 'Default language configured for the login.';
comment on column mssql_logins.isdisabledchecked is 'Indicates whether the login is disabled.';
comment on column mssql_logins.ispolicychecked is 'Indicates whether the Windows password policy is enforced (CHECK_POLICY).';
comment on column mssql_logins.isexpirationchecked is 'Indicates whether password expiration is enforced (CHECK_EXPIRATION).';
comment on column mssql_logins.isexpired is 'Indicates whether the login password is currently expired.';
comment on column mssql_logins.daysuntilexpiration is 'Number of days remaining before the password expires.';
comment on column mssql_logins.islocked is 'Indicates whether the login is currently locked out.';
comment on column mssql_logins.ismustchange is 'Indicates whether the login must change its password at next connection.';
comment on column mssql_logins.lockouttime is 'Timestamp at which the login was locked out, if applicable.';
comment on column mssql_logins.badpasswordcount is 'Number of consecutive failed login attempts recorded.';
comment on column mssql_logins.badpasswordtime is 'Timestamp of the last failed login attempt.';
comment on column mssql_logins.historylength is 'Number of previous passwords retained in the password history.';
comment on column mssql_logins.loginsid is 'Security identifier (SID) of the login.';
comment on column mssql_logins.logintype is 'Type of login (e.g. SQL login, Windows login).';
comment on column mssql_logins.hasserverrole is 'List of fixed server roles assigned to the login.';

-- ============================================================
-- mssql_loginwoperm
-- ============================================================
create table mssql_loginwoperm (
   collect_id         varchar2(16) not null,
   collect_target     varchar2(50 char) not null,
   instance_name varchar2(50 char) not null,
   loginname     varchar2(150 char) not null,
   type_desc     varchar2(50 char) not null,
   is_disabled   number(1) not null,
   db_perms      varchar2(150 char) not null,
   srv_perms     varchar2(150 char) not null,
   modify_date   date not null,
   scandate      date not null
);

comment on table mssql_loginwoperm is 'MSSQL logins that hold no explicit database or server permission (candidates for cleanup review).';
comment on column mssql_loginwoperm.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_loginwoperm.collect_target is 'Target of the collection.';
comment on column mssql_loginwoperm.instance_name is 'Name of the database instance.';
comment on column mssql_loginwoperm.loginname is 'Name of the login being evaluated.';
comment on column mssql_loginwoperm.type_desc is 'Type of login (e.g. SQL_LOGIN, WINDOWS_LOGIN).';
comment on column mssql_loginwoperm.is_disabled is 'Indicates whether the login/account is disabled.';
comment on column mssql_loginwoperm.db_perms is 'Database-level permissions held by the login, if any.';
comment on column mssql_loginwoperm.srv_perms is 'Server-level permissions held by the login, if any.';
comment on column mssql_loginwoperm.modify_date is 'Timestamp at which the login/object was last modified.';
comment on column mssql_loginwoperm.scandate is 'Timestamp at which this row was scanned/collected.';

-- ============================================================
-- mssql_security_auditlevel
-- ============================================================
create table mssql_security_auditlevel (
   collect_id         varchar2(16) not null,
   collect_target     varchar2(50 char) not null,
   servername       varchar2(50 char) not null,
   auditlevel       varchar2(50 char) not null,
   compliance_score number(2) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table mssql_security_auditlevel is 'MSSQL server audit level compliance check results.';
comment on column mssql_security_auditlevel.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_security_auditlevel.collect_target is 'Target of the collection.';
comment on column mssql_security_auditlevel.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_security_auditlevel.auditlevel is 'Audit level configured on the server.';
comment on column mssql_security_auditlevel.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column mssql_security_auditlevel.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_sec_auditlvl_exc
-- ============================================================
create table mssql_sec_auditlvl_exc (
   collect_id         varchar2(16) not null,
   collect_target     varchar2(50 char) not null,
   servername varchar2(50 char) not null,
   auditlevel varchar2(50 char) not null,
   comments   varchar2(200 char) default '0' not null,
   date_value timestamp default on null systimestamp not null
);

comment on table mssql_sec_auditlvl_exc is 'Documented exceptions accepted for the MSSQL server audit level compliance check.';
comment on column mssql_sec_auditlvl_exc.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_sec_auditlvl_exc.collect_target is 'Target of the collection.';
comment on column mssql_sec_auditlvl_exc.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_sec_auditlvl_exc.auditlevel is 'Audit level configured on the server.';
comment on column mssql_sec_auditlvl_exc.comments is 'Free-text justification for this documented exception.';
comment on column mssql_sec_auditlvl_exc.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_security_configoptions
-- ============================================================
create table mssql_security_configoptions (
   collect_id         varchar2(16) not null,
   collect_target     varchar2(50 char) not null,
   servername       varchar2(50 char) not null,
   name             varchar2(200 char) not null,
   config_value     number(10) not null,
   run_value        number(10) not null,
   compliance_score number(3) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table mssql_security_configoptions is 'MSSQL sp_configure options compliance check results.';
comment on column mssql_security_configoptions.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_security_configoptions.collect_target is 'Target of the collection.';
comment on column mssql_security_configoptions.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_security_configoptions.name is 'Name of the sp_configure option.';
comment on column mssql_security_configoptions.config_value is 'Configured value of the option.';
comment on column mssql_security_configoptions.run_value is 'Currently running value of the option.';
comment on column mssql_security_configoptions.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column mssql_security_configoptions.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_sec_cfgopt_exc
-- ============================================================
create table mssql_sec_cfgopt_exc (
   collect_id         varchar2(16) not null,
   collect_target     varchar2(50 char) not null,
   servername   varchar2(50 char) not null,
   name         varchar2(200 char) not null,
   config_value number(10) not null,
   run_value    number(10) not null,
   comments     varchar2(200 char) default '0' not null,
   date_value   timestamp default on null systimestamp not null
);

comment on table mssql_sec_cfgopt_exc is 'Documented exceptions accepted for the MSSQL sp_configure options compliance check.';
comment on column mssql_sec_cfgopt_exc.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_sec_cfgopt_exc.collect_target is 'Target of the collection.';
comment on column mssql_sec_cfgopt_exc.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_sec_cfgopt_exc.name is 'Name of the sp_configure option.';
comment on column mssql_sec_cfgopt_exc.config_value is 'Configured value of the option.';
comment on column mssql_sec_cfgopt_exc.run_value is 'Currently running value of the option.';
comment on column mssql_sec_cfgopt_exc.comments is 'Free-text justification for this documented exception.';
comment on column mssql_sec_cfgopt_exc.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_security_dbproperties
-- ============================================================
-- drop table mssql_security_dbproperties;
create table mssql_security_dbproperties (
   collect_id         varchar2(16) not null,
   collect_target     varchar2(50 char) not null,
   servername        varchar2(50 char) not null,
   db_name           varchar2(50 char) not null,
   is_auto_close_on  number(10) not null,
   is_trustworthy_on number(10) not null,
   compliance_score  number(2) default 0,
   date_value        timestamp default on null systimestamp not null
);

comment on table mssql_security_dbproperties is 'MSSQL database property compliance check results (AUTO_CLOSE, TRUSTWORTHY).';
comment on column mssql_security_dbproperties.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_security_dbproperties.collect_target is 'Target of the collection.';
comment on column mssql_security_dbproperties.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_security_dbproperties.db_name is 'Name of the database.';
comment on column mssql_security_dbproperties.is_auto_close_on is 'Indicates whether the AUTO_CLOSE database option is enabled.';
comment on column mssql_security_dbproperties.is_trustworthy_on is 'Indicates whether the TRUSTWORTHY database option is enabled.';
comment on column mssql_security_dbproperties.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column mssql_security_dbproperties.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_sec_dbprops_exc
-- ============================================================
create table mssql_sec_dbprops_exc (
   collect_id         varchar2(16) not null,
   collect_target     varchar2(50 char) not null,
   servername        varchar2(50 char) not null,
   db_name           varchar2(50 char) not null,
   is_auto_close_on  number(10) not null,
   is_trustworthy_on number(10) not null,
   comments          varchar2(200 char) default '0' not null,
   date_value        timestamp default on null systimestamp not null
);

comment on table mssql_sec_dbprops_exc is 'Documented exceptions accepted for the MSSQL database property compliance check.';
comment on column mssql_sec_dbprops_exc.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_sec_dbprops_exc.collect_target is 'Target of the collection.';
comment on column mssql_sec_dbprops_exc.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_sec_dbprops_exc.db_name is 'Name of the database.';
comment on column mssql_sec_dbprops_exc.is_auto_close_on is 'Indicates whether the AUTO_CLOSE database option is enabled.';
comment on column mssql_sec_dbprops_exc.is_trustworthy_on is 'Indicates whether the TRUSTWORTHY database option is enabled.';
comment on column mssql_sec_dbprops_exc.comments is 'Free-text justification for this documented exception.';
comment on column mssql_sec_dbprops_exc.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_security_encryption
-- ============================================================
create table mssql_security_encryption (
   collect_id       varchar2(16) not null,
   collect_target   varchar2(50 char) not null,
   servername       varchar2(50 char) not null,
   db_name          varchar2(50 char) not null,
   key_type         varchar2(50 char) not null,
   key_name         varchar2(100 char) not null,
   algorithm_desc   varchar2(50 char) not null,
   compliance_score number(3) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table mssql_security_encryption is 'MSSQL encryption keys (TDE certificates/keys) compliance check results.';
comment on column mssql_security_encryption.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_security_encryption.collect_target is 'Target of the collection.';
comment on column mssql_security_encryption.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_security_encryption.db_name is 'Name of the database.';
comment on column mssql_security_encryption.key_type is 'Type of encryption key (e.g. certificate, asymmetric key).';
comment on column mssql_security_encryption.key_name is 'Name of the encryption key.';
comment on column mssql_security_encryption.algorithm_desc is 'Encryption algorithm used by the key.';
comment on column mssql_security_encryption.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column mssql_security_encryption.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_sec_encryption_exc
-- ============================================================
create table mssql_sec_encryption_exc (
   collect_id       varchar2(16) not null,
   collect_target   varchar2(50 char) not null,
   servername       varchar2(50 char) not null,
   db_name          varchar2(50 char) not null,
   key_type         varchar2(50 char) not null,
   key_name         varchar2(100 char) not null,
   algorithm_desc   varchar2(50 char) not null,
   comments         varchar2(200 char) default '0' not null,
   date_value       timestamp default on null systimestamp not null
);

comment on table mssql_sec_encryption_exc is 'Documented exceptions accepted for the MSSQL encryption compliance check.';
comment on column mssql_sec_encryption_exc.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_sec_encryption_exc.collect_target is 'Target of the collection.';
comment on column mssql_sec_encryption_exc.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_sec_encryption_exc.db_name is 'Name of the database.';
comment on column mssql_sec_encryption_exc.key_type is 'Type of encryption key (e.g. certificate, asymmetric key).';
comment on column mssql_sec_encryption_exc.key_name is 'Name of the encryption key.';
comment on column mssql_sec_encryption_exc.algorithm_desc is 'Encryption algorithm used by the key.';
comment on column mssql_sec_encryption_exc.comments is 'Free-text justification for this documented exception.';
comment on column mssql_sec_encryption_exc.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_security_groups
-- ============================================================
create table mssql_security_groups (
   collect_id         varchar2(16) not null,
   collect_target     varchar2(50 char) not null,
   servername       varchar2(50 char) not null,
   localgroupname   varchar2(50 char) not null,
   permission_name  varchar2(100 char) not null,
   state_desc       varchar2(50 char) not null,
   compliance_score number(3) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table mssql_security_groups is 'MSSQL local Windows group permissions compliance check results.';
comment on column mssql_security_groups.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_security_groups.collect_target is 'Target of the collection.';
comment on column mssql_security_groups.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_security_groups.localgroupname is 'Name of the local Windows group.';
comment on column mssql_security_groups.permission_name is 'Name of the permission being evaluated.';
comment on column mssql_security_groups.state_desc is 'State of the permission/object as reported by the engine (e.g. GRANT, DENY, REVOKE).';
comment on column mssql_security_groups.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column mssql_security_groups.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_sec_groups_exc
-- ============================================================
create table mssql_sec_groups_exc (
   collect_id         varchar2(16) not null,
   collect_target     varchar2(50 char) not null,
   servername      varchar2(50 char) not null,
   localgroupname  varchar2(50 char) not null,
   permission_name varchar2(100 char) not null,
   state_desc      varchar2(50 char) not null,
   comments        varchar2(200 char) not null,
   date_value      timestamp default on null systimestamp not null
);

comment on table mssql_sec_groups_exc is 'Documented exceptions accepted for the MSSQL local Windows group permissions compliance check.';
comment on column mssql_sec_groups_exc.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_sec_groups_exc.collect_target is 'Target of the collection.';
comment on column mssql_sec_groups_exc.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_sec_groups_exc.localgroupname is 'Name of the local Windows group.';
comment on column mssql_sec_groups_exc.permission_name is 'Name of the permission being evaluated.';
comment on column mssql_sec_groups_exc.state_desc is 'State of the permission/object as reported by the engine (e.g. GRANT, DENY, REVOKE).';
comment on column mssql_sec_groups_exc.comments is 'Free-text justification for this documented exception.';
comment on column mssql_sec_groups_exc.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_security_guestconnect
-- ============================================================
create table mssql_security_guestconnect (
   collect_id       varchar2(16) not null,
   collect_target   varchar2(50 char) not null, 
   servername       varchar2(50 char) not null,
   db_name          varchar2(50 char) not null,
   permission_name  varchar2(50 char) not null,
   state_desc       varchar2(50 char) not null,
   compliance_score number(3) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table mssql_security_guestconnect is 'MSSQL guest account CONNECT permission compliance check results.';
comment on column mssql_security_guestconnect.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_security_guestconnect.collect_target is 'Target of the collection.';
comment on column mssql_security_guestconnect.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_security_guestconnect.db_name is 'Name of the database.';
comment on column mssql_security_guestconnect.permission_name is 'Name of the permission being evaluated.';
comment on column mssql_security_guestconnect.state_desc is 'State of the permission/object as reported by the engine (e.g. GRANT, DENY, REVOKE).';
comment on column mssql_security_guestconnect.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column mssql_security_guestconnect.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_sec_guestconn_exc
-- ============================================================
create table mssql_sec_guestconn_exc (
   collect_id       varchar2(16) not null,
   collect_target   varchar2(50 char) not null,
   servername      varchar2(50 char) not null,
   db_name         varchar2(50 char) not null,
   permission_name varchar2(50 char) not null,
   state_desc      varchar2(50 char) not null,
   comments        varchar2(200 char) default '0' not null,
   date_value      timestamp default on null systimestamp not null
);

comment on table mssql_sec_guestconn_exc is 'Documented exceptions accepted for the MSSQL guest account CONNECT permission compliance check.';
comment on column mssql_sec_guestconn_exc.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_sec_guestconn_exc.collect_target is 'Target of the collection.';
comment on column mssql_sec_guestconn_exc.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_sec_guestconn_exc.db_name is 'Name of the database.';
comment on column mssql_sec_guestconn_exc.permission_name is 'Name of the permission being evaluated.';
comment on column mssql_sec_guestconn_exc.state_desc is 'State of the permission/object as reported by the engine (e.g. GRANT, DENY, REVOKE).';
comment on column mssql_sec_guestconn_exc.comments is 'Free-text justification for this documented exception.';
comment on column mssql_sec_guestconn_exc.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_security_history
-- ============================================================
create table mssql_security_history (
   collect_id             varchar2(16) not null,
   collect_target         varchar2(50 char) not null,
   servername             varchar2(50 char) not null,
   compliance_score_total number(2),
   date_value             timestamp default on null systimestamp not null
);

comment on table mssql_security_history is 'Historical trend of the overall MSSQL security compliance score per server.';
comment on column mssql_security_history.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_security_history.collect_target is 'Target of the collection.';
comment on column mssql_security_history.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_security_history.compliance_score_total is 'Overall compliance score aggregated across all checks.';
comment on column mssql_security_history.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_security_logins
-- ============================================================
-- drop table mssql_security_logins;
create table mssql_security_logins (
   collect_id             varchar2(16) not null,
   collect_target         varchar2(50 char) not null,
   servername            varchar2(50 char) not null,
   login_name            varchar2(100 char) not null,
   principal_id          varchar2(100 char) not null,
   is_sysadmin           number(2) not null,
   is_policy_checked     number(2) not null,
   access_method         varchar2(50 char) not null,
   is_expiration_checked number(2) not null,
   is_disabled           number(2) not null,
   create_date           date not null,
   compliance_score      number(2) default 0,
   date_value            timestamp
);

comment on table mssql_security_logins is 'MSSQL sysadmin / high-privilege login compliance check results.';
comment on column mssql_security_logins.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_security_logins.collect_target is 'Target of the collection.';
comment on column mssql_security_logins.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_security_logins.login_name is 'Name of the login being evaluated.';
comment on column mssql_security_logins.principal_id is 'Principal ID of the login as reported by sys.server_principals.';
comment on column mssql_security_logins.is_sysadmin is 'Indicates whether the login belongs to the sysadmin fixed server role.';
comment on column mssql_security_logins.is_policy_checked is 'Indicates whether the Windows password policy is enforced for the login.';
comment on column mssql_security_logins.access_method is 'Method used to grant access (e.g. SQL login, Windows login/group).';
comment on column mssql_security_logins.is_expiration_checked is 'Indicates whether password expiration is enforced for the login.';
comment on column mssql_security_logins.is_disabled is 'Indicates whether the login is disabled.';
comment on column mssql_security_logins.create_date is 'Timestamp at which the login was created.';
comment on column mssql_security_logins.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column mssql_security_logins.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_sec_logins_exc
-- Note : ON UPDATE current_timestamp() non supporte en Oracle (supprime)
-- ============================================================
create table mssql_sec_logins_exc (
   collect_id             varchar2(16) not null,
   collect_target         varchar2(50 char) not null,
   servername varchar2(50 char) not null,
   login_name varchar2(100 char) not null,
   comments   varchar2(200 char) default '0' not null,
   date_value timestamp default on null systimestamp not null
);

comment on table mssql_sec_logins_exc is 'Documented exceptions accepted for the MSSQL sysadmin / high-privilege login compliance check.';
comment on column mssql_sec_logins_exc.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_sec_logins_exc.collect_target is 'Target of the collection.';
comment on column mssql_sec_logins_exc.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_sec_logins_exc.login_name is 'Name of the login being evaluated.';
comment on column mssql_sec_logins_exc.comments is 'Free-text justification for this documented exception.';
comment on column mssql_sec_logins_exc.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_security_orphanedusers
-- ============================================================
create table mssql_security_orphanedusers (
   collect_id       varchar2(16) not null,
   collect_target   varchar2(50 char) not null,
   servername       varchar2(50 char) not null,
   db_name          varchar2(50 char) not null,
   user_name        varchar2(100 char) not null,
   compliance_score number(3) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table mssql_security_orphanedusers is 'MSSQL orphaned database users (users without a matching server login) compliance check results.';
comment on column mssql_security_orphanedusers.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_security_orphanedusers.collect_target is 'Target of the collection.';
comment on column mssql_security_orphanedusers.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_security_orphanedusers.db_name is 'Name of the database.';
comment on column mssql_security_orphanedusers.user_name is 'Name of the orphaned database user.';
comment on column mssql_security_orphanedusers.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column mssql_security_orphanedusers.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_sec_orphanusr_exc
-- ============================================================
create table mssql_sec_orphanusr_exc (
   collect_id       varchar2(16) not null,
   collect_target   varchar2(50 char) not null,
   servername varchar2(50 char) not null,
   db_name    varchar2(50 char) not null,
   user_name  varchar2(100 char) not null,
   comments   varchar2(200 char) not null,
   date_value timestamp default on null systimestamp not null
);

comment on table mssql_sec_orphanusr_exc is 'Documented exceptions accepted for the MSSQL orphaned database users compliance check.';
comment on column mssql_sec_orphanusr_exc.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_sec_orphanusr_exc.collect_target is 'Target of the collection.';
comment on column mssql_sec_orphanusr_exc.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_sec_orphanusr_exc.db_name is 'Name of the database.';
comment on column mssql_sec_orphanusr_exc.user_name is 'Name of the orphaned database user.';
comment on column mssql_sec_orphanusr_exc.comments is 'Free-text justification for this documented exception.';
comment on column mssql_sec_orphanusr_exc.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_sec_pubperm
-- ============================================================
create table mssql_sec_pubperm (
   collect_id       varchar2(16) not null,
   collect_target   varchar2(50 char) not null,
   servername       varchar2(50 char) not null,
   db_name          varchar2(50 char) not null,
   username         varchar2(100 char) not null,
   permission_name  varchar2(100 char) not null,
   state_desc       varchar2(50 char) not null,
   compliance_score number(3) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table mssql_sec_pubperm is 'MSSQL permissions granted to the public role compliance check results.';
comment on column mssql_sec_pubperm.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_sec_pubperm.collect_target is 'Target of the collection.';
comment on column mssql_sec_pubperm.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_sec_pubperm.db_name is 'Name of the database.';
comment on column mssql_sec_pubperm.username is 'Name of the database account being evaluated.';
comment on column mssql_sec_pubperm.permission_name is 'Name of the permission being evaluated.';
comment on column mssql_sec_pubperm.state_desc is 'State of the permission/object as reported by the engine (e.g. GRANT, DENY, REVOKE).';
comment on column mssql_sec_pubperm.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column mssql_sec_pubperm.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_sec_pubperm_exc
-- ============================================================
create table mssql_sec_pubperm_exc (
   collect_id       varchar2(16) not null,
   collect_target   varchar2(50 char) not null,
   servername      varchar2(50 char) not null,
   db_name         varchar2(50 char) not null,
   username        varchar2(100 char) not null,
   permission_name varchar2(100 char) not null,
   state_desc      varchar2(50 char) not null,
   comments        varchar2(200 char) default '0' not null,
   date_value      timestamp default on null systimestamp not null
);

comment on table mssql_sec_pubperm_exc is 'Documented exceptions accepted for the MSSQL public role permissions compliance check.';
comment on column mssql_sec_pubperm_exc.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_sec_pubperm_exc.collect_target is 'Target of the collection.';
comment on column mssql_sec_pubperm_exc.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_sec_pubperm_exc.db_name is 'Name of the database.';
comment on column mssql_sec_pubperm_exc.username is 'Name of the database account being evaluated.';
comment on column mssql_sec_pubperm_exc.permission_name is 'Name of the permission being evaluated.';
comment on column mssql_sec_pubperm_exc.state_desc is 'State of the permission/object as reported by the engine (e.g. GRANT, DENY, REVOKE).';
comment on column mssql_sec_pubperm_exc.comments is 'Free-text justification for this documented exception.';
comment on column mssql_sec_pubperm_exc.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_security_registryinfo
-- ============================================================
create table mssql_security_registryinfo (
   collect_id       varchar2(16) not null,
   collect_target   varchar2(50 char) not null,
   servername       varchar2(50 char) not null,
   name             varchar2(100 char) not null,
   value            number(10) not null,
   compliance_score number(3) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table mssql_security_registryinfo is 'MSSQL registry configuration compliance check results (e.g. ForceEncryption).';
comment on column mssql_security_registryinfo.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_security_registryinfo.collect_target is 'Target of the collection.';
comment on column mssql_security_registryinfo.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_security_registryinfo.name is 'Name of the registry value being evaluated.';
comment on column mssql_security_registryinfo.value is 'Value read from the registry.';
comment on column mssql_security_registryinfo.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column mssql_security_registryinfo.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_sec_reginfo_exc
-- ============================================================
create table mssql_sec_reginfo_exc (
   collect_id         varchar2(16) not null,
   collect_target     varchar2(50 char) not null,
   servername varchar2(50 char) not null,
   name       varchar2(100 char) not null,
   comments   varchar2(200 char) default '0' not null,
   date_value timestamp default on null systimestamp not null
);

comment on table mssql_sec_reginfo_exc is 'Documented exceptions accepted for the MSSQL registry configuration compliance check.';
comment on column mssql_sec_reginfo_exc.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_sec_reginfo_exc.collect_target is 'Target of the collection.';
comment on column mssql_sec_reginfo_exc.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_sec_reginfo_exc.name is 'Name of the registry value being evaluated.';
comment on column mssql_sec_reginfo_exc.comments is 'Free-text justification for this documented exception.';
comment on column mssql_sec_reginfo_exc.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_security_scoring
-- ============================================================
create table mssql_security_scoring (
   servername             varchar2(50 char) not null,
   environment            varchar2(20 char),
   configoptions          number(2) default 0 not null,
   dbproperties           number(2) default 0 not null,
   auditlevel             number(2) default 0 not null,
   encryption             number(10) default 0 not null,
   groups                 number(10) default 0 not null,
   guestconnect           number(10) default 0 not null,
   logins                 number(10) default 0 not null,
   orphanedusers          number(10) default 0 not null,
   publicpermission       number(10) default 0 not null,
   registryinfo           number(10) default 0 not null,
   sqlserveraudit         number(10) default 0 not null,
   compliance_score_total number(2) default 0 not null,
   exception_detected     number(2) default 0 not null,
   legacy_server          number(2) default 0 not null,
   date_value             timestamp default on null systimestamp not null
);

comment on table mssql_security_scoring is 'Aggregated MSSQL security compliance score per server, broken down by check category.';
comment on column mssql_security_scoring.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_security_scoring.environment is 'Environment the row applies to (e.g. PROD, DEV, TEST).';
comment on column mssql_security_scoring.configoptions is 'Compliance score for the sp_configure options check.';
comment on column mssql_security_scoring.dbproperties is 'Compliance score for the database properties check.';
comment on column mssql_security_scoring.auditlevel is 'Compliance score for the server audit level check.';
comment on column mssql_security_scoring.encryption is 'Compliance score for the encryption keys check.';
comment on column mssql_security_scoring.groups is 'Compliance score for the local Windows groups check.';
comment on column mssql_security_scoring.guestconnect is 'Compliance score for the guest CONNECT permission check.';
comment on column mssql_security_scoring.logins is 'Compliance score for the sysadmin/high-privilege logins check.';
comment on column mssql_security_scoring.orphanedusers is 'Compliance score for the orphaned database users check.';
comment on column mssql_security_scoring.publicpermission is 'Compliance score for the public role permissions check.';
comment on column mssql_security_scoring.registryinfo is 'Compliance score for the registry configuration check.';
comment on column mssql_security_scoring.sqlserveraudit is 'Compliance score for the SQL Server Audit check.';
comment on column mssql_security_scoring.compliance_score_total is 'Overall compliance score aggregated across all checks.';
comment on column mssql_security_scoring.exception_detected is 'Indicates whether at least one documented exception was applied for this server.';
comment on column mssql_security_scoring.legacy_server is 'Indicates whether the server is flagged as a legacy/end-of-support SQL Server version.';
comment on column mssql_security_scoring.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_security_sqlserveraudit
-- ============================================================
-- drop table mssql_security_sqlserveraudit;
create table mssql_security_sqlserveraudit (
   collect_id                varchar2(16) not null,
   collect_target            varchar2(50 char) not null,
   servername                varchar2(50 char) not null,
   auditname                 varchar2(50 char) not null,
   auditenabled              number(2) not null,
   writelocation             varchar2(50 char) not null,
   auditspecificationname    varchar2(100 char) not null,
   auditspecificationenabled number(2) not null,
   auditactionname           varchar2(100 char) not null,
   audited_result            varchar2(30 char) not null,
   compliance_score          number(2),
   date_value                timestamp
);

comment on table mssql_security_sqlserveraudit is 'MSSQL Server Audit (SQL Server Audit feature) configuration compliance check results.';
comment on column mssql_security_sqlserveraudit.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_security_sqlserveraudit.collect_target is 'Target of the collection.';
comment on column mssql_security_sqlserveraudit.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_security_sqlserveraudit.auditname is 'Name of the SQL Server Audit object.';
comment on column mssql_security_sqlserveraudit.auditenabled is 'Indicates whether the SQL Server Audit object is enabled.';
comment on column mssql_security_sqlserveraudit.writelocation is 'Destination where the audit is writing its output (e.g. file path).';
comment on column mssql_security_sqlserveraudit.auditspecificationname is 'Name of the server/database audit specification.';
comment on column mssql_security_sqlserveraudit.auditspecificationenabled is 'Indicates whether the audit specification is enabled.';
comment on column mssql_security_sqlserveraudit.auditactionname is 'Name of the audited action.';
comment on column mssql_security_sqlserveraudit.audited_result is 'Result recorded by the audit action.';
comment on column mssql_security_sqlserveraudit.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column mssql_security_sqlserveraudit.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_sec_srvaudit_exc
-- ============================================================
create table mssql_sec_srvaudit_exc (
   collect_id       varchar2(16) not null,
   collect_target   varchar2(50 char) not null,
   servername      varchar2(50 char) not null,
   auditactionname varchar2(100 char) not null,
   comments        varchar2(200 char) default '0' not null,
   date_value      timestamp default on null systimestamp not null
);

comment on table mssql_sec_srvaudit_exc is 'Documented exceptions accepted for the MSSQL Server Audit compliance check.';
comment on column mssql_sec_srvaudit_exc.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_sec_srvaudit_exc.collect_target is 'Target of the collection.';
comment on column mssql_sec_srvaudit_exc.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_sec_srvaudit_exc.auditactionname is 'Name of the audited action.';
comment on column mssql_sec_srvaudit_exc.comments is 'Free-text justification for this documented exception.';
comment on column mssql_sec_srvaudit_exc.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- mssql_users
-- ============================================================
-- drop table mssql_users;
create table mssql_users (
   collect_id        varchar2(16) not null,
   collect_target    varchar2(50 char) not null,
   instance_name     varchar2(50 char) not null,
   database_name     varchar2(100 char) not null,
   name              varchar2(100 char) not null,
   groupname         varchar2(100 char),
   loginname         varchar2(100 char),
   defaultdbname     varchar2(100 char),
   defaultschemaname varchar2(100 char),
   principalid       number(10),
   sid               varchar2(100 char)
);

comment on table mssql_users is 'Inventory of MSSQL database users and their mapped logins.';
comment on column mssql_users.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_users.collect_target is 'Target of the collection.';
comment on column mssql_users.instance_name is 'Name of the database instance.';
comment on column mssql_users.database_name is 'Name of the database.';
comment on column mssql_users.name is 'Name of the database user.';
comment on column mssql_users.groupname is 'Name of the database role/group the user belongs to.';
comment on column mssql_users.loginname is 'Name of the login being evaluated.';
comment on column mssql_users.defaultdbname is 'Default database configured for the user.';
comment on column mssql_users.defaultschemaname is 'Default schema configured for the user.';
comment on column mssql_users.principalid is 'Principal ID of the user as reported by sys.database_principals.';
comment on column mssql_users.sid is 'Security identifier (SID) of the user.';

-- ============================================================
-- mssql_validatelogin
-- ============================================================
create table mssql_validatelogin (
   collect_id   varchar2(16) not null,
   collect_target varchar2(50 char) not null,
   servername  varchar2(150 char) not null,
   sid         varchar2(200 char) not null,
   login       varchar2(150 char) not null,
   is_disabled number(1) not null,
   modify_date date not null,
   scandate    date not null
);

comment on table mssql_validatelogin is 'MSSQL login validation results, cross-checking login state (e.g. against Active Directory).';
comment on column mssql_validatelogin.collect_id is 'Identifier for the collect run that produced this row';
comment on column mssql_validatelogin.collect_target is 'Target of the collection.';
comment on column mssql_validatelogin.servername is 'Name of the SQL Server instance being evaluated.';
comment on column mssql_validatelogin.sid is 'Security identifier (SID) of the login.';
comment on column mssql_validatelogin.login is 'Name of the login being validated.';
comment on column mssql_validatelogin.is_disabled is 'Indicates whether the login/account is disabled.';
comment on column mssql_validatelogin.modify_date is 'Timestamp at which the login/object was last modified.';
comment on column mssql_validatelogin.scandate is 'Timestamp at which this row was scanned/collected.';

-- ============================================================
-- oracle_audit_logon
-- ============================================================
create table oracle_audit_logon (
   db_name        varchar2(50 char) not null,
   logon_time     varchar2(100 char),
   db_username    varchar2(100 char) not null,
   os_username    varchar2(100 char) not null,
   host_client    varchar2(100 char) not null,
   client_name    varchar2(200 char) not null,
   expected_logon number(2) default 0 not null
);

comment on table oracle_audit_logon is 'Raw Oracle unified audit logon events collected since the last run.';
comment on column oracle_audit_logon.db_name is 'Name of the database.';
comment on column oracle_audit_logon.logon_time is 'Timestamp of the logon event.';
comment on column oracle_audit_logon.db_username is 'Name of the database account.';
comment on column oracle_audit_logon.os_username is 'Name of the operating system account used to connect.';
comment on column oracle_audit_logon.host_client is 'Host name of the client machine that connected.';
comment on column oracle_audit_logon.client_name is 'Name/program of the client that connected.';
comment on column oracle_audit_logon.expected_logon is 'Indicates whether this logon matches an expected/whitelisted pattern.';

-- ============================================================
-- oracle_audit_logon_history
-- ============================================================
create table oracle_audit_logon_history (
   db_name        varchar2(50 char) not null,
   logon_time     varchar2(100 char),
   db_username    varchar2(100 char) not null,
   os_username    varchar2(100 char) not null,
   host_client    varchar2(100 char) not null,
   client_name    varchar2(200 char) not null,
   expected_logon number(2) default 0 not null,
   date_value     timestamp default on null systimestamp not null
);

comment on table oracle_audit_logon_history is 'Historized Oracle unified audit logon events.';
comment on column oracle_audit_logon_history.db_name is 'Name of the database.';
comment on column oracle_audit_logon_history.logon_time is 'Timestamp of the logon event.';
comment on column oracle_audit_logon_history.db_username is 'Name of the database account.';
comment on column oracle_audit_logon_history.os_username is 'Name of the operating system account used to connect.';
comment on column oracle_audit_logon_history.host_client is 'Host name of the client machine that connected.';
comment on column oracle_audit_logon_history.client_name is 'Name/program of the client that connected.';
comment on column oracle_audit_logon_history.expected_logon is 'Indicates whether this logon matches an expected/whitelisted pattern.';
comment on column oracle_audit_logon_history.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_backup
-- ============================================================
create table oracle_backup (
   db_name      varchar2(50 char) not null,
   environment  varchar2(20 char),
   backup_type  varchar2(50 char) not null,
   status       varchar2(50 char) not null,
   start_time   timestamp(6) not null,
   end_time     timestamp(6) not null,
   elapsed_time varchar2(50 char) not null
);

comment on table oracle_backup is 'Oracle RMAN backup job records.';
comment on column oracle_backup.db_name is 'Name of the database.';
comment on column oracle_backup.environment is 'Environment the row applies to (e.g. PROD, DEV, TEST).';
comment on column oracle_backup.backup_type is 'Type of backup (e.g. FULL, DIFF/DIFFERENTIAL, LOG).';
comment on column oracle_backup.status is 'Status reported for the backup job (e.g. COMPLETED, FAILED).';
comment on column oracle_backup.start_time is 'Timestamp at which the backup job started.';
comment on column oracle_backup.end_time is 'Timestamp at which the backup job completed.';
comment on column oracle_backup.elapsed_time is 'Duration of the backup job.';

-- ============================================================
-- oracle_backup_archivelog_gap
-- ============================================================
create table oracle_backup_archivelog_gap (
   db_name              varchar2(50 char) not null,
   environment          varchar2(20 char) not null,
   start_time           timestamp(6) not null,
   previous_time        timestamp(6) not null,
   hours_between_backup number(10) not null
);

comment on table oracle_backup_archivelog_gap is 'Gaps between successive Oracle archivelog backups, used to monitor archivelog backup freshness.';
comment on column oracle_backup_archivelog_gap.db_name is 'Name of the database.';
comment on column oracle_backup_archivelog_gap.environment is 'Environment the row applies to (e.g. PROD, DEV, TEST).';
comment on column oracle_backup_archivelog_gap.start_time is 'Timestamp of the archivelog backup.';
comment on column oracle_backup_archivelog_gap.previous_time is 'Timestamp of the previous archivelog backup.';
comment on column oracle_backup_archivelog_gap.hours_between_backup is 'Number of hours elapsed between this backup and the previous one.';

-- ============================================================
-- oracle_backup_history
-- ============================================================
create table oracle_backup_history (
   scoring_result                  timestamp default on null systimestamp not null,
   environment                     varchar2(20 char) not null,
   count_backup_failed             varchar2(50 char) not null,
   cumulative_hours_between_backup number(10) not null
);

comment on table oracle_backup_history is 'Historical trend of the aggregated Oracle backup scoring, snapshotted at each daily scoring run.';
comment on column oracle_backup_history.scoring_result is 'Timestamp at which this scoring snapshot was taken.';
comment on column oracle_backup_history.environment is 'Environment the row applies to (e.g. PROD, DEV, TEST).';
comment on column oracle_backup_history.count_backup_failed is 'Number of failed backups counted for this snapshot.';
comment on column oracle_backup_history.cumulative_hours_between_backup is 'Cumulative number of hours elapsed between successive backups.';

-- ============================================================
-- oracle_backup_summary
-- ============================================================
create table oracle_backup_summary (
   db_name                         varchar2(50 char) not null,
   environment                     varchar2(20 char) not null,
   failed_backup_detected          number(10) default 0 not null,
   avg_archive_elapsed             number(10) not null,
   avg_archive_sla                 number(10) not null,
   backup_archive_sla_result       number(10) default 0 not null,
   avg_inc_elapsed                 number(10) not null,
   avg_inc_sla                     number(10) not null,
   backup_inc_sla_result           number(10) default 0 not null,
   cumulative_hours_between_backup number(10) not null
);

comment on table oracle_backup_summary is 'Per-database Oracle backup summary and SLA compliance results.';
comment on column oracle_backup_summary.db_name is 'Name of the database.';
comment on column oracle_backup_summary.environment is 'Environment the row applies to (e.g. PROD, DEV, TEST).';
comment on column oracle_backup_summary.failed_backup_detected is 'Indicates whether a failed backup was detected for this database.';
comment on column oracle_backup_summary.avg_archive_elapsed is 'Average elapsed time of archivelog backups, in minutes.';
comment on column oracle_backup_summary.avg_archive_sla is 'SLA target elapsed time for archivelog backups, in minutes.';
comment on column oracle_backup_summary.backup_archive_sla_result is 'Indicates whether the archivelog backup SLA was met.';
comment on column oracle_backup_summary.avg_inc_elapsed is 'Average elapsed time of incremental backups, in minutes.';
comment on column oracle_backup_summary.avg_inc_sla is 'SLA target elapsed time for incremental backups, in minutes.';
comment on column oracle_backup_summary.backup_inc_sla_result is 'Indicates whether the incremental backup SLA was met.';
comment on column oracle_backup_summary.cumulative_hours_between_backup is 'Cumulative number of hours elapsed between successive backups.';

-- ============================================================
-- oracle_client_version
-- ============================================================
create table oracle_client_version (
   db_name         varchar2(50 char) not null,
   db_version      varchar2(50 char) not null,
   environment     varchar2(50 char) not null,
   pdb_name        varchar2(50 char) not null,
   client_version  varchar2(50 char) not null,
   client_driver   varchar2(100 char),
   username        varchar2(50 char) not null,
   client_host     varchar2(50 char) not null,
   service_name    varchar2(50 char) not null,
   failover_type   varchar2(50 char) not null,
   failover_method varchar2(50 char) not null,
   check_client    number(10) default 1
);

comment on table oracle_client_version is 'Oracle client versions connecting to each database, collected for compatibility and security review.';
comment on column oracle_client_version.db_name is 'Name of the database.';
comment on column oracle_client_version.db_version is 'Database engine version.';
comment on column oracle_client_version.environment is 'Environment the row applies to (e.g. PROD, DEV, TEST).';
comment on column oracle_client_version.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_client_version.client_version is 'Version of the Oracle client used by the connecting session.';
comment on column oracle_client_version.client_driver is 'Driver used by the connecting client (e.g. JDBC, OCI).';
comment on column oracle_client_version.username is 'Name of the database account being evaluated.';
comment on column oracle_client_version.client_host is 'Host name of the connecting client.';
comment on column oracle_client_version.service_name is 'Name of the service the client connected through.';
comment on column oracle_client_version.failover_type is 'Type of connection failover configured (TAF).';
comment on column oracle_client_version.failover_method is 'Method used for connection failover (TAF).';
comment on column oracle_client_version.check_client is 'Indicates whether this client version should be checked against the minimum supported version.';

-- ============================================================
-- oracle_metrics_cpu_memory
-- ============================================================
create table oracle_metrics_cpu_memory (
   pdb_name            varchar2(50 char) not null,
   cpu_time_minutes    number(10) not null,
   avg_sga_mb          number(10) not null,
   avg_pga_mb          number(10) not null,
   avg_buffer_cache_mb number(10) not null,
   avg_shared_pool_mb  number(10) not null,
   environment         varchar2(20 char),
   date_value          timestamp default on null systimestamp not null
);

comment on table oracle_metrics_cpu_memory is 'Current Oracle PDB CPU and memory usage metrics.';
comment on column oracle_metrics_cpu_memory.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_metrics_cpu_memory.cpu_time_minutes is 'Cumulative CPU time consumed, in minutes.';
comment on column oracle_metrics_cpu_memory.avg_sga_mb is 'Average SGA (System Global Area) size, in megabytes.';
comment on column oracle_metrics_cpu_memory.avg_pga_mb is 'Average PGA (Program Global Area) size, in megabytes.';
comment on column oracle_metrics_cpu_memory.avg_buffer_cache_mb is 'Average buffer cache size, in megabytes.';
comment on column oracle_metrics_cpu_memory.avg_shared_pool_mb is 'Average shared pool size, in megabytes.';
comment on column oracle_metrics_cpu_memory.environment is 'Environment the row applies to (e.g. PROD, DEV, TEST).';
comment on column oracle_metrics_cpu_memory.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_metrics_cpu_mem_hist
-- ============================================================
create table oracle_metrics_cpu_mem_hist (
   pdb_name            varchar2(50 char) not null,
   cpu_time_minutes    number(10) not null,
   avg_sga_mb          number(10) not null,
   avg_pga_mb          number(10) not null,
   avg_buffer_cache_mb number(10) not null,
   avg_shared_pool_mb  number(10) not null,
   environment         varchar2(20 char),
   date_value          timestamp default on null systimestamp not null
);

comment on table oracle_metrics_cpu_mem_hist is 'Historized Oracle PDB CPU and memory usage metrics.';
comment on column oracle_metrics_cpu_mem_hist.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_metrics_cpu_mem_hist.cpu_time_minutes is 'Cumulative CPU time consumed, in minutes.';
comment on column oracle_metrics_cpu_mem_hist.avg_sga_mb is 'Average SGA (System Global Area) size, in megabytes.';
comment on column oracle_metrics_cpu_mem_hist.avg_pga_mb is 'Average PGA (Program Global Area) size, in megabytes.';
comment on column oracle_metrics_cpu_mem_hist.avg_buffer_cache_mb is 'Average buffer cache size, in megabytes.';
comment on column oracle_metrics_cpu_mem_hist.avg_shared_pool_mb is 'Average shared pool size, in megabytes.';
comment on column oracle_metrics_cpu_mem_hist.environment is 'Environment the row applies to (e.g. PROD, DEV, TEST).';
comment on column oracle_metrics_cpu_mem_hist.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_metrics_cpu_service
-- ============================================================
create table oracle_metrics_cpu_service (
   pdb_name           varchar2(50 char) not null,
   service_name       varchar2(100 char) not null,
   dbcpu_time_minutes number(10) not null,
   date_value         timestamp default on null systimestamp not null
);

comment on table oracle_metrics_cpu_service is 'Current Oracle CPU usage metrics broken down by service.';
comment on column oracle_metrics_cpu_service.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_metrics_cpu_service.service_name is 'Name of the Oracle service.';
comment on column oracle_metrics_cpu_service.dbcpu_time_minutes is 'Database CPU time consumed by the service, in minutes.';
comment on column oracle_metrics_cpu_service.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_metrics_cpu_svc_hist
-- Note : decimal(50,3) -> NUMBER(38,3) [precision max Oracle = 38]
-- ============================================================
create table oracle_metrics_cpu_svc_hist (
   pdb_name           varchar2(50 char) not null,
   service_name       varchar2(100 char) not null,
   dbcpu_time_minutes number(10) not null,
   percentage_usage   number(38,3) not null,
   date_value         varchar2(8 char) not null
);

comment on table oracle_metrics_cpu_svc_hist is 'Historized Oracle CPU usage metrics broken down by service.';
comment on column oracle_metrics_cpu_svc_hist.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_metrics_cpu_svc_hist.service_name is 'Name of the Oracle service.';
comment on column oracle_metrics_cpu_svc_hist.dbcpu_time_minutes is 'Database CPU time consumed by the service, in minutes.';
comment on column oracle_metrics_cpu_svc_hist.percentage_usage is 'Share of the database total CPU time consumed by this service, in percent.';
comment on column oracle_metrics_cpu_svc_hist.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_size_usage
-- ============================================================
create table oracle_size_usage (
   db_name         varchar2(50 char) not null,
   pdb_name        varchar2(50 char) not null,
   tablespace_name varchar2(200 char) not null,
   size_mb         number(10) not null,
   environment     varchar2(20 char),
   sum_segment_mb  number(10) default 0,
   date_value      timestamp default on null systimestamp not null
);

comment on table oracle_size_usage is 'Current Oracle tablespace size usage per PDB.';
comment on column oracle_size_usage.db_name is 'Name of the database.';
comment on column oracle_size_usage.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_size_usage.tablespace_name is 'Name of the tablespace.';
comment on column oracle_size_usage.size_mb is 'Size, in megabytes.';
comment on column oracle_size_usage.environment is 'Environment the row applies to (e.g. PROD, DEV, TEST).';
comment on column oracle_size_usage.sum_segment_mb is 'Sum of segment sizes allocated within the tablespace, in megabytes.';
comment on column oracle_size_usage.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_size_usage_history
-- ============================================================
create table oracle_size_usage_history (
   db_name         varchar2(50 char) not null,
   pdb_name        varchar2(50 char) not null,
   tablespace_name varchar2(200 char) not null,
   size_mb         number(10) not null,
   environment     varchar2(20 char),
   sum_segment_mb  number(10) default 0,
   date_value      timestamp default on null systimestamp not null
);

comment on table oracle_size_usage_history is 'Historized Oracle tablespace size usage per PDB.';
comment on column oracle_size_usage_history.db_name is 'Name of the database.';
comment on column oracle_size_usage_history.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_size_usage_history.tablespace_name is 'Name of the tablespace.';
comment on column oracle_size_usage_history.size_mb is 'Size, in megabytes.';
comment on column oracle_size_usage_history.environment is 'Environment the row applies to (e.g. PROD, DEV, TEST).';
comment on column oracle_size_usage_history.sum_segment_mb is 'Sum of segment sizes allocated within the tablespace, in megabytes.';
comment on column oracle_size_usage_history.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_size_usage_seg
-- ============================================================
create table oracle_size_usage_seg (
   db_name         varchar2(50 char) not null,
   pdb_name        varchar2(50 char) not null,
   tablespace_name varchar2(200 char) not null,
   sum_segment_mb  number(10) not null,
   date_value      timestamp default on null systimestamp not null
);

comment on table oracle_size_usage_seg is 'Oracle tablespace segment size usage per PDB.';
comment on column oracle_size_usage_seg.db_name is 'Name of the database.';
comment on column oracle_size_usage_seg.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_size_usage_seg.tablespace_name is 'Name of the tablespace.';
comment on column oracle_size_usage_seg.sum_segment_mb is 'Sum of segment sizes allocated within the tablespace, in megabytes.';
comment on column oracle_size_usage_seg.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_capplan_exacc_usage
-- ============================================================
create table oracle_capplan_exacc_usage (
   price         number(10),
   cluster_name  varchar2(30 char) not null,
   date_of_month varchar2(8 char)
);

comment on table oracle_capplan_exacc_usage is 'Exadata Cloud at Customer (ExaCC) cluster pricing reference used for capacity planning cost calculations.';
comment on column oracle_capplan_exacc_usage.price is 'Unit price used for the cost calculation.';
comment on column oracle_capplan_exacc_usage.cluster_name is 'Name of the Exadata Cloud at Customer (ExaCC) cluster.';
comment on column oracle_capplan_exacc_usage.date_of_month is 'Reference month for this capacity planning snapshot (YYYYMM/YYYYMMDD).';

-- ============================================================
-- oracle_capplan_hist_applink
-- Note : DEFAULT '' retire (chaine vide = NULL en Oracle)
-- ============================================================
create table oracle_capplan_hist_applink (
   pdb_name         varchar2(50 char) not null,
   env              varchar2(8 char) not null,
   application_name varchar2(30 char) not null,
   app_code         varchar2(30 char) not null
);

comment on table oracle_capplan_hist_applink is 'Mapping of Oracle PDBs to business application names/codes, used for capacity planning cost allocation.';
comment on column oracle_capplan_hist_applink.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_capplan_hist_applink.env is 'Environment the row applies to (e.g. PROD, DEV, TEST).';
comment on column oracle_capplan_hist_applink.application_name is 'Name of the business application associated with this PDB.';
comment on column oracle_capplan_hist_applink.app_code is 'Application code associated with this PDB, used for cost allocation.';

-- ============================================================
-- oracle_capplan_hist_prebuilt
-- Notes : decimal(50,3) -> NUMBER(38,3) [precision max Oracle = 38]
--         float -> BINARY_FLOAT
--         DEFAULT '' retire (chaine vide = NULL en Oracle)
-- ============================================================
create table oracle_capplan_hist_prebuilt (
   pdb_name                      varchar2(50 char) not null,
   env                           varchar2(8 char) not null,
   application_name              varchar2(30 char) not null,
   cluster_name                  varchar2(30 char) not null,
   size_gb                       number(10),
   cpu_consume_per_month_per_pdb number(10),
   cpu_minutes_price             binary_float,
   global_percentage_consumption number(38,3),
   env_percentage_consumption    number(38,3),
   date_of_month                 varchar2(8 char),
   cost_total                    binary_float not null,
   exacc_cost_usage              binary_float not null,
   exacc_ocpu_usage              binary_float not null,
   zdlra_cost_usage              binary_float not null
);

comment on table oracle_capplan_hist_prebuilt is 'Historized capacity planning data per PDB: size, CPU consumption and cost breakdown.';
comment on column oracle_capplan_hist_prebuilt.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_capplan_hist_prebuilt.env is 'Environment the row applies to (e.g. PROD, DEV, TEST).';
comment on column oracle_capplan_hist_prebuilt.application_name is 'Name of the business application associated with this PDB.';
comment on column oracle_capplan_hist_prebuilt.cluster_name is 'Name of the Exadata Cloud at Customer (ExaCC) cluster.';
comment on column oracle_capplan_hist_prebuilt.size_gb is 'Size, in gigabytes.';
comment on column oracle_capplan_hist_prebuilt.cpu_consume_per_month_per_pdb is 'CPU time consumed per month by this PDB, in minutes.';
comment on column oracle_capplan_hist_prebuilt.cpu_minutes_price is 'Unit price applied per CPU minute consumed.';
comment on column oracle_capplan_hist_prebuilt.global_percentage_consumption is 'Share of the total cluster CPU consumption attributed to this PDB, in percent.';
comment on column oracle_capplan_hist_prebuilt.env_percentage_consumption is 'Share of the environment CPU consumption attributed to this PDB, in percent.';
comment on column oracle_capplan_hist_prebuilt.date_of_month is 'Reference month for this capacity planning snapshot (YYYYMM/YYYYMMDD).';
comment on column oracle_capplan_hist_prebuilt.cost_total is 'Total cost attributed to this PDB for the period.';
comment on column oracle_capplan_hist_prebuilt.exacc_cost_usage is 'Cost share attributed to Exadata Cloud at Customer (ExaCC) usage.';
comment on column oracle_capplan_hist_prebuilt.exacc_ocpu_usage is 'OCPU usage attributed to Exadata Cloud at Customer (ExaCC).';
comment on column oracle_capplan_hist_prebuilt.zdlra_cost_usage is 'Cost share attributed to Zero Data Loss Recovery Appliance (ZDLRA) usage.';

-- ============================================================
-- oracle_capplan_summary
-- ============================================================
create table oracle_capplan_summary (
   db_name             varchar2(50 char) not null,
   pdb_name            varchar2(50 char) not null,
   environment         varchar2(20 char) not null,
   size_mb             number(10) not null,
   cpu_time_minutes    number(10) default 0 not null,
   avg_sga_mb          number(10) default 0 not null,
   avg_pga_mb          number(10) default 0 not null,
   avg_buffer_cache_mb number(10) default 0 not null,
   avg_shared_pool_mb  number(10) default 0 not null,
   zdlra_cost_usage    binary_float default 0 not null,
   exacc_ocpu_usage    binary_float default 0 not null,
   exacc_cost_usage    binary_float default 0 not null,
   cost_total          binary_float default 0 not null,
   date_value          timestamp default on null systimestamp not null
);

comment on table oracle_capplan_summary is 'Current capacity planning summary per PDB: size, CPU/memory usage and cost breakdown.';
comment on column oracle_capplan_summary.db_name is 'Name of the database.';
comment on column oracle_capplan_summary.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_capplan_summary.environment is 'Environment the row applies to (e.g. PROD, DEV, TEST).';
comment on column oracle_capplan_summary.size_mb is 'Size, in megabytes.';
comment on column oracle_capplan_summary.cpu_time_minutes is 'Cumulative CPU time consumed, in minutes.';
comment on column oracle_capplan_summary.avg_sga_mb is 'Average SGA (System Global Area) size, in megabytes.';
comment on column oracle_capplan_summary.avg_pga_mb is 'Average PGA (Program Global Area) size, in megabytes.';
comment on column oracle_capplan_summary.avg_buffer_cache_mb is 'Average buffer cache size, in megabytes.';
comment on column oracle_capplan_summary.avg_shared_pool_mb is 'Average shared pool size, in megabytes.';
comment on column oracle_capplan_summary.zdlra_cost_usage is 'Cost share attributed to Zero Data Loss Recovery Appliance (ZDLRA) usage.';
comment on column oracle_capplan_summary.exacc_ocpu_usage is 'OCPU usage attributed to Exadata Cloud at Customer (ExaCC).';
comment on column oracle_capplan_summary.exacc_cost_usage is 'Cost share attributed to Exadata Cloud at Customer (ExaCC) usage.';
comment on column oracle_capplan_summary.cost_total is 'Total cost attributed to this PDB for the period.';
comment on column oracle_capplan_summary.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_databases
-- ============================================================
create table oracle_databases (
   environment      varchar2(20 char) not null,
   license_type     varchar2(50 char) not null,
   hostname         varchar2(100 char) not null,
   instance_name    varchar2(50 char) not null,
   db_version       varchar2(50 char) not null,
   db_name          varchar2(50 char) not null,
   db_log_mode      varchar2(50 char) not null,
   db_role          varchar2(50 char) not null,
   db_unique_name   varchar2(50 char),
   db_charset       varchar2(50 char) not null,
   db_edition       varchar2(50 char) not null,
   rac_state        varchar2(50 char) not null,
   sga              varchar2(50 char),
   pga              varchar2(50 char),
   asm_free         varchar2(50 char),
   asm_total        varchar2(50 char),
   easy_connect_tns varchar2(100 char),
   database_type    varchar2(50 char) not null,
   count_pdb        number(10) default 0
);

comment on table oracle_databases is 'Inventory of Oracle databases/instances and their configuration.';
comment on column oracle_databases.environment is 'Environment the row applies to (e.g. PROD, DEV, TEST).';
comment on column oracle_databases.license_type is 'Licensing type applied to this host/instance.';
comment on column oracle_databases.hostname is 'Host name of the database server or instance.';
comment on column oracle_databases.instance_name is 'Name of the database instance.';
comment on column oracle_databases.db_version is 'Database engine version.';
comment on column oracle_databases.db_name is 'Name of the database.';
comment on column oracle_databases.db_log_mode is 'Archive log mode of the database (ARCHIVELOG / NOARCHIVELOG).';
comment on column oracle_databases.db_role is 'Role of the database in a Data Guard configuration (PRIMARY / STANDBY).';
comment on column oracle_databases.db_unique_name is 'Unique database name (db_unique_name) used in Data Guard configurations.';
comment on column oracle_databases.db_charset is 'Database character set.';
comment on column oracle_databases.db_edition is 'Oracle Database edition (e.g. Enterprise Edition).';
comment on column oracle_databases.rac_state is 'Indicates whether Real Application Clusters (RAC) is in use.';
comment on column oracle_databases.sga is 'Configured SGA (System Global Area) size.';
comment on column oracle_databases.pga is 'Configured PGA (Program Global Area) target.';
comment on column oracle_databases.asm_free is 'Free space available in the ASM disk group, if applicable.';
comment on column oracle_databases.asm_total is 'Total space of the ASM disk group, if applicable.';
comment on column oracle_databases.easy_connect_tns is 'Easy Connect / TNS connection string for the database.';
comment on column oracle_databases.database_type is 'Type of database deployment (e.g. single instance, RAC, CDB).';
comment on column oracle_databases.count_pdb is 'Number of pluggable databases (PDBs) hosted, if the database is a CDB.';

-- ============================================================
-- oracle_dataguard
-- ============================================================
create table oracle_dataguard (
   primary_db            varchar2(100 char) not null,
   standby_db            varchar2(100 char) not null,
   pdb_list_impacted     varchar2(2000 char),
   service_list_impacted varchar2(2000 char),
   protection_mode       varchar2(100 char)
);

comment on table oracle_dataguard is 'Oracle Data Guard primary/standby configuration and protection mode.';
comment on column oracle_dataguard.primary_db is 'Name of the primary database.';
comment on column oracle_dataguard.standby_db is 'Name of the standby database.';
comment on column oracle_dataguard.pdb_list_impacted is 'List of PDBs impacted by this Data Guard configuration.';
comment on column oracle_dataguard.service_list_impacted is 'List of services impacted by this Data Guard configuration.';
comment on column oracle_dataguard.protection_mode is 'Data Guard protection mode (e.g. MAXIMUM PERFORMANCE, MAXIMUM AVAILABILITY, MAXIMUM PROTECTION).';

-- ============================================================
-- oracle_hosts
-- ============================================================
create table oracle_hosts (
   environment  varchar2(20 char) not null,
   license_type varchar2(50 char) not null,
   hostname     varchar2(100 char) not null,
   num_cpus     number(6) not null,
   memory_gb    number(6) not null,
   os_type      varchar2(100 char) not null
);

comment on table oracle_hosts is 'Inventory of Oracle database hosts and their hardware/OS configuration.';
comment on column oracle_hosts.environment is 'Environment the row applies to (e.g. PROD, DEV, TEST).';
comment on column oracle_hosts.license_type is 'Licensing type applied to this host/instance.';
comment on column oracle_hosts.hostname is 'Host name of the database server or instance.';
comment on column oracle_hosts.num_cpus is 'Number of CPUs available on the host.';
comment on column oracle_hosts.memory_gb is 'Amount of memory available on the host, in gigabytes.';
comment on column oracle_hosts.os_type is 'Operating system running on the host.';

-- ============================================================
-- oracle_jdbc_tns
-- ============================================================
create table oracle_jdbc_tns (
   service_name     varchar2(100 char) not null,
   easy_connect_tns varchar2(100 char),
   db_name          varchar2(50 char) not null,
   tcp_port         number(5),
   primary_hst      varchar2(50 char),
   standby_hst      varchar2(50 char)
);

comment on table oracle_jdbc_tns is 'Oracle JDBC/TNS connection information per service.';
comment on column oracle_jdbc_tns.service_name is 'Name of the Oracle service.';
comment on column oracle_jdbc_tns.easy_connect_tns is 'Easy Connect / TNS connection string for the service.';
comment on column oracle_jdbc_tns.db_name is 'Name of the database.';
comment on column oracle_jdbc_tns.tcp_port is 'TCP port used by the listener for this connection.';
comment on column oracle_jdbc_tns.primary_hst is 'Host name of the primary database for this connection.';
comment on column oracle_jdbc_tns.standby_hst is 'Host name of the standby database for this connection, if any.';

-- ============================================================
-- oracle_lms
-- ============================================================
create table oracle_lms (
   grouping_id      number(1),                     -- 0=détail par PDB, 1=agrégé toutes PDBs
   con_id           number(5),                     -- PDB container ID (DBA_FEATURE_USAGE_STATISTICS)
   db_pdb_name      varchar2(50 char),             -- Nullable in non-CDBs, populated in CDBs with PDB name
   product_name     varchar2(150 char) not null,
   usage_detected   varchar2(100 char) not null,
   last_sample_date varchar2(20 char),             -- format YYYYMMDD produit par oracle_lms.sql
   first_usage_date varchar2(100 char),            -- peut valoir 'Never'
   last_usage_date  varchar2(100 char),            -- peut valoir 'Never'
   db_name          varchar2(50 char) not null,
   hostname         varchar2(50 char) not null
);

comment on table oracle_lms is 'Oracle License Management System (LMS) feature usage detection, used for license compliance review.';
comment on column oracle_lms.grouping_id is 'Aggregation level of the row: 0 = detail per PDB, 1 = aggregated across all PDBs.';
comment on column oracle_lms.con_id is 'PDB container ID, as reported by DBA_FEATURE_USAGE_STATISTICS.';
comment on column oracle_lms.db_pdb_name is 'Name of the database or pluggable database the feature usage was detected on.';
comment on column oracle_lms.product_name is 'Name of the Oracle option/feature being tracked.';
comment on column oracle_lms.usage_detected is 'Indicates whether usage of the feature was detected.';
comment on column oracle_lms.last_sample_date is 'Date of the last usage sample, in YYYYMMDD format.';
comment on column oracle_lms.first_usage_date is 'Date the feature was first used, or ''Never'' if it has not been used.';
comment on column oracle_lms.last_usage_date is 'Date the feature was last used, or ''Never'' if it has not been used.';
comment on column oracle_lms.db_name is 'Name of the database.';
comment on column oracle_lms.hostname is 'Host name of the database server or instance.';

-- ============================================================
-- oracle_lms_reference
-- ============================================================
create table oracle_lms_reference (
   product_name varchar2(150 char) not null,
   num_core     number(6) not null,
   license_type varchar2(50 char) not null,
   constraint pk_oracle_lms_reference primary key ( product_name )
);

comment on table oracle_lms_reference is 'Reference table mapping Oracle product/option names to their licensing core factor and license type, used to compute LMS licensing costs.';
comment on column oracle_lms_reference.product_name is 'Name of the Oracle option/feature, matching oracle_lms.product_name.';
comment on column oracle_lms_reference.num_core is 'Number of cores counted per license unit for this product.';
comment on column oracle_lms_reference.license_type is 'Oracle licensing metric this product is billed under (e.g. Processor, Named User Plus).';

-- ============================================================
-- oracle_pdbs
-- ============================================================
create table oracle_pdbs (
   hostname      varchar2(100 char) not null,
   instance_name varchar2(50 char) not null,
   pdb_name      varchar2(50 char) not null,
   pdb_state     varchar2(50 char) not null
);

comment on table oracle_pdbs is 'Inventory of Oracle pluggable databases (PDBs) and their state.';
comment on column oracle_pdbs.hostname is 'Host name of the database server or instance.';
comment on column oracle_pdbs.instance_name is 'Name of the database instance.';
comment on column oracle_pdbs.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_pdbs.pdb_state is 'State of the pluggable database (e.g. READ WRITE, MOUNTED).';

-- ============================================================
-- oracle_psu
-- ============================================================
create table oracle_psu (
   db_name     varchar2(50 char) not null,
   db_version  varchar2(50 char) not null,
   psu_applied varchar2(200 char) not null
);

comment on table oracle_psu is 'Oracle Patch Set Update (PSU) / patch level applied per database.';
comment on column oracle_psu.db_name is 'Name of the database.';
comment on column oracle_psu.db_version is 'Database engine version.';
comment on column oracle_psu.psu_applied is 'Identifier of the patch set update (PSU/RU) applied to the database.';

-- ============================================================
-- oracle_sec_admin_high_privs
-- ============================================================
create table oracle_sec_admin_high_privs (
   db_name          varchar2(50 char) not null,
   username         varchar2(50 char) not null,
   compliance_score number(2) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table oracle_sec_admin_high_privs is 'Oracle users holding high administrative privileges, compliance check results.';
comment on column oracle_sec_admin_high_privs.db_name is 'Name of the database.';
comment on column oracle_sec_admin_high_privs.username is 'Name of the database account being evaluated.';
comment on column oracle_sec_admin_high_privs.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column oracle_sec_admin_high_privs.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_sec_adm_high_privs_exc
-- ============================================================
create table oracle_sec_adm_high_privs_exc (
   db_name    varchar2(50 char) not null,
   username   varchar2(50 char) not null,
   comments   varchar2(100 char) not null,
   date_value timestamp default on null systimestamp not null
);

comment on table oracle_sec_adm_high_privs_exc is 'Documented exceptions accepted for the Oracle high administrative privileges compliance check.';
comment on column oracle_sec_adm_high_privs_exc.db_name is 'Name of the database.';
comment on column oracle_sec_adm_high_privs_exc.username is 'Name of the database account being evaluated.';
comment on column oracle_sec_adm_high_privs_exc.comments is 'Free-text justification for this documented exception.';
comment on column oracle_sec_adm_high_privs_exc.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_security_audit_enable
-- ============================================================
create table oracle_security_audit_enable (
   db_name          varchar2(50 char) not null,
   pdb_name         varchar2(50 char) not null,
   audit_parameter  varchar2(50 char) not null,
   audit_activated  number(2),
   compliance_score number(2) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table oracle_security_audit_enable is 'Oracle unified audit policy activation compliance check results.';
comment on column oracle_security_audit_enable.db_name is 'Name of the database.';
comment on column oracle_security_audit_enable.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_security_audit_enable.audit_parameter is 'Name of the audit policy/parameter being evaluated.';
comment on column oracle_security_audit_enable.audit_activated is 'Indicates whether the audit policy is activated.';
comment on column oracle_security_audit_enable.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column oracle_security_audit_enable.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_sec_default_profile
-- ============================================================
create table oracle_sec_default_profile (
   db_name          varchar2(50 char) not null,
   pdb_name         varchar2(50 char) not null,
   username         varchar2(50 char) not null,
   profile          varchar2(50 char) not null,
   oracle_managed   varchar2(50 char) not null,
   compliance_score number(2) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table oracle_sec_default_profile is 'Oracle users still assigned the DEFAULT profile, compliance check results.';
comment on column oracle_sec_default_profile.db_name is 'Name of the database.';
comment on column oracle_sec_default_profile.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_sec_default_profile.username is 'Name of the database account being evaluated.';
comment on column oracle_sec_default_profile.profile is 'Name of the profile assigned to the account.';
comment on column oracle_sec_default_profile.oracle_managed is 'Indicates whether the account is an Oracle-managed (built-in) account.';
comment on column oracle_sec_default_profile.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column oracle_sec_default_profile.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_sec_def_profile_exc
-- ============================================================
create table oracle_sec_def_profile_exc (
   db_name    varchar2(50 char) not null,
   pdb_name   varchar2(50 char) not null,
   username   varchar2(50 char) not null,
   profile    varchar2(50 char) not null,
   comments   varchar2(100 char) not null,
   date_value timestamp default on null systimestamp not null
);

comment on table oracle_sec_def_profile_exc is 'Documented exceptions accepted for the Oracle default profile compliance check.';
comment on column oracle_sec_def_profile_exc.db_name is 'Name of the database.';
comment on column oracle_sec_def_profile_exc.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_sec_def_profile_exc.username is 'Name of the database account being evaluated.';
comment on column oracle_sec_def_profile_exc.profile is 'Name of the profile assigned to the account.';
comment on column oracle_sec_def_profile_exc.comments is 'Free-text justification for this documented exception.';
comment on column oracle_sec_def_profile_exc.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_sec_default_user_pwd
-- ============================================================
create table oracle_sec_default_user_pwd (
   db_name          varchar2(50 char) not null,
   pdb_name         varchar2(50 char) not null,
   username         varchar2(50 char) not null,
   compliance_score number(2) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table oracle_sec_default_user_pwd is 'Oracle accounts detected using default/well-known passwords, compliance check results.';
comment on column oracle_sec_default_user_pwd.db_name is 'Name of the database.';
comment on column oracle_sec_default_user_pwd.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_sec_default_user_pwd.username is 'Name of the database account being evaluated.';
comment on column oracle_sec_default_user_pwd.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column oracle_sec_default_user_pwd.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_sec_high_role_privs
-- ============================================================
create table oracle_sec_high_role_privs (
   db_name          varchar2(50 char) not null,
   pdb_name         varchar2(50 char) not null,
   username         varchar2(50 char) not null,
   privilege        varchar2(100 char) not null,
   compliance_score number(2) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table oracle_sec_high_role_privs is 'Oracle users granted high-privilege roles, compliance check results.';
comment on column oracle_sec_high_role_privs.db_name is 'Name of the database.';
comment on column oracle_sec_high_role_privs.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_sec_high_role_privs.username is 'Name of the database account being evaluated.';
comment on column oracle_sec_high_role_privs.privilege is 'Name of the privilege being evaluated.';
comment on column oracle_sec_high_role_privs.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column oracle_sec_high_role_privs.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_sec_high_role_priv_exc
-- ============================================================
create table oracle_sec_high_role_priv_exc (
   db_name    varchar2(50 char) not null,
   pdb_name   varchar2(50 char) not null,
   username   varchar2(50 char) not null,
   privilege  varchar2(100 char) not null,
   comments   varchar2(100 char) not null,
   date_value timestamp default on null systimestamp not null
);

comment on table oracle_sec_high_role_priv_exc is 'Documented exceptions accepted for the Oracle high-privilege role compliance check.';
comment on column oracle_sec_high_role_priv_exc.db_name is 'Name of the database.';
comment on column oracle_sec_high_role_priv_exc.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_sec_high_role_priv_exc.username is 'Name of the database account being evaluated.';
comment on column oracle_sec_high_role_priv_exc.privilege is 'Name of the privilege being evaluated.';
comment on column oracle_sec_high_role_priv_exc.comments is 'Free-text justification for this documented exception.';
comment on column oracle_sec_high_role_priv_exc.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_sec_high_sys_privs
-- ============================================================
create table oracle_sec_high_sys_privs (
   db_name          varchar2(50 char) not null,
   pdb_name         varchar2(50 char) not null,
   username         varchar2(50 char) not null,
   privilege        varchar2(100 char) not null,
   compliance_score number(2) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table oracle_sec_high_sys_privs is 'Oracle users granted high-privilege system privileges, compliance check results.';
comment on column oracle_sec_high_sys_privs.db_name is 'Name of the database.';
comment on column oracle_sec_high_sys_privs.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_sec_high_sys_privs.username is 'Name of the database account being evaluated.';
comment on column oracle_sec_high_sys_privs.privilege is 'Name of the privilege being evaluated.';
comment on column oracle_sec_high_sys_privs.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column oracle_sec_high_sys_privs.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_sec_high_sys_privs_exc
-- ============================================================
create table oracle_sec_high_sys_privs_exc (
   db_name    varchar2(50 char) not null,
   pdb_name   varchar2(50 char) not null,
   username   varchar2(50 char) not null,
   privilege  varchar2(100 char) not null,
   comments   varchar2(100 char) not null,
   date_value timestamp default on null systimestamp not null
);

comment on table oracle_sec_high_sys_privs_exc is 'Documented exceptions accepted for the Oracle high-privilege system privileges compliance check.';
comment on column oracle_sec_high_sys_privs_exc.db_name is 'Name of the database.';
comment on column oracle_sec_high_sys_privs_exc.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_sec_high_sys_privs_exc.username is 'Name of the database account being evaluated.';
comment on column oracle_sec_high_sys_privs_exc.privilege is 'Name of the privilege being evaluated.';
comment on column oracle_sec_high_sys_privs_exc.comments is 'Free-text justification for this documented exception.';
comment on column oracle_sec_high_sys_privs_exc.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_sec_high_tab_privs
-- ============================================================
create table oracle_sec_high_tab_privs (
   db_name          varchar2(50 char) not null,
   pdb_name         varchar2(50 char) not null,
   username         varchar2(50 char) not null,
   privilege        varchar2(100 char) not null,
   compliance_score number(2) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table oracle_sec_high_tab_privs is 'Oracle users granted high-privilege table privileges, compliance check results.';
comment on column oracle_sec_high_tab_privs.db_name is 'Name of the database.';
comment on column oracle_sec_high_tab_privs.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_sec_high_tab_privs.username is 'Name of the database account being evaluated.';
comment on column oracle_sec_high_tab_privs.privilege is 'Name of the privilege being evaluated.';
comment on column oracle_sec_high_tab_privs.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column oracle_sec_high_tab_privs.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_sec_high_tab_privs_exc
-- ============================================================
create table oracle_sec_high_tab_privs_exc (
   db_name    varchar2(50 char) not null,
   pdb_name   varchar2(50 char) not null,
   username   varchar2(50 char) not null,
   privilege  varchar2(100 char) not null,
   comments   varchar2(100 char) not null,
   date_value timestamp default on null systimestamp not null
);

comment on table oracle_sec_high_tab_privs_exc is 'Documented exceptions accepted for the Oracle high-privilege table privileges compliance check.';
comment on column oracle_sec_high_tab_privs_exc.db_name is 'Name of the database.';
comment on column oracle_sec_high_tab_privs_exc.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_sec_high_tab_privs_exc.username is 'Name of the database account being evaluated.';
comment on column oracle_sec_high_tab_privs_exc.privilege is 'Name of the privilege being evaluated.';
comment on column oracle_sec_high_tab_privs_exc.comments is 'Free-text justification for this documented exception.';
comment on column oracle_sec_high_tab_privs_exc.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_security_history
-- ============================================================
create table oracle_security_history (
   db_name                varchar2(50 char) not null,
   environment            varchar2(20 char) not null,
   compliance_score_total number(2),
   date_value             timestamp default on null systimestamp not null
);

comment on table oracle_security_history is 'Historical trend of the overall Oracle security compliance score per database.';
comment on column oracle_security_history.db_name is 'Name of the database.';
comment on column oracle_security_history.environment is 'Environment the row applies to (e.g. PROD, DEV, TEST).';
comment on column oracle_security_history.compliance_score_total is 'Overall compliance score aggregated across all checks.';
comment on column oracle_security_history.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_sec_network_encryption
-- ============================================================
create table oracle_sec_network_encryption (
   db_name           varchar2(50 char) not null,
   sqlnet_encryption varchar2(200 char) not null,
   compliance_score  number(2) default 0,
   date_value        timestamp default on null systimestamp not null
);

comment on table oracle_sec_network_encryption is 'Oracle network (SQL*Net) encryption configuration compliance check results.';
comment on column oracle_sec_network_encryption.db_name is 'Name of the database.';
comment on column oracle_sec_network_encryption.sqlnet_encryption is 'Value of the SQL*Net encryption configuration parameter.';
comment on column oracle_sec_network_encryption.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column oracle_sec_network_encryption.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_security_parameter
-- ============================================================
create table oracle_security_parameter (
   db_name          varchar2(50 char) not null,
   parameter_value  varchar2(1000 char),
   parameter_name   varchar2(50 char) not null,
   compliance_score number(2) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table oracle_security_parameter is 'Oracle initialization/security parameter compliance check results.';
comment on column oracle_security_parameter.db_name is 'Name of the database.';
comment on column oracle_security_parameter.parameter_value is 'Value of the configuration parameter.';
comment on column oracle_security_parameter.parameter_name is 'Name of the configuration parameter being evaluated.';
comment on column oracle_security_parameter.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column oracle_security_parameter.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_sec_parameter_exc
-- ============================================================
create table oracle_sec_parameter_exc (
   db_name         varchar2(50 char) not null,
   parameter_value varchar2(50 char),
   parameter_name  varchar2(50 char) not null,
   comments        varchar2(100 char) not null,
   date_value      timestamp default on null systimestamp not null
);

comment on table oracle_sec_parameter_exc is 'Documented exceptions accepted for the Oracle security parameter compliance check.';
comment on column oracle_sec_parameter_exc.db_name is 'Name of the database.';
comment on column oracle_sec_parameter_exc.parameter_value is 'Value of the configuration parameter.';
comment on column oracle_sec_parameter_exc.parameter_name is 'Name of the configuration parameter being evaluated.';
comment on column oracle_sec_parameter_exc.comments is 'Free-text justification for this documented exception.';
comment on column oracle_sec_parameter_exc.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_security_profile
-- ============================================================
create table oracle_security_profile (
   db_name          varchar2(50 char) not null,
   pdb_name         varchar2(50 char) not null,
   profile          varchar2(50 char) not null,
   resource_name    varchar2(100 char) not null,
   limit_value      varchar2(100 char),
   compliance_score number(2) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table oracle_security_profile is 'Oracle profile resource limit compliance check results.';
comment on column oracle_security_profile.db_name is 'Name of the database.';
comment on column oracle_security_profile.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_security_profile.profile is 'Name of the profile assigned to the account.';
comment on column oracle_security_profile.resource_name is 'Name of the profile resource limit parameter.';
comment on column oracle_security_profile.limit_value is 'Value configured for the profile resource limit.';
comment on column oracle_security_profile.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column oracle_security_profile.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_sec_profile_exc
-- ============================================================
create table oracle_sec_profile_exc (
   db_name       varchar2(50 char) not null,
   pdb_name      varchar2(50 char) not null,
   profile       varchar2(50 char) not null,
   resource_name varchar2(100 char) not null,
   limit_value   varchar2(100 char) not null,
   comments      varchar2(100 char) not null,
   date_value    timestamp default on null systimestamp not null
);

comment on table oracle_sec_profile_exc is 'Documented exceptions accepted for the Oracle profile resource limit compliance check.';
comment on column oracle_sec_profile_exc.db_name is 'Name of the database.';
comment on column oracle_sec_profile_exc.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_sec_profile_exc.profile is 'Name of the profile assigned to the account.';
comment on column oracle_sec_profile_exc.resource_name is 'Name of the profile resource limit parameter.';
comment on column oracle_sec_profile_exc.limit_value is 'Value configured for the profile resource limit.';
comment on column oracle_sec_profile_exc.comments is 'Free-text justification for this documented exception.';
comment on column oracle_sec_profile_exc.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_security_scoring
-- ============================================================
create table oracle_security_scoring (
   db_name                    varchar2(50 char) not null,
   environment                varchar2(20 char),
   admin_high_privs_score     number(2) default 0,
   audit_enable_score         number(2) default 0,
   default_profile_score      number(2) default 0,
   default_user_pwd_score     number(2) default 0,
   high_role_privs_score      number(2) default 0,
   high_sys_privs_score       number(2) default 0,
   high_tab_privs_score       number(2) default 0,
   security_parameter_score   number(2) default 0,
   security_profile_score     number(2) default 0,
   encrypted_tablespace_score number(2) default 0,
   network_encryption_score   number(2) default 0,
   compliance_score_total     number(2) default 0,
   date_value                 timestamp default on null systimestamp not null
);

comment on table oracle_security_scoring is 'Aggregated Oracle security compliance score per database, broken down by check category.';
comment on column oracle_security_scoring.db_name is 'Name of the database.';
comment on column oracle_security_scoring.environment is 'Environment the row applies to (e.g. PROD, DEV, TEST).';
comment on column oracle_security_scoring.admin_high_privs_score is 'Compliance score for the high administrative privileges check.';
comment on column oracle_security_scoring.audit_enable_score is 'Compliance score for the audit policy activation check.';
comment on column oracle_security_scoring.default_profile_score is 'Compliance score for the default profile check.';
comment on column oracle_security_scoring.default_user_pwd_score is 'Compliance score for the default password check.';
comment on column oracle_security_scoring.high_role_privs_score is 'Compliance score for the high-privilege roles check.';
comment on column oracle_security_scoring.high_sys_privs_score is 'Compliance score for the high-privilege system privileges check.';
comment on column oracle_security_scoring.high_tab_privs_score is 'Compliance score for the high-privilege table privileges check.';
comment on column oracle_security_scoring.security_parameter_score is 'Compliance score for the security parameter check.';
comment on column oracle_security_scoring.security_profile_score is 'Compliance score for the profile resource limit check.';
comment on column oracle_security_scoring.encrypted_tablespace_score is 'Compliance score for the tablespace encryption check.';
comment on column oracle_security_scoring.network_encryption_score is 'Compliance score for the network encryption check.';
comment on column oracle_security_scoring.compliance_score_total is 'Overall compliance score aggregated across all checks.';
comment on column oracle_security_scoring.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_security_tablespace
-- ============================================================
create table oracle_security_tablespace (
   db_name          varchar2(50 char) not null,
   pdb_name         varchar2(50 char) not null,
   tablespace_name  varchar2(100 char) not null,
   encrypted        varchar2(100 char) not null,
   license_type     varchar2(50 char),
   compliance_score number(2) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table oracle_security_tablespace is 'Oracle tablespace encryption compliance check results.';
comment on column oracle_security_tablespace.db_name is 'Name of the database.';
comment on column oracle_security_tablespace.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_security_tablespace.tablespace_name is 'Name of the tablespace.';
comment on column oracle_security_tablespace.encrypted is 'Indicates whether the tablespace is encrypted.';
comment on column oracle_security_tablespace.license_type is 'Licensing type applied to this host/instance.';
comment on column oracle_security_tablespace.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column oracle_security_tablespace.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- oracle_sec_usermig_tbl_exist
-- SYS.USER$MIG : residus de migration avec hash legacy 10G (DES).
-- ============================================================
create table oracle_sec_usermig_tbl_exist (
   db_name    varchar2(50 char) not null,
   pdb_name   varchar2(50 char) not null,
   owner      varchar2(30 char) not null,
   table_name varchar2(30 char) not null
);

comment on table oracle_sec_usermig_tbl_exist is 'Detection of the legacy SYS.USER$MIG table, a leftover of pre-11g password hash migration containing weak DES hashes.';
comment on column oracle_sec_usermig_tbl_exist.db_name is 'Name of the database.';
comment on column oracle_sec_usermig_tbl_exist.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_sec_usermig_tbl_exist.owner is 'Owner (schema) of the object.';
comment on column oracle_sec_usermig_tbl_exist.table_name is 'Name of the table.';

-- ============================================================
-- oracle_services
-- ============================================================
create table oracle_services (
   hostname      varchar2(100 char) not null,
   instance_name varchar2(50 char) not null,
   pdb_name      varchar2(50 char) not null,
   service_name  varchar2(100 char) not null
);

comment on table oracle_services is 'Inventory of Oracle database services per PDB.';
comment on column oracle_services.hostname is 'Host name of the database server or instance.';
comment on column oracle_services.instance_name is 'Name of the database instance.';
comment on column oracle_services.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_services.service_name is 'Name of the Oracle service.';

-- ============================================================
-- oracle_users
-- ============================================================
create table oracle_users (
   hostname       varchar2(100 char) not null,
   instance_name  varchar2(50 char) not null,
   pdb_name       varchar2(50 char) not null,
   username       varchar2(50 char) not null,
   account_status varchar2(100 char) not null,
   db_name        varchar2(50 char)
);

comment on table oracle_users is 'Inventory of Oracle database users and their account status.';
comment on column oracle_users.hostname is 'Host name of the database server or instance.';
comment on column oracle_users.instance_name is 'Name of the database instance.';
comment on column oracle_users.pdb_name is 'Name of the Oracle pluggable database (PDB).';
comment on column oracle_users.username is 'Name of the database account being evaluated.';
comment on column oracle_users.account_status is 'Account status of the user (e.g. OPEN, LOCKED, EXPIRED).';
comment on column oracle_users.db_name is 'Name of the database.';

-- ============================================================
-- product_support
-- ============================================================
create table product_support (
   product_company     varchar2(15 char) not null,
   product_type        varchar2(15 char) not null,
   product_version     varchar2(100 char) not null,
   commercial_name     varchar2(100 char),
   display_name        varchar2(30 char) not null,
   current_patch_name  varchar2(30 char),
   current_patch_level varchar2(100 char),
   current_patch_date  date,
   edition_date        date not null,
   end_of_support_date date not null,
   end_of_ext_support_date date,
   constraint pk_product_support primary key ( product_company,
                                               product_type,
                                               product_version )
);

comment on table product_support is 'Reference table of vendor product end-of-support (EOL/EOSL) dates, used for lifecycle compliance checks.';
comment on column product_support.product_company is 'Company that produces the product (e.g. ORACLE, MICROSOFT, POSTGRESQL).';
comment on column product_support.product_type is 'Product family (e.g. ORACLE, MSSQL, POSTGRES, OS).';
comment on column product_support.product_version is 'Product version this end-of-support date applies to.';
comment on column product_support.commercial_name is 'Commercial name of the product version.';
comment on column product_support.display_name is 'Short display name used in reports/dashboards.';
comment on column product_support.edition_date is 'Date on which the product version was released.';
comment on column product_support.end_of_support_date is 'Date on which the vendor ends support for this product version.';
comment on column product_support.end_of_ext_support_date is 'Date on which the vendor ends extended support for this product version.';
comment on column product_support.current_patch_level is 'Current patch level for the product version.';
comment on column product_support.current_patch_date is 'Date of the current patch level.';
   
-- ============================================================
-- postgres_hosts
-- ============================================================
create table postgres_hosts (
   hostname          varchar2(100 char) not null,
   environment       varchar2(20 char) not null,
   license_type      varchar2(50 char) not null,
   pg_version        varchar2(50 char) not null,
   port              number(5) not null,
   data_directory    varchar2(255 char),
   start_time        varchar2(30 char),
   max_connections   number(10),
   shared_buffers_mb number(10),
   wal_level         varchar2(20 char),
   archive_mode      varchar2(20 char),
   db_role           varchar2(20 char) not null
);

comment on table postgres_hosts is 'Inventory of PostgreSQL instances/hosts and their configuration.';
comment on column postgres_hosts.hostname is 'Host name of the database server or instance.';
comment on column postgres_hosts.environment is 'Environment the row applies to (e.g. PROD, DEV, TEST).';
comment on column postgres_hosts.license_type is 'Licensing type applied to this host/instance.';
comment on column postgres_hosts.pg_version is 'PostgreSQL engine version.';
comment on column postgres_hosts.port is 'TCP port the instance listens on.';
comment on column postgres_hosts.data_directory is 'Path of the PostgreSQL data directory.';
comment on column postgres_hosts.start_time is 'Timestamp at which the PostgreSQL instance was started.';
comment on column postgres_hosts.max_connections is 'Maximum number of concurrent connections configured (max_connections).';
comment on column postgres_hosts.shared_buffers_mb is 'Size of the shared_buffers configuration parameter, in megabytes.';
comment on column postgres_hosts.wal_level is 'WAL level configured on the instance (e.g. replica, logical).';
comment on column postgres_hosts.archive_mode is 'WAL archive mode configured on the instance.';
comment on column postgres_hosts.db_role is 'Role of the instance/database in the replication topology (e.g. primary, standby).';

-- ============================================================
-- postgres_databases
-- ============================================================
create table postgres_databases (
   hostname     varchar2(100 char) not null,
   environment  varchar2(20 char) not null,
   datname      varchar2(100 char) not null,
   owner        varchar2(100 char),
   encoding     varchar2(20 char),
   collation    varchar2(50 char),
   size_mb      number(15),
   datconnlimit number(10),
   is_template  varchar2(3 char),
   tablespace   varchar2(100 char),
   date_value   timestamp default on null systimestamp not null
);

comment on table postgres_databases is 'Inventory of PostgreSQL databases and their properties.';
comment on column postgres_databases.hostname is 'Host name of the database server or instance.';
comment on column postgres_databases.environment is 'Environment the row applies to (e.g. PROD, DEV, TEST).';
comment on column postgres_databases.datname is 'Name of the PostgreSQL database.';
comment on column postgres_databases.owner is 'Owner role of the database.';
comment on column postgres_databases.encoding is 'Character encoding of the database.';
comment on column postgres_databases.collation is 'Database or instance collation.';
comment on column postgres_databases.size_mb is 'Size, in megabytes.';
comment on column postgres_databases.datconnlimit is 'Maximum number of concurrent connections allowed to the database (-1 = unlimited).';
comment on column postgres_databases.is_template is 'Indicates whether the database is flagged as a template database.';
comment on column postgres_databases.tablespace is 'Default tablespace of the database.';
comment on column postgres_databases.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- postgres_replication
-- Equivalent oracle_dataguard : etat de la replication streaming.
-- ============================================================
create table postgres_replication (
   hostname    varchar2(100 char) not null,
   db_role     varchar2(20 char) not null,
   peer_addr   varchar2(100 char),
   state       varchar2(30 char),
   sync_state  varchar2(20 char),
   lag_seconds number(10)
);

comment on table postgres_replication is 'PostgreSQL streaming replication status, the Postgres equivalent of oracle_dataguard.';
comment on column postgres_replication.hostname is 'Host name of the database server or instance.';
comment on column postgres_replication.db_role is 'Role of the instance/database in the replication topology (e.g. primary, standby).';
comment on column postgres_replication.peer_addr is 'Network address of the replication peer.';
comment on column postgres_replication.state is 'Replication connection state (e.g. streaming).';
comment on column postgres_replication.sync_state is 'Synchronization state of the replica (e.g. async, sync, quorum).';
comment on column postgres_replication.lag_seconds is 'Replication lag observed on the primary (replay_lag), in seconds.';

-- ============================================================
-- postgres_backup
-- Suivi de l'archivage WAL (pg_stat_archiver) : pas de catalogue de
-- sauvegarde applicative sans outil dedie (pgBackRest/Barman non utilise).
-- ============================================================
create table postgres_backup (
   hostname           varchar2(100 char) not null,
   archive_mode       varchar2(20 char),
   archived_count     number(15),
   last_archived_wal  varchar2(50 char),
   last_archived_time varchar2(30 char),
   failed_count       number(15),
   last_failed_wal    varchar2(50 char),
   last_failed_time   varchar2(30 char)
);

comment on table postgres_backup is 'PostgreSQL WAL archiving status (pg_stat_archiver); no dedicated backup catalog tool (pgBackRest/Barman) is in use.';
comment on column postgres_backup.hostname is 'Host name of the database server or instance.';
comment on column postgres_backup.archive_mode is 'WAL archive mode configured on the instance.';
comment on column postgres_backup.archived_count is 'Number of WAL segments successfully archived since the last statistics reset.';
comment on column postgres_backup.last_archived_wal is 'Name of the last WAL segment successfully archived.';
comment on column postgres_backup.last_archived_time is 'Timestamp of the last successful WAL archiving operation.';
comment on column postgres_backup.failed_count is 'Number of failed attempts to archive WAL segments since the last statistics reset.';
comment on column postgres_backup.last_failed_wal is 'Name of the last WAL segment that failed to archive.';
comment on column postgres_backup.last_failed_time is 'Timestamp of the last failed WAL archiving attempt.';

-- ============================================================
-- postgres_extensions
-- ============================================================
create table postgres_extensions (
   hostname   varchar2(100 char) not null,
   datname    varchar2(100 char) not null,
   extname    varchar2(100 char) not null,
   extversion varchar2(20 char)
);

comment on table postgres_extensions is 'Inventory of PostgreSQL extensions installed per database.';
comment on column postgres_extensions.hostname is 'Host name of the database server or instance.';
comment on column postgres_extensions.datname is 'Name of the PostgreSQL database.';
comment on column postgres_extensions.extname is 'Name of the installed extension.';
comment on column postgres_extensions.extversion is 'Version of the installed extension.';

-- ============================================================
-- postgres_security_parameter
-- ============================================================
create table postgres_security_parameter (
   hostname         varchar2(100 char) not null,
   parameter_name   varchar2(100 char) not null,
   parameter_value  varchar2(500 char),
   compliance_score number(3) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table postgres_security_parameter is 'PostgreSQL configuration parameter compliance check results.';
comment on column postgres_security_parameter.hostname is 'Host name of the database server or instance.';
comment on column postgres_security_parameter.parameter_name is 'Name of the configuration parameter being evaluated.';
comment on column postgres_security_parameter.parameter_value is 'Value of the configuration parameter.';
comment on column postgres_security_parameter.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column postgres_security_parameter.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- postgres_security_roles
-- ============================================================
create table postgres_security_roles (
   hostname         varchar2(100 char) not null,
   rolname          varchar2(100 char) not null,
   rolsuper         varchar2(1 char) not null,
   rolcreaterole    varchar2(1 char) not null,
   rolcreatedb      varchar2(1 char) not null,
   rolcanlogin      varchar2(1 char) not null,
   rolreplication   varchar2(1 char) not null,
   rolbypassrls     varchar2(1 char) not null,
   rolconnlimit     number(10),
   rolvaliduntil    varchar2(30 char),
   compliance_score number(3) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table postgres_security_roles is 'PostgreSQL role attribute compliance check results.';
comment on column postgres_security_roles.hostname is 'Host name of the database server or instance.';
comment on column postgres_security_roles.rolname is 'Name of the PostgreSQL role.';
comment on column postgres_security_roles.rolsuper is 'Indicates whether the role has the SUPERUSER attribute.';
comment on column postgres_security_roles.rolcreaterole is 'Indicates whether the role has the CREATEROLE attribute.';
comment on column postgres_security_roles.rolcreatedb is 'Indicates whether the role has the CREATEDB attribute.';
comment on column postgres_security_roles.rolcanlogin is 'Indicates whether the role has the LOGIN attribute.';
comment on column postgres_security_roles.rolreplication is 'Indicates whether the role has the REPLICATION attribute.';
comment on column postgres_security_roles.rolbypassrls is 'Indicates whether the role has the BYPASSRLS attribute.';
comment on column postgres_security_roles.rolconnlimit is 'Maximum number of concurrent connections allowed for the role (-1 = unlimited).';
comment on column postgres_security_roles.rolvaliduntil is 'Password expiration timestamp configured for the role, if any.';
comment on column postgres_security_roles.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column postgres_security_roles.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- postgres_sec_role_members
-- Appartenance aux roles predefinis sensibles (pg_read_all_data,
-- pg_execute_server_program, pg_monitor, ...).
-- ============================================================
create table postgres_sec_role_members (
   hostname         varchar2(100 char) not null,
   role_name        varchar2(100 char) not null,
   member_of        varchar2(100 char) not null,
   compliance_score number(3) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table postgres_sec_role_members is 'PostgreSQL role membership compliance check results, focused on sensitive predefined roles (pg_read_all_data, pg_execute_server_program, pg_monitor, ...).';
comment on column postgres_sec_role_members.hostname is 'Host name of the database server or instance.';
comment on column postgres_sec_role_members.role_name is 'Name of the role whose membership is being evaluated.';
comment on column postgres_sec_role_members.member_of is 'Name of the (typically sensitive predefined) role this role is a member of.';
comment on column postgres_sec_role_members.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column postgres_sec_role_members.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- postgres_security_hba_rules
-- ============================================================
create table postgres_security_hba_rules (
   hostname         varchar2(100 char) not null,
   line_number      number(10) not null,
   rule_type        varchar2(20 char),
   database         varchar2(200 char),
   user_name        varchar2(200 char),
   address          varchar2(100 char),
   auth_method      varchar2(30 char) not null,
   compliance_score number(3) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table postgres_security_hba_rules is 'PostgreSQL pg_hba.conf authentication rule compliance check results.';
comment on column postgres_security_hba_rules.hostname is 'Host name of the database server or instance.';
comment on column postgres_security_hba_rules.line_number is 'Line number of the rule within pg_hba.conf.';
comment on column postgres_security_hba_rules.rule_type is 'Connection type of the rule (e.g. host, hostssl, local).';
comment on column postgres_security_hba_rules.database is 'Database(s) the rule applies to.';
comment on column postgres_security_hba_rules.user_name is 'User(s)/role(s) the rule applies to.';
comment on column postgres_security_hba_rules.address is 'Client address/CIDR range the rule applies to.';
comment on column postgres_security_hba_rules.auth_method is 'Authentication method configured by the rule (e.g. trust, md5, scram-sha-256).';
comment on column postgres_security_hba_rules.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column postgres_security_hba_rules.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- postgres_sec_db_privs
-- Droits accordes a PUBLIC sur les bases (CONNECT/CREATE).
-- ============================================================
create table postgres_sec_db_privs (
   hostname         varchar2(100 char) not null,
   datname          varchar2(100 char) not null,
   grantee          varchar2(100 char) not null,
   privilege_type   varchar2(30 char) not null,
   compliance_score number(3) default 0,
   date_value       timestamp default on null systimestamp not null
);

comment on table postgres_sec_db_privs is 'PostgreSQL PUBLIC role database privilege (CONNECT/CREATE) compliance check results.';
comment on column postgres_sec_db_privs.hostname is 'Host name of the database server or instance.';
comment on column postgres_sec_db_privs.datname is 'Name of the PostgreSQL database.';
comment on column postgres_sec_db_privs.grantee is 'Name of the role or user the privilege is granted to.';
comment on column postgres_sec_db_privs.privilege_type is 'Type of privilege granted (e.g. CONNECT, CREATE).';
comment on column postgres_sec_db_privs.compliance_score is 'Compliance score assigned to this check result (0 = non-compliant, higher = compliant).';
comment on column postgres_sec_db_privs.date_value is 'Timestamp at which this row was collected or computed.';

-- ============================================================
-- postgres_collect_list
-- ============================================================
create table postgres_collect_list (
   collect_name varchar2(30 char) not null,
   hostname     varchar2(150 char) not null,
   port         number(5) default 5432 not null,
   environment  varchar2(10 char) not null,
   license_type varchar2(50 char) not null,
   active       number(1) default 1 not null,
   constraint pk_postgres_collect_list primary key ( collect_name )
);

comment on table postgres_collect_list is 'List of PostgreSQL instances to be collected by the inventory pipeline.';
comment on column postgres_collect_list.collect_name is 'Unique name identifying this collection target.';
comment on column postgres_collect_list.hostname is 'Host name of the database server or instance.';
comment on column postgres_collect_list.port is 'TCP port the instance listens on.';
comment on column postgres_collect_list.environment is 'Environment the row applies to (e.g. PROD, DEV, TEST).';
comment on column postgres_collect_list.license_type is 'Licensing type applied to this host/instance.';
comment on column postgres_collect_list.active is 'Flag indicating whether this entry is actively collected (1) or disabled (0).';


-- ============================================================
-- mssql_collect_list
-- ============================================================
create table mssql_collect_list (
   hostname     varchar2(150 char) not null,
   port         number(5) default 1433 not null,
   environment  varchar2(10 char) not null,
   license_type varchar2(50 char) not null,
   active       number(1) default 1 not null,
   constraint pk_mssql_collect_list primary key ( hostname, port )
);

comment on table mssql_collect_list is 'List of MSSQL instances to be collected by the inventory pipeline.';
comment on column mssql_collect_list.hostname is 'Host name of the database server or instance.';
comment on column mssql_collect_list.port is 'TCP port the instance listens on.';
comment on column mssql_collect_list.environment is 'Environment the row applies to (e.g. PROD, DEV, TEST).';
comment on column mssql_collect_list.license_type is 'Licensing type applied to this host/instance.';
comment on column mssql_collect_list.active is 'Flag indicating whether this entry is actively collected (1) or disabled (0).';


-- ============================================================
-- oracle_collect_list
-- ============================================================
create table oracle_collect_list (
   collect_name     varchar2(30 char) not null,
   easy_connect_tns varchar2(150 char) not null,
   environment      varchar2(10 char) not null,
   license_type     varchar2(10 char) not null,
   active           number(1) default 1 not null,
   constraint pk_oracle_collect_list primary key ( collect_name )
);

comment on table oracle_collect_list is 'List of Oracle databases to be collected by the inventory pipeline.';
comment on column oracle_collect_list.collect_name is 'Unique name identifying this collection target.';
comment on column oracle_collect_list.easy_connect_tns is 'Easy Connect / TNS connection string used to reach the database.';
comment on column oracle_collect_list.environment is 'Environment the row applies to (e.g. PROD, DEV, TEST).';
comment on column oracle_collect_list.license_type is 'Licensing type applied to this host/instance.';
comment on column oracle_collect_list.active is 'Flag indicating whether this entry is actively collected (1) or disabled (0).';

-- ============================================================
-- scoring_activity_list
-- ============================================================
create table scoring_activity_list (
   scoring_type             varchar2(30 char) not null,
   last_scoring_date        timestamp default current_timestamp not null,
   last_scoring_value       number(3) default 0 not null,
   scoring_card_class       varchar2(100 char) not null,
   scoring_status           varchar2(10 char) not null,
   status_color             varchar2(100 char),
   scoring_label            varchar2(256 char),
   details_apex_page_number number,
   scoring_order            number(2),
   constraint pk_scoring_activity_list primary key ( scoring_type )
);

comment on table scoring_activity_list is 'Reference list of scoring/compliance activities displayed on the dashboard, with their latest computed value and status.';
comment on column scoring_activity_list.scoring_type is 'Unique identifier of the scoring activity.';
comment on column scoring_activity_list.last_scoring_date is 'Timestamp of the last computed scoring run.';
comment on column scoring_activity_list.last_scoring_value is 'Latest computed score value.';
comment on column scoring_activity_list.scoring_card_class is 'CSS/style class used to render the scoring card on the dashboard.';
comment on column scoring_activity_list.scoring_status is 'Latest status of the scoring activity (e.g. OK, WARNING, CRITICAL).';
comment on column scoring_activity_list.status_color is 'Color used to represent the status on the dashboard.';
comment on column scoring_activity_list.scoring_label is 'Display label of the scoring activity on the dashboard.';
comment on column scoring_activity_list.details_apex_page_number is 'APEX page number linked from the dashboard for the detail view.';
comment on column scoring_activity_list.scoring_order is 'Display order of the scoring activity on the dashboard.';

-- ============================================================
-- environments
-- ============================================================
create table environments (
   envt_short_code   varchar2(3 char) not null,
   environment       varchar2(12 char) not null,
   constraint pk_environments primary key ( envt_short_code )
);

comment on table environments is 'List of environments used in the system.';
comment on column environments.envt_short_code is 'Short code representing the environment (PK)';
comment on column environments.environment is 'Full name of the environment.';

-- ============================================================
-- oracle_discovery_list
-- ============================================================
create table oracle_discovery_list (
   server_name       varchar2(100 char) not null,
   instance_name     varchar2(100 char) not null,
   port              number(5),
   envt_short_code   varchar2(3 char) not null,
   license_type      varchar2(30 char) not null,
   collect_active    number(1) default 0 not null,
   discovery_date    timestamp default systimestamp,
   last_update       timestamp default on null systimestamp not null,
   constraint pk_oracle_discovery_list primary key ( instance_name )
);

comment on table oracle_discovery_list is 'List of Oracle instances discovered by the discovery script.';
comment on column oracle_discovery_list.server_name is 'Name of the server hosting the Oracle instance.';
comment on column oracle_discovery_list.instance_name is 'Name of the Oracle instance';
comment on column oracle_discovery_list.port is 'TCP port the instance listens on.';
comment on column oracle_discovery_list.envt_short_code is 'Environment the row applies to (e.g. PRD, DEV, TST).';
comment on column oracle_discovery_list.license_type is 'Licensing type applied to this host/instance.';
comment on column oracle_discovery_list.collect_active is 'Flag indicating whether this entry is actively collected (1) or disabled (0).';
comment on column oracle_discovery_list.discovery_date is 'Timestamp at which this row was discovered.';
comment on column oracle_discovery_list.last_update is 'Timestamp at which this row was last updated.';

-- ============================================================
-- mssql_discovery_list
-- ============================================================
create table mssql_discovery_list (
   server_name       varchar2(100 char) not null,
   instance_name     varchar2(100 char) not null,
   port              number(5),
   envt_short_code   varchar2(3 char) not null,
   license_type      varchar2(30 char) not null,
   collect_active    number(1) default 0 not null,
   discovery_date    timestamp default systimestamp,
   last_update       timestamp default on null systimestamp not null,
   constraint pk_mssql_discovery_list primary key ( instance_name )
);

comment on table mssql_discovery_list is 'List of MSSQL instances discovered by the discovery script.';
comment on column mssql_discovery_list.server_name is 'Name of the server hosting the MSSQL instance.';
comment on column mssql_discovery_list.instance_name is 'Name of the MSSQL instance';
comment on column mssql_discovery_list.port is 'TCP port the instance listens on.';
comment on column mssql_discovery_list.envt_short_code is 'Environment the row applies to (e.g. PRD, DEV, TST).';
comment on column mssql_discovery_list.license_type is 'Licensing type applied to this host/instance.';
comment on column mssql_discovery_list.collect_active is 'Flag indicating whether this entry is actively collected (1) or disabled (0).';
comment on column mssql_discovery_list.discovery_date is 'Timestamp at which this row was discovered.';
comment on column mssql_discovery_list.last_update is 'Timestamp at which this row was last updated.';

-- ============================================================
-- postgres_discovery_list
-- ============================================================
create table postgres_discovery_list (
   server_name       varchar2(100 char) not null,
   instance_name     varchar2(100 char) not null,
   port              number(5),
   envt_short_code   varchar2(3 char) not null,
   license_type      varchar2(30 char) not null,
   collect_active    number(1) default 0 not null,
   discovery_date    timestamp default systimestamp,
   last_update       timestamp default on null systimestamp not null,
   constraint pk_postgres_discovery_list primary key ( instance_name )
);

comment on table postgres_discovery_list is 'List of PostgreSQL instances discovered by the discovery script.';
comment on column postgres_discovery_list.server_name is 'Name of the server hosting the PostgreSQL instance.';
comment on column postgres_discovery_list.instance_name is 'Name of the PostgreSQL instance';
comment on column postgres_discovery_list.port is 'TCP port the instance listens on.';
comment on column postgres_discovery_list.envt_short_code is 'Environment the row applies to (e.g. PRD, DEV, TST).';
comment on column postgres_discovery_list.license_type is 'Licensing type applied to this host/instance.';
comment on column postgres_discovery_list.collect_active is 'Flag indicating whether this entry is actively collected (1) or disabled (0).';
comment on column postgres_discovery_list.discovery_date is 'Timestamp at which this row was discovered.';
comment on column postgres_discovery_list.last_update is 'Timestamp at which this row was last updated.';

-- ============================================================
-- mysql_discovery_list
-- ============================================================
create table mysql_discovery_list (
   server_name       varchar2(100 char) not null,
   instance_name     varchar2(100 char) not null,
   port              number(5),
   envt_short_code   varchar2(3 char) not null,
   license_type      varchar2(30 char) not null,
   collect_active    number(1) default 0 not null,
   discovery_date    timestamp default systimestamp,
   last_update       timestamp default on null systimestamp not null,
   constraint pk_mysql_discovery_list primary key ( instance_name )
);

comment on table mysql_discovery_list is 'List of MySQL instances discovered by the discovery script.';
comment on column mysql_discovery_list.server_name is 'Name of the server hosting the MySQL instance.';
comment on column mysql_discovery_list.instance_name is 'Name of the MySQL instance';
comment on column mysql_discovery_list.port is 'TCP port the instance listens on.';
comment on column mysql_discovery_list.envt_short_code is 'Environment the row applies to (e.g. PRD, DEV, TST).';
comment on column mysql_discovery_list.license_type is 'Licensing type applied to this host/instance.';
comment on column mysql_discovery_list.collect_active is 'Flag indicating whether this entry is actively collected (1) or disabled (0).';
comment on column mysql_discovery_list.discovery_date is 'Timestamp at which this row was discovered.';
comment on column mysql_discovery_list.last_update is 'Timestamp at which this row was last updated.';

-- ============================================================
-- licence_types
-- ============================================================
create table licence_types (
   license_type varchar2(30 char) not null,
   description  varchar2(256 char),
   scoring_impact number(3) default 0 not null,
   constraint pk_licence_types primary key ( license_type )
);

comment on table licence_types is 'Reference list of license types and their impact on scoring/compliance.';
comment on column licence_types.license_type is 'Unique identifier of the license type.';
comment on column licence_types.description is 'Description of the license type.';
comment on column licence_types.scoring_impact is 'Impact of the license type on scoring/compliance (0 = no impact, higher = more impact).';
