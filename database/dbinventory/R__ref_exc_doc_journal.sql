create or replace trigger ref_exc_doc_journal
   after insert or delete on ref_exception_document
   for each row
begin
   if inserting then
      insert into ref_exception_event ( exception_id, event_type, note, new_value )
         values ( :new.exception_id, 'DOCUMENT_ADDED', :new.file_name, :new.checksum_sha256 );
   else
      -- The file goes, the trace of it having existed does not: the journal keeps
      -- its name and fingerprint, so an auditor still sees what was withdrawn.
      insert into ref_exception_event ( exception_id, event_type, note, old_value )
         values ( :old.exception_id, 'DOCUMENT_REMOVED',
                  nvl(pkg_dbinv_exception.removal_reason, 'removed') || ' - ' || :old.file_name,
                  :old.checksum_sha256 );
   end if;
end;
/
