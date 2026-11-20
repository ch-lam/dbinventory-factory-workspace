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

   -- The profile: software, continuity, data, and the review date.
   -- ---------------------------------------------------------------------
   -- Separate from update_application, and with the opposite null semantics.
   -- update_application only overwrites what it is given, which is right for a
   -- caller that knows one field. This one is called by a form that holds every
   -- field at once, where clearing a box is a deliberate act -- so what is passed
   -- overwrites, NULL included.
   --
   -- review_due_date lives here rather than in create_application because the
   -- screen has to be able to set it at creation. It could not: the create path
   -- dropped the date that had just been typed, silently.
   procedure set_profile (
      p_application_id  number,
      p_sourcing        varchar2 default null,
      p_vendor_name     varchar2 default null,
      p_product_version varchar2 default null,
      p_support_end_date date default null,
      p_rto_minutes     number default null,
      p_rpo_minutes     number default null,
      p_service_window  varchar2 default null,
      p_data_sensitivity varchar2 default null,
      p_register_ref    varchar2 default null,
      p_review_due_date date default null,
      p_note            varchar2 default null
   );

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
   -- Named contacts
   -- ---------------------------------------------------------------------
   -- Same shape as the groups, deliberately: whoever has read the three group
   -- routines has read these three. update_contact overwrites with what it is
   -- given, NULL included, for the same reason set_profile does -- it is called
   -- by a form holding every field, where an emptied box means "remove this".
   function add_contact (
      p_application_id number,
      p_contact_role   varchar2,
      p_full_name      varchar2,
      p_job_title      varchar2 default null,
      p_email          varchar2 default null,
      p_phone          varchar2 default null,
      p_ldap_login     varchar2 default null,
      p_is_primary     number default 0,
      p_note           varchar2 default null
   ) return number;

   procedure update_contact (
      p_contact_id   number,
      p_contact_role varchar2,
      p_full_name    varchar2,
      p_job_title    varchar2 default null,
      p_email        varchar2 default null,
      p_phone        varchar2 default null,
      p_ldap_login   varchar2 default null,
      p_is_primary   number default 0,
      p_note         varchar2 default null
   );

   procedure remove_contact ( p_contact_id number, p_reason varchar2 default null );

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
