-- ============================================================================
-- T__001_no_licensed_options.sql
-- ----------------------------------------------------------------------------
-- Fails when the schema uses a separately licensed Oracle option.
--
-- WHY THIS EXISTS
--   V__002 and V__010 created two document LOBs with "securefile ( compress )":
--   Advanced Compression, not licensed here. Nothing failed -- Oracle does not
--   check a licence before using a feature, it records the usage in
--   DBA_FEATURE_USAGE_STATISTICS, and an audit reads it. It was found the hard
--   way. A grep of the DDL is not enough (a default, a dbms_lob.setoptions, an
--   ALTER run by hand), so this asks the dictionary what the schema really is.
--
-- WHAT IT REFUSES
--   * LOB compression, deduplication, encryption -- per column and per stored
--     value (dbms_lob.setoptions can set them on a single row)
--   * table and index compression of any kind: the advanced kinds are the
--     Advanced Compression option, and the basic ones are not worth checking
--     edition by edition -- the schema must install on SE2 too
--   * Partitioning, In-Memory, column encryption (Advanced Security)
--   Using one of them takes an explicit decision from the owner of the
--   licences, recorded in AGENTS.md -- then this test is amended, not bypassed.
--
--   It does not look at the tablespaces: their encryption is an infrastructure
--   decision, made and licensed outside this schema.
--
-- USAGE
--   Run it at the end of every install: migrate.sh and X_000 both do.
--     sql -S -name <conn> @T__001_no_licensed_options.sql
--
--   Exits non-zero when anything is found, so it gates a deployment script.
-- ============================================================================

set serveroutput on size unlimited
set feedback off
set verify off
whenever sqlerror exit failure

declare
   l_found pls_integer := 0;
   l_n     pls_integer;

   procedure fail ( p_what varchar2, p_detail varchar2 ) is
   begin
      l_found := l_found + 1;
      dbms_output.put_line('  FAIL  ' || rpad(p_what, 40) || p_detail);
   end fail;
begin
   dbms_output.put_line('Licensed options check');
   dbms_output.put_line(rpad('-', 78, '-'));

   -- LOB columns: compression and deduplication (Advanced Compression),
   -- encryption (Advanced Security).
   for l in ( select table_name, column_name, compression, deduplication, encrypt
                from user_lobs
               where table_name not like 'BIN$%'
                 and ( compression   not in ( 'NO', 'NONE' )
                    or deduplication not in ( 'NO', 'NONE' )
                    or encrypt       not in ( 'NO', 'NONE' ) )
               order by table_name, column_name ) loop
      fail('LOB ' || l.table_name || '.' || l.column_name,
           'compression=' || l.compression || ' deduplication=' || l.deduplication
           || ' encrypt=' || l.encrypt);
   end loop;

   -- The same options, on the values already stored: the column default says
   -- nothing about a row rewritten with dbms_lob.setoptions.
   for l in ( select table_name, column_name
                from user_lobs
               where table_name not like 'BIN$%'
                 and securefile = 'YES'
               order by table_name, column_name ) loop
      execute immediate
         'declare n pls_integer := 0; '
         || 'begin '
         || '   for r in ( select "' || l.column_name || '" c from "' || l.table_name || '"'
         ||              ' where "' || l.column_name || '" is not null ) loop '
         || '      if dbms_lob.getoptions(r.c, dbms_lob.opt_compress)    <> dbms_lob.compress_off '
         || '      or dbms_lob.getoptions(r.c, dbms_lob.opt_deduplicate) <> dbms_lob.deduplicate_off then '
         || '         n := n + 1; '
         || '      end if; '
         || '   end loop; '
         || '   :n := n; '
         || 'end;'
         using out l_n;
      if l_n > 0 then
         fail('LOB ' || l.table_name || '.' || l.column_name,
              l_n || ' stored value(s) compressed or deduplicated');
      end if;
   end loop;

   for t in ( select table_name, compress_for
                from user_tables
               where dropped = 'NO' and compression = 'ENABLED'
               order by table_name ) loop
      fail('TABLE ' || t.table_name, 'compressed (' || nvl(t.compress_for, '?') || ')');
   end loop;

   for t in ( select table_name
                from user_tables
               where dropped = 'NO' and inmemory = 'ENABLED'
               order by table_name ) loop
      fail('TABLE ' || t.table_name, 'In-Memory enabled');
   end loop;

   for i in ( select index_name, compression
                from user_indexes
               where index_name not like 'BIN$%'
                 and compression not in ( 'DISABLED' )
                 and index_type not like 'LOB%'
               order by index_name ) loop
      fail('INDEX ' || i.index_name, 'compressed (' || i.compression || ')');
   end loop;

   for p in ( select 'TABLE ' || table_name what from user_part_tables
               where table_name not like 'BIN$%'
              union all
              select 'INDEX ' || index_name from user_part_indexes
               where index_name not like 'BIN$%'
              order by 1 ) loop
      fail(p.what, 'partitioned (Partitioning option)');
   end loop;

   for c in ( select table_name, column_name
                from user_encrypted_columns
               order by table_name, column_name ) loop
      fail('COLUMN ' || c.table_name || '.' || c.column_name,
           'encrypted (Advanced Security)');
   end loop;

   dbms_output.put_line(rpad('-', 78, '-'));
   if l_found > 0 then
      raise_application_error(-20906,
         l_found || ' use(s) of a licensed option - not licensed here. '
         || 'See AGENTS.md before changing anything.');
   end if;
   dbms_output.put_line('no licensed option in use');
   dbms_output.put_line('OK');
end;
/

set feedback on
