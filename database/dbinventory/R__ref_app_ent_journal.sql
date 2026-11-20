create or replace trigger ref_app_ent_journal
   after insert or update or delete on ref_application_entity
   for each row
begin
   if inserting then
      insert into ref_application_event (
         application_id, event_type, subject_ref, note )
      values (
         :new.application_id, 'ENTITY_LINKED',
         :new.entity_type || ' ' || :new.entity_id, :new.note );

   elsif deleting or ( :old.active = 1 and :new.active = 0 ) then
      insert into ref_application_event (
         application_id, event_type, subject_ref, note )
      values (
         :old.application_id, 'ENTITY_UNLINKED',
         :old.entity_type || ' ' || :old.entity_id, pkg_dbinv_application.current_reason );

   elsif :old.active = 0 and :new.active = 1 then
      -- Attached again after a detach (link_entity reactivates the row).
      insert into ref_application_event (
         application_id, event_type, subject_ref, note )
      values (
         :new.application_id, 'ENTITY_LINKED',
         :new.entity_type || ' ' || :new.entity_id, :new.note );
   end if;
end;
/
