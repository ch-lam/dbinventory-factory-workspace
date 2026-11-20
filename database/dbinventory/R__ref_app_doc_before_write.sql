-- ============================================================================
-- Enforcement on ref_application_document
-- ----------------------------------------------------------------------------
-- One difference from the derogation case, and it is the whole reason this
-- register exists: content is OPTIONAL here. A document may be a link only, and
-- such a row must be storable on an instance with no DBMS_CRYPTO grant at all.
-- ============================================================================

create or replace trigger ref_app_doc_before_write
   before insert or update on ref_application_document
   for each row
begin
   if :new.content is null then
      :new.file_size       := null;
      :new.checksum_sha256 := null;
   else
      :new.file_size := dbms_lob.getlength(:new.content);

      if :new.file_size = 0 then
         raise_application_error(-20041,
            'Empty file refused. Store nothing and keep the link, or store a real file.');
      end if;

      -- Never trust a checksum supplied by the caller: recompute it. A
      -- fingerprint chosen by whoever uploads the file proves nothing.
      :new.checksum_sha256 := pkg_dbinv_application.fingerprint(:new.content);
   end if;
end;
/
