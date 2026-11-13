-- =============================================================================
-- T_005 — export / import des données saisies (pkg_dbinv_transfer, V__015)
-- =============================================================================
-- Se joue sur la base de démonstration, APRÈS fixtures/load_fixtures.sh :
--
--   sql -S -name DEMO_DBINVENTORY_dbinventory @T_005_ref_data_transfer.sql
--
-- Ce script **annule sa transaction** : il ne laisse rien derrière lui, ni dans
-- le registre ni dans son journal, et ne déplace aucune mesure de la référence.
--
-- Ce qu'il prouve :
--   1. un aller-retour dans la même base ne change rien (idempotence), et le
--      fichier ne porte aucun identifiant technique ;
--   2. sous d'autres codes, tout est créé, rattachements résolus par leur nom ;
--   3. un champ modifié ailleurs est remis, et seulement lui ;
--   4. un fichier binaire (les 256 valeurs d'octet, plus de l'UTF-8) passe :
--      l'import recalcule l'empreinte des octets décodés et refuse s'ils ne sont
--      pas ceux de la source ; un contenu abîmé est donc refusé ;
--   5. un rattachement vers un serveur inconnu est ignoré, pas une erreur ;
--   6. les refus : version future, domaine inconnu, format, JSON invalide,
--      type de groupe inconnu.
--
-- Le rapport d'import est coupé pendant le test (dbms_output.disable, qui vide
-- le tampon) : les résultats sont gardés en mémoire et affichés à la fin.
-- =============================================================================
set serveroutput on size unlimited
set feedback off
whenever sqlerror exit failure rollback

prompt T_005 - export / import des donnees saisies

declare
   type t_lines is table of varchar2(4000);
   l_lines   t_lines := t_lines();
   l_failed  pls_integer := 0;
   l_doc     clob;
   l_bad     clob;
   l_app_id  number;
   l_code    varchar2(30 char);
   l_file    blob;
   l_sum     varchar2(64 char);
   l_n       pls_integer;
   l_groups  pls_integer;
   l_id      number;

   procedure note ( p_line varchar2 ) is
   begin
      l_lines.extend;
      l_lines(l_lines.count) := p_line;
   end note;

   procedure ok ( p_what varchar2 ) is
   begin
      note('  ok   : ' || p_what);
   end ok;

   procedure fail ( p_what varchar2, p_detail varchar2 ) is
   begin
      l_failed := l_failed + 1;
      note('  ECHEC: ' || p_what || ' -- ' || p_detail);
   end fail;

   procedure check_that ( p_what varchar2, p_cond boolean, p_detail varchar2 ) is
   begin
      if p_cond then ok(p_what); else fail(p_what, p_detail); end if;
   end check_that;

   function cnt ( p_item varchar2, p_outcome varchar2 ) return number is
   begin
      return pkg_dbinv_transfer.counter(p_item, p_outcome);
   end cnt;

   procedure expect ( p_what varchar2, p_item varchar2, p_outcome varchar2, p_expected number ) is
   begin
      check_that(p_what, cnt(p_item, p_outcome) = p_expected,
                 p_item || '/' || p_outcome || ' = ' || cnt(p_item, p_outcome) || ', attendu ' || p_expected);
   end expect;

   procedure quiet_import ( p_doc clob ) is
   begin
      dbms_output.disable;
      pkg_dbinv_transfer.import_json(p_doc, 0, 'T_005');
      dbms_output.enable(null);
   exception
      when others then
         dbms_output.enable(null);
         raise;
   end quiet_import;

   procedure expect_refusal ( p_what varchar2, p_doc clob, p_code number ) is
   begin
      quiet_import(p_doc);
      fail(p_what, 'aucune erreur levee, ' || p_code || ' attendue');
   exception
      when others then
         check_that(p_what, sqlcode = p_code, sqlerrm);
   end expect_refusal;

begin
   savepoint t_005;

   -- An application that has groups and attachments, so every part is exercised.
   select min(a.app_code) into l_code
     from ref_application a
    where a.active = 1
      and exists ( select 1 from ref_application_entity e where e.application_id = a.application_id and e.active = 1 )
      and exists ( select 1 from ref_application_group g where g.application_id = a.application_id and g.active = 1 );
   if l_code is null then
      raise_application_error(-20905,
         'T_005 : aucune application avec groupe et rattachement, le jeu de demo est-il charge ?');
   end if;
   select application_id into l_app_id from ref_application where app_code = l_code;

   -- 1. Idempotence.
   l_doc := pkg_dbinv_transfer.export_json;
   l_groups := cnt('GROUP', 'EXPORTED');   -- every import resets the counters
   select count(*) into l_n from ref_application where active = 1;
   expect('l''export porte toutes les applications actives', 'APPLICATION', 'EXPORTED', l_n);
   check_that('aucun identifiant technique dans le fichier', instr(l_doc, '_id"') = 0,
              'une cle en _id est presente');
   quiet_import(l_doc);
   expect('aller-retour : aucune application creee',    'APPLICATION', 'CREATED',   0);
   expect('aller-retour : aucune application modifiee', 'APPLICATION', 'UPDATED',   0);
   expect('aller-retour : toutes inchangees',           'APPLICATION', 'UNCHANGED', l_n);
   expect('aller-retour : aucun rattachement cree',     'ENTITY',      'CREATED',   0);
   expect('aller-retour : aucun rattachement ignore',   'ENTITY',      'SKIPPED',   0);
   expect('aller-retour : aucun document modifie',      'DOCUMENT',    'UPDATED',   0);
   select count(*) into l_id from ref_application_event where event_date > sysdate - 1/1440;
   check_that('aller-retour : rien au journal', l_id = 0, l_id || ' evenement(s)');

   -- 2. Creation, under other codes.
   quiet_import(replace(l_doc, '"app_code" : "', '"app_code" : "ZZ_'));
   expect('autres codes : toutes les applications creees', 'APPLICATION', 'CREATED', l_n);
   expect('autres codes : groupes crees comme exportes',   'GROUP', 'CREATED', l_groups);
   check_that('autres codes : rattachements resolus par leur nom',
              cnt('ENTITY', 'CREATED') > 0 and cnt('ENTITY', 'SKIPPED') = 0,
              cnt('ENTITY', 'CREATED') || ' crees, ' || cnt('ENTITY', 'SKIPPED') || ' ignores');
   select count(*) into l_id from ref_application where app_code like 'ZZ\_%' escape '\';
   check_that('simulation : rien n''est reste ecrit', l_id = 0, l_id || ' application(s) ZZ_ presentes');

   -- 3 and 4. Export a state with a binary file and a changed field, go back to
   -- the starting state, import it.
   dbms_lob.createtemporary(l_file, true);
   for b in 0 .. 255 loop
      dbms_lob.writeappend(l_file, 1, hextoraw(to_char(b, 'FM0X')));
   end loop;
   dbms_lob.append(l_file, to_blob(utl_i18n.string_to_raw(unistr('\00e9t\00e9 \00e0\00e7\00f9 \20ac'), 'AL32UTF8')));
   l_sum := pkg_dbinv_application.fingerprint(l_file);

   savepoint t_005_state;
   l_id := pkg_dbinv_application.add_document(
      p_application_id => l_app_id, p_title => 'T_005 fichier binaire',
      p_doc_kind => 'OTHER', p_file_name => 't005.bin',
      p_mime_type => 'application/octet-stream', p_content => l_file );
   update ref_application set description = 'T_005 description modifiee' where application_id = l_app_id;
   l_doc := pkg_dbinv_transfer.export_json(l_code);
   rollback to t_005_state;

   check_that('le fichier porte l''empreinte de la source', instr(l_doc, l_sum) > 0,
              'empreinte ' || l_sum || ' absente');
   select count(*) into l_id from ref_application_document
    where application_id = l_app_id and title = 'T_005 fichier binaire';
   check_that('etat de depart retabli avant l''import', l_id = 0, l_id || ' document(s)');

   quiet_import(l_doc);
   expect('mise a jour : l''application modifiee est remise',     'APPLICATION', 'UPDATED', 1);
   expect('fichier binaire : cree, octets conformes a l''empreinte', 'DOCUMENT',   'CREATED', 1);
   expect('mise a jour : aucun groupe touche',                     'GROUP',       'UPDATED', 0);

   -- The first four base64 characters stand for bytes 00 01 02; AAAA is 00 00 00.
   l_bad := regexp_replace(l_doc, '("content_base64" : ")....', '\1AAAA', 1, 1);
   check_that('le contenu a bien ete altere pour le test', l_bad <> l_doc, 'remplacement sans effet');
   expect_refusal('un fichier abime est refuse, rien n''est ecrit', l_bad, -20955);

   -- 5. Unknown server.
   quiet_import(regexp_replace(pkg_dbinv_transfer.export_json(l_code),
                               '"hostname" : "[^"]*"', '"hostname" : "t005-serveur-inconnu"'));
   check_that('serveur inconnu : rattachements ignores, sans erreur',
              cnt('ENTITY', 'SKIPPED') > 0 and cnt('ENTITY', 'CREATED') = 0
              and cnt('APPLICATION', 'UNCHANGED') = 1,
              cnt('ENTITY', 'SKIPPED') || ' ignores, ' || cnt('ENTITY', 'CREATED') || ' crees');

   -- 6. Refusals.
   l_doc := pkg_dbinv_transfer.export_json(l_code);
   expect_refusal('version future refusee', replace(l_doc, '"version" : 1,', '"version" : 99,'), -20953);
   expect_refusal('domaine inconnu refuse',
                  replace(l_doc, '"applications" :', '"derogations" : [], "applications" :'), -20954);
   expect_refusal('pas un fichier de transfert', '{"format" : "autre chose"}', -20952);
   expect_refusal('pas du JSON', 'ceci n''est pas du JSON', -20951);
   expect_refusal('type de groupe inconnu : application en erreur, rien d''ecrit',
                  regexp_replace(l_doc, '"group_type_code" : "[^"]*"', '"group_type_code" : "T005XX"', 1, 1),
                  -20955);

   rollback to t_005;

   for i in 1 .. l_lines.count loop
      dbms_output.put_line(l_lines(i));
   end loop;
   dbms_output.put_line('T_005 : ' || l_lines.count || ' verification(s), ' || l_failed || ' echec(s).');
   if l_failed > 0 then
      raise_application_error(-20905, 'T_005 : ' || l_failed || ' verification(s) en echec.');
   end if;
end;
/

rollback;
exit
