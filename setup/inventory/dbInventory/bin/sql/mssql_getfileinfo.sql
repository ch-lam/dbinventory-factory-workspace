SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@SERVERNAME),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),DB_Name(database_id)),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(20),file_id),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(60),type_desc),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(260),name),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(260),physical_name),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(20),(size)*8/1024),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(20),CASE (is_percent_growth) WHEN 1 THEN growth ELSE 0 END),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(20),CASE (is_percent_growth) WHEN 0 THEN growth*8/1024 ELSE 0 END),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(20),max_size),''),'"','""')+'"'
FROM sys.master_files
WHERE type in (0, 1)
