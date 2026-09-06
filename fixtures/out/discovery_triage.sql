-- Décisions de triage du jeu de démonstration.
-- Généré par fixtures/lib/emit_discovery.mjs — ne pas éditer à la main.
whenever sqlerror exit failure rollback
set define off
set serveroutput on
declare
   l_id number;
begin
   select di.disc_instance_id into l_id
     from disc_instance di
     join disc_host dh on dh.disc_host_id = di.disc_host_id
    where dh.platform = 'ORACLE'
      and lower(dh.hostname) = lower('oraapp-dev-73.ghm.lan')
      and di.instance_name = 'LEGACYD';
   pkg_dbinv_discovery.set_triage('INSTANCE', l_id, 'IGNORED', 'Machine editeur : cataloguee, hors perimetre de collecte.');

   select di.disc_instance_id into l_id
     from disc_instance di
     join disc_host dh on dh.disc_host_id = di.disc_host_id
    where dh.platform = 'MSSQL'
      and lower(dh.hostname) = lower('appsrv-dev-72.ghm.lan')
      and di.instance_name = 'SQLEXPRESS';
   pkg_dbinv_discovery.set_triage('INSTANCE', l_id, 'IGNORED', 'SQL Express embarque avec l''application, sous responsabilite editeur.');

   select dh.disc_host_id into l_id
     from disc_host dh
    where dh.platform = 'POSTGRES'
      and lower(dh.hostname) = lower('pgapp-prd-71.ghm.lan');
   pkg_dbinv_discovery.set_triage('HOST', l_id, 'IGNORED', 'Instance applicative embarquee, hors perimetre.');

   select dh.disc_host_id into l_id
     from disc_host dh
    where dh.platform = 'MYSQL'
      and lower(dh.hostname) = lower('mysrv-tst-75.ghm.lan');
   pkg_dbinv_discovery.set_triage('HOST', l_id, 'IGNORED', 'MySQL n''est pas collecte par dbInventory.');

   commit;
   dbms_output.put_line('Triage : 4 decision(s) appliquee(s).');
exception
   when no_data_found then
      raise_application_error(-20100,
         'Une entite de triage du jeu de demonstration est absente de la discovery : '
         || 'le chargement a-t-il bien eu lieu ?');
end;
/
exit
