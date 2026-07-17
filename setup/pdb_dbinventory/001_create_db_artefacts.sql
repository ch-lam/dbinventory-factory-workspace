--
-- Install dbInventory artefacts (tablespace, schema, objects ... )
--

-- standard tablespace creation
create tablespace dbinventory_tbs;

-- standard user creation
create user dbinventory identified by "uEjAYCnXhgbw3IputZCJbeMFKwGBvi"
            profile C##SERVICE_PROFILE 
            default tablespace dbinventory_tbs
            account unlock;

alter user dbinventory quota unlimited on dbinventory_tbs;

-- grant the required privileges to the dbInventory user
grant
   create session,resource to dbinventory;