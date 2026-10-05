# Installation of PDB DBINVENTORY

Prerequisites :

Standard container (CDB) must be available.

```bash
# create new PDB for the dbInventory and dbMonitoring tools
# 
create_PDB.sh -m create -d C19NPRD1 -p PDBT_DBINVENTORY -s TST
```

# check the service exists in the PDB (with oracle restarts and create_PDB.sh, it should be OK, if not, create service in PDB) 
```sql
-- connected in DBINVENTORY pdb 
select name from v$services where name like 'DBINVENTORY%';

-- if it doesnt exists
exec dbms_service.create_service('DBINVENTORY_TST', network_name => 'DBINVENTORY_TST' );
exec dbms_service.start_service('DBINVENTORY_TST');
-- and make it available when when DB reboots
alter pluggable database pdbt_dbinventory save state ;
```

Install APEX
```bash
# Connectected on the newly created PDB as SYS, and on the root dir apex installation
SQL> @apexins.sql SYSAUX SYSAUX TEMP /i/i26.1.0/
SQL> exit;

# re-connectected on the newly created PDB as SYS, and on the root dir apex installation
SQL> @apxchpwd.sql

Enter the administrator's username [ADMIN]
User "ADMIN" does not yet exist and will be created.
Enter ADMIN's email [ADMIN] IT-DBA@chl.lu
Enter ADMIN's password [] FMR1M2FIRjK3xadEX:yggwiCHnN8xhs
Created instance administrator ADMIN.

SQL> exit;
```

Set parameters for new instance (smtp) and ACLs to allow SMTP server access and LDAP access.
connected as SYS on PDB_DBINVENTORY on database server (need rdbms scripts)

```bash

-- ACL for LDAP
begin 
  dbms_network_acl_admin.create_acl (  
    acl         => 'utl_ldap.xml',  
    description => 'Allow LDAP to be accessed (LDAP/LDAPS)',
    principal   => 'PUBLIC',  
    is_grant    => TRUE,  
    privilege   => 'connect' 
    );  
    commit;  
end;
/

begin 
  dbms_network_acl_admin.add_privilege (  
  acl       => 'utl_ldap.xml',  
  principal => 'PUBLIC',  
  is_grant  => TRUE,  
  privilege => 'resolve' 
  );  
  commit;  
end;
/
begin 
  -- LDAP
  dbms_network_acl_admin.assign_acl(  
  acl  => 'utl_ldap.xml',  
  host => 'ad.chl.lu',
  lower_port => 389,
  upper_port => 389
  );
  -- LDAPS
  dbms_network_acl_admin.assign_acl(  
  acl  => 'utl_ldap.xml',  
  host => 'ad.chl.lu',
  lower_port => 636,
  upper_port => 636
  );  
  commit;  
end;
/

-- Install UTL MAIL
@$ORACLE_HOME/rdbms/admin/utlmail.sql
@$ORACLE_HOME/rdbms/admin/prvtmail.plb

alter system set smtp_out_server='gwia.chl.lu' scope = BOTH sid = '*';

-- ACL for MAIL
begin 
  dbms_network_acl_admin.create_acl (  
    acl         => 'utl_mail.xml',  
    description => 'Allow mail to be send',  
    principal   => 'PUBLIC',  
    is_grant    => TRUE,  
    privilege   => 'connect' 
    );  
    commit;  
end;
/

begin 
  dbms_network_acl_admin.add_privilege (  
  acl       => 'utl_mail.xml',  
  principal => 'PUBLIC',  
  is_grant  => TRUE,  
  privilege => 'resolve' 
  );  
  commit;  
end;
/

begin 
  dbms_network_acl_admin.assign_acl(  
  acl  => 'utl_mail.xml',  
  host => 'gwia.chl.lu' 
  );  
  commit;  
end;
/

BEGIN
  UTL_MAIL.send(sender     => 'lambert.christophe@chl.lu',
                recipients => 'lambert.christophe@chl.lu',
                cc         => NULL,
                bcc        => NULL,
                subject    => 'UTL_MAIL Test on PDBT_DBINVENTORY',
                message    => 'If you get this message, installation of UTL_MAIL in PDBT_DBINVENTORY is fully functionnal !');
EXCEPTION WHEN OTHERS THEN
  DBMS_OUTPUT.PUT_LINE('ERROR OCCURED IN UTL_MAIL.SEND : '|| SQLERRM );
END;
/
```

Setup DBINVENTORY schema, workspace and application

```bash
# Connectected on the newly created PDB as SYS, and on the root dir of the dbInventory repository

SQL> cd setup/pdb_dbinventory

SQL> @001_create_db_artefacts.sql

SQL> exit;
```

The workspace, the schema objects and the application are then installed in
that order, as described in `apex/dbinventory/README.md`.

Configure access to Openrouter for AI models

```sql

-- Connectected on the newly created PDB as SYS
-- Create Openrouter ACL Access for APEX applications

SQL> 

begin
   dbms_network_acl_admin.append_host_ace(
      host       => 'openrouter.ai',
      lower_port => 443,
      upper_port => 443,
      ace        => xs$ace_type(
         privilege_list => xs$name_list('connect'),
         principal_name => 'DBINVENTORY',
         principal_type => xs_acl.ptype_db
      )
   );
   dbms_network_acl_admin.append_host_ace(
      host       => 'openrouter.ai',
      lower_port => 443,
      upper_port => 443,
      ace        => xs$ace_type(
         privilege_list => xs$name_list('connect'),
         principal_name => 'APEX_PUBLIC_USER',
         principal_type => xs_acl.ptype_db
      )
   );
  -- mandatory for APEX "developer" mode testing and configuration, needs to be adapted if APEX version changes
   dbms_network_acl_admin.append_host_ace(
      host       => 'openrouter.ai',
      lower_port => 443,
      upper_port => 443,
      ace        => xs$ace_type(
         privilege_list => xs$name_list('connect'),
         principal_name => 'APEX_260100',
         principal_type => xs_acl.ptype_db
      )
   );
end;
/

SQL> exit;
```

