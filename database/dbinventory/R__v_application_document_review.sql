-- ============================================================
-- v_application_document_review
-- ------------------------------------------------------------
-- The review worklist, shaped like v_exception_review: review_state is ordered
-- from the most blocking to the most benign so a report can sort on it directly.
--
-- 'Never reviewed' ranks above 'Overdue' deliberately. A document that has been
-- in the register since the beginning without anyone confirming it still
-- describes reality is a worse signal than one whose review slipped by a week.
-- ============================================================
create or replace view v_application_document_review as
   select d.document_id,
          d.application_id,
          a.app_code,
          a.app_name,
          d.doc_kind,
          d.title,
          d.external_url,
          d.file_name,
          d.review_due_date,
          d.last_review_date,
          d.last_review_by,
          trunc(sysdate) - d.review_due_date days_overdue,
          case
             when d.review_due_date is null and d.last_review_date is null then 1
             when d.last_review_date is null then 2
             when d.review_due_date < trunc(sysdate) then 3
             when d.review_due_date < trunc(sysdate) + 30 then 4
             else 5
          end review_rank,
          case
             when d.review_due_date is null and d.last_review_date is null then 'No review planned'
             when d.last_review_date is null then 'Never reviewed'
             when d.review_due_date < trunc(sysdate) then 'Overdue'
             when d.review_due_date < trunc(sysdate) + 30 then 'Due within 30 days'
             else 'Current'
          end review_state
     from ref_application_document d
     join ref_application a
       on a.application_id = d.application_id
    where d.active = 1
      and a.active = 1;
comment on table v_application_document_review is 'Review worklist for application documentation, ordered from the most blocking state to the most benign.';
