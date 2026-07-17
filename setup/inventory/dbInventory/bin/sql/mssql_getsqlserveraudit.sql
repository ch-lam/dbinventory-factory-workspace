if exists (SELECT @@servername as servername,
S.name AS 'Audit Name'
, S.is_state_enabled AS 'Audit Enabled'
, S.type_desc AS 'Write Location'
, SA.name AS 'Audit Specification Name'
, SA.is_state_enabled as 'Audit Specification Enabled'
, SAD.audit_action_name
, SAD.audited_result
FROM sys.server_audit_specification_details AS SAD
JOIN sys.server_audit_specifications AS SA
ON SAD.server_specification_id = SA.server_specification_id
JOIN sys.server_audits AS S
ON SA.audit_guid = S.audit_guid
WHERE SAD.audit_action_id ='CNAU')
SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@servername),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),S.name),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),S.is_state_enabled),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(60),S.type_desc),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),SA.name),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),SA.is_state_enabled),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(60),SAD.audit_action_name),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),SAD.audited_result),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'
FROM sys.server_audit_specification_details AS SAD
JOIN sys.server_audit_specifications AS SA
ON SAD.server_specification_id = SA.server_specification_id
JOIN sys.server_audits AS S
ON SA.audit_guid = S.audit_guid
WHERE SAD.audit_action_id ='CNAU'
ELSE
SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@SERVERNAME),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+'NoAudit'+'"'+','+
 '"'+'0'+'"'+','+
 '"'+'NONE'+'"'+','+
 '"'+'NONE'+'"'+','+
 '"'+'0'+'"'+','+
 '"'+'AUDIT_CHANGE_GROUP'+'"'+','+
 '"'+'0'+'"'

if exists (SELECT @@servername as servername,
S.name AS 'Audit Name'
, S.is_state_enabled AS 'Audit Enabled'
, S.type_desc AS 'Write Location'
, SA.name AS 'Audit Specification Name'
, SA.is_state_enabled as 'Audit Specification Enabled'
, SAD.audit_action_name
, SAD.audited_result
FROM sys.server_audit_specification_details AS SAD
JOIN sys.server_audit_specifications AS SA
ON SAD.server_specification_id = SA.server_specification_id
JOIN sys.server_audits AS S
ON SA.audit_guid = S.audit_guid
WHERE SAD.audit_action_id ='LGFL')
SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@servername),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),S.name),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),S.is_state_enabled),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(60),S.type_desc),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),SA.name),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),SA.is_state_enabled),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(60),SAD.audit_action_name),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),SAD.audited_result),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'
FROM sys.server_audit_specification_details AS SAD
JOIN sys.server_audit_specifications AS SA
ON SAD.server_specification_id = SA.server_specification_id
JOIN sys.server_audits AS S
ON SA.audit_guid = S.audit_guid
WHERE SAD.audit_action_id ='LGFL'
ELSE
SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@SERVERNAME),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+'NoAudit'+'"'+','+
 '"'+'0'+'"'+','+
 '"'+'NONE'+'"'+','+
 '"'+'NONE'+'"'+','+
 '"'+'0'+'"'+','+
 '"'+'FAILED_LOGIN_GROUP'+'"'+','+
 '"'+'0'+'"'

if exists (SELECT @@servername as servername,
S.name AS 'Audit Name'
, S.is_state_enabled AS 'Audit Enabled'
, S.type_desc AS 'Write Location'
, SA.name AS 'Audit Specification Name'
, SA.is_state_enabled as 'Audit Specification Enabled'
, SAD.audit_action_name
, SAD.audited_result
FROM sys.server_audit_specification_details AS SAD
JOIN sys.server_audit_specifications AS SA
ON SAD.server_specification_id = SA.server_specification_id
JOIN sys.server_audits AS S
ON SA.audit_guid = S.audit_guid
WHERE SAD.audit_action_id ='LGSD')
SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@servername),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),S.name),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),S.is_state_enabled),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(60),S.type_desc),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),SA.name),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),SA.is_state_enabled),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(60),SAD.audit_action_name),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),SAD.audited_result),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'
FROM sys.server_audit_specification_details AS SAD
JOIN sys.server_audit_specifications AS SA
ON SAD.server_specification_id = SA.server_specification_id
JOIN sys.server_audits AS S
ON SA.audit_guid = S.audit_guid
WHERE SAD.audit_action_id ='LGSD'
ELSE
SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@SERVERNAME),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+'NoAudit'+'"'+','+
 '"'+'0'+'"'+','+
 '"'+'NONE'+'"'+','+
 '"'+'NONE'+'"'+','+
 '"'+'0'+'"'+','+
 '"'+'SUCCESSFUL_LOGIN_GROUP'+'"'+','+
 '"'+'0'+'"'
