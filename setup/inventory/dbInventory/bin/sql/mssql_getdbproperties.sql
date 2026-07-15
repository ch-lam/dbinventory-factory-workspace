SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@servername),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),name),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),is_auto_close_on),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),is_trustworthy_on),''),'"','""')+'"'
FROM sys.databases
GO
