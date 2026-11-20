-- ============================================================
-- v_application_database
-- ------------------------------------------------------------
-- The databases an application actually covers, attachment cascade included.
-- Reads v_entity_ancestry, the same view the exceptions use to cascade downwards,
-- so the two features can never disagree about what "below an instance" means.
--
-- attached_at says how the database was reached. It matters when reading the
-- result: a database listed because its whole instance belongs to the
-- application is a different statement from one named explicitly, and detaching
-- them is a different action.
-- ============================================================
create or replace view v_application_database as
   select ae.application_id,
          a.app_code,
          a.app_name,
          d.database_id,
          d.instance_id,
          d.host_id,
          ae.entity_type   attached_at,
          ae.entity_id     attached_entity_id
     from ref_application_entity ae
     join ref_application a
       on a.application_id = ae.application_id
     join v_entity_ancestry d
       on d.entity_type = 'DATABASE'
      and ( ( ae.entity_type = 'DATABASE' and d.database_id = ae.entity_id )
         or ( ae.entity_type = 'INSTANCE' and d.instance_id = ae.entity_id )
         or ( ae.entity_type = 'HOST' and d.host_id = ae.entity_id ) )
    where ae.active = 1
      and a.active = 1;
comment on table v_application_database is 'Databases covered by each application, resolving host and instance attachments down to the database level.';
