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
   values ( '2.0.0', 'Fresh install: upgrade-only migrations folded in, dead staging tables dropped, CHL compliance norms, Query Store, database count trend.' );
commit;

delete from environments;
insert into environments ( envt_short_code, environment ) values ( 'PRD', 'Production' );
insert into environments ( envt_short_code, environment ) values ( 'UAT', 'UAT' );
insert into environments ( envt_short_code, environment ) values ( 'TST', 'Test' );
insert into environments ( envt_short_code, environment ) values ( 'DEV', 'Development' );
commit;
   
delete from licence_types;
insert into licence_types ( license_type, description, scoring_impact ) values ( 'CPU', 'CPU license type', 100 );
insert into licence_types ( license_type, description, scoring_impact ) values ( 'FREE', 'Free license type (No Cost like Open Source, SQLExpress, Oracle XE ...)', 0 );
insert into licence_types ( license_type, description, scoring_impact ) values ( 'ENTERPRISE', 'Enterprise license type', 100 );
insert into licence_types ( license_type, description, scoring_impact ) values ( 'STANDARD', 'Standard license type', 100 );
insert into licence_types ( license_type, description, scoring_impact ) values ( 'SAP', 'SAP license type (bundle provider)', 0 );
insert into licence_types ( license_type, description, scoring_impact ) values ( 'PROVIDER', 'PROVIDER license type (license is provided by a third party)', 0 );
-- CHL et INCCI manquaient, alors que le parc les utilise : 45 entrees CHL et
-- 6 INCCI dans le seul perimetre MSSQL. Un referentiel qui ne connait pas les
-- valeurs en usage ne contraint rien, il empeche seulement de les saisir --
-- c'est ce qui bloquait la promotion depuis la discovery, dont les listes
-- deroulantes lisent cette table.
insert into licence_types ( license_type, description, scoring_impact ) values ( 'CHL', 'Licence acquise et portee par le CHL', 100 );
insert into licence_types ( license_type, description, scoring_impact ) values ( 'INCCI', 'Licence fournie dans le cadre INCCI', 0 );
commit;

