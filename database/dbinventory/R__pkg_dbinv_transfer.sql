-- ============================================================================
-- R__pkg_dbinv_transfer.sql
-- ----------------------------------------------------------------------------
-- pkg_dbinv_transfer: export and import of what is ENTERED by hand in a
-- dbInventory schema -- as opposed to what the collection reloads every night --
-- so it can travel from one database to another (test -> prod, or across a
-- reinstallation, see project note "ref data preservation").
--
-- Driven from the collection server by bin/export_ref_data.sh and
-- bin/import_ref_data.sh. The package does the work; the scripts only carry the
-- file in and out of SQLcl.
--
-- WHAT TRAVELS
--   Domain "applications": the application registry -- ref_application with its
--   groups, contacts, attachments to the inventory, documents (file included)
--   and source repositories. ACTIVE rows only: a deactivated row is history of
--   the source database, not something to impose on the target.
--   Not exported: the journal (ref_application_event). The target writes its own,
--   through the journal triggers of pkg_dbinv_application, with the import as the reason.
--   The file format has a "domains" object so derogations and their documents
--   can join later without a version break.
--
-- NO TECHNICAL ID EVER LEAVES THE DATABASE
--   application_id, group_id... and above all entity_id are identities: they
--   differ between test and prod, and change on every reinstallation. The file
--   carries natural keys only, resolved again in the target:
--     application  app_code
--     group        group_type_code + group_name
--     contact      contact_role + full_name
--     attachment   HOST     platform + hostname
--                  INSTANCE platform + hostname + instance_name
--                  DATABASE platform + hostname + instance_name + db_name
--     document     title (within its application)
--     source       repo_url
--
-- IMPORT SEMANTICS (decided with the user, 2026-11-11)
--   * Add and update, never remove. What the file holds is created or brought
--     in line; what the target holds and the file does not is left alone.
--   * An attachment whose host, instance or database does not exist in the
--     target is skipped and listed, never an error: the estate of the two
--     databases can differ by a collection.
--   * Idempotent: a row that already matches is not touched, so importing the
--     same file twice writes nothing the second time. That matters because the
--     journal trigger of ref_application records every UPDATE, even a no-op one.
--   * Dry run by default: everything is executed, reported, then rolled back.
--     The report is therefore the exact outcome of a real import, not a guess.
--   * All or nothing: if one application fails, nothing is written.
--
-- WHY DIRECT DML AND NOT pkg_dbinv_application
--   The API recomputes review dates from "today" and has no way to set
--   last_review_date / last_review_by: going through it would lose exactly the
--   review history the registry exists to keep. Direct DML is safe here because
--   the guarantees of the registry live in triggers (journal, document checksum),
--   not in the API -- see the header of pkg_dbinv_application. The reason carried into the
--   journal is set through pkg_dbinv_application.set_reason.
--
-- TRANSPORT
--   The JSON is UTF-8, carried base64-encoded through SQLcl in both directions
--   (dbms_output on export, chunk calls on import). Nothing in the payload can
--   then break a SQL literal, and accents survive whatever NLS_LANG the client
--   runs with.
-- ============================================================================


create or replace package pkg_dbinv_transfer as

   c_format  constant varchar2(30) := 'dbinventory-transfer';
   c_version constant pls_integer  := 1;

   -- ---------------------------------------------------------------------
   -- Export
   -- ---------------------------------------------------------------------
   -- p_app_codes: comma-separated app_code list; null exports every active
   -- application. A code that does not exist is an error, not a silent skip.
   function export_json ( p_app_codes varchar2 default null ) return clob;

   -- What export_ref_data.sh calls: the document as base64 lines prefixed
   -- 'B64:', and a summary prefixed 'MSG:', on dbms_output.
   procedure print_export ( p_app_codes varchar2 default null );

   -- ---------------------------------------------------------------------
   -- Import
   -- ---------------------------------------------------------------------
   -- What import_ref_data.sh calls: import_begin, then import_chunk for each
   -- base64 line of the file, then import_run.
   procedure import_begin;
   procedure import_chunk ( p_base64 varchar2 );
   procedure import_run ( p_apply number default 0, p_file_name varchar2 default null );

   -- The same import from a document already in hand (tests, ad hoc use).
   -- p_apply = 0: dry run, rolled back. p_apply = 1: committed.
   -- Raises if the document is invalid or any application fails.
   procedure import_json ( p_doc clob, p_apply number default 0, p_file_name varchar2 default null );

   -- Counters of the last export or import, e.g. counter('GROUP', 'CREATED').
   -- Items: APPLICATION, GROUP, CONTACT, ENTITY, DOCUMENT, SOURCE.
   -- Outcomes: EXPORTED, CREATED, UPDATED, UNCHANGED, SKIPPED.
   function counter ( p_item varchar2, p_outcome varchar2 ) return number;

end pkg_dbinv_transfer;
/
