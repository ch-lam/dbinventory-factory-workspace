-- ============================================================================
-- V__006_create_discovery.sql
-- ----------------------------------------------------------------------------
-- Discovery area: what is actually installed on the estate, as opposed to what
-- dbInventory currently collects.
--
-- Two scripts feed this area, run weekly to detect drift (rogue installs):
--   * discovery/windows/discovery_MSSQL.ps1  - enumerates SQL Server instances
--     across the AD domain by reading the registry (so it also sees stopped
--     instances and the exact edition).
--   * discovery/linux/detect_db_engines.sh   - detects Postgres / Oracle / MySQL
--     on Linux hosts (packages, processes, listening ports), pushed by SALT.
--
-- This is INVENTORY, not monitoring. An entity that stops being discovered
-- produces no verdict and no score: only last_seen_date ages. Reading that as
-- "decommissioned" versus "the host was down that day" is a human call. A real
-- decommission makes the compliance data obsolete by itself; a network incident
-- shows up in the existing controls (backup freshness, etc.).
--
-- Grain: HOST and INSTANCE. Neither script goes down to databases, and on an
-- instance we do not manage we have no account to enumerate them anyway. The
-- two levels are genuinely different data, not one degraded into the other:
-- the Linux script only names instances for Oracle (the ora_pmon_<SID>
-- processes); for Postgres and MySQL all it can say is "present on this host,
-- on that port".
--
-- No FK to dim_host / dim_instance on purpose: a discovered host that is not
-- collected does not exist in the dimensions - that is the whole point. The
-- reconciliation between discovery and collection perimeter is done by natural
-- key in v_discovery_status, not by a constraint.
--
-- Naming conventions: see V__002_create_app_model.sql.
-- ============================================================================


-- ============================================================
-- STAGING (TRUNCATE+LOAD, same contract as V__001 tables)
-- ============================================================

-- ------------------------------------------------------------
-- discovery_mssql_inst
-- Mirrors discovery_MSSQL.ps1 output. Column names match the CSV header
-- exactly so the load can run with SET LOADFORMAT COLUMN_NAMES ON, i.e.
-- mapped BY NAME rather than by position. This feed is the one place where
-- we can afford that, and it is worth it: a positional load silently shifts
-- every field when the producer changes its column list (see the oracle_backup
-- 6-versus-7-columns bug fixed in b0dba94).
-- Everything is varchar2 with no constraint: this is staging.
-- ------------------------------------------------------------
create table discovery_mssql_inst (
   serveur          varchar2(150 char),
   instance         varchar2(128 char),
   service          varchar2(128 char),
   edition          varchar2(100 char),
   version          varchar2(50 char),
   patch            varchar2(50 char),
   etatservice      varchar2(30 char),
   demarrage        varchar2(30 char),
   compteservice    varchar2(150 char),
   bitness          varchar2(10 char),
   editiongratuite  varchar2(10 char),
   portsql          varchar2(10 char),
   acceswmi         varchar2(30 char),
   protocole        varchar2(20 char),
   statut           varchar2(100 char),
   detail           varchar2(1000 char),
   tcpport          varchar2(20 char)
);

comment on table discovery_mssql_inst is 'Staging for the Windows/AD MSSQL discovery CSV (discovery_MSSQL.ps1). Loaded by name, truncated on each load.';
comment on column discovery_mssql_inst.serveur is 'Machine FQDN the instance was found on.';
comment on column discovery_mssql_inst.instance is 'SQL Server instance name (MSSQLSERVER for the default instance).';
comment on column discovery_mssql_inst.service is 'Windows service name backing the instance.';
comment on column discovery_mssql_inst.edition is 'SQL Server edition as recorded in the registry.';
comment on column discovery_mssql_inst.version is 'Version at install time (registry Setup\Version).';
comment on column discovery_mssql_inst.patch is 'Current patch level (registry Setup\PatchLevel).';
comment on column discovery_mssql_inst.etatservice is 'Windows service state (Running, Stopped, Service absent).';
comment on column discovery_mssql_inst.demarrage is 'Service start mode (Auto, Manual, Disabled).';
comment on column discovery_mssql_inst.compteservice is 'Account the service runs under.';
comment on column discovery_mssql_inst.bitness is 'Registry view the instance was found in (64-bit or 32-bit).';
comment on column discovery_mssql_inst.editiongratuite is 'True when the edition is Express, Developer or Evaluation.';
comment on column discovery_mssql_inst.portsql is 'True when one of the probed TCP ports answered.';
comment on column discovery_mssql_inst.acceswmi is 'Outcome of the WMI/registry access (OK, Refuse, Indisponible).';
comment on column discovery_mssql_inst.protocole is 'CIM protocol that succeeded (Dcom or Wsman).';
comment on column discovery_mssql_inst.statut is 'Discovery outcome for the row (detected, suspected, to verify).';
comment on column discovery_mssql_inst.detail is 'Free-text detail, typically the WMI error message.';
comment on column discovery_mssql_inst.tcpport is 'TCP port read from the instance registry key, needed to reach named instances.';


-- ------------------------------------------------------------
-- discovery_linux_engines
-- Mirrors the single ';' line emitted per host by detect_db_engines.sh.
--
-- Fixed 14-column contract, and the column ORDER here is the contract: the
-- file carries no header, so load_info_discovery.sh loads it positionally and
-- a column inserted anywhere but at its emitted position shifts every field
-- after it, silently. The order below is the one the script prints.
--
-- It said 11 columns until 2026-09-06, while the script had been emitting 14
-- since its v2. Every real line was therefore shifted from the fifth field on
-- (ORA_PKG landing in ora_proc, ORA_SIDS in ora_port), and the three trailing
-- fields dropped. The *_PORT_GUESS columns are what v2 added, and they carry
-- real signal: a port attributed by convention because the standard port
-- answered is not a port proven to belong to a process, and that difference is
-- exactly what a human weighs before promoting an instance into the perimeter.
-- ------------------------------------------------------------
create table discovery_linux_engines (
   hostn          varchar2(150 char),
   pg_pkg         varchar2(1 char),
   pg_proc        varchar2(10 char),
   pg_port        varchar2(100 char),
   pg_port_guess  varchar2(1 char),
   ora_pkg        varchar2(1 char),
   ora_proc       varchar2(10 char),
   ora_sids       varchar2(400 char),
   ora_port       varchar2(100 char),
   ora_port_guess varchar2(1 char),
   my_pkg         varchar2(1 char),
   my_proc        varchar2(10 char),
   my_port        varchar2(100 char),
   my_port_guess  varchar2(1 char)
);

comment on table discovery_linux_engines is 'Staging for the Linux engine detection (detect_db_engines.sh, pushed by SALT). One wide row per host covering three engines; truncated on each load.';
comment on column discovery_linux_engines.hostn is 'Host name as reported by hostname(1).';
comment on column discovery_linux_engines.pg_pkg is 'Y when a PostgreSQL server package or binary is installed.';
comment on column discovery_linux_engines.pg_proc is 'Number of postgres/postmaster processes running.';
comment on column discovery_linux_engines.pg_port is 'Listening ports attributed to PostgreSQL, or - when none.';
comment on column discovery_linux_engines.pg_port_guess is 'Y when the PostgreSQL port was attributed because the standard port answered, without proof it belongs to a running process; N when the mapping was confirmed by PID.';
comment on column discovery_linux_engines.ora_pkg is 'Y when Oracle is installed (oratab, oraInst.loc or rpm).';
comment on column discovery_linux_engines.ora_proc is 'Number of Oracle instances detected through ora_pmon_<SID>.';
comment on column discovery_linux_engines.ora_sids is 'Comma-separated list of Oracle SIDs, or - when none.';
comment on column discovery_linux_engines.ora_port is 'Listening ports attributed to the Oracle listener, or - when none.';
comment on column discovery_linux_engines.ora_port_guess is 'Y when the Oracle port was attributed because the standard port answered, without proof it belongs to a running process; N when the mapping was confirmed by PID.';
comment on column discovery_linux_engines.my_pkg is 'Y when a MySQL or MariaDB server package or binary is installed.';
comment on column discovery_linux_engines.my_proc is 'Number of mysqld/mariadbd processes running.';
comment on column discovery_linux_engines.my_port is 'Listening ports attributed to MySQL/MariaDB, or - when none.';
comment on column discovery_linux_engines.my_port_guess is 'Y when the MySQL/MariaDB port was attributed because the standard port answered, without proof it belongs to a running process; N when the mapping was confirmed by PID.';


-- ============================================================
-- disc_run  (one discovery run = the batch notion for this area)
-- ============================================================
create table disc_run (
   run_id        number generated by default on null as identity,
   source        varchar2(20 char) not null,
   run_date      date not null,
   host_count    number(6),
   finding_count number(6),
   note          varchar2(400 char),
   constraint disc_run_pk primary key ( run_id ),
   constraint disc_run_uk unique ( source, run_date ),
   constraint disc_run_source_ck check ( source in ( 'MSSQL_WINDOWS', 'LINUX_SALT' ) )
);

comment on table disc_run is 'One execution of a discovery script. Unique per source and day, so re-running a load for the same day is idempotent.';
comment on column disc_run.run_id is 'Technical primary key of the run.';
comment on column disc_run.source is 'Which discovery script produced the run (MSSQL_WINDOWS, LINUX_SALT).';
comment on column disc_run.run_date is 'Day the discovery was run.';
comment on column disc_run.host_count is 'Number of distinct hosts the run reported on.';
comment on column disc_run.finding_count is 'Number of findings recorded for the run.';
comment on column disc_run.note is 'Free-text note about the run (source file, partial coverage, ...).';


-- ============================================================
-- disc_finding  (immutable evidence, one row per run and entity)
-- ============================================================
-- Kept alongside the current-state tables because it is the only thing that can
-- answer "what changed between two runs" - a version upgrade, an edition change,
-- an instance that appears and disappears. Volume is ~100 rows a week.
create table disc_finding (
   finding_id      number generated by default on null as identity,
   run_id          number not null,
   finding_level   varchar2(10 char) not null,
   platform        varchar2(10 char) not null,
   hostname        varchar2(150 char) not null,
   instance_name   varchar2(128 char),
   edition         varchar2(100 char),
   engine_version  varchar2(50 char),
   patch_level     varchar2(50 char),
   port            number(5),
   service_state   varchar2(30 char),
   service_account varchar2(150 char),
   bitness         varchar2(10 char),
   is_free_edition number(1),
   is_installed    number(1),
   process_count   number(6),
   ports_seen      varchar2(100 char),
   detection_note  varchar2(400 char),
   constraint disc_finding_pk primary key ( finding_id ),
   constraint disc_finding_run_fk foreign key ( run_id )
      references disc_run ( run_id ),
   constraint disc_finding_level_ck check ( finding_level in ( 'HOST', 'INSTANCE' ) ),
   constraint disc_finding_inst_ck check (
      ( finding_level = 'INSTANCE' and instance_name is not null )
      or ( finding_level = 'HOST' and instance_name is null )
   )
);

-- Uniqueness of the natural key within a run. Declared as a function-based
-- unique index rather than a constraint because instance_name is null for
-- host-level findings, and Oracle would not compare those rows.
create unique index disc_finding_uk on disc_finding (
   run_id, platform, hostname, nvl(instance_name, '~')
);

comment on table disc_finding is 'Immutable record of what a given discovery run saw, one row per entity. Never updated: the current state lives in disc_host and disc_instance.';
comment on column disc_finding.finding_id is 'Technical primary key of the finding.';
comment on column disc_finding.run_id is 'Run that produced the finding (FK to disc_run).';
comment on column disc_finding.finding_level is 'Level the finding applies to (HOST when the script could not name an instance, INSTANCE otherwise).';
comment on column disc_finding.platform is 'Database platform (ORACLE, MSSQL, POSTGRES, MYSQL).';
comment on column disc_finding.hostname is 'Machine the engine was found on.';
comment on column disc_finding.instance_name is 'Instance name, null for host-level findings.';
comment on column disc_finding.edition is 'Engine edition as observed.';
comment on column disc_finding.engine_version is 'Engine version as observed.';
comment on column disc_finding.patch_level is 'Patch level as observed.';
comment on column disc_finding.port is 'TCP port the instance listens on, when known.';
comment on column disc_finding.service_state is 'Service state as observed (Running, Stopped, ...).';
comment on column disc_finding.service_account is 'Account the service runs under.';
comment on column disc_finding.bitness is 'Engine bitness (64-bit, 32-bit).';
comment on column disc_finding.is_free_edition is 'Flag: 1 when the edition is free (Express, Developer, Evaluation).';
comment on column disc_finding.is_installed is 'Flag: 1 when the engine is installed on the host (package or binary present).';
comment on column disc_finding.process_count is 'Number of engine processes running at discovery time.';
comment on column disc_finding.ports_seen is 'Listening ports attributed to the engine, as reported.';
comment on column disc_finding.detection_note is 'How the entity was detected, or why the detection is partial.';


-- ============================================================
-- disc_host  (current state, one row per host and platform)
-- ============================================================
create table disc_host (
   disc_host_id    number generated by default on null as identity,
   platform        varchar2(10 char) not null,
   hostname        varchar2(150 char) not null,
   first_seen_date date not null,
   last_seen_date  date not null,
   is_installed    number(1),
   process_count   number(6),
   ports_seen      varchar2(100 char),
   triage_status   varchar2(10 char) default 'NEW' not null,
   triage_note     varchar2(400 char),
   constraint disc_host_pk primary key ( disc_host_id ),
   constraint disc_host_uk unique ( platform, hostname ),
   constraint disc_host_triage_ck check ( triage_status in ( 'NEW', 'IGNORED' ) )
);

comment on table disc_host is 'Current state of every host a discovery run has ever reported an engine on. Rows are never deleted: last_seen_date is what ages.';
comment on column disc_host.disc_host_id is 'Technical primary key of the discovered host.';
comment on column disc_host.platform is 'Database platform found on the host (ORACLE, MSSQL, POSTGRES, MYSQL). A host running two engines has one row per engine.';
comment on column disc_host.hostname is 'Machine name as reported by the discovery script.';
comment on column disc_host.first_seen_date is 'Date of the first run that reported this host, never rewritten.';
comment on column disc_host.last_seen_date is 'Date of the most recent run that reported this host.';
comment on column disc_host.is_installed is 'Flag: 1 when the engine is installed (package or binary present), regardless of it running.';
comment on column disc_host.process_count is 'Number of engine processes seen at the last run (0 = installed but not running).';
comment on column disc_host.ports_seen is 'Listening ports attributed to the engine at the last run.';
comment on column disc_host.triage_status is 'Human decision on this host: NEW (not triaged yet) or IGNORED (deliberately out of collection scope).';
comment on column disc_host.triage_note is 'Why the host was ignored, or any note left during triage.';


-- ============================================================
-- disc_instance  (current state, one row per named instance)
-- ============================================================
create table disc_instance (
   disc_instance_id number generated by default on null as identity,
   disc_host_id     number not null,
   platform         varchar2(10 char) not null,
   instance_name    varchar2(128 char) not null,
   first_seen_date  date not null,
   last_seen_date   date not null,
   edition          varchar2(100 char),
   engine_version   varchar2(50 char),
   patch_level      varchar2(50 char),
   port             number(5),
   service_state    varchar2(30 char),
   service_account  varchar2(150 char),
   bitness          varchar2(10 char),
   is_free_edition  number(1),
   triage_status    varchar2(10 char) default 'NEW' not null,
   triage_note      varchar2(400 char),
   constraint disc_instance_pk primary key ( disc_instance_id ),
   constraint disc_instance_uk unique ( disc_host_id, instance_name ),
   constraint disc_instance_host_fk foreign key ( disc_host_id )
      references disc_host ( disc_host_id ),
   constraint disc_instance_triage_ck check ( triage_status in ( 'NEW', 'IGNORED' ) )
);

comment on table disc_instance is 'Current state of every named instance discovery has reported. Fed by the MSSQL instances (rich attributes) and by the Oracle SIDs found on Linux. Postgres and MySQL stop at disc_host: the Linux script cannot name their instances.';
comment on column disc_instance.disc_instance_id is 'Technical primary key of the discovered instance.';
comment on column disc_instance.disc_host_id is 'Host the instance runs on (FK to disc_host).';
comment on column disc_instance.platform is 'Database platform (ORACLE, MSSQL, POSTGRES, MYSQL).';
comment on column disc_instance.instance_name is 'Instance name (MSSQLSERVER for a default SQL Server instance, SID for Oracle).';
comment on column disc_instance.first_seen_date is 'Date of the first run that reported this instance, never rewritten.';
comment on column disc_instance.last_seen_date is 'Date of the most recent run that reported this instance.';
comment on column disc_instance.edition is 'Engine edition as observed at the last run.';
comment on column disc_instance.engine_version is 'Engine version as observed at the last run.';
comment on column disc_instance.patch_level is 'Patch level as observed at the last run.';
comment on column disc_instance.port is 'TCP port the instance listens on. Required to promote the instance into the collection perimeter.';
comment on column disc_instance.service_state is 'Service state at the last run (Running, Stopped, Service absent).';
comment on column disc_instance.service_account is 'Account the service runs under.';
comment on column disc_instance.bitness is 'Engine bitness (64-bit, 32-bit).';
comment on column disc_instance.is_free_edition is 'Flag: 1 when the edition is free (Express, Developer, Evaluation). Feeds the licensing view of the estate.';
comment on column disc_instance.triage_status is 'Human decision on this instance: NEW (not triaged yet) or IGNORED (deliberately out of collection scope).';
comment on column disc_instance.triage_note is 'Why the instance was ignored, or any note left during triage.';

