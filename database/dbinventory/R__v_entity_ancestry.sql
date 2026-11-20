-- ============================================================
-- v_entity_ancestry
-- ------------------------------------------------------------
-- Resolves any polymorphic (entity_type, entity_id) pair to the whole chain it
-- belongs to: host > instance > database > storage unit, the entity itself
-- included. Defined once because two very different consumers need exactly the
-- same walk:
--   * pkg_dbinv_scoring.apply_exceptions, to cascade an exception granted at a
--     high level down to the findings below it;
--   * pkg_dbinv_scoring.load_compliance, to roll findings up to the grain their
--     control is scored at (ref_control.entity_type).
-- ============================================================
create or replace view v_entity_ancestry as
   select 'HOST' entity_type, h.host_id entity_id,
          h.host_id,
          cast(null as number) instance_id,
          cast(null as number) database_id,
          cast(null as number) storage_unit_id
     from dim_host h
   union all
   select 'INSTANCE', i.instance_id, i.host_id, i.instance_id, null, null
     from dim_instance i
   union all
   select 'DATABASE', d.database_id, i.host_id, d.instance_id, d.database_id, null
     from dim_database d
     join dim_instance i on i.instance_id = d.instance_id
   union all
   select 'STORAGE', s.storage_unit_id, i.host_id, d.instance_id, s.database_id, s.storage_unit_id
     from dim_storage_unit s
     join dim_database d on d.database_id = s.database_id
     join dim_instance i on i.instance_id = d.instance_id;
comment on table v_entity_ancestry is 'Host/instance/database/storage chain of any polymorphic entity reference; used to cascade exceptions downwards and to roll findings up to their control grain.';
