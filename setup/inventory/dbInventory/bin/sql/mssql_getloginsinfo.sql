SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@SERVERNAME),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),sp.[name]),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(19),sp.create_date,120),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(19),sp.modify_date,120),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(30),LOGINPROPERTY( sp.[name], 'PasswordLastSetTime' )),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),sp.default_database_name),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),sp.default_language_name),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),sp.is_disabled),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),sl.is_policy_checked),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),sl.is_expiration_checked),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),LOGINPROPERTY( sp.[name], 'IsExpired' )),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),LOGINPROPERTY (sp.[name], 'DaysUntilExpiration' )),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),LOGINPROPERTY( sp.[name], 'IsLocked' )),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),LOGINPROPERTY( sp.[name], 'IsMustChange' )),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(19),LOGINPROPERTY( sp.[name], 'LockoutTime' ),120),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),LOGINPROPERTY( sp.[name], 'BadPasswordCount' )),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(19),LOGINPROPERTY( sp.[name], 'BadPasswordTime' ),120),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),LOGINPROPERTY( sp.[name], 'HistoryLength' )),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(85),sp.sid,1),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(5),sp.type),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+
 CASE WHEN sysadmin = 1 THEN 'sysadmin'
 WHEN securityadmin=1 THEN 'securityadmin'
 WHEN serveradmin=1 THEN 'serveradmin'
 WHEN setupadmin=1 THEN 'setupadmin'
 WHEN processadmin=1 THEN 'processadmin'
 WHEN diskadmin=1 THEN 'diskadmin'
 WHEN dbcreator=1 THEN 'dbcreator'
 WHEN bulkadmin=1 THEN 'bulkadmin'
 ELSE 'Public' END
 +'"'
FROM sys.server_principals sp
Join syslogins sysl on sysl.loginname=sp.name
LEFT OUTER JOIN sys.sql_logins sl on sl.sid = sp.sid
WHERE sp.type not in ('C', 'R')
