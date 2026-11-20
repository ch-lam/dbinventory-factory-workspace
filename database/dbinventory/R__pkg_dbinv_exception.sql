create or replace package pkg_dbinv_exception as

   -- Default review period. A derogation is re-examined a year after it takes
   -- effect unless the caller says otherwise.
   c_review_months constant number := 12;

   -- Captures a derogation as a draft. Covers nothing until approved.
   function create_draft (
      p_rule_code      varchar2,
      p_entity_type    varchar2,
      p_entity_id      number,
      p_justification  varchar2,
      p_item_key       varchar2 default '*',
      p_observed_value varchar2 default '*',
      p_start_date     date default trunc(sysdate),
      p_end_date       date default null,
      p_deviation_date date default trunc(sysdate),
      p_document_ref   varchar2 default null,
      p_review_due     date default null
   ) return number;

   -- Amends a draft. Anything submitted is frozen: see renew.
   procedure amend (
      p_exception_id   number,
      p_justification  varchar2 default null,
      p_item_key       varchar2 default null,
      p_observed_value varchar2 default null,
      p_start_date     date default null,
      p_end_date       date default null,
      p_document_ref   varchar2 default null,
      p_note           varchar2 default null
   );

   -- Renews an approved derogation: captures a new draft with the same scope,
   -- chained to it through replaces_exception_id, carrying a copy of its
   -- attachments, and returns its id. The old one keeps covering; approving the
   -- renewal supersedes it.
   function renew ( p_exception_id number, p_note varchar2 default null ) return number;

   procedure submit ( p_exception_id number, p_note varchar2 default null );

   -- Approves. Refuses when the approver is the author. Approving a renewal
   -- supersedes the derogation it replaces.
   procedure approve (
      p_exception_id number,
      p_approver     varchar2 default nvl(sys_context('APEX$SESSION','APP_USER'), user),
      p_note         varchar2 default null
   );

   procedure reject ( p_exception_id number, p_reason varchar2 );

   -- Not named `revoke`: that is a reserved word in PL/SQL.
   procedure revoke_exception ( p_exception_id number, p_reason varchar2 );

   -- Records a periodic review and pushes the next due date.
   procedure record_review (
      p_exception_id number,
      p_note         varchar2 default null,
      p_next_review  date default null
   );

   -- SHA-256 of an attachment. Public because the ref_exception_document trigger
   -- calls it: that trigger, not this package, is the enforcement point, so the
   -- fingerprint is computed for every writer -- the APEX form region included.
   function fingerprint ( p_content blob ) return varchar2;

   -- Attaches evidence. Fingerprint, size and journal are applied by the trigger.
   function add_document (
      p_exception_id number,
      p_file_name    varchar2,
      p_content      blob,
      p_mime_type    varchar2 default null,
      p_doc_kind     varchar2 default 'OTHER'
   ) return number;

   procedure remove_document ( p_document_id number, p_reason varchar2 default null );

   -- Read by the journal trigger to label a withdrawal. NULL when a row is
   -- deleted outside remove_document, which the journal then records as a bare
   -- 'removed' rather than losing the event.
   function removal_reason return varchar2;

end pkg_dbinv_exception;
/
