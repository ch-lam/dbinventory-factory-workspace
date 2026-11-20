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
