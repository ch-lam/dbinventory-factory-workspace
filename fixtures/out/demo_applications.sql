-- Registre applicatif du jeu de demonstration.
-- Genere par fixtures/lib/emit_applications.mjs -- ne pas editer a la main.
--
-- Tout passe par pkg_dbinv_application : ce script exerce l'API que l'ecran
-- utilise, et non un chemin de chargement paralle qui ne prouverait rien.
whenever sqlerror exit failure rollback
set define off
set serveroutput on
declare
   l_app      number;
   l_dummy    number;
   l_doc      number;
   l_entity   number;
   l_existing pls_integer;
   l_apps     pls_integer := 0;
   l_links    pls_integer := 0;
begin
   select count(*) into l_existing from ref_application
    where app_code in ( 'DPI', 'SIL', 'PACS', 'PHARMA', 'URG', 'GAP', 'FACT', 'PAIE', 'GED', 'BIOMED' );

   if l_existing > 0 then
      dbms_output.put_line('Registre applicatif : deja en place (' || l_existing
         || ' application(s) de demonstration). Rien fait.');
      dbms_output.put_line('  Le registre se saisit et ne se collecte pas : un rechargement');
      dbms_output.put_line('  des fixtures n''ecrase pas une saisie. Pour le regenerer,');
      dbms_output.put_line('  reinstaller le schema (X_001_cleanup_and_reinstall_all.sql).');
   else

   -- DPI : Dossier Patient Informatise
   l_app := pkg_dbinv_application.create_application(
      p_app_code         => 'DPI',
      p_app_name         => 'Dossier Patient Informatise',
      p_description      => 'Dossier Patient Informatise, progiciel',
      p_criticality      => 'CRITICAL',
      p_lifecycle_status => 'ACTIVE' );
   l_apps := l_apps + 1;
   pkg_dbinv_application.set_profile(
      p_application_id   => l_app,
      p_sourcing         => 'PACKAGE',
      p_vendor_name      => 'Meridian Health Systems',
      p_product_version  => '8.4.2',
      p_support_end_date => date '2028-06-30',
      p_rto_minutes      => 60,
      p_rpo_minutes      => 5,
      p_service_window   => '24/7',
      p_data_sensitivity => 'HEALTH',
      p_register_ref     => 'RT-2019-004',
      p_note             => 'saisi avec le jeu de demonstration' );
   update ref_application set last_review_date = trunc(sysdate) - 60, last_review_by = 'demo', review_due_date = add_months(trunc(sysdate), 10) where application_id = l_app;
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'ADMIN',
      p_group_name      => 'Equipe DPI - exploitation',
      p_contact_email   => 'dl-dpi-exploit@ghm.lan',
      p_ldap_group_name => 'GG_DPI_EXPLOIT',
      p_external_ref    => null );
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'BUSINESS',
      p_group_name      => 'Referents metier DPI',
      p_contact_email   => 'dl-dpi-metier@ghm.lan',
      p_ldap_group_name => 'GG_DPI_METIER',
      p_external_ref    => null );
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'VENDOR',
      p_group_name      => 'Meridian Health Systems - support contractuel',
      p_contact_email   => null,
      p_ldap_group_name => null,
      p_external_ref    => 'CONTRAT-DPI' );
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'SECURITY',
      p_group_name      => 'Securite des systemes d''information',
      p_contact_email   => 'rssi@ghm.lan',
      p_ldap_group_name => 'GG_RSSI',
      p_external_ref    => null );
   l_dummy := pkg_dbinv_application.add_contact(
      p_application_id => l_app,
      p_contact_role   => 'ADMIN',
      p_full_name      => 'Anne Vermeulen',
      p_job_title      => 'Administratrice de bases de donnees',
      p_email          => 'avermeulen@ghm.lan',
      p_phone          => '+352 4411 2201',
      p_ldap_login     => 'avermeulen',
      p_is_primary     => 1 );
   l_dummy := pkg_dbinv_application.add_contact(
      p_application_id => l_app,
      p_contact_role   => 'BUSINESS',
      p_full_name      => 'Karim Benali',
      p_job_title      => 'Administrateur systeme',
      p_email          => 'kbenali@ghm.lan',
      p_phone          => '+352 4411 2202',
      p_ldap_login     => 'kbenali',
      p_is_primary     => 0 );
   l_doc := pkg_dbinv_application.add_document(
      p_application_id => l_app,
      p_title          => 'Procedure d''exploitation - Dossier Patient Informatise',
      p_doc_kind       => 'RUNBOOK',
      p_external_url   => 'https://wiki.example.invalid/dpi/current',
      p_review_months  => 12 );
   update ref_application_document set last_review_date = trunc(sysdate) - 30, last_review_by = 'demo' where document_id = l_doc;
   l_doc := pkg_dbinv_application.add_document(
      p_application_id => l_app,
      p_title          => 'Plan de reprise - Dossier Patient Informatise',
      p_doc_kind       => 'PROCEDURE',
      p_external_url   => 'https://wiki.example.invalid/dpi/due-soon',
      p_review_months  => 12 );
   update ref_application_document set last_review_date = trunc(sysdate) - 330, last_review_by = 'demo', review_due_date = trunc(sysdate) + 20 where document_id = l_doc;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'ORACLE'
      and lower(h.hostname) = lower('oradb-tst-13')
      and i.instance_name = 'DOSSIET';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'ORACLE instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-02.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-02/SQLEXPRESS';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-17.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-17';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-20.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-20';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-24.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-24/FINANCE';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-26.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-26';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-39.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-39';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-03.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-03/SQLEXPRESS';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-08.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-08/SQLEXPRESS';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'POSTGRES'
      and lower(h.hostname) = lower('pgsrv-tst-01.ghm.lan')
      and i.instance_name = 'pgsrv-tst-01.ghm.lan';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'POSTGRES instance' );
   l_links := l_links + 1;

   -- SIL : Systeme d'Information du Laboratoire
   l_app := pkg_dbinv_application.create_application(
      p_app_code         => 'SIL',
      p_app_name         => 'Systeme d''Information du Laboratoire',
      p_description      => 'Systeme d''Information du Laboratoire, progiciel',
      p_criticality      => 'CRITICAL',
      p_lifecycle_status => 'ACTIVE' );
   l_apps := l_apps + 1;
   pkg_dbinv_application.set_profile(
      p_application_id   => l_app,
      p_sourcing         => 'PACKAGE',
      p_vendor_name      => 'Nordlab AG',
      p_product_version  => '12.1',
      p_support_end_date => date '2027-03-31',
      p_rto_minutes      => 120,
      p_rpo_minutes      => 15,
      p_service_window   => '24/7',
      p_data_sensitivity => 'HEALTH',
      p_register_ref     => 'RT-2019-011',
      p_note             => 'saisi avec le jeu de demonstration' );
   update ref_application set last_review_date = trunc(sysdate) - 400, last_review_by = 'demo', review_due_date = trunc(sysdate) - 35 where application_id = l_app;
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'ADMIN',
      p_group_name      => 'Equipe SIL - exploitation',
      p_contact_email   => 'dl-sil-exploit@ghm.lan',
      p_ldap_group_name => 'GG_SIL_EXPLOIT',
      p_external_ref    => null );
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'BUSINESS',
      p_group_name      => 'Referents metier SIL',
      p_contact_email   => 'dl-sil-metier@ghm.lan',
      p_ldap_group_name => 'GG_SIL_METIER',
      p_external_ref    => null );
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'VENDOR',
      p_group_name      => 'Nordlab AG - support contractuel',
      p_contact_email   => null,
      p_ldap_group_name => null,
      p_external_ref    => 'CONTRAT-SIL' );
   l_dummy := pkg_dbinv_application.add_contact(
      p_application_id => l_app,
      p_contact_role   => 'ADMIN',
      p_full_name      => 'Sofia Marchetti',
      p_job_title      => 'Responsable applicative',
      p_email          => 'smarchetti@ghm.lan',
      p_phone          => '+352 4411 2203',
      p_ldap_login     => 'smarchetti',
      p_is_primary     => 1 );
   l_dummy := pkg_dbinv_application.add_contact(
      p_application_id => l_app,
      p_contact_role   => 'BUSINESS',
      p_full_name      => 'Tom Jacobs',
      p_job_title      => 'Cadre de sante referent',
      p_email          => 'tjacobs@ghm.lan',
      p_phone          => '+352 4411 2204',
      p_ldap_login     => 'tjacobs',
      p_is_primary     => 0 );
   l_doc := pkg_dbinv_application.add_document(
      p_application_id => l_app,
      p_title          => 'Contrat de maintenance - Systeme d''Information du Laboratoire',
      p_doc_kind       => 'CONTRACT',
      p_external_url   => 'https://wiki.example.invalid/sil/overdue',
      p_review_months  => 12 );
   update ref_application_document set last_review_date = trunc(sysdate) - 400, last_review_by = 'demo', review_due_date = trunc(sysdate) - 35 where document_id = l_doc;
   l_doc := pkg_dbinv_application.add_document(
      p_application_id => l_app,
      p_title          => 'Schema d''architecture - Systeme d''Information du Laboratoire',
      p_doc_kind       => 'DIAGRAM',
      p_external_url   => 'https://wiki.example.invalid/sil/never',
      p_review_months  => 12 );
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-20.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-20';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-dev-22.ghm.lan')
      and i.instance_name = 'SQLSRV-DEV-22';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-31.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-31/FINANCE';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-37.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-37';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-39.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-39';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-45.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-45';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-52.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-52';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;

   -- PACS : Archivage et diffusion d'images
   l_app := pkg_dbinv_application.create_application(
      p_app_code         => 'PACS',
      p_app_name         => 'Archivage et diffusion d''images',
      p_description      => 'Archivage et diffusion d''images, progiciel',
      p_criticality      => 'CRITICAL',
      p_lifecycle_status => 'ACTIVE' );
   l_apps := l_apps + 1;
   pkg_dbinv_application.set_profile(
      p_application_id   => l_app,
      p_sourcing         => 'PACKAGE',
      p_vendor_name      => 'Visiora Imaging',
      p_product_version  => '6.9.1',
      p_support_end_date => date '2026-12-31',
      p_rto_minutes      => 240,
      p_rpo_minutes      => 60,
      p_service_window   => '24/7',
      p_data_sensitivity => 'HEALTH',
      p_register_ref     => 'RT-2020-002',
      p_note             => 'saisi avec le jeu de demonstration' );
   update ref_application set last_review_date = null, last_review_by = null, review_due_date = add_months(trunc(sysdate), 3) where application_id = l_app;
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'ADMIN',
      p_group_name      => 'Equipe PACS - exploitation',
      p_contact_email   => 'dl-pacs-exploit@ghm.lan',
      p_ldap_group_name => 'GG_PACS_EXPLOIT',
      p_external_ref    => null );
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'VENDOR',
      p_group_name      => 'Visiora Imaging - support contractuel',
      p_contact_email   => null,
      p_ldap_group_name => null,
      p_external_ref    => 'CONTRAT-PACS' );
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'SECURITY',
      p_group_name      => 'Securite des systemes d''information',
      p_contact_email   => 'rssi@ghm.lan',
      p_ldap_group_name => 'GG_RSSI',
      p_external_ref    => null );
   l_dummy := pkg_dbinv_application.add_contact(
      p_application_id => l_app,
      p_contact_role   => 'ADMIN',
      p_full_name      => 'Lena Dupont',
      p_job_title      => 'Cheffe de projet SI',
      p_email          => 'ldupont@ghm.lan',
      p_phone          => '+352 4411 2205',
      p_ldap_login     => 'ldupont',
      p_is_primary     => 1 );
   l_dummy := pkg_dbinv_application.add_contact(
      p_application_id => l_app,
      p_contact_role   => 'VENDOR',
      p_full_name      => 'Pierre Roth',
      p_job_title      => 'Ingenieur d''exploitation',
      p_email          => 'proth@ghm.lan',
      p_phone          => '+352 4411 2206',
      p_ldap_login     => 'proth',
      p_is_primary     => 0 );
   l_doc := pkg_dbinv_application.add_document(
      p_application_id => l_app,
      p_title          => 'Procedure d''exploitation - Archivage et diffusion d''images',
      p_doc_kind       => 'RUNBOOK',
      p_external_url   => 'https://wiki.example.invalid/pacs/current',
      p_review_months  => 12 );
   update ref_application_document set last_review_date = trunc(sysdate) - 30, last_review_by = 'demo' where document_id = l_doc;
   l_doc := pkg_dbinv_application.add_document(
      p_application_id => l_app,
      p_title          => 'Notes de reprise - Archivage et diffusion d''images',
      p_doc_kind       => 'OTHER',
      p_external_url   => 'https://wiki.example.invalid/pacs/unplanned',
      p_review_months  => null );
   select h.host_id into l_entity
     from dim_host h
    where h.platform = 'ORACLE'
      and lower(h.hostname) = lower('oradb-prd-07');
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'HOST',
      p_entity_id      => l_entity,
      p_note           => 'ORACLE host' );
   l_links := l_links + 1;
   select h.host_id into l_entity
     from dim_host h
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-uat-07.ghm.lan');
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'HOST',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL host' );
   l_links := l_links + 1;
   select h.host_id into l_entity
     from dim_host h
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-dev-15.ghm.lan');
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'HOST',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL host' );
   l_links := l_links + 1;
   select h.host_id into l_entity
     from dim_host h
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-16.ghm.lan');
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'HOST',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL host' );
   l_links := l_links + 1;
   select h.host_id into l_entity
     from dim_host h
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-26.ghm.lan');
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'HOST',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL host' );
   l_links := l_links + 1;
   select h.host_id into l_entity
     from dim_host h
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-dev-30.ghm.lan');
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'HOST',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL host' );
   l_links := l_links + 1;
   select h.host_id into l_entity
     from dim_host h
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-dev-33.ghm.lan');
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'HOST',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL host' );
   l_links := l_links + 1;
   select h.host_id into l_entity
     from dim_host h
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-41.ghm.lan');
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'HOST',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL host' );
   l_links := l_links + 1;
   select h.host_id into l_entity
     from dim_host h
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-dev-42.ghm.lan');
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'HOST',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL host' );
   l_links := l_links + 1;
   select h.host_id into l_entity
     from dim_host h
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-uat-50.ghm.lan');
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'HOST',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL host' );
   l_links := l_links + 1;
   select h.host_id into l_entity
     from dim_host h
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-05.ghm.lan');
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'HOST',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL host' );
   l_links := l_links + 1;

   -- PHARMA : Circuit du medicament
   l_app := pkg_dbinv_application.create_application(
      p_app_code         => 'PHARMA',
      p_app_name         => 'Circuit du medicament',
      p_description      => 'Circuit du medicament, progiciel',
      p_criticality      => 'CRITICAL',
      p_lifecycle_status => 'ACTIVE' );
   l_apps := l_apps + 1;
   pkg_dbinv_application.set_profile(
      p_application_id   => l_app,
      p_sourcing         => 'PACKAGE',
      p_vendor_name      => 'Meridian Health Systems',
      p_product_version  => '8.4.2',
      p_support_end_date => date '2028-06-30',
      p_rto_minutes      => 60,
      p_rpo_minutes      => 5,
      p_service_window   => '24/7',
      p_data_sensitivity => 'HEALTH',
      p_register_ref     => 'RT-2019-007',
      p_note             => 'saisi avec le jeu de demonstration' );
   update ref_application set last_review_date = trunc(sysdate) - 60, last_review_by = 'demo', review_due_date = add_months(trunc(sysdate), 10) where application_id = l_app;
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'ADMIN',
      p_group_name      => 'Equipe PHARMA - exploitation',
      p_contact_email   => 'dl-pharma-exploit@ghm.lan',
      p_ldap_group_name => 'GG_PHARMA_EXPLOIT',
      p_external_ref    => null );
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'BUSINESS',
      p_group_name      => 'Referents metier PHARMA',
      p_contact_email   => 'dl-pharma-metier@ghm.lan',
      p_ldap_group_name => 'GG_PHARMA_METIER',
      p_external_ref    => null );
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'SUPPORT',
      p_group_name      => 'Centre de services',
      p_contact_email   => 'servicedesk@ghm.lan',
      p_ldap_group_name => 'GG_SERVICEDESK',
      p_external_ref    => null );
   l_dummy := pkg_dbinv_application.add_contact(
      p_application_id => l_app,
      p_contact_role   => 'ADMIN',
      p_full_name      => 'Anne Vermeulen',
      p_job_title      => 'Administratrice de bases de donnees',
      p_email          => 'avermeulen@ghm.lan',
      p_phone          => '+352 4411 2201',
      p_ldap_login     => 'avermeulen',
      p_is_primary     => 1 );
   l_dummy := pkg_dbinv_application.add_contact(
      p_application_id => l_app,
      p_contact_role   => 'BUSINESS',
      p_full_name      => 'Karim Benali',
      p_job_title      => 'Administrateur systeme',
      p_email          => 'kbenali@ghm.lan',
      p_phone          => '+352 4411 2202',
      p_ldap_login     => 'kbenali',
      p_is_primary     => 0 );
   l_doc := pkg_dbinv_application.add_document(
      p_application_id => l_app,
      p_title          => 'Procedure d''exploitation - Circuit du medicament',
      p_doc_kind       => 'RUNBOOK',
      p_external_url   => 'https://wiki.example.invalid/pharma/current',
      p_review_months  => 12 );
   update ref_application_document set last_review_date = trunc(sysdate) - 30, last_review_by = 'demo' where document_id = l_doc;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'ORACLE'
      and lower(h.hostname) = lower('oradb-prd-02')
      and i.instance_name = 'PHARMAP';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'ORACLE instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-08.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-08';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-10.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-10';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-dev-30.ghm.lan')
      and i.instance_name = 'SQLSRV-DEV-30';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-32.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-32';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-34.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-34/FINANCE';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-37.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-37';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-43.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-43';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-44.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-44';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-dev-47.ghm.lan')
      and i.instance_name = 'SQLSRV-DEV-47/METIER';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;

   -- URG : Dossier des urgences
   l_app := pkg_dbinv_application.create_application(
      p_app_code         => 'URG',
      p_app_name         => 'Dossier des urgences',
      p_description      => 'Dossier des urgences, developpe en interne',
      p_criticality      => 'CRITICAL',
      p_lifecycle_status => 'ACTIVE' );
   l_apps := l_apps + 1;
   pkg_dbinv_application.set_profile(
      p_application_id   => l_app,
      p_sourcing         => 'INTERNAL',
      p_vendor_name      => null,
      p_product_version  => '2026.2',
      p_support_end_date => null,
      p_rto_minutes      => 30,
      p_rpo_minutes      => 5,
      p_service_window   => '24/7',
      p_data_sensitivity => 'HEALTH',
      p_register_ref     => 'RT-2021-001',
      p_note             => 'saisi avec le jeu de demonstration' );
   update ref_application set last_review_date = trunc(sysdate) - 60, last_review_by = 'demo', review_due_date = add_months(trunc(sysdate), 10) where application_id = l_app;
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'ADMIN',
      p_group_name      => 'Equipe URG - exploitation',
      p_contact_email   => 'dl-urg-exploit@ghm.lan',
      p_ldap_group_name => 'GG_URG_EXPLOIT',
      p_external_ref    => null );
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'BUSINESS',
      p_group_name      => 'Referents metier URG',
      p_contact_email   => 'dl-urg-metier@ghm.lan',
      p_ldap_group_name => 'GG_URG_METIER',
      p_external_ref    => null );
   l_dummy := pkg_dbinv_application.add_contact(
      p_application_id => l_app,
      p_contact_role   => 'ADMIN',
      p_full_name      => 'Sofia Marchetti',
      p_job_title      => 'Responsable applicative',
      p_email          => 'smarchetti@ghm.lan',
      p_phone          => '+352 4411 2203',
      p_ldap_login     => 'smarchetti',
      p_is_primary     => 1 );
   l_dummy := pkg_dbinv_application.add_contact(
      p_application_id => l_app,
      p_contact_role   => 'BUSINESS',
      p_full_name      => 'Tom Jacobs',
      p_job_title      => 'Cadre de sante referent',
      p_email          => 'tjacobs@ghm.lan',
      p_phone          => '+352 4411 2204',
      p_ldap_login     => 'tjacobs',
      p_is_primary     => 0 );
   l_doc := pkg_dbinv_application.add_document(
      p_application_id => l_app,
      p_title          => 'Plan de reprise - Dossier des urgences',
      p_doc_kind       => 'PROCEDURE',
      p_external_url   => 'https://wiki.example.invalid/urg/due-soon',
      p_review_months  => 12 );
   update ref_application_document set last_review_date = trunc(sysdate) - 330, last_review_by = 'demo', review_due_date = trunc(sysdate) + 20 where document_id = l_doc;
   l_dummy := pkg_dbinv_application.add_source(
      p_application_id => l_app,
      p_repo_url       => 'https://git.example.invalid/si/urg.git',
      p_source_kind    => 'GIT',
      p_branch         => 'production' );
   l_dummy := pkg_dbinv_application.add_source(
      p_application_id => l_app,
      p_repo_url       => 'https://git.example.invalid/si/urg-batch.git',
      p_source_kind    => 'GIT',
      p_branch         => 'main' );
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'ORACLE'
      and lower(h.hostname) = lower('oradb-dev-12')
      and i.instance_name = 'URGENCD'
      and db.db_name = 'URGENCD';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'ORACLE database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-dev-14.ghm.lan')
      and i.instance_name = 'SQLSRV-DEV-14'
      and db.db_name = 'URGENCE_DEV';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-16.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-16'
      and db.db_name = 'URGENCE_PRD';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-dev-23.ghm.lan')
      and i.instance_name = 'SQLSRV-DEV-23/APPLI'
      and db.db_name = 'URGENCE_DEV';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-dev-33.ghm.lan')
      and i.instance_name = 'SQLSRV-DEV-33'
      and db.db_name = 'URGENCE_DEV';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-dev-42.ghm.lan')
      and i.instance_name = 'SQLSRV-DEV-42/APPLI'
      and db.db_name = 'URGENCE_DEV';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-48.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-48'
      and db.db_name = 'URGENCE_PRD';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-09.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-09/SQLEXPRESS'
      and db.db_name = 'URGENCE_PRD';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;

   -- GAP : Gestion administrative du patient
   l_app := pkg_dbinv_application.create_application(
      p_app_code         => 'GAP',
      p_app_name         => 'Gestion administrative du patient',
      p_description      => 'Gestion administrative du patient, progiciel',
      p_criticality      => 'HIGH',
      p_lifecycle_status => 'ACTIVE' );
   l_apps := l_apps + 1;
   pkg_dbinv_application.set_profile(
      p_application_id   => l_app,
      p_sourcing         => 'PACKAGE',
      p_vendor_name      => 'Meridian Health Systems',
      p_product_version  => '7.8.0',
      p_support_end_date => date '2027-09-30',
      p_rto_minutes      => 240,
      p_rpo_minutes      => 30,
      p_service_window   => '24/7',
      p_data_sensitivity => 'PERSONAL',
      p_register_ref     => 'RT-2019-001',
      p_note             => 'saisi avec le jeu de demonstration' );
   update ref_application set last_review_date = trunc(sysdate) - 60, last_review_by = 'demo', review_due_date = add_months(trunc(sysdate), 10) where application_id = l_app;
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'ADMIN',
      p_group_name      => 'Equipe GAP - exploitation',
      p_contact_email   => 'dl-gap-exploit@ghm.lan',
      p_ldap_group_name => 'GG_GAP_EXPLOIT',
      p_external_ref    => null );
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'BUSINESS',
      p_group_name      => 'Referents metier GAP',
      p_contact_email   => 'dl-gap-metier@ghm.lan',
      p_ldap_group_name => 'GG_GAP_METIER',
      p_external_ref    => null );
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'SUPPORT',
      p_group_name      => 'Centre de services',
      p_contact_email   => 'servicedesk@ghm.lan',
      p_ldap_group_name => 'GG_SERVICEDESK',
      p_external_ref    => null );
   l_dummy := pkg_dbinv_application.add_contact(
      p_application_id => l_app,
      p_contact_role   => 'ADMIN',
      p_full_name      => 'Lena Dupont',
      p_job_title      => 'Cheffe de projet SI',
      p_email          => 'ldupont@ghm.lan',
      p_phone          => '+352 4411 2205',
      p_ldap_login     => 'ldupont',
      p_is_primary     => 1 );
   l_dummy := pkg_dbinv_application.add_contact(
      p_application_id => l_app,
      p_contact_role   => 'BUSINESS',
      p_full_name      => 'Pierre Roth',
      p_job_title      => 'Ingenieur d''exploitation',
      p_email          => 'proth@ghm.lan',
      p_phone          => '+352 4411 2206',
      p_ldap_login     => 'proth',
      p_is_primary     => 0 );
   l_doc := pkg_dbinv_application.add_document(
      p_application_id => l_app,
      p_title          => 'Procedure d''exploitation - Gestion administrative du patient',
      p_doc_kind       => 'RUNBOOK',
      p_external_url   => 'https://wiki.example.invalid/gap/current',
      p_review_months  => 12 );
   update ref_application_document set last_review_date = trunc(sysdate) - 30, last_review_by = 'demo' where document_id = l_doc;
   l_doc := pkg_dbinv_application.add_document(
      p_application_id => l_app,
      p_title          => 'Contrat de maintenance - Gestion administrative du patient',
      p_doc_kind       => 'CONTRACT',
      p_external_url   => 'https://wiki.example.invalid/gap/overdue',
      p_review_months  => 12 );
   update ref_application_document set last_review_date = trunc(sysdate) - 400, last_review_by = 'demo', review_due_date = trunc(sysdate) - 35 where document_id = l_doc;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'ORACLE'
      and lower(h.hostname) = lower('oradb-uat-19')
      and i.instance_name = 'ADMISU';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'ORACLE instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-tst-01.ghm.lan')
      and i.instance_name = 'SQLSRV-TST-01';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-02.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-02/SQLEXPRESS';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-16.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-16';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-dev-19.ghm.lan')
      and i.instance_name = 'SQLSRV-DEV-19';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-52.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-52';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-uat-54.ghm.lan')
      and i.instance_name = 'SQLSRV-UAT-54';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-55.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-55';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-04.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-04/GESTION';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-08.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-08/SQLEXPRESS';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;

   -- FACT : Facturation et recouvrement
   l_app := pkg_dbinv_application.create_application(
      p_app_code         => 'FACT',
      p_app_name         => 'Facturation et recouvrement',
      p_description      => 'Facturation et recouvrement, progiciel',
      p_criticality      => 'HIGH',
      p_lifecycle_status => 'ACTIVE' );
   l_apps := l_apps + 1;
   pkg_dbinv_application.set_profile(
      p_application_id   => l_app,
      p_sourcing         => 'PACKAGE',
      p_vendor_name      => 'Aldeb Finance',
      p_product_version  => 'R14',
      p_support_end_date => date '2029-12-31',
      p_rto_minutes      => 480,
      p_rpo_minutes      => 60,
      p_service_window   => '7h-20h ouvres',
      p_data_sensitivity => 'PERSONAL',
      p_register_ref     => 'RT-2020-009',
      p_note             => 'saisi avec le jeu de demonstration' );
   update ref_application set last_review_date = null, last_review_by = null, review_due_date = null where application_id = l_app;
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'ADMIN',
      p_group_name      => 'Equipe FACT - exploitation',
      p_contact_email   => 'dl-fact-exploit@ghm.lan',
      p_ldap_group_name => 'GG_FACT_EXPLOIT',
      p_external_ref    => null );
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'BUSINESS',
      p_group_name      => 'Referents metier FACT',
      p_contact_email   => 'dl-fact-metier@ghm.lan',
      p_ldap_group_name => 'GG_FACT_METIER',
      p_external_ref    => null );
   l_dummy := pkg_dbinv_application.add_contact(
      p_application_id => l_app,
      p_contact_role   => 'ADMIN',
      p_full_name      => 'Anne Vermeulen',
      p_job_title      => 'Administratrice de bases de donnees',
      p_email          => 'avermeulen@ghm.lan',
      p_phone          => '+352 4411 2201',
      p_ldap_login     => 'avermeulen',
      p_is_primary     => 1 );
   l_dummy := pkg_dbinv_application.add_contact(
      p_application_id => l_app,
      p_contact_role   => 'BUSINESS',
      p_full_name      => 'Karim Benali',
      p_job_title      => 'Administrateur systeme',
      p_email          => 'kbenali@ghm.lan',
      p_phone          => '+352 4411 2202',
      p_ldap_login     => 'kbenali',
      p_is_primary     => 0 );
   l_doc := pkg_dbinv_application.add_document(
      p_application_id => l_app,
      p_title          => 'Schema d''architecture - Facturation et recouvrement',
      p_doc_kind       => 'DIAGRAM',
      p_external_url   => 'https://wiki.example.invalid/fact/never',
      p_review_months  => 12 );
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'ORACLE'
      and lower(h.hostname) = lower('oradb-prd-08')
      and i.instance_name = 'FACTURP'
      and db.db_name = 'FACTURPDB1';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'ORACLE database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'ORACLE'
      and lower(h.hostname) = lower('oradb-prd-08')
      and i.instance_name = 'FACTURP'
      and db.db_name = 'FACTURPDB2';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'ORACLE database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-02.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-02/SQLEXPRESS'
      and db.db_name = 'FACTUR_PRD';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-11.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-11'
      and db.db_name = 'FACTUR_PRD';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-21.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-21'
      and db.db_name = 'FACTUR_PRD';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-43.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-43'
      and db.db_name = 'FACTUR_PRD';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-52.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-52'
      and db.db_name = 'FACTUR_PRD';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-09.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-09/SQLEXPRESS'
      and db.db_name = 'FACTUR_PRD';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;

   -- PAIE : Paie et declarations sociales
   l_app := pkg_dbinv_application.create_application(
      p_app_code         => 'PAIE',
      p_app_name         => 'Paie et declarations sociales',
      p_description      => 'Paie et declarations sociales, progiciel',
      p_criticality      => 'HIGH',
      p_lifecycle_status => 'ACTIVE' );
   l_apps := l_apps + 1;
   pkg_dbinv_application.set_profile(
      p_application_id   => l_app,
      p_sourcing         => 'SAAS',
      p_vendor_name      => 'Cegapaie',
      p_product_version  => 'cloud',
      p_support_end_date => null,
      p_rto_minutes      => 1440,
      p_rpo_minutes      => 1440,
      p_service_window   => '7h-19h ouvres',
      p_data_sensitivity => 'SENSITIVE',
      p_register_ref     => 'RT-2019-022',
      p_note             => 'saisi avec le jeu de demonstration' );
   update ref_application set last_review_date = trunc(sysdate) - 60, last_review_by = 'demo', review_due_date = add_months(trunc(sysdate), 10) where application_id = l_app;
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'ADMIN',
      p_group_name      => 'Equipe PAIE - exploitation',
      p_contact_email   => 'dl-paie-exploit@ghm.lan',
      p_ldap_group_name => 'GG_PAIE_EXPLOIT',
      p_external_ref    => null );
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'BUSINESS',
      p_group_name      => 'Referents metier PAIE',
      p_contact_email   => 'dl-paie-metier@ghm.lan',
      p_ldap_group_name => 'GG_PAIE_METIER',
      p_external_ref    => null );
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'VENDOR',
      p_group_name      => 'Cegapaie - support contractuel',
      p_contact_email   => null,
      p_ldap_group_name => null,
      p_external_ref    => 'CONTRAT-PAIE' );
   l_dummy := pkg_dbinv_application.add_contact(
      p_application_id => l_app,
      p_contact_role   => 'ADMIN',
      p_full_name      => 'Sofia Marchetti',
      p_job_title      => 'Responsable applicative',
      p_email          => 'smarchetti@ghm.lan',
      p_phone          => '+352 4411 2203',
      p_ldap_login     => 'smarchetti',
      p_is_primary     => 1 );
   l_dummy := pkg_dbinv_application.add_contact(
      p_application_id => l_app,
      p_contact_role   => 'BUSINESS',
      p_full_name      => 'Tom Jacobs',
      p_job_title      => 'Cadre de sante referent',
      p_email          => 'tjacobs@ghm.lan',
      p_phone          => '+352 4411 2204',
      p_ldap_login     => 'tjacobs',
      p_is_primary     => 0 );
   l_doc := pkg_dbinv_application.add_document(
      p_application_id => l_app,
      p_title          => 'Procedure d''exploitation - Paie et declarations sociales',
      p_doc_kind       => 'RUNBOOK',
      p_external_url   => 'https://wiki.example.invalid/paie/current',
      p_review_months  => 12 );
   update ref_application_document set last_review_date = trunc(sysdate) - 30, last_review_by = 'demo' where document_id = l_doc;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'ORACLE'
      and lower(h.hostname) = lower('oradb-tst-16')
      and i.instance_name = 'PAIET'
      and db.db_name = 'PAIET';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'ORACLE database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-03.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-03'
      and db.db_name = 'PAIE_PRD';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-dev-30.ghm.lan')
      and i.instance_name = 'SQLSRV-DEV-30'
      and db.db_name = 'PAIE_DEV';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-09.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-09/SQLEXPRESS'
      and db.db_name = 'PAIE_PRD';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;

   -- GED : Gestion documentaire qualite
   l_app := pkg_dbinv_application.create_application(
      p_app_code         => 'GED',
      p_app_name         => 'Gestion documentaire qualite',
      p_description      => 'Gestion documentaire qualite, developpe en interne',
      p_criticality      => 'STANDARD',
      p_lifecycle_status => 'ACTIVE' );
   l_apps := l_apps + 1;
   pkg_dbinv_application.set_profile(
      p_application_id   => l_app,
      p_sourcing         => 'INTERNAL',
      p_vendor_name      => null,
      p_product_version  => '1.12',
      p_support_end_date => null,
      p_rto_minutes      => 1440,
      p_rpo_minutes      => 1440,
      p_service_window   => '7h-19h ouvres',
      p_data_sensitivity => 'NONE',
      p_register_ref     => null,
      p_note             => 'saisi avec le jeu de demonstration' );
   update ref_application set last_review_date = trunc(sysdate) - 400, last_review_by = 'demo', review_due_date = trunc(sysdate) - 35 where application_id = l_app;
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'ADMIN',
      p_group_name      => 'Equipe GED - exploitation',
      p_contact_email   => 'dl-ged-exploit@ghm.lan',
      p_ldap_group_name => 'GG_GED_EXPLOIT',
      p_external_ref    => null );
   l_dummy := pkg_dbinv_application.add_contact(
      p_application_id => l_app,
      p_contact_role   => 'ADMIN',
      p_full_name      => 'Lena Dupont',
      p_job_title      => 'Cheffe de projet SI',
      p_email          => 'ldupont@ghm.lan',
      p_phone          => '+352 4411 2205',
      p_ldap_login     => 'ldupont',
      p_is_primary     => 1 );
   l_doc := pkg_dbinv_application.add_document(
      p_application_id => l_app,
      p_title          => 'Notes de reprise - Gestion documentaire qualite',
      p_doc_kind       => 'OTHER',
      p_external_url   => 'https://wiki.example.invalid/ged/unplanned',
      p_review_months  => null );
   l_dummy := pkg_dbinv_application.add_source(
      p_application_id => l_app,
      p_repo_url       => 'https://git.example.invalid/si/ged.git',
      p_source_kind    => 'GIT',
      p_branch         => 'production' );
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'ORACLE'
      and lower(h.hostname) = lower('oradb-tst-01')
      and i.instance_name = 'QUALITT';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'ORACLE instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-06.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-06/GESTION';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-uat-07.ghm.lan')
      and i.instance_name = 'SQLSRV-UAT-07';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-11.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-11';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-13.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-13';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-dev-15.ghm.lan')
      and i.instance_name = 'SQLSRV-DEV-15';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-26.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-26';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-29.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-29/APPLI';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-41.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-41';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-uat-54.ghm.lan')
      and i.instance_name = 'SQLSRV-UAT-54';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-04.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-04/GESTION';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-05.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-05/METIER';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-uat-07.ghm.lan')
      and i.instance_name = 'SQLSRV-UAT-07/METIER';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-09.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-09/SQLEXPRESS';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL instance' );
   l_links := l_links + 1;
   select i.instance_id into l_entity
     from dim_instance i
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'POSTGRES'
      and lower(h.hostname) = lower('pgsrv-tst-03.ghm.lan')
      and i.instance_name = 'pgsrv-tst-03.ghm.lan';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'INSTANCE',
      p_entity_id      => l_entity,
      p_note           => 'POSTGRES instance' );
   l_links := l_links + 1;

   -- BIOMED : Parc des dispositifs medicaux
   l_app := pkg_dbinv_application.create_application(
      p_app_code         => 'BIOMED',
      p_app_name         => 'Parc des dispositifs medicaux',
      p_description      => 'Parc des dispositifs medicaux, progiciel',
      p_criticality      => 'LOW',
      p_lifecycle_status => 'DECOMMISSIONING' );
   l_apps := l_apps + 1;
   pkg_dbinv_application.set_profile(
      p_application_id   => l_app,
      p_sourcing         => 'OTHER',
      p_vendor_name      => 'Repris en interne',
      p_product_version  => '3.2',
      p_support_end_date => date '2026-03-31',
      p_rto_minutes      => null,
      p_rpo_minutes      => null,
      p_service_window   => 'heures ouvrables',
      p_data_sensitivity => 'UNKNOWN',
      p_register_ref     => null,
      p_note             => 'saisi avec le jeu de demonstration' );
   update ref_application set last_review_date = null, last_review_by = null, review_due_date = add_months(trunc(sysdate), 3) where application_id = l_app;
   l_dummy := pkg_dbinv_application.add_group(
      p_application_id  => l_app,
      p_group_type_code => 'ADMIN',
      p_group_name      => 'Equipe BIOMED - exploitation',
      p_contact_email   => 'dl-biomed-exploit@ghm.lan',
      p_ldap_group_name => 'GG_BIOMED_EXPLOIT',
      p_external_ref    => null );
   l_dummy := pkg_dbinv_application.add_contact(
      p_application_id => l_app,
      p_contact_role   => 'ADMIN',
      p_full_name      => 'Anne Vermeulen',
      p_job_title      => 'Administratrice de bases de donnees',
      p_email          => 'avermeulen@ghm.lan',
      p_phone          => '+352 4411 2201',
      p_ldap_login     => 'avermeulen',
      p_is_primary     => 1 );
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-02.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-02/SQLEXPRESS'
      and db.db_name = 'BIOMED_PRD';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-dev-23.ghm.lan')
      and i.instance_name = 'SQLSRV-DEV-23/APPLI'
      and db.db_name = 'BIOMED_DEV';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-46.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-46'
      and db.db_name = 'BIOMED_PRD';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-dev-49.ghm.lan')
      and i.instance_name = 'SQLSRV-DEV-49/APPLI'
      and db.db_name = 'BIOMED_DEV';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-prd-55.ghm.lan')
      and i.instance_name = 'SQLSRV-PRD-55'
      and db.db_name = 'BIOMED_PRD';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-tst-01.ghm.lan')
      and i.instance_name = 'SQLSRV-TST-01/FINANCE'
      and db.db_name = 'BIOMED_TST';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;
   select db.database_id into l_entity
     from dim_database db
     join dim_instance i on i.instance_id = db.instance_id
     join dim_host h on h.host_id = i.host_id
    where h.platform = 'MSSQL'
      and lower(h.hostname) = lower('sqlsrv-uat-07.ghm.lan')
      and i.instance_name = 'SQLSRV-UAT-07/METIER'
      and db.db_name = 'BIOMED_UAT';
   l_dummy := pkg_dbinv_application.link_entity(
      p_application_id => l_app,
      p_entity_type    => 'DATABASE',
      p_entity_id      => l_entity,
      p_note           => 'MSSQL database' );
   l_links := l_links + 1;

      dbms_output.put_line('Registre applicatif : ' || l_apps || ' application(s), '
         || l_links || ' rattachement(s).');
   end if;

   commit;
exception
   when no_data_found then
      raise_application_error(-20101,
         'Une entite attendue par le registre applicatif est absente de l''inventaire : '
         || 'l''ETL a-t-il bien tourne avant ce script ?');
end;
/
exit
