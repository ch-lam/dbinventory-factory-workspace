-- ============================================================
-- v_discovery_status
-- Reconciliation between what discovery sees and what we collect.
-- ============================================================
-- The collected/not-collected state is NOT stored anywhere in this area: it is
-- derived here by joining the *_collect_list tables, which are the perimeter's
-- single source of truth. Storing it would create a second truth about the
-- perimeter that could silently drift from the first.
--
-- level_name:
--   INSTANCE   a discovered instance (MSSQL instance, Oracle SID)
--   HOST       a discovered host on which no instance could be named, which is
--              every PostgreSQL and MySQL finding: the Linux detection reports
--              "engine present on this port" and never descends below the host
--   PERIMETER  not a discovery finding at all -- an entry of the collect list
--              that no run has reported. It carries no entity_id because there
--              is nothing discovered to point at, and the triage screen has
--              nothing to decide about it. It said INSTANCE until 2026-09-06,
--              which made the screen link it to a triage dialog that could only
--              fail on a null id.
--
-- effective_status:
--   COLLECTED  discovered and in the collection perimeter (active)
--   IGNORED    deliberately out of scope, either triaged as such or present in
--              the perimeter registry but disabled
--   NEW        discovered, not in the perimeter, not triaged yet
--   NOT_SEEN   in the active perimeter but absent from every discovery run
--
-- days_since_last_seen is the only ageing signal. It carries no verdict: a host
-- that stops being discovered may have been decommissioned or may simply have
-- been down on the day of the run.
--
-- Matching a discovered MSSQL instance to its perimeter entry:
--   * on (hostname, port) whenever discovery knows the port - the only exact
--     rule, and the one that applies once the Windows discovery reads TcpPort
--     from the registry;
--   * otherwise on hostname alone, but only when it cannot be ambiguous, i.e.
--     the host runs a single instance, or the instance is the default one.
-- The fallback exists because the collect list is keyed on (hostname, port)
-- while holding one row per machine, all on 1433: requiring the port would
-- match nothing before TcpPort exists, and would still miss the 11 hosts that
-- are collected today while running a NAMED instance declared on 1433.
-- Matching on hostname alone would be wrong the other way round: on a machine
-- running two instances it would report both as collected when only one is.
--
-- Matching an Oracle SID: oracle_collect_list holds neither a hostname nor a
-- port, only easy_connect_tns (host:port/service), so both are parsed out of
-- it. The comparison is SID against SERVICE, which is an approximation the
-- model cannot avoid -- a SID is not a service name, and the discovery has no
-- way to learn the service. It is deliberately made per-service and not
-- per-host: a single machine commonly carries several databases, of which only
-- some are collected, and a host-level match would declare all of them
-- COLLECTED. A false negative here reads as NEW, which a human then triages;
-- a false positive would silently hide an uncollected database.
--
-- Matching a PostgreSQL host: postgres_collect_list is keyed on hostname, and
-- the discovery does not descend below the host, so hostname is the whole rule.
--
-- Host names are compared on their first label as well as in full: the Windows
-- discovery reports FQDNs, hostname(1) on Linux usually does not, and the
-- perimeter holds whichever was typed. Comparing only in full would report a
-- collected Linux host as NEW forever. The looseness is bounded by the platform
-- being part of every match, and by the CHL running a single domain.
--
-- The match is a scalar subquery rather than a join so that a host with several
-- perimeter rows can never multiply the discovery rows.
create or replace view v_discovery_status as
   select 'INSTANCE'                                  as level_name,
          di.disc_instance_id                         as entity_id,
          dh.platform                                 as platform,
          dh.hostname                                 as hostname,
          di.instance_name                            as instance_name,
          di.port                                     as port,
          di.edition                                  as edition,
          di.engine_version                           as engine_version,
          di.is_free_edition                          as is_free_edition,
          di.first_seen_date                          as first_seen_date,
          di.last_seen_date                           as last_seen_date,
          trunc(sysdate) - di.last_seen_date          as days_since_last_seen,
          case
             when trunc(sysdate) - di.last_seen_date > 30 then 1
             else 0
          end                                         as is_stale,
          case
             when m.collect_active = 1 then 'COLLECTED'
             when di.triage_status = 'IGNORED'
                  or m.collect_active = 0 then 'IGNORED'
             else 'NEW'
          end                                         as effective_status,
          di.triage_note                              as triage_note
     from disc_instance di
     join disc_host dh
   on dh.disc_host_id = di.disc_host_id
     outer apply ( select max(active) as collect_active
                     from ( select cl.active
                              from mssql_collect_list cl
                             where dh.platform = 'MSSQL'
                               and lower(cl.hostname) = lower(dh.hostname)
                               and ( cl.port = di.port
                                     or ( di.port is null
                                          and ( di.instance_name = 'MSSQLSERVER'
                                                or 1 = ( select count(*)
                                                           from disc_instance x
                                                          where x.disc_host_id = di.disc_host_id ) ) ) )
                            union all
                            select cl.active
                              from oracle_collect_list cl
                             where dh.platform = 'ORACLE'
                               and lower(regexp_substr(cl.easy_connect_tns, '^[^:/]+'))
                                   in ( lower(dh.hostname),
                                        lower(regexp_substr(dh.hostname, '^[^.]+')) )
                               and lower(regexp_substr(regexp_substr(cl.easy_connect_tns, '[^/]+$'), '^[^.]+'))
                                   = lower(di.instance_name) ) ) m
    union all
   select 'HOST'                                      as level_name,
          dh.disc_host_id                             as entity_id,
          dh.platform                                 as platform,
          dh.hostname                                 as hostname,
          cast(null as varchar2(128 char))            as instance_name,
          cast(null as number)                        as port,
          cast(null as varchar2(100 char))            as edition,
          cast(null as varchar2(50 char))             as engine_version,
          cast(null as number)                        as is_free_edition,
          dh.first_seen_date                          as first_seen_date,
          dh.last_seen_date                           as last_seen_date,
          trunc(sysdate) - dh.last_seen_date          as days_since_last_seen,
          case
             when trunc(sysdate) - dh.last_seen_date > 30 then 1
             else 0
          end                                         as is_stale,
          case
             when m.collect_active = 1 then 'COLLECTED'
             when dh.triage_status = 'IGNORED'
                  or m.collect_active = 0 then 'IGNORED'
             else 'NEW'
          end                                         as effective_status,
          dh.triage_note                              as triage_note
     from disc_host dh
     outer apply ( select max(active) as collect_active
                     from ( select cl.active
                              from postgres_collect_list cl
                             where dh.platform = 'POSTGRES'
                               and lower(cl.hostname)
                                   in ( lower(dh.hostname),
                                        lower(regexp_substr(dh.hostname, '^[^.]+')) )
                            union all
                            -- A host-level MSSQL finding is the "port answered,
                            -- WMI refused" case: the machine is known, the
                            -- instance is not. Hostname is all there is to match.
                            select cl.active
                              from mssql_collect_list cl
                             where dh.platform = 'MSSQL'
                               and lower(cl.hostname) = lower(dh.hostname) ) ) m
    where not exists (
      select 1
        from disc_instance di
       where di.disc_host_id = dh.disc_host_id
   )
    union all
-- The reverse reading: perimeter entries we actively collect that no discovery
-- run has ever reported. Either the discovery does not reach them, or they are
-- gone. MySQL has no perimeter table, so it cannot appear here at all.
   select 'PERIMETER'                                 as level_name,
          cast(null as number)                        as entity_id,
          p.platform                                  as platform,
          p.hostname                                  as hostname,
          p.instance_name                             as instance_name,
          p.port                                      as port,
          cast(null as varchar2(100 char))            as edition,
          cast(null as varchar2(50 char))             as engine_version,
          cast(null as number)                        as is_free_edition,
          cast(null as date)                          as first_seen_date,
          cast(null as date)                          as last_seen_date,
          cast(null as number)                        as days_since_last_seen,
          0                                           as is_stale,
          'NOT_SEEN'                                  as effective_status,
          cast(null as varchar2(400 char))            as triage_note
     from ( select 'MSSQL'                                  as platform,
                   cl.hostname                              as hostname,
                   cast(null as varchar2(128 char))         as instance_name,
                   cl.port                                  as port
              from mssql_collect_list cl
             where cl.active = 1
            union all
            select 'ORACLE',
                   regexp_substr(cl.easy_connect_tns, '^[^:/]+'),
                   cast(regexp_substr(regexp_substr(cl.easy_connect_tns, '[^/]+$'), '^[^.]+')
                        as varchar2(128 char)),
                   to_number(regexp_substr(cl.easy_connect_tns, ':([0-9]+)', 1, 1, null, 1)
                             default null on conversion error)
              from oracle_collect_list cl
             where cl.active = 1
            union all
            select 'POSTGRES',
                   cl.hostname,
                   cast(null as varchar2(128 char)),
                   cl.port
              from postgres_collect_list cl
             where cl.active = 1 ) p
    where not exists (
      select 1
        from disc_host dh
       where dh.platform = p.platform
         and lower(dh.hostname) in ( lower(p.hostname),
                                     lower(regexp_substr(p.hostname, '^[^.]+')) )
   );
comment on table v_discovery_status is 'Reconciliation of the discovery findings against the collection perimeter, over the three engines that have one. Drives the APEX triage screen. Collected status is derived from *_collect_list, never stored. level_name PERIMETER marks a row that is not a discovery finding but a collect list entry nothing reported, and therefore carries no entity_id.';
