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
   values ( 'MSSQL_DBPROPERTIES', 'MSSQL', 'SECURITY', 'dbproperties', 'DATABASE', 'Database properties (AUTO_CLOSE, TRUSTWORTHY)', 'MEDIUM' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_AUDITLEVEL', 'MSSQL', 'SECURITY', 'auditlevel', 'INSTANCE', 'Server audit level', 'MEDIUM' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_ENCRYPTION', 'MSSQL', 'SECURITY', 'encryption', 'DATABASE', 'Transparent Data Encryption keys', 'MEDIUM' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_GROUPS', 'MSSQL', 'SECURITY', 'groups', 'INSTANCE', 'Local Windows group permissions', 'MEDIUM' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_GUESTCONNECT', 'MSSQL', 'SECURITY', 'guestconnect', 'DATABASE', 'Guest CONNECT permission', 'MEDIUM' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_ORPHANEDUSERS', 'MSSQL', 'SECURITY', 'orphanedusers', 'DATABASE', 'Orphaned database users', 'LOW' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_PUBLICPERMISSION', 'MSSQL', 'SECURITY', 'publicpermission', 'DATABASE', 'Public role permissions', 'MEDIUM' );

-- Oracle security controls (score_domain = SECURITY)
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_ADMIN_HIGH_PRIVS', 'ORACLE', 'SECURITY', 'admin_high_privs', 'INSTANCE', 'High administrative privileges (pwfile)', 'HIGH' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_AUDIT_ENABLE', 'ORACLE', 'SECURITY', 'audit_enable', 'DATABASE', 'Audit policy activation', 'MEDIUM' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_DEFAULT_PROFILE', 'ORACLE', 'SECURITY', 'default_profile', 'DATABASE', 'Users on DEFAULT profile', 'LOW' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_DEFAULT_USER_PWD', 'ORACLE', 'SECURITY', 'default_user_pwd', 'DATABASE', 'Accounts with default passwords', 'HIGH' );
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

-- Backup freshness controls (score_domain = BACKUP)
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_BACKUP_FRESHNESS', 'MSSQL', 'BACKUP', 'backup_freshness', 'DATABASE', 'Backup freshness vs SLA', 'HIGH' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_BACKUP_FRESHNESS', 'ORACLE', 'BACKUP', 'backup_freshness', 'DATABASE', 'Backup freshness vs SLA', 'HIGH' );

-- Capacity saturation controls (score_domain = CAPACITY)
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_CAPACITY_SATURATION', 'MSSQL', 'CAPACITY', 'capacity_saturation', 'STORAGE', 'Storage saturation vs threshold', 'MEDIUM' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_CAPACITY_SATURATION', 'ORACLE', 'CAPACITY', 'capacity_saturation', 'STORAGE', 'Tablespace saturation vs threshold', 'MEDIUM' );

-- Lifecycle / out-of-support controls (score_domain = LIFECYCLE)
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_OUT_OF_SUPPORT', 'MSSQL', 'LIFECYCLE', 'out_of_support', 'INSTANCE', 'Engine version end-of-support', 'HIGH' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_OUT_OF_SUPPORT', 'ORACLE', 'LIFECYCLE', 'out_of_support', 'INSTANCE', 'Engine version end-of-support', 'HIGH' );

-- Licensing controls (score_domain = LICENSING)
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'ORACLE_LICENSING_LMS', 'ORACLE', 'LICENSING', 'licensing', 'INSTANCE', 'Oracle feature usage (LMS) licensing', 'HIGH' );
insert into ref_control ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( 'MSSQL_LICENSING', 'MSSQL', 'LICENSING', 'licensing', 'INSTANCE', 'MSSQL edition/licensing', 'MEDIUM' );


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
insert into ref_scoring_weight ( platform, score_domain, category, weight ) values ( 'MSSQL', 'LIFECYCLE', 'out_of_support', 100 );
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

commit;
