-- ============================================================================
-- V__011_create_application_api.sql
-- ----------------------------------------------------------------------------
-- Write API for the application registry: pkg_dbinv_application, plus the
-- triggers that journal every change to it.
--
-- WHERE THE GUARANTEE LIVES, AND WHY IT MOVED
--   The derogation model puts its journal calls inside pkg_dbinv_exception and
--   relies on every screen going through the package. That works because page 71
--   was written that way -- 1050 lines of APEXlang doing its DML through
--   processes.
--
--   This registry does not make that bet. An ordinary APEX form or interactive
--   grid writes the table with its own DML and will never call a package, so a
--   journal that lives in the package is a journal that silently stops the first
--   time somebody builds a screen the normal way. The journal therefore lives in
--   AFTER triggers: it holds for the package, for a form, for an interactive
--   grid, for a script, and for whatever comes next.
--
--   The package then exists for the things a trigger cannot do: validating a
--   polymorphic reference before it is stored, computing the next review date,
--   and carrying a human reason down to the trigger through current_reason.
--
-- WHAT THE PACKAGE STILL ENFORCES
--   link_entity checks that the entity exists. The reference is polymorphic, so
--   no foreign key can protect it, and a mistyped id would produce an attachment
--   that resolves to no database at all -- indistinguishable from an application
--   nobody has attached yet.
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

   -- ---------------------------------------------------------------------
   -- The channel between the API and the journal triggers.
   -- ---------------------------------------------------------------------
   -- A trigger sees what changed but never why. The package sets a reason before
   -- its DML and the triggers read it here. A screen writing the table directly
   -- simply leaves it null, and the change is journalled without a reason --
   -- which is still infinitely better than not journalled at all.
   --
   -- set_reason is public so a page process can supply one before its own DML.
   procedure set_reason ( p_reason varchar2 );
   function current_reason return varchar2;

end pkg_dbinv_application;
/

create or replace package body pkg_dbinv_application as

   g_reason varchar2(1000 char);


   -- ---------------------------------------------------------------------
   -- Internal helpers
   -- ---------------------------------------------------------------------

   procedure set_reason ( p_reason varchar2 ) is
   begin
      g_reason := substr(p_reason, 1, 1000);
   end set_reason;


   function current_reason return varchar2 is
   begin
      return g_reason;
   end current_reason;


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
   begin
      require_application(p_application_id);
      set_reason(p_note);

      update ref_application
         set app_name         = nvl(p_app_name, app_name),
             description      = nvl(p_description, description),
             criticality      = nvl(upper(p_criticality), criticality),
             lifecycle_status = nvl(upper(p_lifecycle_status), lifecycle_status),
             updated_by       = nvl(sys_context('APEX$SESSION','APP_USER'), user),
             updated_date     = sysdate
       where application_id = p_application_id;

      set_reason(null);
   end update_application;


   procedure deactivate_application ( p_application_id number, p_reason varchar2 ) is
   begin
      require_application(p_application_id);
      if p_reason is null then
         raise_application_error(-20035, 'Deactivating an application requires a reason.');
      end if;
      set_reason(p_reason);

      update ref_application
         set active = 0, updated_by = nvl(sys_context('APEX$SESSION','APP_USER'), user), updated_date = sysdate
       where application_id = p_application_id;

      set_reason(null);
   end deactivate_application;


   procedure record_review (
      p_application_id number,
      p_note           varchar2 default null,
      p_next_months    number default 12
   ) is
   begin
      require_application(p_application_id);
      set_reason(p_note);

      update ref_application
         set last_review_date = trunc(sysdate),
             last_review_by   = nvl(sys_context('APEX$SESSION','APP_USER'), user),
             review_due_date  = case when p_next_months is null then null
                                     else add_months(trunc(sysdate), p_next_months) end,
             updated_by       = nvl(sys_context('APEX$SESSION','APP_USER'), user),
             updated_date     = sysdate
       where application_id = p_application_id;

      set_reason(null);
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
   begin
      set_reason(p_note);

      update ref_application_group
         set contact_email   = nvl(p_contact_email, contact_email),
             ldap_dn         = nvl(p_ldap_dn, ldap_dn),
             ldap_group_name = nvl(p_ldap_group_name, ldap_group_name),
             external_ref    = nvl(p_external_ref, external_ref),
             note            = nvl(p_note, note),
             updated_by       = nvl(sys_context('APEX$SESSION','APP_USER'), user),
             updated_date     = sysdate
       where group_id = p_group_id;

      if sql%rowcount = 0 then
         set_reason(null);
         raise_application_error(-20036, 'Group ' || p_group_id || ' does not exist.');
      end if;
      set_reason(null);
   end update_group;


   procedure remove_group ( p_group_id number, p_reason varchar2 default null ) is
   begin
      set_reason(p_reason);

      -- Deactivated, not deleted. Knowing who used to be responsible is most of
      -- the value of a contact registry once something has gone wrong.
      update ref_application_group
         set active = 0, updated_by = nvl(sys_context('APEX$SESSION','APP_USER'), user), updated_date = sysdate
       where group_id = p_group_id;

      if sql%rowcount = 0 then
         set_reason(null);
         raise_application_error(-20036, 'Group ' || p_group_id || ' does not exist.');
      end if;
      set_reason(null);
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

      return l_id;
   end link_entity;


   procedure unlink_entity ( p_app_entity_id number, p_reason varchar2 default null ) is
   begin
      set_reason(p_reason);

      update ref_application_entity
         set active = 0
       where app_entity_id = p_app_entity_id;

      if sql%rowcount = 0 then
         set_reason(null);
         raise_application_error(-20037, 'Attachment ' || p_app_entity_id || ' does not exist.');
      end if;
      set_reason(null);
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

      return l_id;
   end add_document;


   procedure remove_document ( p_document_id number, p_reason varchar2 default null ) is
   begin
      set_reason(p_reason);
      delete from ref_application_document where document_id = p_document_id;
      set_reason(null);
   exception
      when others then
         set_reason(null);
         raise;
   end remove_document;


   procedure record_document_review (
      p_document_id number,
      p_note        varchar2 default null,
      p_next_months number default 12
   ) is
   begin
      set_reason(p_note);

      update ref_application_document
         set last_review_date = trunc(sysdate),
             last_review_by   = nvl(sys_context('APEX$SESSION','APP_USER'), user),
             review_due_date  = case when p_next_months is null then null
                                     else add_months(trunc(sysdate), p_next_months) end,
             updated_by       = nvl(sys_context('APEX$SESSION','APP_USER'), user),
             updated_date     = sysdate
       where document_id = p_document_id;

      if sql%rowcount = 0 then
         set_reason(null);
         raise_application_error(-20039, 'Document ' || p_document_id || ' does not exist.');
      end if;
      set_reason(null);
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

      return l_id;
   end add_source;


   procedure remove_source ( p_source_id number, p_reason varchar2 default null ) is
   begin
      set_reason(p_reason);

      update ref_application_source
         set active = 0
       where source_id = p_source_id;

      if sql%rowcount = 0 then
         set_reason(null);
         raise_application_error(-20040, 'Source ' || p_source_id || ' does not exist.');
      end if;
      set_reason(null);
   end remove_source;

end pkg_dbinv_application;
/


-- ============================================================================
-- The journal, in triggers
-- ----------------------------------------------------------------------------
-- One AFTER trigger per table. They are the only place the journal is written,
-- so there is exactly one answer to "is this change recorded" and it does not
-- depend on which piece of software made it.
--
-- Deactivation is journalled as a removal rather than as an update, because that
-- is what it means here: nothing is deleted, active = 0 is how something leaves
-- the registry, and a reader looking for "when did this group stop being
-- responsible" must not have to know that.
-- ============================================================================

create or replace trigger ref_application_journal
   after insert or update on ref_application
   for each row
begin
   if inserting then
      insert into ref_application_event ( application_id, event_type, subject_ref, new_value )
         values ( :new.application_id, 'CREATED', :new.app_code, :new.app_name );

   elsif :old.active = 1 and :new.active = 0 then
      insert into ref_application_event ( application_id, event_type, note )
         values ( :new.application_id, 'DEACTIVATED', pkg_dbinv_application.current_reason );

   elsif nvl(:new.last_review_date, date '0001-01-01')
         <> nvl(:old.last_review_date, date '0001-01-01') then
      insert into ref_application_event ( application_id, event_type, note, new_value )
         values ( :new.application_id, 'REVIEWED', pkg_dbinv_application.current_reason,
                  to_char(:new.review_due_date, 'YYYY-MM-DD') );

   elsif :old.lifecycle_status <> :new.lifecycle_status then
      -- Journalled on its own: this is the field whose history somebody actually
      -- goes looking for later.
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, old_value, new_value )
      values (
         :new.application_id, 'UPDATED', 'lifecycle_status',
         pkg_dbinv_application.current_reason, :old.lifecycle_status, :new.lifecycle_status );

   else
      insert into ref_application_event ( application_id, event_type, subject_ref, note )
         values ( :new.application_id, 'UPDATED', 'attributes',
                  pkg_dbinv_application.current_reason );
   end if;
end;
/

create or replace trigger ref_app_grp_journal
   after insert or update or delete on ref_application_group
   for each row
begin
   if inserting then
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, new_value )
      values (
         :new.application_id, 'GROUP_ADDED', :new.group_name, :new.group_type_code,
         nvl(:new.contact_email, nvl(:new.ldap_group_name, :new.external_ref)) );

   elsif deleting or ( :old.active = 1 and :new.active = 0 ) then
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, old_value )
      values (
         :old.application_id, 'GROUP_REMOVED', :old.group_name,
         pkg_dbinv_application.current_reason, :old.contact_email );

   else
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, old_value, new_value )
      values (
         :new.application_id, 'GROUP_UPDATED', :new.group_name,
         pkg_dbinv_application.current_reason, :old.contact_email, :new.contact_email );
   end if;
end;
/

create or replace trigger ref_app_ent_journal
   after insert or update or delete on ref_application_entity
   for each row
begin
   if inserting then
      insert into ref_application_event (
         application_id, event_type, subject_ref, note )
      values (
         :new.application_id, 'ENTITY_LINKED',
         :new.entity_type || ' ' || :new.entity_id, :new.note );

   elsif deleting or ( :old.active = 1 and :new.active = 0 ) then
      insert into ref_application_event (
         application_id, event_type, subject_ref, note )
      values (
         :old.application_id, 'ENTITY_UNLINKED',
         :old.entity_type || ' ' || :old.entity_id, pkg_dbinv_application.current_reason );
   end if;
end;
/

create or replace trigger ref_app_src_journal
   after insert or update or delete on ref_application_source
   for each row
begin
   if inserting then
      insert into ref_application_event (
         application_id, event_type, subject_ref, note )
      values (
         :new.application_id, 'SOURCE_ADDED', substr(:new.repo_url, 1, 200), :new.note );

   elsif deleting or ( :old.active = 1 and :new.active = 0 ) then
      insert into ref_application_event (
         application_id, event_type, subject_ref, note )
      values (
         :old.application_id, 'SOURCE_REMOVED', substr(:old.repo_url, 1, 200),
         pkg_dbinv_application.current_reason );
   end if;
end;
/


-- ============================================================================
-- Enforcement on ref_application_document
-- ----------------------------------------------------------------------------
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
   after insert or update or delete on ref_application_document
   for each row
begin
   if inserting then
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, new_value )
      values (
         :new.application_id, 'DOCUMENT_ADDED', substr(:new.title, 1, 200),
         nvl(:new.file_name, :new.external_url),
         nvl(:new.checksum_sha256, 'link only') );

   elsif deleting then
      -- The document goes, the trace of it having existed does not: the journal
      -- keeps its title and fingerprint, so a reader still sees what was
      -- withdrawn and can tell a deleted file from a deleted link.
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, old_value )
      values (
         :old.application_id, 'DOCUMENT_REMOVED', substr(:old.title, 1, 200),
         nvl(pkg_dbinv_application.current_reason, 'removed')
            || ' - ' || nvl(:old.file_name, :old.external_url),
         nvl(:old.checksum_sha256, 'link only') );

   elsif nvl(:new.last_review_date, date '0001-01-01')
         <> nvl(:old.last_review_date, date '0001-01-01') then
      insert into ref_application_event (
         application_id, event_type, subject_ref, note, new_value )
      values (
         :new.application_id, 'DOCUMENT_REVIEWED', substr(:new.title, 1, 200),
         pkg_dbinv_application.current_reason,
         to_char(:new.review_due_date, 'YYYY-MM-DD') );
   end if;
end;
/
