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
            -- msdb ships with TRUSTWORTHY ON and Microsoft requires it (SQL Agent,
            -- Database Mail): scope of the norm, not a derogation. msdb at 0 is
            -- unusual but not a security risk, so it is compliant too. The
            -- expected value says so, instead of contradicting the verdict.
            select 'MSSQL_DBPROP_TRUSTWORTHY_OFF', d.servername, d.db_name, '*',
                   case when d.is_trustworthy_on = 0 or d.db_name = 'msdb' then 1 else 0 end,
                   d.db_name || ' (trustworthy=' || d.is_trustworthy_on || ')'
                   || case when d.db_name = 'msdb' and d.is_trustworthy_on = 0
                           then ' - non standard, SQL Agent / Database Mail may fail' end,
                   case when d.db_name = 'msdb'
                        then 'msdb: is_trustworthy_on=1 required by Microsoft (SQL Agent, Database Mail)'
                        else 'is_trustworthy_on=0' end
            from mssql_security_dbproperties d
            union all
            -- Query Store must be READ_WRITE on user databases from SQL Server
            -- 2016 (major version 13). READ_ONLY means it is full and captures
            -- nothing any more. The collect leaves the state empty where it means
            -- nothing (older engine, system, offline or read-only database): no row.
            select 'MSSQL_DBPROP_QUERY_STORE_ON', d.servername, d.db_name, '*',
                   case when upper(d.query_store_state) = 'READ_WRITE' then 1 else 0 end,
                   d.db_name || ' (query_store=' || d.query_store_state || ')',
                   'query_store=READ_WRITE (SQL Server 2016+)'
            from mssql_security_dbproperties d
            where d.query_store_state is not null
              and d.db_name not in ( 'master', 'model', 'msdb', 'tempdb' )
              and exists ( select 1 from mssql_hosts h
                            where h.hostname = d.servername
                              and to_number(regexp_substr(h.mssql_product_version, '^[0-9]+')) >= 13 )
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
            -- The collect writes the sentinel NoGroup / NoPerm / NoState when no
            -- local group holds a server permission. Compared case-insensitively:
            -- matching 'nogroup' exactly made every clean server non-compliant.
            select 'MSSQL_GROUP_NO_LOCAL_PERMISSION', g.servername, cast(null as varchar2(50 char)), g.localgroupname,
                   case when upper(g.localgroupname) = 'NOGROUP' then 1 else 0 end,
                   case when upper(g.localgroupname) = 'NOGROUP' then 'no local group holds a server permission'
                        else g.localgroupname || ' (' || g.permission_name || ')' end,
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
            -- Mixed mode is accepted by the CHL norm: always compliant, but the
            -- row is kept so the mode of every instance stays on record.
            select 'MSSQL_AUTH_WINDOWS_ONLY', h.hostname, cast(null as varchar2(50 char)), '*',
                   1,
                   case when h.is_integrated_security_only = 1 then 'Windows authentication only'
                        else 'mixed mode (accepted by the CHL norm)' end,
                   'Windows only or mixed mode (both accepted)'
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
   -- The MSSQL collects emit SENTINEL rows ('NoOrphanedUser', 'NoGroup',
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
         -- Databases left in REQUESTED network encryption: the unencrypted-client
         -- audit table exists in at least one of their containers.
         net_audit as (
            select db_name,
                   listagg(distinct pdb_name, ', ') within group ( order by pdb_name ) containers
              from oracle_sec_net_enc_audit
             where record_type = 'AUDIT'
             group by db_name
         ),
         -- Their unencrypted clients seen in the 30 days before the snapshot --
         -- counted from the snapshot date, not from today, so a replayed snapshot
         -- keeps its verdicts. The audit table also keys on the OS user; it is
         -- folded here so the item_key (container, user, machine, program) stays
         -- unique.
         net_clients as (
            select db_name, pdb_name, username, machine, program,
                   listagg(distinct osuser, ', ') within group ( order by osuser ) osusers,
                   min(first_seen) first_seen,
                   max(last_seen) last_seen,
                   sum(logons) logons
              from ( select a.db_name, a.pdb_name,
                            nvl(a.username, '-') username, nvl(a.machine, '-') machine,
                            nvl(a.program, '-') program, nvl(a.osuser, '-') osuser,
                            case when validate_conversion(a.first_seen as date, 'YYYY-MM-DD HH24:MI:SS') = 1
                                 then to_date(a.first_seen, 'YYYY-MM-DD HH24:MI:SS') end first_seen,
                            case when validate_conversion(a.last_seen as date, 'YYYY-MM-DD HH24:MI:SS') = 1
                                 then to_date(a.last_seen, 'YYYY-MM-DD HH24:MI:SS') end last_seen,
                            case when validate_conversion(a.logon_count as number) = 1
                                 then to_number(a.logon_count) end logons
                       from oracle_sec_net_enc_audit a
                      where a.record_type = 'CLIENT' )
             where last_seen >= p_snapshot_date - 30
             group by db_name, pdb_name, username, machine, program
         ),
         -- Accounts Oracle ships and maintains itself: out of scope of the
         -- privilege and profile rules. This is the norm's own scope, not a
         -- derogation, so it must never reach the RSSI review list.
         ora_managed as (
            select db_name, pdb_name, username
              from oracle_sec_default_profile
             where oracle_managed = 'Y'
         ),
         -- Roles Oracle ships that hold high privileges by construction, as
         -- grantees: the CHL norm judges the accounts, not these roles. Same
         -- standing as ora_managed: scope of the norm, never a derogation.
         ora_role as (
            select '^(DBA|OGG.*CAPTURE|AVTUNE_PKG_ROLE|.*IMP_FULL_DATABASE|.*EXP_FULL_DATABASE'
                || '|AUDIT_ADMIN|AUDIT_SYSTEM|SCHEDULER_ADMIN|EM_EXPRESS_ALL|EM_EXPRESS_BASIC'
                || '|SYSUMF_ROLE|OEM_MONITOR|GSMUSER_ROLE|GSMADMIN_ROLE)$' pattern
              from dual
         ),
         -- Databases in pure Unified Auditing (v$option = TRUE): the traditional
         -- audit parameters (audit_trail, audit_sys_operations -- the latter
         -- deprecated from 21c) are ignored by the engine. They are written as
         -- compliant, saying why, rather than dropped: the trace shows the
         -- parameter was looked at. Mixed mode keeps them judged.
         unified_pure as (
            select distinct db_name
              from oracle_security_parameter
             where lower(parameter_name) = 'unified auditing'
               and upper(trim(parameter_value)) = 'TRUE'
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
               and not exists ( select 1 from ora_role r where regexp_like(sp.username, r.pattern) )
            union all
            -- SELECT_CATALOG_ROLE is accepted by the CHL norm (read access to the
            -- dictionary, not a privilege escalation): not a deviation here, and
            -- traced as a compliant row of its own (accepted-grants branch below).
            select 'ORACLE_HIGH_ROLE_PRIVS_GRANT', rp.db_name, rp.pdb_name,
                   rp.username || '/' || rp.privilege,
                   rp.username || ' holds ' || rp.privilege
              from oracle_sec_high_role_privs rp
             where not exists ( select 1 from ora_managed m
                                 where m.db_name = rp.db_name and m.pdb_name = rp.pdb_name
                                   and m.username = rp.username )
               and not exists ( select 1 from ora_role r where regexp_like(rp.username, r.pattern) )
               and rp.privilege <> 'SELECT_CATALOG_ROLE'
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
                   'no DBA, DELETE/EXECUTE_CATALOG or GSM role granted',
                   'no DBA, DELETE/EXECUTE_CATALOG or GSM role' from dual
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
                   case when up.db_name is not null
                         and lower(p.parameter_name) in ( 'audit_trail', 'audit_sys_operations' ) then 1
                   else
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
                   end
                   end is_ok,
                   p.parameter_name || '=' || nvl(trim(p.parameter_value), '<empty>')
                   || case when up.db_name is not null
                            and lower(p.parameter_name) in ( 'audit_trail', 'audit_sys_operations' )
                           then ' (ignored: pure Unified Auditing)' end observed_value,
                   case when up.db_name is not null
                         and lower(p.parameter_name) in ( 'audit_trail', 'audit_sys_operations' )
                        then 'not applicable under pure Unified Auditing'
                   else
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
                   end
                   end expected_value
            from oracle_security_parameter p
            left join unified_pure up on up.db_name = p.db_name
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
                      -- CHL standard: service, system and monitoring profiles may
                      -- keep a non-expiring password (CDB names, then non-CDB).
                      when upper(pr.resource_name) = 'PASSWORD_LIFE_TIME'
                       and upper(trim(pr.limit_value)) = 'UNLIMITED'
                       and upper(pr.profile) in ( 'C##SERVICE_PROFILE', 'C##SYSTEM_PROFILE', 'C##MONITORING',
                                                  'CHL_SERVICE_PROFILE', 'CHL_SYSTEM_PROFILE', 'MONITORING' )
                         then 1
                      -- "at most" limits: UNLIMITED breaks them
                      else case when upper(trim(pr.limit_value)) = 'UNLIMITED' then 0
                                when regexp_like(trim(pr.limit_value), '^[0-9]*\.?[0-9]+$')
                                 and to_number(trim(pr.limit_value)) <= case upper(pr.resource_name)
                                                                           when 'FAILED_LOGIN_ATTEMPTS' then 5
                                                                           when 'PASSWORD_LIFE_TIME'    then 90
                                                                           when 'PASSWORD_GRACE_TIME'   then 7
                                                                           when 'SESSIONS_PER_USER'     then 10
                                                                           else 120
                                                                        end
                                then 1 else 0 end
                   end,
                   pr.profile || '/' || pr.resource_name || '=' || nvl(trim(pr.limit_value), 'NULL'),
                   case upper(pr.resource_name)
                      when 'FAILED_LOGIN_ATTEMPTS'    then '<= 5'
                      when 'PASSWORD_LIFE_TIME'       then '<= 90 (UNLIMITED for service/system/monitoring profiles)'
                      when 'PASSWORD_LOCK_TIME'       then '>= 1 or UNLIMITED'
                      when 'PASSWORD_GRACE_TIME'      then '<= 7'
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
            -- ---------- SQL*Net encryption mode (per instance) ----------
            -- The audit table only exists on a database left in REQUESTED: its
            -- presence is the deviation, whatever it holds. A derogation is
            -- what documents why the database cannot go to REQUIRED.
            select 'ORACLE_NETWORK_ENCRYPTION_REQUIRED', wi.db_name, cast(null as varchar2(200 char)), '*',
                   case when na.db_name is null then 1 else 0 end,
                   case when na.db_name is null then 'no unencrypted-client audit table'
                        else substr('REQUESTED (audit table in ' || na.containers || ')', 1, 400) end,
                   'REQUIRED: no unencrypted-client audit table'
            from w_inst wi
            left join net_audit na on na.db_name = wi.db_name
            union all
            -- ---------- unencrypted clients (per instance, REQUESTED only) ----------
            -- One deviation per client; a database whose audit table holds no
            -- recent client gets one compliant row. Without the audit table the
            -- rule does not apply and emits nothing.
            select 'ORACLE_NETWORK_UNENCRYPTED_CLIENT', nc.db_name, cast(null as varchar2(200 char)),
                   substr(case when nc.pdb_name <> 'NON CONTAINER' then nc.pdb_name || ': ' end
                          || nc.username || '@' || nc.machine || ' (' || nc.program || ')', 1, 200),
                   0,
                   substr('last seen ' || to_char(nc.last_seen, 'YYYY-MM-DD HH24:MI')
                          || ', ' || nvl(to_char(nc.logons), '?') || ' logon(s) since '
                          || nvl(to_char(nc.first_seen, 'YYYY-MM-DD'), '?')
                          || ', OS user ' || nc.osusers, 1, 400),
                   'no client connecting without encryption'
            from net_clients nc
            where nc.db_name in ( select db_name from w_inst )
            union all
            select 'ORACLE_NETWORK_UNENCRYPTED_CLIENT', na.db_name, cast(null as varchar2(200 char)), '*', 1,
                   'no unencrypted client in the 30 days before the snapshot',
                   'no client connecting without encryption'
            from net_audit na
            where na.db_name in ( select db_name from w_inst )
              and not exists ( select 1 from net_clients nc where nc.db_name = na.db_name )
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
            -- ... and the accepted grants: SELECT_CATALOG_ROLE is within the CHL
            -- norm, so each grant is a compliant row naming its holder. Kept as a
            -- trace that the grant was seen and judged, not as a deviation.
            select distinct 'ORACLE_HIGH_ROLE_PRIVS_GRANT', rp.db_name, rp.pdb_name,
                   rp.username || '/' || rp.privilege, 1,
                   rp.username || ' holds SELECT_CATALOG_ROLE (accepted by the CHL norm)',
                   r.expected_value
            from oracle_sec_high_role_privs rp
            join abs_db_rule r on r.rule_code = 'ORACLE_HIGH_ROLE_PRIVS_GRANT'
            where rp.privilege = 'SELECT_CATALOG_ROLE'
              and not exists ( select 1 from ora_managed m
                                where m.db_name = rp.db_name and m.pdb_name = rp.pdb_name
                                  and m.username = rp.username )
              and not exists ( select 1 from ora_role r2 where regexp_like(rp.username, r2.pattern) )
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
   -- Oracle licensing findings (option and pack usage, LMS)
   -- ===============================================================
   -- Read from v_oracle_lms_usage, which carries the scope (perimeter licence)
   -- and the Multitenant recount; see the view header.
   --
   -- Shape: a non-compliant row per option in use (item_key = product), and a
   -- compliant '*' row for every judged instance without one -- the dev_db
   -- pattern of the security findings. The witness is the usage script itself:
   -- an instance without any row in oracle_lms was not read, and gets no
   -- verdict rather than a clean one.
   --
   -- A licence the CHL holds is not a rule exemption: it is a derogation on the
   -- finding, with the contract as evidence. observed_value therefore carries no
   -- date -- the last usage date moves with every weekly sample, and a
   -- derogation pinned to the observed value would fall off on the next one.
   procedure load_findings_licensing ( p_snapshot_date in date ) is
   begin
      merge into fact_control_finding f
      using (
         with
         u as (
            select *
              from v_oracle_lms_usage
             where in_scope = 1
               and instance_id is not null
         ),
         rules as (
            select r.*
              from ( select 'ORACLE_LMS_OPTION_IN_USE' rule_code,
                            'no option or pack in use without a licence' expected_value,
                            'no option or pack in use' ok_value
                       from dual
                     union all
                     select 'ORACLE_LMS_OPTION_PAST_USE',
                            'no past usage of an option or pack without a licence',
                            'no past usage of an option or pack'
                       from dual ) r
              join ref_control_rule rr on rr.rule_code = r.rule_code and rr.active = 1
         ),
         dev as (
            select case when usage_status in ( 'CURRENT_USAGE', 'PAST_OR_CURRENT_USAGE' )
                        then 'ORACLE_LMS_OPTION_IN_USE'
                        else 'ORACLE_LMS_OPTION_PAST_USE'
                   end rule_code,
                   instance_id,
                   product_name item_key,
                   substr(
                      case when upper(edition) like '%STANDARD%' and is_separate_product = 0
                           then 'Standard Edition, cannot be licensed: ' end
                      || product_label
                      || case when is_separate_product = 1 then ' (separate product)' end
                      || ': ' || usage_status
                      || case when containers is not null then ' in ' || containers end,
                      1, 400 ) observed_value
              from u
             where usage_status <> 'NO_USAGE'
         ),
         wit as ( select distinct instance_id from u )
         select d.rule_code, d.instance_id, d.item_key, 0 is_compliant,
                d.observed_value, r.expected_value
           from dev d
           join rules r on r.rule_code = d.rule_code
         union all
         select r.rule_code, w.instance_id, '*', 1, r.ok_value, r.expected_value
           from wit w
          cross join rules r
          where not exists ( select 1 from dev d
                              where d.rule_code = r.rule_code
                                and d.instance_id = w.instance_id )
      ) s
      on ( f.rule_code = s.rule_code and f.entity_type = 'INSTANCE'
           and f.entity_id = s.instance_id and f.item_key = s.item_key
           and f.snapshot_date = p_snapshot_date )
      when matched then update set
         f.is_compliant = s.is_compliant,
         f.observed_value = s.observed_value,
         f.expected_value = s.expected_value
      when not matched then
         insert ( rule_code, entity_type, entity_id, item_key, snapshot_date,
                  is_compliant, observed_value, expected_value )
         values ( s.rule_code, 'INSTANCE', s.instance_id, s.item_key, p_snapshot_date,
                  s.is_compliant, s.observed_value, s.expected_value );
   end load_findings_licensing;


   -- ===============================================================
   -- POSTGRESQL security findings
   -- ===============================================================
   -- A hybrid of the two procedures above, because the PostgreSQL collect is
   -- itself a hybrid:
   --
   --   * pg_settings and pg_roles are dumped whole, one row per evaluated item,
   --     so the compliant verdict falls out of the MERGE as it does for MSSQL;
   --   * predefined role memberships, weak pg_hba lines and PUBLIC grants are
   --     collected ONLY when they exist. Merged as they stand they would write
   --     is_compliant = 0 rows and nothing else, and a clean cluster would be
   --     indistinguishable from one that was never collected -- the same trap
   --     load_findings_oracle_sec works around, with the same anti-join.
   --
   -- The witness of "security was collected here" is postgres_security_parameter,
   -- and it is load-bearing: get_info_postgres_security.sh skips STANDBY
   -- instances, so a standby has no row there, gets no compliant witness, and
   -- therefore no SECURITY finding at all. That is the intended outcome, not an
   -- oversight -- a standby's configuration is the primary's, already judged.
   -- Note this is why w_db filters on that same witness: postgres_databases IS
   -- collected on a standby, so without the filter every standby database would
   -- report a compliant PG_PUBLIC_NO_CREATE it was never checked for.
   procedure load_findings_postgres_sec ( p_snapshot_date in date ) is
   begin
      merge into fact_control_finding f
      using (
         with
         -- Collected-entity witnesses (see header).
         w_inst as ( select distinct hostname from postgres_security_parameter ),
         w_db   as ( select distinct d.hostname, d.datname
                       from postgres_databases d
                      where exists ( select 1 from postgres_security_parameter p
                                      where p.hostname = d.hostname ) ),
         -- Deviations of the rules whose collect only reports what is wrong.
         -- Listed once, used twice: as the non-compliant rows, and as the
         -- anti-join that decides which instances get their compliant row.
         --
         -- postgres_sec_role_members.role_name is the MEMBER and member_of is the
         -- predefined role -- the collect selects m.rolname before r.rolname.
         dev_inst as (
            select 'PG_MEMBER_NO_SERVER_PROGRAM' rule_code, m.hostname,
                   m.member_of || ':' || m.role_name item_key,
                   m.role_name || ' is a member of ' || m.member_of observed_value
              from postgres_sec_role_members m
             where m.member_of = 'pg_execute_server_program'
            union all
            select 'PG_MEMBER_NO_SERVER_FILES', m.hostname,
                   m.member_of || ':' || m.role_name,
                   m.role_name || ' is a member of ' || m.member_of
              from postgres_sec_role_members m
             where m.member_of in ( 'pg_read_server_files', 'pg_write_server_files' )
            union all
            select 'PG_MEMBER_NO_WRITE_ALL_DATA', m.hostname,
                   m.member_of || ':' || m.role_name,
                   m.role_name || ' is a member of ' || m.member_of
              from postgres_sec_role_members m
             where m.member_of = 'pg_write_all_data'
            union all
            select 'PG_HBA_NO_TRUST', h.hostname,
                   to_char(h.line_number),
                   'line ' || h.line_number || ': ' || h.rule_type || ' ' || h.database
                      || ' ' || h.user_name || ' ' || h.address || ' ' || h.auth_method
              from postgres_security_hba_rules h
             where lower(h.auth_method) = 'trust'
            union all
            select 'PG_HBA_NO_WEAK_METHOD', h.hostname,
                   to_char(h.line_number),
                   'line ' || h.line_number || ': ' || h.rule_type || ' ' || h.database
                      || ' ' || h.user_name || ' ' || h.address || ' ' || h.auth_method
              from postgres_security_hba_rules h
             where lower(h.auth_method) in ( 'md5', 'password' )
         ),
         -- Same idea at database grain. Only CREATE is judged; CONNECT to PUBLIC
         -- is the engine default and is out of the norm's scope.
         dev_db as (
            select 'PG_PUBLIC_NO_CREATE' rule_code, p.hostname, p.datname,
                   'PUBLIC holds ' || p.privilege_type || ' on ' || p.datname observed_value
              from postgres_sec_db_privs p
             where p.grantee = 'PUBLIC' and upper(p.privilege_type) = 'CREATE'
         ),
         -- The rule codes driven by the anti-join, with the wording of their
         -- compliant row.
         abs_inst_rule as (
            select 'PG_MEMBER_NO_SERVER_PROGRAM' rule_code,
                   'no member of pg_execute_server_program' ok_value,
                   'no member of pg_execute_server_program' expected_value from dual
            union all
            select 'PG_MEMBER_NO_SERVER_FILES',
                   'no member of the server file roles',
                   'no member of pg_read_server_files or pg_write_server_files' from dual
            union all
            select 'PG_MEMBER_NO_WRITE_ALL_DATA',
                   'no member of pg_write_all_data',
                   'no member of pg_write_all_data' from dual
            union all
            select 'PG_HBA_NO_TRUST',
                   'no trust rule in pg_hba.conf', 'no auth_method trust' from dual
            union all
            select 'PG_HBA_NO_WEAK_METHOD',
                   'no md5 or password rule in pg_hba.conf',
                   'no auth_method md5 or password' from dual
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
            -- ---------- security settings (per instance) ----------
            -- The collect whitelists nine parameter names; the two that carry no
            -- settled norm (log_hostname, log_min_duration_statement) fall through
            -- the case to a NULL rule_code and are dropped by the join to
            -- ref_control_rule rather than silently counted as deviations.
            select case p.parameter_name
                      when 'ssl'                      then 'PG_PRM_SSL_ON'
                      when 'password_encryption'      then 'PG_PRM_PASSWORD_ENCRYPTION'
                      when 'log_connections'          then 'PG_PRM_LOG_CONNECTIONS'
                      when 'log_disconnections'       then 'PG_PRM_LOG_DISCONNECTIONS'
                      when 'log_statement'            then 'PG_PRM_LOG_STATEMENT'
                      when 'ssl_min_protocol_version' then 'PG_PRM_SSL_MIN_PROTOCOL'
                      when 'shared_preload_libraries' then 'PG_PRM_PGAUDIT_LOADED'
                   end rule_code,
                   p.hostname,
                   cast(null as varchar2(100 char)) datname,
                   '*' item_key,
                   case p.parameter_name
                      when 'ssl'                      then case when lower(p.parameter_value) = 'on' then 1 else 0 end
                      when 'password_encryption'      then case when lower(p.parameter_value) = 'scram-sha-256' then 1 else 0 end
                      when 'log_connections'          then case when lower(p.parameter_value) = 'on' then 1 else 0 end
                      when 'log_disconnections'       then case when lower(p.parameter_value) = 'on' then 1 else 0 end
                      when 'log_statement'            then case when lower(p.parameter_value) in ( 'ddl', 'mod', 'all' ) then 1 else 0 end
                      when 'ssl_min_protocol_version' then case when upper(p.parameter_value) in ( 'TLSV1.2', 'TLSV1.3' ) then 1 else 0 end
                      when 'shared_preload_libraries' then case when lower(p.parameter_value) like '%pgaudit%' then 1 else 0 end
                   end is_ok,
                   p.parameter_name || '=' || nvl(p.parameter_value, '(empty)') observed_value,
                   case p.parameter_name
                      when 'ssl'                      then 'on'
                      when 'password_encryption'      then 'scram-sha-256'
                      when 'log_connections'          then 'on'
                      when 'log_disconnections'       then 'on'
                      when 'log_statement'            then 'ddl, mod or all'
                      when 'ssl_min_protocol_version' then 'TLSv1.2 or above'
                      when 'shared_preload_libraries' then 'pgaudit loaded'
                   end expected_value
              from postgres_security_parameter p
            union all
            -- ---------- role attributes (per role) ----------
            -- postgres owns the cluster and monitoring is the collector: both are
            -- privileged by construction. Excluding them is the norm's own scope,
            -- so they must never appear in the list the RSSI team reviews.
            select 'PG_ROLE_NO_EXTRA_SUPERUSER', r.hostname, cast(null as varchar2(100 char)), r.rolname,
                   case when r.rolsuper = 'Y' then 0 else 1 end,
                   r.rolname || ' rolsuper=' || r.rolsuper,
                   'not a superuser'
              from postgres_security_roles r
             where r.rolname not in ( 'postgres', 'monitoring' )
            union all
            -- A superuser bypasses RLS whatever rolbypassrls says; judging it here
            -- too would count one deviation twice under two different rules.
            select 'PG_ROLE_NO_BYPASSRLS', r.hostname, cast(null as varchar2(100 char)), r.rolname,
                   case when r.rolbypassrls = 'Y' then 0 else 1 end,
                   r.rolname || ' rolbypassrls=' || r.rolbypassrls,
                   'does not bypass row level security'
              from postgres_security_roles r
             where r.rolsuper = 'N'
            union all
            select 'PG_ROLE_REPLICATION_LIMITED', r.hostname, cast(null as varchar2(100 char)), r.rolname,
                   case when r.rolreplication = 'Y' then 0 else 1 end,
                   r.rolname || ' rolreplication=' || r.rolreplication,
                   'no replication attribute'
              from postgres_security_roles r
             where r.rolname not in ( 'postgres', 'monitoring' )
            union all
            -- ---------- deviation-only rules, per instance ----------
            select d.rule_code, d.hostname, cast(null as varchar2(100 char)), d.item_key, 0,
                   d.observed_value, r.expected_value
              from dev_inst d
              join abs_inst_rule r on r.rule_code = d.rule_code
            union all
            -- ... and the compliant row for every collected instance that has none
            select r.rule_code, wi.hostname, cast(null as varchar2(100 char)), '*', 1,
                   r.ok_value, r.expected_value
              from w_inst wi
             cross join abs_inst_rule r
             where not exists ( select 1 from dev_inst d
                                 where d.rule_code = r.rule_code
                                   and d.hostname = wi.hostname )
            union all
            -- ---------- deviation-only rule, per database ----------
            select d.rule_code, d.hostname, d.datname, '*', 0,
                   d.observed_value, 'no CREATE granted to PUBLIC'
              from dev_db d
            union all
            select 'PG_PUBLIC_NO_CREATE', wd.hostname, wd.datname, '*', 1,
                   'no CREATE granted to PUBLIC', 'no CREATE granted to PUBLIC'
              from w_db wd
             where not exists ( select 1 from dev_db d
                                 where d.hostname = wd.hostname
                                   and d.datname = wd.datname )
         ) src
         join ref_control_rule rr on rr.rule_code = src.rule_code and rr.active = 1
         -- hostname is both the host and the instance name on PostgreSQL: the
         -- collect never carries the port into the data (see load_dim_host).
         join dim_host ds on ds.platform = 'POSTGRES' and ds.hostname = src.hostname
         join dim_instance di on di.host_id = ds.host_id and di.instance_name = src.hostname
         left join dim_database dd on rr.entity_type = 'DATABASE'
              and dd.instance_id = di.instance_id
              and dd.db_name = src.datname
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
   end load_findings_postgres_sec;


   -- ===============================================================
   -- Capacity findings (threshold-based)
   -- ===============================================================
   -- Two shapes, because "running out" does not mean the same thing on the three
   -- engines. Oracle and MSSQL saturate a storage unit against a ceiling the
   -- database itself carries (tablespace maxbytes, file max_size), so the verdict
   -- is a pct_used per storage unit. PostgreSQL has no such ceiling and no way to
   -- read the filesystem from SQL, so its hard limit is transaction id
   -- wraparound, judged per database. See load_fact_storage_capacity.
   procedure load_findings_capacity ( p_snapshot_date in date ) is
   begin
      merge into fact_control_finding f
      using (
         -- The platform is spelled out rather than defaulted through an `else`:
         -- PostgreSQL storage units live in the same table with pct_used null, and
         -- an `else 'MSSQL_...'` would label them MSSQL the day that column stops
         -- being null.
         select case dd.platform when 'ORACLE' then 'ORACLE_STORAGE_PCT_USED'
                                 when 'MSSQL'  then 'MSSQL_STORAGE_PCT_USED' end rule_code,
                'STORAGE' entity_type, sc.storage_unit_id entity_id, '*' item_key,
                p_snapshot_date snapshot_date,
                case when sc.pct_used >= t.crit_value then 0 else 1 end is_compliant,
                to_char(sc.pct_used) observed_value, to_char(t.crit_value) expected_value
         from fact_storage_capacity sc
         join dim_storage_unit su on su.storage_unit_id = sc.storage_unit_id
         join dim_database dd on dd.database_id = su.database_id
         join ref_threshold t on t.control_code = case dd.platform when 'ORACLE' then 'ORACLE_CAPACITY_SATURATION'
                                                                   when 'MSSQL'  then 'MSSQL_CAPACITY_SATURATION' end
              and t.metric = 'pct_used' and t.environment = '*'
         where sc.snapshot_date = p_snapshot_date and sc.pct_used is not null
           and dd.platform in ( 'ORACLE', 'MSSQL' )
         union all
         -- PostgreSQL: transaction id wraparound headroom. 2147483648 = 2^31, the
         -- point at which the cluster refuses writes until a VACUUM FREEZE has run.
         -- Read straight from the collect rather than from a fact table: it is a
         -- property of the database as collected, not a measure of a storage unit.
         select 'PG_XID_WRAPAROUND', 'DATABASE', dd.database_id, '*',
                p_snapshot_date,
                case when round(100 * p.xid_age / 2147483648, 2) >= t.crit_value then 0 else 1 end,
                to_char(round(100 * p.xid_age / 2147483648, 2)), to_char(t.crit_value)
         from postgres_databases p
         join dim_host ds on ds.platform = 'POSTGRES' and ds.hostname = p.hostname
         join dim_instance di on di.host_id = ds.host_id and di.instance_name = p.hostname
         join dim_database dd on dd.instance_id = di.instance_id and dd.db_name = p.datname
         join ref_threshold t on t.control_code = 'POSTGRES_CAPACITY_SATURATION'
              and t.metric = 'pct_xid_used' and t.environment = '*'
         -- A collect predating the xid_age column leaves it null: no verdict
         -- rather than a fabricated 0 %.
         where p.xid_age is not null
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
         union all
         -- PostgreSQL, also at instance grain: the WAL stream belongs to the
         -- cluster. hours_since_backup dates the last ARCHIVED SEGMENT, not a
         -- backup -- no pgBackRest/Barman catalogue is collected, so this is a
         -- necessary condition for point-in-time recovery and nothing more.
         select 'PG_BACKUP_FRESHNESS_SLA',
                'INSTANCE', ib.instance_id, '*',
                p_snapshot_date,
                case when ib.hours_since_backup > t.crit_value then 0 else 1 end,
                to_char(ib.hours_since_backup), to_char(t.crit_value)
         from fact_instance_backup ib
         join dim_instance di on di.instance_id = ib.instance_id and di.platform = 'POSTGRES'
         join ref_threshold t on t.control_code = 'POSTGRES_BACKUP_FRESHNESS'
              and t.metric = 'hours_since_archived' and t.environment = '*'
         where ib.snapshot_date = p_snapshot_date and ib.hours_since_backup is not null
         union all
         -- Whether archiving is switched on at all. A control of its own rather
         -- than a second rule under the freshness control: rolled into one,
         -- "archiving is off" would be the single verdict reported and would mask
         -- a stale archive on the clusters that do archive.
         select 'PG_ARCHIVE_MODE_ON',
                'INSTANCE', e.instance_id, '*',
                p_snapshot_date,
                case when lower(e.archive_mode) in ( 'on', 'always' ) then 1 else 0 end,
                'archive_mode=' || e.archive_mode, 'on'
         from ext_postgres_instance e
         join dim_instance di on di.instance_id = e.instance_id and di.platform = 'POSTGRES'
         where e.archive_mode is not null
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
      -- Oracle end of support, on the same shape as SQL Server -- Extended
      -- Support keeps the instance compliant and raises is_norm_exception,
      -- because it is a vendor condition and not a derogation granted here.
      --
      -- The cut is the leading digits, NOT the major.minor of the block above:
      -- an Oracle banner reads 19.20.0.0.0 and the support dates belong to the
      -- release, not to the release update. Copying the SQL Server substr would
      -- have looked for '19.20' in product_support and judged nothing at all.
      --
      -- An instance whose release is absent from the calendar produces NO row,
      -- as everywhere else here, rather than a fabricated verdict.
      merge into fact_control_finding f
      using (
         select 'ORACLE_ENGINE_SUPPORTED' rule_code,
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
                                   then 'premier support until ' || to_char(ps.end_of_support_date, 'YYYY-MM-DD')
                                when ps.end_of_ext_support_date is not null
                                   and p_snapshot_date <= ps.end_of_ext_support_date
                                   then 'premier support ended ' || to_char(ps.end_of_support_date, 'YYYY-MM-DD')
                                        || ', extended support until ' || to_char(ps.end_of_ext_support_date, 'YYYY-MM-DD')
                                else 'out of support since '
                                     || to_char(nvl(ps.end_of_ext_support_date, ps.end_of_support_date), 'YYYY-MM-DD')
                           end
                      , 1, 400 ) observed_value,
                'supported on ' || to_char(p_snapshot_date, 'YYYY-MM-DD') expected_value
         from dim_instance di
         join product_support ps
           on ps.product_company = 'ORACLE'
          and ps.product_type = 'ORACLE'
          and ps.product_version = regexp_substr( di.engine_version, '^\d+' )
         where di.platform = 'ORACLE'
           and regexp_like( di.engine_version, '^\d+' )
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

      -- PostgreSQL end of support.
      --
      -- The major version is a SINGLE component since release 10 (16.4 is major
      -- 16, minor 4), so the major.minor cut used for SQL Server above must NOT be
      -- copied here: it would look for a product_version of '16.4' and match
      -- nothing, silently judging no instance at all. regexp_substr on the leading
      -- digits is the right cut, and it also copes with the 'x.y' shape of the
      -- pre-10 releases by reading their first component.
      --
      -- There is no community extended support, so end_of_ext_support_date is null
      -- throughout and is_norm_exception can only ever be 0 -- the ESU branch is
      -- inert by construction, not by omission.
      merge into fact_control_finding f
      using (
         select 'PG_ENGINE_SUPPORTED' rule_code,
                'INSTANCE' entity_type,
                di.instance_id entity_id,
                '*' item_key,
                p_snapshot_date snapshot_date,
                case when p_snapshot_date <= ps.end_of_support_date then 1 else 0 end is_compliant,
                substr( ps.display_name || ' (' || di.engine_version || '), '
                        || case when p_snapshot_date <= ps.end_of_support_date
                                   then 'community support until ' || to_char(ps.end_of_support_date, 'YYYY-MM-DD')
                                else 'out of support since ' || to_char(ps.end_of_support_date, 'YYYY-MM-DD')
                           end
                      , 1, 400 ) observed_value,
                'supported on ' || to_char(p_snapshot_date, 'YYYY-MM-DD') expected_value
         from dim_instance di
         join product_support ps
           on ps.product_company = 'POSTGRESQL'
          and ps.product_type = 'POSTGRES'
          and ps.product_version = regexp_substr( di.engine_version, '^\d+' )
         where di.platform = 'POSTGRES'
           and regexp_like( di.engine_version, '^\d+' )
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
      load_findings_postgres_sec(p_snapshot_date);
      load_findings_licensing(p_snapshot_date);
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
      -- The instant validity is judged at: the time of the run for today's
      -- snapshot, the last second of the day for a past one -- so replaying an
      -- old snapshot still never applies a derogation granted later. A renewal
      -- starts to the second of its approval, and is honoured from that second.
      l_ref date := least( sysdate, p_snapshot_date + 1 - 1/86400 );
   begin
      -- Start from a clean slate: an exception that expired, was deactivated or
      -- no longer matches must release the finding it used to cover.
      update fact_control_finding
         set exception_id = null
       where snapshot_date = p_snapshot_date
         and exception_id is not null;

      -- The scope match itself (rule, cascade, item, observed value) lives in
      -- v_exception_finding_match, shared with v_exception_review: the review
      -- page must never disagree with the scoring on what a derogation designates.
      merge into fact_control_finding f
      using (
         select rid, exception_id
         from (
            select m.finding_rowid rid,
                   m.exception_id,
                   row_number() over (
                      partition by m.finding_rowid
                      order by m.specificity,         -- most specific level wins
                               e.start_date desc,     -- then the most recent grant
                               e.exception_id desc    -- deterministic tie-break
                   ) rn
            from v_exception_finding_match m
            join ref_exception e
              on e.exception_id = m.exception_id
             -- The approval gate. Without it a derogation masked its deviation
             -- the moment it was typed, which would hand anyone with access to
             -- the screen a way to erase a finding from the score unreviewed.
             -- A draft, a rejected or a revoked derogation covers nothing.
             --
             -- A SUPERSEDED one keeps covering until its renewal comes into
             -- force, to the second: the handover happens at the instant the
             -- renewal starts, so the finding never reopens in between.
             and ( e.status = 'APPROVED'
                   or ( e.status = 'SUPERSEDED'
                        and not exists ( select 1
                                           from ref_exception s
                                          where s.replaces_exception_id = e.exception_id
                                            and s.status in ( 'APPROVED', 'SUPERSEDED' )
                                            and s.start_date <= l_ref ) ) )
             and e.active = 1
             -- start judged at l_ref (to the second), end at the day of the
             -- snapshot: end_date is a last day of validity
             and e.start_date <= l_ref
             and p_snapshot_date <= nvl(e.end_date, p_snapshot_date)
            where m.snapshot_date = p_snapshot_date
              and m.is_compliant = 0
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
