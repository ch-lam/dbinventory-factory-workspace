-- ============================================================================
-- V__017_drop_awr_resource_metrics.sql
-- ----------------------------------------------------------------------------
-- Drop the Oracle CPU/memory metrics, on schemas already installed.
--
-- WHY
--   get_info_oracle.sh read them from DBA_HIST_SERVICE_STAT and
--   DBA_HIST_RSRC_PDB_METRIC. Both belong to the Diagnostics Pack, which only
--   exists on Enterprise Edition: on the Standard Edition 2 databases now in the
--   estate it cannot be licensed at all, and querying the view is the usage --
--   a view being readable is no licence to read it. The metrics fed nothing but
--   one report region on page 26, and the per-service CPU was wrong anyway
--   (cumulative counters summed across snapshots, microseconds divided by
--   60 000). The collect, the loader, the ETL and the page drop them together.
--
-- WHAT
--   staging : oracle_metrics_cpu_memory, oracle_metrics_cpu_mem_hist,
--             oracle_metrics_cpu_service, oracle_metrics_cpu_svc_hist
--   model   : fact_db_resource
--   V__001, V__002 and V__004 no longer create or fill them on a fresh install.
--
-- WHY A SEPARATE SCRIPT
--   X_000 does not replay V__001 / V__002 on an installed schema. Each drop
--   runs only if the table exists: a no-op on a fresh install, safe to run twice.
--
-- ORDER (installed schema)
--   1. V__004             package without load_fact_db_resource (create or replace)
--   2. this script        drops; run before it, the old package body would go invalid
--   3. deploy get_info_oracle.sh AND load_info_oracle.sh together: the old
--      loader truncates and loads the dropped tables, the old collect still
--      queries AWR.
--   4. the application (page 26 without the Resources region)
-- ============================================================================

alter session set current_schema=dbinventory;

declare
   l_n pls_integer;
begin
   for t in ( select column_value table_name
                from table ( sys.odcivarchar2list (
                        'FACT_DB_RESOURCE',
                        'ORACLE_METRICS_CPU_MEMORY',
                        'ORACLE_METRICS_CPU_MEM_HIST',
                        'ORACLE_METRICS_CPU_SERVICE',
                        'ORACLE_METRICS_CPU_SVC_HIST' ) ) ) loop
      select count(*) into l_n from user_tables where table_name = t.table_name;
      if l_n > 0 then
         execute immediate 'drop table ' || t.table_name || ' purge';
      end if;
   end loop;
end;
/
