-- ============================================================
-- v_database_without_application
-- ------------------------------------------------------------
-- The databases nobody claims. This is the view that makes the registry useful
-- rather than decorative: it measures what is left to do, and it never falls to
-- zero on its own -- a new database appears here the moment the ETL discovers
-- it, which is exactly when someone should be asked whose it is.
-- ============================================================
create or replace view v_database_without_application as
   select d.database_id,
          d.platform,
          d.db_name,
          d.environment,
          i.instance_name,
          h.hostname
     from dim_database d
     join dim_instance i
       on i.instance_id = d.instance_id
     join dim_host h
       on h.host_id = i.host_id
    where not exists ( select 1
                         from v_application_database ad
                        where ad.database_id = d.database_id );

comment on table v_database_without_application is 'Databases attached to no application; the backlog of the registry, and the first thing to look at after a collect discovers something new.';
