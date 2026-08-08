-- ============================================================================
-- V__008_create_exception_api.sql
-- ----------------------------------------------------------------------------
-- Write API for derogations: pkg_dbinv_exception. The derogation screen never
-- writes to ref_exception directly, it calls these procedures - the same shape
-- pkg_dbinv_discovery.set_triage already gives the discovery triage modal.
--
-- Why an API rather than an APEX form:
--   * every transition journals itself into ref_exception_event, so the audit
--     trail cannot be bypassed from the interface. A form doing DML would leave
--     it to each page to remember;
--   * the rules that make a derogation defensible - who may approve, what an
--     amendment invalidates, what a review resets - live in one place instead of
--     being spread over page processes and validations;
--   * the screen is platform-agnostic and so is this package. Nothing here knows
--     about MSSQL, Oracle, Postgres or MySQL: it all goes through rule_code and
--     the polymorphic entity reference.
--
-- Lifecycle:
--   DRAFT --submit--> SUBMITTED --approve--> APPROVED --revoke--> REVOKED
--                          |                     |
--                          +---reject---> REJECTED
--                                                +--amend--> SUBMITTED (again)
--
-- Only APPROVED is honoured by pkg_dbinv_scoring.apply_exceptions.
--
-- Prerequisite for attachments: EXECUTE on SYS.DBMS_CRYPTO, which this schema
-- does not currently hold. add_document refuses to store a file it cannot
-- fingerprint rather than keeping an unverifiable attachment, so the grant is a
-- hard prerequisite of the upload feature (and only of that feature).
-- ============================================================================

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

   -- Amends a draft, or an approved derogation. Amending the scope or extending
   -- the end date of an approved derogation sends it back for approval.
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

   procedure submit ( p_exception_id number, p_note varchar2 default null );

   -- Approves. Refuses when the approver is the author.
   procedure approve (
      p_exception_id number,
      p_approver     varchar2 default user,
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

create or replace package body pkg_dbinv_exception as

   -- Set for the duration of a remove_document call, read by the journal trigger.
   g_remove_reason varchar2(1000 char);


   -- ---------------------------------------------------------------------
   -- Internal helpers
   -- ---------------------------------------------------------------------

   function removal_reason return varchar2 is
   begin
      return g_remove_reason;
   end removal_reason;

   procedure journal (
      p_exception_id number,
      p_event_type   varchar2,
      p_note         varchar2 default null,
      p_old_value    varchar2 default null,
      p_new_value    varchar2 default null
   ) is
   begin
      insert into ref_exception_event ( exception_id, event_type, note, old_value, new_value )
         values ( p_exception_id, p_event_type,
                  substr(p_note, 1, 1000), substr(p_old_value, 1, 1000), substr(p_new_value, 1, 1000) );
   end journal;


   function current_status ( p_exception_id number ) return varchar2 is
      l_status ref_exception.status%type;
   begin
      select status into l_status from ref_exception where exception_id = p_exception_id;
      return l_status;
   exception
      when no_data_found then
         raise_application_error(-20020, 'Derogation ' || p_exception_id || ' does not exist.');
   end current_status;


   procedure require_status ( p_exception_id number, p_expected varchar2 ) is
      l_status ref_exception.status%type := current_status(p_exception_id);
   begin
      if instr(',' || p_expected || ',', ',' || l_status || ',') = 0 then
         raise_application_error(-20021,
            'Derogation ' || p_exception_id || ' is ' || l_status
            || '; this operation expects one of: ' || p_expected || '.');
      end if;
   end require_status;


   -- DBMS_CRYPTO is reached through dynamic SQL so this package still compiles
   -- where the grant is missing: the failure then surfaces at upload time with an
   -- actionable message, instead of leaving the whole API uninstallable.
   function fingerprint ( p_content blob ) return varchar2 is
      l_hash raw(32);
   begin
      execute immediate
         'begin :h := sys.dbms_crypto.hash(:c, 4); end;'   -- 4 = HASH_SH256
         using out l_hash, in p_content;
      return lower(rawtohex(l_hash));
   exception
      when others then
         raise_application_error(-20022,
            'Cannot fingerprint the attachment: EXECUTE on SYS.DBMS_CRYPTO is required '
            || '(grant execute on sys.dbms_crypto to ' || user || '). '
            || 'A file that cannot be fingerprinted is not stored, because it could not be '
            || 'proven intact later. Original error: ' || sqlerrm);
   end fingerprint;


   -- ---------------------------------------------------------------------
   -- create_draft
   -- ---------------------------------------------------------------------
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
   ) return number is
      l_id ref_exception.exception_id%type;
   begin
      insert into ref_exception (
         rule_code, entity_type, entity_id, item_key, observed_value,
         start_date, end_date, deviation_date, justification, document_ref,
         review_due_date, status )
      values (
         p_rule_code, p_entity_type, p_entity_id,
         nvl(p_item_key, '*'), nvl(p_observed_value, '*'),
         trunc(nvl(p_start_date, sysdate)), p_end_date,
         trunc(nvl(p_deviation_date, sysdate)), p_justification, p_document_ref,
         nvl( p_review_due, add_months(trunc(nvl(p_start_date, sysdate)), c_review_months) ),
         'DRAFT' )
      returning exception_id into l_id;

      journal(l_id, 'CREATED', 'Draft captured on rule ' || p_rule_code
                               || ' for ' || p_entity_type || ' ' || p_entity_id);
      return l_id;
   end create_draft;


   -- ---------------------------------------------------------------------
   -- amend
   -- ---------------------------------------------------------------------
   procedure amend (
      p_exception_id   number,
      p_justification  varchar2 default null,
      p_item_key       varchar2 default null,
      p_observed_value varchar2 default null,
      p_start_date     date default null,
      p_end_date       date default null,
      p_document_ref   varchar2 default null,
      p_note           varchar2 default null
   ) is
      l_row       ref_exception%rowtype;
      l_scope_old varchar2(1000 char);
      l_scope_new varchar2(1000 char);
      l_material  boolean := false;
   begin
      select * into l_row from ref_exception where exception_id = p_exception_id for update;

      if l_row.status in ( 'REVOKED', 'REJECTED' ) then
         raise_application_error(-20023,
            'Derogation ' || p_exception_id || ' is ' || l_row.status || ' and cannot be amended. '
            || 'Capture a new one instead, so the closed decision stays readable.');
      end if;

      l_scope_old := l_row.item_key || ' / ' || l_row.observed_value
                     || ' / ' || to_char(l_row.start_date, 'YYYY-MM-DD')
                     || ' / ' || nvl(to_char(l_row.end_date, 'YYYY-MM-DD'), 'open');

      -- What counts as material: anything widening what the derogation covers.
      -- Rewording the justification does not, pushing the end date back does.
      if ( p_item_key is not null and p_item_key <> l_row.item_key )
         or ( p_observed_value is not null and p_observed_value <> l_row.observed_value )
         or ( p_start_date is not null and trunc(p_start_date) <> l_row.start_date )
         or ( p_end_date is not null
              and ( l_row.end_date is null or trunc(p_end_date) > l_row.end_date ) )
      then
         l_material := true;
      end if;

      update ref_exception
         set item_key       = nvl(p_item_key, item_key),
             observed_value = nvl(p_observed_value, observed_value),
             start_date     = trunc(nvl(p_start_date, start_date)),
             end_date       = nvl(p_end_date, end_date),
             justification  = nvl(p_justification, justification),
             document_ref   = nvl(p_document_ref, document_ref),
             -- A material amendment on an approved derogation sends it back for
             -- approval: otherwise a derogation accepted for one case could be
             -- silently stretched to another while keeping its signature.
             status         = case when l_material and status = 'APPROVED' then 'SUBMITTED' else status end,
             approved_by    = case when l_material and status = 'APPROVED' then null else approved_by end,
             approval_date  = case when l_material and status = 'APPROVED' then null else approval_date end,
             updated_by     = user,
             updated_date   = sysdate
       where exception_id = p_exception_id
      returning item_key || ' / ' || observed_value
                || ' / ' || to_char(start_date, 'YYYY-MM-DD')
                || ' / ' || nvl(to_char(end_date, 'YYYY-MM-DD'), 'open')
        into l_scope_new;

      journal(p_exception_id, 'AMENDED',
              case when l_material then 'Material amendment: approval reset. ' else '' end || p_note,
              l_scope_old, l_scope_new);
   end amend;


   -- ---------------------------------------------------------------------
   -- submit / approve / reject / revoke
   -- ---------------------------------------------------------------------
   procedure submit ( p_exception_id number, p_note varchar2 default null ) is
   begin
      require_status(p_exception_id, 'DRAFT,REJECTED');
      update ref_exception
         set status = 'SUBMITTED', submitted_by = user, submitted_date = sysdate,
             rejected_reason = null, updated_by = user, updated_date = sysdate
       where exception_id = p_exception_id;
      journal(p_exception_id, 'SUBMITTED', p_note);
   end submit;


   procedure approve (
      p_exception_id number,
      p_approver     varchar2 default user,
      p_note         varchar2 default null
   ) is
      l_created_by ref_exception.created_by%type;
   begin
      require_status(p_exception_id, 'SUBMITTED');
      select created_by into l_created_by from ref_exception where exception_id = p_exception_id;

      -- Checked here as well as by the table constraint: the error raised from
      -- the API names the reason, where the constraint would only name itself.
      if upper(p_approver) = upper(l_created_by) then
         raise_application_error(-20024,
            'A derogation cannot be approved by the person who created it (' || l_created_by || '). '
            || 'Approval must come from a different person, typically the SSI or operations manager.');
      end if;

      update ref_exception
         set status = 'APPROVED', approved_by = p_approver, approval_date = sysdate,
             review_due_date = nvl(review_due_date, add_months(trunc(sysdate), c_review_months)),
             updated_by = user, updated_date = sysdate
       where exception_id = p_exception_id;

      journal(p_exception_id, 'APPROVED', p_note, null, 'approved by ' || p_approver);
   end approve;


   procedure reject ( p_exception_id number, p_reason varchar2 ) is
   begin
      require_status(p_exception_id, 'SUBMITTED');
      update ref_exception
         set status = 'REJECTED', rejected_reason = p_reason,
             updated_by = user, updated_date = sysdate
       where exception_id = p_exception_id;
      journal(p_exception_id, 'REJECTED', p_reason);
   end reject;


   procedure revoke_exception ( p_exception_id number, p_reason varchar2 ) is
   begin
      require_status(p_exception_id, 'DRAFT,SUBMITTED,APPROVED');
      update ref_exception
         set status = 'REVOKED', revoked_by = user, revoked_date = sysdate,
             revoke_reason = p_reason, active = 0,
             updated_by = user, updated_date = sysdate
       where exception_id = p_exception_id;
      journal(p_exception_id, 'REVOKED', p_reason);
   end revoke_exception;


   -- ---------------------------------------------------------------------
   -- record_review
   -- ---------------------------------------------------------------------
   procedure record_review (
      p_exception_id number,
      p_note         varchar2 default null,
      p_next_review  date default null
   ) is
      l_next date;
   begin
      require_status(p_exception_id, 'APPROVED');
      l_next := nvl(p_next_review, add_months(trunc(sysdate), c_review_months));
      update ref_exception
         set last_review_date = trunc(sysdate), review_due_date = l_next,
             updated_by = user, updated_date = sysdate
       where exception_id = p_exception_id;
      journal(p_exception_id, 'REVIEWED', p_note, null,
              'next review ' || to_char(l_next, 'YYYY-MM-DD'));
   end record_review;


   -- ---------------------------------------------------------------------
   -- Attachments
   -- ---------------------------------------------------------------------
   function add_document (
      p_exception_id number,
      p_file_name    varchar2,
      p_content      blob,
      p_mime_type    varchar2 default null,
      p_doc_kind     varchar2 default 'OTHER'
   ) return number is
      l_id ref_exception_document.document_id%type;
   begin
      -- Deliberately a plain insert: size, fingerprint and journalling are applied
      -- by the trigger below, so a row written by the APEX form region carries the
      -- exact same guarantees as one written here.
      insert into ref_exception_document (
         exception_id, doc_kind, file_name, mime_type, content )
      values (
         p_exception_id, p_doc_kind, p_file_name, p_mime_type, p_content )
      returning document_id into l_id;

      return l_id;
   end add_document;


   procedure remove_document ( p_document_id number, p_reason varchar2 default null ) is
   begin
      -- The withdrawal reason is stashed for the trigger, which does the
      -- journalling: it is the only place that sees every delete, wherever it
      -- comes from.
      g_remove_reason := p_reason;
      delete from ref_exception_document where document_id = p_document_id;
      g_remove_reason := null;

      if sql%rowcount = 0 then
         raise_application_error(-20026, 'Attachment ' || p_document_id || ' does not exist.');
      end if;
   end remove_document;

end pkg_dbinv_exception;
/


-- ============================================================================
-- Enforcement on ref_exception_document
-- ----------------------------------------------------------------------------
-- The fingerprint and the journal live here rather than in add_document because
-- the derogation screen cannot call the API to upload: APEXlang only sanctions a
-- BLOB upload as a `fileUpload` render role inside a `form` region bound to the
-- table (component-policies REGION_RULE_014/015), which means APEX writes the row
-- with its own DML. Putting the guarantees in the trigger makes them hold for
-- every writer -- the screen, this package, a script -- instead of only for
-- callers who remembered to go through the API.
-- ============================================================================

create or replace trigger ref_exc_doc_before_write
   before insert on ref_exception_document
   for each row
begin
   :new.file_size := dbms_lob.getlength(:new.content);

   if :new.file_size is null or :new.file_size = 0 then
      raise_application_error(-20025, 'Empty attachment refused.');
   end if;

   -- Never trust a checksum supplied by the caller: recompute it. An attachment
   -- whose fingerprint could be chosen by whoever uploads it proves nothing.
   :new.checksum_sha256 := pkg_dbinv_exception.fingerprint(:new.content);
end;
/

create or replace trigger ref_exc_doc_journal
   after insert or delete on ref_exception_document
   for each row
begin
   if inserting then
      insert into ref_exception_event ( exception_id, event_type, note, new_value )
         values ( :new.exception_id, 'DOCUMENT_ADDED', :new.file_name, :new.checksum_sha256 );
   else
      -- The file goes, the trace of it having existed does not: the journal keeps
      -- its name and fingerprint, so an auditor still sees what was withdrawn.
      insert into ref_exception_event ( exception_id, event_type, note, old_value )
         values ( :old.exception_id, 'DOCUMENT_REMOVED',
                  nvl(pkg_dbinv_exception.removal_reason, 'removed') || ' - ' || :old.file_name,
                  :old.checksum_sha256 );
   end if;
end;
/
