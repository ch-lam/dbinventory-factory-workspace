/*
** ORACLE_network_encryption_audit.sql
** ---------------------------------------------------------------------------
** Suivi des clients qui se connectent SANS chiffrement réseau, sur une base que
** l'on ne peut pas passer en SQLNET.ENCRYPTION_SERVER = REQUIRED et qui reste
** donc en REQUESTED. Sur une base en REQUIRED, ce script est inutile : une
** connexion non chiffrée y est refusée avant même l'ouverture de session.
**
** dbInventory lit la table créée ici :
**   - sa PRÉSENCE déclare la base en REQUESTED, ce qui est un écart sauf
**     dérogation (règle ORACLE_NETWORK_ENCRYPTION_REQUIRED) ;
**   - chaque client vu sur les 30 derniers jours est un écart
**     (règle ORACLE_NETWORK_UNENCRYPTED_CLIENT).
** Une table vide sur 30 jours = plus aucun client à corriger : la base peut
** passer en REQUIRED, puis on désinstalle (bloc en fin de script).
**
** OÙ LE JOUER
**   En SYS, dans CHAQUE conteneur où arrivent les sessions applicatives :
**   chaque PDB concernée pour un CDB, la base elle-même pour un non-CDB.
**   Un trigger de PDB se déclenche à coup sûr pour les connexions à cette PDB ;
**   le comportement d'un trigger posé dans CDB$ROOT pour les connexions aux PDB
**   n'a pas été vérifié. La collecte lit la table dans tous les conteneurs où
**   elle existe, racine comprise.
**     sqlplus / as sysdba
**     SQL> alter session set container = <PDB>;
**     SQL> @ORACLE_network_encryption_audit.sql
**
** CE QUI CHANGE PAR RAPPORT À LA PREMIÈRE VERSION (2026-11-11)
**   1. Droits DIRECTS à SYSTEM sur v_$session_connect_info et v_$session : dans
**      un trigger, les rôles (DBA) ne comptent pas. Sans eux le trigger est
**      INVALIDE, et un trigger de logon invalide BLOQUE les connexions de tous
**      les comptes non DBA (ORA-04098). Le trigger est donc créé DÉSACTIVÉ,
**      contrôlé, et activé seulement s'il est valide.
**   2. Seules les connexions réseau en TCP sont suivies. Bequeath et IPC ne
**      passent pas par le réseau ; TCPS est chiffré par TLS et n'affiche pas
**      d'adaptateur natif : les suivre ferait des faux positifs.
**   3. Critère de chiffrement = « Encryption service adapter », le même que la
**      collecte. La ligne « Encryption service for Linux » est présente MÊME
**      SANS chiffrement : '%encryption%' insensible à la casse la prendrait.
**   4. Une ligne par client (utilisateur, machine, programme, utilisateur OS)
**      avec première/dernière connexion et compteur, au lieu d'une ligne par
**      connexion : la table reste petite même face à un pool de connexions.
**   5. Valeurs tronquées à la taille des colonnes : un MODULE de 64 caractères
**      dans une colonne de 48 faisait échouer l'insertion, avalée en silence
**      par le WHEN OTHERS -- le client non chiffré disparaissait.
**   6. Transaction autonome : la ligne est écrite même si la session de
**      l'application annule son propre travail.
**
** Droit de lecture pour la collecte : C##MONITORING (CDB) ou MONITORING
** (non-CDB), selon le compte qui existe.
*/
whenever sqlerror exit failure
set serveroutput on

prompt == Conteneur courant :
select sys_context('USERENV', 'CON_NAME') as conteneur from dual;

-- ---------------------------------------------------------------------------
-- 1. Droits directs de SYSTEM (voir point 1 de l'en-tête)
-- ---------------------------------------------------------------------------
grant select on sys.v_$session_connect_info to system;
grant select on sys.v_$session to system;

-- ---------------------------------------------------------------------------
-- 2. Table de suivi
-- ---------------------------------------------------------------------------
-- Une ancienne table au format « une ligne par connexion » (première version)
-- n'est pas reprise : le script s'arrête et demande de la renommer.
declare
   l_tab pls_integer;
   l_new pls_integer;
begin
   select count(*) into l_tab from dba_tables
    where owner = 'SYSTEM' and table_name = 'HIST_SESSION_ENCRYPTION';
   select count(*) into l_new from dba_tab_columns
    where owner = 'SYSTEM' and table_name = 'HIST_SESSION_ENCRYPTION' and column_name = 'LOGON_COUNT';

   if l_tab = 1 and l_new = 0 then
      raise_application_error(-20001,
         'SYSTEM.HIST_SESSION_ENCRYPTION existe au format de la premiere version (une ligne par '
         || 'connexion). La renommer (alter table system.hist_session_encryption rename to '
         || 'hist_session_encryption_v1), puis relancer ce script.');
   elsif l_tab = 0 then
      execute immediate q'[
         create table system.hist_session_encryption (
            username    varchar2(128) not null,
            machine     varchar2(256) not null,
            program     varchar2(128) not null,
            osuser      varchar2(128) not null,
            first_seen  date          not null,
            last_seen   date          not null,
            logon_count number        not null,
            last_banner varchar2(4000),
            constraint hist_session_encryption_pk
               primary key ( username, machine, program, osuser )
         )]';
      dbms_output.put_line('Table SYSTEM.HIST_SESSION_ENCRYPTION creee.');
   else
      dbms_output.put_line('Table SYSTEM.HIST_SESSION_ENCRYPTION deja en place, conservee.');
   end if;
end;
/

comment on table system.hist_session_encryption is
   'CHL : clients connectes sans chiffrement reseau (base en SQLNET.ENCRYPTION_SERVER=REQUESTED). Une ligne par client. Alimentee par SYSTEM.TRG_NETWORK_ENCRYPTION_AUDIT, lue par dbInventory. Geree par l''equipe DBA.';

-- ---------------------------------------------------------------------------
-- 3. Trigger, créé DÉSACTIVÉ (voir point 1)
-- ---------------------------------------------------------------------------
create or replace trigger system.trg_network_encryption_audit
   after logon on database
   disable
declare
   pragma autonomous_transaction;
   l_sid       number := to_number(sys_context('USERENV', 'SID'));
   l_encrypted pls_integer;
   l_username  varchar2(128);
   l_machine   varchar2(256);
   l_program   varchar2(128);
   l_osuser    varchar2(128);
   l_banner    varchar2(4000);
begin
   -- Point 2 : TCP seulement.
   if nvl(lower(sys_context('USERENV', 'NETWORK_PROTOCOL')), '-') <> 'tcp' then
      return;
   end if;

   -- Point 3 : un adaptateur d'algorithme négocié, et rien d'autre.
   select count(*) into l_encrypted
     from v$session_connect_info
    where sid = l_sid
      and network_service_banner like '%Encryption service adapter%';
   if l_encrypted > 0 then
      return;
   end if;

   select substr(nvl(s.username, sys_context('USERENV', 'SESSION_USER')), 1, 128),
          substr(nvl(s.machine, '-'), 1, 256),
          substr(nvl(s.program, nvl(s.module, '-')), 1, 128),
          substr(nvl(s.osuser, '-'), 1, 128)
     into l_username, l_machine, l_program, l_osuser
     from v$session s
    where s.sid = l_sid;

   select substr(min(network_service_banner), 1, 4000) into l_banner
     from v$session_connect_info
    where sid = l_sid
      and network_service_banner like '%Protocol Adapter%';

   -- Point 4 : une ligne par client.
   merge into system.hist_session_encryption t
   using ( select l_username username, l_machine machine,
                  l_program program, l_osuser osuser from dual ) s
      on ( t.username = s.username and t.machine = s.machine
           and t.program = s.program and t.osuser = s.osuser )
   when matched then update set
      t.last_seen = sysdate, t.logon_count = t.logon_count + 1, t.last_banner = l_banner
   when not matched then insert
      ( username, machine, program, osuser, first_seen, last_seen, logon_count, last_banner )
      values ( s.username, s.machine, s.program, s.osuser, sysdate, sysdate, 1, l_banner );
   commit;
exception
   -- Un suivi ne doit jamais empêcher une connexion.
   when others then
      rollback;
end;
/

-- Contrôle : on n'active qu'un trigger valide.
declare
   l_status varchar2(10);
begin
   select status into l_status from dba_objects
    where owner = 'SYSTEM' and object_name = 'TRG_NETWORK_ENCRYPTION_AUDIT' and object_type = 'TRIGGER';
   if l_status <> 'VALID' then
      raise_application_error(-20002,
         'Trigger SYSTEM.TRG_NETWORK_ENCRYPTION_AUDIT INVALIDE : laisse DESACTIVE pour ne pas '
         || 'bloquer les connexions. Voir : show errors trigger system.trg_network_encryption_audit');
   end if;
   execute immediate 'alter trigger system.trg_network_encryption_audit enable';
   dbms_output.put_line('Trigger valide et active.');
end;
/

-- ---------------------------------------------------------------------------
-- 4. Lecture pour la collecte dbInventory
-- ---------------------------------------------------------------------------
declare
   l_granted pls_integer := 0;
begin
   for u in ( select username from dba_users where username in ( 'C##MONITORING', 'MONITORING' ) ) loop
      execute immediate 'grant select on system.hist_session_encryption to ' || u.username;
      dbms_output.put_line('Lecture accordee a ' || u.username || '.');
      l_granted := l_granted + 1;
   end loop;
   if l_granted = 0 then
      dbms_output.put_line('ATTENTION : ni C##MONITORING ni MONITORING ici, la collecte ne pourra pas lire la table.');
   end if;
end;
/

-- ---------------------------------------------------------------------------
-- 5. Sessions déjà ouvertes (best effort)
-- ---------------------------------------------------------------------------
-- Un pool de connexions ouvert avant la pose du trigger ne se reconnecte
-- parfois pas avant des semaines : on relève tout de suite les sessions réseau
-- en cours sans adaptateur de chiffrement. Le protocole d'une AUTRE session
-- n'est pas lisible directement ; les sessions TLS sont écartées sur leur
-- bannière (SSL / TLS), ce qui est une approximation. Le trigger reste la
-- source qui fait foi.
merge into system.hist_session_encryption t
using ( select substr(nvl(s.username, '-'), 1, 128) username,
               substr(nvl(s.machine, '-'), 1, 256) machine,
               substr(nvl(s.program, nvl(s.module, '-')), 1, 128) program,
               substr(nvl(s.osuser, '-'), 1, 128) osuser,
               count(*) sessions,
               substr(min(p.network_service_banner), 1, 4000) banner
          from v$session s
          join v$session_connect_info p
            on p.sid = s.sid and p.serial# = s.serial#
           and p.network_service_banner like 'TCP/IP%Protocol Adapter%'
         where s.type <> 'BACKGROUND'
           and not exists ( select 1 from v$session_connect_info c
                             where c.sid = s.sid and c.serial# = s.serial#
                               and ( c.network_service_banner like '%Encryption service adapter%'
                                     or upper(c.network_service_banner) like '%SSL%'
                                     or upper(c.network_service_banner) like '%TLS%' ) )
         group by substr(nvl(s.username, '-'), 1, 128), substr(nvl(s.machine, '-'), 1, 256),
                  substr(nvl(s.program, nvl(s.module, '-')), 1, 128), substr(nvl(s.osuser, '-'), 1, 128) ) s
   on ( t.username = s.username and t.machine = s.machine
        and t.program = s.program and t.osuser = s.osuser )
when matched then update set t.last_seen = sysdate
when not matched then insert
   ( username, machine, program, osuser, first_seen, last_seen, logon_count, last_banner )
   values ( s.username, s.machine, s.program, s.osuser, sysdate, sysdate, s.sessions, s.banner );
commit;

prompt == Clients non chiffres releves a l'installation :
select username, machine, program, osuser, logon_count
  from system.hist_session_encryption
 order by last_seen desc;

/*
** ---------------------------------------------------------------------------
** DÉSINSTALLATION, une fois la base passée en REQUIRED (dans chaque conteneur).
** dbInventory voit alors la base en REQUIRED et lève l'écart de mode.
** ---------------------------------------------------------------------------
drop trigger system.trg_network_encryption_audit;
drop table system.hist_session_encryption purge;
*/
