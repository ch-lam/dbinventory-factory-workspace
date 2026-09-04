-- =============================================================================
-- T_004  –  Assertions sur le jeu de données de démonstration
--
--   sql -S -name DEMO_DBINVENTORY_dbinventory @database/dbinventory/T_004_fixture_expectations.sql
--
-- Deux natures de vérification, volontairement séparées.
--
-- 1. ASSERTIONS STRUCTURELLES (ce fichier, partie basse).
--    Des invariants qui doivent tenir quel que soit le jeu de données : les
--    poids somment à 100, tout rule_code émis existe au catalogue, aucun
--    constat ne pend dans le vide, aucun score ne sort de ses bornes, et
--    chaque règle active produit des constats DES DEUX POLARITÉS. Cette
--    dernière est la plus utile : une règle qui ne rend qu'un seul verdict
--    n'est pas testée, elle est seulement exécutée.
--    Elles échouent bruyamment, par raise_application_error.
--
-- 2. EMPREINTE CHIFFRÉE (partie haute, spoolée).
--    Les comptes réels, dans un format ligne à ligne trié. Ce fichier n'est
--    PAS comparé ici : fixtures/check_baseline.sh le confronte à
--    fixtures/expected/baseline.csv par un simple diff. C'est délibéré --
--    quand un changement de règle déplace des chiffres, on veut voir LESQUELS
--    ont bougé, pas apprendre qu'un total ne correspond plus.
--
-- Pourquoi ne pas recalculer les verdicts attendus ici : ce serait
-- réimplémenter pkg_dbinv_scoring, et un test qui réimplémente son sujet ne
-- prouve que sa propre cohérence.
-- =============================================================================

whenever sqlerror exit failure rollback

set feedback off
set echo off
set verify off
set heading off
set pagesize 0
set linesize 400
set trimspool on
set serveroutput on size unlimited

-- Chemin du fichier d'empreinte. Surchargeable :
--   sql ... @T_004_fixture_expectations.sql /chemin/vers/actual.csv
define P_OUT = "&1"

-- =============================================================================
-- 1. Empreinte chiffrée
-- =============================================================================
spool &P_OUT

-- Le tri est fait en SQL et non par le shell : l'ordre doit être le même sur
-- toutes les machines, et un tri shell dépend de la locale.
with lignes as (
   -- ---- cardinalités du modèle -------------------------------------------
   select 1 ord, 'dim' section, 'host/' || platform k, to_char(count(*)) v
     from dim_host group by platform
   union all
   select 1, 'dim', 'instance/' || platform, to_char(count(*)) from dim_instance group by platform
   union all
   select 1, 'dim', 'database/' || platform, to_char(count(*)) from dim_database group by platform
   union all
   select 1, 'dim', 'storage/' || platform, to_char(count(*)) from dim_storage_unit group by platform
   union all
   select 1, 'dim', 'account/' || platform, to_char(count(*)) from dim_account group by platform
   union all
   select 1, 'dim', 'parameter/' || platform, to_char(count(*)) from dim_parameter group by platform
   union all
   -- ---- constats par règle et par verdict ---------------------------------
   select 2, 'finding', rule_code || '/' || is_compliant, to_char(count(*))
     from fact_control_finding group by rule_code, is_compliant
   union all
   -- ---- couverture par dérogation ------------------------------------------
   -- Séparé du verdict brut : une dérogation ne réécrit jamais is_compliant,
   -- elle pose exception_id. C'est ce qui rend la revue périodique possible.
   select 3, 'covered', rule_code,
          to_char(count(case when exception_id is not null then 1 end))
     from fact_control_finding group by rule_code
   union all
   select 3, 'norm_exception', rule_code,
          to_char(count(case when is_norm_exception = 1 then 1 end))
     from fact_control_finding group by rule_code
   union all
   -- ---- conformité agrégée -------------------------------------------------
   select 4, 'compliance', control_code || '/' || is_compliant, to_char(count(*))
     from fact_compliance group by control_code, is_compliant
   union all
   -- ---- scoring ------------------------------------------------------------
   -- Somme plutôt que ligne à ligne : une instance de plus ou de moins doit se
   -- voir, mais la liste des 200 instances n'apprendrait rien de plus.
   select 5, 'scoring', platform || '/' || environment || '/' || score_domain || '/' || entity_type,
          count(*) || ' rows, score=' || to_char(sum(score_value), 'FM999999990.00')
          || ', max=' || to_char(sum(max_score), 'FM999999990.00')
     from fact_scoring group by platform, environment, score_domain, entity_type
   union all
   select 5, 'scoring_status', platform || '/' || score_domain || '/' || nvl(status, 'NULL'),
          to_char(count(*))
     from fact_scoring group by platform, score_domain, status
   union all
   -- ---- volumétrie du staging ----------------------------------------------
   -- Prouve que le chargement a bien eu lieu : un CSV rejeté en silence se voit
   -- ici avant de se voir dans les constats.
   select 6, 'staging', 'oracle_databases', to_char(count(*)) from oracle_databases
   union all
   select 6, 'staging', 'oracle_security_parameter', to_char(count(*)) from oracle_security_parameter
   union all
   select 6, 'staging', 'oracle_security_profile', to_char(count(*)) from oracle_security_profile
   union all
   select 6, 'staging', 'oracle_size_usage', to_char(count(*)) from oracle_size_usage
   union all
   select 6, 'staging', 'oracle_size_usage_seg', to_char(count(*)) from oracle_size_usage_seg
   union all
   select 6, 'staging', 'oracle_users', to_char(count(*)) from oracle_users
   union all
   select 6, 'staging', 'mssql_hosts', to_char(count(*)) from mssql_hosts
   union all
   select 6, 'staging', 'mssql_databases', to_char(count(*)) from mssql_databases
   union all
   select 6, 'staging', 'mssql_files', to_char(count(*)) from mssql_files
   union all
   select 6, 'staging', 'mssql_security_configoptions', to_char(count(*)) from mssql_security_configoptions
   union all
   select 6, 'staging', 'postgres_hosts', to_char(count(*)) from postgres_hosts
   union all
   select 6, 'staging', 'postgres_databases', to_char(count(*)) from postgres_databases
)
select section || '|' || k || '|' || v
  from lignes
 order by ord, section, k;

spool off

-- =============================================================================
-- 2. Assertions structurelles
-- =============================================================================
set termout on

declare
   -- Toutes les variables AVANT les sous-programmes : PL/SQL n'accepte pas de
   -- declaration d'objet apres une declaration de procedure dans le meme bloc.
   l_failed  pls_integer := 0;
   l_checked pls_integer := 0;
   l_n       pls_integer;
   l_txt     varchar2(4000);

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

   procedure expect_zero ( p_what varchar2, p_count pls_integer, p_detail varchar2 ) is
   begin
      if p_count = 0 then ok(p_what);
      else fail(p_what, p_count || ' ' || p_detail);
      end if;
   end expect_zero;
begin
   dbms_output.put_line('T_004 - assertions structurelles');

   -- 1. Les poids de scoring somment à 100 par (plateforme, domaine).
   --    load_scoring divise par sum(weight) : une somme differente de 100 ne
   --    casse rien, mais rend les scores incomparables entre domaines, ce qui
   --    est précisément l'usage qu'on en fait sur le tableau de bord.
   select count(*) into l_n
     from ( select platform, score_domain, sum(weight) s
              from ref_scoring_weight where environment = '*'
             group by platform, score_domain )
    where s <> 100;
   expect_zero('poids sommant a 100 par (plateforme, domaine)', l_n, 'combinaison(s) hors 100');

   -- 2. Tout rule_code présent dans les faits existe au catalogue et est actif.
   select count(*) into l_n
     from fact_control_finding f
    where not exists ( select 1 from ref_control_rule r
                        where r.rule_code = f.rule_code and r.active = 1 );
   expect_zero('tout rule_code emis existe et est actif', l_n, 'constat(s) orphelin(s)');

   -- 3. Aucun constat ne pend dans le vide : son entité doit se résoudre.
   select count(*) into l_n
     from fact_control_finding f
    where not exists ( select 1 from v_entity_ancestry a
                        where a.entity_type = f.entity_type and a.entity_id = f.entity_id );
   expect_zero('toute entite de constat se resout', l_n, 'constat(s) sans entite');

   -- 4. Les scores restent dans leurs bornes.
   select count(*) into l_n from fact_scoring
    where score_value < 0 or max_score <= 0 or score_value > max_score;
   expect_zero('score dans [0, max_score]', l_n, 'score(s) hors bornes');

   -- 5. COUVERTURE : chaque règle active produit les DEUX verdicts.
   --    C'est l'assertion qui donne sa valeur au jeu de données. Une règle qui
   --    ne rend qu'un seul verdict passe tous les autres contrôles sans avoir
   --    jamais été mise à l'épreuve -- c'était le cas de la saturation, verte
   --    sur 1034 constats parce qu'elle ne pouvait structurellement pas rougir.
   --
   --    Exclues : les règles inactives, et les contrôles catalogués sans règle
   --    (les deux *_LICENSING, dont la logique LMS est différée).
   select count(*), listagg(rule_code, ', ') within group ( order by rule_code )
     into l_n, l_txt
     from ( select f.rule_code
              from fact_control_finding f
              join ref_control_rule r on r.rule_code = f.rule_code and r.active = 1
             group by f.rule_code
            having count(distinct f.is_compliant) < 2 );
   if l_n = 0 then
      ok('chaque regle active couvre les deux polarites');
   else
      fail('chaque regle active couvre les deux polarites',
           l_n || ' regle(s) a verdict unique : ' || substr(l_txt, 1, 900));
   end if;

   -- 6. Toute règle active a bien produit au moins un constat.
   --    Une règle muette est un trou dans le jeu de données, pas une règle qui
   --    passe : elle n'a jamais été exécutée.
   select count(*), listagg(rule_code, ', ') within group ( order by rule_code )
     into l_n, l_txt
     from ref_control_rule r
    where r.active = 1
      and not exists ( select 1 from fact_control_finding f where f.rule_code = r.rule_code );
   if l_n = 0 then
      ok('aucune regle active muette');
   else
      fail('aucune regle active muette', l_n || ' regle(s) sans constat : ' || substr(l_txt, 1, 900));
   end if;

   -- 7. Aucun nom du parc réel n'a survécu dans les dimensions.
   --    Le jeu de démonstration existe pour pouvoir montrer l'outil sans
   --    exposer le parc du CHL ; une base chargée par-dessus des données
   --    réelles les garderait, dim_host ne supprimant jamais rien.
   select count(*) into l_n from dim_host where lower(hostname) like '%chl.lu%';
   expect_zero('aucun hote residuel du parc reel', l_n, 'hote(s) en .chl.lu dans dim_host');

   -- 8. Un standby PostgreSQL ne porte AUCUN constat SECURITY.
   --    get_info_postgres_security.sh saute les standby : leur configuration est
   --    celle de leur primaire, deja jugee. C'est le seul endroit du modele ou
   --    une instance collectee n'a legitimement aucun verdict de securite, et
   --    c'est donc le seul endroit ou l'absence de constat doit etre testee
   --    comme un resultat plutot que soupconnee comme un trou.
   select count(*) into l_n
     from fact_control_finding f
     join ref_control_rule r on r.rule_code = f.rule_code
     join ref_control rc on rc.control_code = r.control_code
          and rc.platform = 'POSTGRES' and rc.score_domain = 'SECURITY'
     join v_entity_ancestry a on a.entity_type = f.entity_type and a.entity_id = f.entity_id
     join ext_postgres_instance e on e.instance_id = a.instance_id and e.db_role = 'STANDBY';
   expect_zero('aucun constat SECURITY sur un standby PostgreSQL', l_n, 'constat(s) sur standby');

   -- 9. ... et sa moitie indispensable : tout PRIMAIRE en porte.
   --    Sans elle, l'assertion 8 passerait aussi bien si la securite PostgreSQL
   --    ne produisait rien du tout -- ce qui etait precisement l'etat du produit
   --    avant ce chantier.
   select count(*) into l_n
     from ext_postgres_instance e
    where e.db_role = 'PRIMARY'
      and not exists ( select 1
                         from fact_control_finding f
                         join ref_control_rule r on r.rule_code = f.rule_code
                         join ref_control rc on rc.control_code = r.control_code
                              and rc.platform = 'POSTGRES' and rc.score_domain = 'SECURITY'
                         join v_entity_ancestry a on a.entity_type = f.entity_type
                              and a.entity_id = f.entity_id
                        where a.instance_id = e.instance_id );
   expect_zero('tout primaire PostgreSQL porte des constats SECURITY', l_n, 'primaire(s) sans constat');

   dbms_output.put_line('T_004 : ' || l_checked || ' verification(s), ' || l_failed || ' echec(s).');
   if l_failed > 0 then
      raise_application_error(-20903,
         'T_004 : ' || l_failed || ' assertion(s) en echec sur le jeu de donnees de demonstration.');
   end if;
end;
/

exit
