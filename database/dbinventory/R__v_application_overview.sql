-- ============================================================
-- v_application_overview
-- ------------------------------------------------------------
-- One row per application with everything a list needs, so the screen carries no
-- query logic of its own. Counting here rather than in the page means the
-- numbers on screen and the numbers a script reads cannot drift apart.
--
-- database_count reads v_application_database, so it counts what the cascade
-- actually resolves -- not the number of attachment rows, which would report 1
-- for an application covering an entire instance.
-- ============================================================
create or replace view v_application_overview as
   select a.application_id,
          a.app_code,
          a.app_name,
          a.description,
          a.criticality,
          a.lifecycle_status,
          a.review_due_date,
          a.last_review_date,
          a.sourcing,
          a.vendor_name,
          a.product_version,
          a.support_end_date,
          a.rto_minutes,
          a.rpo_minutes,
          a.service_window,
          a.data_sensitivity,
          ( select count(*) from v_application_database ad
             where ad.application_id = a.application_id ) database_count,
          ( select count(*) from ref_application_group g
             where g.application_id = a.application_id and g.active = 1 ) group_count,
          ( select count(*) from ref_application_contact c
             where c.application_id = a.application_id and c.active = 1 ) contact_count,
          ( select count(*) from ref_application_document d
             where d.application_id = a.application_id and d.active = 1 ) document_count,
          ( select count(*) from ref_application_source s
             where s.application_id = a.application_id and s.active = 1 ) source_count,
          ( select count(*) from v_application_document_review r
             where r.application_id = a.application_id and r.review_rank <= 3 ) doc_alert_count,
          case
             when a.review_due_date is null and a.last_review_date is null then 1
             when a.last_review_date is null then 2
             when a.review_due_date < trunc(sysdate) then 3
             else 4
          end review_rank,
          case
             when a.review_due_date is null and a.last_review_date is null then 'No review planned'
             when a.last_review_date is null then 'Never reviewed'
             when a.review_due_date < trunc(sysdate) then 'Overdue'
             else 'Current'
          end review_state
     from ref_application a
    where a.active = 1;
comment on table v_application_overview is 'One row per active application with its resolved database count, its satellites and its review state; the source of the application list screen.';
