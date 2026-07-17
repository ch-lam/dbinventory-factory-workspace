SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@Servername),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),name),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(20),CAST(value as int)),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(20),CAST(value_in_use as int)),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'
FROM sys.configurations
WHERE name in  ('Ad Hoc Distributed Queries','clr enabled','cross db ownership chaining','Database Mail XPs','Ole Automation Procedures',
'remote access','scan for startup procs','xp_cmdshell','default trace enabled','clr strict security');
GO
SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@Servername),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),name),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(20),CAST(value as int)),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(20),CAST(value_in_use as int)),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'
FROM sys.configurations
WHERE name = 'remote admin connections' AND SERVERPROPERTY('IsClustered') = 0;
GO
