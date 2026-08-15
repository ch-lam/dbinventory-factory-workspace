-- ============================================================================
-- V__005_create_scoring_etl.sql
-- ----------------------------------------------------------------------------
-- Scoring ETL package pkg_dbinv_scoring, driven by the parametric reference
-- tables (ref_control, ref_control_rule, ref_exception, ref_scoring_weight,
-- ref_threshold).
--
-- Four stages, one single derivation chain:
--
--   load_findings     raw per-item verdicts        -> fact_control_finding
--   apply_exceptions  resolve granted derogations  -> fact_control_finding.exception_id
--   load_compliance   roll-up per control/entity   -> fact_compliance
--   load_scoring      weighted aggregation         -> fact_scoring
--
-- Why a per-item fact:
--   The verdict an auditor needs is "which item deviates, and is that deviation
--   covered by a signed derogation". Collapsing it straight into a per-category
--   verdict, as the previous version did, left only a truncated text blob. The
--   raw verdict in fact_control_finding.is_compliant is NEVER rewritten by an
--   exception: a covered deviation keeps is_compliant = 0 and gets an
--   exception_id. That is what lets the RSSI team spot, during a periodic
--   review, a derogation that no longer covers anything.
--
-- Why exceptions are a separate stage:
--   Granting a derogation does not require a new collect. Running
--   apply_exceptions + load_compliance + load_scoring for a snapshot date is
--   enough to refresh that day's score.
--
-- Rules vs exceptions:
--   Scope conditions are part of the norm and stay in the predicates below
--   (system databases exempt from encryption, Express/Developer editions exempt
--   from TDE, sa/monitoring exempt from the login policy). Turning them into
--   exceptions would flood the list the RSSI team has to review. Only a decision
--   taken by a human on a specific item belongs in ref_exception.
--
-- Grain:
--   * Rules are evaluated at their natural level (ref_control_rule.entity_type):
--     per instance for sp_configure/registry/logins, per database for database
--     properties/encryption/guest/orphaned users/public role.
--   * fact_compliance stays at the control's grain (ref_control.entity_type) and
--     keeps exactly the shape it had before this refactoring, so load_scoring
--     and the APEX pages are untouched.
--
-- NOT YET IMPLEMENTED (documented gaps, no policy fabricated here):
--   * LICENSING scoring: requires LMS logic; deferred.
--   * PDB_OS_CREDENTIAL is collected but has no settled norm; it is catalogued
--     in ref_control_rule at active = 0 rather than judged on a made-up value.
--
-- Assumptions (validated against real data on the dev database):
--   * MSSQL security tables key on `servername`, joined to dim_instance on
--     instance_name. Verified: 0 unmatched instance, 0 unmatched database.
--   * ORACLE security tables key on `db_name` (v$database.name) and, at database
--     grain, on `pdb_name` -- 'NON CONTAINER' for a non-CDB, which maps to
--     dim_database.db_name = the database name itself.
--   * the ORACLE compliance_score column present on all twelve staging tables is
--     never populated by get_info_oracle_security.sh: it is a legacy vestige and
--     carries no verdict. Every Oracle predicate below is evaluated from the raw
--     collected values.
-- ============================================================================

create or replace package pkg_dbinv_scoring as

   procedure load_findings ( p_snapshot_date in date default trunc(sysdate) );

   procedure apply_exceptions ( p_snapshot_date in date default trunc(sysdate) );

   procedure load_compliance ( p_snapshot_date in date default trunc(sysdate) );

   procedure load_scoring ( p_snapshot_date in date default trunc(sysdate) );

   procedure load_all ( p_snapshot_date in date default trunc(sysdate) );

end pkg_dbinv_scoring;
/

create or replace package body pkg_dbinv_scoring as

   -- ===============================================================
   -- MSSQL security findings
   -- ===============================================================
   -- One row per evaluated item. `observed_value` carries the rendered evidence
   -- ("clr enabled=1", "SALES/guest"): it is what load_compliance lists in the
   -- roll-up, and what ref_exception.observed_value is matched against when a
   -- derogation is pinned to a specific value.
   --
   -- The entity is resolved from ref_control_rule.entity_type, so moving a rule
   -- from instance to database grain is a reference-data change, not a code
   -- change.
   procedure load_findings_mssql_sec ( p_snapshot_date in date ) is
   begin
      merge into fact_control_finding f
      using (
         select src.rule_code,
                rr.entity_type,
                case rr.entity_type when 'DATABASE' then dd.database_id else di.instance_id end entity_id,
                src.item_key,
                p_snapshot_date snapshot_date,
                src.is_ok is_compliant,
                substr(src.observed_value, 1, 400) observed_value,
                substr(src.expected_value, 1, 400) expected_value
         from (
            -- ---------- configoptions ----------
            -- mssql_getconfigoptions.sql whitelists exactly these names, so the
            -- decode below covers every collected row; an unknown option would
            -- produce a NULL rule_code and be dropped by the join to
            -- ref_control_rule rather than silently counted as a deviation.
            select case c.name
                      when 'Ad Hoc Distributed Queries'   then 'MSSQL_CFG_ADHOC_DIST_QUERIES'
                      when 'clr enabled'                  then 'MSSQL_CFG_CLR_ENABLED'
                      when 'cross db ownership chaining'  then 'MSSQL_CFG_CROSS_DB_CHAINING'
                      when 'Database Mail XPs'            then 'MSSQL_CFG_DATABASE_MAIL_XPS'
                      when 'Ole Automation Procedures'    then 'MSSQL_CFG_OLE_AUTOMATION'
                      when 'remote access'                then 'MSSQL_CFG_REMOTE_ACCESS'
                      when 'remote admin connections'     then 'MSSQL_CFG_REMOTE_ADMIN_CONN'
                      when 'scan for startup procs'       then 'MSSQL_CFG_SCAN_STARTUP_PROCS'
                      when 'xp_cmdshell'                  then 'MSSQL_CFG_XP_CMDSHELL'
                      when 'default trace enabled'        then 'MSSQL_CFG_DEFAULT_TRACE'
                      when 'clr strict security'          then 'MSSQL_CFG_CLR_STRICT_SECURITY'
                   end rule_code,
                   c.servername,
                   cast(null as varchar2(50 char)) db_name,
                   '*' item_key,
                   case when c.run_value = case c.name
                                              when 'default trace enabled' then 1
                                              when 'clr strict security'   then 1
                                              else 0
                                           end
                        then 1 else 0 end is_ok,
                   c.name || '=' || c.run_value observed_value,
                   'run_value=' || case c.name
                                      when 'default trace enabled' then 1
                                      when 'clr strict security'   then 1
                                      else 0
                                   end expected_value
            from mssql_security_configoptions c
            union all
            -- ---------- registryinfo ----------
            -- The legacy rule also accepted "Hide Instance = 0" on servers named
            -- XV%; that was a derogation disguised as a norm and has been moved
            -- out (it covered 0 rows on the current fleet). Such a case is now
            -- expressed as a ref_exception row so the RSSI team can review it.
            select case r.name
                      when 'Hide Instance'    then 'MSSQL_REG_HIDE_INSTANCE'
                      when 'ForceEncryption'  then 'MSSQL_REG_FORCE_ENCRYPTION'
                      when 'NumErrorlogFiles' then 'MSSQL_REG_NUM_ERRORLOG_FILES'
                      when 'TCP Port'         then 'MSSQL_REG_TCP_PORT'
                   end,
                   r.servername,
                   cast(null as varchar2(50 char)),
                   '*',
                   case when ( r.name = 'Hide Instance'    and r.value = 1 )
                          or ( r.name = 'ForceEncryption'  and r.value = 1 )
                          or ( r.name = 'NumErrorlogFiles' and r.value > 12 )
                          or ( r.name = 'TCP Port'         and r.value = 1433 )
                        then 1 else 0 end,
                   r.name || '=' || r.value,
                   case r.name
                      when 'Hide Instance'    then 'value=1'
                      when 'ForceEncryption'  then 'value=1'
                      when 'NumErrorlogFiles' then 'value>12'
                      when 'TCP Port'         then 'value=1433'
                   end
            from mssql_security_registryinfo r
            union all
            -- ---------- dbproperties (per database) ----------
            select 'MSSQL_DBPROP_AUTO_CLOSE_OFF', d.servername, d.db_name, '*',
                   case when d.is_auto_close_on = 0 then 1 else 0 end,
                   d.db_name || ' (auto_close=' || d.is_auto_close_on || ')',
                   'is_auto_close_on=0'
            from mssql_security_dbproperties d
            union all
            -- msdb needs TRUSTWORTHY for Database Mail and SQL Agent: scope of
            -- the norm, not a derogation.
            select 'MSSQL_DBPROP_TRUSTWORTHY_OFF', d.servername, d.db_name, '*',
                   case when d.is_trustworthy_on = 0 or d.db_name = 'msdb' then 1 else 0 end,
                   d.db_name || ' (trustworthy=' || d.is_trustworthy_on || ')',
                   'is_trustworthy_on=0'
            from mssql_security_dbproperties d
            union all
            -- ---------- auditlevel ----------
            select 'MSSQL_AUDIT_LEVEL_LOGIN_FAILURES', a.servername, cast(null as varchar2(50 char)), '*',
                   case when a.auditlevel in ( 'All', 'Failed' ) then 1 else 0 end,
                   'auditlevel=' || a.auditlevel,
                   'auditlevel in (All, Failed)'
            from mssql_security_auditlevel a
            union all
            -- ---------- encryption (per database) ----------
            -- Scope of the norm: system databases hold engine-managed keys, and
            -- Express/Developer editions do not ship TDE at all.
            select 'MSSQL_ENC_STRONG_ALGORITHM', e.servername, e.db_name, e.key_name,
                   case when e.db_name in ( 'master', 'model', 'msdb', 'tempdb' )
                          or e.algorithm_desc in ( 'TRIPLE_DES', 'AES_128', 'AES_192', 'AES_256' )
                          or ( e.key_name = 'AES' and e.algorithm_desc = '256' )
                          or exists ( select 1 from mssql_hosts h
                                       where h.hostname = e.servername
                                         and ( lower(h.mssql_edition) like '%express%'
                                            or lower(h.mssql_edition) like '%developer%' ) )
                        then 1 else 0 end,
                   e.db_name || '/' || e.key_name || ' (' || e.algorithm_desc || ')',
                   'algorithm_desc in (TRIPLE_DES, AES_128, AES_192, AES_256)'
            from mssql_security_encryption e
            union all
            -- ---------- groups ----------
            select 'MSSQL_GROUP_NO_LOCAL_PERMISSION', g.servername, cast(null as varchar2(50 char)), g.localgroupname,
                   case when g.localgroupname = 'nogroup' then 1 else 0 end,
                   g.localgroupname || ' (' || g.permission_name || ')',
                   'no local group holding a permission'
            from mssql_security_groups g
            union all
            -- ---------- guestconnect (per database) ----------
            select 'MSSQL_GUEST_NO_CONNECT', gc.servername, gc.db_name, gc.permission_name,
                   case when gc.permission_name = 'no_permission' and gc.state_desc = 'no_permission'
                        then 1 else 0 end,
                   gc.db_name || ' (' || gc.permission_name || ')',
                   'no CONNECT permission for guest'
            from mssql_security_guestconnect gc
            union all
            -- ---------- logins ----------
            -- The two rules partition the population on is_sysadmin, which
            -- reproduces the legacy ordered CASE exactly: a sysadmin login was
            -- judged on password expiration alone (a sysadmin with expiration
            -- checked passed even without the password policy), a regular login
            -- on the password policy alone.
            select 'MSSQL_LOGIN_SYSADMIN_EXPIRATION', l.servername, cast(null as varchar2(50 char)), l.login_name,
                   case when l.login_name in ( 'sa', 'monitoring' ) then 1
                        when l.is_expiration_checked = 1 then 1
                        else 0 end,
                   l.login_name,
                   'is_expiration_checked=1'
            from mssql_security_logins l
            where l.is_sysadmin = 1
            union all
            select 'MSSQL_LOGIN_POLICY_CHECKED', l.servername, cast(null as varchar2(50 char)), l.login_name,
                   case when l.login_name in ( 'sa', 'monitoring' ) then 1
                        when l.is_policy_checked = 1 then 1
                        else 0 end,
                   l.login_name,
                   'is_policy_checked=1'
            from mssql_security_logins l
            where l.is_sysadmin <> 1
            union all
            -- ---------- authentication mode ----------
            -- Read from mssql_hosts rather than from a security table: the
            -- property comes back with the instance inventory, which is where
            -- the collect already asks for it. An instance collected before the
            -- property was added reads NULL and is left unjudged rather than
            -- counted as mixed mode.
            select 'MSSQL_AUTH_WINDOWS_ONLY', h.hostname, cast(null as varchar2(50 char)), '*',
                   case when h.is_integrated_security_only = 1 then 1 else 0 end,
                   case when h.is_integrated_security_only = 1 then 'Windows authentication only'
                        else 'mixed mode (SQL logins accepted)' end,
                   'Windows authentication only'
            from mssql_hosts h
            where h.is_integrated_security_only is not null
            union all
            -- ---------- built-in sysadmin account ----------
            -- Keyed on the sid by the collect, not on the name, so the rule keeps
            -- working once the account has been renamed as it asks.
            select 'MSSQL_SA_RENAMED', sa.servername, cast(null as varchar2(50 char)), '*',
                   case when lower(sa.login_name) <> 'sa' then 1 else 0 end,
                   'sid 0x01 is named ' || sa.login_name,
                   'a name other than sa'
            from mssql_security_sa sa
            union all
            select 'MSSQL_SA_DISABLED', sa.servername, cast(null as varchar2(50 char)), '*',
                   case when sa.is_disabled = 1 then 1 else 0 end,
                   sa.login_name || ' (is_disabled=' || nvl(to_char(sa.is_disabled), 'null') || ')',
                   'is_disabled=1'
            from mssql_security_sa sa
            union all
            -- ---------- orphanedusers (per database) ----------
            select 'MSSQL_NO_ORPHANED_USER', o.servername, o.db_name, o.user_name,
                   case when o.user_name = 'NoOrphanedUser' then 1 else 0 end,
                   o.db_name || '/' || o.user_name,
                   'no orphaned user'
            from mssql_security_orphanedusers o
            union all
            -- ---------- publicpermission (per database) ----------
            select 'MSSQL_PUBLIC_DEFAULT_PERMISSION', pp.servername, pp.db_name,
                   pp.username || '/' || pp.permission_name,
                   case when pp.permission_name = 'OnlyDefaultPermission'
                         and pp.state_desc = 'OnlyDefaultPermission'
                        then 1 else 0 end,
                   pp.db_name || '/' || pp.username || ' (' || pp.permission_name || ')',
                   'only default permissions on the public role'
            from mssql_sec_pubperm pp
            union all
            -- ---------- sqlserveraudit ----------
            select 'MSSQL_SRVAUDIT_ACTION_GROUP_ON', sa.servername, cast(null as varchar2(50 char)), sa.auditactionname,
                   case when sa.auditactionname in ( 'AUDIT_CHANGE_GROUP', 'FAILED_LOGIN_GROUP', 'SUCCESSFUL_LOGIN_GROUP' )
                         and sa.auditenabled = 1
                         and sa.auditspecificationenabled = 1
                        then 1 else 0 end,
                   sa.auditactionname,
                   'expected action group, audit and specification enabled'
            from mssql_security_sqlserveraudit sa
         ) src
         join ref_control_rule rr on rr.rule_code = src.rule_code and rr.active = 1
         join dim_instance di on di.platform = 'MSSQL' and di.instance_name = src.servername
         left join dim_database dd on rr.entity_type = 'DATABASE'
              and dd.instance_id = di.instance_id and dd.db_name = src.db_name
         where rr.entity_type <> 'DATABASE' or dd.database_id is not null
      ) s
      on ( f.rule_code = s.rule_code and f.entity_type = s.entity_type
           and f.entity_id = s.entity_id and f.item_key = s.item_key
           and f.snapshot_date = s.snapshot_date )
      when matched then update set
         f.is_compliant = s.is_compliant,
         f.observed_value = s.observed_value,
         f.expected_value = s.expected_value
      when not matched then
         insert ( rule_code, entity_type, entity_id, item_key, snapshot_date,
                  is_compliant, observed_value, expected_value )
         values ( s.rule_code, s.entity_type, s.entity_id, s.item_key, s.snapshot_date,
                  s.is_compliant, s.observed_value, s.expected_value );
   end load_findings_mssql_sec;


   -- ===============================================================
   -- ORACLE security findings
   -- ===============================================================
   -- Same shape as the MSSQL procedure, with one structural difference that
   -- drives most of the code below.
   --
   -- The MSSQL collects emit SENTINEL rows ('NoOrphanedUser', 'nogroup',
   -- 'no_permission'), so every instance yields a row and a compliant verdict
   -- falls out of the merge. The Oracle collects emit ONLY THE DEVIATIONS:
   -- oracle_sec_high_sys_privs & co. are empty on a clean database. Merging them
   -- as they stand would write is_compliant = 0 rows and nothing else, and a
   -- compliant database would be indistinguishable from one that was never
   -- collected -- scored on zero item either way.
   --
   -- So those rules are driven from the population of COLLECTED entities and
   -- left-joined to the deviations. The witness of a successful collect is:
   --   * per instance  - oracle_security_parameter, emitted unconditionally for
   --     every non-standby database (the _sys_logon_delay branch always returns
   --     a row, set or not);
   --   * per database  - oracle_security_profile, emitted unconditionally for
   --     every PDB (dba_profiles/cdb_profiles always return rows).
   -- A database missing from its witness produces no finding at all, which is
   -- the intended behaviour: a failed collect must not be scored as clean.
   --
   -- Entity resolution reuses the convention of load_fact_config_parameter:
   -- oracle_databases on db_name, then dim_host, then dim_instance. The staging
   -- tables carry 'NON CONTAINER' as pdb_name for non-CDB databases, whereas
   -- dim_database.db_name holds the PDB name, hence the case below.
   procedure load_findings_oracle_sec ( p_snapshot_date in date ) is
   begin
      merge into fact_control_finding f
      using (
         with
         -- Collected-entity witnesses (see header).
         w_inst as ( select distinct db_name from oracle_security_parameter ),
         w_db   as ( select distinct db_name, pdb_name from oracle_security_profile ),
         -- Accounts Oracle ships and maintains itself: out of scope of the
         -- privilege and profile rules. This is the norm's own scope, not a
         -- derogation, so it must never reach the RSSI review list.
         ora_managed as (
            select db_name, pdb_name, username
              from oracle_sec_default_profile
             where oracle_managed = 'Y'
         ),
         -- Per-item deviations of the rules whose collect only reports what is
         -- wrong. Listed once, used twice: as the non-compliant rows, and as the
         -- anti-join that decides which entities get their compliant row.
         dev_db as (
            select 'ORACLE_HIGH_SYS_PRIVS_GRANT' rule_code, sp.db_name, sp.pdb_name,
                   sp.username || '/' || sp.privilege item_key,
                   sp.username || ' holds ' || sp.privilege observed_value
              from oracle_sec_high_sys_privs sp
             where not exists ( select 1 from ora_managed m
                                 where m.db_name = sp.db_name and m.pdb_name = sp.pdb_name
                                   and m.username = sp.username )
            union all
            select 'ORACLE_HIGH_ROLE_PRIVS_GRANT', rp.db_name, rp.pdb_name,
                   rp.username || '/' || rp.privilege,
                   rp.username || ' holds ' || rp.privilege
              from oracle_sec_high_role_privs rp
             where not exists ( select 1 from ora_managed m
                                 where m.db_name = rp.db_name and m.pdb_name = rp.pdb_name
                                   and m.username = rp.username )
            union all
            -- No account exemption here: the grantee is PUBLIC by construction.
            select 'ORACLE_HIGH_TAB_PRIVS_PUBLIC', tp.db_name, tp.pdb_name,
                   tp.username || '/' || tp.privilege,
                   tp.username || ' -> ' || tp.privilege
              from oracle_sec_high_tab_privs tp
         ),
         -- Same idea at instance grain. DBA_USERS_WITH_DEFPWD is reported without
         -- a usable PDB name in CDB mode (the collect emits the literal
         -- 'CONTAINER'), which is why the rule is catalogued at INSTANCE grain.
         dev_inst as (
            select 'ORACLE_NO_DEFAULT_PASSWORD' rule_code, dp.db_name,
                   dp.username item_key,
                   dp.username || ' still has its default password' observed_value
              from oracle_sec_default_user_pwd dp
         ),
         -- The rule codes driven by the anti-join, with the wording of their
         -- compliant row.
         abs_db_rule as (
            select 'ORACLE_HIGH_SYS_PRIVS_GRANT' rule_code,
                   'no high-privilege system privilege granted' ok_value,
                   'no high-privilege system privilege' expected_value from dual
            union all
            select 'ORACLE_HIGH_ROLE_PRIVS_GRANT',
                   'no DBA or catalog role granted', 'no DBA or catalog role' from dual
            union all
            select 'ORACLE_HIGH_TAB_PRIVS_PUBLIC',
                   'no sensitive package granted to PUBLIC', 'no EXECUTE to PUBLIC on sensitive packages' from dual
         )
         select src.rule_code,
                rr.entity_type,
                case rr.entity_type when 'DATABASE' then dd.database_id else di.instance_id end entity_id,
                src.item_key,
                p_snapshot_date snapshot_date,
                src.is_ok is_compliant,
                substr(src.observed_value, 1, 400) observed_value,
                substr(src.expected_value, 1, 400) expected_value
         from (
            -- ---------- initialisation parameters (per instance) ----------
            -- The collect whitelists exactly these names; an unknown one yields a
            -- NULL rule_code and is dropped by the join to ref_control_rule
            -- rather than silently counted as a deviation.
            select case lower(p.parameter_name)
                      when 'o7_dictionary_accessibility'       then 'ORACLE_PRM_O7_DICT_ACCESS'
                      when 'remote_os_authent'                 then 'ORACLE_PRM_REMOTE_OS_AUTHENT'
                      when 'remote_os_roles'                   then 'ORACLE_PRM_REMOTE_OS_ROLES'
                      when 'os_roles'                          then 'ORACLE_PRM_OS_ROLES'
                      when 'utl_file_dir'                      then 'ORACLE_PRM_UTL_FILE_DIR'
                      when 'audit_trail'                       then 'ORACLE_PRM_AUDIT_TRAIL'
                      when 'audit_sys_operations'              then 'ORACLE_PRM_AUDIT_SYS_OPERATIONS'
                      when 'unified auditing'                  then 'ORACLE_PRM_UNIFIED_AUDITING'
                      when 'resource_limit'                    then 'ORACLE_PRM_RESOURCE_LIMIT'
                      when 'sec_case_sensitive_logon'          then 'ORACLE_PRM_SEC_CASE_SENSITIVE'
                      when 'sec_max_failed_login_attempts'     then 'ORACLE_PRM_SEC_MAX_FAILED_LOGIN'
                      when 'sec_return_server_release_banner'  then 'ORACLE_PRM_SEC_BANNER'
                      when 'sec_protocol_error_trace_action'   then 'ORACLE_PRM_SEC_PROTO_ERR_TRACE'
                      when 'sec_protocol_error_further_action' then 'ORACLE_PRM_SEC_PROTO_ERR_FURTHER'
                      when '_sys_logon_delay'                  then 'ORACLE_PRM_SYS_LOGON_DELAY'
                      when 'pdb_os_credential'                 then 'ORACLE_PRM_PDB_OS_CREDENTIAL'
                   end rule_code,
                   p.db_name,
                   cast(null as varchar2(200 char)) pdb_name,
                   '*' item_key,
                   case lower(p.parameter_name)
                      when 'utl_file_dir'
                         then case when trim(p.parameter_value) is null then 1 else 0 end
                      when 'audit_trail'
                         then case when upper(nvl(trim(p.parameter_value), 'NONE')) <> 'NONE' then 1 else 0 end
                      when 'sec_max_failed_login_attempts'
                         then case when regexp_like(trim(p.parameter_value), '^[0-9]+$')
                                    and to_number(trim(p.parameter_value)) <= 3 then 1 else 0 end
                      when 'sec_protocol_error_trace_action'
                         then case when upper(nvl(trim(p.parameter_value), 'NONE')) in ( 'LOG', 'TRACE' ) then 1 else 0 end
                      when 'sec_protocol_error_further_action'
                         then case when upper(nvl(trim(p.parameter_value), 'CONTINUE')) not like 'CONTINUE%' then 1 else 0 end
                      when '_sys_logon_delay'
                         then case when trim(p.parameter_value) = '4' then 1 else 0 end
                      when 'pdb_os_credential'
                         then 0                       -- catalogued at active = 0, never merged
                      else
                         -- the remaining parameters are plain booleans
                         case when lower(p.parameter_name) in ( 'audit_sys_operations', 'resource_limit',
                                                                'sec_case_sensitive_logon', 'unified auditing' )
                                   then case when upper(nvl(trim(p.parameter_value), 'FALSE')) = 'TRUE' then 1 else 0 end
                              else case when upper(nvl(trim(p.parameter_value), 'FALSE')) = 'FALSE' then 1 else 0 end
                         end
                   end is_ok,
                   p.parameter_name || '=' || nvl(trim(p.parameter_value), '<empty>') observed_value,
                   case lower(p.parameter_name)
                      when 'utl_file_dir'                      then 'empty'
                      when 'audit_trail'                       then 'any value but NONE'
                      when 'sec_max_failed_login_attempts'     then '<= 3'
                      when 'sec_protocol_error_trace_action'   then 'LOG or TRACE'
                      when 'sec_protocol_error_further_action' then 'not CONTINUE'
                      when '_sys_logon_delay'                  then '4'
                      when 'audit_sys_operations'              then 'TRUE'
                      when 'resource_limit'                    then 'TRUE'
                      when 'sec_case_sensitive_logon'          then 'TRUE'
                      when 'unified auditing'                  then 'TRUE'
                      else 'FALSE'
                   end expected_value
            from oracle_security_parameter p
            union all
            -- ---------- profile resource limits (per database) ----------
            -- A limit collected as DEFAULT is inherited from the DEFAULT profile,
            -- which is itself evaluated: judging it here would count it twice.
            select case upper(pr.resource_name)
                      when 'FAILED_LOGIN_ATTEMPTS'    then 'ORACLE_PRF_FAILED_LOGIN_ATTEMPTS'
                      when 'PASSWORD_LIFE_TIME'       then 'ORACLE_PRF_PASSWORD_LIFE_TIME'
                      when 'PASSWORD_LOCK_TIME'       then 'ORACLE_PRF_PASSWORD_LOCK_TIME'
                      when 'PASSWORD_GRACE_TIME'      then 'ORACLE_PRF_PASSWORD_GRACE_TIME'
                      when 'PASSWORD_REUSE_MAX'       then 'ORACLE_PRF_PASSWORD_REUSE_MAX'
                      when 'PASSWORD_REUSE_TIME'      then 'ORACLE_PRF_PASSWORD_REUSE_TIME'
                      when 'PASSWORD_VERIFY_FUNCTION' then 'ORACLE_PRF_PASSWORD_VERIFY_FUNCTION'
                      when 'SESSIONS_PER_USER'        then 'ORACLE_PRF_SESSIONS_PER_USER'
                      when 'INACTIVE_ACCOUNT_TIME'    then 'ORACLE_PRF_INACTIVE_ACCOUNT_TIME'
                   end,
                   pr.db_name, pr.pdb_name,
                   pr.profile || '/' || pr.resource_name,
                   case
                      when upper(pr.resource_name) = 'PASSWORD_VERIFY_FUNCTION'
                         then case when upper(nvl(trim(pr.limit_value), 'NULL')) = 'NULL' then 0 else 1 end
                      -- "at least" limits: UNLIMITED satisfies them
                      when upper(pr.resource_name) in ( 'PASSWORD_LOCK_TIME', 'PASSWORD_REUSE_MAX', 'PASSWORD_REUSE_TIME' )
                         then case when upper(trim(pr.limit_value)) = 'UNLIMITED' then 1
                                   when regexp_like(trim(pr.limit_value), '^[0-9]*\.?[0-9]+$')
                                    and to_number(trim(pr.limit_value)) >= case upper(pr.resource_name)
                                                                              when 'PASSWORD_LOCK_TIME' then 1
                                                                              when 'PASSWORD_REUSE_MAX' then 20
                                                                              else 365
                                                                           end
                                   then 1 else 0 end
                      -- "at most" limits: UNLIMITED breaks them
                      else case when upper(trim(pr.limit_value)) = 'UNLIMITED' then 0
                                when regexp_like(trim(pr.limit_value), '^[0-9]*\.?[0-9]+$')
                                 and to_number(trim(pr.limit_value)) <= case upper(pr.resource_name)
                                                                           when 'FAILED_LOGIN_ATTEMPTS' then 5
                                                                           when 'PASSWORD_LIFE_TIME'    then 90
                                                                           when 'PASSWORD_GRACE_TIME'   then 5
                                                                           when 'SESSIONS_PER_USER'     then 10
                                                                           else 120
                                                                        end
                                then 1 else 0 end
                   end,
                   pr.profile || '/' || pr.resource_name || '=' || nvl(trim(pr.limit_value), 'NULL'),
                   case upper(pr.resource_name)
                      when 'FAILED_LOGIN_ATTEMPTS'    then '<= 5'
                      when 'PASSWORD_LIFE_TIME'       then '<= 90'
                      when 'PASSWORD_LOCK_TIME'       then '>= 1 or UNLIMITED'
                      when 'PASSWORD_GRACE_TIME'      then '<= 5'
                      when 'PASSWORD_REUSE_MAX'       then '>= 20 or UNLIMITED'
                      when 'PASSWORD_REUSE_TIME'      then '>= 365 or UNLIMITED'
                      when 'PASSWORD_VERIFY_FUNCTION' then 'a verify function, not NULL'
                      when 'SESSIONS_PER_USER'        then '<= 10'
                      when 'INACTIVE_ACCOUNT_TIME'    then '<= 120'
                   end
            from oracle_security_profile pr
            where upper(nvl(trim(pr.limit_value), 'NULL')) <> 'DEFAULT'
            union all
            -- ---------- users on the DEFAULT profile (per database) ----------
            select 'ORACLE_NO_DEFAULT_PROFILE', dp.db_name, dp.pdb_name, dp.username,
                   case when dp.oracle_managed = 'Y' then 1
                        when upper(dp.profile) <> 'DEFAULT' then 1
                        else 0 end,
                   dp.username || ' on profile ' || dp.profile,
                   'a profile other than DEFAULT'
            from oracle_sec_default_profile dp
            union all
            -- ---------- audit policy (per database) ----------
            -- 12c+ reports ORA_CIS_RECOMMENDATIONS; 11g falls back to the classic
            -- audit options, one row per option, judged on the same rule.
            select 'ORACLE_AUDIT_CIS_POLICY_ON', a.db_name, a.pdb_name, a.audit_parameter,
                   case when a.audit_activated >= 1 then 1 else 0 end,
                   a.audit_parameter || '=' || a.audit_activated,
                   'enabled'
            from oracle_security_audit_enable a
            union all
            -- ---------- tablespace encryption (per database) ----------
            -- Scope of the norm: engine-managed tablespaces are exempt.
            select 'ORACLE_TABLESPACE_ENCRYPTED', ts.db_name, ts.pdb_name, ts.tablespace_name,
                   case when upper(nvl(ts.encrypted, 'NO')) = 'YES' then 1
                        when upper(ts.tablespace_name) in ( 'SYSTEM', 'SYSAUX' ) then 1
                        when upper(ts.tablespace_name) like 'TEMP%' then 1
                        when upper(ts.tablespace_name) like 'UNDO%' then 1
                        else 0 end,
                   ts.tablespace_name || ' (encrypted=' || nvl(ts.encrypted, 'NO') || ')',
                   'encrypted=YES'
            from oracle_security_tablespace ts
            union all
            -- ---------- password file members (per instance) ----------
            select 'ORACLE_ADMIN_PWFILE_SYS_ONLY', ap.db_name, cast(null as varchar2(200 char)), ap.username,
                   case when upper(ap.username) = 'SYS' then 1 else 0 end,
                   ap.username || ' in the password file',
                   'SYS only'
            from oracle_sec_admin_high_privs ap
            union all
            -- ---------- SQL*Net encryption (per instance) ----------
            -- Inverted absence: the collect only emits a row when the session
            -- reports an encryption service adapter, so a collected instance with
            -- no row is non-compliant rather than unknown.
            select 'ORACLE_NETWORK_ENCRYPTION_ON', wi.db_name, cast(null as varchar2(200 char)), '*',
                   case when ne.db_name is not null then 1 else 0 end,
                   nvl(ne.sqlnet_encryption, 'no encryption service adapter'),
                   'an encryption service adapter on the session'
            from w_inst wi
            left join oracle_sec_network_encryption ne
                   on ne.db_name = wi.db_name
                  and upper(nvl(trim(ne.sqlnet_encryption), 'EMPTY')) <> 'EMPTY'
            union all
            -- ---------- residual SYS.USER$MIG (per database) ----------
            select 'ORACLE_NO_USERMIG_TABLE', wd.db_name, wd.pdb_name, '*',
                   case when um.db_name is null then 1 else 0 end,
                   case when um.db_name is null then 'no SYS.USER$MIG table'
                        else 'SYS.USER$MIG present' end,
                   'absent'
            from w_db wd
            left join oracle_sec_usermig_tbl_exist um
                   on um.db_name = wd.db_name and um.pdb_name = wd.pdb_name
            union all
            -- ---------- deviation-only rules, per database ----------
            select d.rule_code, d.db_name, d.pdb_name, d.item_key, 0, d.observed_value,
                   r.expected_value
            from dev_db d
            join abs_db_rule r on r.rule_code = d.rule_code
            union all
            -- ... and the compliant row for every collected database that has none
            select r.rule_code, wd.db_name, wd.pdb_name, '*', 1, r.ok_value, r.expected_value
            from w_db wd
            cross join abs_db_rule r
            where not exists ( select 1 from dev_db d
                                where d.rule_code = r.rule_code
                                  and d.db_name = wd.db_name
                                  and d.pdb_name = wd.pdb_name )
            union all
            -- ---------- deviation-only rule, per instance ----------
            select d.rule_code, d.db_name, cast(null as varchar2(200 char)), d.item_key, 0,
                   d.observed_value, 'no account on its default password'
            from dev_inst d
            union all
            select 'ORACLE_NO_DEFAULT_PASSWORD', wi.db_name, cast(null as varchar2(200 char)), '*', 1,
                   'no account on its default password', 'no account on its default password'
            from w_inst wi
            where not exists ( select 1 from dev_inst d where d.db_name = wi.db_name )
         ) src
         join ref_control_rule rr on rr.rule_code = src.rule_code and rr.active = 1
         -- One instance per database name: a RAC database has several rows in
         -- oracle_databases and the security config is a property of the database,
         -- not of the instance that happened to answer.
         join ( select db_name, hostname, instance_name
                  from ( select od.db_name, od.hostname, od.instance_name,
                                row_number() over ( partition by od.db_name
                                                        order by od.instance_name ) rn
                           from oracle_databases od )
                 where rn = 1 ) od on od.db_name = src.db_name
         join dim_host ds on ds.platform = 'ORACLE' and ds.hostname = od.hostname
         join dim_instance di on di.host_id = ds.host_id and di.instance_name = od.instance_name
         left join dim_database dd on rr.entity_type = 'DATABASE'
              and dd.instance_id = di.instance_id
              and dd.db_name = case when src.pdb_name = 'NON CONTAINER' then src.db_name else src.pdb_name end
         where rr.entity_type <> 'DATABASE' or dd.database_id is not null
      ) s
      on ( f.rule_code = s.rule_code and f.entity_type = s.entity_type
           and f.entity_id = s.entity_id and f.item_key = s.item_key
           and f.snapshot_date = s.snapshot_date )
      when matched then update set
         f.is_compliant = s.is_compliant,
         f.observed_value = s.observed_value,
         f.expected_value = s.expected_value
      when not matched then
         insert ( rule_code, entity_type, entity_id, item_key, snapshot_date,
                  is_compliant, observed_value, expected_value )
         values ( s.rule_code, s.entity_type, s.entity_id, s.item_key, s.snapshot_date,
                  s.is_compliant, s.observed_value, s.expected_value );
   end load_findings_oracle_sec;


   -- ===============================================================
   -- Capacity findings (per storage unit, threshold-based)
   -- ===============================================================
   procedure load_findings_capacity ( p_snapshot_date in date ) is
   begin
      merge into fact_control_finding f
      using (
         select case dd.platform when 'ORACLE' then 'ORACLE_STORAGE_PCT_USED'
                                 else 'MSSQL_STORAGE_PCT_USED' end rule_code,
                'STORAGE' entity_type, sc.storage_unit_id entity_id, '*' item_key,
                p_snapshot_date snapshot_date,
                case when sc.pct_used >= t.crit_value then 0 else 1 end is_compliant,
                to_char(sc.pct_used) observed_value, to_char(t.crit_value) expected_value
         from fact_storage_capacity sc
         join dim_storage_unit su on su.storage_unit_id = sc.storage_unit_id
         join dim_database dd on dd.database_id = su.database_id
         join ref_threshold t on t.control_code = case dd.platform when 'ORACLE' then 'ORACLE_CAPACITY_SATURATION'
                                                                   else 'MSSQL_CAPACITY_SATURATION' end
              and t.metric = 'pct_used' and t.environment = '*'
         where sc.snapshot_date = p_snapshot_date and sc.pct_used is not null
      ) s
      on ( f.rule_code = s.rule_code and f.entity_type = s.entity_type
           and f.entity_id = s.entity_id and f.item_key = s.item_key
           and f.snapshot_date = s.snapshot_date )
      when matched then update set
         f.is_compliant = s.is_compliant,
         f.observed_value = s.observed_value, f.expected_value = s.expected_value
      when not matched then
         insert ( rule_code, entity_type, entity_id, item_key, snapshot_date,
                  is_compliant, observed_value, expected_value )
         values ( s.rule_code, s.entity_type, s.entity_id, s.item_key, s.snapshot_date,
                  s.is_compliant, s.observed_value, s.expected_value );
   end load_findings_capacity;


   -- ===============================================================
   -- Backup freshness findings
   -- ===============================================================
   -- Two grains, because the backups themselves have two grains: MSSQL backs up
   -- a database (from fact_backup), Oracle RMAN backs up a container (from
   -- fact_instance_backup). load_scoring rolls both up to the instance, so a
   -- single BACKUP score comes out either way.
   procedure load_findings_backup ( p_snapshot_date in date ) is
   begin
      merge into fact_control_finding f
      using (
         select 'MSSQL_BACKUP_FRESHNESS_SLA' rule_code,
                'DATABASE' entity_type, b.database_id entity_id, '*' item_key,
                p_snapshot_date snapshot_date,
                case when b.hours_since_backup > t.crit_value then 0 else 1 end is_compliant,
                to_char(b.hours_since_backup) observed_value, to_char(t.crit_value) expected_value
         from fact_backup b
         join dim_database dd on dd.database_id = b.database_id and dd.platform = 'MSSQL'
         join ref_threshold t on t.control_code = 'MSSQL_BACKUP_FRESHNESS'
              and t.metric = 'hours_since_full' and t.environment = '*'
         where b.snapshot_date = p_snapshot_date and b.hours_since_backup is not null
         union all
         select 'ORACLE_BACKUP_FRESHNESS_SLA',
                'INSTANCE', ib.instance_id, '*',
                p_snapshot_date,
                case when ib.hours_since_backup > t.crit_value then 0 else 1 end,
                to_char(ib.hours_since_backup), to_char(t.crit_value)
         from fact_instance_backup ib
         join dim_instance di on di.instance_id = ib.instance_id and di.platform = 'ORACLE'
         join ref_threshold t on t.control_code = 'ORACLE_BACKUP_FRESHNESS'
              and t.metric = 'hours_since_backup' and t.environment = '*'
         where ib.snapshot_date = p_snapshot_date and ib.hours_since_backup is not null
      ) s
      on ( f.rule_code = s.rule_code and f.entity_type = s.entity_type
           and f.entity_id = s.entity_id and f.item_key = s.item_key
           and f.snapshot_date = s.snapshot_date )
      when matched then update set
         f.is_compliant = s.is_compliant,
         f.observed_value = s.observed_value, f.expected_value = s.expected_value
      when not matched then
         insert ( rule_code, entity_type, entity_id, item_key, snapshot_date,
                  is_compliant, observed_value, expected_value )
         values ( s.rule_code, s.entity_type, s.entity_id, s.item_key, s.snapshot_date,
                  s.is_compliant, s.observed_value, s.expected_value );
   end load_findings_backup;


   -- ===============================================================
   -- Lifecycle findings (per instance, vendor EOS calendar)
   -- ===============================================================
   procedure load_findings_lifecycle ( p_snapshot_date in date ) is
   begin
      -- Joined on the MAJOR version (major.minor), which is what product_support
      -- is keyed on. An instance whose engine_version does not match any known
      -- release produces NO row rather than a fabricated verdict.
      --
      -- Extended support (ESU) keeps the instance compliant but raises
      -- is_norm_exception: it is a vendor condition, not a derogation granted by
      -- the SSI team, so it does NOT belong in ref_exception. Both origins feed
      -- fact_compliance.has_exception (see load_compliance).
      merge into fact_control_finding f
      using (
         select 'MSSQL_ENGINE_SUPPORTED' rule_code,
                'INSTANCE' entity_type,
                di.instance_id entity_id,
                '*' item_key,
                p_snapshot_date snapshot_date,
                case when p_snapshot_date <= ps.end_of_support_date then 1
                     when ps.end_of_ext_support_date is not null
                          and p_snapshot_date <= ps.end_of_ext_support_date then 1
                     else 0 end is_compliant,
                case when p_snapshot_date > ps.end_of_support_date
                          and ps.end_of_ext_support_date is not null
                          and p_snapshot_date <= ps.end_of_ext_support_date then 1
                     else 0 end is_norm_exception,
                substr( ps.display_name || ' (' || di.engine_version || '), '
                        || case when p_snapshot_date <= ps.end_of_support_date
                                   then 'standard support until ' || to_char(ps.end_of_support_date, 'YYYY-MM-DD')
                                when ps.end_of_ext_support_date is not null
                                   and p_snapshot_date <= ps.end_of_ext_support_date
                                   then 'standard support ended ' || to_char(ps.end_of_support_date, 'YYYY-MM-DD')
                                        || ', extended support until ' || to_char(ps.end_of_ext_support_date, 'YYYY-MM-DD')
                                else 'out of support since '
                                     || to_char(nvl(ps.end_of_ext_support_date, ps.end_of_support_date), 'YYYY-MM-DD')
                           end
                      , 1, 400 ) observed_value,
                'supported on ' || to_char(p_snapshot_date, 'YYYY-MM-DD') expected_value
         from dim_instance di
         join product_support ps
           on ps.product_company = 'MICROSOFT'
          and ps.product_type = 'MSSQL'
          and ps.product_version = substr( di.engine_version, 1, instr(di.engine_version, '.', 1, 2) - 1 )
         where di.platform = 'MSSQL'
           and instr(di.engine_version, '.', 1, 2) > 0
      ) s
      on ( f.rule_code = s.rule_code and f.entity_type = s.entity_type
           and f.entity_id = s.entity_id and f.item_key = s.item_key
           and f.snapshot_date = s.snapshot_date )
      when matched then update set
         f.is_compliant = s.is_compliant, f.is_norm_exception = s.is_norm_exception,
         f.observed_value = s.observed_value, f.expected_value = s.expected_value
      when not matched then
         insert ( rule_code, entity_type, entity_id, item_key, snapshot_date,
                  is_compliant, is_norm_exception, observed_value, expected_value )
         values ( s.rule_code, s.entity_type, s.entity_id, s.item_key, s.snapshot_date,
                  s.is_compliant, s.is_norm_exception, s.observed_value, s.expected_value );

      -- Patch level, against the same reference table. The major.minor pair is
      -- already fixed by the join, so the verdict rests on the build and revision
      -- numbers, compared as numbers: '15.0.900.1' sorts after '15.0.4470.1' as a
      -- string and would read as up to date.
      --
      -- An instance is judged only when its major version has a published patch
      -- level, and only when both builds parse into four parts; anything else
      -- produces no row rather than a fabricated verdict, consistent with the
      -- end-of-support rule above.
      merge into fact_control_finding f
      using (
         select 'MSSQL_ENGINE_PATCH_CURRENT' rule_code,
                'INSTANCE' entity_type,
                di.instance_id entity_id,
                '*' item_key,
                p_snapshot_date snapshot_date,
                case when to_number(regexp_substr(di.engine_version, '\d+', 1, 3))
                          > to_number(regexp_substr(ps.current_patch_level, '\d+', 1, 3))
                        then 1
                     when to_number(regexp_substr(di.engine_version, '\d+', 1, 3))
                          = to_number(regexp_substr(ps.current_patch_level, '\d+', 1, 3))
                      and to_number(regexp_substr(di.engine_version, '\d+', 1, 4))
                          >= to_number(regexp_substr(ps.current_patch_level, '\d+', 1, 4))
                        then 1
                     else 0 end is_compliant,
                substr( ps.display_name || ' (' || di.engine_version || '), latest '
                        || ps.current_patch_name || ' = ' || ps.current_patch_level
                      , 1, 400 ) observed_value,
                substr( 'build at or above ' || ps.current_patch_level, 1, 400 ) expected_value
         from dim_instance di
         join product_support ps
           on ps.product_company = 'MICROSOFT'
          and ps.product_type = 'MSSQL'
          and ps.product_version = substr( di.engine_version, 1, instr(di.engine_version, '.', 1, 2) - 1 )
         where di.platform = 'MSSQL'
           and instr(di.engine_version, '.', 1, 2) > 0
           and regexp_count(di.engine_version, '\d+') >= 4
           and regexp_count(ps.current_patch_level, '\d+') >= 4
      ) s
      on ( f.rule_code = s.rule_code and f.entity_type = s.entity_type
           and f.entity_id = s.entity_id and f.item_key = s.item_key
           and f.snapshot_date = s.snapshot_date )
      when matched then update set
         f.is_compliant = s.is_compliant,
         f.observed_value = s.observed_value, f.expected_value = s.expected_value
      when not matched then
         insert ( rule_code, entity_type, entity_id, item_key, snapshot_date,
                  is_compliant, observed_value, expected_value )
         values ( s.rule_code, s.entity_type, s.entity_id, s.item_key, s.snapshot_date,
                  s.is_compliant, s.observed_value, s.expected_value );
   end load_findings_lifecycle;


   procedure load_findings ( p_snapshot_date in date default trunc(sysdate) ) is
   begin
      load_findings_mssql_sec(p_snapshot_date);
      load_findings_oracle_sec(p_snapshot_date);
      load_findings_capacity(p_snapshot_date);
      load_findings_backup(p_snapshot_date);
      load_findings_lifecycle(p_snapshot_date);
   end load_findings;


   -- ===============================================================
   -- Exception resolution
   -- ===============================================================
   -- Rejouable on its own: granting a derogation and refreshing the day's score
   -- needs apply_exceptions + load_compliance + load_scoring, no new collect.
   --
   -- Only deviations are matched (is_compliant = 0). An exception sitting on an
   -- item that has become compliant again is deliberately left unattached, so
   -- the periodic review can tell a derogation that still covers something from
   -- one that can be revoked.
   procedure apply_exceptions ( p_snapshot_date in date default trunc(sysdate) ) is
   begin
      -- Start from a clean slate: an exception that expired, was deactivated or
      -- no longer matches must release the finding it used to cover.
      update fact_control_finding
         set exception_id = null
       where snapshot_date = p_snapshot_date
         and exception_id is not null;

      merge into fact_control_finding f
      using (
         select rid, exception_id
         from (
            select f2.rowid rid,
                   e.exception_id,
                   row_number() over (
                      partition by f2.rowid
                      order by case e.entity_type
                                  when 'STORAGE'  then 1
                                  when 'DATABASE' then 2
                                  when 'INSTANCE' then 3
                                  else 4
                               end,                 -- most specific level wins
                               e.start_date desc,   -- then the most recent grant
                               e.exception_id desc  -- deterministic tie-break
                   ) rn
            from fact_control_finding f2
            join v_entity_ancestry a
              on a.entity_type = f2.entity_type and a.entity_id = f2.entity_id
            join ref_exception e
              on e.rule_code = f2.rule_code
             -- The approval gate. Without it a derogation masked its deviation
             -- the moment it was typed, which would hand anyone with access to
             -- the screen a way to erase a finding from the score unreviewed.
             -- A draft, a rejected or a revoked derogation covers nothing.
             and e.status = 'APPROVED'
             and e.active = 1
             -- validity is judged on the snapshot date, never sysdate, so
             -- replaying an old snapshot does not apply today's derogations
             and p_snapshot_date >= e.start_date
             and p_snapshot_date <= nvl(e.end_date, p_snapshot_date)
             and ( e.item_key = '*' or e.item_key = f2.item_key )
             and ( e.observed_value = '*' or e.observed_value = f2.observed_value )
             -- cascade: the exception entity must be the finding entity or one
             -- of its ancestors
             and e.entity_id = case e.entity_type
                                  when 'HOST'     then a.host_id
                                  when 'INSTANCE' then a.instance_id
                                  when 'DATABASE' then a.database_id
                                  when 'STORAGE'  then a.storage_unit_id
                               end
            where f2.snapshot_date = p_snapshot_date
              and f2.is_compliant = 0
         )
         where rn = 1
      ) s
      on ( f.rowid = s.rid )
      when matched then update set f.exception_id = s.exception_id;
   end apply_exceptions;


   -- ===============================================================
   -- Roll-up into fact_compliance
   -- ===============================================================
   -- fact_compliance keeps exactly the grain, columns and semantics it had
   -- before the refactoring, so load_scoring and the APEX pages are untouched.
   -- It is now entirely derived from fact_control_finding: a single code path,
   -- so the verdict and the evidence behind it can no longer diverge.
   procedure load_compliance ( p_snapshot_date in date default trunc(sysdate) ) is
   begin
      merge into fact_compliance f
      using (
         select agg.control_code,
                agg.entity_type,
                agg.entity_id,
                p_snapshot_date snapshot_date,
                agg.is_compliant,
                agg.has_exception,
                case when agg.score_domain <> 'SECURITY' then agg.single_observed
                     -- SECURITY controls report how many items deviate and which
                     -- ones; the count always survives truncation, the item list
                     -- is evidence so mark it explicitly when it does not fit.
                     when agg.offending_count = 0 then '0'
                     when length( agg.offending_count || ' : ' || agg.offending_items ) <= 400
                        then agg.offending_count || ' : ' || agg.offending_items
                     else substr( agg.offending_count || ' : ' || agg.offending_items, 1, 397 ) || '...'
                end observed_value,
                case when agg.score_domain <> 'SECURITY' then agg.single_expected
                     else '0'
                end expected_value
         from (
            select rc.control_code,
                   rc.score_domain,
                   rc.entity_type,
                   case rc.entity_type
                      when 'HOST'     then a.host_id
                      when 'INSTANCE' then a.instance_id
                      when 'DATABASE' then a.database_id
                      when 'STORAGE'  then a.storage_unit_id
                   end entity_id,
                   -- an item covered by a derogation counts as compliant, which
                   -- is the policy the fleet has always been scored on
                   min(fcf.is_covered) is_compliant,
                   greatest( max(fcf.is_norm_exception),
                             max(case when fcf.exception_id is not null then 1 else 0 end) ) has_exception,
                   count( case when fcf.is_covered = 0 then 1 end ) offending_count,
                   listagg( case when fcf.is_covered = 0 then fcf.observed_value end, '; '
                            on overflow truncate '...' without count )
                      within group ( order by fcf.observed_value ) offending_items,
                   min(fcf.observed_value) single_observed,
                   min(fcf.expected_value) single_expected
            from fact_control_finding fcf
            join ref_control_rule rr on rr.rule_code = fcf.rule_code
            join ref_control rc on rc.control_code = rr.control_code and rc.active = 1
            join v_entity_ancestry a
              on a.entity_type = fcf.entity_type and a.entity_id = fcf.entity_id
            where fcf.snapshot_date = p_snapshot_date
            group by rc.control_code, rc.score_domain, rc.entity_type,
                     case rc.entity_type
                        when 'HOST'     then a.host_id
                        when 'INSTANCE' then a.instance_id
                        when 'DATABASE' then a.database_id
                        when 'STORAGE'  then a.storage_unit_id
                     end
         ) agg
         where agg.entity_id is not null
      ) s
      on ( f.control_code = s.control_code and f.entity_type = s.entity_type
           and f.entity_id = s.entity_id and f.snapshot_date = s.snapshot_date )
      when matched then update set
         f.is_compliant = s.is_compliant, f.has_exception = s.has_exception,
         f.observed_value = s.observed_value, f.expected_value = s.expected_value
      when not matched then
         insert ( control_code, entity_type, entity_id, snapshot_date, is_compliant, has_exception, observed_value, expected_value )
         values ( s.control_code, s.entity_type, s.entity_id, s.snapshot_date, s.is_compliant, s.has_exception, s.observed_value, s.expected_value );
   end load_compliance;


   -- ===============================================================
   -- Scoring aggregation (instance + environment)
   -- ===============================================================
   procedure load_scoring ( p_snapshot_date in date default trunc(sysdate) ) is
   begin
      -- Instance-level scores per domain
      merge into fact_scoring f
      using (
         with fc_inst as (
            -- roll every evaluated entity up to its instance
            select fc.control_code, fc.is_compliant,
                   case fc.entity_type
                      when 'INSTANCE' then fc.entity_id
                      when 'DATABASE' then dd.instance_id
                      when 'STORAGE'  then dsu.instance_id
                      when 'ACCOUNT'  then dac.instance_id
                   end instance_id
            from fact_compliance fc
            left join dim_database dd on fc.entity_type = 'DATABASE' and dd.database_id = fc.entity_id
            left join ( select su.storage_unit_id, d2.instance_id
                          from dim_storage_unit su join dim_database d2 on d2.database_id = su.database_id ) dsu
                   on fc.entity_type = 'STORAGE' and dsu.storage_unit_id = fc.entity_id
            left join ( select a.account_id, d3.instance_id
                          from dim_account a join dim_database d3 on d3.database_id = a.database_id ) dac
                   on fc.entity_type = 'ACCOUNT' and dac.account_id = fc.entity_id
            where fc.snapshot_date = p_snapshot_date
         ),
         cat as (
            select rc.platform, rc.score_domain, rc.category, fci.instance_id,
                   min(fci.is_compliant) cat_compliant
            from fc_inst fci
            join ref_control rc on rc.control_code = fci.control_code
            where fci.instance_id is not null
            group by rc.platform, rc.score_domain, rc.category, fci.instance_id
         ),
         inst_score as (
            select c.platform, c.score_domain, c.instance_id,
                   sum(w.weight * c.cat_compliant) score_value,
                   sum(w.weight) max_score
            from cat c
            join ref_scoring_weight w on w.platform = c.platform and w.score_domain = c.score_domain
                 and w.category = c.category and w.environment = '*'
            group by c.platform, c.score_domain, c.instance_id
         )
         select isc.platform,
                nvl(ds.environment, 'UNKNOWN') environment,
                isc.score_domain,
                'INSTANCE' entity_type,
                isc.instance_id entity_id,
                p_snapshot_date snapshot_date,
                isc.score_value,
                isc.max_score,
                case when isc.max_score = 0 then null
                     when 100 * isc.score_value / isc.max_score >= 90 then 'OK'
                     when 100 * isc.score_value / isc.max_score >= 70 then 'WARNING'
                     else 'CRITICAL' end status,
                -- left join: an instance whose collect date cannot be resolved
                -- keeps a NULL rather than a fabricated date, and the score is
                -- still produced -- it is dated, never suppressed.
                ecd.data_as_of,
                p_snapshot_date - ecd.data_as_of data_age_days
         from inst_score isc
         join dim_instance di on di.instance_id = isc.instance_id
         join dim_host ds on ds.host_id = di.host_id
         left join v_entity_collect_date ecd on ecd.instance_id = isc.instance_id
      ) s
      on ( f.platform = s.platform and f.environment = s.environment and f.score_domain = s.score_domain
           and f.entity_type = s.entity_type and f.entity_id = s.entity_id and f.snapshot_date = s.snapshot_date )
      when matched then update set
         f.score_value = s.score_value, f.max_score = s.max_score, f.status = s.status,
         f.data_as_of = s.data_as_of, f.data_age_days = s.data_age_days
      when not matched then
         insert ( platform, environment, score_domain, entity_type, entity_id, snapshot_date, score_value, max_score, status,
                  data_as_of, data_age_days )
         values ( s.platform, s.environment, s.score_domain, s.entity_type, s.entity_id, s.snapshot_date, s.score_value, s.max_score, s.status,
                  s.data_as_of, s.data_age_days );

      -- Environment-level aggregate (mean of instance percentages)
      merge into fact_scoring f
      using (
         select platform, environment, score_domain, 'ENVIRONMENT' entity_type, 0 entity_id,
                p_snapshot_date snapshot_date,
                round(avg(100 * score_value / nullif(max_score, 0)), 2) score_value,
                100 max_score,
                case when round(avg(100 * score_value / nullif(max_score, 0)), 2) >= 90 then 'OK'
                     when round(avg(100 * score_value / nullif(max_score, 0)), 2) >= 70 then 'WARNING'
                     else 'CRITICAL' end status,
                -- weakest link again: a fleet aggregate is only as current as its
                -- least recently collected instance, so the oldest date and the
                -- largest age win. The score itself stays an average.
                min(data_as_of) data_as_of,
                max(data_age_days) data_age_days
         from fact_scoring
         where snapshot_date = p_snapshot_date and entity_type = 'INSTANCE'
         group by platform, environment, score_domain
      ) s
      on ( f.platform = s.platform and f.environment = s.environment and f.score_domain = s.score_domain
           and f.entity_type = s.entity_type and f.entity_id = s.entity_id and f.snapshot_date = s.snapshot_date )
      when matched then update set
         f.score_value = s.score_value, f.max_score = s.max_score, f.status = s.status,
         f.data_as_of = s.data_as_of, f.data_age_days = s.data_age_days
      when not matched then
         insert ( platform, environment, score_domain, entity_type, entity_id, snapshot_date, score_value, max_score, status,
                  data_as_of, data_age_days )
         values ( s.platform, s.environment, s.score_domain, s.entity_type, s.entity_id, s.snapshot_date, s.score_value, s.max_score, s.status,
                  s.data_as_of, s.data_age_days );
   end load_scoring;


   procedure load_all ( p_snapshot_date in date default trunc(sysdate) ) is
   begin
      load_findings(p_snapshot_date);
      apply_exceptions(p_snapshot_date);
      load_compliance(p_snapshot_date);
      load_scoring(p_snapshot_date);
      commit;
   end load_all;

end pkg_dbinv_scoring;
/
