 IF (OBJECT_ID('tempdb..#invalidlogins') IS NOT NULL)
BEGIN
DROP TABLE #invalidlogins
END
CREATE TABLE #invalidlogins(
ACCTSID VARBINARY(85)
, NTLOGIN SYSNAME)
INSERT INTO #invalidlogins
EXEC sys.sp_validatelogins
SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@servername),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(85),IL.ACCTSID,1),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),IL.NTLogin),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),SP.is_disabled),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(19),SP.modify_date,120),''),'"','""')+'"'+','+
 '"'+REPLACE(CONVERT(varchar(19),getdate(),120),'"','""')+'"'
FROM #invalidlogins as IL
join sys.server_principals as SP on IL.NTLOGIN = SP.Name
order by IL.NTLogin
