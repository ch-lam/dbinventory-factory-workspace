-- ============================================================================
-- R__pkg_dbinv_scoring.sql
-- ----------------------------------------------------------------------------
-- Scoring ETL package pkg_dbinv_scoring, driven by the parametric reference
-- tables (ref_control, ref_control_rule, ref_exception, ref_scoring_weight,
-- ref_threshold).
--
-- Four stages, one single derivation chain:
--
--   load_findings     raw per-item verdicts        -> fact_control_finding
--   apply_exceptions  resolve granted derogations  -> fact_control_finding.exception_id
--   load_compliance   roll-up per control/entity   -> fact_compliance
--   load_scoring      weighted aggregation         -> fact_scoring
--
-- Why a per-item fact:
--   The verdict an auditor needs is "which item deviates, and is that deviation
--   covered by a signed derogation". Collapsing it straight into a per-category
--   verdict, as the previous version did, left only a truncated text blob. The
--   raw verdict in fact_control_finding.is_compliant is NEVER rewritten by an
--   exception: a covered deviation keeps is_compliant = 0 and gets an
--   exception_id. That is what lets the RSSI team spot, during a periodic
--   review, a derogation that no longer covers anything.
--
-- Why exceptions are a separate stage:
--   Granting a derogation does not require a new collect. Running
--   apply_exceptions + load_compliance + load_scoring for a snapshot date is
--   enough to refresh that day's score.
--
-- Rules vs exceptions:
--   Scope conditions are part of the norm and stay in the predicates below
--   (system databases exempt from encryption, Express/Developer editions exempt
--   from TDE, sa/monitoring exempt from the login policy). Turning them into
--   exceptions would flood the list the RSSI team has to review. Only a decision
--   taken by a human on a specific item belongs in ref_exception.
--
-- Grain:
--   * Rules are evaluated at their natural level (ref_control_rule.entity_type):
--     per instance for sp_configure/registry/logins, per database for database
--     properties/encryption/guest/orphaned users/public role.
--   * fact_compliance stays at the control's grain (ref_control.entity_type) and
--     keeps exactly the shape it had before this refactoring, so load_scoring
--     and the APEX pages are untouched.
--
-- LICENSING (Oracle only): option and pack usage from Oracle's LMS usage script,
-- read through v_oracle_lms_usage (below), which the licensing page reads too.
-- MSSQL_LICENSING stays catalogued without a rule.
--
-- NOT YET IMPLEMENTED (documented gaps, no policy fabricated here):
--   * MSSQL LICENSING scoring: no edition/licence norm settled yet.
--   * PDB_OS_CREDENTIAL is collected but has no settled norm; it is catalogued
--     in ref_control_rule at active = 0 rather than judged on a made-up value.
--
-- Assumptions (validated against real data on the dev database):
--   * MSSQL security tables key on `servername`, joined to dim_instance on
--     instance_name. Verified: 0 unmatched instance, 0 unmatched database.
--   * ORACLE security tables key on `db_name` (v$database.name) and, at database
--     grain, on `pdb_name` -- 'NON CONTAINER' for a non-CDB, which maps to
--     dim_database.db_name = the database name itself.
--   * the ORACLE compliance_score column present on all twelve staging tables is
--     never populated by get_info_oracle_security.sh: it is a legacy vestige and
--     carries no verdict. Every Oracle predicate below is evaluated from the raw
--     collected values.
-- ============================================================================

create or replace package pkg_dbinv_scoring as

   procedure load_findings ( p_snapshot_date in date default trunc(sysdate) );

   procedure apply_exceptions ( p_snapshot_date in date default trunc(sysdate) );

   procedure load_compliance ( p_snapshot_date in date default trunc(sysdate) );

   procedure load_scoring ( p_snapshot_date in date default trunc(sysdate) );

   procedure load_all ( p_snapshot_date in date default trunc(sysdate) );

end pkg_dbinv_scoring;
/
