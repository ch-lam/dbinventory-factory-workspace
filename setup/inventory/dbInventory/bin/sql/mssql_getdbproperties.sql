SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@servername),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),name),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),is_auto_close_on),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),is_trustworthy_on),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'
FROM sys.databases
GO
