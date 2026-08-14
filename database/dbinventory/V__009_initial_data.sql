--
-- Generate initial data for the DB Inventory database.
--

-- ---------------------------------------------------------------------------
-- Record this installation.
--
-- Deliberately an INSERT with no delete: ref_app_release is append-only, so a
-- reinstall adds a line instead of erasing the previous ones. That history is
-- what lets you see how two environments diverged, not merely that they did.
--
-- Bump SCHEMA_VERSION when the model changes, and say what it carries in the
-- note. v_environment_identity reads the latest row, and the About page shows it.
-- ---------------------------------------------------------------------------
insert into ref_app_release ( version, note )
   values ( '1.1.0', 'CIS alignment: Oracle security rules, rule provenance, scoring freshness, derogation lifecycle.' );
commit;

delete from environments cascade;
insert into environments ( envt_short_code, environment ) values ( 'PRD', 'Production' );
insert into environments ( envt_short_code, environment ) values ( 'UAT', 'UAT' );
insert into environments ( envt_short_code, environment ) values ( 'TST', 'Test' );
insert into environments ( envt_short_code, environment ) values ( 'DEV', 'Development' );
commit;
   
delete from licence_types cascade;
insert into licence_types ( license_type, description, scoring_impact ) values ( 'CPU', 'CPU license type', 100 );
insert into licence_types ( license_type, description, scoring_impact ) values ( 'FREE', 'Free license type (No Cost like Open Source, SQLExpress, Oracle XE ...)', 0 );
insert into licence_types ( license_type, description, scoring_impact ) values ( 'ENTERPRISE', 'Enterprise license type', 100 );
insert into licence_types ( license_type, description, scoring_impact ) values ( 'STANDARD', 'Standard license type', 100 );
insert into licence_types ( license_type, description, scoring_impact ) values ( 'SAP', 'SAP license type (bundle provider)', 0 );
insert into licence_types ( license_type, description, scoring_impact ) values ( 'PROVIDER', 'PROVIDER license type (license is provided by a third party)', 0 );
commit;

delete from scoring_activity_list;

insert into scoring_activity_list (
   scoring_type,
   last_scoring_date,
   last_scoring_value,
   scoring_card_class,
   scoring_status,
   status_color,
   scoring_label,
   details_apex_page_number,
   scoring_order
) values ( 'Oracle Compliance',
           current_timestamp,
           100,
           'u-color-4-border',
           'OK',
           'u-color-4',
           'Compliance is 100%, all of the tests, checks and scoring passed.',
           2,
           1 );

insert into scoring_activity_list (
   scoring_type,
   last_scoring_date,
   last_scoring_value,
   scoring_card_class,
   scoring_status,
   status_color,
   scoring_label,
   details_apex_page_number,
   scoring_order
) values ( 'Oracle Licensing',
           current_timestamp,
           85,
           'u-color-7-border',
           'Warning',
           'u-color-7',
           'Compliance is 85%, some configuration items need improvement.',
           2,
           2 );

insert into scoring_activity_list (
   scoring_type,
   last_scoring_date,
   last_scoring_value,
   scoring_card_class,
   scoring_status,
   status_color,
   scoring_label,
   details_apex_page_number,
   scoring_order
) values ( 'MSSQL Compliance',
           current_timestamp,
           80,
           'u-color-7-border',
           'Warning',
           'u-color-7',
           'Compliance is 80%, some configuration items need improvement.',
           3,
           3 );

insert into scoring_activity_list (
   scoring_type,
   last_scoring_date,
   last_scoring_value,
   scoring_card_class,
   scoring_status,
   status_color,
   scoring_label,
   details_apex_page_number,
   scoring_order
) values ( 'MSSQL Licensing',
           current_timestamp,
           30,
           'u-color-9-border',
           'Warning',
           'u-color-9',
           'Compliance is 30%, this is critical, some configuration items need critical review.',
           3,
           4 );

insert into scoring_activity_list (
   scoring_type,
   last_scoring_date,
   last_scoring_value,
   scoring_card_class,
   scoring_status,
   status_color,
   scoring_label,
   details_apex_page_number,
   scoring_order
) values ( 'Postgres Compliance',
           current_timestamp,
           100,
           'u-color-4-border',
           'OK',
           'u-color-4',
           'Compliance is 100%, all of the tests, checks and scoring passed.',
           4,
           5 );

insert into scoring_activity_list (
   scoring_type,
   last_scoring_date,
   last_scoring_value,
   scoring_card_class,
   scoring_status,
   status_color,
   scoring_label,
   details_apex_page_number,
   scoring_order
) values ( 'MySQL Compliance',
           current_timestamp,
           80,
           'u-color-7-border',
           'Warning',
           'u-color-7',
           'Compliance is 80%, some configuration items need improvement.',
           5,
           7 );
/*
insert into scoring_activity_list (
   scoring_type,
   last_scoring_date,
   last_scoring_value,
   scoring_card_class,
   scoring_status,
   status_color,
   scoring_label,
   details_apex_page_number,
   scoring_order
) values ( 'MongoDB Compliance',
           current_timestamp,
           80,
           'u-color-7-border',
           'Warning',
           'u-color-7',
           'Compliance is 80%, some configuration items need improvement.',
           6,
           9 );

insert into scoring_activity_list (
   scoring_type,
   last_scoring_date,
   last_scoring_value,
   scoring_card_class,
   scoring_status,
   status_color,
   scoring_label,
   details_apex_page_number,
   scoring_order
) values ( 'MongoDB Licensing',
           current_timestamp,
           30,
           'u-color-9-border',
           'Warning',
           'u-color-9',
           'Compliance is 30%, this is critical, some configuration items need critical review.',
           6,
           10 );
*/
commit;