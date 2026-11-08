@V__001_create_schema.sql
@V__002_create_app_model.sql
@V__003_app_model_reference_data.sql
@V__004_create_inventory_etl.sql
@V__005_create_scoring_etl.sql
@V__006_create_discovery.sql
@V__007_create_discovery_etl.sql
@V__008_create_exception_api.sql
@V__009_initial_data.sql
@V__010_create_application_model.sql
@V__011_create_application_api.sql
@V__012_fix_audit_user_defaults.sql
@V__013_journal_document_replacement.sql

-- Last, and not optional: a package body that fails to compile does not stop the
-- run above -- SQLcl prints the errors and carries on to "Commit complete."
-- This turns that into an exit code.
@T_002_no_invalid_objects.sql
