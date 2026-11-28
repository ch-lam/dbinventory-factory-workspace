-- ============================================================================
-- X_000_reinstall_all.sql
-- ----------------------------------------------------------------------------
-- Installs the whole schema in an EMPTY schema, in one SQLcl run, without
-- migrate.sh: for a temporary environment (a test, a throwaway PDB, a laptop).
-- DEV and DEMO of the factory are migrated by migrate.sh, never by this script.
--
-- Same order as migrate.sh: the V__ files in name order, then the R__ files in
-- the order of R__order.txt, then the T__ checks. migrate.sh, --dry-run
-- included, checks that this file lists exactly those files in that order: a
-- V__, R__ or T__ added without updating this file fails the pipeline.
--
-- It does not fill SCHEMA_MIGRATIONS: a schema installed this way is not
-- managed by migrate.sh afterwards.
--
-- Run from database/dbinventory/ (the @ are relative), connected as the
-- schema owner:
--   cd database/dbinventory && sql -S -name <conn> @X_000_reinstall_all.sql
-- ============================================================================
set define off

-- ---- V__ : tables and data
@V__001_create_schema.sql
@V__002_create_app_model.sql
@V__003_app_model_reference_data.sql
@V__004_create_discovery.sql
@V__005_initial_data.sql
@V__006_create_application_model.sql

-- ---- R__ : code, in the order of R__order.txt
@R__pkg_dbinv_inventory.sql
@R__pkg_dbinv_scoring.sql
@R__pkg_dbinv_discovery.sql
@R__pkg_dbinv_exception.sql
@R__pkg_dbinv_application.sql
@R__pkg_dbinv_transfer.sql
@R__v_benchmark_mapping_gap.sql
@R__v_entity_ancestry.sql
@R__v_exception_finding_match.sql
@R__v_exception_review.sql
@R__v_nis2_posture.sql
@R__v_entity_collect_date.sql
@R__v_database_census.sql
@R__v_environment_identity.sql
@R__v_oracle_lms_usage.sql
@R__v_discovery_status.sql
@R__v_application_database.sql
@R__v_database_without_application.sql
@R__v_application_document_review.sql
@R__v_application_overview.sql
@R__v_entity_application.sql
@R__pkg_dbinv_inventory_BODY.sql
@R__pkg_dbinv_scoring_BODY.sql
@R__pkg_dbinv_discovery_BODY.sql
@R__pkg_dbinv_exception_BODY.sql
@R__pkg_dbinv_application_BODY.sql
@R__pkg_dbinv_transfer_BODY.sql
@R__ref_exception_event_append_only.sql
@R__ref_exc_doc_before_write.sql
@R__ref_exc_doc_journal.sql
@R__ref_application_event_append_only.sql
@R__ref_application_journal.sql
@R__ref_app_grp_journal.sql
@R__ref_app_ctc_journal.sql
@R__ref_app_ent_journal.sql
@R__ref_app_src_journal.sql
@R__ref_app_doc_before_write.sql
@R__ref_app_doc_journal.sql

-- Objects created before what they reference are left INVALID until first use.
-- Recompile them now, so that T__000 only reports what really does not compile.
begin
   dbms_utility.compile_schema(schema => user, compile_all => false);
end;
/

-- ---- T__ : checks, last and not optional
-- A package body that fails to compile does not stop the run above: SQLcl
-- prints the errors and carries on to "Commit complete." T__000 turns that into
-- an exit code. T__001: Oracle does not refuse an unlicensed option, it records
-- the usage.
@T__000_no_invalid_objects.sql
@T__001_no_licensed_options.sql
