if exists (SELECT * FROM master.sys.server_permissions
WHERE (grantee_principal_id = SUSER_SID(N'public') and state_desc LIKE 'GRANT%')
AND NOT (state_desc = 'GRANT' and [permission_name] = 'VIEW ANY DATABASE' and class_desc = 'SERVER')
AND NOT (state_desc = 'GRANT' and [permission_name] = 'CONNECT' and class_desc = 'ENDPOINT' and major_id = 2)
AND NOT (state_desc = 'GRANT' and [permission_name] = 'CONNECT' and class_desc = 'ENDPOINT' and major_id = 3)
AND NOT (state_desc = 'GRANT' and [permission_name] = 'CONNECT' and class_desc = 'ENDPOINT' and major_id = 4)
AND NOT (state_desc = 'GRANT' and [permission_name] = 'CONNECT' and class_desc = 'ENDPOINT' and major_id = 5))
SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@servername),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),db_name()),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),SUSER_NAME(grantee_principal_id)),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),permission_name),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(60),state_desc),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'
FROM master.sys.server_permissions
WHERE (grantee_principal_id = SUSER_SID(N'public') and state_desc LIKE 'GRANT%')
AND NOT (state_desc = 'GRANT' and [permission_name] = 'VIEW ANY DATABASE' and class_desc = 'SERVER')
AND NOT (state_desc = 'GRANT' and [permission_name] = 'CONNECT' and class_desc = 'ENDPOINT' and major_id = 2)
AND NOT (state_desc = 'GRANT' and [permission_name] = 'CONNECT' and class_desc = 'ENDPOINT' and major_id = 3)
AND NOT (state_desc = 'GRANT' and [permission_name] = 'CONNECT' and class_desc = 'ENDPOINT' and major_id = 4)
AND NOT (state_desc = 'GRANT' and [permission_name] = 'CONNECT' and class_desc = 'ENDPOINT' and major_id = 5);
ELSE
SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@Servername),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),DB_NAME()),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+'Public'+'"'+','+
 '"'+'OnlyDefaultPermission'+'"'+','+
 '"'+'OnlyDefaultPermission'+'"'
