-- ============================================================================
-- V__011_create_application_api.sql
-- ----------------------------------------------------------------------------
-- Write API for the application registry: pkg_dbinv_application. Screens never
-- write to ref_application and its satellites directly, they call these
-- procedures -- the same shape pkg_dbinv_exception gives the derogation screen.
--
-- Why an API rather than APEX forms:
--   * every change journals itself into ref_application_event, so the audit
--     trail cannot be bypassed from the interface. Forms doing their own DML
--     would leave it to each page to remember;
--   * the rules that make the registry trustworthy live in one place -- that a
--     link points at something that exists, that a document is either stored or
--     linked, that a review moves the next due date;
--   * it is platform-agnostic, like the registry itself. Nothing here knows
--     about Oracle, MSSQL, Postgres or MySQL.
--
-- One rule is enforced here and NOT in the model, deliberately: link_entity
-- checks that the entity exists. The reference is polymorphic, so the database
-- cannot do it with a foreign key -- and a mistyped entity_id would otherwise
-- produce an application that silently covers nothing, which reads exactly like
-- an application nobody has attached yet.
--
-- Prerequisite for stored documents: EXECUTE on SYS.DBMS_CRYPTO. A file that
-- cannot be fingerprinted is refused rather than stored unverifiable. Documents
-- carrying only a URL need no such grant, so the registry stays usable without
-- it -- which is the point of allowing a link instead of a file.
-- ============================================================================

alter session set current_schema=dbinventory;

create or replace package pkg_dbinv_application as

   -- ---------------------------------------------------------------------
   -- The application itself
   -- ---------------------------------------------------------------------
   function create_application (
      p_app_code         varchar2,
      p_app_name         varchar2,
      p_description      varchar2 default null,
      p_criticality      varchar2 default 'STANDARD',
      p_lifecycle_status varchar2 default 'ACTIVE',
      p_review_months    number default 12
   ) return number;

   procedure update_application (
      p_application_id   number,
      p_app_name         varchar2 default null,
      p_description      varchar2 default null,
      p_criticality      varchar2 default null,
      p_lifecycle_status varchar2 default null,
      p_note             varchar2 default null
   );

   procedure deactivate_application ( p_application_id number, p_reason varchar2 );

   procedure record_review (
      p_application_id number,
      p_note           varchar2 default null,
      p_next_months    number default 12
   );

   -- ---------------------------------------------------------------------
   -- Groups
   -- ---------------------------------------------------------------------
   function add_group (
      p_application_id  number,
      p_group_type_code varchar2,
      p_group_name      varchar2,
      p_contact_email   varchar2 default null,
      p_ldap_dn         varchar2 default null,
      p_ldap_group_name varchar2 default null,
      p_external_ref    varchar2 default null,
      p_note            varchar2 default null
   ) return number;

   procedure update_group (
      p_group_id        number,
      p_contact_email   varchar2 default null,
      p_ldap_dn         varchar2 default null,
      p_ldap_group_name varchar2 default null,
      p_external_ref    varchar2 default null,
      p_note            varchar2 default null
   );

   procedure remove_group ( p_group_id number, p_reason varchar2 default null );

   -- ---------------------------------------------------------------------
   -- Attachment to the inventory
   -- ---------------------------------------------------------------------
   function link_entity (
      p_application_id number,
      p_entity_type    varchar2,
      p_entity_id      number,
      p_note           varchar2 default null
   ) return number;

   procedure unlink_entity ( p_app_entity_id number, p_reason varchar2 default null );

   -- ---------------------------------------------------------------------
   -- Documentation
   -- ---------------------------------------------------------------------
   function fingerprint ( p_content blob ) return varchar2;

   function add_document (
      p_application_id  number,
      p_title           varchar2,
      p_doc_kind        varchar2 default 'OTHER',
      p_description     varchar2 default null,
      p_external_url    varchar2 default null,
      p_file_name       varchar2 default null,
      p_mime_type       varchar2 default null,
      p_content         blob default null,
      p_review_months   number default 12
   ) return number;

   procedure remove_document ( p_document_id number, p_reason varchar2 default null );

   procedure record_document_review (
      p_document_id number,
      p_note        varchar2 default null,
      p_next_months number default 12
   );

   -- ---------------------------------------------------------------------
   -- Sources
   -- ---------------------------------------------------------------------
   function add_source (
      p_application_id number,
      p_repo_url       varchar2,
      p_source_kind    varchar2 default 'GIT',
      p_branch         varchar2 default null,
      p_note           varchar2 default null
   ) return number;

   procedure remove_source ( p_source_id number, p_reason varchar2 default null );

   -- Read by the document journal trigger; see remove_document.
   function removal_reason return varchar2;

end pkg_dbinv_application;
/

create or replace package body pkg_dbinv_application as

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
      p_application_id number,
      p_event_type     varchar2,
      p_subject_ref    varchar2 default null,
      p_note           varchar2 default null,
      p_old_value      varchar2 default null,
      p_new_value      varchar2 default null
   ) is
   begin
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, old_value, new_value )
      values (
         p_application_id, p_event_type, substr(p_subject_ref, 1, 200),
         substr(p_note, 1, 1000), substr(p_old_value, 1, 1000), substr(p_new_value, 1, 1000) );
   end journal;


   procedure require_application ( p_application_id number ) is
      l_n pls_integer;
   begin
      select count(*) into l_n from ref_application where application_id = p_application_id;
      if l_n = 0 then
         raise_application_error(-20031,
            'Application ' || p_application_id || ' does not exist.');
      end if;
   end require_application;


   -- The check the database cannot make. entity_id is a polymorphic reference,
   -- so no foreign key can protect it; a mistyped id would create an attachment
   -- that resolves to no database at all, and an application covering nothing
   -- looks exactly like an application nobody has attached yet.
   procedure require_entity ( p_entity_type varchar2, p_entity_id number ) is
      l_n pls_integer;
   begin
      case upper(p_entity_type)
         when 'HOST' then
            select count(*) into l_n from dim_host where host_id = p_entity_id;
         when 'INSTANCE' then
            select count(*) into l_n from dim_instance where instance_id = p_entity_id;
         when 'DATABASE' then
            select count(*) into l_n from dim_database where database_id = p_entity_id;
         else
            raise_application_error(-20032,
               'Unknown entity type ' || p_entity_type || '; expected HOST, INSTANCE or DATABASE.');
      end case;

      if l_n = 0 then
         raise_application_error(-20033,
            'No ' || upper(p_entity_type) || ' with id ' || p_entity_id || '. '
            || 'Refused rather than stored: an attachment pointing at nothing resolves to no '
            || 'database, which is indistinguishable from an application nobody has attached.');
      end if;
   end require_entity;


   function fingerprint ( p_content blob ) return varchar2 is
      l_hash raw(32);
   begin
      execute immediate
         'begin :h := sys.dbms_crypto.hash(:c, 4); end;'   -- 4 = HASH_SH256
         using out l_hash, in p_content;
      return lower(rawtohex(l_hash));
   exception
      when others then
         raise_application_error(-20034,
            'Cannot fingerprint the document: EXECUTE on SYS.DBMS_CRYPTO is required '
            || '(grant execute on sys.dbms_crypto to ' || user || '). '
            || 'A file that cannot be fingerprinted is not stored, because it could not be '
            || 'proven intact later. Attach it as a URL instead, or obtain the grant. '
            || 'Original error: ' || sqlerrm);
   end fingerprint;


   -- ---------------------------------------------------------------------
   -- The application itself
   -- ---------------------------------------------------------------------
   function create_application (
      p_app_code         varchar2,
      p_app_name         varchar2,
      p_description      varchar2 default null,
      p_criticality      varchar2 default 'STANDARD',
      p_lifecycle_status varchar2 default 'ACTIVE',
      p_review_months    number default 12
   ) return number is
      l_id number;
   begin
      insert into ref_application (
         app_code, app_name, description, criticality, lifecycle_status, review_due_date )
      values (
         upper(trim(p_app_code)), p_app_name, p_description,
         upper(p_criticality), upper(p_lifecycle_status),
         case when p_review_months is null then null
              else add_months(trunc(sysdate), p_review_months) end )
      returning application_id into l_id;

      journal(l_id, 'CREATED', upper(trim(p_app_code)), p_app_name);
      return l_id;
   end create_application;


   procedure update_application (
      p_application_id   number,
      p_app_name         varchar2 default null,
      p_description      varchar2 default null,
      p_criticality      varchar2 default null,
      p_lifecycle_status varchar2 default null,
      p_note             varchar2 default null
   ) is
      l_old ref_application%rowtype;
   begin
      require_application(p_application_id);
      select * into l_old from ref_application where application_id = p_application_id;

      update ref_application
         set app_name         = nvl(p_app_name, app_name),
             description      = nvl(p_description, description),
             criticality      = nvl(upper(p_criticality), criticality),
             lifecycle_status = nvl(upper(p_lifecycle_status), lifecycle_status),
             updated_by       = user,
             updated_date     = sysdate
       where application_id = p_application_id;

      -- Journal the lifecycle move on its own: it is the field whose history
      -- anyone actually goes looking for afterwards.
      if p_lifecycle_status is not null and upper(p_lifecycle_status) <> l_old.lifecycle_status then
         journal(p_application_id, 'UPDATED', 'lifecycle_status', p_note,
                 l_old.lifecycle_status, upper(p_lifecycle_status));
      else
         journal(p_application_id, 'UPDATED', 'attributes', p_note);
      end if;
   end update_application;


   procedure deactivate_application ( p_application_id number, p_reason varchar2 ) is
   begin
      require_application(p_application_id);
      if p_reason is null then
         raise_application_error(-20035, 'Deactivating an application requires a reason.');
      end if;

      update ref_application
         set active = 0, updated_by = user, updated_date = sysdate
       where application_id = p_application_id;

      journal(p_application_id, 'DEACTIVATED', null, p_reason);
   end deactivate_application;


   procedure record_review (
      p_application_id number,
      p_note           varchar2 default null,
      p_next_months    number default 12
   ) is
   begin
      require_application(p_application_id);
      update ref_application
         set last_review_date = trunc(sysdate),
             last_review_by   = user,
             review_due_date  = case when p_next_months is null then null
                                     else add_months(trunc(sysdate), p_next_months) end,
             updated_by       = user,
             updated_date     = sysdate
       where application_id = p_application_id;

      journal(p_application_id, 'REVIEWED', null, p_note);
   end record_review;


   -- ---------------------------------------------------------------------
   -- Groups
   -- ---------------------------------------------------------------------
   function add_group (
      p_application_id  number,
      p_group_type_code varchar2,
      p_group_name      varchar2,
      p_contact_email   varchar2 default null,
      p_ldap_dn         varchar2 default null,
      p_ldap_group_name varchar2 default null,
      p_external_ref    varchar2 default null,
      p_note            varchar2 default null
   ) return number is
      l_id number;
   begin
      require_application(p_application_id);

      insert into ref_application_group (
         application_id, group_type_code, group_name, contact_email,
         ldap_dn, ldap_group_name, external_ref, note )
      values (
         p_application_id, upper(p_group_type_code), p_group_name, p_contact_email,
         p_ldap_dn, p_ldap_group_name, p_external_ref, p_note )
      returning group_id into l_id;

      journal(p_application_id, 'GROUP_ADDED', p_group_name,
              upper(p_group_type_code),
              null, nvl(p_contact_email, nvl(p_ldap_group_name, p_external_ref)));
      return l_id;
   end add_group;


   procedure update_group (
      p_group_id        number,
      p_contact_email   varchar2 default null,
      p_ldap_dn         varchar2 default null,
      p_ldap_group_name varchar2 default null,
      p_external_ref    varchar2 default null,
      p_note            varchar2 default null
   ) is
      l_old ref_application_group%rowtype;
   begin
      select * into l_old from ref_application_group where group_id = p_group_id;

      update ref_application_group
         set contact_email   = nvl(p_contact_email, contact_email),
             ldap_dn         = nvl(p_ldap_dn, ldap_dn),
             ldap_group_name = nvl(p_ldap_group_name, ldap_group_name),
             external_ref    = nvl(p_external_ref, external_ref),
             note            = nvl(p_note, note),
             updated_by      = user,
             updated_date    = sysdate
       where group_id = p_group_id;

      journal(l_old.application_id, 'GROUP_UPDATED', l_old.group_name, p_note,
              l_old.contact_email, nvl(p_contact_email, l_old.contact_email));
   exception
      when no_data_found then
         raise_application_error(-20036, 'Group ' || p_group_id || ' does not exist.');
   end update_group;


   procedure remove_group ( p_group_id number, p_reason varchar2 default null ) is
      l_old ref_application_group%rowtype;
   begin
      select * into l_old from ref_application_group where group_id = p_group_id;

      -- Deactivated, not deleted. Knowing who used to be responsible is most of
      -- the value of a contact registry once something has gone wrong.
      update ref_application_group
         set active = 0, updated_by = user, updated_date = sysdate
       where group_id = p_group_id;

      journal(l_old.application_id, 'GROUP_REMOVED', l_old.group_name, p_reason,
              l_old.contact_email, null);
   exception
      when no_data_found then
         raise_application_error(-20036, 'Group ' || p_group_id || ' does not exist.');
   end remove_group;


   -- ---------------------------------------------------------------------
   -- Attachment to the inventory
   -- ---------------------------------------------------------------------
   function link_entity (
      p_application_id number,
      p_entity_type    varchar2,
      p_entity_id      number,
      p_note           varchar2 default null
   ) return number is
      l_id number;
   begin
      require_application(p_application_id);
      require_entity(p_entity_type, p_entity_id);

      insert into ref_application_entity ( application_id, entity_type, entity_id, note )
         values ( p_application_id, upper(p_entity_type), p_entity_id, p_note )
      returning app_entity_id into l_id;

      journal(p_application_id, 'ENTITY_LINKED',
              upper(p_entity_type) || ' ' || p_entity_id, p_note);
      return l_id;
   end link_entity;


   procedure unlink_entity ( p_app_entity_id number, p_reason varchar2 default null ) is
      l_old ref_application_entity%rowtype;
   begin
      select * into l_old from ref_application_entity where app_entity_id = p_app_entity_id;

      update ref_application_entity
         set active = 0
       where app_entity_id = p_app_entity_id;

      journal(l_old.application_id, 'ENTITY_UNLINKED',
              l_old.entity_type || ' ' || l_old.entity_id, p_reason);
   exception
      when no_data_found then
         raise_application_error(-20037, 'Attachment ' || p_app_entity_id || ' does not exist.');
   end unlink_entity;


   -- ---------------------------------------------------------------------
   -- Documentation
   -- ---------------------------------------------------------------------
   function add_document (
      p_application_id  number,
      p_title           varchar2,
      p_doc_kind        varchar2 default 'OTHER',
      p_description     varchar2 default null,
      p_external_url    varchar2 default null,
      p_file_name       varchar2 default null,
      p_mime_type       varchar2 default null,
      p_content         blob default null,
      p_review_months   number default 12
   ) return number is
      l_id number;
   begin
      require_application(p_application_id);

      -- Said here as well as in the check constraint, because the constraint
      -- reports a name and this reports the decision.
      if p_content is null and p_external_url is null then
         raise_application_error(-20038,
            'A document needs a file or a link, or both. An entry with neither is '
            || 'an inventory line nobody can open.');
      end if;

      insert into ref_application_document (
         application_id, doc_kind, title, description, external_url,
         file_name, mime_type, content, review_due_date )
      values (
         p_application_id, upper(p_doc_kind), p_title, p_description, p_external_url,
         p_file_name, p_mime_type, p_content,
         case when p_review_months is null then null
              else add_months(trunc(sysdate), p_review_months) end )
      returning document_id into l_id;

      return l_id;   -- the journal entry is written by the trigger, for every writer
   end add_document;


   procedure remove_document ( p_document_id number, p_reason varchar2 default null ) is
   begin
      -- Read back by the journal trigger. The document row is really deleted, so
      -- the reason has nowhere else to live.
      g_remove_reason := p_reason;
      delete from ref_application_document where document_id = p_document_id;
      g_remove_reason := null;
   exception
      when others then
         g_remove_reason := null;
         raise;
   end remove_document;


   procedure record_document_review (
      p_document_id number,
      p_note        varchar2 default null,
      p_next_months number default 12
   ) is
      l_app  number;
      l_title ref_application_document.title%type;
   begin
      select application_id, title into l_app, l_title
        from ref_application_document where document_id = p_document_id;

      update ref_application_document
         set last_review_date = trunc(sysdate),
             last_review_by   = user,
             review_due_date  = case when p_next_months is null then null
                                     else add_months(trunc(sysdate), p_next_months) end,
             updated_by       = user,
             updated_date     = sysdate
       where document_id = p_document_id;

      journal(l_app, 'DOCUMENT_REVIEWED', l_title, p_note);
   exception
      when no_data_found then
         raise_application_error(-20039, 'Document ' || p_document_id || ' does not exist.');
   end record_document_review;


   -- ---------------------------------------------------------------------
   -- Sources
   -- ---------------------------------------------------------------------
   function add_source (
      p_application_id number,
      p_repo_url       varchar2,
      p_source_kind    varchar2 default 'GIT',
      p_branch         varchar2 default null,
      p_note           varchar2 default null
   ) return number is
      l_id number;
   begin
      require_application(p_application_id);

      insert into ref_application_source ( application_id, source_kind, repo_url, branch, note )
         values ( p_application_id, upper(p_source_kind), p_repo_url, p_branch, p_note )
      returning source_id into l_id;

      journal(p_application_id, 'SOURCE_ADDED', substr(p_repo_url, 1, 200), p_note);
      return l_id;
   end add_source;


   procedure remove_source ( p_source_id number, p_reason varchar2 default null ) is
      l_old ref_application_source%rowtype;
   begin
      select * into l_old from ref_application_source where source_id = p_source_id;

      update ref_application_source
         set active = 0
       where source_id = p_source_id;

      journal(l_old.application_id, 'SOURCE_REMOVED', substr(l_old.repo_url, 1, 200), p_reason);
   exception
      when no_data_found then
         raise_application_error(-20040, 'Source ' || p_source_id || ' does not exist.');
   end remove_source;

end pkg_dbinv_application;
/


-- ============================================================================
-- Enforcement on ref_application_document
-- ----------------------------------------------------------------------------
-- The fingerprint and the journal live in triggers rather than in add_document,
-- for the same reason they do on ref_exception_document: an APEX form uploading
-- a BLOB writes the row with its own DML and never calls the package. Putting
-- the guarantees here makes them hold for every writer -- a screen, the package,
-- a script -- instead of only for callers who remembered to go through the API.
--
-- One difference from the derogation case, and it is the whole reason this
-- register exists: content is OPTIONAL here. A document may be a link only, and
-- such a row must be storable on an instance with no DBMS_CRYPTO grant at all.
-- ============================================================================

create or replace trigger ref_app_doc_before_write
   before insert or update on ref_application_document
   for each row
begin
   if :new.content is null then
      :new.file_size       := null;
      :new.checksum_sha256 := null;
   else
      :new.file_size := dbms_lob.getlength(:new.content);

      if :new.file_size = 0 then
         raise_application_error(-20041,
            'Empty file refused. Store nothing and keep the link, or store a real file.');
      end if;

      -- Never trust a checksum supplied by the caller: recompute it. A
      -- fingerprint chosen by whoever uploads the file proves nothing.
      :new.checksum_sha256 := pkg_dbinv_application.fingerprint(:new.content);
   end if;
end;
/

create or replace trigger ref_app_doc_journal
   after insert or delete on ref_application_document
   for each row
begin
   if inserting then
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, new_value )
      values (
         :new.application_id, 'DOCUMENT_ADDED', substr(:new.title, 1, 200),
         nvl(:new.file_name, :new.external_url),
         nvl(:new.checksum_sha256, 'link only') );
   else
      -- The document goes, the trace of it having existed does not: the journal
      -- keeps its title and fingerprint, so a reader still sees what was
      -- withdrawn and can tell a deleted file from a deleted link.
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, old_value )
      values (
         :old.application_id, 'DOCUMENT_REMOVED', substr(:old.title, 1, 200),
         nvl(pkg_dbinv_application.removal_reason, 'removed')
            || ' - ' || nvl(:old.file_name, :old.external_url),
         nvl(:old.checksum_sha256, 'link only') );
   end if;
end;
/
