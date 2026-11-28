-- =============================================================================
-- T_004 — la promotion, depuis la discovery vers les trois périmètres
-- =============================================================================
-- Se joue sur la base de démonstration, APRÈS fixtures/load_fixtures.sh.
--
--   sql -S -name DEMO_DBINVENTORY_dbinventory @fixtures/checks/T_004_discovery_promotion.sql
--
-- Ce script **annule sa transaction**. Il ne laisse donc rien derrière lui, et
-- peut se jouer avant ou après check_baseline.sh sans en déplacer une mesure.
-- C'est ce qui lui permet d'exister à côté de T_003 plutôt que dedans : une
-- promotion réussie change le périmètre, donc l'empreinte, et un test qui
-- déplace la référence qu'il vérifie ne vérifie rien.
--
-- Les entités sont résolues par CLÉ NATURELLE et jamais par identifiant : les
-- identity sont régénérés à chaque rechargement du jeu, et un id écrit en dur
-- ici testerait la mauvaise ligne le lendemain, ou aucune.
-- =============================================================================
set serveroutput on size unlimited
set feedback off
whenever sqlerror exit failure rollback

prompt T_004 - promotion depuis la discovery

declare
   l_failed  pls_integer := 0;
   l_checked pls_integer := 0;
   l_id      number;
   l_n       pls_integer;
   l_tns     varchar2(150 char);

   procedure ok ( p_what varchar2 ) is
   begin
      l_checked := l_checked + 1;
      dbms_output.put_line('  ok   : ' || p_what);
   end ok;

   procedure fail ( p_what varchar2, p_detail varchar2 ) is
   begin
      l_checked := l_checked + 1;
      l_failed := l_failed + 1;
      dbms_output.put_line('  ECHEC: ' || p_what || ' -- ' || p_detail);
   end fail;

   -- Une entité découverte que le périmètre ne connaît pas : c'est sur celle-là
   -- que la promotion a quelque chose à faire.
   function a_new_instance ( p_platform varchar2 ) return number is
      l_out number;
   begin
      select min(entity_id) into l_out
        from v_discovery_status
       where platform = p_platform
         and level_name = 'INSTANCE'
         and effective_status = 'NEW';
      return l_out;
   end a_new_instance;

   function a_new_host ( p_platform varchar2 ) return number is
      l_out number;
   begin
      select min(entity_id) into l_out
        from v_discovery_status
       where platform = p_platform
         and level_name = 'HOST'
         and effective_status = 'NEW';
      return l_out;
   end a_new_host;

begin

   -- ---------------------------------------------------------------- MSSQL --
   -- Le cas le plus simple : la discovery donne tout ce que le périmètre veut.
   l_id := a_new_instance('MSSQL');
   if l_id is null then
      fail('promotion MSSQL', 'aucune instance MSSQL en NEW dans le jeu');
   else
      pkg_dbinv_discovery.promote_instance(l_id, 'DEV', 'FREE');
      select count(*) into l_n
        from v_discovery_status
       where level_name = 'INSTANCE' and entity_id = l_id
         and effective_status = 'COLLECTED';
      if l_n = 1 then ok('la promotion MSSQL fait basculer la ligne en COLLECTED');
      else fail('la promotion MSSQL fait basculer la ligne en COLLECTED',
                'statut inchange apres promotion');
      end if;
   end if;

   -- --------------------------------------------------------------- Oracle --
   -- Le SID n'est pas un nom de service : les deux sont passés séparément, et
   -- c'est l'easy_connect produit qu'on vérifie, pas seulement la présence
   -- d'une ligne. Une entrée mal formée se connecterait à rien, chaque nuit.
   l_id := a_new_instance('ORACLE');
   if l_id is null then
      fail('promotion ORACLE', 'aucune instance Oracle en NEW dans le jeu');
   else
      pkg_dbinv_discovery.promote_instance(
         p_disc_instance_id => l_id,
         p_environment      => 'DEV',
         p_license_type     => 'CPU',
         p_collect_name     => 'T004ORA',
         p_service_name     => 'T004SRV',
         p_port             => 1521 );
      select max(easy_connect_tns) into l_tns
        from oracle_collect_list
       where collect_name = 'T004ORA';
      if l_tns is not null and regexp_like(l_tns, '^[^:/]+:[0-9]+/T004SRV$') then
         ok('la promotion ORACLE ecrit un easy_connect bien forme (' || l_tns || ')');
      else
         fail('la promotion ORACLE ecrit un easy_connect bien forme',
              nvl(l_tns, '(aucune entree creee)'));
      end if;
   end if;

   -- Sans nom de service, elle doit refuser plutôt que d'inventer.
   l_id := a_new_instance('ORACLE');
   if l_id is not null then
      begin
         pkg_dbinv_discovery.promote_instance(
            p_disc_instance_id => l_id,
            p_environment      => 'DEV',
            p_license_type     => 'CPU',
            p_collect_name     => 'T004ORA2' );
         fail('la promotion ORACLE sans service est refusee', 'elle a ete acceptee');
      exception
         when others then
            if sqlcode = -20009 then ok('la promotion ORACLE sans service est refusee');
            else fail('la promotion ORACLE sans service est refusee', sqlerrm);
            end if;
      end;
   end if;

   -- ----------------------------------------------------------- PostgreSQL --
   -- Aucun grain instance dans la discovery : c'est promote_host, ou rien.
   l_id := a_new_host('POSTGRES');
   if l_id is null then
      fail('promotion POSTGRES', 'aucun hote PostgreSQL en NEW dans le jeu');
   else
      pkg_dbinv_discovery.promote_host(
         p_disc_host_id => l_id,
         p_environment  => 'DEV',
         p_license_type => 'FREE',
         p_collect_name => 'T004PG' );
      select count(*) into l_n from postgres_collect_list
       where collect_name = 'T004PG' and active = 1;
      if l_n = 1 then ok('la promotion POSTGRES cree son entree de perimetre');
      else fail('la promotion POSTGRES cree son entree de perimetre', 'aucune entree');
      end if;
   end if;

   -- Le même hôte par promote_instance : il n'a pas de grain instance, la
   -- procédure doit le dire au lieu d'échouer sur un identifiant introuvable.
   begin
      pkg_dbinv_discovery.promote_instance(
         p_disc_instance_id => -1,
         p_environment      => 'DEV',
         p_license_type     => 'FREE' );
      fail('un identifiant inconnu est refuse', 'il a ete accepte');
   exception
      when others then
         if sqlcode = -20003 then ok('un identifiant inconnu est refuse');
         else fail('un identifiant inconnu est refuse', sqlerrm);
         end if;
   end;

   -- ---------------------------------------------------------------- MySQL --
   -- MySQL n'a pas de table de périmètre. Le refus doit être nommé, pas un
   -- échec de contrainte : c'est ce que lit l'utilisateur dans l'écran.
   l_id := a_new_host('MYSQL');
   if l_id is null then
      fail('promotion MYSQL', 'aucun hote MySQL en NEW dans le jeu');
   else
      begin
         pkg_dbinv_discovery.promote_host(
            p_disc_host_id => l_id,
            p_environment  => 'DEV',
            p_license_type => 'FREE',
            p_collect_name => 'T004MY' );
         fail('la promotion MYSQL est refusee', 'elle a ete acceptee');
      exception
         when others then
            if sqlcode = -20001 then ok('la promotion MYSQL est refusee');
            else fail('la promotion MYSQL est refusee', sqlerrm);
            end if;
      end;
   end if;

   -- ------------------------------------------------------- reactivation ----
   -- Repromouvoir une entree desactivee doit la RALLUMER, pas echouer sur la
   -- cle primaire : c'est le geste courant apres une decision revue.
   select min(entity_id) into l_id
     from v_discovery_status
    where platform = 'MSSQL' and level_name = 'INSTANCE'
      and effective_status = 'IGNORED' and entity_id is not null;
   if l_id is null then
      fail('la re-promotion reactive une entree desactivee',
           'aucune instance MSSQL IGNORED dans le jeu');
   else
      begin
         pkg_dbinv_discovery.promote_instance(l_id, 'PRD', 'CHL');
         select count(*) into l_n
           from v_discovery_status
          where level_name = 'INSTANCE' and entity_id = l_id
            and effective_status = 'COLLECTED';
         if l_n = 1 then ok('la re-promotion reactive une entree desactivee');
         else fail('la re-promotion reactive une entree desactivee', 'statut inchange');
         end if;
      exception
         when others then
            fail('la re-promotion reactive une entree desactivee', sqlerrm);
      end;
   end if;

   -- Rien ne doit survivre a ce script : il se joue sur une base dont la
   -- reference est comparee au constat pres.
   rollback;

   dbms_output.put_line('T_004 : ' || l_checked || ' verification(s), '
                        || l_failed || ' echec(s).  (rollback)');
   if l_failed > 0 then
      raise_application_error(-20904,
         'T_004 : ' || l_failed || ' assertion(s) en echec sur la promotion.');
   end if;
end;
/

exit
