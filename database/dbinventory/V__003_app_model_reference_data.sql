-- ============================================================================
-- V__003_app_model_reference_data.sql
-- ----------------------------------------------------------------------------
-- Seed data for the scoring reference tables created in V__002:
--   ref_control          - catalog of compliance/quality controls
--   ref_scoring_weight   - weight of each check category within a scoring domain
--   ref_threshold        - warning/critical thresholds for metric-based controls
--
-- MSSQL SECURITY weights are transcribed verbatim from the legacy scoring script
-- (setup/inventory/dbInventory/bin/sql/mssql_scoring_data.sql): configoptions=35,
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
   values ( 'MSSQL_DBPROPERTIES', 'MSSQL', 'SECURITY', 'dbproperties', 'INSTANCE', 'Database properties (AUTO_CLOSE, TRUSTWORTHY)', 'MEDIUM' );
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
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_LICENSING_LMS', 'ORACLE', 'LICENSING', 'licensing', 'INSTANCE', 'Oracle feature usage (LMS) licensing', 'HIGH' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_LICENSING', 'MSSQL', 'LICENSING', 'licensing', 'INSTANCE', 'MSSQL edition/licensing', 'MEDIUM' );


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
            'TRUSTWORTHY must be off', 'is_trustworthy_on must be 0. Scope: msdb is exempt, it requires TRUSTWORTHY for Database Mail and SQL Agent.', 'MEDIUM' );

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
            'No local Windows group must hold server permissions', 'Compliant only when the collect reports the ''nogroup'' sentinel, i.e. no local group holds a permission.', 'MEDIUM' );
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
            'AUDIT_TRAIL must not be NONE', 'Any destination (DB, DB,EXTENDED, OS, XML) is accepted; NONE disables traditional auditing entirely.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRM_AUDIT_SYS_OPERATIONS', 'ORACLE_SECURITY_PARAMETER', 'INSTANCE', '*',
            'AUDIT_SYS_OPERATIONS must be TRUE', 'Without it, actions performed as SYSDBA are not audited.', 'MEDIUM' );
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
            'PASSWORD_LIFE_TIME must be at most 90 days', 'UNLIMITED is non-compliant: the password never expires.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRF_PASSWORD_LOCK_TIME', 'ORACLE_SECURITY_PROFILE', 'DATABASE', 'profile / resource',
            'PASSWORD_LOCK_TIME must be at least 1 day', 'UNLIMITED is compliant: the account stays locked until an administrator releases it.', 'MEDIUM' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_PRF_PASSWORD_GRACE_TIME', 'ORACLE_SECURITY_PROFILE', 'DATABASE', 'profile / resource',
            'PASSWORD_GRACE_TIME must be at most 5 days', 'UNLIMITED is non-compliant: an expired password can be used indefinitely.', 'LOW' );
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
            'No account may hold a high-privilege system privilege', 'Covers the CIS list collected by get_info_oracle_security.sh (SELECT ANY DICTIONARY, BECOME USER, GRANT ANY ROLE, CREATE EXTERNAL JOB and the rest). Scope: Oracle-maintained accounts are exempt.', 'HIGH' );
insert into ref_control_rule ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( 'ORACLE_HIGH_ROLE_PRIVS_GRANT', 'ORACLE_HIGH_ROLE_PRIVS', 'DATABASE', 'grantee / role',
            'No account may hold DBA or a catalog role', 'Covers DBA, SELECT_CATALOG_ROLE, DELETE_CATALOG_ROLE and EXECUTE_CATALOG_ROLE. Scope: Oracle-maintained accounts are exempt.', 'HIGH' );
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
   values ( 'MSSQL_ENGINE_PATCH_CURRENT', 'MSSQL_PATCH_LEVEL', 'INSTANCE', '*',
            'Engine build must be at the latest published patch level', 'dim_instance.engine_version must be at or above product_support.current_patch_level for its major version, compared on the build and revision numbers. Note: an instance kept on the GDR-only branch reads as behind, because the reference tracks the cumulative-update train.', 'MEDIUM' );


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
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'ORACLE', 'LICENSING', 'licensing', 100 );


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

commit;
