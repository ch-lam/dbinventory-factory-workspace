if exists (SELECT @@servername as Servername, pr.[name], pe.[permission_name], pe.[state_desc]
FROM sys.server_principals pr
JOIN sys.server_permissions pe
ON pr.principal_id = pe.grantee_principal_id
WHERE pr.name like 'BUILTIN%'
UNION
SELECT @@servername as Servername, pr.[name] AS LocalGroupName, pe.[permission_name], pe.[state_desc]
FROM sys.server_principals pr
JOIN sys.server_permissions pe
ON pr.[principal_id] = pe.[grantee_principal_id]
WHERE pr.[type_desc] = 'WINDOWS_GROUP'
AND pr.[name] like CAST(SERVERPROPERTY('MachineName') AS nvarchar) + '%')
SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@servername),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),pr.[name]),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),pe.[permission_name]),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(60),pe.[state_desc]),''),'"','""')+'"'
FROM sys.server_principals pr
JOIN sys.server_permissions pe
ON pr.principal_id = pe.grantee_principal_id
WHERE pr.name like 'BUILTIN%'
UNION
SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@servername),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),pr.[name]),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),pe.[permission_name]),''),'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(60),pe.[state_desc]),''),'"','""')+'"'
FROM sys.server_principals pr
JOIN sys.server_permissions pe
ON pr.[principal_id] = pe.[grantee_principal_id]
WHERE pr.[type_desc] = 'WINDOWS_GROUP'
AND pr.[name] like CAST(SERVERPROPERTY('MachineName') AS nvarchar) + '%';
ELSE
SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@SERVERNAME),''),'"','""')+'"'+','+
 '"'+'NoGroup'+'"'+','+
 '"'+'NoPerm'+'"'+','+
 '"'+'NoState'+'"'
