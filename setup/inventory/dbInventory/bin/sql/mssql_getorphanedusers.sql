EXEC sp_MSforeachdb 'USE [?] If exists
(SELECT @@servername, db_name(), name
FROM sys.database_principals
WHERE sid NOT IN (SELECT sid FROM sys.server_principals)
    AND type = ''S''
    AND principal_id != 2
    AND DATALENGTH(sid) <= 28
    AND name <>''MS_DataCollectorInternalUser'')
SELECT
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),@@servername),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),db_name()),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),name),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)
FROM sys.database_principals
WHERE sid NOT IN (
        SELECT sid
        FROM sys.server_principals
        )
    AND type = ''S''
    AND principal_id != 2
    AND DATALENGTH(sid) <= 28
    AND name <>''MS_DataCollectorInternalUser''
ELSE SELECT
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),@@Servername),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),db_name()),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
 CHAR(34)+''NoOrphanedUser''+CHAR(34)'
