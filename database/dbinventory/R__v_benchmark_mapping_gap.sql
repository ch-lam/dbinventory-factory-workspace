-- ============================================================
-- v_benchmark_mapping_gap
-- ------------------------------------------------------------
-- The worklist of the mapping pass: every rule that claims a benchmark origin
-- but does not yet name the recommendation it transcribes. A compliance claim
-- is only as strong as this view is empty.
-- ============================================================
create or replace view v_benchmark_mapping_gap as
select rr.rule_code,
       rc.platform,
       rc.score_domain,
       rr.origin,
       rr.benchmark_code,
       b.version benchmark_version,
       rr.title,
       rr.active
  from ref_control_rule rr
  join ref_control rc on rc.control_code = rr.control_code
  left join ref_benchmark b on b.benchmark_code = rr.benchmark_code
 where rr.origin in ( 'BENCHMARK', 'HOUSE_CONFLICT' )
   and rr.benchmark_ref is null;
comment on table v_benchmark_mapping_gap is 'Rules claiming a benchmark origin whose recommendation identifier is not yet mapped; drives the review that makes the score opposable.';
