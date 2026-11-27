-- ============================================================================
-- V__003_app_model_reference_data.sql
-- ----------------------------------------------------------------------------
-- Seed data for the scoring reference tables created in V__002:
--   ref_control          - catalog of compliance/quality controls
--   ref_scoring_weight   - weight of each check category within a scoring domain
--   ref_threshold        - warning/critical thresholds for metric-based controls
--
-- MSSQL SECURITY weights are transcribed verbatim from the legacy scoring script
-- (mssql_scoring_data.sql, removed in 2.0.0, see git history): configoptions=35,
-- logins/registryinfo/sqlserveraudit=10, the other seven categories=5 (sum=100).
--
-- ORACLE SECURITY weights are INITIAL PROPOSALS (no authoritative weighting
-- existed for Oracle; the legacy oracle_security_scoring only stored per-category
-- flags). They sum to 100 and are meant to be tuned.
-- ============================================================================


-- ============================================================
-- ref_control
-- ============================================================

-- MSSQL security controls (score_domain = SECURITY)
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_CONFIGOPTIONS', 'MSSQL', 'SECURITY', 'configoptions', 'INSTANCE', 'sp_configure security options', 'HIGH' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_LOGINS', 'MSSQL', 'SECURITY', 'logins', 'INSTANCE', 'sysadmin / high-privilege logins', 'HIGH' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_REGISTRYINFO', 'MSSQL', 'SECURITY', 'registryinfo', 'INSTANCE', 'Registry security configuration', 'MEDIUM' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_SQLSERVERAUDIT', 'MSSQL', 'SECURITY', 'sqlserveraudit', 'INSTANCE', 'SQL Server Audit specifications', 'MEDIUM' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_DBPROPERTIES', 'MSSQL', 'SECURITY', 'dbproperties', 'INSTANCE', 'Database properties (AUTO_CLOSE, TRUSTWORTHY, Query Store)', 'MEDIUM' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_AUDITLEVEL', 'MSSQL', 'SECURITY', 'auditlevel', 'INSTANCE', 'Server audit level', 'MEDIUM' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_ENCRYPTION', 'MSSQL', 'SECURITY', 'encryption', 'INSTANCE', 'Transparent Data Encryption keys', 'MEDIUM' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_GROUPS', 'MSSQL', 'SECURITY', 'groups', 'INSTANCE', 'Local Windows group permissions', 'MEDIUM' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_GUESTCONNECT', 'MSSQL', 'SECURITY', 'guestconnect', 'INSTANCE', 'Guest CONNECT permission', 'MEDIUM' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_ORPHANEDUSERS', 'MSSQL', 'SECURITY', 'orphanedusers', 'INSTANCE', 'Orphaned database users', 'LOW' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_PUBLICPERMISSION', 'MSSQL', 'SECURITY', 'publicpermission', 'INSTANCE', 'Public role permissions', 'MEDIUM' );

-- Oracle security controls (score_domain = SECURITY)
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_ADMIN_HIGH_PRIVS', 'ORACLE', 'SECURITY', 'admin_high_privs', 'INSTANCE', 'High administrative privileges (pwfile)', 'HIGH' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_AUDIT_ENABLE', 'ORACLE', 'SECURITY', 'audit_enable', 'DATABASE', 'Audit policy activation', 'MEDIUM' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_DEFAULT_PROFILE', 'ORACLE', 'SECURITY', 'default_profile', 'DATABASE', 'Users on DEFAULT profile', 'LOW' );
-- INSTANCE, not DATABASE: in CDB mode the collect emits the literal 'CONTAINER'
-- instead of the PDB name (get_info_oracle_security.sh:151), so the finding can
-- only be keyed at instance grain. A DATABASE roll-up grain would silently drop
-- every finding of this control, since load_compliance discards the rows whose
-- entity resolves to NULL at the control's grain.
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_DEFAULT_USER_PWD', 'ORACLE', 'SECURITY', 'default_user_pwd', 'INSTANCE', 'Accounts with default passwords', 'HIGH' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_HIGH_ROLE_PRIVS', 'ORACLE', 'SECURITY', 'high_role_privs', 'DATABASE', 'High-privilege roles granted', 'HIGH' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_HIGH_SYS_PRIVS', 'ORACLE', 'SECURITY', 'high_sys_privs', 'DATABASE', 'High-privilege system privileges', 'HIGH' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_HIGH_TAB_PRIVS', 'ORACLE', 'SECURITY', 'high_tab_privs', 'DATABASE', 'High-privilege table privileges (PUBLIC)', 'MEDIUM' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_SECURITY_PARAMETER', 'ORACLE', 'SECURITY', 'security_parameter', 'INSTANCE', 'Security-relevant init parameters', 'MEDIUM' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_SECURITY_PROFILE', 'ORACLE', 'SECURITY', 'security_profile', 'DATABASE', 'Profile resource limits', 'LOW' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_ENCRYPTED_TABLESPACE', 'ORACLE', 'SECURITY', 'encrypted_tablespace', 'DATABASE', 'Tablespace encryption', 'MEDIUM' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_NETWORK_ENCRYPTION', 'ORACLE', 'SECURITY', 'network_encryption', 'INSTANCE', 'SQL*Net network encryption', 'MEDIUM' );
-- The twelfth collected security table (oracle_sec_usermig_tbl_exist) had no control
-- at all. It shares the default_user_pwd category on purpose: both judge the strength
-- of stored credentials, and reusing the category keeps ORACLE SECURITY summing to 100
-- without re-tuning the ten weights already agreed.
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_USERMIG_TABLE', 'ORACLE', 'SECURITY', 'default_user_pwd', 'DATABASE', 'Residual SYS.USER$MIG password hashes', 'HIGH' );

-- Backup freshness controls (score_domain = BACKUP)
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_BACKUP_FRESHNESS', 'MSSQL', 'BACKUP', 'backup_freshness', 'DATABASE', 'Backup freshness vs SLA', 'HIGH' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   -- INSTANCE, not DATABASE: RMAN backs up the whole container (see fact_instance_backup).
   values ( 'ORACLE_BACKUP_FRESHNESS', 'ORACLE', 'BACKUP', 'backup_freshness', 'INSTANCE', 'Backup freshness vs SLA', 'HIGH' );

-- Capacity saturation controls (score_domain = CAPACITY)
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_CAPACITY_SATURATION', 'MSSQL', 'CAPACITY', 'capacity_saturation', 'STORAGE', 'Storage saturation vs threshold', 'MEDIUM' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_CAPACITY_SATURATION', 'ORACLE', 'CAPACITY', 'capacity_saturation', 'STORAGE', 'Tablespace saturation vs threshold', 'MEDIUM' );

-- Lifecycle / out-of-support controls (score_domain = LIFECYCLE)
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_OUT_OF_SUPPORT', 'MSSQL', 'LIFECYCLE', 'out_of_support', 'INSTANCE', 'Engine version end-of-support', 'HIGH' );
-- Its own control rather than a second rule under MSSQL_OUT_OF_SUPPORT: for a
-- non-SECURITY domain load_compliance reports min(observed_value) across the
-- control's rules, so two rules sharing one control would report one verdict and
-- hide the other.
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_PATCH_LEVEL', 'MSSQL', 'LIFECYCLE', 'patch_level', 'INSTANCE', 'Engine cumulative update level', 'MEDIUM' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_OUT_OF_SUPPORT', 'ORACLE', 'LIFECYCLE', 'out_of_support', 'INSTANCE', 'Engine version end-of-support', 'HIGH' );

-- Licensing controls (score_domain = LICENSING)
-- Oracle splits current and past option usage into two controls, so that each
-- category can carry its own weight (70/30, see ref_scoring_weight): a past
-- usage is still billed at audit, but it no longer grows and weighs less.
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_LICENSING_LMS', 'ORACLE', 'LICENSING', 'licensing', 'INSTANCE', 'Oracle feature usage (LMS) licensing', 'HIGH' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_LICENSING_LMS_PAST', 'ORACLE', 'LICENSING', 'licensing_past', 'INSTANCE', 'Oracle feature usage (LMS) licensing, past usage', 'MEDIUM' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_LICENSING', 'MSSQL', 'LICENSING', 'licensing', 'INSTANCE', 'MSSQL edition/licensing', 'MEDIUM' );


-- PostgreSQL controls
--
-- One control per family of verdict, per the rule stated at the top of this
-- section: two rules under one control would report a single verdict and hide
-- the other. That is why WAL archiving and archive freshness are two controls
-- and not two rules -- "archiving is off" would otherwise mask "the last
-- segment is three days old", which is the more actionable of the two.
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'POSTGRES_SECURITY_PARAMETER', 'POSTGRES', 'SECURITY', 'security_parameter', 'INSTANCE', 'PostgreSQL security settings', 'HIGH' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'POSTGRES_ROLE_PRIVS', 'POSTGRES', 'SECURITY', 'role_privs', 'INSTANCE', 'Privileged role attributes', 'HIGH' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'POSTGRES_PREDEF_ROLE_MEMBER', 'POSTGRES', 'SECURITY', 'predef_role_member', 'INSTANCE', 'Membership of sensitive predefined roles', 'HIGH' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'POSTGRES_HBA_AUTH', 'POSTGRES', 'SECURITY', 'hba_auth', 'INSTANCE', 'Host-based authentication methods', 'CRITICAL' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'POSTGRES_PUBLIC_PRIVS', 'POSTGRES', 'SECURITY', 'public_privs', 'DATABASE', 'Privileges granted to PUBLIC', 'MEDIUM' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'POSTGRES_WAL_ARCHIVING', 'POSTGRES', 'BACKUP', 'wal_archiving', 'INSTANCE', 'WAL archiving enabled', 'HIGH' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'POSTGRES_BACKUP_FRESHNESS', 'POSTGRES', 'BACKUP', 'backup_freshness', 'INSTANCE', 'WAL archive freshness', 'HIGH' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'POSTGRES_OUT_OF_SUPPORT', 'POSTGRES', 'LIFECYCLE', 'out_of_support', 'INSTANCE', 'Engine version end-of-support', 'HIGH' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'POSTGRES_CAPACITY_SATURATION', 'POSTGRES', 'CAPACITY', 'capacity_saturation', 'DATABASE', 'Transaction id wraparound headroom', 'HIGH' );


-- ============================================================
-- ref_control_rule
-- ------------------------------------------------------------
-- One row per individual norm, so that a documented exception can designate
-- exactly what it derogates from. Predicates are transcribed verbatim from the
-- expressions of pkg_dbinv_scoring.load_findings, which itself transcribes the
-- legacy mssql_scoring_data.sql.
--
-- entity_type here is the EVALUATION grain (what fact_control_finding rows key
-- on); the roll-up grain into fact_compliance stays ref_control.entity_type.
--
-- Scope conditions stated in `description` are part of the norm and are NOT
-- exceptions: they must not appear in the list the RSSI team reviews.
-- ============================================================

-- MSSQL configoptions: one rule per sp_configure option collected by
-- mssql_getconfigoptions.sql (the collect query whitelists exactly these names).
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_CFG_ADHOC_DIST_QUERIES', 'MSSQL_CONFIGOPTIONS', 'INSTANCE', '*',
            'Ad Hoc Distributed Queries must be disabled', 'sp_configure ''Ad Hoc Distributed Queries'' run_value must be 0.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_CFG_CLR_ENABLED', 'MSSQL_CONFIGOPTIONS', 'INSTANCE', '*',
            'CLR integration must be disabled', 'sp_configure ''clr enabled'' run_value must be 0.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_CFG_CROSS_DB_CHAINING', 'MSSQL_CONFIGOPTIONS', 'INSTANCE', '*',
            'Cross DB ownership chaining must be disabled', 'sp_configure ''cross db ownership chaining'' run_value must be 0.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_CFG_DATABASE_MAIL_XPS', 'MSSQL_CONFIGOPTIONS', 'INSTANCE', '*',
            'Database Mail XPs must be disabled', 'sp_configure ''Database Mail XPs'' run_value must be 0.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_CFG_OLE_AUTOMATION', 'MSSQL_CONFIGOPTIONS', 'INSTANCE', '*',
            'OLE Automation Procedures must be disabled', 'sp_configure ''Ole Automation Procedures'' run_value must be 0.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_CFG_REMOTE_ACCESS', 'MSSQL_CONFIGOPTIONS', 'INSTANCE', '*',
            'Remote access must be disabled', 'sp_configure ''remote access'' run_value must be 0.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_CFG_REMOTE_ADMIN_CONN', 'MSSQL_CONFIGOPTIONS', 'INSTANCE', '*',
            'Remote admin connections must be disabled', 'sp_configure ''remote admin connections'' run_value must be 0. Only collected on non-clustered instances.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_CFG_SCAN_STARTUP_PROCS', 'MSSQL_CONFIGOPTIONS', 'INSTANCE', '*',
            'Scan for startup procs must be disabled', 'sp_configure ''scan for startup procs'' run_value must be 0.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_CFG_XP_CMDSHELL', 'MSSQL_CONFIGOPTIONS', 'INSTANCE', '*',
            'xp_cmdshell must be disabled', 'sp_configure ''xp_cmdshell'' run_value must be 0.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_CFG_DEFAULT_TRACE', 'MSSQL_CONFIGOPTIONS', 'INSTANCE', '*',
            'Default trace must be enabled', 'sp_configure ''default trace enabled'' run_value must be 1.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_CFG_CLR_STRICT_SECURITY', 'MSSQL_CONFIGOPTIONS', 'INSTANCE', '*',
            'CLR strict security must be enabled', 'sp_configure ''clr strict security'' run_value must be 1.', 'HIGH' );

-- MSSQL registryinfo: one rule per registry value collected by mssql_getregistryinfo.sql.
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_REG_HIDE_INSTANCE', 'MSSQL_REGISTRYINFO', 'INSTANCE', '*',
            'Instance must be hidden', 'Registry HideInstance must be 1.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_REG_FORCE_ENCRYPTION', 'MSSQL_REGISTRYINFO', 'INSTANCE', '*',
            'Connection encryption must be forced', 'Registry ForceEncryption must be 1.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_REG_NUM_ERRORLOG_FILES', 'MSSQL_REGISTRYINFO', 'INSTANCE', '*',
            'Enough error log files must be retained', 'Registry NumErrorLogs must be greater than 12.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_REG_TCP_PORT', 'MSSQL_REGISTRYINFO', 'INSTANCE', '*',
            'Instance must listen on the standard TCP port', 'Registry TcpPort must be 1433.', 'MEDIUM' );

-- MSSQL database properties (evaluated per database, rolled up to the instance).
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_DBPROP_AUTO_CLOSE_OFF', 'MSSQL_DBPROPERTIES', 'DATABASE', '*',
            'AUTO_CLOSE must be off', 'is_auto_close_on must be 0.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_DBPROP_TRUSTWORTHY_OFF', 'MSSQL_DBPROPERTIES', 'DATABASE', '*',
            'TRUSTWORTHY must be off', 'is_trustworthy_on must be 0 on every database but msdb. Scope: msdb ships with TRUSTWORTHY on and Microsoft requires it (SQL Agent, Database Mail), so it is compliant at 1, and at 0 too (unusual, not a security risk).', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_DBPROP_QUERY_STORE_ON', 'MSSQL_DBPROPERTIES', 'DATABASE', '*',
            'Query Store must be on (READ_WRITE)', 'From SQL Server 2016, Query Store must be READ_WRITE on every user database: READ_ONLY means it is full and no longer captures, OFF and ERROR record nothing. Scope: system databases, offline or non READ_WRITE databases (AG secondaries, read-only) and engines before 2016 are not judged.', 'LOW' );

-- MSSQL logins. The two rules partition the population on is_sysadmin so that
-- together they reproduce the legacy ordered CASE exactly: a sysadmin login is
-- judged on password expiration only, a regular login on password policy only.
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_LOGIN_SYSADMIN_EXPIRATION', 'MSSQL_LOGINS', 'INSTANCE', 'login name',
            'Sysadmin logins must have password expiration checked', 'is_expiration_checked must be 1 for sysadmin logins. Scope: sysadmin logins only; sa and monitoring are exempt (service accounts of the inventory itself).', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_LOGIN_POLICY_CHECKED', 'MSSQL_LOGINS', 'INSTANCE', 'login name',
            'Logins must have password policy checked', 'is_policy_checked must be 1. Scope: non-sysadmin logins only; sa and monitoring are exempt.', 'HIGH' );
-- The built-in sysadmin account, identified by its sid (0x01) rather than by its
-- name, so the check survives the rename it is asking for. Attached to
-- MSSQL_LOGINS rather than given its own control: it is a login rule, and a
-- SECURITY control reports a deviation count, so several rules coexist under one
-- control without hiding each other. Reusing the category also leaves the eleven
-- MSSQL SECURITY weights summing to 100 untouched.
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_SA_RENAMED', 'MSSQL_LOGINS', 'INSTANCE', '*',
            'The built-in sysadmin account must be renamed', 'The principal holding sid 0x01 must no longer be named ''sa'': the default name is half of a guessable credential.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_SA_DISABLED', 'MSSQL_LOGINS', 'INSTANCE', '*',
            'The built-in sysadmin account must be disabled', 'The principal holding sid 0x01 must have is_disabled = 1. Applies whatever the account was renamed to.', 'HIGH' );
-- Authentication mode. Also under MSSQL_LOGINS: it decides whether SQL logins
-- are an attack surface at all, which is what every other rule of this control
-- is about. Giving it its own control would mean re-tuning the eleven MSSQL
-- SECURITY weights, which are transcribed verbatim from the legacy script.
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_AUTH_WINDOWS_ONLY', 'MSSQL_LOGINS', 'INSTANCE', '*',
            'Authentication mode recorded (mixed mode accepted)', 'SERVERPROPERTY(''IsIntegratedSecurityOnly'') is recorded for every instance. The CHL norm accepts mixed mode, so the rule is always compliant: it keeps the proof the mode was checked. CIS asks for Windows authentication only.', 'HIGH' );

-- MSSQL audit level / SQL Server Audit.
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_AUDIT_LEVEL_LOGIN_FAILURES', 'MSSQL_AUDITLEVEL', 'INSTANCE', '*',
            'Login auditing must record at least failures', 'Server audit level must be All or Failed.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_SRVAUDIT_ACTION_GROUP_ON', 'MSSQL_SQLSERVERAUDIT', 'INSTANCE', 'audit action group',
            'Expected audit action groups must be enabled', 'The audit action group must be one of AUDIT_CHANGE_GROUP, FAILED_LOGIN_GROUP, SUCCESSFUL_LOGIN_GROUP, with both the audit and its specification enabled.', 'MEDIUM' );

-- MSSQL encryption (evaluated per database, rolled up to the instance).
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_ENC_STRONG_ALGORITHM', 'MSSQL_ENCRYPTION', 'DATABASE', 'key name',
            'Encryption keys must use a strong algorithm', 'algorithm_desc must be TRIPLE_DES, AES_128, AES_192 or AES_256. Scope: system databases (master, model, msdb, tempdb) and Express/Developer editions are exempt.', 'MEDIUM' );

-- MSSQL local Windows groups, guest access, orphaned users, public role.
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_GROUP_NO_LOCAL_PERMISSION', 'MSSQL_GROUPS', 'INSTANCE', 'local group name',
            'No local Windows group must hold server permissions', 'Compliant only when the collect reports the NoGroup sentinel (compared case-insensitively), i.e. no local group holds a permission.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_GUEST_NO_CONNECT', 'MSSQL_GUESTCONNECT', 'DATABASE', 'permission name',
            'Guest must not hold CONNECT', 'Compliant only when the collect reports the ''no_permission'' sentinel for both permission and state.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_NO_ORPHANED_USER', 'MSSQL_ORPHANEDUSERS', 'DATABASE', 'user name',
            'No orphaned database user must exist', 'Compliant only when the collect reports the ''NoOrphanedUser'' sentinel.', 'LOW' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_PUBLIC_DEFAULT_PERMISSION', 'MSSQL_PUBLICPERMISSION', 'DATABASE', 'user name / permission',
            'Public role must keep only its default permissions', 'Compliant only when the collect reports the ''OnlyDefaultPermission'' sentinel for both permission and state.', 'MEDIUM' );

-- ------------------------------------------------------------
-- ORACLE security rules
-- ------------------------------------------------------------
-- Expected values are those of the CIS Oracle Database Benchmark section 2
-- (initialisation parameters) and section 3 (profiles). They are transcribed
-- here rather than in ref_threshold: ref_threshold carries measured metrics
-- that drift (pct_used, hours_since_backup), whereas these are fixed norms,
-- exactly like the MSSQL sp_configure expected values above.
--
-- Two scope conditions run through the whole block and are part of the NORM,
-- not derogations:
--   * Oracle-maintained accounts (oracle_maintained = 'Y' in
--     oracle_sec_default_profile) are out of scope of the privilege and profile
--     rules: SYS, SYSTEM, DBSNMP et al. hold those privileges by construction,
--     and listing them would bury the real deviations.
--   * a profile limit collected as 'DEFAULT' is inherited from the DEFAULT
--     profile, which is itself evaluated; judging it twice would double-count.

-- Initialisation parameters: one rule per parameter collected by
-- get_info_oracle_security.sh, which whitelists exactly these names.
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRM_O7_DICT_ACCESS', 'ORACLE_SECURITY_PARAMETER', 'INSTANCE', '*',
            'O7_DICTIONARY_ACCESSIBILITY must be FALSE', 'Setting it TRUE grants SELECT ANY TABLE access to the data dictionary.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRM_REMOTE_OS_AUTHENT', 'ORACLE_SECURITY_PARAMETER', 'INSTANCE', '*',
            'REMOTE_OS_AUTHENT must be FALSE', 'Allows a remote client to assert its own OS identity to authenticate.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRM_REMOTE_OS_ROLES', 'ORACLE_SECURITY_PARAMETER', 'INSTANCE', '*',
            'REMOTE_OS_ROLES must be FALSE', 'Lets a remote OS grant roles, bypassing database role management.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRM_UTL_FILE_DIR', 'ORACLE_SECURITY_PARAMETER', 'INSTANCE', '*',
            'UTL_FILE_DIR must be empty', 'A non-empty value exposes server file systems through UTL_FILE.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRM_OS_ROLES', 'ORACLE_SECURITY_PARAMETER', 'INSTANCE', '*',
            'OS_ROLES must be FALSE', 'Delegates role management to the operating system.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRM_AUDIT_TRAIL', 'ORACLE_SECURITY_PARAMETER', 'INSTANCE', '*',
            'AUDIT_TRAIL must not be NONE', 'Any destination (DB, DB,EXTENDED, OS, XML) is accepted; NONE disables traditional auditing entirely. On a database in pure Unified Auditing the engine ignores it: recorded as compliant, not applicable.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRM_AUDIT_SYS_OPERATIONS', 'ORACLE_SECURITY_PARAMETER', 'INSTANCE', '*',
            'AUDIT_SYS_OPERATIONS must be TRUE', 'Without it, actions performed as SYSDBA are not audited. Deprecated from 21c. On a database in pure Unified Auditing the engine ignores it: recorded as compliant, not applicable.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRM_UNIFIED_AUDITING', 'ORACLE_SECURITY_PARAMETER', 'INSTANCE', '*',
            'Unified Auditing must be enabled', 'v$option ''Unified Auditing'' must be TRUE; it is the prerequisite for the ORA_CIS_RECOMMENDATIONS policy.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRM_RESOURCE_LIMIT', 'ORACLE_SECURITY_PARAMETER', 'INSTANCE', '*',
            'RESOURCE_LIMIT must be TRUE', 'When FALSE, every profile resource limit is silently ignored, which voids the profile rules below.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRM_SEC_CASE_SENSITIVE', 'ORACLE_SECURITY_PARAMETER', 'INSTANCE', '*',
            'SEC_CASE_SENSITIVE_LOGON must be TRUE', 'FALSE forces the weak 10g password verifier. Deprecated from 21c, where the parameter is no longer collected.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRM_SEC_MAX_FAILED_LOGIN', 'ORACLE_SECURITY_PARAMETER', 'INSTANCE', '*',
            'SEC_MAX_FAILED_LOGIN_ATTEMPTS must be at most 3', 'Caps failed authentication attempts per connection before the server drops it.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRM_SEC_BANNER', 'ORACLE_SECURITY_PARAMETER', 'INSTANCE', '*',
            'SEC_RETURN_SERVER_RELEASE_BANNER must be FALSE', 'TRUE discloses the exact server version to unauthenticated clients.', 'LOW' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRM_SEC_PROTO_ERR_TRACE', 'ORACLE_SECURITY_PARAMETER', 'INSTANCE', '*',
            'SEC_PROTOCOL_ERROR_TRACE_ACTION must be LOG or TRACE', 'NONE leaves malformed-packet attacks untraced.', 'LOW' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRM_SEC_PROTO_ERR_FURTHER', 'ORACLE_SECURITY_PARAMETER', 'INSTANCE', '*',
            'SEC_PROTOCOL_ERROR_FURTHER_ACTION must not be CONTINUE', 'CONTINUE keeps serving a client sending malformed packets; DROP or DELAY is expected.', 'LOW' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRM_SYS_LOGON_DELAY', 'ORACLE_SECURITY_PARAMETER', 'INSTANCE', '*',
            '_SYS_LOGON_DELAY must be 4', 'Delay inserted after a failed SYS logon; the collect normalises it to 4 (set) or 0 (not set).', 'LOW' );
-- Collected, deliberately not scored: no authoritative norm exists for
-- PDB_OS_CREDENTIAL, and fabricating one here would be indistinguishable from a
-- real CIS requirement. Catalogued at active = 0 so the gap is visible rather
-- than silent, and can be turned on the day the policy is settled.
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity, active )
   values ( 'ORACLE_PRM_PDB_OS_CREDENTIAL', 'ORACLE_SECURITY_PARAMETER', 'INSTANCE', '*',
            'PDB_OS_CREDENTIAL norm not settled', 'Parameter collected but not judged: the expected value depends on whether PDB OS operations are delegated, which the inventory does not know.', 'LOW', 0 );

-- Profile resource limits: one rule per resource_name of the CIS section 3.
-- Limits collected as 'DEFAULT' are inherited and skipped (see scope above).
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRF_FAILED_LOGIN_ATTEMPTS', 'ORACLE_SECURITY_PROFILE', 'DATABASE', 'profile / resource',
            'FAILED_LOGIN_ATTEMPTS must be at most 5', 'UNLIMITED is non-compliant: it disables account lockout after repeated failures.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRF_PASSWORD_LIFE_TIME', 'ORACLE_SECURITY_PROFILE', 'DATABASE', 'profile / resource',
            'PASSWORD_LIFE_TIME must be at most 90 days', 'UNLIMITED is non-compliant: the password never expires. CHL standard: allowed for the service, system and monitoring profiles (C##SERVICE_PROFILE, C##SYSTEM_PROFILE, C##MONITORING, CHL_SERVICE_PROFILE, CHL_SYSTEM_PROFILE, MONITORING).', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRF_PASSWORD_LOCK_TIME', 'ORACLE_SECURITY_PROFILE', 'DATABASE', 'profile / resource',
            'PASSWORD_LOCK_TIME must be at least 1 day', 'UNLIMITED is compliant: the account stays locked until an administrator releases it.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRF_PASSWORD_GRACE_TIME', 'ORACLE_SECURITY_PROFILE', 'DATABASE', 'profile / resource',
            'PASSWORD_GRACE_TIME must be at most 7 days', 'UNLIMITED is non-compliant: an expired password can be used indefinitely.', 'LOW' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRF_PASSWORD_REUSE_MAX', 'ORACLE_SECURITY_PROFILE', 'DATABASE', 'profile / resource',
            'PASSWORD_REUSE_MAX must be at least 20', 'UNLIMITED is compliant: a password can never be reused.', 'LOW' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRF_PASSWORD_REUSE_TIME', 'ORACLE_SECURITY_PROFILE', 'DATABASE', 'profile / resource',
            'PASSWORD_REUSE_TIME must be at least 365 days', 'UNLIMITED is compliant: a password can never be reused.', 'LOW' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRF_PASSWORD_VERIFY_FUNCTION', 'ORACLE_SECURITY_PROFILE', 'DATABASE', 'profile / resource',
            'PASSWORD_VERIFY_FUNCTION must be set', 'NULL means no complexity check is applied when a password is set.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRF_SESSIONS_PER_USER', 'ORACLE_SECURITY_PROFILE', 'DATABASE', 'profile / resource',
            'SESSIONS_PER_USER must be at most 10', 'UNLIMITED is non-compliant: a single account can exhaust the session pool.', 'LOW' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRF_INACTIVE_ACCOUNT_TIME', 'ORACLE_SECURITY_PROFILE', 'DATABASE', 'profile / resource',
            'INACTIVE_ACCOUNT_TIME must be at most 120 days', 'UNLIMITED is non-compliant: a dormant account is never locked automatically.', 'LOW' );

-- Privilege families: one rule each rather than one per privilege. item_key
-- already carries the grantee and the privilege, so a derogation stays as
-- precise as a per-privilege rule would make it, without a 60-row catalog.
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_HIGH_SYS_PRIVS_GRANT', 'ORACLE_HIGH_SYS_PRIVS', 'DATABASE', 'grantee / privilege',
            'No account may hold a high-privilege system privilege', 'Covers the CIS list collected by get_info_oracle_security.sh (SELECT ANY DICTIONARY, BECOME USER, GRANT ANY ROLE, CREATE EXTERNAL JOB and the rest). Scope: Oracle-maintained accounts are exempt, and so are the roles Oracle ships with these privileges (DBA, OGG*CAPTURE, AVTUNE_PKG_ROLE, *IMP_FULL_DATABASE, *EXP_FULL_DATABASE, AUDIT_ADMIN, AUDIT_SYSTEM, SCHEDULER_ADMIN, EM_EXPRESS_ALL, EM_EXPRESS_BASIC, SYSUMF_ROLE, OEM_MONITOR, GSMUSER_ROLE, GSMADMIN_ROLE): the norm judges the accounts.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_HIGH_ROLE_PRIVS_GRANT', 'ORACLE_HIGH_ROLE_PRIVS', 'DATABASE', 'grantee / role',
            'No account may hold DBA, a catalog role or a GSM role', 'Covers DBA, DELETE_CATALOG_ROLE, EXECUTE_CATALOG_ROLE, GSMUSER_ROLE and GSMADMIN_ROLE. SELECT_CATALOG_ROLE is accepted by the CHL norm: each grant is recorded as compliant, naming its holder. Scope: Oracle-maintained accounts and the roles Oracle ships (same list as ORACLE_HIGH_SYS_PRIVS_GRANT) are exempt; a custom role holding a GSM role is not.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_HIGH_TAB_PRIVS_PUBLIC', 'ORACLE_HIGH_TAB_PRIVS', 'DATABASE', 'grantee / package',
            'PUBLIC must not hold EXECUTE on sensitive packages', 'Covers the CIS package list (UTL_FILE, UTL_SMTP, UTL_HTTP, DBMS_SYS_SQL, DBMS_FILE_TRANSFER and the rest) plus INHERIT PRIVILEGES granted to PUBLIC. No account exemption applies: the grantee is PUBLIC by construction.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_ADMIN_PWFILE_SYS_ONLY', 'ORACLE_ADMIN_HIGH_PRIVS', 'INSTANCE', 'username',
            'Only SYS may appear in the password file', 'Every other v$pwfile_users entry can connect AS SYSDBA remotely and bypass database authentication.', 'HIGH' );

-- Accounts and credentials.
-- INSTANCE grain, not DATABASE: in CDB mode the collect emits the literal
-- 'CONTAINER' instead of the real PDB name (get_info_oracle_security.sh:151),
-- so the finer grain is not resolvable until the collect is fixed.
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_NO_DEFAULT_PASSWORD', 'ORACLE_DEFAULT_USER_PWD', 'INSTANCE', 'username',
            'No account may keep its default password', 'Any DBA_USERS_WITH_DEFPWD entry is a deviation, Oracle-maintained or not: a default password is guessable whoever owns the account.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_NO_DEFAULT_PROFILE', 'ORACLE_DEFAULT_PROFILE', 'DATABASE', 'username',
            'No account may sit on the DEFAULT profile', 'Application accounts must use a profile carrying explicit password and resource limits. Scope: Oracle-maintained accounts are exempt.', 'LOW' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_NO_USERMIG_TABLE', 'ORACLE_USERMIG_TABLE', 'DATABASE', '*',
            'SYS.USER$MIG must not exist', 'A leftover migration table holding legacy 10g DES password hashes, brute-forceable in parallel with the modern verifier.', 'HIGH' );

-- Audit, encryption at rest and in transit.
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_AUDIT_CIS_POLICY_ON', 'ORACLE_AUDIT_ENABLE', 'DATABASE', 'policy name',
            'The CIS audit policy must be enabled', 'ORA_CIS_RECOMMENDATIONS must be enabled from 12c. On 11g the collect falls back to the classic audit options, each judged on the same rule.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_TABLESPACE_ENCRYPTED', 'ORACLE_ENCRYPTED_TABLESPACE', 'DATABASE', 'tablespace name',
            'User tablespaces must be encrypted', 'Scope: SYSTEM, SYSAUX, temporary and undo tablespaces are engine-managed and exempt.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_NETWORK_ENCRYPTION_ON', 'ORACLE_NETWORK_ENCRYPTION', 'INSTANCE', '*',
            'SQL*Net traffic must be encrypted', 'The collect only emits a row when the session reports an encryption service adapter; a collected instance with no such row is non-compliant.', 'MEDIUM' );
-- The two rules below read SYSTEM.HIST_SESSION_ENCRYPTION, which the DBA team
-- installs only on a database that cannot go to REQUIRED (setup/targets/oracle/
-- ORACLE_network_encryption_audit.sql). Same control, so the category weight is
-- unchanged: the instance is compliant on network encryption only if all three
-- rules are.
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_NETWORK_ENCRYPTION_REQUIRED', 'ORACLE_NETWORK_ENCRYPTION', 'INSTANCE', '*',
            'SQL*Net encryption must be REQUIRED, not REQUESTED', 'The CHL target is SQLNET.ENCRYPTION_SERVER=REQUIRED. A database left in REQUESTED is declared by the presence of the unencrypted-client audit table, and is a deviation unless covered by an approved derogation, even when no client is recorded. SQL cannot read sqlnet.ora: a database in REQUESTED without the audit table is not detected by this rule.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_NETWORK_UNENCRYPTED_CLIENT', 'ORACLE_NETWORK_ENCRYPTION', 'INSTANCE', 'container: user@machine (program)',
            'No client may connect without network encryption', 'One deviation per client (user, machine, program) recorded connecting over TCP without an encryption service adapter in the 30 days before the snapshot. Evaluated only where the audit table exists.', 'HIGH' );


-- Oracle option and pack usage (LMS). One finding per option in use, read from
-- Oracle's own usage script (oracle_lms) through v_oracle_lms_usage. A licence
-- the CHL does hold is proven by a derogation whose evidence is the contract
-- (ref_exception_document.doc_kind = LICENSE), not by a rule exemption.
-- Scope of the norm: instances whose perimeter licence has scoring_impact = 0
-- (SAP runtime, FREE, PROVIDER, INCCI) carry their options in that licence and
-- are not judged. No NIS2 domain: licensing is a contractual exposure, not one
-- of the article 21(2) measures, and T_003 exempts the LICENSING domain from
-- that classification.
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_LMS_OPTION_IN_USE', 'ORACLE_LICENSING_LMS', 'INSTANCE', 'option / pack',
            'No unlicensed Oracle option or pack in use', 'CURRENT_USAGE or PAST_OR_CURRENT_USAGE reported by the LMS usage script. Multitenant is recounted from the collected PDBs: up to 3 user PDBs need no licence from 19c, 1 before. On Standard Edition no option can be licensed at all.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_LMS_OPTION_PAST_USE', 'ORACLE_LICENSING_LMS_PAST', 'INSTANCE', 'option / pack',
            'No past usage of an unlicensed Oracle option or pack', 'PAST_USAGE reported by the LMS usage script: the option is no longer used, but an audit still counts it.', 'MEDIUM' );


-- Threshold-based and lifecycle controls: a single rule each, evaluated once per
-- entity. They get a rule so that a derogation is expressible there too (e.g. a
-- tablespace allowed to run above its threshold).
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_STORAGE_PCT_USED', 'MSSQL_CAPACITY_SATURATION', 'STORAGE', '*',
            'Storage usage must stay below its threshold', 'pct_used must stay below ref_threshold.crit_value for metric pct_used.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_STORAGE_PCT_USED', 'ORACLE_CAPACITY_SATURATION', 'STORAGE', '*',
            'Tablespace usage must stay below its threshold', 'pct_used must stay below ref_threshold.crit_value for metric pct_used.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_BACKUP_FRESHNESS_SLA', 'MSSQL_BACKUP_FRESHNESS', 'DATABASE', '*',
            'Last full backup must be within the SLA', 'hours_since_backup must not exceed ref_threshold.crit_value for metric hours_since_full.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_BACKUP_FRESHNESS_SLA', 'ORACLE_BACKUP_FRESHNESS', 'INSTANCE', '*',
            'Last backup must be within the SLA', 'hours_since_backup must not exceed ref_threshold.crit_value for metric hours_since_backup.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_ENGINE_SUPPORTED', 'MSSQL_OUT_OF_SUPPORT', 'INSTANCE', '*',
            'Engine version must still be supported', 'The major version must not be past its end of support. Extended support (ESU) keeps the instance compliant but is flagged as an exception on the compliance row.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_ENGINE_SUPPORTED', 'ORACLE_OUT_OF_SUPPORT', 'INSTANCE', '*',
            'Engine release must still be supported', 'The major release must not be past its end of support. Extended Support keeps the instance compliant and raises the norm exception flag, as it does on SQL Server. Note the Innovation Releases (18c, 21c) are not eligible for Extended Support at all, so for them the Premier date is the only one there is.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'MSSQL_ENGINE_PATCH_CURRENT', 'MSSQL_PATCH_LEVEL', 'INSTANCE', '*',
            'Engine build must be at the latest published patch level', 'dim_instance.engine_version must be at or above product_support.current_patch_level for its major version, compared on the build and revision numbers. Note: an instance kept on the GDR-only branch reads as behind, because the reference tracks the cumulative-update train.', 'MEDIUM' );



-- ============================================================
-- PostgreSQL rules
-- ------------------------------------------------------------
-- Written strictly against what get_info_postgres_security.sh already collects.
-- Three of the five security collects emit ONLY DEVIATIONS (predefined role
-- memberships, weak pg_hba lines, PUBLIC privileges): a clean cluster produces
-- no row at all, so load_findings_postgres_sec has to manufacture the compliant
-- verdict per instance, the same way load_findings_oracle_sec does. Rules whose
-- collect emits one row per evaluated item (settings, roles) need no such care.
--
-- Two parameters are collected but deliberately NOT judged, and are absent from
-- this list rather than catalogued inactive: log_hostname (CIS argues both ways,
-- and it costs a DNS lookup per connection) and log_min_duration_statement
-- (a performance-tuning knob, not a security norm). They are collected because
-- they are useful context on the instance page.
-- ============================================================

-- Security settings, from pg_settings. One row per instance per parameter, so
-- the compliant verdict falls straight out of the collect.
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'PG_PRM_SSL_ON', 'POSTGRES_SECURITY_PARAMETER', 'INSTANCE', '*',
            'TLS must be enabled on the cluster', 'pg_settings ''ssl'' must be on. Without it no client connection can be encrypted, whatever pg_hba requires.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'PG_PRM_PASSWORD_ENCRYPTION', 'POSTGRES_SECURITY_PARAMETER', 'INSTANCE', '*',
            'Passwords must be stored with SCRAM', 'pg_settings ''password_encryption'' must be scram-sha-256. md5 is the historical default and is considered broken.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'PG_PRM_LOG_CONNECTIONS', 'POSTGRES_SECURITY_PARAMETER', 'INSTANCE', '*',
            'Connections must be logged', 'pg_settings ''log_connections'' must be on.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'PG_PRM_LOG_DISCONNECTIONS', 'POSTGRES_SECURITY_PARAMETER', 'INSTANCE', '*',
            'Disconnections must be logged', 'pg_settings ''log_disconnections'' must be on; without it a session duration cannot be reconstructed.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'PG_PRM_LOG_STATEMENT', 'POSTGRES_SECURITY_PARAMETER', 'INSTANCE', '*',
            'DDL must be logged at least', 'pg_settings ''log_statement'' must be ddl, mod or all. Scope: none is the engine default and is what this rule exists to catch.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'PG_PRM_SSL_MIN_PROTOCOL', 'POSTGRES_SECURITY_PARAMETER', 'INSTANCE', '*',
            'TLS must be at least 1.2', 'pg_settings ''ssl_min_protocol_version'' must be TLSv1.2 or TLSv1.3.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'PG_PRM_PGAUDIT_LOADED', 'POSTGRES_SECURITY_PARAMETER', 'INSTANCE', '*',
            'pgaudit must be loaded', 'pg_settings ''shared_preload_libraries'' must list pgaudit. Native logging records statements, not who was authorised to run them.', 'MEDIUM' );

-- Role attributes, from pg_roles. One row per role, so both verdicts come from
-- the collect. The exemptions below are conditions of the norm, not derogations:
-- the cluster owner and the collector account are privileged by construction, and
-- listing them for review every day would bury the roles that actually matter.
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'PG_ROLE_NO_EXTRA_SUPERUSER', 'POSTGRES_ROLE_PRIVS', 'INSTANCE', 'role name',
            'Superuser must stay exceptional', 'No role may hold rolsuper. Scope: postgres (the cluster owner) and monitoring (the collector) are exempt by construction.', 'CRITICAL' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'PG_ROLE_NO_BYPASSRLS', 'POSTGRES_ROLE_PRIVS', 'INSTANCE', 'role name',
            'Row level security must not be bypassable', 'No role may hold rolbypassrls. Scope: superusers bypass RLS by construction and are judged by PG_ROLE_NO_EXTRA_SUPERUSER instead, not counted twice here.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'PG_ROLE_REPLICATION_LIMITED', 'POSTGRES_ROLE_PRIVS', 'INSTANCE', 'role name',
            'Replication must be granted deliberately', 'No role may hold rolreplication, which allows streaming the entire cluster. Scope: postgres and monitoring are exempt. A legitimate replication account is expected to carry a documented derogation -- that is the point of listing it.', 'HIGH' );

-- Membership of sensitive predefined roles. The collect emits only the rows that
-- exist, so a cluster with no such grant produces nothing at all.
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'PG_MEMBER_NO_SERVER_PROGRAM', 'POSTGRES_PREDEF_ROLE_MEMBER', 'INSTANCE', 'role:member',
            'pg_execute_server_program must have no member', 'Membership grants command execution as the postgres OS user; it is a straight path from database access to the server.', 'CRITICAL' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'PG_MEMBER_NO_SERVER_FILES', 'POSTGRES_PREDEF_ROLE_MEMBER', 'INSTANCE', 'role:member',
            'Server file roles must have no member', 'No role may be a member of pg_read_server_files or pg_write_server_files.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'PG_MEMBER_NO_WRITE_ALL_DATA', 'POSTGRES_PREDEF_ROLE_MEMBER', 'INSTANCE', 'role:member',
            'pg_write_all_data must have no member', 'Membership grants write access to every table of every database, bypassing per-object grants. Scope: pg_monitor and pg_read_all_data are collected but not judged -- the collector itself holds pg_monitor.', 'HIGH' );

-- pg_hba.conf. Only the offending lines are collected.
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'PG_HBA_NO_TRUST', 'POSTGRES_HBA_AUTH', 'INSTANCE', 'pg_hba line number',
            'No trust authentication', 'No pg_hba.conf rule may use auth_method trust, which authenticates anyone who can reach the port.', 'CRITICAL' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'PG_HBA_NO_WEAK_METHOD', 'POSTGRES_HBA_AUTH', 'INSTANCE', 'pg_hba line number',
            'No weak authentication method', 'No pg_hba.conf rule may use md5 or password. Scope: peer and ident on local sockets are not weak and are not judged here.', 'HIGH' );

-- PUBLIC privileges on databases.
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'PG_PUBLIC_NO_CREATE', 'POSTGRES_PUBLIC_PRIVS', 'DATABASE', '*',
            'PUBLIC must not hold CREATE', 'PUBLIC must not be granted CREATE on a database. Scope: CONNECT is the engine default and is not judged -- revoking it is a per-database decision, not a fleet norm.', 'MEDIUM' );

-- Backup, lifecycle and capacity: one rule each, evaluated once per entity.
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'PG_ARCHIVE_MODE_ON', 'POSTGRES_WAL_ARCHIVING', 'INSTANCE', '*',
            'WAL archiving must be enabled', 'archive_mode must be on or always. NOTE: WAL archiving is not a backup -- no pgBackRest/Barman catalogue is collected, so this control attests a necessary condition for point-in-time recovery, never a restorable backup.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'PG_BACKUP_FRESHNESS_SLA', 'POSTGRES_BACKUP_FRESHNESS', 'INSTANCE', '*',
            'Last archived WAL must be within the SLA', 'hours_since_backup, measured from pg_stat_archiver.last_archived_time, must not exceed ref_threshold.crit_value for metric hours_since_archived. Same caveat as PG_ARCHIVE_MODE_ON: this dates a WAL segment, not a backup.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'PG_ENGINE_SUPPORTED', 'POSTGRES_OUT_OF_SUPPORT', 'INSTANCE', '*',
            'Engine major version must still be supported', 'The major version must not be past its community end of support. There is no extended support for PostgreSQL: end_of_ext_support_date is null and the ESU branch of the scoring is inert here.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'PG_XID_WRAPAROUND', 'POSTGRES_CAPACITY_SATURATION', 'DATABASE', '*',
            'Transaction id headroom must stay above its threshold', 'age(datfrozenxid) expressed as a percentage of the 2^31 wraparound ceiling must stay below ref_threshold.crit_value for metric pct_xid_used. This is the only hard capacity ceiling PostgreSQL exposes to SQL: a database has no size limit of its own, and no filesystem size is reachable from the engine.', 'HIGH' );


-- ============================================================
-- ref_benchmark
-- ------------------------------------------------------------
-- version and published_date are left NULL on purpose. The rules below were
-- written against the CIS benchmarks, but WHICH edition the organisation
-- retains as its opposable reference is a decision that has not been taken.
-- Filling a plausible version here would be the one thing that cannot be
-- defended in front of an auditor, since nothing in this repository could back
-- it up. Pin them the day the document is chosen, then work through
-- v_benchmark_mapping_gap.
-- ============================================================
insert into ref_benchmark ( benchmark_code, publisher, title, platform )
   values ( 'CIS_MSSQL', 'CIS', 'CIS Microsoft SQL Server Benchmark', 'MSSQL' );
insert into ref_benchmark ( benchmark_code, publisher, title, platform )
   values ( 'CIS_ORACLE_DB', 'CIS', 'CIS Oracle Database Benchmark', 'ORACLE' );
insert into ref_benchmark ( benchmark_code, publisher, title, platform )
   values ( 'CIS_POSTGRESQL', 'CIS', 'CIS PostgreSQL Benchmark', 'POSTGRES' );


-- ============================================================
-- Rule provenance
-- ------------------------------------------------------------
-- Everything defaults to HOUSE, then the rules transcribed from a benchmark are
-- named explicitly. Written as set-based updates rather than folded into the 70
-- inserts above: the classification is reviewed as a whole, and reading it as a
-- list is what makes a wrong entry visible.
--
-- benchmark_ref (the recommendation identifier) is deliberately NOT populated:
-- CIS renumbers between editions, and an identifier that cannot be checked
-- against the retained document is worse than none. The origin below is a first
-- pass to be confirmed during the same mapping review.
-- ============================================================
update ref_control_rule set origin = 'HOUSE', benchmark_code = null;

update ref_control_rule set origin = 'BENCHMARK', benchmark_code = 'CIS_MSSQL'
 where rule_code in (
   'MSSQL_CFG_ADHOC_DIST_QUERIES', 'MSSQL_CFG_CLR_ENABLED', 'MSSQL_CFG_CLR_STRICT_SECURITY',
   'MSSQL_CFG_CROSS_DB_CHAINING', 'MSSQL_CFG_DATABASE_MAIL_XPS', 'MSSQL_CFG_DEFAULT_TRACE',
   'MSSQL_CFG_OLE_AUTOMATION', 'MSSQL_CFG_REMOTE_ACCESS', 'MSSQL_CFG_REMOTE_ADMIN_CONN',
   'MSSQL_CFG_SCAN_STARTUP_PROCS', 'MSSQL_CFG_XP_CMDSHELL',
   'MSSQL_REG_HIDE_INSTANCE', 'MSSQL_REG_FORCE_ENCRYPTION', 'MSSQL_REG_NUM_ERRORLOG_FILES',
   'MSSQL_DBPROP_AUTO_CLOSE_OFF', 'MSSQL_DBPROP_TRUSTWORTHY_OFF',
   'MSSQL_AUDIT_LEVEL_LOGIN_FAILURES', 'MSSQL_SRVAUDIT_ACTION_GROUP_ON',
   'MSSQL_ENC_STRONG_ALGORITHM', 'MSSQL_GROUP_NO_LOCAL_PERMISSION', 'MSSQL_GUEST_NO_CONNECT',
   'MSSQL_NO_ORPHANED_USER', 'MSSQL_PUBLIC_DEFAULT_PERMISSION',
   'MSSQL_LOGIN_POLICY_CHECKED', 'MSSQL_LOGIN_SYSADMIN_EXPIRATION',
   'MSSQL_SA_RENAMED', 'MSSQL_SA_DISABLED',
   'MSSQL_ENGINE_PATCH_CURRENT' );

update ref_control_rule set origin = 'BENCHMARK', benchmark_code = 'CIS_ORACLE_DB'
 where rule_code in (
   'ORACLE_PRM_O7_DICT_ACCESS', 'ORACLE_PRM_REMOTE_OS_AUTHENT', 'ORACLE_PRM_REMOTE_OS_ROLES',
   'ORACLE_PRM_OS_ROLES', 'ORACLE_PRM_UTL_FILE_DIR', 'ORACLE_PRM_AUDIT_TRAIL',
   'ORACLE_PRM_AUDIT_SYS_OPERATIONS', 'ORACLE_PRM_UNIFIED_AUDITING', 'ORACLE_PRM_RESOURCE_LIMIT',
   'ORACLE_PRM_SEC_CASE_SENSITIVE', 'ORACLE_PRM_SEC_MAX_FAILED_LOGIN', 'ORACLE_PRM_SEC_BANNER',
   'ORACLE_PRM_SEC_PROTO_ERR_TRACE', 'ORACLE_PRM_SEC_PROTO_ERR_FURTHER',
   'ORACLE_PRF_FAILED_LOGIN_ATTEMPTS', 'ORACLE_PRF_PASSWORD_LIFE_TIME',
   'ORACLE_PRF_PASSWORD_LOCK_TIME', 'ORACLE_PRF_PASSWORD_GRACE_TIME',
   'ORACLE_PRF_PASSWORD_REUSE_MAX', 'ORACLE_PRF_PASSWORD_REUSE_TIME',
   'ORACLE_PRF_PASSWORD_VERIFY_FUNCTION', 'ORACLE_PRF_SESSIONS_PER_USER',
   'ORACLE_PRF_INACTIVE_ACCOUNT_TIME',
   'ORACLE_HIGH_SYS_PRIVS_GRANT', 'ORACLE_HIGH_ROLE_PRIVS_GRANT', 'ORACLE_HIGH_TAB_PRIVS_PUBLIC',
   'ORACLE_ADMIN_PWFILE_SYS_ONLY', 'ORACLE_NO_DEFAULT_PASSWORD', 'ORACLE_NO_DEFAULT_PROFILE',
   'ORACLE_AUDIT_CIS_POLICY_ON', 'ORACLE_NETWORK_ENCRYPTION_ON' );

-- The one rule that states the opposite of the benchmark it sits beside: the
-- fleet standardises on port 1433, CIS asks for the default port to be left
-- behind. Kept as the norm the organisation actually applies, but no longer
-- counted as benchmark compliance.
update ref_control_rule set origin = 'BENCHMARK', benchmark_code = 'CIS_POSTGRESQL'
 where rule_code in (
   'PG_PRM_SSL_ON', 'PG_PRM_PASSWORD_ENCRYPTION', 'PG_PRM_LOG_CONNECTIONS',
   'PG_PRM_LOG_DISCONNECTIONS', 'PG_PRM_LOG_STATEMENT', 'PG_PRM_SSL_MIN_PROTOCOL',
   'PG_PRM_PGAUDIT_LOADED',
   'PG_ROLE_NO_EXTRA_SUPERUSER', 'PG_ROLE_NO_BYPASSRLS',
   'PG_MEMBER_NO_SERVER_PROGRAM', 'PG_MEMBER_NO_SERVER_FILES', 'PG_MEMBER_NO_WRITE_ALL_DATA',
   'PG_HBA_NO_TRUST', 'PG_HBA_NO_WEAK_METHOD',
   'PG_PUBLIC_NO_CREATE' );

-- Mixed mode authentication: CIS asks for Windows only, the CHL norm accepts
-- mixed mode. Same standing as the TCP port. ref_control_rule set origin = 'HOUSE_CONFLICT', benchmark_code = 'CIS_MSSQL'
 where rule_code in ( 'MSSQL_REG_TCP_PORT', 'MSSQL_AUTH_WINDOWS_ONLY' );

-- Left as HOUSE, and worth re-examining during the mapping review:
--   *_ENGINE_SUPPORTED, *_BACKUP_FRESHNESS_SLA, *_STORAGE_PCT_USED
--     - service-level commitments, no benchmark equivalent.
--   ORACLE_PRM_SYS_LOGON_DELAY, ORACLE_NO_USERMIG_TABLE
--     - real hardening, but not traced to a published recommendation here.
--   ORACLE_TABLESPACE_ENCRYPTED
--     - encryption at rest is driven by regulation more than by the CIS Oracle
--       document; classify it against whichever framework actually mandates it.
--   ORACLE_PRM_PDB_OS_CREDENTIAL
--     - inactive, norm not settled (see its own comment above).


-- ============================================================
-- ref_nis2_domain
-- ------------------------------------------------------------
-- Six of the ten measures of NIS2 article 21(2): those a database can attest
-- about ITSELF, from what the collect already brings back. The four left out --
-- (d) supply chain, (f) effectiveness review, (g) training and hygiene beyond
-- configuration, (j) secured emergency communication -- are real obligations,
-- simply not ones this inventory can evidence. Declaring them here would put
-- four permanently grey blocks on every card and teach the reader to ignore
-- grey, which is the one colour that has to keep meaning something.
--
-- No version column, unlike ref_benchmark: article 21(2) is the text of the
-- directive, not an edition the organisation picks.
-- ============================================================
insert into ref_nis2_domain ( nis2_domain_code, display_order, title, article_ref, description )
   values ( 'ACCESS', 1, 'Access Control', 'Art. 21(2)(i)',
            'Who may connect and what they may do: privileged grants, account and password policy, authentication methods, default and orphaned accounts, rights held by PUBLIC.' );
insert into ref_nis2_domain ( nis2_domain_code, display_order, title, article_ref, description )
   values ( 'CRYPTO', 2, 'Cryptography', 'Art. 21(2)(h)',
            'Encryption at rest and in transit: tablespace and database encryption, key algorithms, forced TLS and its minimum protocol version.' );
insert into ref_nis2_domain ( nis2_domain_code, display_order, title, article_ref, description )
   values ( 'LOGGING', 3, 'Logging and Detection', 'Art. 21(2)(b)',
            'What the engine records of what happens to it: audit activation and policies, connection logging, error log retention. Incident HANDLING is not in scope -- this inventory attests that the trace exists, it does not watch it.' );
insert into ref_nis2_domain ( nis2_domain_code, display_order, title, article_ref, description )
   values ( 'CONTINUITY', 4, 'Business Continuity', 'Art. 21(2)(c)',
            'What stands between the service and a stop: backup freshness, WAL archiving, storage saturation, and the hard engine ceilings such as transaction id wraparound.' );
insert into ref_nis2_domain ( nis2_domain_code, display_order, title, article_ref, description )
   values ( 'HARDENING', 5, 'System Hardening', 'Art. 21(2)(a)',
            'Attack surface left enabled by configuration: command and automation surfaces, external file and network access, exposure of the instance itself.' );
insert into ref_nis2_domain ( nis2_domain_code, display_order, title, article_ref, description )
   values ( 'VULN', 6, 'Vulnerability Management', 'Art. 21(2)(e)',
            'Whether the engine can still receive a fix at all: major version support status and patch level.' );


-- ============================================================
-- NIS2 classification of the rules
-- ------------------------------------------------------------
-- One domain per rule. Written as six set-based updates for the same reason as
-- the provenance block above: the classification is reviewed as a whole, and
-- reading it as a list is what makes a wrong entry visible. A rule_code typed
-- wrong here updates nothing and leaves its rule unclassified, which the T_003
-- assertion reports by name.
--
-- Two placements that are not obvious, and are deliberate:
--   * MSSQL_DBPROP_TRUSTWORTHY_OFF and MSSQL_CFG_CROSS_DB_CHAINING sit in
--     ACCESS, not HARDENING. Both are privilege escalation paths across
--     database boundaries; what they put at risk is who ends up with what.
--   * ORACLE_PRM_SEC_PROTO_ERR_TRACE is LOGGING (it asks for the protocol error
--     to be recorded) while ORACLE_PRM_SEC_PROTO_ERR_FURTHER is HARDENING (it
--     asks for the session to be dropped). Same parameter family, two different
--     measures.
-- ============================================================
update ref_control_rule set nis2_domain_code = 'ACCESS'
 where rule_code in (
   'MSSQL_LOGIN_SYSADMIN_EXPIRATION', 'MSSQL_LOGIN_POLICY_CHECKED',
   'MSSQL_SA_RENAMED', 'MSSQL_SA_DISABLED', 'MSSQL_AUTH_WINDOWS_ONLY',
   'MSSQL_GROUP_NO_LOCAL_PERMISSION', 'MSSQL_GUEST_NO_CONNECT',
   'MSSQL_NO_ORPHANED_USER', 'MSSQL_PUBLIC_DEFAULT_PERMISSION',
   'MSSQL_DBPROP_TRUSTWORTHY_OFF', 'MSSQL_CFG_CROSS_DB_CHAINING',
   'ORACLE_PRF_FAILED_LOGIN_ATTEMPTS', 'ORACLE_PRF_PASSWORD_LIFE_TIME',
   'ORACLE_PRF_PASSWORD_LOCK_TIME', 'ORACLE_PRF_PASSWORD_GRACE_TIME',
   'ORACLE_PRF_PASSWORD_REUSE_MAX', 'ORACLE_PRF_PASSWORD_REUSE_TIME',
   'ORACLE_PRF_PASSWORD_VERIFY_FUNCTION', 'ORACLE_PRF_SESSIONS_PER_USER',
   'ORACLE_PRF_INACTIVE_ACCOUNT_TIME',
   'ORACLE_HIGH_SYS_PRIVS_GRANT', 'ORACLE_HIGH_ROLE_PRIVS_GRANT',
   'ORACLE_HIGH_TAB_PRIVS_PUBLIC', 'ORACLE_ADMIN_PWFILE_SYS_ONLY',
   'ORACLE_NO_DEFAULT_PASSWORD', 'ORACLE_NO_DEFAULT_PROFILE',
   'ORACLE_NO_USERMIG_TABLE',
   'ORACLE_PRM_O7_DICT_ACCESS', 'ORACLE_PRM_REMOTE_OS_AUTHENT',
   'ORACLE_PRM_REMOTE_OS_ROLES', 'ORACLE_PRM_OS_ROLES',
   'ORACLE_PRM_SEC_CASE_SENSITIVE', 'ORACLE_PRM_SEC_MAX_FAILED_LOGIN',
   'ORACLE_PRM_SYS_LOGON_DELAY',
   'PG_ROLE_NO_EXTRA_SUPERUSER', 'PG_ROLE_NO_BYPASSRLS',
   'PG_ROLE_REPLICATION_LIMITED', 'PG_MEMBER_NO_SERVER_PROGRAM',
   'PG_MEMBER_NO_SERVER_FILES', 'PG_MEMBER_NO_WRITE_ALL_DATA',
   'PG_HBA_NO_TRUST', 'PG_HBA_NO_WEAK_METHOD', 'PG_PUBLIC_NO_CREATE',
   'PG_PRM_PASSWORD_ENCRYPTION' );

update ref_control_rule set nis2_domain_code = 'CRYPTO'
 where rule_code in (
   'MSSQL_REG_FORCE_ENCRYPTION', 'MSSQL_ENC_STRONG_ALGORITHM',
   'ORACLE_TABLESPACE_ENCRYPTED', 'ORACLE_NETWORK_ENCRYPTION_ON',
   'ORACLE_NETWORK_ENCRYPTION_REQUIRED', 'ORACLE_NETWORK_UNENCRYPTED_CLIENT',
   'PG_PRM_SSL_ON', 'PG_PRM_SSL_MIN_PROTOCOL' );

update ref_control_rule set nis2_domain_code = 'LOGGING'
 where rule_code in (
   'MSSQL_AUDIT_LEVEL_LOGIN_FAILURES', 'MSSQL_SRVAUDIT_ACTION_GROUP_ON',
   'MSSQL_CFG_DEFAULT_TRACE', 'MSSQL_REG_NUM_ERRORLOG_FILES',
   'ORACLE_PRM_AUDIT_TRAIL', 'ORACLE_PRM_AUDIT_SYS_OPERATIONS',
   'ORACLE_PRM_UNIFIED_AUDITING', 'ORACLE_PRM_SEC_PROTO_ERR_TRACE',
   'ORACLE_AUDIT_CIS_POLICY_ON',
   'PG_PRM_LOG_CONNECTIONS', 'PG_PRM_LOG_DISCONNECTIONS',
   'PG_PRM_LOG_STATEMENT', 'PG_PRM_PGAUDIT_LOADED' );

update ref_control_rule set nis2_domain_code = 'CONTINUITY'
 where rule_code in (
   'MSSQL_BACKUP_FRESHNESS_SLA', 'MSSQL_STORAGE_PCT_USED',
   'MSSQL_DBPROP_AUTO_CLOSE_OFF', 'MSSQL_DBPROP_QUERY_STORE_ON',
   'ORACLE_BACKUP_FRESHNESS_SLA', 'ORACLE_STORAGE_PCT_USED',
   'PG_ARCHIVE_MODE_ON', 'PG_BACKUP_FRESHNESS_SLA', 'PG_XID_WRAPAROUND' );

update ref_control_rule set nis2_domain_code = 'HARDENING'
 where rule_code in (
   'MSSQL_CFG_ADHOC_DIST_QUERIES', 'MSSQL_CFG_CLR_ENABLED',
   'MSSQL_CFG_CLR_STRICT_SECURITY', 'MSSQL_CFG_DATABASE_MAIL_XPS',
   'MSSQL_CFG_OLE_AUTOMATION', 'MSSQL_CFG_REMOTE_ACCESS',
   'MSSQL_CFG_REMOTE_ADMIN_CONN', 'MSSQL_CFG_SCAN_STARTUP_PROCS',
   'MSSQL_CFG_XP_CMDSHELL', 'MSSQL_REG_HIDE_INSTANCE', 'MSSQL_REG_TCP_PORT',
   'ORACLE_PRM_UTL_FILE_DIR', 'ORACLE_PRM_RESOURCE_LIMIT',
   'ORACLE_PRM_SEC_BANNER', 'ORACLE_PRM_SEC_PROTO_ERR_FURTHER',
   'ORACLE_PRM_PDB_OS_CREDENTIAL' );

update ref_control_rule set nis2_domain_code = 'VULN'
 where rule_code in (
   'MSSQL_ENGINE_SUPPORTED', 'MSSQL_ENGINE_PATCH_CURRENT',
   'ORACLE_ENGINE_SUPPORTED', 'PG_ENGINE_SUPPORTED' );

-- PostgreSQL has NO rule in HARDENING, and that is a finding, not an oversight:
-- the Postgres collect brings back parameters that are all authentication,
-- logging or transport, and nothing that reduces an execution surface the way
-- xp_cmdshell or utl_file_dir do. Its cards will show a grey block there until
-- such a rule exists. Left visible on purpose.


-- ============================================================
-- ref_scoring_weight   (environment defaults to '*' = all environments)
-- ============================================================

-- MSSQL SECURITY  (verbatim from mssql_scoring_data.sql; sum = 100)
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'MSSQL', 'SECURITY', 'configoptions', 35 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'MSSQL', 'SECURITY', 'logins', 10 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'MSSQL', 'SECURITY', 'registryinfo', 10 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'MSSQL', 'SECURITY', 'sqlserveraudit', 10 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'MSSQL', 'SECURITY', 'dbproperties', 5 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'MSSQL', 'SECURITY', 'auditlevel', 5 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'MSSQL', 'SECURITY', 'encryption', 5 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'MSSQL', 'SECURITY', 'groups', 5 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'MSSQL', 'SECURITY', 'guestconnect', 5 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'MSSQL', 'SECURITY', 'orphanedusers', 5 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'MSSQL', 'SECURITY', 'publicpermission', 5 );

-- ORACLE SECURITY  (initial proposal, to be tuned; sum = 100)
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'ORACLE', 'SECURITY', 'admin_high_privs', 12 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'ORACLE', 'SECURITY', 'high_sys_privs', 12 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'ORACLE', 'SECURITY', 'default_user_pwd', 12 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'ORACLE', 'SECURITY', 'audit_enable', 10 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'ORACLE', 'SECURITY', 'security_parameter', 10 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'ORACLE', 'SECURITY', 'high_role_privs', 8 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'ORACLE', 'SECURITY', 'high_tab_privs', 8 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'ORACLE', 'SECURITY', 'network_encryption', 8 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'ORACLE', 'SECURITY', 'encrypted_tablespace', 8 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'ORACLE', 'SECURITY', 'default_profile', 6 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'ORACLE', 'SECURITY', 'security_profile', 6 );

-- Single-category domains (weight 100)
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'MSSQL', 'BACKUP', 'backup_freshness', 100 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'ORACLE', 'BACKUP', 'backup_freshness', 100 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'MSSQL', 'CAPACITY', 'capacity_saturation', 100 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'ORACLE', 'CAPACITY', 'capacity_saturation', 100 );
-- MSSQL LIFECYCLE now carries two categories: running a version that is out of
-- support is a heavier failure than lagging a cumulative update on a supported
-- one, hence 70/30 rather than an even split. ORACLE keeps 100 on out_of_support
-- for want of an Oracle patch reference in product_support.
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'MSSQL', 'LIFECYCLE', 'out_of_support', 70 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'MSSQL', 'LIFECYCLE', 'patch_level', 30 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'ORACLE', 'LIFECYCLE', 'out_of_support', 100 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'MSSQL', 'LICENSING', 'licensing', 100 );
-- ORACLE LICENSING: an option in use today outweighs one used in the past, the
-- same 70/30 reasoning as MSSQL LIFECYCLE above.
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'ORACLE', 'LICENSING', 'licensing', 70 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'ORACLE', 'LICENSING', 'licensing_past', 30 );

-- POSTGRES SECURITY  (sum = 100)
-- Weighted by what a deviation actually opens up rather than by how many rules
-- sit in each family: one trust line in pg_hba defeats every setting above it.
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'POSTGRES', 'SECURITY', 'security_parameter', 30 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'POSTGRES', 'SECURITY', 'hba_auth', 20 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'POSTGRES', 'SECURITY', 'role_privs', 20 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'POSTGRES', 'SECURITY', 'predef_role_member', 20 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'POSTGRES', 'SECURITY', 'public_privs', 10 );

-- POSTGRES BACKUP: archiving off is worse than archiving late, but not by much
-- -- both mean the recovery window is not what it is believed to be.
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'POSTGRES', 'BACKUP', 'wal_archiving', 40 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'POSTGRES', 'BACKUP', 'backup_freshness', 60 );

insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'POSTGRES', 'LIFECYCLE', 'out_of_support', 100 );
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'POSTGRES', 'CAPACITY', 'capacity_saturation', 100 );


-- ============================================================
-- ref_threshold   (environment defaults to '*' = all environments)
-- ============================================================

-- Capacity saturation (percentage used)
insert into ref_threshold ( control_code, metric, warn_value, crit_value )
   values ( 'MSSQL_CAPACITY_SATURATION', 'pct_used', 80, 90 );
insert into ref_threshold ( control_code, metric, warn_value, crit_value )
   values ( 'ORACLE_CAPACITY_SATURATION', 'pct_used', 80, 90 );

-- Backup freshness SLA (hours since last backup)
insert into ref_threshold ( control_code, metric, warn_value, crit_value )
   values ( 'MSSQL_BACKUP_FRESHNESS', 'hours_since_full', 24, 48 );
insert into ref_threshold ( control_code, metric, warn_value, crit_value )
   values ( 'MSSQL_BACKUP_FRESHNESS', 'hours_since_log', 2, 6 );
insert into ref_threshold ( control_code, metric, warn_value, crit_value )
   values ( 'ORACLE_BACKUP_FRESHNESS', 'hours_since_backup', 24, 48 );
insert into ref_threshold ( control_code, metric, warn_value, crit_value )
   values ( 'POSTGRES_BACKUP_FRESHNESS', 'hours_since_archived', 24, 48 );

-- Transaction id wraparound, as a percentage of the 2^31 ceiling. 50/80 rather
-- than the 80/90 used for storage: past the ceiling PostgreSQL refuses writes
-- cluster-wide, and the remedy is a VACUUM FREEZE whose duration grows with the
-- table -- reaching 80% already means the autovacuum settings need revisiting,
-- not that a disk needs extending. autovacuum_freeze_max_age defaults to 200M,
-- i.e. about 9% of the ceiling, so a healthy database sits far below the warning.
insert into ref_threshold ( control_code, metric, warn_value, crit_value )
   values ( 'POSTGRES_CAPACITY_SATURATION', 'pct_xid_used', 50, 80 );


-- ============================================================
-- product_support   (vendor end-of-support calendar)
-- ============================================================
-- Keyed on the MAJOR version (major.minor of the ProductVersion), because that
-- is what end-of-support dates actually depend on: every service pack of a given
-- release shares the same EOS dates (all SQL Server 2016 SPs end 2021-07-13 /
-- 2026-07-14). This makes the join to dim_instance.engine_version exact rather
-- than a fuzzy string match. Note 2008 R2 is 10.50, distinct from 2008 = 10.0.
--
-- Source: discovery/mssql/sqlserver_versions.csv. That file is transcribed by
-- hand here rather than loaded: it is ~10 rows of reference data that change
-- once or twice a year, and its CSV quoting is broken on several lines.
-- current_patch_level / current_patch_name reflect the latest published CU.

delete from product_support where product_company = 'MICROSOFT' and product_type = 'MSSQL';

insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              current_patch_name, current_patch_level, edition_date, end_of_support_date, end_of_ext_support_date )
   values ( 'MICROSOFT', 'MSSQL', '17.0', 'SQL Server 2025', 'SQL Server 2025',
            'CU6', '17.0.4055.5', date '2025-11-18', date '2031-01-06', date '2036-01-06' );
insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              current_patch_name, current_patch_level, edition_date, end_of_support_date, end_of_ext_support_date )
   values ( 'MICROSOFT', 'MSSQL', '16.0', 'SQL Server 2022 (Dallas)', 'SQL Server 2022',
            'CU25', '16.0.4255.1', date '2022-11-16', date '2028-01-11', date '2033-01-11' );
insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              current_patch_name, current_patch_level, edition_date, end_of_support_date, end_of_ext_support_date )
   values ( 'MICROSOFT', 'MSSQL', '15.0', 'SQL Server 2019 (Seattle)', 'SQL Server 2019',
            'CU32 + GDR securite', '15.0.4470.1', date '2019-11-04', date '2025-02-28', date '2030-01-08' );
insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              current_patch_name, current_patch_level, edition_date, end_of_support_date, end_of_ext_support_date )
   values ( 'MICROSOFT', 'MSSQL', '14.0', 'SQL Server 2017 (Helsinki)', 'SQL Server 2017',
            'CU31 + GDR securite', '14.0.3530.2', date '2017-10-02', date '2022-10-11', date '2027-10-12' );
insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              current_patch_name, current_patch_level, edition_date, end_of_support_date, end_of_ext_support_date )
   values ( 'MICROSOFT', 'MSSQL', '13.0', 'SQL Server 2016', 'SQL Server 2016',
            'SP3 GDR (securite)', '13.0.6490.1', date '2016-06-01', date '2021-07-13', date '2026-07-14' );
insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              current_patch_name, current_patch_level, edition_date, end_of_support_date, end_of_ext_support_date )
   values ( 'MICROSOFT', 'MSSQL', '12.0', 'SQL Server 2014 (Hekaton)', 'SQL Server 2014',
            'SP3 CU4+GDR', '12.0.6449.1', date '2014-04-01', date '2019-07-09', date '2024-07-09' );
insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              current_patch_name, current_patch_level, edition_date, end_of_support_date, end_of_ext_support_date )
   values ( 'MICROSOFT', 'MSSQL', '11.0', 'SQL Server 2012 (Denali)', 'SQL Server 2012',
            'SP4 GDR (ESU)', '11.0.7512.11', date '2012-03-06', date '2017-07-11', date '2022-07-12' );
insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              current_patch_name, current_patch_level, edition_date, end_of_support_date, end_of_ext_support_date )
   values ( 'MICROSOFT', 'MSSQL', '10.50', 'SQL Server 2008 R2 (Kilimanjaro)', 'SQL Server 2008 R2',
            'SP3 GDR (ESU)', '10.50.6785.2', date '2010-04-21', date '2014-07-08', date '2019-07-09' );
insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              current_patch_name, current_patch_level, edition_date, end_of_support_date, end_of_ext_support_date )
   values ( 'MICROSOFT', 'MSSQL', '10.0', 'SQL Server 2008 (Katmai)', 'SQL Server 2008',
            'SP4 GDR (ESU)', '10.0.6814.4', date '2008-08-07', date '2014-07-08', date '2019-07-09' );
insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              current_patch_name, current_patch_level, edition_date, end_of_support_date, end_of_ext_support_date )
   values ( 'MICROSOFT', 'MSSQL', '9.0', 'SQL Server 2005 (Yukon)', 'SQL Server 2005',
            'SP4 QFE', '9.0.5324.0', date '2005-11-07', date '2011-04-12', date '2016-04-12' );


-- PostgreSQL, keyed on the MAJOR version alone: since release 10 PostgreSQL
-- numbers a major with a single component (16.4 is major 16, minor 4), so the
-- major.minor split used for SQL Server does not apply and must not be copied.
--
-- The community policy is five years of support from the initial release, with
-- NO extended support: end_of_ext_support_date stays null, and the ESU branch of
-- load_findings_lifecycle is inert for PostgreSQL by construction rather than by
-- omission. current_patch_level is left null too: there is no PG_ENGINE_PATCH_
-- CURRENT rule, and publishing a minor version here that nobody refreshes would
-- make instances read as behind for as long as the file went untouched.
--
-- Transcribed by hand from postgresql.org/support/versioning, like the Microsoft
-- rows above. Recheck it against that page when a new major ships.

delete from product_support where product_company = 'POSTGRESQL' and product_type = 'POSTGRES';

insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              edition_date, end_of_support_date )
   values ( 'POSTGRESQL', 'POSTGRES', '18', 'PostgreSQL 18', 'PostgreSQL 18', date '2025-09-25', date '2030-11-14' );
insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              edition_date, end_of_support_date )
   values ( 'POSTGRESQL', 'POSTGRES', '17', 'PostgreSQL 17', 'PostgreSQL 17', date '2024-09-26', date '2029-11-08' );
insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              edition_date, end_of_support_date )
   values ( 'POSTGRESQL', 'POSTGRES', '16', 'PostgreSQL 16', 'PostgreSQL 16', date '2023-09-14', date '2028-11-09' );
insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              edition_date, end_of_support_date )
   values ( 'POSTGRESQL', 'POSTGRES', '15', 'PostgreSQL 15', 'PostgreSQL 15', date '2022-10-13', date '2027-11-11' );
insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              edition_date, end_of_support_date )
   values ( 'POSTGRESQL', 'POSTGRES', '14', 'PostgreSQL 14', 'PostgreSQL 14', date '2021-09-30', date '2026-11-12' );
insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              edition_date, end_of_support_date )
   values ( 'POSTGRESQL', 'POSTGRES', '13', 'PostgreSQL 13', 'PostgreSQL 13', date '2020-09-24', date '2025-11-13' );
insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              edition_date, end_of_support_date )
   values ( 'POSTGRESQL', 'POSTGRES', '12', 'PostgreSQL 12', 'PostgreSQL 12', date '2019-10-03', date '2024-11-14' );
insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              edition_date, end_of_support_date )
   values ( 'POSTGRESQL', 'POSTGRES', '11', 'PostgreSQL 11', 'PostgreSQL 11', date '2018-10-18', date '2023-11-09' );
insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              edition_date, end_of_support_date )
   values ( 'POSTGRESQL', 'POSTGRES', '10', 'PostgreSQL 10', 'PostgreSQL 10', date '2017-10-05', date '2022-11-10' );


-- Oracle, keyed on the MAJOR release alone. An Oracle banner version carries
-- five components (19.20.0.0.0) but the support dates depend only on the first:
-- every release update of 19c shares them. Same cut as PostgreSQL, and NOT the
-- major.minor cut used for SQL Server -- '19.20' matches nothing here.
--
-- Two release kinds, and the difference is load-bearing. A Long Term Release
-- (19c, and the 23 line) gets Premier then Extended Support; an Innovation
-- Release (18c, 21c) is not eligible for Extended Support AT ALL, so its
-- end_of_ext_support_date is null and the Premier date is the only one there is.
-- A null there means "none exists", not "not filled in yet".
--
-- The 23 line is branded Oracle AI Database 26ai since the October 2025 release
-- update, but the internal version stays 23.x (26ai reports 23.26.1.0.0), which
-- is what an instance banner returns and what this table must therefore be
-- keyed on. Only versions from 18c are listed: nothing older runs on the estate.
--
-- current_patch_level is left null, as for PostgreSQL: there is no Oracle patch
-- reference here and no *_ENGINE_PATCH_CURRENT rule to consume one.
--
-- Transcribed by hand from Oracle's Lifetime Support Policy, like the Microsoft
-- rows above; 19c and 23ai/26ai were both extended after their original dates,
-- so recheck rather than assume when a release changes status.

delete from product_support where product_company = 'ORACLE' and product_type = 'ORACLE';

insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              edition_date, end_of_support_date, end_of_ext_support_date )
   values ( 'ORACLE', 'ORACLE', '23', 'Oracle AI Database 26ai (formerly 23ai)', 'Oracle 26ai (23.x)',
            date '2023-09-19', date '2031-12-31', null );
insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              edition_date, end_of_support_date, end_of_ext_support_date )
   values ( 'ORACLE', 'ORACLE', '21', 'Oracle Database 21c (Innovation Release)', 'Oracle 21c',
            date '2021-08-13', date '2027-07-31', null );
insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              edition_date, end_of_support_date, end_of_ext_support_date )
   values ( 'ORACLE', 'ORACLE', '19', 'Oracle Database 19c (Long Term Release)', 'Oracle 19c',
            date '2019-04-25', date '2029-12-31', date '2032-12-31' );
insert into product_support ( product_company, product_type, product_version, commercial_name, display_name,
                              edition_date, end_of_support_date, end_of_ext_support_date )
   values ( 'ORACLE', 'ORACLE', '18', 'Oracle Database 18c (Innovation Release)', 'Oracle 18c',
            date '2018-07-23', date '2021-06-30', null );

commit;
