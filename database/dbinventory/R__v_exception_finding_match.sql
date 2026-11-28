-- ============================================================
-- v_exception_finding_match
-- ------------------------------------------------------------
-- Which findings the scope of a derogation designates: same rule, the
-- derogation entity being the finding entity or one of its ancestors, item and
-- observed value equal or wildcarded. Deliberately WITHOUT the approval gate,
-- the validity dates and the compliance of the finding: those belong to the
-- caller.
--   * pkg_dbinv_scoring.apply_exceptions adds them, the dates judged on the
--     snapshot date;
--   * v_exception_review uses the bare match to tell a derogation the scoring
--     has not applied yet from one that genuinely covers nothing.
-- Defined once so the two can never disagree on what "matches" means.
-- ============================================================
create or replace view v_exception_finding_match as
   select e.exception_id,
          f.rowid finding_rowid,
          f.snapshot_date,
          f.is_compliant,
          case e.entity_type
             when 'STORAGE'  then 1
             when 'DATABASE' then 2
             when 'INSTANCE' then 3
             else 4
          end specificity
     from fact_control_finding f
     join v_entity_ancestry a
       on a.entity_type = f.entity_type and a.entity_id = f.entity_id
     join ref_exception e
       on e.rule_code = f.rule_code
      and ( e.item_key = '*' or e.item_key = f.item_key )
      and ( e.observed_value = '*' or e.observed_value = f.observed_value )
      -- cascade: the exception entity must be the finding entity or one of its
      -- ancestors
      and e.entity_id = case e.entity_type
                           when 'HOST'     then a.host_id
                           when 'INSTANCE' then a.instance_id
                           when 'DATABASE' then a.database_id
                           when 'STORAGE'  then a.storage_unit_id
                        end;

comment on table v_exception_finding_match is 'Findings designated by the scope of each derogation, regardless of its status, dates or the compliance of the finding; the single matching rule shared by apply_exceptions and v_exception_review.';
