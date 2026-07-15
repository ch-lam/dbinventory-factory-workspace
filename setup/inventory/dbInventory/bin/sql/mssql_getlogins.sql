SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@servername),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),l.[name]),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(20),l.principal_id),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),IS_SRVROLEMEMBER('sysadmin',name)),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),l.is_policy_checked),''),'"','""')+'"'+','+
 '"'+'sysadmin membership'+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),l.is_expiration_checked),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),l.is_disabled),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(19),l.create_date,120),''),'"','""')+'"'
FROM sys.sql_logins AS l
UNION ALL
SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@Servername),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),l.[name]),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(20),l.principal_id),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),IS_SRVROLEMEMBER('sysadmin',name)),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),l.is_policy_checked),''),'"','""')+'"'+','+
 '"'+'CONTROL SERVER'+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),l.is_expiration_checked),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),l.is_disabled),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(19),l.create_date,120),''),'"','""')+'"'
FROM sys.sql_logins AS l
JOIN sys.server_permissions AS p
ON l.principal_id = p.grantee_principal_id
WHERE p.type = 'CL' AND p.state IN ('G', 'W')
