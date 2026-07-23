-- ============================================================================
-- V__005_create_scoring_etl.sql
-- ----------------------------------------------------------------------------
-- Scoring ETL package pkg_dbinv_scoring: evaluates controls into fact_compliance
-- and aggregates them into fact_scoring, driven by the parametric reference
-- tables (ref_control, ref_scoring_weight, ref_threshold).
--
-- Grain / approach:
--   * MSSQL SECURITY compliance is evaluated per SQL Server instance (matching
--     the legacy per-server verdict): a category is compliant for a server iff
--     no offending, non-excepted detail row exists. Rules are transcribed
--     verbatim from setup/inventory/dbInventory/bin/sql/mssql_scoring_data.sql.
--   * CAPACITY / BACKUP compliance is threshold-based (ref_threshold), evaluated
--     per storage unit / per database, for BOTH platforms.
--   * fact_scoring aggregates fact_compliance up to the instance (rolling every
--     entity to its instance) and to the environment, weighting each category by
--     ref_scoring_weight. Status bands: >=90 OK, >=70 WARNING, else CRITICAL.
--
-- NOT YET IMPLEMENTED (documented gaps, no policy fabricated here):
--   * ORACLE SECURITY compliance rules do not exist anywhere (neither code nor a
--     collected compliance_score); left unpopulated until the per-control policy
--     is defined. The generic aggregation will pick them up automatically once
--     fact_compliance rows are produced for them.
--   * LICENSING scoring: requires LMS logic; deferred.
--     (LIFECYCLE / out_of_support is now implemented, see
--     load_compliance_lifecycle: it matches dim_instance.engine_version to the
--     product_support EOS calendar on the major version.)
--
-- Assumptions (validate against real data):
--   * MSSQL security tables key on `servername`, joined to dim_instance on
--     instance_name (= hostname in this collection). If servername differs from
--     hostname, MSSQL scoring will not resolve an instance.
-- ============================================================================

create or replace package pkg_dbinv_scoring as

   procedure load_compliance ( p_snapshot_date in date default trunc(sysdate) );

   procedure load_scoring ( p_snapshot_date in date default trunc(sysdate) );

   procedure load_all ( p_snapshot_date in date default trunc(sysdate) );

end pkg_dbinv_scoring;
/

create or replace package body pkg_dbinv_scoring as

   -- ===============================================================
   -- MSSQL security compliance (per instance)
   -- ===============================================================
   procedure load_compliance_mssql_security ( p_snapshot_date in date ) is
   begin
      -- Per-row evaluation (is_ok / has_exc / item_label) is unioned first, then
      -- aggregated once per (control, server). Keeping the rule in a single
      -- per-row expression means the verdict and the evidence can never drift:
      -- is_compliant is still min(is_ok), exactly as the legacy script computed it.
      merge into fact_compliance f
      using (
         select agg.control_code,
                'INSTANCE' entity_type,
                di.instance_id entity_id,
                p_snapshot_date snapshot_date,
                agg.is_compliant,
                agg.has_exception,
                -- the count always survives truncation; the item list is evidence,
                -- so mark it explicitly when it does not fit in observed_value.
                case when agg.offending_count = 0 then '0'
                     when length( agg.offending_count || ' : ' || agg.offending_items ) <= 400
                        then agg.offending_count || ' : ' || agg.offending_items
                     else substr( agg.offending_count || ' : ' || agg.offending_items, 1, 397 ) || '...'
                end observed_value,
                '0' expected_value
         from (
            select r.control_code,
                   r.servername,
                   min(r.is_ok) is_compliant,
                   max(r.has_exc) has_exception,
                   count( case when r.is_ok = 0 then 1 end ) offending_count,
                   listagg( case when r.is_ok = 0 then r.item_label end, '; '
                            on overflow truncate '...' without count )
                      within group ( order by r.item_label ) offending_items
            from (
               -- configoptions
               select 'MSSQL_CONFIGOPTIONS' control_code, c.servername,
                      case when ( c.name = 'Ad Hoc Distributed Queries' and c.run_value = 0 )
                             or ( c.name = 'clr enabled' and c.run_value = 0 )
                             or ( c.name = 'cross db ownership chaining' and c.run_value = 0 )
                             or ( c.name = 'Database Mail XPs' and c.run_value = 0 )
                             or ( c.name = 'Ole Automation Procedures' and c.run_value = 0 )
                             or ( c.name = 'remote access' and c.run_value = 0 )
                             or ( c.name = 'remote admin connections' and c.run_value = 0 )
                             or ( c.name = 'scan for startup procs' and c.run_value = 0 )
                             or ( c.name = 'xp_cmdshell' and c.run_value = 0 )
                             or ( c.name = 'default trace enabled' and c.run_value = 1 )
                             or ( c.name = 'clr strict security' and c.run_value = 1 )
                             or exists ( select 1 from mssql_sec_cfgopt_exc x
                                          where x.servername = c.servername and x.name = c.name and x.run_value = c.run_value )
                           then 1 else 0 end is_ok,
                      case when exists ( select 1 from mssql_sec_cfgopt_exc x
                                          where x.servername = c.servername and x.name = c.name and x.run_value = c.run_value )
                           then 1 else 0 end has_exc,
                      c.name || '=' || c.run_value item_label
               from mssql_security_configoptions c
               union all
               -- dbproperties
               select 'MSSQL_DBPROPERTIES', d.servername,
                      case when ( d.db_name = 'msdb' and d.is_auto_close_on = 0 and d.is_trustworthy_on = 1 )
                             or ( d.is_auto_close_on = 0 and d.is_trustworthy_on = 0 )
                             or exists ( select 1 from mssql_sec_dbprops_exc x
                                          where x.servername = d.servername and x.db_name = d.db_name
                                            and x.is_auto_close_on = d.is_auto_close_on and x.is_trustworthy_on = d.is_trustworthy_on )
                           then 1 else 0 end,
                      case when exists ( select 1 from mssql_sec_dbprops_exc x
                                          where x.servername = d.servername and x.db_name = d.db_name
                                            and x.is_auto_close_on = d.is_auto_close_on and x.is_trustworthy_on = d.is_trustworthy_on )
                           then 1 else 0 end,
                      d.db_name || ' (auto_close=' || d.is_auto_close_on || ', trustworthy=' || d.is_trustworthy_on || ')'
               from mssql_security_dbproperties d
               union all
               -- auditlevel
               select 'MSSQL_AUDITLEVEL', a.servername,
                      case when a.auditlevel in ( 'All', 'Failed' )
                             or exists ( select 1 from mssql_sec_auditlvl_exc x
                                          where x.servername = a.servername and x.auditlevel = a.auditlevel )
                           then 1 else 0 end,
                      case when exists ( select 1 from mssql_sec_auditlvl_exc x
                                          where x.servername = a.servername and x.auditlevel = a.auditlevel )
                           then 1 else 0 end,
                      'auditlevel=' || a.auditlevel
               from mssql_security_auditlevel a
               union all
               -- encryption
               select 'MSSQL_ENCRYPTION', e.servername,
                      case when e.db_name in ( 'master', 'model', 'msdb', 'tempdb' )
                             or e.algorithm_desc in ( 'TRIPLE_DES', 'AES_128', 'AES_192', 'AES_256' )
                             or ( e.key_name = 'AES' and e.algorithm_desc = '256' )
                             or exists ( select 1 from mssql_hosts h
                                          where h.hostname = e.servername
                                            and ( lower(h.mssql_edition) like '%express%' or lower(h.mssql_edition) like '%developer%' ) )
                             or exists ( select 1 from mssql_sec_encryption_exc x
                                          where x.servername = e.servername and x.db_name = e.db_name and x.key_type = e.key_type
                                            and x.key_name = e.key_name and x.algorithm_desc = e.algorithm_desc )
                           then 1 else 0 end,
                      case when exists ( select 1 from mssql_sec_encryption_exc x
                                          where x.servername = e.servername and x.db_name = e.db_name and x.key_type = e.key_type
                                            and x.key_name = e.key_name and x.algorithm_desc = e.algorithm_desc )
                           then 1 else 0 end,
                      e.db_name || '/' || e.key_name || ' (' || e.algorithm_desc || ')'
               from mssql_security_encryption e
               union all
               -- groups
               select 'MSSQL_GROUPS', g.servername,
                      case when g.localgroupname = 'nogroup'
                             or exists ( select 1 from mssql_sec_groups_exc x
                                          where x.servername = g.servername and x.localgroupname = g.localgroupname )
                           then 1 else 0 end,
                      case when exists ( select 1 from mssql_sec_groups_exc x
                                          where x.servername = g.servername and x.localgroupname = g.localgroupname )
                           then 1 else 0 end,
                      g.localgroupname || ' (' || g.permission_name || ')'
               from mssql_security_groups g
               union all
               -- guestconnect
               select 'MSSQL_GUESTCONNECT', gc.servername,
                      case when ( gc.permission_name = 'no_permission' and gc.state_desc = 'no_permission' )
                             or exists ( select 1 from mssql_sec_guestconn_exc x
                                          where x.servername = gc.servername and x.db_name = gc.db_name
                                            and x.permission_name = gc.permission_name and x.state_desc = gc.state_desc )
                           then 1 else 0 end,
                      case when exists ( select 1 from mssql_sec_guestconn_exc x
                                          where x.servername = gc.servername and x.db_name = gc.db_name
                                            and x.permission_name = gc.permission_name and x.state_desc = gc.state_desc )
                           then 1 else 0 end,
                      gc.db_name || ' (' || gc.permission_name || ')'
               from mssql_security_guestconnect gc
               union all
               -- logins
               select 'MSSQL_LOGINS', l.servername,
                      case when l.login_name in ( 'sa', 'monitoring' ) then 1
                           when exists ( select 1 from mssql_sec_logins_exc x
                                          where x.servername = l.servername and x.login_name = l.login_name ) then 1
                           when l.is_sysadmin = 1 and l.is_expiration_checked = 0 then 0
                           when l.is_policy_checked = 1 then 1
                           when l.is_sysadmin = 1 and l.is_expiration_checked = 1 then 1
                           else 0 end,
                      case when exists ( select 1 from mssql_sec_logins_exc x
                                          where x.servername = l.servername and x.login_name = l.login_name )
                           then 1 else 0 end,
                      l.login_name
               from mssql_security_logins l
               union all
               -- orphanedusers
               select 'MSSQL_ORPHANEDUSERS', o.servername,
                      case when o.user_name = 'NoOrphanedUser'
                             or exists ( select 1 from mssql_sec_orphanusr_exc x
                                          where x.servername = o.servername and x.db_name = o.db_name and x.user_name = o.user_name )
                           then 1 else 0 end,
                      case when exists ( select 1 from mssql_sec_orphanusr_exc x
                                          where x.servername = o.servername and x.db_name = o.db_name and x.user_name = o.user_name )
                           then 1 else 0 end,
                      o.db_name || '/' || o.user_name
               from mssql_security_orphanedusers o
               union all
               -- publicpermission (no exception in the legacy rules)
               select 'MSSQL_PUBLICPERMISSION', pp.servername,
                      case when pp.permission_name = 'OnlyDefaultPermission' and pp.state_desc = 'OnlyDefaultPermission'
                           then 1 else 0 end,
                      0,
                      pp.db_name || '/' || pp.username || ' (' || pp.permission_name || ')'
               from mssql_sec_pubperm pp
               union all
               -- registryinfo
               select 'MSSQL_REGISTRYINFO', r.servername,
                      case when ( r.name = 'Hide Instance' and r.value = 1 )
                             or ( r.name = 'Hide Instance' and r.value = 0 and r.servername like 'XV%' )
                             or ( r.name = 'ForceEncryption' and r.value = 1 )
                             or ( r.name = 'NumErrorlogFiles' and r.value > 12 )
                             or ( r.name = 'TCP Port' and r.value = 1433 )
                             or exists ( select 1 from mssql_sec_reginfo_exc x
                                          where x.servername = r.servername and x.name = r.name )
                           then 1 else 0 end,
                      case when exists ( select 1 from mssql_sec_reginfo_exc x
                                          where x.servername = r.servername and x.name = r.name )
                           then 1 else 0 end,
                      r.name || '=' || r.value
               from mssql_security_registryinfo r
               union all
               -- sqlserveraudit
               select 'MSSQL_SQLSERVERAUDIT', sa.servername,
                      case when ( sa.auditactionname in ( 'AUDIT_CHANGE_GROUP', 'FAILED_LOGIN_GROUP', 'SUCCESSFUL_LOGIN_GROUP' )
                                  and sa.auditenabled = 1 and sa.auditspecificationenabled = 1 )
                             or exists ( select 1 from mssql_sec_srvaudit_exc x
                                          where x.servername = sa.servername and x.auditactionname = sa.auditactionname )
                           then 1 else 0 end,
                      case when exists ( select 1 from mssql_sec_srvaudit_exc x
                                          where x.servername = sa.servername and x.auditactionname = sa.auditactionname )
                           then 1 else 0 end,
                      sa.auditactionname
               from mssql_security_sqlserveraudit sa
            ) r
            group by r.control_code, r.servername
         ) agg
         join dim_instance di on di.platform = 'MSSQL' and di.instance_name = agg.servername
      ) s
      on ( f.control_code = s.control_code and f.entity_type = s.entity_type
           and f.entity_id = s.entity_id and f.snapshot_date = s.snapshot_date )
      when matched then update set
         f.is_compliant = s.is_compliant, f.has_exception = s.has_exception,
         f.observed_value = s.observed_value, f.expected_value = s.expected_value
      when not matched then
         insert ( control_code, entity_type, entity_id, snapshot_date, is_compliant, has_exception, observed_value, expected_value )
         values ( s.control_code, s.entity_type, s.entity_id, s.snapshot_date, s.is_compliant, s.has_exception, s.observed_value, s.expected_value );
   end load_compliance_mssql_security;

   -- ===============================================================
   -- Capacity compliance (per storage unit, threshold-based)
   -- ===============================================================
   procedure load_compliance_capacity ( p_snapshot_date in date ) is
   begin
      merge into fact_compliance f
      using (
         select case dd.platform when 'ORACLE' then 'ORACLE_CAPACITY_SATURATION'
                                  else 'MSSQL_CAPACITY_SATURATION' end control_code,
                'STORAGE' entity_type, sc.storage_unit_id entity_id, p_snapshot_date snapshot_date,
                case when sc.pct_used >= t.crit_value then 0 else 1 end is_compliant,
                0 has_exception,
                to_char(sc.pct_used) observed_value, to_char(t.crit_value) expected_value
         from fact_storage_capacity sc
         join dim_storage_unit su on su.storage_unit_id = sc.storage_unit_id
         join dim_database dd on dd.database_id = su.database_id
         join ref_threshold t on t.control_code = case dd.platform when 'ORACLE' then 'ORACLE_CAPACITY_SATURATION'
                                                                   else 'MSSQL_CAPACITY_SATURATION' end
              and t.metric = 'pct_used' and t.environment = '*'
         where sc.snapshot_date = p_snapshot_date and sc.pct_used is not null
      ) s
      on ( f.control_code = s.control_code and f.entity_type = s.entity_type
           and f.entity_id = s.entity_id and f.snapshot_date = s.snapshot_date )
      when matched then update set
         f.is_compliant = s.is_compliant, f.has_exception = s.has_exception,
         f.observed_value = s.observed_value, f.expected_value = s.expected_value
      when not matched then
         insert ( control_code, entity_type, entity_id, snapshot_date, is_compliant, has_exception, observed_value, expected_value )
         values ( s.control_code, s.entity_type, s.entity_id, s.snapshot_date, s.is_compliant, s.has_exception, s.observed_value, s.expected_value );
   end load_compliance_capacity;

   -- ===============================================================
   -- Backup freshness compliance (threshold-based)
   -- ===============================================================
   -- Two grains, because the backups themselves have two grains: MSSQL backs up a
   -- database (entity DATABASE, from fact_backup), Oracle RMAN backs up a container
   -- (entity INSTANCE, from fact_instance_backup). load_scoring rolls both up to the
   -- instance, so a single BACKUP score comes out either way.
   procedure load_compliance_backup ( p_snapshot_date in date ) is
   begin
      merge into fact_compliance f
      using (
         select 'MSSQL_BACKUP_FRESHNESS' control_code,
                'DATABASE' entity_type, b.database_id entity_id, p_snapshot_date snapshot_date,
                case when b.hours_since_backup > t.crit_value then 0 else 1 end is_compliant,
                0 has_exception,
                to_char(b.hours_since_backup) observed_value, to_char(t.crit_value) expected_value
         from fact_backup b
         join dim_database dd on dd.database_id = b.database_id and dd.platform = 'MSSQL'
         join ref_threshold t on t.control_code = 'MSSQL_BACKUP_FRESHNESS'
              and t.metric = 'hours_since_full' and t.environment = '*'
         where b.snapshot_date = p_snapshot_date and b.hours_since_backup is not null
         union all
         select 'ORACLE_BACKUP_FRESHNESS' control_code,
                'INSTANCE' entity_type, ib.instance_id entity_id, p_snapshot_date snapshot_date,
                case when ib.hours_since_backup > t.crit_value then 0 else 1 end is_compliant,
                0 has_exception,
                to_char(ib.hours_since_backup) observed_value, to_char(t.crit_value) expected_value
         from fact_instance_backup ib
         join dim_instance di on di.instance_id = ib.instance_id and di.platform = 'ORACLE'
         join ref_threshold t on t.control_code = 'ORACLE_BACKUP_FRESHNESS'
              and t.metric = 'hours_since_backup' and t.environment = '*'
         where ib.snapshot_date = p_snapshot_date and ib.hours_since_backup is not null
      ) s
      on ( f.control_code = s.control_code and f.entity_type = s.entity_type
           and f.entity_id = s.entity_id and f.snapshot_date = s.snapshot_date )
      when matched then update set
         f.is_compliant = s.is_compliant, f.has_exception = s.has_exception,
         f.observed_value = s.observed_value, f.expected_value = s.expected_value
      when not matched then
         insert ( control_code, entity_type, entity_id, snapshot_date, is_compliant, has_exception, observed_value, expected_value )
         values ( s.control_code, s.entity_type, s.entity_id, s.snapshot_date, s.is_compliant, s.has_exception, s.observed_value, s.expected_value );
   end load_compliance_backup;

   -- ===============================================================
   -- Lifecycle compliance (per instance, vendor EOS calendar)
   -- ===============================================================
   procedure load_compliance_lifecycle ( p_snapshot_date in date ) is
   begin
      -- Joined on the MAJOR version (major.minor), which is what product_support
      -- is keyed on. An instance whose engine_version does not match any known
      -- release produces NO row rather than a fabricated verdict.
      merge into fact_compliance f
      using (
         select 'MSSQL_OUT_OF_SUPPORT' control_code,
                'INSTANCE' entity_type,
                di.instance_id entity_id,
                p_snapshot_date snapshot_date,
                -- Extended support (ESU) is treated as an exception, mirroring the
                -- SECURITY controls: it keeps the instance compliant but flags it,
                -- so an instance surviving only on ESU stays visible without
                -- collapsing its lifecycle score. Hard failure = past extended too.
                case when p_snapshot_date <= ps.end_of_support_date then 1
                     when ps.end_of_ext_support_date is not null
                          and p_snapshot_date <= ps.end_of_ext_support_date then 1
                     else 0 end is_compliant,
                case when p_snapshot_date > ps.end_of_support_date
                          and ps.end_of_ext_support_date is not null
                          and p_snapshot_date <= ps.end_of_ext_support_date then 1
                     else 0 end has_exception,
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
      on ( f.control_code = s.control_code and f.entity_type = s.entity_type
           and f.entity_id = s.entity_id and f.snapshot_date = s.snapshot_date )
      when matched then update set
         f.is_compliant = s.is_compliant, f.has_exception = s.has_exception,
         f.observed_value = s.observed_value, f.expected_value = s.expected_value
      when not matched then
         insert ( control_code, entity_type, entity_id, snapshot_date, is_compliant, has_exception, observed_value, expected_value )
         values ( s.control_code, s.entity_type, s.entity_id, s.snapshot_date, s.is_compliant, s.has_exception, s.observed_value, s.expected_value );
   end load_compliance_lifecycle;

   procedure load_compliance ( p_snapshot_date in date default trunc(sysdate) ) is
   begin
      load_compliance_mssql_security(p_snapshot_date);
      load_compliance_capacity(p_snapshot_date);
      load_compliance_backup(p_snapshot_date);
      load_compliance_lifecycle(p_snapshot_date);
      -- ORACLE security compliance: intentionally not populated (rules undefined).
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
      load_compliance(p_snapshot_date);
      load_scoring(p_snapshot_date);
      commit;
   end load_all;

end pkg_dbinv_scoring;
/
