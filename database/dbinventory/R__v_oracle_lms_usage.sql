-- ============================================================================
-- v_oracle_lms_usage
-- ----------------------------------------------------------------------------
-- One row per (instance, product) of Oracle's option and pack usage script
-- (bin/sql/oracle_lms.sql -> staging oracle_lms), with the perimeter that
-- decides whether it is judged. Shared by load_findings_licensing and the
-- licensing page, so the screen can never disagree with the score on what is
-- in use.
--
-- Why a view over the staging and not a fact: the usage script already carries
-- its own history (first and last usage dates). What the model needs is the
-- latest reading, which is exactly what the staging holds.
--
-- Reading the script output:
--   * a CDB reports one row per container (grouping_id = 0) plus an aggregate
--     over all of them (grouping_id = 1, '--ALL--'); a non-CDB reports one row.
--     Taking the strongest usage over every row of a database never counts a
--     container twice and never misses one.
--   * Multitenant: the script counts it as used as soon as a CDB holds more
--     than one PDB, which was the rule before 19c. From 19c, up to 3 user PDBs
--     need no licence. The usage is recounted from oracle_pdbs (PDB$SEED is not
--     collected there) and a current usage within the free allowance is read as
--     no usage. The script itself is Oracle's and is left untouched.
--   * products prefixed with '.' are separate products (Database Gateway,
--     GoldenGate, Exadata...), not database options. They stay judged: a
--     gateway other than the free ODBC one is licensed on its own.
--   * scope: an instance whose perimeter licence has scoring_impact = 0 (SAP
--     runtime, FREE, PROVIDER, INCCI) is shown but not judged. An unknown
--     licence is judged: the conservative side.
-- ============================================================================
create or replace view v_oracle_lms_usage as
with
lms as (
   select l.db_name,
          l.product_name,
          l.grouping_id,
          -- the aggregate row names no container
          nullif(trim(l.db_pdb_name), '--ALL--') container_name,
          upper(trim(l.usage_detected)) usage_detected,
          case upper(trim(l.usage_detected))
             when 'CURRENT_USAGE'         then 4
             when 'PAST_OR_CURRENT_USAGE' then 3
             when 'PAST_USAGE'            then 2
             else 1
          end usage_rank,
          -- validate_conversion, not to_date(... default null on conversion
          -- error): on 23.26 a GROUP BY GROUPING SETS over this view -- which is
          -- how a faceted search counts its facets (page 22) -- fails with
          -- ORA-43907, the rewrite no longer seeing the default as a literal.
          case when validate_conversion(l.first_usage_date as date, 'YYYYMMDD') = 1
               then to_date(l.first_usage_date, 'YYYYMMDD') end first_usage,
          case when validate_conversion(l.last_usage_date as date, 'YYYYMMDD') = 1
               then to_date(l.last_usage_date, 'YYYYMMDD') end last_usage
     from oracle_lms l
),
prod as (
   select db_name,
          product_name,
          max(usage_rank) usage_rank,
          min(first_usage) first_usage_date,
          max(last_usage) last_usage_date,
          listagg(distinct case when grouping_id = 0 and usage_rank >= 2 then container_name end, ', ')
             within group ( order by case when grouping_id = 0 and usage_rank >= 2 then container_name end )
             containers
     from lms
    group by db_name, product_name
),
-- One instance per database name, as the security findings do: a RAC database
-- has several rows in oracle_databases and option usage belongs to the database.
od as (
   select db_name, hostname, instance_name, environment, license_type
     from ( select od.db_name, od.hostname, od.instance_name, od.environment, od.license_type,
                   row_number() over ( partition by od.db_name order by od.instance_name ) rn
              from oracle_databases od )
    where rn = 1
),
pdbs as (
   select hostname, instance_name, count(*) user_pdbs
     from oracle_pdbs
    where pdb_name not like 'PDB$%'
    group by hostname, instance_name
),
base as (
   select di.instance_id,
          od.hostname,
          od.instance_name,
          p.db_name,
          od.environment,
          od.license_type,
          case when nvl(lt.scoring_impact, 100) > 0 then 1 else 0 end in_scope,
          di.edition,
          di.engine_version,
          to_number(regexp_substr(di.engine_version, '^[0-9]+')) major_version,
          p.product_name,
          case when p.product_name like '.%' then 1 else 0 end is_separate_product,
          p.usage_rank,
          p.first_usage_date,
          p.last_usage_date,
          p.containers,
          nvl(pc.user_pdbs, 0) user_pdbs
     from prod p
     left join od on od.db_name = p.db_name
     left join dim_host dh on dh.platform = 'ORACLE' and dh.hostname = od.hostname
     left join dim_instance di on di.host_id = dh.host_id and di.instance_name = od.instance_name
     left join licence_types lt on lt.license_type = od.license_type
     left join pdbs pc on pc.hostname = od.hostname and pc.instance_name = od.instance_name
),
judged as (
   select b.*,
          case when b.major_version >= 19 then 3 else 1 end free_pdbs,
          case when b.product_name = 'Multitenant'
                and b.usage_rank >= 3
                and b.user_pdbs <= case when b.major_version >= 19 then 3 else 1 end
               then 1
               else b.usage_rank
          end effective_rank
     from base b
)
select instance_id,
       hostname,
       instance_name,
       db_name,
       environment,
       license_type,
       in_scope,
       edition,
       engine_version,
       product_name,
       ltrim(product_name, '.') product_label,
       is_separate_product,
       case usage_rank when 4 then 'CURRENT_USAGE' when 3 then 'PAST_OR_CURRENT_USAGE'
                       when 2 then 'PAST_USAGE' else 'NO_USAGE' end reported_usage,
       case effective_rank when 4 then 'CURRENT_USAGE' when 3 then 'PAST_OR_CURRENT_USAGE'
                           when 2 then 'PAST_USAGE' else 'NO_USAGE' end usage_status,
       case when effective_rank <> usage_rank
            then user_pdbs || ' user PDB(s), up to ' || free_pdbs || ' need no Multitenant licence on '
                 || nvl(engine_version, 'this version')
       end usage_note,
       containers,
       first_usage_date,
       last_usage_date,
       user_pdbs
  from judged;

comment on table v_oracle_lms_usage is 'Oracle option and pack usage per (instance, product), from the LMS usage script, with the perimeter licence that decides whether it is judged and the Multitenant recount; read by load_findings_licensing and by the licensing page.';
