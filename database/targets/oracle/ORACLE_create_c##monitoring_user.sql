/*
** Create MONITORING user for Zabbix collector to be deployed in all oracle databases
** (it should be part of post deployment template after a new cdb/pdb, this script if for 
**  manual deployment only and documentation purposes).
*/
-- create monitoring profile to avoid password lock
create profile C##MONITORING limit PASSWORD_LIFE_TIME UNLIMITED;

-- Create user and privs.
create user C##MONITORING identified by "F5t9TAcbjLTzhBNE69YeYBTx1BLgOZ" -- use secret server to retreive correct value.
       profile C##MONITORING;
grant create session to C##MONITORING;
grant SELECT_CATALOG_ROLE to C##MONITORING;

-- create view as X$ cannot be granted directly, then grant select on view
create view vw_x$dbgalertext as select * from sys.x$dbgalertext;
grant select on vw_x$dbgalertext to C##MONITORING;

-- In case C##MONITORING user password expired (prior to profile creation)
create profile C##MONITORING limit PASSWORD_LIFE_TIME UNLIMITED;
alter user C##MONITORING profile C##MONITORING;
alter user C##MONITORING identified by "*******************************" account unlock;

