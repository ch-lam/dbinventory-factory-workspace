-- ============================================================================
-- V__007_create_discovery_etl.sql
-- ----------------------------------------------------------------------------
-- ETL package pkg_dbinv_discovery: populates the discovery area (V__006) from
-- the discovery staging tables, and promotes a discovered instance into the
-- collection perimeter.
--
-- Design, aligned on pkg_dbinv_inventory (V__004):
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

create or replace package body pkg_dbinv_discovery as

   -- ---------------------------------------------------------------------
   -- load_run
   -- ---------------------------------------------------------------------
   function load_run (
      p_source   varchar2,
      p_run_date date default trunc(sysdate)
   ) return number is
      l_run_id number;
   begin
      merge into disc_run r
      using ( select p_source           as source,
                     trunc(p_run_date)  as run_date
                from dual ) s
      on ( r.source = s.source
           and r.run_date = s.run_date )
      when not matched then
         insert ( source, run_date )
         values ( s.source, s.run_date );

      select run_id
        into l_run_id
        from disc_run
       where source = p_source
         and run_date = trunc(p_run_date);

      return l_run_id;
   end load_run;


   -- ---------------------------------------------------------------------
   -- load_findings_mssql
   -- One staging row = one finding. A row without an instance name is a
   -- host-level finding: that is the "port answered but WMI gave nothing"
   -- case the PowerShell script deliberately keeps rather than dropping.
   -- ---------------------------------------------------------------------
   procedure load_findings_mssql ( p_run_id number ) is
   begin
      delete from disc_finding
       where run_id = p_run_id;

      insert into disc_finding (
         run_id, finding_level, platform, hostname, instance_name,
         edition, engine_version, patch_level, port,
         service_state, service_account, bitness, is_free_edition,
         is_installed, process_count, ports_seen, detection_note
      )
         select p_run_id,
                case
                   when s.instance is not null then 'INSTANCE'
                   else 'HOST'
                end,
                'MSSQL',
                trim(s.serveur),
                trim(s.instance),
                trim(s.edition),
                trim(s.version),
                trim(s.patch),
                to_number(trim(s.tcpport) default null on conversion error),
                trim(s.etatservice),
                trim(s.compteservice),
                trim(s.bitness),
                case
                   when upper(trim(s.editiongratuite)) = 'TRUE' then 1
                   when upper(trim(s.editiongratuite)) = 'FALSE' then 0
                end,
                -- The registry key exists, so the engine is installed, whether
                -- or not its service happens to be running.
                1,
                case
                   when upper(trim(s.etatservice)) = 'RUNNING' then 1
                   when s.etatservice is null then null
                   else 0
                end,
                trim(s.portsql),
                trim(s.statut)
           from discovery_mssql_inst s
          where s.serveur is not null;
   end load_findings_mssql;


   -- ---------------------------------------------------------------------
   -- load_findings_linux
   -- The staging row is wide (three engines on one line). It is denormalised
   -- into one finding per engine actually detected, and the Oracle SID list is
   -- split into one finding per SID - the only case where the Linux script can
   -- name an instance. Postgres and MySQL stay at host level.
   -- '-' is the script's empty marker and must not be stored as a value.
   -- ---------------------------------------------------------------------
   procedure load_findings_linux ( p_run_id number ) is
   begin
      delete from disc_finding
       where run_id = p_run_id;

      -- Postgres and MySQL: host level only.
      insert into disc_finding (
         run_id, finding_level, platform, hostname,
         is_installed, process_count, ports_seen, detection_note
      )
         select p_run_id,
                'HOST',
                e.platform,
                trim(e.hostn),
                e.is_installed,
                e.process_count,
                e.ports_seen,
                'Linux engine detection'
           from ( select s.hostn,
                         'POSTGRES'                                            as platform,
                         case when upper(trim(s.pg_pkg)) = 'Y' then 1 else 0 end as is_installed,
                         to_number(trim(s.pg_proc) default null on conversion error) as process_count,
                         nullif(trim(s.pg_port), '-')                          as ports_seen
                    from discovery_linux_engines s
                   union all
                  select s.hostn,
                         'MYSQL',
                         case when upper(trim(s.my_pkg)) = 'Y' then 1 else 0 end,
                         to_number(trim(s.my_proc) default null on conversion error),
                         nullif(trim(s.my_port), '-')
                    from discovery_linux_engines s ) e
          where e.hostn is not null
            and ( e.is_installed = 1
                  or e.process_count > 0
                  or e.ports_seen is not null );

      -- Oracle: one finding per SID when the listener/pmon gave us names,
      -- otherwise a single host-level finding saying the software is there.
      insert into disc_finding (
         run_id, finding_level, platform, hostname, instance_name,
         is_installed, process_count, ports_seen, detection_note
      )
         select p_run_id,
                case
                   when o.sid is not null then 'INSTANCE'
                   else 'HOST'
                end,
                'ORACLE',
                trim(o.hostn),
                o.sid,
                o.is_installed,
                o.process_count,
                o.ports_seen,
                'Linux engine detection'
           from ( select s.hostn,
                         trim(regexp_substr(nullif(trim(s.ora_sids), '-'),
                                            '[^,]+', 1, lv.column_value))      as sid,
                         case when upper(trim(s.ora_pkg)) = 'Y' then 1 else 0 end as is_installed,
                         to_number(trim(s.ora_proc) default null on conversion error) as process_count,
                         nullif(trim(s.ora_port), '-')                         as ports_seen
                    from discovery_linux_engines s,
                         table ( cast ( multiset (
                            select level
                              from dual
                           connect by level <=
                              greatest(regexp_count(nullif(trim(s.ora_sids), '-'), ',') + 1, 1)
                         ) as sys.odcinumberlist ) ) lv ) o
          where o.hostn is not null
            and ( o.is_installed = 1
                  or o.process_count > 0
                  or o.ports_seen is not null
                  or o.sid is not null );
   end load_findings_linux;


   -- ---------------------------------------------------------------------
   -- merge_hosts
   -- Fed by findings of BOTH levels: an instance-level finding implies its
   -- host. The source is grouped so the MERGE sees exactly one row per
   -- (platform, hostname) - several instances on one machine would otherwise
   -- raise ORA-30926.
   -- ---------------------------------------------------------------------
   procedure merge_hosts ( p_run_id number ) is
      l_run_date date;
   begin
      select run_date into l_run_date from disc_run where run_id = p_run_id;

      merge into disc_host h
      using ( select f.platform,
                     f.hostname,
                     max(f.is_installed)  as is_installed,
                     max(f.process_count) as process_count,
                     max(f.ports_seen)    as ports_seen
                from disc_finding f
               where f.run_id = p_run_id
               group by f.platform, f.hostname ) s
      on ( h.platform = s.platform
           and h.hostname = s.hostname )
      when matched then
         update
            set h.last_seen_date = l_run_date,
                h.is_installed   = s.is_installed,
                h.process_count  = s.process_count,
                h.ports_seen     = s.ports_seen
      when not matched then
         insert ( platform, hostname, first_seen_date, last_seen_date,
                  is_installed, process_count, ports_seen )
         values ( s.platform, s.hostname, l_run_date, l_run_date,
                  s.is_installed, s.process_count, s.ports_seen );
   end merge_hosts;


   -- ---------------------------------------------------------------------
   -- merge_instances
   -- ---------------------------------------------------------------------
   procedure merge_instances ( p_run_id number ) is
      l_run_date date;
   begin
      select run_date into l_run_date from disc_run where run_id = p_run_id;

      merge into disc_instance i
      using ( select h.disc_host_id,
                     f.platform,
                     f.instance_name,
                     max(f.edition)         as edition,
                     max(f.engine_version)  as engine_version,
                     max(f.patch_level)     as patch_level,
                     max(f.port)            as port,
                     max(f.service_state)   as service_state,
                     max(f.service_account) as service_account,
                     max(f.bitness)         as bitness,
                     max(f.is_free_edition) as is_free_edition
                from disc_finding f
                join disc_host h
              on h.platform = f.platform
                 and h.hostname = f.hostname
               where f.run_id = p_run_id
                 and f.finding_level = 'INSTANCE'
               group by h.disc_host_id, f.platform, f.instance_name ) s
      on ( i.disc_host_id = s.disc_host_id
           and i.instance_name = s.instance_name )
      when matched then
         update
            set i.last_seen_date  = l_run_date,
                i.edition         = s.edition,
                i.engine_version  = s.engine_version,
                i.patch_level     = s.patch_level,
                i.port            = s.port,
                i.service_state   = s.service_state,
                i.service_account = s.service_account,
                i.bitness         = s.bitness,
                i.is_free_edition = s.is_free_edition
      when not matched then
         insert ( disc_host_id, platform, instance_name,
                  first_seen_date, last_seen_date,
                  edition, engine_version, patch_level, port,
                  service_state, service_account, bitness, is_free_edition )
         values ( s.disc_host_id, s.platform, s.instance_name,
                  l_run_date, l_run_date,
                  s.edition, s.engine_version, s.patch_level, s.port,
                  s.service_state, s.service_account, s.bitness, s.is_free_edition );
   end merge_instances;


   -- ---------------------------------------------------------------------
   -- Per-source loads
   -- ---------------------------------------------------------------------
   procedure finish_run ( p_run_id number ) is
   begin
      update disc_run r
         set ( host_count, finding_count ) = (
                select count(distinct f.hostname), count(*)
                  from disc_finding f
                 where f.run_id = r.run_id )
       where r.run_id = p_run_id;
   end finish_run;


   procedure load_mssql ( p_run_date date default trunc(sysdate) ) is
      l_run_id  number;
      l_staged  number;
   begin
      select count(*) into l_staged from discovery_mssql_inst;
      if l_staged = 0 then
         return;   -- nothing staged: no run, rather than an empty run that
                   -- would look like a discovery that found nothing.
      end if;

      l_run_id := load_run('MSSQL_WINDOWS', p_run_date);
      load_findings_mssql(l_run_id);
      merge_hosts(l_run_id);
      merge_instances(l_run_id);
      finish_run(l_run_id);
   end load_mssql;


   procedure load_linux ( p_run_date date default trunc(sysdate) ) is
      l_run_id number;
      l_staged number;
   begin
      select count(*) into l_staged from discovery_linux_engines;
      if l_staged = 0 then
         return;
      end if;

      l_run_id := load_run('LINUX_SALT', p_run_date);
      load_findings_linux(l_run_id);
      merge_hosts(l_run_id);
      merge_instances(l_run_id);
      finish_run(l_run_id);
   end load_linux;


   procedure load_all ( p_run_date date default trunc(sysdate) ) is
   begin
      load_mssql(p_run_date);
      load_linux(p_run_date);
      commit;
   end load_all;


   -- ---------------------------------------------------------------------
   -- one_port
   -- The port a host is listening on, when there is exactly one candidate.
   --
   -- disc_host.ports_seen holds what the Linux detection reported: a
   -- comma-separated list, or a single port, or nothing. Oracle and PostgreSQL
   -- perimeters need ONE port, and this returns it only when the answer is not
   -- a guess -- several ports listed means the human must choose, and saying
   -- nothing is how this function says so.
   -- ---------------------------------------------------------------------
   function one_port ( p_ports_seen varchar2 ) return number is
      l_clean varchar2(100 char) := trim(p_ports_seen);
   begin
      if l_clean is null or instr(l_clean, ',') > 0 then
         return null;
      end if;
      return to_number(l_clean default null on conversion error);
   end one_port;

   -- ---------------------------------------------------------------------
   -- promote_instance
   -- Adds a discovered INSTANCE to the collection perimeter, which lives in
   -- the *_collect_list tables. Re-promoting an entry that was disabled
   -- reactivates it rather than failing.
   --
   -- Two platforms reach this level, and they need different things, because
   -- their perimeter tables are shaped differently:
   --   * MSSQL     keyed on (hostname, port), both of which the Windows
   --               discovery reads from the registry. Nothing to add.
   --   * ORACLE    keyed on collect_name, and holding an easy_connect_tns
   --               (host:port/service). The discovery yields a SID from
   --               ora_pmon_<SID> -- which is NOT a service name -- and the
   --               listener ports at HOST level, never per instance. So the
   --               service name, the collect_name and, when the host listens
   --               on several ports, the port itself are human input. They are
   --               asked for rather than guessed: an easy_connect built on a
   --               SID would produce a perimeter entry that silently fails to
   --               connect every night.
   --
   -- PostgreSQL never reaches this level (the Linux detection does not descend
   -- below the host) and MySQL has no perimeter table at all. Both are refused
   -- here, by name, rather than left to fail on a null.
   -- ---------------------------------------------------------------------
   procedure promote_instance (
      p_disc_instance_id number,
      p_environment      varchar2,
      p_license_type     varchar2,
      p_collect_name     varchar2 default null,
      p_service_name     varchar2 default null,
      p_port             number default null
   ) is
      l_platform   varchar2(10 char);
      l_hostname   varchar2(150 char);
      l_instance   varchar2(128 char);
      l_port       number;
      l_host_ports varchar2(100 char);
      l_tns        varchar2(150 char);
   begin
      select i.platform, h.hostname, i.instance_name, i.port, h.ports_seen
        into l_platform, l_hostname, l_instance, l_port, l_host_ports
        from disc_instance i
        join disc_host h
      on h.disc_host_id = i.disc_host_id
       where i.disc_instance_id = p_disc_instance_id;

      if l_platform = 'MYSQL' then
         raise_application_error(-20001,
            'MySQL has no collection perimeter: dbInventory does not collect it. '
            || 'Record the decision with set_triage instead.');
      elsif l_platform = 'POSTGRES' then
         raise_application_error(-20007,
            'PostgreSQL is discovered at host level, not instance level: '
            || 'use promote_host.');
      elsif l_platform not in ( 'MSSQL', 'ORACLE' ) then
         raise_application_error(-20001,
            'Promotion is not supported for ' || l_platform || '.');
      end if;

      -- The port: what discovery knows, unless the caller overrides it. Oracle
      -- knows it only at host level, and only when the host listens on one.
      l_port := coalesce(p_port, l_port, one_port(l_host_ports));

      if l_port is null then
         raise_application_error(-20002,
            'Instance ' || l_hostname || ' / ' || l_instance
            || ' has no known TCP port: it cannot be collected. '
            || case l_platform
                  when 'MSSQL' then
                     'Re-run the Windows discovery so it reads the port from the registry.'
                  else
                     'The listener ports seen on the host were: '
                     || nvl(l_host_ports, '(none)') || '. Pass the one to collect.'
               end);
      end if;

      if l_platform = 'MSSQL' then

         -- Matched case-insensitively, although the primary key of the perimeter is
         -- the raw (hostname, port): the two spellings are the same machine, and a
         -- case-sensitive match would insert a second row instead of reactivating
         -- the first, putting the host twice in the generated .lst and collecting
         -- it twice. The perimeter really does hold mixed case (ora-dev vs ORA-DEV
         -- in the Oracle list), and v_discovery_status already reconciles with
         -- lower() - this is the same rule, applied on the write side.
         -- The existing spelling is kept on update; only a genuinely new host is
         -- inserted with the spelling discovery reported.
         merge into mssql_collect_list cl
         using ( select l_hostname as hostname, l_port as port from dual ) s
         on ( lower(cl.hostname) = lower(s.hostname)
              and cl.port = s.port )
         when matched then
            update
               set cl.environment  = p_environment,
                   cl.license_type = p_license_type,
                   cl.active       = 1
         when not matched then
            insert ( hostname, port, environment, license_type, active )
            values ( s.hostname, s.port, p_environment, p_license_type, 1 );

      else

         if p_collect_name is null then
            raise_application_error(-20008,
               'Oracle perimeter entries are keyed on a collect_name, which is a '
               || 'human choice: pass one for ' || l_hostname || ' / ' || l_instance || '.');
         end if;

         if p_service_name is null then
            raise_application_error(-20009,
               'Oracle needs the database SERVICE name to build its connect string. '
               || 'The discovery only found the SID ' || l_instance
               || ', which is not the same thing.');
         end if;

         l_tns := l_hostname || ':' || l_port || '/' || p_service_name;

         merge into oracle_collect_list cl
         using ( select upper(p_collect_name) as collect_name from dual ) s
         on ( upper(cl.collect_name) = s.collect_name )
         when matched then
            update
               set cl.easy_connect_tns = l_tns,
                   cl.environment      = p_environment,
                   cl.license_type     = p_license_type,
                   cl.active           = 1
         when not matched then
            insert ( collect_name, easy_connect_tns, environment, license_type, active )
            values ( s.collect_name, l_tns, p_environment, p_license_type, 1 );

      end if;

      update disc_instance
         set triage_status = 'NEW',
             triage_note   = null
       where disc_instance_id = p_disc_instance_id;

      -- No commit: promotion is an interactive action, the caller owns the
      -- transaction (APEX commits at the end of the page submit).
   exception
      when no_data_found then
         raise_application_error(-20003,
            'No discovered instance with id ' || p_disc_instance_id || '.');
   end promote_instance;

   -- ---------------------------------------------------------------------
   -- promote_host
   -- The host-level counterpart. It exists because PostgreSQL is only ever
   -- discovered at host level: detect_db_engines.sh reports "an engine is
   -- installed and listening on this port" and cannot name an instance, so
   -- there is no disc_instance row to pass to promote_instance. Forcing an
   -- instance id that does not exist would have been the alternative.
   --
   -- It also serves the MSSQL machine whose port answered while WMI refused:
   -- the host is known, the instance is not, and hostname + port is exactly
   -- what mssql_collect_list is keyed on.
   --
   -- Oracle is refused here: a host-level Oracle finding means the software is
   -- installed but no SID was resolved, and without a SID there is no service,
   -- hence no connect string. That is a discovery to re-run, not a decision to
   -- record.
   -- ---------------------------------------------------------------------
   procedure promote_host (
      p_disc_host_id number,
      p_environment  varchar2,
      p_license_type varchar2,
      p_collect_name varchar2 default null,
      p_port         number default null
   ) is
      l_platform   varchar2(10 char);
      l_hostname   varchar2(150 char);
      l_host_ports varchar2(100 char);
      l_port       number;
   begin
      select h.platform, h.hostname, h.ports_seen
        into l_platform, l_hostname, l_host_ports
        from disc_host h
       where h.disc_host_id = p_disc_host_id;

      if l_platform = 'MYSQL' then
         raise_application_error(-20001,
            'MySQL has no collection perimeter: dbInventory does not collect it. '
            || 'Record the decision with set_triage instead.');
      elsif l_platform = 'ORACLE' then
         raise_application_error(-20010,
            'Oracle was found installed on ' || l_hostname
            || ' but no SID was resolved, so no service and no connect string. '
            || 'Re-run the discovery on that host rather than recording a guess.');
      elsif l_platform not in ( 'MSSQL', 'POSTGRES' ) then
         raise_application_error(-20001,
            'Promotion is not supported for ' || l_platform || '.');
      end if;

      l_port := coalesce(p_port, one_port(l_host_ports));

      if l_port is null then
         raise_application_error(-20002,
            'Host ' || l_hostname || ' has no single known port: it cannot be '
            || 'collected. Ports seen: ' || nvl(l_host_ports, '(none)')
            || '. Pass the one to collect.');
      end if;

      if l_platform = 'MSSQL' then

         merge into mssql_collect_list cl
         using ( select l_hostname as hostname, l_port as port from dual ) s
         on ( lower(cl.hostname) = lower(s.hostname)
              and cl.port = s.port )
         when matched then
            update
               set cl.environment  = p_environment,
                   cl.license_type = p_license_type,
                   cl.active       = 1
         when not matched then
            insert ( hostname, port, environment, license_type, active )
            values ( s.hostname, s.port, p_environment, p_license_type, 1 );

      else

         if p_collect_name is null then
            raise_application_error(-20008,
               'PostgreSQL perimeter entries are keyed on a collect_name, which is '
               || 'a human choice: pass one for ' || l_hostname || '.');
         end if;

         merge into postgres_collect_list cl
         using ( select upper(p_collect_name) as collect_name from dual ) s
         on ( upper(cl.collect_name) = s.collect_name )
         when matched then
            update
               set cl.hostname     = l_hostname,
                   cl.port         = l_port,
                   cl.environment  = p_environment,
                   cl.license_type = p_license_type,
                   cl.active       = 1
         when not matched then
            insert ( collect_name, hostname, port, environment, license_type, active )
            values ( s.collect_name, l_hostname, l_port, p_environment, p_license_type, 1 );

      end if;

      update disc_host
         set triage_status = 'NEW',
             triage_note   = null
       where disc_host_id = p_disc_host_id;

      -- No commit, same reason as promote_instance.
   exception
      when no_data_found then
         raise_application_error(-20003,
            'No discovered host with id ' || p_disc_host_id || '.');
   end promote_host;


   -- ---------------------------------------------------------------------
   -- set_triage
   -- ---------------------------------------------------------------------
   procedure set_triage (
      p_level     varchar2,
      p_entity_id number,
      p_status    varchar2,
      p_note      varchar2 default null
   ) is
   begin
      if p_status not in ( 'NEW', 'IGNORED' ) then
         raise_application_error(-20004,
            'Triage status must be NEW or IGNORED, got ' || p_status || '.');
      end if;

      if p_level = 'INSTANCE' then
         update disc_instance
            set triage_status = p_status,
                triage_note   = p_note
          where disc_instance_id = p_entity_id;
      elsif p_level = 'HOST' then
         update disc_host
            set triage_status = p_status,
                triage_note   = p_note
          where disc_host_id = p_entity_id;
      else
         raise_application_error(-20005,
            'Triage level must be HOST or INSTANCE, got ' || p_level || '.');
      end if;

      if sql%rowcount = 0 then
         raise_application_error(-20006,
            'No ' || p_level || ' with id ' || p_entity_id || '.');
      end if;
      -- No commit: see promote_instance.
   end set_triage;

end pkg_dbinv_discovery;
/
