-- ============================================================================
-- X_001_cleanup_and_reinstall_all.sql
-- ----------------------------------------------------------------------------
-- Drop every object of the connected schema, then reinstall it with X_000.
-- Everything goes, ref_app_release and the data entered through the application
-- included: export it first with export_ref_data.sh (derogations are not covered).
--
-- Run connected as the schema owner (DBINVENTORY): it drops from user_*.
-- ============================================================================
set verify off serveroutput on
begin
   for to_drop in (
      select 'drop table ' || table_name || ' cascade constraints purge' as cmd
        from user_tables
       where table_name not like 'BIN$%'
         and table_name not like 'RDB$%'
         and table_name not like 'SYS_%'
         and table_name not like 'X$%'
      union all
      select 'drop ' || object_type || ' ' || object_name
        from user_objects
       where object_type not in ( 'TABLE',
                                  'INDEX',
                                  'PACKAGE BODY',
                                  'TRIGGER',
                                  'LOB' )
         and object_type not like '%LINK%'
         and object_type not like '%PARTITION%'
         and object_name not like 'BIN$%'
         and object_name not like 'ISEQ$%'
       order by 1
   ) loop
      begin
         execute immediate to_drop.cmd;
         dbms_output.put_line('Executed: ' || to_drop.cmd);
      exception
         when others then
            dbms_output.put_line('Error executing: '
                                 || to_drop.cmd
                                 || ' - ' || sqlerrm);
      end;
   end loop;
end;
/

-- reinstall all objects
@X_000_reinstall_all.sql
