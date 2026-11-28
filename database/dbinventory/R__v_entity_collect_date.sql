-- ============================================================
-- v_entity_collect_date
-- ------------------------------------------------------------
-- When was the data behind an instance actually collected. Single source of
-- truth for the freshness columns of fact_scoring: every consumer reads this
-- view, so changing where the date comes from stays a one-place change.
--
-- The date is read from collect_id, which all three collect chains write as
-- COLL_ID_YYYYMMDD. It is a real collect date, unlike date_value, which is a
-- `default systimestamp` stamped when the row lands in Oracle and therefore
-- dates the load, not the collect.
--
-- MIN across the sources, not MAX: an instance is only as fresh as its oldest
-- input. The inventory collect and the security collect run on separate
-- schedules, and a fresh inventory next to a three-week-old security collect
-- must not read as fresh.
--
-- Two sources per platform - the inventory anchor, which defines the instance,
-- and the security anchor, the domain most sensitive to staleness. Widening the
-- coverage is one more UNION branch.
--
-- A malformed collect_id yields no date rather than a wrong one: the regexp
-- guard drops it, and the instance ends up with NULL, which is distinguishable
-- from a collect dated today.
-- ============================================================
create or replace view v_entity_collect_date as
   select instance_id, min(collect_date) data_as_of
     from (
        -- MSSQL inventory
        select di.instance_id,
               to_date(substr(h.collect_id, 9), 'YYYYMMDD') collect_date
          from mssql_hosts h
          join dim_instance di on di.platform = 'MSSQL' and di.instance_name = h.hostname
         where regexp_like(h.collect_id, '^COLL_ID_[0-9]{8}$')
        union all
        -- MSSQL security
        select di.instance_id,
               to_date(substr(c.collect_id, 9), 'YYYYMMDD')
          from mssql_security_configoptions c
          join dim_instance di on di.platform = 'MSSQL' and di.instance_name = c.servername
         where regexp_like(c.collect_id, '^COLL_ID_[0-9]{8}$')
        union all
        -- Oracle inventory
        select di.instance_id,
               to_date(substr(od.collect_id, 9), 'YYYYMMDD')
          from oracle_databases od
          join dim_host dh on dh.platform = 'ORACLE' and dh.hostname = od.hostname
          join dim_instance di on di.host_id = dh.host_id and di.instance_name = od.instance_name
         where regexp_like(od.collect_id, '^COLL_ID_[0-9]{8}$')
        union all
        -- Oracle security, resolved through the inventory the same way the
        -- security ETL resolves its own entities
        select di.instance_id,
               to_date(substr(sp.collect_id, 9), 'YYYYMMDD')
          from oracle_security_parameter sp
          join oracle_databases od on od.db_name = sp.db_name
          join dim_host dh on dh.platform = 'ORACLE' and dh.hostname = od.hostname
          join dim_instance di on di.host_id = dh.host_id and di.instance_name = od.instance_name
         where regexp_like(sp.collect_id, '^COLL_ID_[0-9]{8}$')
        union all
        -- PostgreSQL inventory: instance_name = hostname, see load_dim_instance
        select di.instance_id,
               to_date(substr(ph.collect_id, 9), 'YYYYMMDD')
          from postgres_hosts ph
          join dim_instance di on di.platform = 'POSTGRES' and di.instance_name = ph.hostname
         where regexp_like(ph.collect_id, '^COLL_ID_[0-9]{8}$')
        union all
        -- PostgreSQL security. Collected on primaries only, so a standby is
        -- dated by its inventory alone.
        select di.instance_id,
               to_date(substr(ps.collect_id, 9), 'YYYYMMDD')
          from postgres_security_parameter ps
          join dim_instance di on di.platform = 'POSTGRES' and di.instance_name = ps.hostname
         where regexp_like(ps.collect_id, '^COLL_ID_[0-9]{8}$')
     )
    group by instance_id;

comment on table v_entity_collect_date is 'Collect date of the data behind each instance, taken as the oldest of its inputs; feeds the freshness columns of fact_scoring.';
