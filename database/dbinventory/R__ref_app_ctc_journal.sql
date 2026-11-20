-- The contacts journal. Same shape as the groups', and it has to be: a reader
-- comparing "who was responsible" against "who was the contact" reads two
-- streams of the same table, and they must speak alike.
--
-- The value carried is the way of reaching the person -- address, then phone,
-- then directory login. That is the field which rots, and the one whose previous
-- value somebody will want back.
create or replace trigger ref_app_ctc_journal
   after insert or update or delete on ref_application_contact
   for each row
begin
   if inserting then
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, new_value )
      values (
         :new.application_id, 'CONTACT_ADDED', :new.full_name, :new.contact_role,
         nvl(:new.email, nvl(:new.phone, :new.ldap_login)) );

   elsif deleting or ( :old.active = 1 and :new.active = 0 ) then
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, old_value )
      values (
         :old.application_id, 'CONTACT_REMOVED', :old.full_name,
         pkg_dbinv_application.current_reason,
         nvl(:old.email, nvl(:old.phone, :old.ldap_login)) );

   elsif :old.active = 0 and :new.active = 1 then
      -- A removed contact added back (add_contact reactivates the row).
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, new_value )
      values (
         :new.application_id, 'CONTACT_ADDED', :new.full_name, :new.contact_role,
         nvl(:new.email, nvl(:new.phone, :new.ldap_login)) );

   else
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, old_value, new_value )
      values (
         :new.application_id, 'CONTACT_UPDATED', :new.full_name,
         pkg_dbinv_application.current_reason,
         nvl(:old.email, nvl(:old.phone, :old.ldap_login)),
         nvl(:new.email, nvl(:new.phone, :new.ldap_login)) );
   end if;
end;
/
