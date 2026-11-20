create or replace trigger ref_app_doc_journal
   after insert or update or delete on ref_application_document
   for each row
begin
   if inserting then
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, new_value )
      values (
         :new.application_id, 'DOCUMENT_ADDED', substr(:new.title, 1, 200),
         nvl(:new.file_name, :new.external_url),
         nvl(:new.checksum_sha256, 'link only') );

   elsif deleting then
      -- The document goes, the trace of it having existed does not: the journal
      -- keeps its title and fingerprint, so a reader still sees what was
      -- withdrawn and can tell a deleted file from a deleted link.
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, old_value )
      values (
         :old.application_id, 'DOCUMENT_REMOVED', substr(:old.title, 1, 200),
         nvl(pkg_dbinv_application.current_reason, 'removed')
            || ' - ' || nvl(:old.file_name, :old.external_url),
         nvl(:old.checksum_sha256, 'link only') );

   elsif nvl(:old.checksum_sha256, 'link only') <> nvl(:new.checksum_sha256, 'link only') then
      -- A new file over an existing document. Without this branch the old
      -- fingerprint vanished with the old content and the new one was never
      -- written, so the journal could not say which file had been filed when.
      -- Covers a file added to a link-only document as well. Needs
      -- DOCUMENT_REPLACED in ref_app_evt_type_ck (V__010, or V__013 on a schema
      -- installed before it).
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, old_value, new_value )
      values (
         :new.application_id, 'DOCUMENT_REPLACED', substr(:new.title, 1, 200),
         substr(nvl(pkg_dbinv_application.current_reason, 'replaced')
                || ' - ' || nvl(:old.file_name, :old.external_url)
                || ' -> ' || nvl(:new.file_name, :new.external_url), 1, 1000),
         nvl(:old.checksum_sha256, 'link only'),
         nvl(:new.checksum_sha256, 'link only') );

   elsif nvl(:new.last_review_date, date '0001-01-01')
         <> nvl(:old.last_review_date, date '0001-01-01') then
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, new_value )
      values (
         :new.application_id, 'DOCUMENT_REVIEWED', substr(:new.title, 1, 200),
         pkg_dbinv_application.current_reason,
         to_char(:new.review_due_date, 'YYYY-MM-DD') );
   end if;
end;
/
