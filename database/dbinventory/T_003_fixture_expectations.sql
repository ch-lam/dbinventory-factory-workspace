-- =============================================================================
-- T_003  –  Assertions sur le jeu de données de démonstration
--
--   sql -S -name DEMO_DBINVENTORY_dbinventory @database/dbinventory/T_003_fixture_expectations.sql
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
--   sql ... @T_003_fixture_expectations.sql /chemin/vers/actual.csv
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
   union all
   select 6, 'staging', 'discovery_mssql_inst', to_char(count(*)) from discovery_mssql_inst
   union all
   select 6, 'staging', 'discovery_linux_engines', to_char(count(*)) from discovery_linux_engines
   union all
   -- ---- discovery -----------------------------------------------------------
   -- Rien ici ne descend de sysdate. days_since_last_seen et is_stale de
   -- v_discovery_status en derivent, eux : ils vaudraient autre chose le
   -- lendemain de la capture, et une reference qui les porterait serait fausse
   -- sans que personne n'ait rien change. effective_status, au contraire, ne
   -- depend que de triage_status et du perimetre.
   select 7, 'discovery', 'run/' || source,
          host_count || ' hotes, ' || finding_count || ' constats'
     from disc_run
   union all
   -- La date de run, en clair : load_all a pour defaut trunc(sysdate), et sans
   -- cette mesure une chaine qui daterait le run d'aujourd'hui passerait
   -- inapercue jusqu'au lendemain.
   select 7, 'discovery', 'run_date/' || source, to_char(run_date, 'YYYY-MM-DD')
     from disc_run
   union all
   select 7, 'discovery', 'finding/' || platform || '/' || finding_level, to_char(count(*))
     from disc_finding group by platform, finding_level
   union all
   select 7, 'discovery', 'host/' || platform || '/' || triage_status, to_char(count(*))
     from disc_host group by platform, triage_status
   union all
   select 7, 'discovery', 'instance/' || platform || '/' || triage_status, to_char(count(*))
     from disc_instance group by platform, triage_status
   union all
   select 7, 'discovery', 'status/' || platform || '/' || level_name || '/' || effective_status,
          to_char(count(*))
     from v_discovery_status group by platform, level_name, effective_status
   union all
   -- ---- perimetre de collecte ----------------------------------------------
   -- Le perimetre est desormais alimente par le jeu, et c'est la cible de la
   -- promotion : il se mesure.
   select 8, 'perimetre', 'oracle/' || active, to_char(count(*))
     from oracle_collect_list group by active
   union all
   select 8, 'perimetre', 'mssql/' || active, to_char(count(*))
     from mssql_collect_list group by active
   union all
   select 8, 'perimetre', 'postgres/' || active, to_char(count(*))
     from postgres_collect_list group by active
   union all
   -- ---- registre applicatif -------------------------------------------------
   -- Ce que le registre couvre, et surtout ce qu'il ne couvre pas. Rien ici ne
   -- descend de sysdate : les etats de revue en descendent, eux, et une
   -- reference qui les porterait deviendrait fausse toute seule.
   select 9, 'application', 'criticality/' || criticality, to_char(count(*))
     from ref_application group by criticality
   union all
   select 9, 'application', 'sourcing/' || sourcing, to_char(count(*))
     from ref_application group by sourcing
   union all
   select 9, 'application', 'sensitivity/' || data_sensitivity, to_char(count(*))
     from ref_application group by data_sensitivity
   union all
   select 9, 'application', 'lifecycle/' || lifecycle_status, to_char(count(*))
     from ref_application group by lifecycle_status
   union all
   select 9, 'application', 'attachment/' || entity_type, to_char(count(*))
     from ref_application_entity where active = 1 group by entity_type
   union all
   select 9, 'application', 'group/' || group_type_code, to_char(count(*))
     from ref_application_group where active = 1 group by group_type_code
   union all
   select 9, 'application', 'contact/' || contact_role, to_char(count(*))
     from ref_application_contact where active = 1 group by contact_role
   union all
   select 9, 'application', 'document/' || doc_kind, to_char(count(*))
     from ref_application_document where active = 1 group by doc_kind
   union all
   select 9, 'application', 'source', to_char(count(*))
     from ref_application_source where active = 1
   union all
   -- La cascade, mesuree des deux cotes. 90 rattachements couvrant 90 bases
   -- voudrait dire qu'elle ne cascade rien.
   select 9, 'application', 'covered_database', to_char(count(distinct database_id))
     from v_application_database
   union all
   select 9, 'application', 'unclaimed_database', to_char(count(*))
     from v_database_without_application
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
   l_warned  pls_integer := 0;
   l_checked pls_integer := 0;
   l_n       pls_integer;
   l_txt     varchar2(4000);

   -- Age du jeu, en jours depuis load_fixtures. Les fixtures posent certaines
   -- dates relativement au jour du chargement (fixtures/lib/emit_applications.mjs)
   -- et les vues les evaluent contre sysdate : le jeu vieillit. La plus courte
   -- fenetre est celle du document « due soon », echeance a sysdate + 20.
   -- En deca, un etat date absent est un defaut du generateur ; au-dela, c'est
   -- le jeu qui a vieilli.
   c_aging_days constant pls_integer := 20;
   l_age     pls_integer;

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

   -- Couverture d'etats qui descendent de sysdate. Un jeu vieilli n'est pas
   -- casse : il ne montre plus tous ses etats. Avertir, sans bloquer --
   -- recharger la demo les repose.
   procedure expect_dated_coverage ( p_what varchar2, p_got pls_integer, p_expected pls_integer ) is
   begin
      if p_got = p_expected then
         ok(p_what);
      elsif l_age > c_aging_days then
         l_checked := l_checked + 1;
         l_warned := l_warned + 1;
         dbms_output.put_line('  ATTENTION: ' || p_what || ' -- seulement ' || p_got || ' sur '
            || p_expected || ' : jeu charge il y a ' || l_age || ' jour(s), rejouer load_fixtures');
      else
         fail(p_what, 'seulement ' || p_got || ' sur ' || p_expected);
      end if;
   end expect_dated_coverage;
begin
   dbms_output.put_line('T_003 - assertions structurelles');

   select nvl(trunc(sysdate) - trunc(max(created_date)), 0) into l_age from ref_application;

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
   --    (MSSQL_LICENSING, dont la norme n'est pas arrêtée).
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

   -- 10. Les deux runs de discovery existent.
   --     load_mssql et load_linux sortent sans rien faire quand leur table de
   --     staging est vide : un fichier non depose ne produit donc AUCUN run,
   --     et pas une erreur. C'est cette assertion qui le dit.
   select count(distinct source) into l_n from disc_run;
   if l_n = 2 then ok('les deux sources de discovery ont produit un run');
   else fail('les deux sources de discovery ont produit un run',
             l_n || ' source(s) au lieu de 2');
   end if;

   -- 11. La date de run est celle du snapshot.
   --     pkg_dbinv_discovery.load_all a pour defaut trunc(sysdate) : si la
   --     chaine oublie de passer la date, la reference devient fausse le
   --     lendemain, et le diff ne dirait pas pourquoi.
   select count(*) into l_n
     from disc_run
    where run_date <> ( select max(snapshot_date) from fact_scoring );
   expect_zero('la discovery est datee du snapshot', l_n, 'run(s) a une autre date');

   -- 12. COUVERTURE : les quatre statuts de reconciliation sont representes.
   --     L'equivalent, pour la discovery, de l'assertion 5 sur les regles. Un
   --     jeu qui cesserait d'exercer NOT_SEEN -- le cas qui compte le plus pour
   --     le RSSI, une base collectee qui a disparu du parc -- retrecirait en
   --     silence. MySQL n'a pas de table de perimetre : il ne peut etre que NEW
   --     ou IGNORED, et c'est la definition, pas un trou.
   l_txt := null;
   for c in ( select p.platform, st.statut
                from ( select 'ORACLE' platform from dual
                       union all select 'MSSQL' from dual
                       union all select 'POSTGRES' from dual
                       union all select 'MYSQL' from dual ) p
                cross join ( select 'NEW' statut from dual
                             union all select 'COLLECTED' from dual
                             union all select 'IGNORED' from dual
                             union all select 'NOT_SEEN' from dual ) st
               where not ( p.platform = 'MYSQL'
                           and st.statut in ( 'COLLECTED', 'NOT_SEEN' ) )
                 and not exists ( select 1
                                    from v_discovery_status v
                                   where v.platform = p.platform
                                     and v.effective_status = st.statut )
               order by p.platform, st.statut )
   loop
      l_txt := ltrim(l_txt || ', ') || c.platform || '/' || c.statut;
   end loop;
   if l_txt is null then
      ok('les quatre statuts de reconciliation sont exerces sur chaque moteur');
   else
      fail('les quatre statuts de reconciliation sont exerces sur chaque moteur',
           'absent(s) : ' || l_txt);
   end if;

   -- 13. Un constat ORACLE de niveau HOTE existe.
   --     Le cas << Oracle installe, aucun SID resolu >>, que la promotion doit
   --     refuser. Sans une donnee pour le declencher, ce refus n'est jamais
   --     joue et pourrait disparaitre sans que rien ne le signale.
   select count(*) into l_n
     from disc_finding
    where platform = 'ORACLE' and finding_level = 'HOST';
   if l_n > 0 then ok('un constat ORACLE de niveau hote existe');
   else fail('un constat ORACLE de niveau hote existe', 'aucun');
   end if;

   -- 14. Le fichier Linux n'a pas ete decale.
   --     Le chargement est POSITIONNEL : une colonne de plus chez le producteur
   --     et tout glisse d'un cran, sans erreur. load_findings_linux lit les
   --     compteurs de processus a travers un to_number ... on conversion error,
   --     donc un 'Y' decale devient un NULL silencieux, pas une exception.
   --     Ces trois colonnes ne peuvent valoir que Y ou N, et ces trois-la que
   --     des chiffres : c'est ce qui rend le decalage visible.
   select count(*) into l_n
     from discovery_linux_engines
    where pg_pkg not in ( 'Y', 'N' )
       or ora_pkg not in ( 'Y', 'N' )
       or my_pkg not in ( 'Y', 'N' )
       or not regexp_like(pg_proc, '^[0-9]+$')
       or not regexp_like(ora_proc, '^[0-9]+$')
       or not regexp_like(my_proc, '^[0-9]+$');
   expect_zero('le fichier Linux est aligne sur son contrat', l_n, 'ligne(s) decalee(s)');

   -- 15. Aucun nom du parc reel dans la discovery.
   --     Le pendant de l'assertion 7, et il n'est pas theorique : le depot
   --     contient discovery/windows/discovery_MSSQL_20260715.csv, un extrait
   --     reel plein de .ad.chl.lu, a un cp pres de collect/.
   select count(*) into l_n
     from disc_host
    where lower(hostname) like '%chl.lu%';
   expect_zero('aucun hote residuel du parc reel dans la discovery', l_n,
               'hote(s) en .chl.lu dans disc_host');


   -- 16. Toute règle active porte un domaine NIS2.
   --     La colonne est nullable exprès : une contrainte NOT NULL dirait que
   --     quelque chose n'est pas classé, cette assertion dit QUOI. Une règle
   --     non classée ne casse rien -- elle disparaît simplement de la bande,
   --     et un écart réel cesse d'être compté sans que rien ne rougisse.
   --     Exclu : le domaine LICENSING. Une option utilisée sans licence est une
   --     exposition contractuelle, pas une des mesures de l'article 21(2) ; la
   --     classer quelque part ferait rougir la posture NIS2 pour une facture.
   select count(*), listagg(r.rule_code, ', ') within group ( order by r.rule_code )
     into l_n, l_txt
     from ref_control_rule r
     join ref_control c on c.control_code = r.control_code
    where r.active = 1
      and c.score_domain <> 'LICENSING'
      and r.nis2_domain_code is null;
   if l_n = 0 then
      ok('toute regle active porte un domaine NIS2');
   else
      fail('toute regle active porte un domaine NIS2',
           l_n || ' regle(s) non classee(s) : ' || substr(l_txt, 1, 900));
   end if;

   -- 17. Chaque instance et chaque base a sa bande complète.
   --     C'est l'assertion qui protège le produit cartésien de la vue. Sans
   --     lui, un domaine sans constat DISPARAÎT au lieu de s'afficher en gris,
   --     et un bloc absent se lit exactement comme un bloc conforme.
   select count(*) into l_n
     from ( select e.entity_type, e.entity_id
              from ( select 'INSTANCE' entity_type, instance_id entity_id from dim_instance
                     union all
                     select 'DATABASE', database_id from dim_database ) e
              left join v_nis2_posture p
                on p.entity_type = e.entity_type
               and p.entity_id = e.entity_id
             group by e.entity_type, e.entity_id
            having count(p.nis2_domain_code) <> ( select count(*) from ref_nis2_domain ) );
   expect_zero('chaque entite porte un bloc par domaine NIS2', l_n, 'entite(s) a la bande incomplete');

   -- 18. Le statut affiché suit les comptes qui le justifient.
   --     La bande est lue en une seconde, sans son détail : une pastille verte
   --     posée sur un écart ouvert ne se rattrape nulle part.
   select count(*) into l_n
     from v_nis2_posture
    where ( rules_evaluated = 0 and status <> 'NOT_ASSESSED' )
       or ( rules_evaluated > 0 and status = 'NOT_ASSESSED' )
       or ( open_gaps > 0 and status not in ( 'CRITICAL', 'WARNING' ) )
       or ( open_gaps = 0 and status in ( 'CRITICAL', 'WARNING' ) );
   expect_zero('le statut NIS2 suit ses comptes', l_n, 'ligne(s) incoherente(s)');

   -- 19. Aucun domaine NIS2 déclaré sans la moindre règle.
   --     Un domaine vide serait gris sur TOUTE carte des trois moteurs, et
   --     apprendrait au lecteur à ignorer le gris -- la seule couleur dont on
   --     a besoin qu'elle continue de vouloir dire quelque chose.
   select count(*), listagg(d.nis2_domain_code, ', ') within group ( order by d.display_order )
     into l_n, l_txt
     from ref_nis2_domain d
    where not exists ( select 1 from ref_control_rule r
                        where r.nis2_domain_code = d.nis2_domain_code and r.active = 1 );
   if l_n = 0 then
      ok('chaque domaine NIS2 porte au moins une regle active');
   else
      fail('chaque domaine NIS2 porte au moins une regle active',
           l_n || ' domaine(s) vide(s) : ' || l_txt);
   end if;
   -- 20. Toute application du registre a au moins un groupe responsable.
   --     Une entree sans personne derriere est exactement ce que ce registre
   --     existe pour supprimer : elle repond "oui" a "est-ce inventorie ?" et
   --     rien a "qui j'appelle ?".
   select count(*), listagg(a.app_code, ', ') within group ( order by a.app_code )
     into l_n, l_txt
     from ref_application a
    where a.active = 1
      and not exists ( select 1 from ref_application_group g
                        where g.application_id = a.application_id and g.active = 1 );
   if l_n = 0 then
      ok('chaque application porte au moins un groupe responsable');
   else
      fail('chaque application porte au moins un groupe responsable',
           l_n || ' application(s) sans groupe : ' || l_txt);
   end if;

   -- 21. Tout contact nomme est joignable.
   --     La contrainte du modele le garantit deja ; on le mesure quand meme,
   --     parce que la contrainte peut etre relachee un jour et que c'est
   --     precisement le jour ou personne ne s'en apercevra.
   select count(*) into l_n
     from ref_application_contact
    where active = 1
      and email is null and phone is null and ldap_login is null;
   expect_zero('chaque contact nomme est joignable', l_n, 'contact(s) injoignable(s)');

   -- 22. La cascade de rattachement resout PLUS de bases qu'il n'y a de lignes
   --     de rattachement. C'est toute l'economie du modele : rattacher une
   --     instance couvre ses bases sans les enumerer. Une egalite stricte
   --     voudrait dire que chaque rattachement ne couvre qu'une base, donc que
   --     plus rien ne cascade -- et le jeu passerait sans rien prouver.
   declare
      l_links pls_integer;
      l_dbs   pls_integer;
   begin
      select count(*) into l_links from ref_application_entity where active = 1;
      select count(distinct database_id) into l_dbs from v_application_database;
      if l_dbs > l_links then
         ok('la cascade de rattachement couvre ' || l_dbs || ' base(s) pour '
            || l_links || ' rattachement(s)');
      else
         fail('la cascade de rattachement couvre plus que ses lignes',
              l_dbs || ' base(s) couverte(s) pour ' || l_links || ' rattachement(s)');
      end if;
   end;

   -- 23. Il reste des bases non reclamees.
   --     C'est le produit utile du registre, pas un defaut : la liste de ce
   --     qu'il reste a faire. Un jeu ou tout serait reclame n'exercerait jamais
   --     l'ecran qui la porte, et ne montrerait pas le seul chiffre qui bouge
   --     quand l'ETL decouvre une base.
   select count(*) into l_n from v_database_without_application;
   if l_n > 0 then
      ok(l_n || ' base(s) non reclamee(s), comme attendu');
   else
      fail('il reste des bases non reclamees',
           'toutes les bases sont reclamees : le backlog du registre ne se voit plus');
   end if;

   -- 24. Les deux bouts de la relation comptent pareil.
   --     v_entity_application alimente les six ecrans d'inventaire,
   --     v_application_database alimente l'ecran d'application. Un desaccord
   --     afficherait une base reclamee d'un cote et orpheline de l'autre.
   select count(*) into l_n
     from ( select application_id, database_id from v_application_database
            minus
            select application_id, entity_id from v_entity_application
             where entity_type = 'DATABASE' );
   expect_zero('les deux lectures de la couverture concordent', l_n, 'ecart(s)');

   -- 25. Les quatre etats de revue d'application sont representes.
   --     Meme raison que la couverture des regles : un etat jamais produit est
   --     un etat jamais teste. Ces etats descendent de sysdate, donc ils sont
   --     vrais au chargement -- rejouer load_fixtures les repose. Passe
   --     c_aging_days, un etat manquant n'est plus qu'un avertissement.
   select count(distinct review_rank) into l_n from v_application_overview;
   expect_dated_coverage('les quatre etats de revue d''application sont representes', l_n, 4);

   -- 26. Les cinq rangs de revue documentaire sont representes.
   --     Le rang 4, « Due within 30 days », est le premier a glisser : son
   --     unique document passe en retard 20 jours apres le chargement.
   select count(distinct review_rank) into l_n from v_application_document_review;
   expect_dated_coverage('les cinq rangs de revue documentaire sont representes', l_n, 5);

   -- 27. Les trois niveaux de rattachement sont exerces.
   --     HOST, INSTANCE et DATABASE ne suivent pas le meme chemin dans
   --     v_application_database : un niveau absent du jeu est une branche du
   --     CASE que rien ne parcourt.
   select count(distinct entity_type) into l_n
     from ref_application_entity where active = 1;
   if l_n = 3 then
      ok('les trois niveaux de rattachement sont exerces');
   else
      fail('les trois niveaux de rattachement sont exerces',
           'seulement ' || l_n || ' niveau(x) sur 3');
   end if;

   -- 28. Aucun rattachement ne pend dans le vide.
   --     La reference est polymorphe : aucune cle etrangere ne peut la
   --     proteger, et un rattachement vers une entite disparue ne resout aucune
   --     base -- ce qui se lit exactement comme une application que personne
   --     n'a rattachee.
   select count(*) into l_n
     from ref_application_entity e
    where e.active = 1
      and not exists ( select 1 from v_entity_ancestry a
                        where a.entity_type = e.entity_type
                          and a.entity_id = e.entity_id );
   expect_zero('chaque rattachement vise une entite qui existe', l_n, 'rattachement(s) orphelin(s)');

   -- 29. LMS : une instance hors périmètre de licence n'a aucun constat.
   --     Les bases SAP portent leurs options dans la licence runtime SAP : un
   --     constat sur elles noierait les vrais écarts sous des dizaines de faux.
   select count(*) into l_n
     from fact_control_finding f
    where f.rule_code like 'ORACLE_LMS%'
      and f.entity_type = 'INSTANCE'
      and f.entity_id in ( select instance_id from v_oracle_lms_usage where in_scope = 0 );
   expect_zero('LMS : aucun constat hors perimetre de licence', l_n, 'constat(s) sur une instance SAP/FREE/PROVIDER/INCCI');

   -- 30. LMS : aucun écart sur un produit que la vue dit non utilisé.
   --     C'est le recompte Multitenant qui est visé : le script d'Oracle le
   --     signale sur toute CDB, et une CDB 19c à 3 PDB au plus n'en doit rien.
   select count(*) into l_n
     from fact_control_finding f
     join v_oracle_lms_usage u
       on u.instance_id = f.entity_id and u.product_name = f.item_key
    where f.rule_code like 'ORACLE_LMS%'
      and f.is_compliant = 0
      and u.usage_status = 'NO_USAGE';
   expect_zero('LMS : aucun ecart sur un produit non utilise', l_n, 'ecart(s) sur un produit recompte NO_USAGE');

   -- 31. LMS : le recompte Multitenant a bien servi au moins une fois.
   --     Sans cela, l'assertion 30 passerait sur un jeu sans aucune CDB.
   select count(*) into l_n
     from v_oracle_lms_usage
    where product_name = 'Multitenant'
      and reported_usage = 'CURRENT_USAGE'
      and usage_status = 'NO_USAGE';
   if l_n > 0 then
      ok('LMS : recompte Multitenant exerce');
   else
      fail('LMS : recompte Multitenant exerce', 'aucune CDB recomptee');
   end if;

   -- 32. Chiffrement réseau : la présence de la table de suivi vaut REQUESTED.
   --     Chaque base qui la porte est en écart sur le mode, même vide, et
   --     aucune autre (décision du 2026-11-11 : REQUESTED = écart sauf dérogation).
   declare
      l_snap   date;
      l_audit  pls_integer;
      l_recent pls_integer;
      l_old    pls_integer;
   begin
      select max(snapshot_date) into l_snap
        from fact_control_finding where rule_code like 'ORACLE_NETWORK%';
      select count(distinct db_name) into l_audit
        from oracle_sec_net_enc_audit where record_type = 'AUDIT';
      select count(*) into l_n
        from fact_control_finding
       where rule_code = 'ORACLE_NETWORK_ENCRYPTION_REQUIRED'
         and is_compliant = 0 and snapshot_date = l_snap;
      if l_audit > 0 and l_n = l_audit then
         ok('chiffrement reseau : ' || l_audit || ' base(s) en REQUESTED, toutes en ecart');
      else
         fail('chiffrement reseau : table de suivi = ecart sur le mode',
              l_n || ' ecart(s) pour ' || l_audit || ' base(s) portant la table');
      end if;

      -- 33. Chiffrement réseau : seuls les clients des 30 jours avant le
      --     snapshot sont des écarts. Le jeu porte aussi des clients plus
      --     anciens : sans eux, la fenêtre ne serait pas exercée.
      select count(*) into l_recent
        from ( select distinct db_name, pdb_name, username, machine, program
                 from oracle_sec_net_enc_audit
                where record_type = 'CLIENT'
                  and to_date(last_seen, 'YYYY-MM-DD HH24:MI:SS') >= l_snap - 30 );
      select count(*) into l_old
        from oracle_sec_net_enc_audit
       where record_type = 'CLIENT'
         and to_date(last_seen, 'YYYY-MM-DD HH24:MI:SS') < l_snap - 30;
      select count(*) into l_n
        from fact_control_finding
       where rule_code = 'ORACLE_NETWORK_UNENCRYPTED_CLIENT'
         and is_compliant = 0 and snapshot_date = l_snap;
      if l_old > 0 and l_recent > 0 and l_n = l_recent then
         ok('chiffrement reseau : ' || l_recent || ' client(s) recent(s) en ecart, '
            || l_old || ' ancien(s) ignore(s)');
      else
         fail('chiffrement reseau : fenetre de 30 jours',
              l_n || ' ecart(s) pour ' || l_recent || ' client(s) recent(s), '
              || l_old || ' client(s) ancien(s) dans le jeu');
      end if;
   end;

   dbms_output.put_line('T_003 : ' || l_checked || ' verification(s), ' || l_failed || ' echec(s), '
      || l_warned || ' avertissement(s).');
   if l_failed > 0 then
      raise_application_error(-20903,
         'T_003 : ' || l_failed || ' assertion(s) en echec sur le jeu de donnees de demonstration.');
   end if;
end;
/

exit
