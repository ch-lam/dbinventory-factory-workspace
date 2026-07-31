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
--   * ORACLE SECURITY rules do not exist anywhere (neither code nor a collected
--     compliance_score); left unpopulated until the per-control policy is
--     defined. The generic aggregation picks them up as soon as rows appear.
--   * LICENSING scoring: requires LMS logic; deferred.
--
-- Assumptions (validated against real data on the dev database):
--   * MSSQL security tables key on `servername`, joined to dim_instance on
--     instance_name. Verified: 0 unmatched instance, 0 unmatched database.
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
   end load_findings_lifecycle;


   procedure load_findings ( p_snapshot_date in date default trunc(sysdate) ) is
   begin
      load_findings_mssql_sec(p_snapshot_date);
      load_findings_capacity(p_snapshot_date);
      load_findings_backup(p_snapshot_date);
      load_findings_lifecycle(p_snapshot_date);
      -- ORACLE security findings: intentionally not produced (rules undefined).
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
                     else 'CRITICAL' end status
         from inst_score isc
         join dim_instance di on di.instance_id = isc.instance_id
         join dim_host ds on ds.host_id = di.host_id
      ) s
      on ( f.platform = s.platform and f.environment = s.environment and f.score_domain = s.score_domain
           and f.entity_type = s.entity_type and f.entity_id = s.entity_id and f.snapshot_date = s.snapshot_date )
      when matched then update set
         f.score_value = s.score_value, f.max_score = s.max_score, f.status = s.status
      when not matched then
         insert ( platform, environment, score_domain, entity_type, entity_id, snapshot_date, score_value, max_score, status )
         values ( s.platform, s.environment, s.score_domain, s.entity_type, s.entity_id, s.snapshot_date, s.score_value, s.max_score, s.status );

      -- Environment-level aggregate (mean of instance percentages)
      merge into fact_scoring f
      using (
         select platform, environment, score_domain, 'ENVIRONMENT' entity_type, 0 entity_id,
                p_snapshot_date snapshot_date,
                round(avg(100 * score_value / nullif(max_score, 0)), 2) score_value,
                100 max_score,
                case when round(avg(100 * score_value / nullif(max_score, 0)), 2) >= 90 then 'OK'
                     when round(avg(100 * score_value / nullif(max_score, 0)), 2) >= 70 then 'WARNING'
                     else 'CRITICAL' end status
         from fact_scoring
         where snapshot_date = p_snapshot_date and entity_type = 'INSTANCE'
         group by platform, environment, score_domain
      ) s
      on ( f.platform = s.platform and f.environment = s.environment and f.score_domain = s.score_domain
           and f.entity_type = s.entity_type and f.entity_id = s.entity_id and f.snapshot_date = s.snapshot_date )
      when matched then update set
         f.score_value = s.score_value, f.max_score = s.max_score, f.status = s.status
      when not matched then
         insert ( platform, environment, score_domain, entity_type, entity_id, snapshot_date, score_value, max_score, status )
         values ( s.platform, s.environment, s.score_domain, s.entity_type, s.entity_id, s.snapshot_date, s.score_value, s.max_score, s.status );
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
