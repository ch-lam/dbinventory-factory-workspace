create or replace package body pkg_dbinv_transfer as

   type t_counts is table of pls_integer index by varchar2(60);
   g_counts t_counts;
   g_buffer blob;

   c_items constant sys.odcivarchar2list := sys.odcivarchar2list(
      'APPLICATION', 'GROUP', 'CONTACT', 'ENTITY', 'DOCUMENT', 'SOURCE' );


   -- ---------------------------------------------------------------------
   -- Helpers
   -- ---------------------------------------------------------------------

   procedure say ( p_line varchar2 ) is
   begin
      dbms_output.put_line(p_line);
   end say;


   procedure bump ( p_item varchar2, p_outcome varchar2 ) is
      l_key varchar2(60) := upper(p_item) || '/' || upper(p_outcome);
   begin
      g_counts(l_key) := case when g_counts.exists(l_key) then g_counts(l_key) else 0 end + 1;
   end bump;


   function counter ( p_item varchar2, p_outcome varchar2 ) return number is
      l_key varchar2(60) := upper(p_item) || '/' || upper(p_outcome);
   begin
      return case when g_counts.exists(l_key) then g_counts(l_key) else 0 end;
   end counter;


   function d2s ( p_date date ) return varchar2 is
   begin
      return to_char(p_date, 'YYYY-MM-DD');
   end d2s;


   function s2d ( p_text varchar2 ) return date is
   begin
      return to_date(p_text, 'YYYY-MM-DD');
   end s2d;


   -- Null-aware inequality: the comparison every "has it changed" test needs.
   function differs ( p_a varchar2, p_b varchar2 ) return boolean is
   begin
      return ( p_a is null and p_b is not null )
          or ( p_a is not null and p_b is null )
          or p_a <> p_b;
   end differs;


   -- Appends a field name to the list of changes when the values differ.
   procedure track ( p_changes in out varchar2, p_field varchar2, p_old varchar2, p_new varchar2 ) is
   begin
      if differs(p_old, p_new) then
         p_changes := p_changes || case when p_changes is not null then ', ' end || p_field;
      end if;
   end track;


   function utf8_blob ( p_text clob ) return blob is
      l_out  blob;
      l_dest integer := 1;
      l_src  integer := 1;
      l_lang integer := dbms_lob.default_lang_ctx;
      l_warn integer;
   begin
      dbms_lob.createtemporary(l_out, true);
      dbms_lob.converttoblob(l_out, p_text, dbms_lob.lobmaxsize, l_dest, l_src,
                             nls_charset_id('AL32UTF8'), l_lang, l_warn);
      return l_out;
   end utf8_blob;


   function utf8_clob ( p_bytes blob ) return clob is
      l_out  clob;
      l_dest integer := 1;
      l_src  integer := 1;
      l_lang integer := dbms_lob.default_lang_ctx;
      l_warn integer;
   begin
      dbms_lob.createtemporary(l_out, true);
      dbms_lob.converttoclob(l_out, p_bytes, dbms_lob.lobmaxsize, l_dest, l_src,
                             nls_charset_id('AL32UTF8'), l_lang, l_warn);
      return l_out;
   end utf8_clob;


   -- Base64 without line breaks. 12000 bytes is a multiple of 3, so every
   -- piece encodes without padding and the pieces simply concatenate.
   function to_base64 ( p_bytes blob ) return clob is
      c_step constant pls_integer := 12000;
      l_out   clob;
      l_off   integer := 1;
      l_len   integer := nvl(dbms_lob.getlength(p_bytes), 0);
      l_piece varchar2(32767);
   begin
      if l_len = 0 then
         return null;
      end if;
      dbms_lob.createtemporary(l_out, true);
      while l_off <= l_len loop
         l_piece := utl_raw.cast_to_varchar2(
                       utl_encode.base64_encode(dbms_lob.substr(p_bytes, c_step, l_off)));
         l_piece := replace(replace(l_piece, chr(13)), chr(10));
         dbms_lob.writeappend(l_out, length(l_piece), l_piece);
         l_off := l_off + c_step;
      end loop;
      return l_out;
   end to_base64;


   -- 16000 characters is a multiple of 4: each piece decodes on its own.
   function from_base64 ( p_text clob ) return blob is
      c_step constant pls_integer := 16000;
      l_out  blob;
      l_off  integer := 1;
      l_len  integer := nvl(dbms_lob.getlength(p_text), 0);
      l_raw  raw(32767);
   begin
      if l_len = 0 then
         return null;
      end if;
      dbms_lob.createtemporary(l_out, true);
      while l_off <= l_len loop
         l_raw := utl_encode.base64_decode(utl_raw.cast_to_raw(dbms_lob.substr(p_text, c_step, l_off)));
         dbms_lob.writeappend(l_out, utl_raw.length(l_raw), l_raw);
         l_off := l_off + c_step;
      end loop;
      return l_out;
   end from_base64;


   function has_value ( p_obj json_object_t, p_key varchar2 ) return boolean is
   begin
      return p_obj.has(p_key) and not p_obj.get(p_key).is_null;
   end has_value;


   function array_of ( p_obj json_object_t, p_key varchar2 ) return json_array_t is
   begin
      if has_value(p_obj, p_key) then
         return p_obj.get_array(p_key);
      end if;
      return json_array_t();
   end array_of;


   function audit_user return varchar2 is
   begin
      return nvl(sys_context('APEX$SESSION', 'APP_USER'), user);
   end audit_user;


   -- ---------------------------------------------------------------------
   -- Export
   -- ---------------------------------------------------------------------

   function export_json ( p_app_codes varchar2 default null ) return clob is
      l_root json_object_t := json_object_t();
      l_src  json_object_t := json_object_t();
      l_doms json_object_t := json_object_t();
      l_apps json_array_t  := json_array_t();
      l_app  json_object_t;
      l_arr  json_array_t;
      l_obj  json_object_t;
      l_out  clob;
      l_missing varchar2(4000);
   begin
      g_counts.delete;

      -- Every requested code must exist: a typo would otherwise produce a
      -- smaller file that looks complete.
      if p_app_codes is not null then
         select listagg(c.code, ', ') within group ( order by c.code )
           into l_missing
           from ( select distinct upper(trim(regexp_substr(p_app_codes, '[^,]+', 1, level))) code
                    from dual
                 connect by level <= regexp_count(p_app_codes, '[^,]+') ) c
          where c.code is not null
            and not exists ( select 1 from ref_application a
                              where a.app_code = c.code and a.active = 1 );
         if l_missing is not null then
            raise_application_error(-20950,
               'Unknown or inactive application code(s): ' || l_missing || '.');
         end if;
      end if;

      l_root.put('format', c_format);
      l_root.put('version', c_version);
      l_root.put('exported_at', to_char(sysdate, 'YYYY-MM-DD"T"HH24:MI:SS'));
      l_src.put('service', sys_context('USERENV', 'SERVICE_NAME'));
      l_src.put('container', sys_context('USERENV', 'CON_NAME'));
      l_src.put('schema', sys_context('USERENV', 'CURRENT_SCHEMA'));
      l_root.put('source', l_src);

      for a in ( select *
                   from ref_application
                  where active = 1
                    and ( p_app_codes is null
                          or app_code in ( select upper(trim(regexp_substr(p_app_codes, '[^,]+', 1, level)))
                                             from dual
                                          connect by level <= regexp_count(p_app_codes, '[^,]+') ) )
                  order by app_code ) loop
         l_app := json_object_t();
         l_app.put('app_code',                a.app_code);
         l_app.put('app_name',                a.app_name);
         l_app.put('description',             a.description);
         l_app.put('criticality',             a.criticality);
         l_app.put('lifecycle_status',        a.lifecycle_status);
         l_app.put('review_due_date',         d2s(a.review_due_date));
         l_app.put('last_review_date',        d2s(a.last_review_date));
         l_app.put('last_review_by',          a.last_review_by);
         l_app.put('sourcing',                a.sourcing);
         l_app.put('vendor_name',             a.vendor_name);
         l_app.put('product_version',         a.product_version);
         l_app.put('support_end_date',        d2s(a.support_end_date));
         l_app.put('rto_minutes',             a.rto_minutes);
         l_app.put('rpo_minutes',             a.rpo_minutes);
         l_app.put('service_window',          a.service_window);
         l_app.put('data_sensitivity',        a.data_sensitivity);
         l_app.put('processing_register_ref', a.processing_register_ref);

         l_arr := json_array_t();
         for g in ( select * from ref_application_group
                     where application_id = a.application_id and active = 1
                     order by group_type_code, group_name ) loop
            l_obj := json_object_t();
            l_obj.put('group_type_code', g.group_type_code);
            l_obj.put('group_name',      g.group_name);
            l_obj.put('contact_email',   g.contact_email);
            l_obj.put('ldap_dn',         g.ldap_dn);
            l_obj.put('ldap_group_name', g.ldap_group_name);
            l_obj.put('external_ref',    g.external_ref);
            l_obj.put('note',            g.note);
            l_arr.append(l_obj);
            bump('GROUP', 'EXPORTED');
         end loop;
         l_app.put('groups', l_arr);

         l_arr := json_array_t();
         for c in ( select * from ref_application_contact
                     where application_id = a.application_id and active = 1
                     order by contact_role, full_name ) loop
            l_obj := json_object_t();
            l_obj.put('contact_role', c.contact_role);
            l_obj.put('full_name',    c.full_name);
            l_obj.put('job_title',    c.job_title);
            l_obj.put('email',        c.email);
            l_obj.put('phone',        c.phone);
            l_obj.put('ldap_login',   c.ldap_login);
            l_obj.put('is_primary',   c.is_primary);
            l_obj.put('note',         c.note);
            l_arr.append(l_obj);
            bump('CONTACT', 'EXPORTED');
         end loop;
         l_app.put('contacts', l_arr);

         -- The attachment leaves as names. An attachment whose entity no longer
         -- exists here has no name to give, and is reported rather than exported.
         l_arr := json_array_t();
         for e in ( select ae.entity_type, ae.entity_id, ae.note,
                           h.platform, h.hostname, i.instance_name, d.db_name
                      from ref_application_entity ae
                      left join dim_database d
                        on ae.entity_type = 'DATABASE' and d.database_id = ae.entity_id
                      left join dim_instance i
                        on i.instance_id = case ae.entity_type
                                              when 'INSTANCE' then ae.entity_id
                                              when 'DATABASE' then d.instance_id
                                           end
                      left join dim_host h
                        on h.host_id = case ae.entity_type
                                          when 'HOST' then ae.entity_id
                                          else i.host_id
                                       end
                     where ae.application_id = a.application_id and ae.active = 1
                     order by ae.entity_type, h.hostname, i.instance_name, d.db_name ) loop
            if e.hostname is null then
               say('MSG:  attention, ' || a.app_code || ' : rattachement ' || e.entity_type || ' '
                   || e.entity_id || ' ne pointe plus sur rien ici, non exporte');
               bump('ENTITY', 'SKIPPED');
            else
               l_obj := json_object_t();
               l_obj.put('entity_type',   e.entity_type);
               l_obj.put('platform',      e.platform);
               l_obj.put('hostname',      e.hostname);
               l_obj.put('instance_name', e.instance_name);
               l_obj.put('db_name',       e.db_name);
               l_obj.put('note',          e.note);
               l_arr.append(l_obj);
               bump('ENTITY', 'EXPORTED');
            end if;
         end loop;
         l_app.put('entities', l_arr);

         l_arr := json_array_t();
         for d in ( select * from ref_application_document
                     where application_id = a.application_id and active = 1
                     order by title, document_id ) loop
            l_obj := json_object_t();
            l_obj.put('doc_kind',         d.doc_kind);
            l_obj.put('title',            d.title);
            l_obj.put('description',      d.description);
            l_obj.put('external_url',     d.external_url);
            l_obj.put('file_name',        d.file_name);
            l_obj.put('mime_type',        d.mime_type);
            l_obj.put('file_size',        d.file_size);
            l_obj.put('checksum_sha256',  d.checksum_sha256);
            l_obj.put('review_due_date',  d2s(d.review_due_date));
            l_obj.put('last_review_date', d2s(d.last_review_date));
            l_obj.put('last_review_by',   d.last_review_by);
            if d.content is null then
               l_obj.put_null('content_base64');
            else
               l_obj.put('content_base64', to_base64(d.content));
            end if;
            l_arr.append(l_obj);
            bump('DOCUMENT', 'EXPORTED');
         end loop;
         l_app.put('documents', l_arr);

         l_arr := json_array_t();
         for s in ( select * from ref_application_source
                     where application_id = a.application_id and active = 1
                     order by repo_url ) loop
            l_obj := json_object_t();
            l_obj.put('source_kind', s.source_kind);
            l_obj.put('repo_url',    s.repo_url);
            l_obj.put('branch',      s.branch);
            l_obj.put('note',        s.note);
            l_arr.append(l_obj);
            bump('SOURCE', 'EXPORTED');
         end loop;
         l_app.put('sources', l_arr);

         l_apps.append(l_app);
         bump('APPLICATION', 'EXPORTED');
      end loop;

      l_doms.put('applications', l_apps);
      l_root.put('domains', l_doms);

      l_out := l_root.to_clob;
      select json_serialize(l_out returning clob pretty) into l_out from dual;
      return l_out;
   end export_json;


   procedure print_export ( p_app_codes varchar2 default null ) is
      c_width constant pls_integer := 3200;   -- multiple of 4
      l_b64 clob;
      l_off integer := 1;
      l_len integer;
   begin
      l_b64 := to_base64(utf8_blob(export_json(p_app_codes)));
      l_len := dbms_lob.getlength(l_b64);
      while l_off <= l_len loop
         say('B64:' || dbms_lob.substr(l_b64, c_width, l_off));
         l_off := l_off + c_width;
      end loop;

      say('MSG:Source : ' || sys_context('USERENV', 'SERVICE_NAME'));
      for i in 1 .. c_items.count loop
         say('MSG:  ' || rpad(lower(c_items(i)), 12) || ' ' || counter(c_items(i), 'EXPORTED'));
      end loop;
   end print_export;


   -- ---------------------------------------------------------------------
   -- Import
   -- ---------------------------------------------------------------------

   function resolve_entity (
      p_type     varchar2,
      p_platform varchar2,
      p_host     varchar2,
      p_instance varchar2,
      p_db       varchar2,
      p_why      out varchar2
   ) return number is
      l_id number;
   begin
      -- Case-insensitive: the same machine reported as SRV01 by one collector
      -- and srv01 by another is still the same machine. Two rows that only
      -- differ by case would make it ambiguous, and are reported as such.
      case p_type
         when 'HOST' then
            select h.host_id into l_id
              from dim_host h
             where h.platform = p_platform
               and upper(h.hostname) = upper(p_host);
         when 'INSTANCE' then
            select i.instance_id into l_id
              from dim_instance i
              join dim_host h on h.host_id = i.host_id
             where h.platform = p_platform
               and upper(h.hostname) = upper(p_host)
               and upper(i.instance_name) = upper(p_instance);
         when 'DATABASE' then
            select d.database_id into l_id
              from dim_database d
              join dim_instance i on i.instance_id = d.instance_id
              join dim_host h on h.host_id = i.host_id
             where h.platform = p_platform
               and upper(h.hostname) = upper(p_host)
               and upper(i.instance_name) = upper(p_instance)
               and upper(d.db_name) = upper(p_db);
         else
            p_why := 'type de rattachement inconnu';
            return null;
      end case;
      return l_id;
   exception
      when no_data_found then
         p_why := 'absent de la cible';
         return null;
      when too_many_rows then
         p_why := 'ambigu dans la cible';
         return null;
   end resolve_entity;


   procedure require_group_type ( p_code varchar2 ) is
      l_n pls_integer;
   begin
      select count(*) into l_n from ref_application_group_type where group_type_code = p_code;
      if l_n = 0 then
         raise_application_error(-20956,
            'Group type / contact role ' || p_code || ' does not exist in the target '
            || '(ref_application_group_type). Add it there first.');
      end if;
   end require_group_type;


   -- Every value is read from the JSON into a record before any DML: package
   -- private functions and JSON object methods cannot be called from SQL.
   function import_application ( p_app json_object_t ) return number is
      n         ref_application%rowtype;
      r         ref_application%rowtype;
      l_changes varchar2(4000);
      l_user    varchar2(100 char) := audit_user;
   begin
      n.app_code                := upper(trim(p_app.get_string('app_code')));
      n.app_name                := p_app.get_string('app_name');
      n.description             := p_app.get_string('description');
      n.criticality             := nvl(upper(p_app.get_string('criticality')), 'STANDARD');
      n.lifecycle_status        := nvl(upper(p_app.get_string('lifecycle_status')), 'ACTIVE');
      n.review_due_date         := s2d(p_app.get_string('review_due_date'));
      n.last_review_date        := s2d(p_app.get_string('last_review_date'));
      n.last_review_by          := p_app.get_string('last_review_by');
      n.sourcing                := nvl(upper(p_app.get_string('sourcing')), 'UNKNOWN');
      n.vendor_name             := p_app.get_string('vendor_name');
      n.product_version         := p_app.get_string('product_version');
      n.support_end_date        := s2d(p_app.get_string('support_end_date'));
      n.rto_minutes             := p_app.get_number('rto_minutes');
      n.rpo_minutes             := p_app.get_number('rpo_minutes');
      n.service_window          := p_app.get_string('service_window');
      n.data_sensitivity        := nvl(upper(p_app.get_string('data_sensitivity')), 'UNKNOWN');
      n.processing_register_ref := p_app.get_string('processing_register_ref');

      if n.app_code is null then
         raise_application_error(-20957, 'An application in the file has no app_code.');
      end if;

      begin
         select * into r from ref_application where app_code = n.app_code;
      exception
         when no_data_found then
            insert into ref_application (
               app_code, app_name, description, criticality, lifecycle_status,
               review_due_date, last_review_date, last_review_by,
               sourcing, vendor_name, product_version, support_end_date,
               rto_minutes, rpo_minutes, service_window, data_sensitivity,
               processing_register_ref )
            values (
               n.app_code, n.app_name, n.description, n.criticality, n.lifecycle_status,
               n.review_due_date, n.last_review_date, n.last_review_by,
               n.sourcing, n.vendor_name, n.product_version, n.support_end_date,
               n.rto_minutes, n.rpo_minutes, n.service_window, n.data_sensitivity,
               n.processing_register_ref )
            returning application_id into n.application_id;
            say('  + application creee');
            bump('APPLICATION', 'CREATED');
            return n.application_id;
      end;

      track(l_changes, 'app_name',         r.app_name,         n.app_name);
      track(l_changes, 'description',      r.description,      n.description);
      track(l_changes, 'criticality',      r.criticality,      n.criticality);
      track(l_changes, 'lifecycle_status', r.lifecycle_status, n.lifecycle_status);
      track(l_changes, 'review_due_date',  d2s(r.review_due_date),  d2s(n.review_due_date));
      track(l_changes, 'last_review_date', d2s(r.last_review_date), d2s(n.last_review_date));
      track(l_changes, 'last_review_by',   r.last_review_by,   n.last_review_by);
      track(l_changes, 'sourcing',         r.sourcing,         n.sourcing);
      track(l_changes, 'vendor_name',      r.vendor_name,      n.vendor_name);
      track(l_changes, 'product_version',  r.product_version,  n.product_version);
      track(l_changes, 'support_end_date', d2s(r.support_end_date), d2s(n.support_end_date));
      track(l_changes, 'rto_minutes',      to_char(r.rto_minutes), to_char(n.rto_minutes));
      track(l_changes, 'rpo_minutes',      to_char(r.rpo_minutes), to_char(n.rpo_minutes));
      track(l_changes, 'service_window',   r.service_window,   n.service_window);
      track(l_changes, 'data_sensitivity', r.data_sensitivity, n.data_sensitivity);
      track(l_changes, 'processing_register_ref', r.processing_register_ref, n.processing_register_ref);
      track(l_changes, 'active',           to_char(r.active),  '1');

      if l_changes is null then
         bump('APPLICATION', 'UNCHANGED');
         return r.application_id;
      end if;

      update ref_application
         set app_name                = n.app_name,
             description             = n.description,
             criticality             = n.criticality,
             lifecycle_status        = n.lifecycle_status,
             review_due_date         = n.review_due_date,
             last_review_date        = n.last_review_date,
             last_review_by          = n.last_review_by,
             sourcing                = n.sourcing,
             vendor_name             = n.vendor_name,
             product_version         = n.product_version,
             support_end_date        = n.support_end_date,
             rto_minutes             = n.rto_minutes,
             rpo_minutes             = n.rpo_minutes,
             service_window          = n.service_window,
             data_sensitivity        = n.data_sensitivity,
             processing_register_ref = n.processing_register_ref,
             active                  = 1,
             updated_by              = l_user,
             updated_date            = sysdate
       where application_id = r.application_id;
      say('  ~ application mise a jour : ' || l_changes);
      bump('APPLICATION', 'UPDATED');
      return r.application_id;
   end import_application;


   procedure import_groups ( p_app_id number, p_list json_array_t ) is
      o         json_object_t;
      n         ref_application_group%rowtype;
      g         ref_application_group%rowtype;
      l_changes varchar2(4000);
      l_user    varchar2(100 char) := audit_user;
   begin
      for j in 0 .. p_list.get_size - 1 loop
         o := treat(p_list.get(j) as json_object_t);
         n.group_type_code := upper(o.get_string('group_type_code'));
         n.group_name      := o.get_string('group_name');
         n.contact_email   := o.get_string('contact_email');
         n.ldap_dn         := o.get_string('ldap_dn');
         n.ldap_group_name := o.get_string('ldap_group_name');
         n.external_ref    := o.get_string('external_ref');
         n.note            := o.get_string('note');
         require_group_type(n.group_type_code);
         begin
            select * into g from ref_application_group
             where application_id = p_app_id
               and group_type_code = n.group_type_code
               and group_name = n.group_name;
         exception
            when no_data_found then
               insert into ref_application_group (
                  application_id, group_type_code, group_name, contact_email,
                  ldap_dn, ldap_group_name, external_ref, note )
               values (
                  p_app_id, n.group_type_code, n.group_name, n.contact_email,
                  n.ldap_dn, n.ldap_group_name, n.external_ref, n.note );
               say('  + groupe ' || n.group_type_code || ' ' || n.group_name);
               bump('GROUP', 'CREATED');
               continue;
         end;

         l_changes := null;
         track(l_changes, 'contact_email',   g.contact_email,   n.contact_email);
         track(l_changes, 'ldap_dn',         g.ldap_dn,         n.ldap_dn);
         track(l_changes, 'ldap_group_name', g.ldap_group_name, n.ldap_group_name);
         track(l_changes, 'external_ref',    g.external_ref,    n.external_ref);
         track(l_changes, 'note',            g.note,            n.note);
         track(l_changes, 'active',          to_char(g.active), '1');
         if l_changes is null then
            bump('GROUP', 'UNCHANGED');
            continue;
         end if;

         update ref_application_group
            set contact_email   = n.contact_email,
                ldap_dn         = n.ldap_dn,
                ldap_group_name = n.ldap_group_name,
                external_ref    = n.external_ref,
                note            = n.note,
                active          = 1,
                updated_by      = l_user,
                updated_date    = sysdate
          where group_id = g.group_id;
         say('  ~ groupe ' || n.group_type_code || ' ' || n.group_name || ' : ' || l_changes);
         bump('GROUP', 'UPDATED');
      end loop;
   end import_groups;


   procedure import_contacts ( p_app_id number, p_list json_array_t ) is
      o         json_object_t;
      n         ref_application_contact%rowtype;
      c         ref_application_contact%rowtype;
      l_changes varchar2(4000);
      l_user    varchar2(100 char) := audit_user;
   begin
      for j in 0 .. p_list.get_size - 1 loop
         o := treat(p_list.get(j) as json_object_t);
         n.contact_role := upper(o.get_string('contact_role'));
         n.full_name    := o.get_string('full_name');
         n.job_title    := o.get_string('job_title');
         n.email        := o.get_string('email');
         n.phone        := o.get_string('phone');
         n.ldap_login   := o.get_string('ldap_login');
         n.is_primary   := nvl(o.get_number('is_primary'), 0);
         n.note         := o.get_string('note');
         require_group_type(n.contact_role);
         begin
            select * into c from ref_application_contact
             where application_id = p_app_id
               and contact_role = n.contact_role
               and full_name = n.full_name;
         exception
            when no_data_found then
               insert into ref_application_contact (
                  application_id, contact_role, full_name, job_title,
                  email, phone, ldap_login, is_primary, note )
               values (
                  p_app_id, n.contact_role, n.full_name, n.job_title,
                  n.email, n.phone, n.ldap_login, n.is_primary, n.note );
               say('  + contact ' || n.contact_role || ' ' || n.full_name);
               bump('CONTACT', 'CREATED');
               continue;
         end;

         l_changes := null;
         track(l_changes, 'job_title',  c.job_title,  n.job_title);
         track(l_changes, 'email',      c.email,      n.email);
         track(l_changes, 'phone',      c.phone,      n.phone);
         track(l_changes, 'ldap_login', c.ldap_login, n.ldap_login);
         track(l_changes, 'is_primary', to_char(c.is_primary), to_char(n.is_primary));
         track(l_changes, 'note',       c.note,       n.note);
         track(l_changes, 'active',     to_char(c.active), '1');
         if l_changes is null then
            bump('CONTACT', 'UNCHANGED');
            continue;
         end if;

         update ref_application_contact
            set job_title    = n.job_title,
                email        = n.email,
                phone        = n.phone,
                ldap_login   = n.ldap_login,
                is_primary   = n.is_primary,
                note         = n.note,
                active       = 1,
                updated_by   = l_user,
                updated_date = sysdate
          where contact_id = c.contact_id;
         say('  ~ contact ' || n.contact_role || ' ' || n.full_name || ' : ' || l_changes);
         bump('CONTACT', 'UPDATED');
      end loop;
   end import_contacts;


   procedure import_entities ( p_app_id number, p_list json_array_t ) is
      o        json_object_t;
      e        ref_application_entity%rowtype;
      l_type   varchar2(20 char);
      l_plat   varchar2(10 char);
      l_host   varchar2(100 char);
      l_inst   varchar2(128 char);
      l_db     varchar2(128 char);
      l_note   varchar2(400 char);
      l_eid    number;
      l_why    varchar2(100);
      l_label  varchar2(1000);
   begin
      for j in 0 .. p_list.get_size - 1 loop
         o := treat(p_list.get(j) as json_object_t);
         l_type := upper(o.get_string('entity_type'));
         l_plat := upper(o.get_string('platform'));
         l_host := o.get_string('hostname');
         l_inst := o.get_string('instance_name');
         l_db   := o.get_string('db_name');
         l_note := o.get_string('note');
         l_label := l_type || ' ' || l_plat || ' ' || l_host
                    || case when l_inst is not null then '/' || l_inst end
                    || case when l_db is not null then '/' || l_db end;

         l_eid := resolve_entity(l_type, l_plat, l_host, l_inst, l_db, l_why);
         if l_eid is null then
            say('  - rattachement ignore : ' || l_label || ' (' || l_why || ')');
            bump('ENTITY', 'SKIPPED');
            continue;
         end if;

         begin
            select * into e from ref_application_entity
             where application_id = p_app_id and entity_type = l_type and entity_id = l_eid;
         exception
            when no_data_found then
               insert into ref_application_entity ( application_id, entity_type, entity_id, note )
                  values ( p_app_id, l_type, l_eid, l_note );
               say('  + rattachement ' || l_label);
               bump('ENTITY', 'CREATED');
               continue;
         end;

         if e.active = 1 and not differs(e.note, l_note) then
            bump('ENTITY', 'UNCHANGED');
            continue;
         end if;

         update ref_application_entity
            set active = 1, note = l_note
          where app_entity_id = e.app_entity_id;
         say('  ~ rattachement ' || l_label
             || case when e.active = 0 then ' : reactive' else ' : note' end);
         bump('ENTITY', 'UPDATED');
      end loop;
   end import_entities;


   procedure import_documents ( p_app_id number, p_list json_array_t ) is
      o          json_object_t;
      n          ref_application_document%rowtype;
      d          ref_application_document%rowtype;
      l_sum_file varchar2(64 char);
      l_sum_new  varchar2(64 char);
      l_n        pls_integer;
      l_changes  varchar2(4000);
      l_user     varchar2(100 char) := audit_user;
   begin
      for j in 0 .. p_list.get_size - 1 loop
         o := treat(p_list.get(j) as json_object_t);
         n.doc_kind         := nvl(upper(o.get_string('doc_kind')), 'OTHER');
         n.title            := o.get_string('title');
         n.description      := o.get_string('description');
         n.external_url     := o.get_string('external_url');
         n.file_name        := o.get_string('file_name');
         n.mime_type        := o.get_string('mime_type');
         n.review_due_date  := s2d(o.get_string('review_due_date'));
         n.last_review_date := s2d(o.get_string('last_review_date'));
         n.last_review_by   := o.get_string('last_review_by');
         n.content          := null;
         l_sum_new          := null;
         if has_value(o, 'content_base64') then
            n.content := from_base64(o.get_clob('content_base64'));
            l_sum_new := pkg_dbinv_application.fingerprint(n.content);
         end if;
         l_sum_file := lower(o.get_string('checksum_sha256'));

         -- The file must arrive as it left: the checksum computed by the source
         -- must match the one of the decoded bytes.
         if l_sum_new is not null and l_sum_file is not null and l_sum_new <> l_sum_file then
            raise_application_error(-20958,
               'Document "' || n.title || '": the content does not match its checksum; '
               || 'the file is damaged.');
         end if;

         select count(*) into l_n from ref_application_document
          where application_id = p_app_id and title = n.title;

         if l_n > 1 then
            say('  - document ignore : "' || n.title || '" (plusieurs documents de ce titre dans la cible)');
            bump('DOCUMENT', 'SKIPPED');
            continue;
         end if;

         if l_n = 0 then
            insert into ref_application_document (
               application_id, doc_kind, title, description, external_url,
               file_name, mime_type, content,
               review_due_date, last_review_date, last_review_by )
            values (
               p_app_id, n.doc_kind, n.title, n.description, n.external_url,
               n.file_name, n.mime_type, n.content,
               n.review_due_date, n.last_review_date, n.last_review_by );
            say('  + document "' || n.title || '"'
                || case when n.content is not null
                        then ' (' || dbms_lob.getlength(n.content) || ' octets)' end);
            bump('DOCUMENT', 'CREATED');
            continue;
         end if;

         select * into d from ref_application_document
          where application_id = p_app_id and title = n.title;

         l_changes := null;
         track(l_changes, 'doc_kind',         d.doc_kind,         n.doc_kind);
         track(l_changes, 'description',      d.description,      n.description);
         track(l_changes, 'external_url',     d.external_url,     n.external_url);
         track(l_changes, 'file_name',        d.file_name,        n.file_name);
         track(l_changes, 'mime_type',        d.mime_type,        n.mime_type);
         track(l_changes, 'content',          d.checksum_sha256,  l_sum_new);
         track(l_changes, 'review_due_date',  d2s(d.review_due_date),  d2s(n.review_due_date));
         track(l_changes, 'last_review_date', d2s(d.last_review_date), d2s(n.last_review_date));
         track(l_changes, 'last_review_by',   d.last_review_by,   n.last_review_by);
         track(l_changes, 'active',           to_char(d.active),  '1');
         if l_changes is null then
            bump('DOCUMENT', 'UNCHANGED');
            continue;
         end if;

         update ref_application_document
            set doc_kind         = n.doc_kind,
                description      = n.description,
                external_url     = n.external_url,
                file_name        = n.file_name,
                mime_type        = n.mime_type,
                content          = n.content,
                review_due_date  = n.review_due_date,
                last_review_date = n.last_review_date,
                last_review_by   = n.last_review_by,
                active           = 1,
                updated_by       = l_user,
                updated_date     = sysdate
          where document_id = d.document_id;
         say('  ~ document "' || n.title || '" : ' || l_changes);
         bump('DOCUMENT', 'UPDATED');
      end loop;
   end import_documents;


   procedure import_sources ( p_app_id number, p_list json_array_t ) is
      o         json_object_t;
      n         ref_application_source%rowtype;
      s         ref_application_source%rowtype;
      l_changes varchar2(4000);
   begin
      for j in 0 .. p_list.get_size - 1 loop
         o := treat(p_list.get(j) as json_object_t);
         n.source_kind := nvl(upper(o.get_string('source_kind')), 'GIT');
         n.repo_url    := o.get_string('repo_url');
         n.branch      := o.get_string('branch');
         n.note        := o.get_string('note');
         begin
            -- No unique key on sources: an active row wins over a removed one.
            select * into s from ref_application_source
             where application_id = p_app_id and repo_url = n.repo_url
             order by active desc, source_id
             fetch first 1 row only;
         exception
            when no_data_found then
               insert into ref_application_source ( application_id, source_kind, repo_url, branch, note )
                  values ( p_app_id, n.source_kind, n.repo_url, n.branch, n.note );
               say('  + source ' || n.repo_url);
               bump('SOURCE', 'CREATED');
               continue;
         end;

         l_changes := null;
         track(l_changes, 'source_kind', s.source_kind, n.source_kind);
         track(l_changes, 'branch',      s.branch,      n.branch);
         track(l_changes, 'note',        s.note,        n.note);
         track(l_changes, 'active',      to_char(s.active), '1');
         if l_changes is null then
            bump('SOURCE', 'UNCHANGED');
            continue;
         end if;

         update ref_application_source
            set source_kind = n.source_kind,
                branch      = n.branch,
                note        = n.note,
                active      = 1
          where source_id = s.source_id;
         say('  ~ source ' || n.repo_url || ' : ' || l_changes);
         bump('SOURCE', 'UPDATED');
      end loop;
   end import_sources;


   -- One application and everything under it. Returns false on failure, after
   -- rolling back what this application had written.
   function import_one ( p_app json_object_t ) return boolean is
      l_id number;
   begin
      say('APPLICATION ' || upper(trim(p_app.get_string('app_code'))));
      savepoint xfer_app;
      l_id := import_application(p_app);
      import_groups(l_id,    array_of(p_app, 'groups'));
      import_contacts(l_id,  array_of(p_app, 'contacts'));
      import_entities(l_id,  array_of(p_app, 'entities'));
      import_documents(l_id, array_of(p_app, 'documents'));
      import_sources(l_id,   array_of(p_app, 'sources'));
      return true;
   exception
      when others then
         rollback to xfer_app;
         say('  ! ERREUR : ' || sqlerrm);
         return false;
   end import_one;


   procedure import_json ( p_doc clob, p_apply number default 0, p_file_name varchar2 default null ) is
      l_root   json_object_t;
      l_src    json_object_t;
      l_doms   json_object_t;
      l_keys   json_key_list;
      l_apps   json_array_t;
      l_failed pls_integer := 0;
      l_source varchar2(200);
   begin
      g_counts.delete;

      begin
         l_root := json_object_t.parse(p_doc);
      exception
         when others then
            raise_application_error(-20951, 'The file is not a JSON document: ' || sqlerrm);
      end;

      if differs(l_root.get_string('format'), c_format) then
         raise_application_error(-20952,
            'Not a dbInventory transfer file (format "' || l_root.get_string('format') || '").');
      end if;
      if nvl(l_root.get_number('version'), 0) > c_version then
         raise_application_error(-20953,
            'File format version ' || l_root.get_number('version') || ' is newer than this '
            || 'package (' || c_version || '). Deploy the newer V__015 here first.');
      end if;

      l_src    := case when has_value(l_root, 'source') then l_root.get_object('source') else json_object_t() end;
      l_source := l_src.get_string('service');
      l_doms   := case when has_value(l_root, 'domains') then l_root.get_object('domains') else json_object_t() end;

      l_keys := l_doms.get_keys;
      for k in 1 .. l_keys.count loop
         if l_keys(k) not in ( 'applications' ) then
            raise_application_error(-20954,
               'Unknown domain "' || l_keys(k) || '" in the file: refused rather than half-imported.');
         end if;
      end loop;

      say('Fichier : ' || nvl(p_file_name, '(document)'));
      say('Exporte de ' || nvl(l_source, '?') || ' le ' || l_root.get_string('exported_at'));
      say('Cible   : ' || sys_context('USERENV', 'SERVICE_NAME'));
      say('Mode    : ' || case when p_apply = 1 then 'IMPORT REEL'
                               else 'SIMULATION (rien ne sera ecrit)' end);
      if upper(l_source) = upper(sys_context('USERENV', 'SERVICE_NAME')) then
         say('Attention : la source et la cible sont la meme base.');
      end if;
      say('');

      savepoint xfer_start;
      pkg_dbinv_application.set_reason(substr(
         'Import ' || nvl(p_file_name, 'transfer file') || ' from ' || nvl(l_source, '?')
         || ' exported ' || l_root.get_string('exported_at'), 1, 1000));

      l_apps := array_of(l_doms, 'applications');
      for i in 0 .. l_apps.get_size - 1 loop
         if not import_one(treat(l_apps.get(i) as json_object_t)) then
            l_failed := l_failed + 1;
         end if;
      end loop;

      pkg_dbinv_application.set_reason(null);

      say('');
      say('Bilan           crees  mis a jour  inchanges  ignores');
      for i in 1 .. c_items.count loop
         say('  ' || rpad(lower(c_items(i)), 12)
             || lpad(counter(c_items(i), 'CREATED'), 7)
             || lpad(counter(c_items(i), 'UPDATED'), 12)
             || lpad(counter(c_items(i), 'UNCHANGED'), 11)
             || lpad(counter(c_items(i), 'SKIPPED'), 9));
      end loop;
      say('');

      if l_failed > 0 then
         rollback to xfer_start;
         raise_application_error(-20955,
            l_failed || ' application(s) en erreur (voir ci-dessus) : rien n''a ete ecrit.');
      elsif p_apply = 1 then
         commit;
         say('Import valide (commit).');
      else
         rollback to xfer_start;
         say('SIMULATION terminee : rien n''a ete ecrit. Relancer avec --apply pour importer.');
      end if;
   exception
      when others then
         pkg_dbinv_application.set_reason(null);
         raise;
   end import_json;


   procedure import_begin is
   begin
      if g_buffer is not null and dbms_lob.istemporary(g_buffer) = 1 then
         dbms_lob.freetemporary(g_buffer);
      end if;
      dbms_lob.createtemporary(g_buffer, true);
   end import_begin;


   procedure import_chunk ( p_base64 varchar2 ) is
      l_raw raw(32767);
   begin
      if g_buffer is null then
         raise_application_error(-20959, 'import_chunk called before import_begin.');
      end if;
      if trim(p_base64) is null then
         return;
      end if;
      l_raw := utl_encode.base64_decode(utl_raw.cast_to_raw(trim(p_base64)));
      dbms_lob.writeappend(g_buffer, utl_raw.length(l_raw), l_raw);
   end import_chunk;


   procedure import_run ( p_apply number default 0, p_file_name varchar2 default null ) is
      l_doc clob;
   begin
      if g_buffer is null or dbms_lob.getlength(g_buffer) = 0 then
         raise_application_error(-20959, 'Nothing received: import_begin / import_chunk first.');
      end if;
      l_doc := utf8_clob(g_buffer);
      dbms_lob.freetemporary(g_buffer);
      g_buffer := null;
      import_json(l_doc, p_apply, p_file_name);
   end import_run;

end pkg_dbinv_transfer;
/
