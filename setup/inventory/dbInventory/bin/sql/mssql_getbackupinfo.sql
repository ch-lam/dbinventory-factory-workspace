SELECT DISTINCT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),SERVERPROPERTY('ServerName')),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),msdb.dbo.backupset.database_name),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(19),msdb.dbo.backupset.backup_start_date,120),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(19),msdb.dbo.backupset.backup_finish_date,120),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CASE msdb..backupset.type
 WHEN 'D' THEN 'Full'
 WHEN 'I' THEN 'Incr'
 WHEN 'L' THEN 'Log'
 END,'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(20),msdb.dbo.backupset.backup_size),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'
FROM msdb.dbo.backupmediafamily
INNER JOIN msdb.dbo.backupset ON msdb.dbo.backupmediafamily.media_set_id = msdb.dbo.backupset.media_set_id
-- 7-day window: the model only consumes the last Full backup per database, and the
-- interval/duration analytics need a few days at most. 31 days multiplied the volume
-- by ~4 for no consumer (log backups dominate the row count).
WHERE (CONVERT(datetime, msdb.dbo.backupset.backup_start_date, 102) >= GETDATE() - 7)
