DECLARE @command varchar(2000)
SELECT @command = 'USE [?] if exists (SELECT DB_NAME() AS DatabaseName, ''guest'' AS Database_User,[permission_name], [state_desc]
FROM sys.database_permissions WHERE [grantee_principal_id] = DATABASE_PRINCIPAL_ID(''guest'')
AND [state_desc] LIKE ''GRANT%''
AND [permission_name] = ''CONNECT''
AND DB_NAME() NOT IN (''master'',''tempdb'',''msdb''))
SELECT
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),@@Servername),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),DB_NAME()),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),[permission_name]),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(60),[state_desc]),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)
FROM sys.database_permissions
WHERE [grantee_principal_id] = DATABASE_PRINCIPAL_ID(''guest'')
AND [state_desc] LIKE ''GRANT%''
AND [permission_name] = ''CONNECT''
AND DB_NAME() NOT IN (''master'',''tempdb'',''msdb'')
ELSE
SELECT
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),@@Servername),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),DB_NAME()),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
 CHAR(34)+''no_permission''+CHAR(34)+'',''+
 CHAR(34)+''no_permission''+CHAR(34)'
EXEC sp_MSforeachdb @command
