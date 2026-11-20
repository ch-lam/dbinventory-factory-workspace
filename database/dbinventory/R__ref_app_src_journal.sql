create or replace trigger ref_app_src_journal
   after insert or update or delete on ref_application_source
   for each row
begin
   if inserting then
      insert into ref_application_event (
         application_id, event_type, subject_ref, note )
      values (
         :new.application_id, 'SOURCE_ADDED', substr(:new.repo_url, 1, 200), :new.note );

   elsif deleting or ( :old.active = 1 and :new.active = 0 ) then
      insert into ref_application_event (
         application_id, event_type, subject_ref, note )
      values (
         :old.application_id, 'SOURCE_REMOVED', substr(:old.repo_url, 1, 200),
         pkg_dbinv_application.current_reason );
   end if;
end;
/
