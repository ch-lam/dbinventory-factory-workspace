-- Quoting CSV : CHAR(34) = caractere guillemet, evite l'echappement imbrique
-- dans le SQL dynamique de sp_MSforeachdb.
-- Convention : CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(N),expr),'') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)

DECLARE @command varchar(4000)
SELECT @command = 'USE [?] if exists (SELECT db_name() AS Database_Name, ''symmetric'',name AS Key_Name,algorithm_desc FROM sys.symmetric_keys WHERE db_id() > 4)
SELECT
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),@@servername),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),db_name()),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
 CHAR(34)+''symmetric''+CHAR(34)+'',''+
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),name),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),algorithm_desc),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)
FROM sys.symmetric_keys WHERE db_id() > 4
ELSE
SELECT
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),@@Servername),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),DB_NAME()),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
 CHAR(34)+''symmetric''+CHAR(34)+'',''+
 CHAR(34)+''NoSymKeyFound''+CHAR(34)+'',''+
 CHAR(34)+''NotFound''+CHAR(34)'
EXEC sp_MSforeachdb @command

DECLARE @command2 varchar(4000)
SELECT @command2 = 'USE [?] if exists (SELECT db_name() AS Database_Name, ''asymmetric'',name AS Key_Name, key_length FROM sys.asymmetric_keys WHERE db_id() > 4)
SELECT
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),@@servername),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),db_name()),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
 CHAR(34)+''asymmetric''+CHAR(34)+'',''+
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),name),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),key_length),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)
FROM sys.asymmetric_keys WHERE db_id() > 4
ELSE
SELECT
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),@@Servername),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),DB_NAME()),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
 CHAR(34)+''asymmetric''+CHAR(34)+'',''+
 CHAR(34)+''NoAsymKeyFound''+CHAR(34)+'',''+
 CHAR(34)+''NotFound''+CHAR(34)'
EXEC sp_MSforeachdb @command2

SELECT
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),@@servername),'') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+','+
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),db.name),'') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+','+
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(60),dm.encryptor_type),'') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+','+
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(60),dm.key_algorithm),'') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+','+
 CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),dm.key_length),'') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)
FROM sys.databases db LEFT OUTER JOIN sys.dm_database_encryption_keys dm ON db.database_id = dm.database_id
WHERE db.name not in ('master','tempdb','model','msdb') and db.is_encrypted=1;
