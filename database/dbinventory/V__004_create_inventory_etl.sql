-- ============================================================================
-- V__004_create_inventory_etl.sql
-- ----------------------------------------------------------------------------
-- ETL package pkg_dbinv_inventory: populates the dimensional application model
-- (V__002) from the collection/staging tables (V__001). Inventory + capacity
-- only; compliance/scoring lives in a separate package (V__005).
--
-- Design:
--   * Dimensions are MERGEd by their natural UNIQUE key (insert/update, never
--     delete - no SCD, current state only).
--   * Facts are MERGEd on their grain PK (entity id(s) + snapshot_date), so a
--     re-run for the same day overwrites that day's snapshot (idempotent).
--   * snapshot_date is a single value for the whole run (default trunc(sysdate)).
--
-- MSSQL host/instance separation (validated against real data):
--   * mssql_hosts.collect_target = machine FQDN (prepended by get_info_mssql.sh);
--     mssql_hosts.hostname = @@SERVERNAME = instance identity (e.g. MACHINE/INSTANCE).
--     dim_host is keyed on collect_target (a machine hosting several instances
--     shares one host); dim_instance.instance_name = hostname.
--   * MSSQL environment/license come from mssql_collect_list, joined on
--     collect_target (= the FQDN) with active = 1.
-- Oracle join notes:
--   * Oracle storage/metrics/parameter link to a database through
--     oracle_databases (db_name) -> (hostname, instance_name) -> database (pdb_name).
--   * Coherent refuge value: the collection emits the db_name into the pdb_name
--     field for non-CDB databases (real PDB name for CDB), so dd.db_name = pdb_name
--     resolves uniformly. is_pdb=0 (ext_oracle_database) keeps the non-PDB distinction.
--   * oracle_metrics_cpu_memory only carries pdb_name; matched on
--     dim_database.db_name = pdb_name (unique per instance after the refuge fix).
--   * oracle_backup carries the container db_name (v$database.name), so it resolves
--     to an instance through oracle_databases and lands in fact_instance_backup.
-- ============================================================================

create or replace package pkg_dbinv_inventory as

   -- Tolerant date parser for varchar-typed staging timestamps.
   function safe_to_date ( p_text in varchar2 ) return date;

   procedure load_dimensions;

   procedure load_facts ( p_snapshot_date in date default trunc(sysdate) );

   procedure load_all ( p_snapshot_date in date default trunc(sysdate) );

end pkg_dbinv_inventory;
/

create or replace package body pkg_dbinv_inventory as

   -- ---------------------------------------------------------------
   function safe_to_date ( p_text in varchar2 ) return date is
   begin
      if p_text is null then
         return null;
      end if;
      begin
         return to_date(p_text, 'YYYY-MM-DD HH24:MI:SS');
      exception
         when others then null;
      end;
      begin
         return to_date(p_text, 'YYYY-MM-DD');
      exception
         when others then null;
      end;
      return null;
   end safe_to_date;

   -- ===============================================================
   -- Dimension loaders
   -- ===============================================================

   procedure load_dim_date ( p_snapshot_date in date ) is
   begin
      merge into dim_date d
      using ( select to_number(to_char(p_snapshot_date, 'YYYYMMDD')) date_id,
                     trunc(p_snapshot_date) cal_date,
                     extract(year from p_snapshot_date) cal_year,
                     to_number(to_char(p_snapshot_date, 'Q')) cal_quarter,
                     extract(month from p_snapshot_date) cal_month,
                     rtrim(to_char(p_snapshot_date, 'Month', 'NLS_DATE_LANGUAGE=ENGLISH')) month_name,
                     extract(day from p_snapshot_date) cal_day,
                     to_number(to_char(p_snapshot_date, 'D')) day_of_week,
                     case when trunc(p_snapshot_date) = trunc(last_day(p_snapshot_date)) then 1 else 0 end is_month_end
                from dual ) s
      on ( d.date_id = s.date_id )
      when not matched then
         insert ( date_id, cal_date, cal_year, cal_quarter, cal_month, month_name, cal_day, day_of_week, is_month_end )
         values ( s.date_id, s.cal_date, s.cal_year, s.cal_quarter, s.cal_month, s.month_name, s.cal_day, s.day_of_week, s.is_month_end );
   end load_dim_date;

   procedure load_dim_host is
   begin
      -- Oracle: environment/license carried directly by oracle_hosts
      merge into dim_host d
      using ( select 'ORACLE' platform, hostname,
                     max(os_type) os_type, max(num_cpus) num_cpus, max(memory_gb) memory_gb,
                     max(environment) environment, max(license_type) license_type
                from oracle_hosts
               group by hostname ) s
      on ( d.platform = s.platform and d.hostname = s.hostname )
      when matched then update set
         d.os_type = s.os_type, d.num_cpus = s.num_cpus, d.memory_gb = s.memory_gb,
         d.environment = s.environment, d.license_type = s.license_type
      when not matched then
         insert ( platform, hostname, os_type, num_cpus, memory_gb, environment, license_type )
         values ( s.platform, s.hostname, s.os_type, s.num_cpus, s.memory_gb, s.environment, s.license_type );

      -- MSSQL: host = collect_target (FQDN); env/license from mssql_collect_list joined on collect_target
      merge into dim_host d
      using ( select 'MSSQL' platform, h.collect_target hostname,
                     max(h.os_type) os_type, max(h.num_cpus) num_cpus, max(h.memory_gb) memory_gb,
                     max(cl.environment) environment, max(cl.license_type) license_type
                from mssql_hosts h
                left join mssql_collect_list cl on cl.hostname = h.collect_target and cl.active = 1
               group by h.collect_target ) s
      on ( d.platform = s.platform and d.hostname = s.hostname )
      when matched then update set
         d.os_type = s.os_type, d.num_cpus = s.num_cpus, d.memory_gb = s.memory_gb,
         d.environment = s.environment, d.license_type = s.license_type
      when not matched then
         insert ( platform, hostname, os_type, num_cpus, memory_gb, environment, license_type )
         values ( s.platform, s.hostname, s.os_type, s.num_cpus, s.memory_gb, s.environment, s.license_type );

      -- MSSQL host extension (cluster configuration)
      merge into ext_mssql_host e
      using ( select ds.host_id,
                     max(h.is_clustered) is_clustered, max(h.activenodename) activenodename,
                     max(h.clusternode1) clusternode1, max(h.clusternode2) clusternode2
                from mssql_hosts h
                join dim_host ds on ds.platform = 'MSSQL' and ds.hostname = h.collect_target
               group by ds.host_id ) s
      on ( e.host_id = s.host_id )
      when matched then update set
         e.is_clustered = s.is_clustered, e.activenodename = s.activenodename,
         e.clusternode1 = s.clusternode1, e.clusternode2 = s.clusternode2
      when not matched then
         insert ( host_id, is_clustered, activenodename, clusternode1, clusternode2 )
         values ( s.host_id, s.is_clustered, s.activenodename, s.clusternode1, s.clusternode2 );
   end load_dim_host;

   procedure load_dim_instance is
   begin
      -- Oracle instance (one per hostname+instance_name)
      merge into dim_instance di
      using ( select ds.host_id, 'ORACLE' platform, od.instance_name,
                     max(od.db_version) engine_version, max(od.db_edition) edition
                from oracle_databases od
                join dim_host ds on ds.platform = 'ORACLE' and ds.hostname = od.hostname
               group by ds.host_id, od.instance_name ) s
      on ( di.host_id = s.host_id and di.instance_name = s.instance_name )
      when matched then update set
         di.engine_version = s.engine_version, di.edition = s.edition
      when not matched then
         insert ( host_id, platform, instance_name, engine_version, edition )
         values ( s.host_id, s.platform, s.instance_name, s.engine_version, s.edition );

      -- MSSQL instance (instance_name = hostname in this collection)
      -- The port comes from the perimeter, not from the collection: mssql_hosts
      -- carries no port. It is only meaningful when the machine has a single
      -- active perimeter entry. As soon as a named instance is promoted next to
      -- a default one, several entries share the collect_target and there is
      -- nothing in the collected data to tell which port belongs to which
      -- instance - so the port is left null rather than guessed.
      merge into dim_instance di
      using ( select ds.host_id, 'MSSQL' platform, h.hostname instance_name,
                     max(h.mssql_product_version) engine_version, max(h.mssql_edition) edition,
                     max(h.collation) collation,
                     case when count(distinct cl.port) = 1 then max(cl.port) end port,
                     max(h.install_date) install_date
                from mssql_hosts h
                join dim_host ds on ds.platform = 'MSSQL' and ds.hostname = h.collect_target
                left join mssql_collect_list cl on cl.hostname = h.collect_target and cl.active = 1
               group by ds.host_id, h.hostname ) s
      on ( di.host_id = s.host_id and di.instance_name = s.instance_name )
      when matched then update set
         di.engine_version = s.engine_version, di.edition = s.edition, di.collation = s.collation,
         di.port = s.port, di.install_date = s.install_date
      when not matched then
         insert ( host_id, platform, instance_name, engine_version, edition, collation, port, install_date )
         values ( s.host_id, s.platform, s.instance_name, s.engine_version, s.edition, s.collation, s.port, s.install_date );

      -- Oracle instance extension
      merge into ext_oracle_instance e
      using ( select di.instance_id,
                     max(od.db_role) db_role, max(od.rac_state) rac_state, max(od.db_unique_name) db_unique_name,
                     max(od.database_type) database_type, max(od.count_pdb) count_pdb, max(od.db_charset) charset,
                     max( ( select max(dg.protection_mode) from oracle_dataguard dg
                              where dg.primary_db in ( od.db_name, od.db_unique_name ) ) ) protection_mode
                from oracle_databases od
                join dim_host ds on ds.platform = 'ORACLE' and ds.hostname = od.hostname
                join dim_instance di on di.host_id = ds.host_id and di.instance_name = od.instance_name
               group by di.instance_id ) s
      on ( e.instance_id = s.instance_id )
      when matched then update set
         e.db_role = s.db_role, e.rac_state = s.rac_state, e.db_unique_name = s.db_unique_name,
         e.database_type = s.database_type, e.count_pdb = s.count_pdb, e.charset = s.charset,
         e.protection_mode = s.protection_mode
      when not matched then
         insert ( instance_id, db_role, rac_state, db_unique_name, database_type, count_pdb, charset, protection_mode )
         values ( s.instance_id, s.db_role, s.rac_state, s.db_unique_name, s.database_type, s.count_pdb, s.charset, s.protection_mode );

      -- MSSQL instance extension
      merge into ext_mssql_instance e
      using ( select di.instance_id,
                     max(h.parallel_threshold) parallel_threshold, max(h.max_dop) max_dop,
                     max(h.min_memory) min_memory, max(h.max_memory) max_memory,
                     max(h.xp_cmdshell_enabled) xp_cmdshell_enabled, max(h.service_account) service_account
                from mssql_hosts h
                join dim_host ds on ds.platform = 'MSSQL' and ds.hostname = h.collect_target
                join dim_instance di on di.host_id = ds.host_id and di.instance_name = h.hostname
               group by di.instance_id ) s
      on ( e.instance_id = s.instance_id )
      when matched then update set
         e.parallel_threshold = s.parallel_threshold, e.max_dop = s.max_dop,
         e.min_memory = s.min_memory, e.max_memory = s.max_memory,
         e.xp_cmdshell_enabled = s.xp_cmdshell_enabled, e.service_account = s.service_account
      when not matched then
         insert ( instance_id, parallel_threshold, max_dop, min_memory, max_memory, xp_cmdshell_enabled, service_account )
         values ( s.instance_id, s.parallel_threshold, s.max_dop, s.min_memory, s.max_memory, s.xp_cmdshell_enabled, s.service_account );
   end load_dim_instance;

   procedure load_dim_database is
   begin
      -- Oracle pluggable databases
      merge into dim_database dd
      using ( select di.instance_id, 'ORACLE' platform, p.pdb_name db_name,
                     max(p.pdb_state) db_state, max(od.environment) environment
                from oracle_pdbs p
                join dim_host ds on ds.platform = 'ORACLE' and ds.hostname = p.hostname
                join dim_instance di on di.host_id = ds.host_id and di.instance_name = p.instance_name
                left join oracle_databases od on od.hostname = p.hostname and od.instance_name = p.instance_name
               group by di.instance_id, p.pdb_name ) s
      on ( dd.instance_id = s.instance_id and dd.db_name = s.db_name )
      when matched then update set dd.db_state = s.db_state, dd.environment = s.environment
      when not matched then
         insert ( instance_id, platform, db_name, db_state, environment )
         values ( s.instance_id, s.platform, s.db_name, s.db_state, s.environment );

      -- Oracle non-CDB databases (no PDB rows)
      merge into dim_database dd
      using ( select di.instance_id, 'ORACLE' platform, od.db_name,
                     max(od.environment) environment
                from oracle_databases od
                join dim_host ds on ds.platform = 'ORACLE' and ds.hostname = od.hostname
                join dim_instance di on di.host_id = ds.host_id and di.instance_name = od.instance_name
               where nvl(od.count_pdb, 0) = 0
               group by di.instance_id, od.db_name ) s
      on ( dd.instance_id = s.instance_id and dd.db_name = s.db_name )
      when matched then update set dd.environment = s.environment
      when not matched then
         insert ( instance_id, platform, db_name, environment )
         values ( s.instance_id, s.platform, s.db_name, s.environment );

      -- MSSQL databases
      merge into dim_database dd
      using ( select di.instance_id, 'MSSQL' platform, d.database_name db_name,
                     max(d.database_state) db_state, max(d.create_date) create_date,
                     max(d.owner) owner, max(cl.environment) environment
                from mssql_databases d
                join dim_host ds on ds.platform = 'MSSQL' and ds.hostname = d.collect_target
                join dim_instance di on di.host_id = ds.host_id and di.instance_name = d.hostname
                left join mssql_collect_list cl on cl.hostname = d.collect_target and cl.active = 1
               group by di.instance_id, d.database_name ) s
      on ( dd.instance_id = s.instance_id and dd.db_name = s.db_name )
      when matched then update set dd.db_state = s.db_state, dd.create_date = s.create_date,
         dd.owner = s.owner, dd.environment = s.environment
      when not matched then
         insert ( instance_id, platform, db_name, db_state, create_date, owner, environment )
         values ( s.instance_id, s.platform, s.db_name, s.db_state, s.create_date, s.owner, s.environment );

      -- Oracle database extension (pdb attributes; is_pdb derived)
      merge into ext_oracle_database e
      using ( select dd.database_id,
                     max(p.pdb_name) pdb_name, max(p.pdb_state) pdb_state,
                     case when max(p.pdb_name) is not null then 1 else 0 end is_pdb,
                     max(od.db_charset) charset
                from dim_database dd
                join dim_instance di on di.instance_id = dd.instance_id
                join dim_host ds on ds.host_id = di.host_id
                left join oracle_pdbs p on p.hostname = ds.hostname and p.instance_name = di.instance_name and p.pdb_name = dd.db_name
                left join oracle_databases od on od.hostname = ds.hostname and od.instance_name = di.instance_name
               where dd.platform = 'ORACLE'
               group by dd.database_id ) s
      on ( e.database_id = s.database_id )
      when matched then update set e.pdb_name = s.pdb_name, e.pdb_state = s.pdb_state,
         e.is_pdb = s.is_pdb, e.charset = s.charset
      when not matched then
         insert ( database_id, pdb_name, pdb_state, is_pdb, charset )
         values ( s.database_id, s.pdb_name, s.pdb_state, s.is_pdb, s.charset );

      -- MSSQL database extension
      merge into ext_mssql_database e
      using ( select dd.database_id,
                     max(d.database_id) database_id_src, max(d.recovery_model) recovery_model,
                     max(d.compatibility_level) compatibility_level, max(d.collation) collation,
                     max(d.is_mirroring_enabled) is_mirroring_enabled, max(d.agtype) agtype, max(d.agname) agname
                from mssql_databases d
                join dim_host ds on ds.platform = 'MSSQL' and ds.hostname = d.collect_target
                join dim_instance di on di.host_id = ds.host_id and di.instance_name = d.hostname
                join dim_database dd on dd.instance_id = di.instance_id and dd.db_name = d.database_name
               group by dd.database_id ) s
      on ( e.database_id = s.database_id )
      when matched then update set e.database_id_src = s.database_id_src, e.recovery_model = s.recovery_model,
         e.compatibility_level = s.compatibility_level, e.collation = s.collation,
         e.is_mirroring_enabled = s.is_mirroring_enabled, e.agtype = s.agtype, e.agname = s.agname
      when not matched then
         insert ( database_id, database_id_src, recovery_model, compatibility_level, collation, is_mirroring_enabled, agtype, agname )
         values ( s.database_id, s.database_id_src, s.recovery_model, s.compatibility_level, s.collation, s.is_mirroring_enabled, s.agtype, s.agname );
   end load_dim_database;

   procedure load_dim_storage_unit is
   begin
      -- Oracle tablespaces
      merge into dim_storage_unit su
      using ( select dd.database_id, 'ORACLE' platform, 'TABLESPACE' storage_type, z.tablespace_name name
                from oracle_size_usage z
                join oracle_databases od on od.db_name = z.db_name
                join dim_host ds on ds.platform = 'ORACLE' and ds.hostname = od.hostname
                join dim_instance di on di.host_id = ds.host_id and di.instance_name = od.instance_name
                join dim_database dd on dd.instance_id = di.instance_id and dd.db_name = z.pdb_name
               group by dd.database_id, z.tablespace_name ) s
      on ( su.database_id = s.database_id and su.storage_type = s.storage_type and su.name = s.name )
      when not matched then
         insert ( database_id, platform, storage_type, name )
         values ( s.database_id, s.platform, s.storage_type, s.name );

      -- MSSQL data/log files
      merge into dim_storage_unit su
      using ( select dd.database_id, 'MSSQL' platform,
                     case when upper(f.type_desc) like 'LOG%' then 'LOGFILE' else 'DATAFILE' end storage_type,
                     f.name,
                     max(f.physical_name) physical_name, max(f.max_size) max_size_mb,
                     max(f.growth_percent) autogrowth_pct, max(f.growth_mb) autogrowth_mb
                from mssql_files f
                join dim_host ds on ds.platform = 'MSSQL' and ds.hostname = f.collect_target
                join dim_instance di on di.host_id = ds.host_id and di.instance_name = f.hostname
                join dim_database dd on dd.instance_id = di.instance_id and dd.db_name = f.database_name
               group by dd.database_id,
                     case when upper(f.type_desc) like 'LOG%' then 'LOGFILE' else 'DATAFILE' end, f.name ) s
      on ( su.database_id = s.database_id and su.storage_type = s.storage_type and su.name = s.name )
      when matched then update set su.physical_name = s.physical_name, su.max_size_mb = s.max_size_mb,
         su.autogrowth_pct = s.autogrowth_pct, su.autogrowth_mb = s.autogrowth_mb
      when not matched then
         insert ( database_id, platform, storage_type, name, physical_name, max_size_mb, autogrowth_pct, autogrowth_mb )
         values ( s.database_id, s.platform, s.storage_type, s.name, s.physical_name, s.max_size_mb, s.autogrowth_pct, s.autogrowth_mb );
   end load_dim_storage_unit;

   procedure load_dim_parameter is
   begin
      -- Oracle init/security parameters
      merge into dim_parameter p
      using ( select distinct 'ORACLE' platform, parameter_name, 'security' category, 'INIT' source
                from oracle_security_parameter ) s
      on ( p.platform = s.platform and p.parameter_name = s.parameter_name and p.source = s.source )
      when not matched then
         insert ( platform, parameter_name, category, source )
         values ( s.platform, s.parameter_name, s.category, s.source );

      -- MSSQL sp_configure options
      merge into dim_parameter p
      using ( select distinct 'MSSQL' platform, name parameter_name, 'security' category, 'SP_CONFIGURE' source
                from mssql_security_configoptions ) s
      on ( p.platform = s.platform and p.parameter_name = s.parameter_name and p.source = s.source )
      when not matched then
         insert ( platform, parameter_name, category, source )
         values ( s.platform, s.parameter_name, s.category, s.source );

      -- MSSQL registry values
      merge into dim_parameter p
      using ( select distinct 'MSSQL' platform, name parameter_name, 'security' category, 'REGISTRY' source
                from mssql_security_registryinfo ) s
      on ( p.platform = s.platform and p.parameter_name = s.parameter_name and p.source = s.source )
      when not matched then
         insert ( platform, parameter_name, category, source )
         values ( s.platform, s.parameter_name, s.category, s.source );
   end load_dim_parameter;

   procedure load_dim_account is
   begin
      -- Oracle database users (scope DATABASE)
      merge into dim_account a
      using ( select 'ORACLE' platform, 'DATABASE' scope,
                     cast(null as number) host_id, dd.database_id, u.username account_name,
                     cast(null as varchar2(50 char)) account_type
                from oracle_users u
                join dim_host ds on ds.platform = 'ORACLE' and ds.hostname = u.hostname
                join dim_instance di on di.host_id = ds.host_id and di.instance_name = u.instance_name
                join dim_database dd on dd.instance_id = di.instance_id and dd.db_name = u.pdb_name
               group by dd.database_id, u.username ) s
      on ( a.platform = s.platform and a.scope = s.scope and a.account_name = s.account_name
           and nvl(a.database_id, -1) = nvl(s.database_id, -1) and nvl(a.host_id, -1) = nvl(s.host_id, -1) )
      when not matched then
         insert ( platform, scope, host_id, database_id, account_name, account_type )
         values ( s.platform, s.scope, s.host_id, s.database_id, s.account_name, s.account_type );

      -- MSSQL server logins (scope SERVER): attached to the host via collect_target
      -- (dim_account has no instance FK; per-instance login granularity is a future refinement)
      merge into dim_account a
      using ( select 'MSSQL' platform, 'SERVER' scope, ds.host_id,
                     cast(null as number) database_id, l.loginname account_name,
                     max(l.logintype) account_type
                from mssql_logins l
                join dim_host ds on ds.platform = 'MSSQL' and ds.hostname = l.collect_target
               group by ds.host_id, l.loginname ) s
      on ( a.platform = s.platform and a.scope = s.scope and a.account_name = s.account_name
           and nvl(a.host_id, -1) = nvl(s.host_id, -1) and nvl(a.database_id, -1) = nvl(-1, -1) )
      when not matched then
         insert ( platform, scope, host_id, database_id, account_name, account_type )
         values ( s.platform, s.scope, s.host_id, s.database_id, s.account_name, s.account_type );

      -- MSSQL database users (scope DATABASE)
      merge into dim_account a
      using ( select 'MSSQL' platform, 'DATABASE' scope, cast(null as number) host_id,
                     dd.database_id, u.name account_name, cast(null as varchar2(50 char)) account_type
                from mssql_users u
                join dim_host ds on ds.platform = 'MSSQL' and ds.hostname = u.collect_target
                join dim_instance di on di.host_id = ds.host_id and di.instance_name = u.instance_name
                join dim_database dd on dd.instance_id = di.instance_id and dd.db_name = u.database_name
               group by dd.database_id, u.name ) s
      on ( a.platform = s.platform and a.scope = s.scope and a.account_name = s.account_name
           and nvl(a.database_id, -1) = nvl(s.database_id, -1) and nvl(a.host_id, -1) = nvl(s.host_id, -1) )
      when not matched then
         insert ( platform, scope, host_id, database_id, account_name, account_type )
         values ( s.platform, s.scope, s.host_id, s.database_id, s.account_name, s.account_type );
   end load_dim_account;

   procedure load_dimensions is
   begin
      load_dim_host;
      load_dim_instance;
      load_dim_database;
      load_dim_storage_unit;
      load_dim_parameter;
      load_dim_account;
   end load_dimensions;

   -- ===============================================================
   -- Fact loaders (dated, idempotent per snapshot_date)
   -- ===============================================================

   procedure load_fact_storage_capacity ( p_snapshot_date in date ) is
   begin
      -- Oracle tablespaces: allocated size vs sum of segments
      merge into fact_storage_capacity f
      using ( select su.storage_unit_id, p_snapshot_date snapshot_date,
                     max(z.size_mb) size_mb,
                     max(nvl(z.sum_segment_mb, 0)) used_mb,
                     max(z.size_mb) - max(nvl(z.sum_segment_mb, 0)) free_mb,
                     cast(null as number) max_size_mb,
                     round(100 * max(nvl(z.sum_segment_mb, 0)) / nullif(max(z.size_mb), 0), 2) pct_used
                from oracle_size_usage z
                join oracle_databases od on od.db_name = z.db_name
                join dim_host ds on ds.platform = 'ORACLE' and ds.hostname = od.hostname
                join dim_instance di on di.host_id = ds.host_id and di.instance_name = od.instance_name
                join dim_database dd on dd.instance_id = di.instance_id and dd.db_name = z.pdb_name
                join dim_storage_unit su on su.database_id = dd.database_id
                     and su.storage_type = 'TABLESPACE' and su.name = z.tablespace_name
               group by su.storage_unit_id ) s
      on ( f.storage_unit_id = s.storage_unit_id and f.snapshot_date = s.snapshot_date )
      when matched then update set f.size_mb = s.size_mb, f.used_mb = s.used_mb, f.free_mb = s.free_mb,
         f.max_size_mb = s.max_size_mb, f.pct_used = s.pct_used
      when not matched then
         insert ( storage_unit_id, snapshot_date, size_mb, used_mb, free_mb, max_size_mb, pct_used )
         values ( s.storage_unit_id, s.snapshot_date, s.size_mb, s.used_mb, s.free_mb, s.max_size_mb, s.pct_used );

      -- MSSQL files: current size vs max size (used space not collected)
      merge into fact_storage_capacity f
      using ( select su.storage_unit_id, p_snapshot_date snapshot_date,
                     max(f2.size_mb) size_mb, cast(null as number) used_mb, cast(null as number) free_mb,
                     case when max(f2.max_size) > 0 then max(f2.max_size) else null end max_size_mb,
                     case when max(f2.max_size) > 0 then round(100 * max(f2.size_mb) / max(f2.max_size), 2) else null end pct_used
                from mssql_files f2
                join dim_host ds on ds.platform = 'MSSQL' and ds.hostname = f2.collect_target
                join dim_instance di on di.host_id = ds.host_id and di.instance_name = f2.hostname
                join dim_database dd on dd.instance_id = di.instance_id and dd.db_name = f2.database_name
                join dim_storage_unit su on su.database_id = dd.database_id
                     and su.storage_type = case when upper(f2.type_desc) like 'LOG%' then 'LOGFILE' else 'DATAFILE' end
                     and su.name = f2.name
               group by su.storage_unit_id ) s
      on ( f.storage_unit_id = s.storage_unit_id and f.snapshot_date = s.snapshot_date )
      when matched then update set f.size_mb = s.size_mb, f.used_mb = s.used_mb, f.free_mb = s.free_mb,
         f.max_size_mb = s.max_size_mb, f.pct_used = s.pct_used
      when not matched then
         insert ( storage_unit_id, snapshot_date, size_mb, used_mb, free_mb, max_size_mb, pct_used )
         values ( s.storage_unit_id, s.snapshot_date, s.size_mb, s.used_mb, s.free_mb, s.max_size_mb, s.pct_used );
   end load_fact_storage_capacity;

   procedure load_fact_db_resource ( p_snapshot_date in date ) is
   begin
      -- Oracle per-PDB CPU/memory (ASSUMPTION: pdb_name uniquely maps to one database)
      merge into fact_db_resource f
      using ( select dd.database_id, p_snapshot_date snapshot_date,
                     max(m.cpu_time_minutes) cpu_time_min, max(m.avg_sga_mb) sga_mb, max(m.avg_pga_mb) pga_mb,
                     max(m.avg_buffer_cache_mb) buffer_cache_mb, max(m.avg_shared_pool_mb) shared_pool_mb
                from oracle_metrics_cpu_memory m
                join dim_database dd on dd.platform = 'ORACLE' and dd.db_name = m.pdb_name
               group by dd.database_id ) s
      on ( f.database_id = s.database_id and f.snapshot_date = s.snapshot_date )
      when matched then update set f.cpu_time_min = s.cpu_time_min, f.sga_mb = s.sga_mb, f.pga_mb = s.pga_mb,
         f.buffer_cache_mb = s.buffer_cache_mb, f.shared_pool_mb = s.shared_pool_mb
      when not matched then
         insert ( database_id, snapshot_date, cpu_time_min, sga_mb, pga_mb, buffer_cache_mb, shared_pool_mb )
         values ( s.database_id, s.snapshot_date, s.cpu_time_min, s.sga_mb, s.pga_mb, s.buffer_cache_mb, s.shared_pool_mb );
   end load_fact_db_resource;

   procedure load_fact_backup ( p_snapshot_date in date ) is
   begin
      -- MSSQL backup freshness from mssql_databases.last_backup_*. Oracle is NOT here:
      -- RMAN backs up the whole container, so it feeds fact_instance_backup instead.
      merge into fact_backup f
      using ( select dd.database_id, p_snapshot_date snapshot_date,
                     max(pkg_dbinv_inventory.safe_to_date(d.last_backup_date)) last_full_date,
                     max(pkg_dbinv_inventory.safe_to_date(d.last_backup_diff_date)) last_diff_date,
                     max(pkg_dbinv_inventory.safe_to_date(d.last_backup_log_date)) last_log_date,
                     round( ( cast(p_snapshot_date as date)
                              - max(pkg_dbinv_inventory.safe_to_date(d.last_backup_date)) ) * 24, 2 ) hours_since_backup,
                     -- Size of the most recent Full backup, from the collected
                     -- msdb.dbo.backupset history (backup_size is in bytes).
                     max(bs.backup_size_mb) backup_size_mb,
                     -- status has NO source: msdb.dbo.backupset only records
                     -- successful backups, so a FAILED verdict cannot be derived
                     -- from it. Populating this needs SQL Agent job history
                     -- (msdb.dbo.sysjobhistory), which is not collected today.
                     cast(null as varchar2(30 char)) status
                from mssql_databases d
                join dim_host ds on ds.platform = 'MSSQL' and ds.hostname = d.collect_target
                join dim_instance di on di.host_id = ds.host_id and di.instance_name = d.hostname
                join dim_database dd on dd.instance_id = di.instance_id and dd.db_name = d.database_name
                left join ( select b.collect_target, b.hostname, b.database_name,
                                   round( max(b.backup_size) keep ( dense_rank last order by b.backup_finish_date )
                                          / 1024 / 1024 ) backup_size_mb
                              from mssql_backup b
                             where b.backup_type = 'Full'
                             group by b.collect_target, b.hostname, b.database_name ) bs
                       on bs.collect_target = d.collect_target
                      and bs.hostname = d.hostname
                      and bs.database_name = d.database_name
               group by dd.database_id ) s
      on ( f.database_id = s.database_id and f.snapshot_date = s.snapshot_date )
      when matched then update set f.last_full_date = s.last_full_date, f.last_diff_date = s.last_diff_date,
         f.last_log_date = s.last_log_date, f.hours_since_backup = s.hours_since_backup,
         f.backup_size_mb = s.backup_size_mb, f.status = s.status
      when not matched then
         insert ( database_id, snapshot_date, last_full_date, last_diff_date, last_log_date, hours_since_backup, backup_size_mb, status )
         values ( s.database_id, s.snapshot_date, s.last_full_date, s.last_diff_date, s.last_log_date, s.hours_since_backup, s.backup_size_mb, s.status );
   end load_fact_backup;

   procedure load_fact_instance_backup ( p_snapshot_date in date ) is
   begin
      -- Oracle RMAN jobs (oracle_backup), rolled up to the container they cover.
      -- v$rman_backup_job_details.input_type distinguishes the backup kind; a job is
      -- counted as successful only when it COMPLETED (with warnings at worst) -
      -- 'COMPLETED WITH ERRORS' is treated as a failure, not as a backup you can restore.
      merge into fact_instance_backup f
      using ( select instance_id, p_snapshot_date snapshot_date,
                     max(case when kind = 'FULL' and is_ok = 1 then start_dt end) last_full_date,
                     max(case when kind = 'INCR' and is_ok = 1 then start_dt end) last_incr_date,
                     max(case when kind = 'LOG'  and is_ok = 1 then start_dt end) last_log_date,
                     round( ( cast(p_snapshot_date as date)
                              - max(case when kind in ('FULL', 'INCR') and is_ok = 1 then start_dt end)
                            ) * 24, 2 ) hours_since_backup,
                     sum(case when is_ok = 0 then 1 else 0 end) failed_count,
                     -- Outcome of the most recent full/incremental job. NULLS FIRST puts the
                     -- archivelog/controlfile rows (null sort key) in the first group, so the
                     -- last group is the newest DB backup - or nothing at all if none exists.
                     max(case when kind in ('FULL', 'INCR') then status end)
                        keep ( dense_rank last
                               order by case when kind in ('FULL', 'INCR') then start_dt end nulls first ) status
                from ( select di.instance_id,
                              case when b.backup_type in ('DB FULL', 'DATAFILE FULL') then 'FULL'
                                   when b.backup_type in ('DB INCR', 'DATAFILE INCR') then 'INCR'
                                   when b.backup_type = 'ARCHIVELOG' then 'LOG' end kind,
                              case when b.status in ('COMPLETED', 'COMPLETED WITH WARNINGS') then 1 else 0 end is_ok,
                              cast(b.start_time as date) start_dt,
                              b.status
                         from oracle_backup b
                         join oracle_databases od on od.db_name = b.db_name
                         join dim_host dh on dh.platform = 'ORACLE' and dh.hostname = od.hostname
                         join dim_instance di on di.host_id = dh.host_id and di.instance_name = od.instance_name )
               group by instance_id ) s
      on ( f.instance_id = s.instance_id and f.snapshot_date = s.snapshot_date )
      when matched then update set f.last_full_date = s.last_full_date, f.last_incr_date = s.last_incr_date,
         f.last_log_date = s.last_log_date, f.hours_since_backup = s.hours_since_backup,
         f.failed_count = s.failed_count, f.status = s.status
      when not matched then
         insert ( instance_id, snapshot_date, last_full_date, last_incr_date, last_log_date,
                  hours_since_backup, failed_count, status )
         values ( s.instance_id, s.snapshot_date, s.last_full_date, s.last_incr_date, s.last_log_date,
                  s.hours_since_backup, s.failed_count, s.status );
   end load_fact_instance_backup;

   procedure load_fact_config_parameter ( p_snapshot_date in date ) is
   begin
      -- Oracle init/security parameters
      merge into fact_config_parameter f
      using ( select di.instance_id, dp.parameter_id, p_snapshot_date snapshot_date,
                     cast(null as varchar2(400 char)) config_value, cast(null as varchar2(400 char)) run_value,
                     max(sp.parameter_value) value_text
                from oracle_security_parameter sp
                join dim_parameter dp on dp.platform = 'ORACLE' and dp.source = 'INIT' and dp.parameter_name = sp.parameter_name
                join oracle_databases od on od.db_name = sp.db_name
                join dim_host ds on ds.platform = 'ORACLE' and ds.hostname = od.hostname
                join dim_instance di on di.host_id = ds.host_id and di.instance_name = od.instance_name
               group by di.instance_id, dp.parameter_id ) s
      on ( f.instance_id = s.instance_id and f.parameter_id = s.parameter_id and f.snapshot_date = s.snapshot_date )
      when matched then update set f.config_value = s.config_value, f.run_value = s.run_value, f.value_text = s.value_text
      when not matched then
         insert ( instance_id, parameter_id, snapshot_date, config_value, run_value, value_text )
         values ( s.instance_id, s.parameter_id, s.snapshot_date, s.config_value, s.run_value, s.value_text );

      -- MSSQL sp_configure options (config_value / run_value)
      merge into fact_config_parameter f
      using ( select di.instance_id, dp.parameter_id, p_snapshot_date snapshot_date,
                     max(to_char(c.config_value)) config_value, max(to_char(c.run_value)) run_value,
                     cast(null as varchar2(400 char)) value_text
                from mssql_security_configoptions c
                join dim_parameter dp on dp.platform = 'MSSQL' and dp.source = 'SP_CONFIGURE' and dp.parameter_name = c.name
                join dim_instance di on di.platform = 'MSSQL' and di.instance_name = c.servername
               group by di.instance_id, dp.parameter_id ) s
      on ( f.instance_id = s.instance_id and f.parameter_id = s.parameter_id and f.snapshot_date = s.snapshot_date )
      when matched then update set f.config_value = s.config_value, f.run_value = s.run_value, f.value_text = s.value_text
      when not matched then
         insert ( instance_id, parameter_id, snapshot_date, config_value, run_value, value_text )
         values ( s.instance_id, s.parameter_id, s.snapshot_date, s.config_value, s.run_value, s.value_text );

      -- MSSQL registry values (value_text)
      merge into fact_config_parameter f
      using ( select di.instance_id, dp.parameter_id, p_snapshot_date snapshot_date,
                     cast(null as varchar2(400 char)) config_value, cast(null as varchar2(400 char)) run_value,
                     max(to_char(r.value)) value_text
                from mssql_security_registryinfo r
                join dim_parameter dp on dp.platform = 'MSSQL' and dp.source = 'REGISTRY' and dp.parameter_name = r.name
                join dim_instance di on di.platform = 'MSSQL' and di.instance_name = r.servername
               group by di.instance_id, dp.parameter_id ) s
      on ( f.instance_id = s.instance_id and f.parameter_id = s.parameter_id and f.snapshot_date = s.snapshot_date )
      when matched then update set f.config_value = s.config_value, f.run_value = s.run_value, f.value_text = s.value_text
      when not matched then
         insert ( instance_id, parameter_id, snapshot_date, config_value, run_value, value_text )
         values ( s.instance_id, s.parameter_id, s.snapshot_date, s.config_value, s.run_value, s.value_text );
   end load_fact_config_parameter;

   procedure load_facts ( p_snapshot_date in date default trunc(sysdate) ) is
   begin
      load_dim_date(p_snapshot_date);
      load_fact_storage_capacity(p_snapshot_date);
      load_fact_db_resource(p_snapshot_date);
      load_fact_backup(p_snapshot_date);
      load_fact_instance_backup(p_snapshot_date);
      load_fact_config_parameter(p_snapshot_date);
   end load_facts;

   procedure load_all ( p_snapshot_date in date default trunc(sysdate) ) is
   begin
      load_dimensions;
      load_facts(p_snapshot_date);
      commit;
   end load_all;

end pkg_dbinv_inventory;
/
