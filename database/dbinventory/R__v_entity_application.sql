-- ============================================================
-- v_entity_application
-- ------------------------------------------------------------
-- The registry read from the other end: given a host, an instance or a database,
-- which applications claim it. Without this, the relation only exists in one
-- direction and the question actually asked -- "whose is this database" -- is the
-- one that has no screen.
--
-- One view rather than a query per page. Six inventory pages consume it (the
-- instance and database pages of the three engines), and a view is the only way
-- for the six to be unable to disagree.
--
-- attached_at survives at DATABASE level and is dropped above it. On a database
-- it is a real distinction -- reached explicitly, or swept in with its whole
-- instance -- and detaching the two is a different action. On an instance or a
-- host it would only restate the level you are already looking at.
-- ============================================================
create or replace view v_entity_application as
   -- The three literals are cast on purpose. Without it, a UNION of character
   -- literals of different lengths resolves to CHAR of the longest, so 'HOST'
   -- would arrive padded to eight characters and a region filtering on
   -- entity_type = 'HOST' would be relying on blank-padded comparison rules to
   -- come out right. A view read by six screens does not get to depend on that.
   select cast('DATABASE' as varchar2(20 char)) entity_type,
          ad.database_id   entity_id,
          ad.application_id,
          a.app_code,
          a.app_name,
          a.criticality,
          a.lifecycle_status,
          a.data_sensitivity,
          ad.attached_at
     from v_application_database ad
     join ref_application a
       on a.application_id = ad.application_id
   union all
   select distinct cast('INSTANCE' as varchar2(20 char)),
          ad.instance_id,
          ad.application_id,
          a.app_code,
          a.app_name,
          a.criticality,
          a.lifecycle_status,
          a.data_sensitivity,
          cast(null as varchar2(20 char))
     from v_application_database ad
     join ref_application a
       on a.application_id = ad.application_id
   union all
   select distinct cast('HOST' as varchar2(20 char)),
          ad.host_id,
          ad.application_id,
          a.app_code,
          a.app_name,
          a.criticality,
          a.lifecycle_status,
          a.data_sensitivity,
          cast(null as varchar2(20 char))
     from v_application_database ad
     join ref_application a
       on a.application_id = ad.application_id;

comment on table v_entity_application is 'Applications claiming a given inventory entity, at host, instance or database level; the registry read from the inventory rather than from the application.';
