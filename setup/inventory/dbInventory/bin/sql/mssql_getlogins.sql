SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@servername),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),l.[name]),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(20),l.principal_id),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),IS_SRVROLEMEMBER('sysadmin',name)),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),l.is_policy_checked),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+'sysadmin membership'+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),l.is_expiration_checked),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),l.is_disabled),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(19),l.create_date,120),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'
FROM sys.sql_logins AS l
UNION ALL
SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@Servername),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),l.[name]),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(20),l.principal_id),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),IS_SRVROLEMEMBER('sysadmin',name)),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),l.is_policy_checked),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+'CONTROL SERVER'+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),l.is_expiration_checked),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),l.is_disabled),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(19),l.create_date,120),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'
FROM sys.sql_logins AS l
JOIN sys.server_permissions AS p
ON l.principal_id = p.grantee_principal_id
WHERE p.type = 'CL' AND p.state IN ('G', 'W')
