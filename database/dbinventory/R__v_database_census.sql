-- ============================================================
-- v_database_census  (how many databases each snapshot saw)
-- ------------------------------------------------------------
-- One row per platform and snapshot: the databases the collect actually
-- measured that day, and what changed since the previous snapshot of the same
-- platform. Feeds the Databases counters of the dashboard (page 1).
--
-- Why not dim_database: it is merged and never purged, so it counts every
-- database ever seen, including those dropped or taken out of the perimeter.
-- A database "seen" on a snapshot is one with a storage measure that day:
-- every collected database has one (tablespaces, data/log files, PostgreSQL
-- database size). Limit: an Oracle PDB whose tablespaces were not collected
-- (closed or mounted) is not counted.
--
-- Same population as the dashboard always showed: MSSQL system databases and
-- the PostgreSQL maintenance database are left out. No previous snapshot:
-- previous_*, added_count and removed_count are NULL, not zero.
-- ============================================================
create or replace view v_database_census as
with seen as (
   select distinct d.platform, d.database_id, f.snapshot_date
     from fact_storage_capacity f
     join dim_storage_unit su on su.storage_unit_id = f.storage_unit_id
     join dim_database d on d.database_id = su.database_id
    where not ( d.platform = 'MSSQL' and d.db_name in ( 'master', 'msdb', 'tempdb', 'model' ) )
      and not ( d.platform = 'POSTGRES' and d.db_name = 'postgres' )
),
snaps as (
   select platform, snapshot_date,
          lag(snapshot_date) over ( partition by platform order by snapshot_date ) previous_snapshot_date
     from ( select distinct platform, snapshot_date from seen )
)
select sn.platform,
       sn.snapshot_date,
       ( select count(*) from seen s
          where s.platform = sn.platform and s.snapshot_date = sn.snapshot_date ) database_count,
       sn.previous_snapshot_date,
       case when sn.previous_snapshot_date is not null then
          ( select count(*) from seen s
             where s.platform = sn.platform and s.snapshot_date = sn.previous_snapshot_date )
       end previous_count,
       case when sn.previous_snapshot_date is not null then
          ( select count(*) from seen s
             where s.platform = sn.platform and s.snapshot_date = sn.snapshot_date
               and not exists ( select 1 from seen o
                                 where o.database_id = s.database_id
                                   and o.snapshot_date = sn.previous_snapshot_date ) )
       end added_count,
       case when sn.previous_snapshot_date is not null then
          ( select count(*) from seen o
             where o.platform = sn.platform and o.snapshot_date = sn.previous_snapshot_date
               and not exists ( select 1 from seen s
                                 where s.database_id = o.database_id
                                   and s.snapshot_date = sn.snapshot_date ) )
       end removed_count
  from snaps sn;

comment on table v_database_census is 'Databases measured per platform and snapshot, with the count, additions and removals since the previous snapshot; feeds the dashboard Databases counters.';
