-- ============================================================================
-- Enforcement on ref_exception_document
-- ----------------------------------------------------------------------------
-- The fingerprint and the journal live here rather than in add_document because
-- the derogation screen cannot call the API to upload: APEXlang only sanctions a
-- BLOB upload as a `fileUpload` render role inside a `form` region bound to the
-- table (component-policies REGION_RULE_014/015), which means APEX writes the row
-- with its own DML. Putting the guarantees in the trigger makes them hold for
-- every writer -- the screen, this package, a script -- instead of only for
-- callers who remembered to go through the API.
-- ============================================================================

create or replace trigger ref_exc_doc_before_write
   before insert on ref_exception_document
   for each row
begin
   :new.file_size := dbms_lob.getlength(:new.content);

   if :new.file_size is null or :new.file_size = 0 then
      raise_application_error(-20025, 'Empty attachment refused.');
   end if;

   -- Never trust a checksum supplied by the caller: recompute it. An attachment
   -- whose fingerprint could be chosen by whoever uploads it proves nothing.
   :new.checksum_sha256 := pkg_dbinv_exception.fingerprint(:new.content);
end;
/
