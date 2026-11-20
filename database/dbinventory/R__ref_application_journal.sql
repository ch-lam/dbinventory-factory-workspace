-- ============================================================================
-- The journal, in triggers
-- ----------------------------------------------------------------------------
-- One AFTER trigger per table. They are the only place the journal is written,
-- so there is exactly one answer to "is this change recorded" and it does not
-- depend on which piece of software made it.
--
-- Deactivation is journalled as a removal rather than as an update, because that
-- is what it means here: nothing is deleted, active = 0 is how something leaves
-- the registry, and a reader looking for "when did this group stop being
-- responsible" must not have to know that.
-- ============================================================================

create or replace trigger ref_application_journal
   after insert or update on ref_application
   for each row
begin
   if inserting then
      insert into ref_application_event ( application_id, event_type, subject_ref, new_value )
         values ( :new.application_id, 'CREATED', :new.app_code, :new.app_name );

   elsif :old.active = 1 and :new.active = 0 then
      insert into ref_application_event ( application_id, event_type, note )
         values ( :new.application_id, 'DEACTIVATED', pkg_dbinv_application.current_reason );

   elsif nvl(:new.last_review_date, date '0001-01-01')
         <> nvl(:old.last_review_date, date '0001-01-01') then
      insert into ref_application_event ( application_id, event_type, note, new_value )
         values ( :new.application_id, 'REVIEWED', pkg_dbinv_application.current_reason,
                  to_char(:new.review_due_date, 'YYYY-MM-DD') );

   elsif :old.lifecycle_status <> :new.lifecycle_status then
      -- Journalled on its own: this is the field whose history somebody actually
      -- goes looking for later.
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, old_value, new_value )
      values (
         :new.application_id, 'UPDATED', 'lifecycle_status',
         pkg_dbinv_application.current_reason, :old.lifecycle_status, :new.lifecycle_status );

   else
      insert into ref_application_event ( application_id, event_type, subject_ref, note )
         values ( :new.application_id, 'UPDATED', 'attributes',
                  pkg_dbinv_application.current_reason );
   end if;
end;
/
