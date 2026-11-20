create or replace trigger ref_app_grp_journal
   after insert or update or delete on ref_application_group
   for each row
begin
   if inserting then
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, new_value )
      values (
         :new.application_id, 'GROUP_ADDED', :new.group_name, :new.group_type_code,
         nvl(:new.contact_email, nvl(:new.ldap_group_name, :new.external_ref)) );

   elsif deleting or ( :old.active = 1 and :new.active = 0 ) then
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, old_value )
      values (
         :old.application_id, 'GROUP_REMOVED', :old.group_name,
         pkg_dbinv_application.current_reason, :old.contact_email );

   elsif :old.active = 0 and :new.active = 1 then
      -- A removed group added back (add_group reactivates the row): to the
      -- reader of the journal this is an addition, not an edit.
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, new_value )
      values (
         :new.application_id, 'GROUP_ADDED', :new.group_name, :new.group_type_code,
         nvl(:new.contact_email, nvl(:new.ldap_group_name, :new.external_ref)) );

   else
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, old_value, new_value )
      values (
         :new.application_id, 'GROUP_UPDATED', :new.group_name,
         pkg_dbinv_application.current_reason, :old.contact_email, :new.contact_email );
   end if;
end;
/
