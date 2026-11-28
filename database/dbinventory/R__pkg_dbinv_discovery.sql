-- ============================================================================
-- R__pkg_dbinv_discovery.sql
-- ----------------------------------------------------------------------------
-- ETL package pkg_dbinv_discovery: populates the discovery area (V__004) from
-- the discovery staging tables, and promotes a discovered instance into the
-- collection perimeter.
--
-- Design, aligned on pkg_dbinv_inventory (pkg_dbinv_inventory):
--   * A run is MERGEd on (source, run_date), so loading the same day twice
--     reuses the same run instead of duplicating it.
--   * Findings are deleted then re-inserted for that run: the whole load is
--     idempotent per day.
--   * Current state (disc_host, disc_instance) is MERGEd on its natural key.
--     first_seen_date is set on insert and never rewritten; last_seen_date
--     follows the run. Nothing is ever deleted - an entity that stops being
--     discovered simply stops having its last_seen_date moved forward.
--   * Hosts are merged before instances: an instance-level finding implies its
--     host, so disc_host is fed from findings of both levels.
--
-- No verdict is produced anywhere in this package. Ageing is a fact, not a
-- status: reading it as a decommission is a human call.
-- ============================================================================

create or replace package pkg_dbinv_discovery as

   -- Creates (or reuses) the run for a source and a day, and returns its id.
   function load_run (
      p_source   varchar2,
      p_run_date date default trunc(sysdate)
   ) return number;

   -- Staging -> disc_finding. Replaces the findings of the run.
   procedure load_findings_mssql ( p_run_id number );
   procedure load_findings_linux ( p_run_id number );

   -- disc_finding -> current state.
   procedure merge_hosts ( p_run_id number );
   procedure merge_instances ( p_run_id number );

   -- Full load for one source, then for everything staged.
   procedure load_mssql ( p_run_date date default trunc(sysdate) );
   procedure load_linux ( p_run_date date default trunc(sysdate) );
   procedure load_all ( p_run_date date default trunc(sysdate) );

   -- Adds a discovered instance to the collection perimeter (MSSQL, Oracle).
   -- collect_name, service_name and port are human input: Oracle needs all
   -- three, MSSQL needs none. See the body for why they are not guessed.
   procedure promote_instance (
      p_disc_instance_id number,
      p_environment      varchar2,
      p_license_type     varchar2,
      p_collect_name     varchar2 default null,
      p_service_name     varchar2 default null,
      p_port             number default null
   );

   -- Same, at host level (PostgreSQL, and the MSSQL host whose WMI refused).
   -- PostgreSQL has no instance grain in the discovery, so it has no other way in.
   procedure promote_host (
      p_disc_host_id number,
      p_environment  varchar2,
      p_license_type varchar2,
      p_collect_name varchar2 default null,
      p_port         number default null
   );

   -- Records a triage decision (NEW / IGNORED) on a host or an instance.
   procedure set_triage (
      p_level     varchar2,
      p_entity_id number,
      p_status    varchar2,
      p_note      varchar2 default null
   );

end pkg_dbinv_discovery;
/
