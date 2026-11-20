-- ============================================================
-- v_exception_review
-- ------------------------------------------------------------
-- The periodic review worklist. review_state is ordered from the most blocking
-- to the most benign, and the row that matters most is the last one before
-- 'Current': an approved derogation that no longer covers any finding. It costs
-- nothing, breaks nothing, and therefore survives untouched for years -- while
-- still standing as an accepted deviation in front of an auditor.
-- ============================================================
create or replace view v_exception_review as
select e.exception_id,
       e.status,
       rc.platform,
       e.rule_code,
       r.title rule_title,
       e.entity_type,
       e.entity_id,
       nvl( nvl( i.instance_name, d.db_name ), h.hostname ) scope_name,
       e.item_key,
       e.observed_value,
       e.start_date,
       e.end_date,
       e.review_due_date,
       e.last_review_date,
       e.created_by,
       e.approved_by,
       e.replaces_exception_id,
       ( select count(*)
           from fact_control_finding f
          where f.exception_id = e.exception_id
            and f.snapshot_date = ( select max(f2.snapshot_date) from fact_control_finding f2 ) ) covered_today,
       case
          when e.status = 'DRAFT'     then 'Draft, not submitted'
          when e.status = 'SUBMITTED' then 'Awaiting approval'
          when e.status = 'REJECTED'  then 'Rejected'
          when e.status = 'REVOKED'   then 'Revoked'
          when e.status = 'SUPERSEDED' then 'Superseded'
          when e.active = 0           then 'Disabled'
          when e.end_date is not null and e.end_date < trunc(sysdate) then 'Expired'
          -- Approved but starting later, typically a renewal: the derogation it
          -- replaces covers until then. Without this state it read as "covers
          -- nothing", which is true today and wrong tomorrow.
          when e.start_date > sysdate then 'Approved, not yet in force'
          -- Approved and valid today, it designates an open deviation of the
          -- latest snapshot, yet covers none: the scoring has not run since it
          -- was granted (or it starts after the latest snapshot date, which is
          -- what apply_exceptions judges validity on). It has no effect at all,
          -- which ranks it above any deadline -- and without this state it would
          -- read exactly like a derogation that covers nothing.
          when e.start_date <= sysdate
           and ( select count(*)
                   from fact_control_finding f
                  where f.exception_id = e.exception_id
                    and f.snapshot_date = ( select max(f2.snapshot_date) from fact_control_finding f2 ) ) = 0
           and exists ( select 1
                          from v_exception_finding_match m
                         where m.exception_id = e.exception_id
                           and m.is_compliant = 0
                           and m.snapshot_date = ( select max(f3.snapshot_date) from fact_control_finding f3 ) )
             then 'Approved, not yet scored'
          when e.review_due_date is not null and e.review_due_date < trunc(sysdate) then 'Review overdue'
          when e.end_date is not null and e.end_date <= trunc(sysdate) + 60 then 'Expiring within 60 days'
          when ( select count(*)
                   from fact_control_finding f
                  where f.exception_id = e.exception_id
                    and f.snapshot_date = ( select max(f2.snapshot_date) from fact_control_finding f2 ) ) = 0
             then 'Approved, covers nothing'
          else 'Current'
       end review_state
  from ref_exception e
  join ref_control_rule r on r.rule_code = e.rule_code
  join ref_control rc on rc.control_code = r.control_code
  left join dim_host h on e.entity_type = 'HOST' and h.host_id = e.entity_id
  left join dim_instance i on e.entity_type = 'INSTANCE' and i.instance_id = e.entity_id
  left join dim_database d on e.entity_type = 'DATABASE' and d.database_id = e.entity_id;
comment on table v_exception_review is 'Every derogation with its review state; drives the periodic RSSI review and the derogations page. Platform-agnostic by construction.';
