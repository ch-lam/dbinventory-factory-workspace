-- ============================================================================
-- V__016_oracle_network_encryption_audit.sql
-- ----------------------------------------------------------------------------
-- Score the databases left in REQUESTED network encryption, and their
-- unencrypted clients, on schemas already installed.
--
-- WHY
--   ORACLE_NETWORK_ENCRYPTION_ON only checks the collector's own session. On a
--   database in REQUESTED that session is encrypted (the collector accepts), and
--   every client that does not ask for encryption goes unseen. The DBA team
--   installs a logon trigger on those databases (setup/targets/oracle/
--   ORACLE_network_encryption_audit.sql) that records the unencrypted clients in
--   SYSTEM.HIST_SESSION_ENCRYPTION. The collect reads it into
--   oracle_sec_net_enc_audit, and two rules join the network encryption control:
--     ORACLE_NETWORK_ENCRYPTION_REQUIRED  the audit table exists = REQUESTED =
--                                         deviation unless derogated (user
--                                         decision, 2026-11-11)
--     ORACLE_NETWORK_UNENCRYPTED_CLIENT   one deviation per client seen in the
--                                         30 days before the snapshot
--   V__001, V__003 and V__005 carry the same for a fresh install.
--
-- WHY A SEPARATE SCRIPT
--   X_000 does not replay V__001 / V__003 on an installed schema. This script
--   creates the staging table only if missing and brings the reference rows
--   with MERGE: a no-op on a fresh install, safe to run twice.
--
-- ORDER (installed schema)
--   1. this script        staging table + reference rows
--   2. V__005             package (create or replace)
--   3. deploy get_info_oracle_security.sh AND load_info_oracle.sh together: the
--      loader expects oracle_sec_net_enc_audit.csv, which only the new collect
--      writes -- a loader ahead of its collect stops the nightly chain.
--   4. compute_info_all.sh, or pkg_dbinv_scoring.load_all, for the findings
-- ============================================================================

alter session set current_schema=dbinventory;

declare
   l_n pls_integer;
begin
   select count(*) into l_n from user_tables where table_name = 'ORACLE_SEC_NET_ENC_AUDIT';
   if l_n = 0 then
      execute immediate q'[
         create table oracle_sec_net_enc_audit (
            collect_id  varchar2(16),
            db_name     varchar2(50 char) not null,
            pdb_name    varchar2(128 char) not null,
            record_type varchar2(10 char) not null,
            username    varchar2(128 char),
            machine     varchar2(256 char),
            program     varchar2(128 char),
            osuser      varchar2(128 char),
            first_seen  varchar2(20 char),
            last_seen   varchar2(20 char),
            logon_count varchar2(20 char)
         )]';
   end if;
end;
/

comment on table oracle_sec_net_enc_audit is 'Unencrypted-client audit of Oracle databases left in REQUESTED network encryption mode (SYSTEM.HIST_SESSION_ENCRYPTION).';
comment on column oracle_sec_net_enc_audit.collect_id is 'Identifier for the collect run that produced this row';
comment on column oracle_sec_net_enc_audit.db_name is 'Name of the database (v$database.name).';
comment on column oracle_sec_net_enc_audit.pdb_name is 'Container holding the audit table, or NON CONTAINER.';
comment on column oracle_sec_net_enc_audit.record_type is 'AUDIT: the audit table exists in this container; CLIENT: one unencrypted client.';
comment on column oracle_sec_net_enc_audit.username is 'Database user of the unencrypted client.';
comment on column oracle_sec_net_enc_audit.machine is 'Client machine.';
comment on column oracle_sec_net_enc_audit.program is 'Client program.';
comment on column oracle_sec_net_enc_audit.osuser is 'Client operating system user.';
comment on column oracle_sec_net_enc_audit.first_seen is 'First unencrypted logon, YYYY-MM-DD HH24:MI:SS.';
comment on column oracle_sec_net_enc_audit.last_seen is 'Last unencrypted logon, YYYY-MM-DD HH24:MI:SS.';
comment on column oracle_sec_net_enc_audit.logon_count is 'Number of unencrypted logons recorded.';

merge into ref_control_rule t
using ( select 'ORACLE_NETWORK_ENCRYPTION_REQUIRED' rule_code, 'ORACLE_NETWORK_ENCRYPTION' control_code,
               'INSTANCE' entity_type, '*' item_key_label,
               'SQL*Net encryption must be REQUIRED, not REQUESTED' title,
               'The CHL target is SQLNET.ENCRYPTION_SERVER=REQUIRED. A database left in REQUESTED is declared by the presence of the unencrypted-client audit table, and is a deviation unless covered by an approved derogation, even when no client is recorded. SQL cannot read sqlnet.ora: a database in REQUESTED without the audit table is not detected by this rule.' description,
               'MEDIUM' severity
          from dual
        union all
        select 'ORACLE_NETWORK_UNENCRYPTED_CLIENT', 'ORACLE_NETWORK_ENCRYPTION',
               'INSTANCE', 'container: user@machine (program)',
               'No client may connect without network encryption',
               'One deviation per client (user, machine, program) recorded connecting over TCP without an encryption service adapter in the 30 days before the snapshot. Evaluated only where the audit table exists.',
               'HIGH'
          from dual ) s
on ( t.rule_code = s.rule_code )
when matched then update set
   t.control_code = s.control_code, t.entity_type = s.entity_type,
   t.item_key_label = s.item_key_label, t.title = s.title,
   t.description = s.description, t.severity = s.severity,
   t.origin = 'HOUSE', t.nis2_domain_code = 'CRYPTO'
when not matched then
   insert ( rule_code, control_code, entity_type, item_key_label, title, description, severity,
            origin, nis2_domain_code )
   values ( s.rule_code, s.control_code, s.entity_type, s.item_key_label, s.title, s.description,
            s.severity, 'HOUSE', 'CRYPTO' );

commit;
