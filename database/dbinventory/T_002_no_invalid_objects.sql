-- ============================================================================
-- T_002_no_invalid_objects.sql
-- ----------------------------------------------------------------------------
-- Fails when any object in the schema carries a compilation error.
--
-- WHY THIS EXISTS
--   A package body that fails to compile does not stop an install. SQLcl prints
--   the errors, carries on with the next statement, and the run ends on
--   "Commit complete." -- so a reinstall reports success while leaving an API
--   that raises ORA-06508 the first time anything calls it.
--
--   That happened: pkg_dbinv_exception compiled with errors at a site running an
--   older Oracle release, and the install said nothing. It was found by a human
--   reading the scrollback, weeks later. This turns that into an exit code.
--
--   The specific bug was a PL/SQL BOOLEAN read inside a SQL statement. SQL had no
--   boolean type before 23ai, so it compiled on the 23ai development database and
--   failed everywhere older -- the development environment being MORE permissive
--   than the target is the nastiest shape a portability bug can take, because
--   every local check passes. This test does not know about booleans; it does not
--   need to. It asks the database whether anything is broken.
--
-- USAGE
--   Run it at the end of every install. X_000 does.
--     sql -S -name <conn> @T_002_no_invalid_objects.sql
--
--   Exits non-zero when anything is invalid, so it gates a deployment script.
-- ============================================================================

set serveroutput on size unlimited
set feedback off
set verify off
whenever sqlerror exit failure

declare
   l_broken pls_integer := 0;
begin
   dbms_output.put_line('Compilation check');
   dbms_output.put_line(rpad('-', 78, '-'));

   -- Errors first, with their text: an invalid object tells you that something is
   -- wrong, user_errors tells you what.
   for e in ( select name, type, line, position, text
                from user_errors
               where attribute = 'ERROR'
               order by type, name, sequence ) loop
      l_broken := l_broken + 1;
      dbms_output.put_line('  FAIL  ' || rpad(e.type || ' ' || e.name, 40)
                           || 'line ' || e.line || '/' || e.position);
      dbms_output.put_line('        ' || substr(e.text, 1, 160));
   end loop;

   -- An object can be INVALID without holding errors -- typically because
   -- something it depends on changed and it has simply not been recompiled yet.
   -- Reported separately, because the cure is different: recompile, do not debug.
   for o in ( select object_type, object_name
                from user_objects
               where status <> 'VALID'
                 and object_name not in ( select name from user_errors where attribute = 'ERROR' )
               order by object_type, object_name ) loop
      l_broken := l_broken + 1;
      dbms_output.put_line('  FAIL  ' || rpad(o.object_type || ' ' || o.object_name, 40)
                           || 'INVALID, no error recorded - needs recompiling');
   end loop;

   dbms_output.put_line(rpad('-', 78, '-'));
   if l_broken > 0 then
      raise_application_error(-20902,
         l_broken || ' object(s) failed to compile - the install did NOT succeed, '
         || 'whatever the last line of the log says.');
   end if;
   dbms_output.put_line('every object compiled');
   dbms_output.put_line('OK');
end;
/

set feedback on
