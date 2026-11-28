-- ============================================================================
-- R__pkg_dbinv_inventory.sql
-- ----------------------------------------------------------------------------
-- ETL package pkg_dbinv_inventory: populates the dimensional application model
-- (V__002) from the collection/staging tables (V__001). Inventory + capacity
-- only; compliance/scoring lives in a separate package (pkg_dbinv_scoring).
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
--   * MSSQL environment/license/port are carried by the collection itself
--     (mssql_hosts, mssql_databases), prepended from the perimeter .lst by
--     get_info_mssql.sh - exactly as oracle_hosts/oracle_databases do. They are
--     deliberately NOT re-read from mssql_collect_list at load time: that table is
--     the current perimeter, not the state of the run, so a host removed from or
--     never promoted into the perimeter would silently lose its environment.
-- Oracle join notes:
--   * Oracle storage/parameter link to a database through
--     oracle_databases (db_name) -> (hostname, instance_name) -> database (pdb_name).
--   * Coherent refuge value: the collection emits the db_name into the pdb_name
--     field for non-CDB databases (real PDB name for CDB), so dd.db_name = pdb_name
--     resolves uniformly. is_pdb=0 (ext_oracle_database) keeps the non-PDB distinction.
--   * No CPU/memory fact any more: the collect read them from AWR (Diagnostics
--     Pack), which cannot be licensed on the Standard Edition 2 databases of
--     the estate.
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
