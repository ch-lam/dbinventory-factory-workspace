-- ============================================================================
-- V__013_journal_document_replacement.sql
-- ----------------------------------------------------------------------------
-- Allow the journal to record that the file of a document was replaced.
--
-- WHY
--   The journal kept the fingerprint (SHA-256) of a document when it was added
--   and when it was removed, but not when its file was replaced. Uploading a new
--   file on an existing document is an UPDATE of the content, and the journal
--   trigger only looked at the review date on update: the fingerprint of the old
--   file vanished without a trace, and the new one was never written anywhere.
--   For a register whose point is to prove which file was filed, that is the
--   one move that must not go unrecorded.
--
--   V__011 now journals it as DOCUMENT_REPLACED, old fingerprint in old_value and
--   new one in new_value. This script lets the check constraint on event_type
--   accept that value.
--
-- WHY A SEPARATE SCRIPT
--   V__010 now creates the constraint with DOCUMENT_REPLACED, so a fresh install
--   needs nothing from this file. It exists for schemas already installed, which
--   X_000 does not rebuild and whose journal must not be lost. Written to be a
--   no-op when the constraint already accepts the value, so running it twice, or
--   on a fresh install, changes nothing.
--
--   No row is rewritten. A replacement made before this script left no event,
--   and there is nothing truthful to write in its place now.
--
-- ORDER
--   Run it before replaying V__011: the new trigger branch writes an event_type
--   the old constraint refuses, so the first replaced file would fail.
-- ============================================================================


set serveroutput on size unlimited

declare
   l_condition varchar2(4000);
begin
   -- search_condition is a LONG: read through a PL/SQL variable, which converts it.
   begin
      select search_condition into l_condition
        from user_constraints
       where table_name = 'REF_APPLICATION_EVENT'
         and constraint_name = 'REF_APP_EVT_TYPE_CK';
   exception
      when no_data_found then
         -- The table is not there yet; a fresh install runs V__010 first, which
         -- already creates the constraint with the new value.
         dbms_output.put_line('V__013: ref_app_evt_type_ck not found, nothing to do');
         return;
   end;

   if instr(l_condition, '''DOCUMENT_REPLACED''') > 0 then
      dbms_output.put_line('V__013: ref_app_evt_type_ck already accepts DOCUMENT_REPLACED, nothing to do');
      return;
   end if;

   execute immediate 'alter table ref_application_event drop constraint ref_app_evt_type_ck';
   -- Same list as V__010, which stays the reference for it.
   execute immediate q'[
      alter table ref_application_event add constraint ref_app_evt_type_ck check ( event_type in (
         'CREATED', 'UPDATED', 'DEACTIVATED', 'REVIEWED',
         'GROUP_ADDED', 'GROUP_UPDATED', 'GROUP_REMOVED',
         'CONTACT_ADDED', 'CONTACT_UPDATED', 'CONTACT_REMOVED',
         'ENTITY_LINKED', 'ENTITY_UNLINKED',
         'DOCUMENT_ADDED', 'DOCUMENT_REPLACED', 'DOCUMENT_REMOVED', 'DOCUMENT_REVIEWED',
         'SOURCE_ADDED', 'SOURCE_REMOVED' ) )]';
   dbms_output.put_line('V__013: ref_app_evt_type_ck now accepts DOCUMENT_REPLACED');
end;
/
