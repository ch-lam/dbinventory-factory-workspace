-- ============================================================
-- v_environment_identity
-- ------------------------------------------------------------
-- Which environment am I looking at, and is its data real. One source of truth
-- for three consumers: the About page for a human, SQLcl for a test, a pipeline
-- for an automated guard.
--
-- Shaped as name/value pairs rather than columns, deliberately. The APEX page
-- becomes a trivial report, a pipeline extracts one value by name
--   select value from v_environment_identity where name = 'Service name'
-- and adding an entry later touches neither the page nor any caller.
--
-- Why it exists: APEX_BASE_URL and the SQLcl connection name are configured
-- independently, so nothing guarantees a browser and a script are looking at the
-- same database. Two environments look alike until one of them lies to you.
-- ============================================================
create or replace view v_environment_identity as
with release as (
   select version, installed_date, installed_by
     from ( select version, installed_date, installed_by
              from ref_app_release order by release_id desc )
    where rownum = 1
),
freshness as (
   select max(data_as_of) newest, min(data_as_of) oldest, max(snapshot_date) last_snapshot
     from fact_scoring
    where snapshot_date = ( select max(snapshot_date) from fact_scoring )
)
-- 1. Identity: where this is running.
select 1 section_order, 'Identity' section, 10 sort_order, 'Database' name,
       sys_context('USERENV','DB_NAME') value from dual
union all
select 1, 'Identity', 20, 'Container', sys_context('USERENV','CON_NAME') from dual
union all
select 1, 'Identity', 30, 'Service name', sys_context('USERENV','SERVICE_NAME') from dual
union all
select 1, 'Identity', 40, 'Database unique name', sys_context('USERENV','DB_UNIQUE_NAME') from dual
union all
select 1, 'Identity', 50, 'Server host', sys_context('USERENV','SERVER_HOST') from dual
union all
select 1, 'Identity', 60, 'Schema', sys_context('USERENV','CURRENT_SCHEMA') from dual
union all
-- Matched on '%Database%', not 'Oracle Database%': the product is named
-- "Oracle AI Database 26ai Enterprise Edition" here, and a stricter pattern
-- silently returns nothing -- an empty field looks like a missing privilege.
select 1, 'Identity', 70, 'Database version',
       ( select max(version_full) from product_component_version
          where product like '%Database%' ) from dual
-- 2. Release: what was installed, and when.
union all
select 2, 'Release', 10, 'Schema version',
       nvl(( select version from release ), '(never recorded)') from dual
union all
select 2, 'Release', 20, 'Deployed on',
       nvl(to_char(( select installed_date from release ), 'YYYY-MM-DD HH24:MI'), '-') from dual
union all
select 2, 'Release', 30, 'Deployed by', nvl(( select installed_by from release ), '-') from dual
union all
select 2, 'Release', 40, 'Installations recorded', to_char(( select count(*) from ref_app_release )) from dual
-- 3. Data: is what I am looking at real and recent.
union all
select 3, 'Data', 10, 'Collected on',
       nvl(to_char(( select newest from freshness ), 'YYYY-MM-DD'), '(no scoring yet)') from dual
union all
select 3, 'Data', 20, 'Data age (days)',
       nvl(to_char(trunc(sysdate) - ( select newest from freshness )), '-') from dual
union all
select 3, 'Data', 30, 'Oldest collect in scope',
       nvl(to_char(( select oldest from freshness ), 'YYYY-MM-DD'), '-') from dual
union all
select 3, 'Data', 40, 'Last scoring snapshot',
       nvl(to_char(( select last_snapshot from freshness ), 'YYYY-MM-DD'), '(none)') from dual
-- 4. Volume: a plausibility check at a glance.
union all
select 4, 'Volume', 10, 'Instances', to_char(( select count(*) from dim_instance )) from dual
union all
select 4, 'Volume', 20, 'Databases', to_char(( select count(*) from dim_database )) from dual
union all
select 4, 'Volume', 30, 'Findings (last snapshot)',
       to_char(( select count(*) from fact_control_finding
                  where snapshot_date = ( select max(snapshot_date) from fact_control_finding ) )) from dual
union all
select 4, 'Volume', 40, 'Active rules', to_char(( select count(*) from ref_control_rule where active = 1 )) from dual
union all
select 4, 'Volume', 50, 'Derogations', to_char(( select count(*) from ref_exception )) from dual;
comment on table v_environment_identity is 'Name/value description of the environment: identity, release, data freshness and volume. Read by the About page, by SQLcl and by deployment pipelines to confirm which database they are talking to.';
