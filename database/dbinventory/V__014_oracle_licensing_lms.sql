-- ============================================================================
-- V__014_oracle_licensing_lms.sql
-- ----------------------------------------------------------------------------
-- Score Oracle option and pack usage (LMS) on schemas already installed.
--
-- WHY
--   The LMS usage script has been collected and loaded into oracle_lms since
--   the start, and nothing read it: ORACLE_LICENSING_LMS was catalogued with no
--   rule, so no finding, no LICENSING score and no page. V__003 and V__005 now
--   carry the reference rows, the view v_oracle_lms_usage and the findings
--   procedure for a fresh install.
--
-- WHY A SEPARATE SCRIPT
--   X_000 does not replay V__003 on an installed schema (plain inserts). This
--   script brings the same reference rows with MERGE, so it is a no-op on a
--   fresh install and safe to run twice.
--
-- ORDER (installed schema)
--   1. this script        reference rows
--   2. V__005             view + package (create or replace)
--   3. compute_info_all.sh, or pkg_dbinv_scoring.load_all, for the findings
-- ============================================================================

alter session set current_schema=dbinventory;

merge into ref_control t
using ( select 'ORACLE_LICENSING_LMS_PAST' control_code, 'ORACLE' platform, 'LICENSING' score_domain,
               'licensing_past' category, 'INSTANCE' entity_type,
               'Oracle feature usage (LMS) licensing, past usage' title, 'MEDIUM' severity
          from dual ) s
on ( t.control_code = s.control_code )
when not matched then
   insert ( control_code, platform, score_domain, category, entity_type, title, severity )
   values ( s.control_code, s.platform, s.score_domain, s.category, s.entity_type, s.title, s.severity );

-- 100 on a single category before; 70/30 between current and past usage now.
merge into ref_scoring_weight t
using ( select 'ORACLE' platform, 'LICENSING' score_domain, 'licensing' category, '*' environment, 70 weight from dual
        union all
        select 'ORACLE', 'LICENSING', 'licensing_past', '*', 30 from dual ) s
on ( t.platform = s.platform and t.score_domain = s.score_domain
     and t.category = s.category and t.environment = s.environment )
when matched then update set t.weight = s.weight
when not matched then
   insert ( platform, score_domain, category, environment, weight )
   values ( s.platform, s.score_domain, s.category, s.environment, s.weight );

merge into ref_control_rule t
using ( select 'ORACLE_LMS_OPTION_IN_USE' rule_code, 'ORACLE_LICENSING_LMS' control_code,
               'INSTANCE' entity_type, 'option / pack' item_key_label,
               'No unlicensed Oracle option or pack in use' title,
               'CURRENT_USAGE or PAST_OR_CURRENT_USAGE reported by the LMS usage script. Multitenant is recounted from the collected PDBs: up to 3 user PDBs need no licence from 19c, 1 before. On Standard Edition no option can be licensed at all.' description,
               'HIGH' severity
          from dual
        union all
        select 'ORACLE_LMS_OPTION_PAST_USE', 'ORACLE_LICENSING_LMS_PAST',
               'INSTANCE', 'option / pack',
               'No past usage of an unlicensed Oracle option or pack',
               'PAST_USAGE reported by the LMS usage script: the option is no longer used, but an audit still counts it.',
               'MEDIUM'
          from dual ) s
on ( t.rule_code = s.rule_code )
when matched then update set
   t.control_code = s.control_code, t.entity_type = s.entity_type,
   t.item_key_label = s.item_key_label, t.title = s.title,
   t.description = s.description, t.severity = s.severity
when not matched then
   insert ( rule_code, control_code, entity_type, item_key_label, title, description, severity )
   values ( s.rule_code, s.control_code, s.entity_type, s.item_key_label, s.title, s.description, s.severity );

commit;
