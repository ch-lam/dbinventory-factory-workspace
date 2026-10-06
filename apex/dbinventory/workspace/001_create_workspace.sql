--
-- Create the DBINVENTORY APEX workspace and its developer accounts.
--
-- Prerequisites: APEX installed in the PDB (setup/pdb_dbinventory), and the
-- DBINVENTORY schema created (setup/pdb_dbinventory/001_create_db_artefacts.sql).
-- Run connected as SYS on the PDB.
--
-- Passwords are asked at run time and never written here. They used to be, in
-- clear, in setup/pdb_dbinventory/002_create_apex_artefacts.sql: those values
-- are still in the git history and must be considered disclosed.
--

set verify off

accept pwd_goepfert char prompt 'Initial APEX password for goepfert: ' hide
accept pwd_lamchr02 char prompt 'Initial APEX password for lamchr02: ' hide

begin
    -- Grant all the needed privileges for an APEX workspace to DBINVENTORY user
   for prv in (
      select privilege
        from sys.dba_sys_privs
       where grantee = 'APEX_GRANTS_FOR_NEW_USERS_ROLE'
   ) loop
      execute immediate 'grant '
                        || prv.privilege
                        || ' to DBINVENTORY';
   end loop;
   apex_instance_admin.add_workspace(
      p_workspace      => 'DBINVENTORY',
      p_primary_schema => 'DBINVENTORY'
   );
   apex_util.set_workspace(p_workspace => 'DBINVENTORY');
   apex_util.create_user(
      p_user_name                    => 'goepfert',
      p_web_password                 => '&pwd_goepfert',
      p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
      p_email_address                => 'goepfert.nelly@chl.lu',
      p_default_schema               => 'DBINVENTORY',
      p_change_password_on_first_use => 'Y'
   );
   apex_util.create_user(
      p_user_name                    => 'lamchr02',
      p_web_password                 => '&pwd_lamchr02',
      p_developer_privs              => 'ADMIN:CREATE:DATA_LOADER:EDIT:HELP:MONITOR:SQL',
      p_email_address                => 'lambert.christophe@chl.lu',
      p_default_schema               => 'DBINVENTORY',
      p_change_password_on_first_use => 'Y'
   );
   -- mandatory after user creation.
   Commit;
end;
/

undefine pwd_goepfert
undefine pwd_lamchr02
