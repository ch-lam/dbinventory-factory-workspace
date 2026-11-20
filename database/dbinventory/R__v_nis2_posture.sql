-- ============================================================
-- v_nis2_posture
-- ------------------------------------------------------------
-- One row per (entity, NIS2 domain), for the posture band carried by the six
-- instance and database cards. Polymorphic like the rest of the model: INSTANCE
-- and DATABASE rows sit in the same view, so the six pages share one query.
--
-- The CROSS JOIN with ref_nis2_domain is the point of the view, not a detail.
-- Aggregating the findings alone would make a domain with nothing collected
-- VANISH, and a missing block reads exactly like a passing one. Crossing first
-- and outer-joining after is what lets rules_evaluated = 0 be stated instead of
-- being inferred from an absence -- "what is missing" is the question the band
-- exists to answer.
--
-- Two grains, two rules of belonging:
--   * INSTANCE rolls the whole chain up -- the instance, its databases, their
--     storage units. "Is anything wrong under this instance?"
--   * DATABASE stops at the database and its storage units. An instance-grain
--     finding is NOT copied down: one xp_cmdshell left on would otherwise
--     redden all eleven databases of that instance, eleven times one fix.
--
-- An open gap is is_compliant = 0 AND no exception AND not accepted by the
-- norm, the same definition the severity donuts of pages 21/31/41 already use.
-- A waived finding is a deviation that someone owns; it must not be counted as
-- a gap, and must not be silently turned into compliance either, hence its own
-- DEROGATED status.
--
-- Severity ranks CRITICAL and HIGH together as CRITICAL: the band has one
-- colour for "stop and fix", and splitting it further makes the screen quieter
-- than the fleet is.
-- ============================================================
create or replace view v_nis2_posture as
with fnd as (
   select a.instance_id,
          a.database_id,
          r.nis2_domain_code,
          f.rule_code,
          case when f.is_compliant = 0
                and f.exception_id is null
                and f.is_norm_exception = 0
               then 1 else 0 end is_open,
          case when f.is_compliant = 0
                and ( f.exception_id is not null or f.is_norm_exception = 1 )
               then 1 else 0 end is_waived,
          case nvl( r.severity, rc.severity )
             when 'CRITICAL' then 4
             when 'HIGH'     then 3
             when 'MEDIUM'   then 2
             else 1
          end severity_rank
     from fact_control_finding f
     join ref_control_rule r
       on r.rule_code = f.rule_code
      and r.active = 1
      and r.nis2_domain_code is not null
     join ref_control rc
       on rc.control_code = r.control_code
      and rc.active = 1
     join v_entity_ancestry a
       on a.entity_type = f.entity_type
      and a.entity_id = f.entity_id
    where f.snapshot_date = ( select max(f2.snapshot_date) from fact_control_finding f2 )
),
agg as (
   select 'INSTANCE' entity_type,
          f.instance_id entity_id,
          f.nis2_domain_code,
          count(distinct f.rule_code) rules_evaluated,
          sum(f.is_open) open_gaps,
          sum(f.is_waived) derogated,
          max(case when f.is_open = 1 then f.severity_rank end) worst_rank
     from fnd f
    where f.instance_id is not null
    group by f.instance_id, f.nis2_domain_code
   union all
   select 'DATABASE',
          f.database_id,
          f.nis2_domain_code,
          count(distinct f.rule_code),
          sum(f.is_open),
          sum(f.is_waived),
          max(case when f.is_open = 1 then f.severity_rank end)
     from fnd f
    where f.database_id is not null
    group by f.database_id, f.nis2_domain_code
),
ent as (
   select 'INSTANCE' entity_type, i.instance_id entity_id, i.platform
     from dim_instance i
   union all
   select 'DATABASE', d.database_id, d.platform
     from dim_database d
)
select e.entity_type,
       e.entity_id,
       e.platform,
       d.nis2_domain_code,
       d.display_order,
       d.title,
       d.article_ref,
       nvl( a.rules_evaluated, 0 ) rules_evaluated,
       nvl( a.open_gaps, 0 ) open_gaps,
       nvl( a.derogated, 0 ) derogated,
       case a.worst_rank
          when 4 then 'CRITICAL'
          when 3 then 'HIGH'
          when 2 then 'MEDIUM'
          when 1 then 'LOW'
       end worst_severity,
       case when nvl( a.rules_evaluated, 0 ) = 0 then 'NOT_ASSESSED'
            when a.worst_rank >= 3                then 'CRITICAL'
            when a.worst_rank >= 1                then 'WARNING'
            when nvl( a.derogated, 0 ) > 0        then 'DEROGATED'
            else 'OK'
       end status,
       case when nvl( a.rules_evaluated, 0 ) = 0
               then 'No rule of this measure is evaluated at this level.'
            when nvl( a.open_gaps, 0 ) > 0
               then a.open_gaps || ' open, worst '
                    || initcap( case a.worst_rank
                                   when 4 then 'CRITICAL'
                                   when 3 then 'HIGH'
                                   when 2 then 'MEDIUM'
                                   else 'LOW'
                                end )
                    || ', on ' || a.rules_evaluated || ' rule(s) checked.'
            when nvl( a.derogated, 0 ) > 0
               then 'No open gap, ' || a.derogated
                    || ' deviation(s) waived, on ' || a.rules_evaluated || ' rule(s) checked.'
            else 'Compliant on ' || a.rules_evaluated || ' rule(s) checked.'
       end summary
  from ent e
 cross join ref_nis2_domain d
  left join agg a
    on a.entity_type = e.entity_type
   and a.entity_id = e.entity_id
   and a.nis2_domain_code = d.nis2_domain_code;
comment on table v_nis2_posture is 'NIS2 article 21(2) posture of every instance and database, one row per domain including those with nothing evaluated; feeds the posture band of the six card pages and nothing else.';
