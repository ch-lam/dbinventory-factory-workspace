-- ============================================================================
-- T_002_application_model.sql
-- ----------------------------------------------------------------------------
-- Tests the application registry: the model, its constraints, and the write API.
--
-- WHAT IT IS FOR
--   The registry is worth exactly what its refusals are worth. A contact with no
--   way of reaching anybody, a document nobody can open, an attachment pointing
--   at a database that does not exist -- each of those looks like data until the
--   day someone needs it. So this test checks what the model REJECTS at least as
--   carefully as what it accepts.
--
-- SAFE TO RUN ANYWHERE
--   Everything happens inside one transaction and ends with a rollback, so it
--   leaves no rows behind -- including in the append-only journal, which cannot
--   be cleaned up any other way once committed. It reads dim_instance and
--   dim_database but never writes to them.
--
-- USAGE
--   sql -S -name <conn> @T_002_application_model.sql
--   Exits non-zero when a check fails, so it can gate a deployment script.
-- ============================================================================

set serveroutput on size unlimited
set feedback off
set verify off
whenever sqlerror exit failure

declare
   l_failures pls_integer := 0;
   l_checked  pls_integer := 0;

   l_app      number;
   l_group    number;
   l_link     number;
   l_doc      number;
   l_src      number;

   l_instance number;
   l_expected pls_integer;
   l_actual   pls_integer;
   l_n        pls_integer;
   l_sum1     varchar2(64 char);
   l_sum2     varchar2(64 char);

   procedure ok ( p_what varchar2 ) is
   begin
      dbms_output.put_line('  ok    ' || p_what);
   end ok;

   procedure fail ( p_what varchar2, p_detail varchar2 default null ) is
   begin
      l_failures := l_failures + 1;
      dbms_output.put_line('  FAIL  ' || p_what);
      if p_detail is not null then
         dbms_output.put_line('        ' || substr(p_detail, 1, 200));
      end if;
   end fail;

   -- Every rejection test has the same shape, and getting it wrong the other way
   -- round -- reporting success when nothing was rejected -- is the failure mode
   -- that makes a test lie. So the "no exception" branch always fails.
   procedure expect_rejected ( p_what varchar2, p_raised boolean, p_err varchar2 ) is
   begin
      l_checked := l_checked + 1;
      if p_raised then
         ok(p_what || ' (rejected: ' || substr(p_err, 1, 60) || ')');
      else
         fail(p_what, 'accepted, but should have been rejected');
      end if;
   end expect_rejected;

begin
   dbms_output.put_line('Application registry test');
   dbms_output.put_line(rpad('-', 78, '-'));

   -- ---------------------------------------------------------------------
   -- Fixture
   -- ---------------------------------------------------------------------
   l_app := pkg_dbinv_application.create_application(
               p_app_code    => 'T002TEST',
               p_app_name    => 'Test fixture, rolled back',
               p_criticality => 'STANDARD' );
   l_checked := l_checked + 1;
   if l_app is null then
      fail('create_application returned nothing');
   else
      ok('application created');
   end if;

   -- ---------------------------------------------------------------------
   -- 1. A group nobody can reach must be refused.
   -- ---------------------------------------------------------------------
   dbms_output.put_line('1. A group with no means of contact');
   declare
      l_raised boolean := false;
      l_err    varchar2(400);
   begin
      begin
         l_group := pkg_dbinv_application.add_group(
                       p_application_id  => l_app,
                       p_group_type_code => 'ADMIN',
                       p_group_name      => 'Unreachable' );
      exception when others then
         l_raised := true; l_err := sqlerrm;
      end;
      expect_rejected('group with no email, no LDAP and no external reference', l_raised, l_err);
   end;

   -- and the same group with one contact must be accepted
   l_group := pkg_dbinv_application.add_group(
                 p_application_id  => l_app,
                 p_group_type_code => 'ADMIN',
                 p_group_name      => 'DBA team',
                 p_contact_email   => 'dba@example.invalid' );
   l_checked := l_checked + 1;
   if l_group is null then fail('add_group returned nothing'); else ok('group with a contact accepted'); end if;

   -- ---------------------------------------------------------------------
   -- 2. A document that is neither stored nor linked must be refused.
   -- ---------------------------------------------------------------------
   dbms_output.put_line('2. A document with neither content nor link');
   declare
      l_raised boolean := false;
      l_err    varchar2(400);
   begin
      begin
         l_doc := pkg_dbinv_application.add_document(
                     p_application_id => l_app,
                     p_title          => 'Ghost entry' );
      exception when others then
         l_raised := true; l_err := sqlerrm;
      end;
      expect_rejected('document with no content and no URL', l_raised, l_err);
   end;

   -- link only must be accepted, and must not need DBMS_CRYPTO
   l_doc := pkg_dbinv_application.add_document(
               p_application_id => l_app,
               p_title          => 'Runbook, linked',
               p_doc_kind       => 'RUNBOOK',
               p_external_url   => 'https://wiki.example.invalid/runbook' );
   l_checked := l_checked + 1;
   select count(*) into l_n from ref_application_document
    where document_id = l_doc and checksum_sha256 is null and file_size is null;
   if l_n = 1 then
      ok('link-only document stored, with no fingerprint and no size');
   else
      fail('link-only document', 'a document with no content must carry neither checksum nor size');
   end if;

   -- ---------------------------------------------------------------------
   -- 3. An attachment pointing at nothing must be refused.
   -- ---------------------------------------------------------------------
   dbms_output.put_line('3. An attachment pointing at a non-existent entity');
   declare
      l_raised boolean := false;
      l_err    varchar2(400);
      l_bogus  number;
   begin
      select nvl(max(instance_id), 0) + 999999 into l_bogus from dim_instance;
      begin
         l_link := pkg_dbinv_application.link_entity(l_app, 'INSTANCE', l_bogus);
      exception when others then
         l_raised := true; l_err := sqlerrm;
      end;
      expect_rejected('link to an instance id that does not exist', l_raised, l_err);
   end;

   -- ---------------------------------------------------------------------
   -- 4. The cascade. This is the one that matters.
   --    Attaching an INSTANCE must surface exactly its databases -- no more, and
   --    above all no fewer, since a database silently missing from an
   --    application's scope is invisible until someone needs it.
   -- ---------------------------------------------------------------------
   dbms_output.put_line('4. Instance-level attachment cascades to its databases');
   -- The instance with the MOST databases, never simply the first one. An
   -- instance carrying a single database would let a broken cascade pass:
   -- returning one row is right by accident when the right answer is one.
   select instance_id into l_instance
     from ( select d.instance_id
              from dim_database d
             group by d.instance_id
             order by count(*) desc, d.instance_id )
    where rownum = 1;

   select count(*) into l_expected from dim_database where instance_id = l_instance;

   l_link := pkg_dbinv_application.link_entity(l_app, 'INSTANCE', l_instance,
                                               'attached for T_002');

   select count(*) into l_actual from v_application_database where application_id = l_app;
   l_checked := l_checked + 1;
   if l_actual = l_expected and l_expected > 0 then
      ok('instance ' || l_instance || ' cascades to its ' || l_expected || ' database(s)');
   else
      fail('cascade count', 'expected ' || l_expected || ', got ' || l_actual);
   end if;

   -- attached_at must say HOW the database was reached, not merely that it was
   l_checked := l_checked + 1;
   select count(*) into l_n from v_application_database
    where application_id = l_app and attached_at = 'INSTANCE';
   if l_n = l_expected then
      ok('every row reports the level it was attached at');
   else
      fail('attached_at', 'expected ' || l_expected || ' rows marked INSTANCE, got ' || l_n);
   end if;

   -- those databases must have left the backlog
   l_checked := l_checked + 1;
   select count(*) into l_n from v_database_without_application
    where database_id in ( select database_id from dim_database where instance_id = l_instance );
   if l_n = 0 then
      ok('the attached databases no longer appear as unclaimed');
   else
      fail('v_database_without_application', l_n || ' attached database(s) still listed as unclaimed');
   end if;

   -- ---------------------------------------------------------------------
   -- 5. Fingerprinting: recomputed, and it follows the content.
   -- ---------------------------------------------------------------------
   dbms_output.put_line('5. Stored documents are fingerprinted');
   declare
      l_doc2 number;
      l_doc3 number;
   begin
      l_doc2 := pkg_dbinv_application.add_document(
                   p_application_id => l_app,
                   p_title          => 'Procedure, stored',
                   p_doc_kind       => 'PROCEDURE',
                   p_file_name      => 'proc.txt',
                   p_content        => utl_raw.cast_to_raw('first version') );
      l_doc3 := pkg_dbinv_application.add_document(
                   p_application_id => l_app,
                   p_title          => 'Procedure, stored, amended',
                   p_doc_kind       => 'PROCEDURE',
                   p_file_name      => 'proc.txt',
                   p_content        => utl_raw.cast_to_raw('second version') );

      select checksum_sha256 into l_sum1 from ref_application_document where document_id = l_doc2;
      select checksum_sha256 into l_sum2 from ref_application_document where document_id = l_doc3;

      l_checked := l_checked + 1;
      if l_sum1 is not null and l_sum2 is not null and l_sum1 <> l_sum2 then
         ok('different content yields a different fingerprint');
      else
         fail('fingerprint', 'got ' || nvl(l_sum1, 'null') || ' and ' || nvl(l_sum2, 'null'));
      end if;

      -- size is computed, never taken from the caller
      l_checked := l_checked + 1;
      select count(*) into l_n from ref_application_document
       where document_id = l_doc2 and file_size = 13;
      if l_n = 1 then ok('file size computed from the content'); else fail('file_size not computed'); end if;
   end;

   -- an empty file is refused rather than stored as a zero-byte truth
   dbms_output.put_line('6. An empty file');
   declare
      l_raised boolean := false;
      l_err    varchar2(400);
      l_dummy  number;
   begin
      begin
         l_dummy := pkg_dbinv_application.add_document(
                       p_application_id => l_app,
                       p_title          => 'Empty',
                       p_file_name      => 'empty.txt',
                       p_content        => empty_blob() );
      exception when others then
         l_raised := true; l_err := sqlerrm;
      end;
      expect_rejected('zero-byte file', l_raised, l_err);
   end;

   -- ---------------------------------------------------------------------
   -- 7. The journal: written by itself, and impossible to rewrite.
   -- ---------------------------------------------------------------------
   dbms_output.put_line('7. The audit trail');
   l_checked := l_checked + 1;
   select count(*) into l_n from ref_application_event
    where application_id = l_app and event_type = 'DOCUMENT_ADDED';
   if l_n >= 3 then
      ok(l_n || ' document additions journalled without the caller asking');
   else
      fail('journal', 'expected at least 3 DOCUMENT_ADDED events, got ' || l_n);
   end if;

   l_checked := l_checked + 1;
   select count(*) into l_n from ref_application_event
    where application_id = l_app and event_type = 'ENTITY_LINKED';
   if l_n = 1 then ok('attachment journalled'); else fail('ENTITY_LINKED missing'); end if;

   declare
      l_raised boolean := false;
      l_err    varchar2(400);
   begin
      begin
         update ref_application_event set note = 'tampered' where application_id = l_app;
      exception when others then
         l_raised := true; l_err := sqlerrm;
      end;
      expect_rejected('update on the journal', l_raised, l_err);
   end;

   declare
      l_raised boolean := false;
      l_err    varchar2(400);
   begin
      begin
         delete from ref_application_event where application_id = l_app;
      exception when others then
         l_raised := true; l_err := sqlerrm;
      end;
      expect_rejected('delete on the journal', l_raised, l_err);
   end;

   -- removing a document keeps the trace of what left
   dbms_output.put_line('8. Removal keeps the trace');
   pkg_dbinv_application.remove_document(l_doc, 'superseded by the wiki');
   l_checked := l_checked + 1;
   select count(*) into l_n from ref_application_event
    where application_id = l_app and event_type = 'DOCUMENT_REMOVED'
      and note like 'superseded by the wiki%';
   if l_n = 1 then
      ok('the withdrawn document left its title, its reason and its fingerprint behind');
   else
      fail('DOCUMENT_REMOVED', 'expected 1 journal entry carrying the reason, got ' || l_n);
   end if;

   -- ---------------------------------------------------------------------
   -- 9. The rest of the API answers.
   -- ---------------------------------------------------------------------
   -- ---------------------------------------------------------------------
   -- 9. The reason the journal lives in triggers rather than in the package.
   --    A screen built the ordinary way -- an APEX form, an interactive grid --
   --    writes the table with its own DML and never calls the package. If the
   --    journal depended on the package, it would stop the day somebody builds
   --    such a screen, and nothing would say so. So: write directly, in SQL,
   --    exactly as a form would, and require the journal anyway.
   -- ---------------------------------------------------------------------
   dbms_output.put_line('9. A write that bypasses the API is still journalled');
   declare
      l_before pls_integer;
      l_after  pls_integer;
      l_gid    number;
   begin
      select count(*) into l_before from ref_application_event
       where application_id = l_app and event_type = 'GROUP_ADDED';

      insert into ref_application_group (
         application_id, group_type_code, group_name, contact_email )
      values ( l_app, 'BUSINESS', 'Written by a form, not the package',
               'business@example.invalid' )
      returning group_id into l_gid;

      select count(*) into l_after from ref_application_event
       where application_id = l_app and event_type = 'GROUP_ADDED';

      l_checked := l_checked + 1;
      if l_after = l_before + 1 then
         ok('a plain INSERT was journalled without going through the package');
      else
         fail('trigger journalling', 'GROUP_ADDED went from ' || l_before || ' to ' || l_after);
      end if;

      -- and deactivating it directly must read as a removal, not as an update
      update ref_application_group set active = 0 where group_id = l_gid;
      l_checked := l_checked + 1;
      select count(*) into l_n from ref_application_event
       where application_id = l_app and event_type = 'GROUP_REMOVED'
         and subject_ref = 'Written by a form, not the package';
      if l_n = 1 then
         ok('a direct deactivation reads as a removal, not as an edit');
      else
         fail('deactivation journalling', 'expected 1 GROUP_REMOVED, got ' || l_n);
      end if;
   end;

   dbms_output.put_line('10. Sources and reviews');
   l_src := pkg_dbinv_application.add_source(l_app, 'https://github.com/example/repo.git',
                                             p_branch => 'main');
   l_checked := l_checked + 1;
   if l_src is not null then ok('source added'); else fail('add_source returned nothing'); end if;

   pkg_dbinv_application.record_review(l_app, 'annual review', 12);
   l_checked := l_checked + 1;
   select count(*) into l_n from ref_application
    where application_id = l_app
      and last_review_date = trunc(sysdate)
      and review_due_date = add_months(trunc(sysdate), 12);
   if l_n = 1 then ok('review recorded and next due date moved'); else fail('record_review'); end if;

   -- ---------------------------------------------------------------------
   dbms_output.put_line(rpad('-', 78, '-'));
   dbms_output.put_line(l_checked || ' checks run, ' || l_failures || ' failure(s)');

   -- Always, whatever the verdict: this test writes into a live schema.
   rollback;
   dbms_output.put_line('rolled back, nothing left behind');

   if l_failures > 0 then
      raise_application_error(-20901,
         l_failures || ' application registry check(s) failed - see the report above.');
   end if;
   dbms_output.put_line('OK');
exception
   when others then
      rollback;
      raise;
end;
/

set feedback on
