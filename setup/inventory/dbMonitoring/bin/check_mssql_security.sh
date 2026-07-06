#!/bin/bash
# check_mssql_security.sh - MSSQL security/compliance monitoring checks
# Script maison (ne dépend pas des plugins vendored check_mssql_health.sh / check_ssl_cert.sh)
# ajouté suite à l'audit du 2026-07-06 : ces contrôles n'avaient aucun équivalent
# de supervision alors qu'ils sont collectés quotidiennement par get_info_sqlserver_security.sh.

export PATH=/opt/mssql-tools18/bin:${PATH}

export RETCODE=0
export WARNING_MSG="WARNING - "
export CRITICAL_MSG="CRITICAL - "
export OK_MSG="OK - "

#DEFAULT EXIT CODE
export STATE_OK=0
export STATE_CRITICAL=2
export STATE_WARNING=1

#DEFAULT THRESHOLD
export WARNING_THRESHOLD=80
export CRITICAL_THRESHOLD=90

while getopts :m:h:u:p:w:c: OPTION
        do
         case "$OPTION" in
          m) export MODE=$OPTARG
             ;;
          h) export HOST_NAME_TO_CHECK=$OPTARG
             ;;
          u) export USERNAME=$OPTARG
             ;;
          p) export PASSWORD=$OPTARG
             ;;
          w) export WARNING_THRESHOLD=$OPTARG
             ;;
          c) export CRITICAL_THRESHOLD=$OPTARG
             ;;
          :) echo "$0: $OPTARG option missing argument!"
             exit 2 ;;
          ?)  echo Invalid Option $"Usage: "
              echo "-m check_sysadmin_members -h HOSTNAME -u USERNAME -p PASSWORD -w WARNING -c CRITICAL (number of sysadmin members beyond sa)"
              echo "-m check_xp_cmdshell -h HOSTNAME -u USERNAME -p PASSWORD"
              echo "-m check_trustworthy -h HOSTNAME -u USERNAME -p PASSWORD (user databases with TRUSTWORTHY ON)"
              echo "-m check_guest_connect -h HOSTNAME -u USERNAME -p PASSWORD (databases granting CONNECT to guest)"
              echo "-m check_orphaned_users -h HOSTNAME -u USERNAME -p PASSWORD"
              echo "-m check_invalid_logins -h HOSTNAME -u USERNAME -p PASSWORD (enabled logins mapped to a removed AD account)"
              echo "-m check_encryption_status -h HOSTNAME -u USERNAME -p PASSWORD (databases with TDE in a transitional/inconsistent state)"
              echo "-m check_audit_level -h HOSTNAME -u USERNAME -p PASSWORD (instance login audit level)"
              echo "-m check_sqlserver_audit -h HOSTNAME -u USERNAME -p PASSWORD (SQL Server Audit change/login groups)"
              echo "-m check_public_permission -h HOSTNAME -u USERNAME -p PASSWORD (non-default permissions granted to public)"
              echo "-m check_force_encryption -h HOSTNAME -u USERNAME -p PASSWORD (registry ForceEncryption)"
              echo "-m check_config_options -h HOSTNAME -u USERNAME -p PASSWORD (hardening options: xp_cmdshell excluded, see check_xp_cmdshell)"
              echo "-m check_groups_permission -h HOSTNAME -u USERNAME -p PASSWORD (BUILTIN/local Windows groups with server permissions)"
              exit 1
         esac
done

fct_sqlcmd(){
    sqlcmd -U "${USERNAME}" -S "${HOST_NAME_TO_CHECK}" -P "${PASSWORD}" -C -Q "$1" -h-1 -W -w 999 -s"," 2>/dev/null \
        | grep -v "affected" | grep -vi "^Sqlcmd:"
}

fct_check_sysadmin_members(){
RESULT=`fct_sqlcmd "
SET NOCOUNT ON
SELECT l.name FROM sys.sql_logins l WHERE IS_SRVROLEMEMBER('sysadmin',l.name)=1 AND l.name <> 'sa'
UNION
SELECT l.name FROM sys.server_principals l
JOIN sys.server_role_members r ON l.principal_id=r.member_principal_id
JOIN sys.server_principals rp ON r.role_principal_id=rp.principal_id
WHERE rp.name='sysadmin' AND l.type_desc <> 'SERVER_ROLE' AND l.name <> 'sa'
"`
RESULT=`echo "${RESULT}" | grep -v '^\s*$'`
NB=`echo "${RESULT}" | grep -c .`

if [[ "${NB}" -gt "${CRITICAL_THRESHOLD}" ]]; then
        echo "CRITICAL - ${NB} sysadmin member(s) beyond sa on ${HOST_NAME_TO_CHECK}: `echo ${RESULT} | tr '\n' ' '`"
        exit $STATE_CRITICAL
elif [[ "${NB}" -gt "${WARNING_THRESHOLD}" ]]; then
        echo "WARNING - ${NB} sysadmin member(s) beyond sa on ${HOST_NAME_TO_CHECK}: `echo ${RESULT} | tr '\n' ' '`"
        exit $STATE_WARNING
else
        echo "OK - ${NB} sysadmin member(s) beyond sa on ${HOST_NAME_TO_CHECK}: `echo ${RESULT} | tr '\n' ' '`"
        exit $STATE_OK
fi
}

fct_check_xp_cmdshell(){
RESULT=`fct_sqlcmd "SET NOCOUNT ON; SELECT CAST(value_in_use as int) FROM sys.configurations WHERE name='xp_cmdshell'"`
VAL=`echo "${RESULT}" | tr -d ' \r\n'`

if [ "${VAL}" = "1" ]; then
        echo "WARNING - xp_cmdshell is enabled on ${HOST_NAME_TO_CHECK}"
        exit $STATE_WARNING
else
        echo "OK - xp_cmdshell is disabled on ${HOST_NAME_TO_CHECK}"
        exit $STATE_OK
fi
}

fct_check_trustworthy(){
RESULT=`fct_sqlcmd "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE is_trustworthy_on=1 AND name NOT IN ('master','tempdb','model','msdb')"`
RESULT=`echo "${RESULT}" | grep -v '^\s*$'`

if [ ! -z "${RESULT}" ]; then
        echo "WARNING - TRUSTWORTHY enabled on database(s) on ${HOST_NAME_TO_CHECK}: `echo ${RESULT} | tr '\n' ' '`"
        exit $STATE_WARNING
else
        echo "OK - No user database with TRUSTWORTHY enabled on ${HOST_NAME_TO_CHECK}"
        exit $STATE_OK
fi
}

fct_check_guest_connect(){
RESULT=`fct_sqlcmd "
SET NOCOUNT ON
DECLARE @command varchar(1000)
SELECT @command = 'USE [?] IF EXISTS (SELECT 1 FROM sys.database_permissions WHERE grantee_principal_id=DATABASE_PRINCIPAL_ID(''guest'') AND state_desc LIKE ''GRANT%'' AND permission_name=''CONNECT'' AND DB_NAME() NOT IN (''master'',''tempdb'',''msdb'')) SELECT DB_NAME()'
EXEC sp_MSforeachdb @command
"`
RESULT=`echo "${RESULT}" | grep -v '^\s*$'`

if [ ! -z "${RESULT}" ]; then
        echo "WARNING - guest has CONNECT permission on database(s) on ${HOST_NAME_TO_CHECK}: `echo ${RESULT} | tr '\n' ' '`"
        exit $STATE_WARNING
else
        echo "OK - No database grants CONNECT to guest (outside system databases) on ${HOST_NAME_TO_CHECK}"
        exit $STATE_OK
fi
}

fct_check_orphaned_users(){
RESULT=`fct_sqlcmd "
SET NOCOUNT ON
DECLARE @command varchar(1000)
SELECT @command = 'USE [?] IF EXISTS (SELECT 1 FROM sys.database_principals WHERE sid NOT IN (SELECT sid FROM sys.server_principals) AND type=''S'' AND principal_id<>2 AND DATALENGTH(sid)<=28 AND name<>''MS_DataCollectorInternalUser'') SELECT DB_NAME()+'':''+name FROM sys.database_principals WHERE sid NOT IN (SELECT sid FROM sys.server_principals) AND type=''S'' AND principal_id<>2 AND DATALENGTH(sid)<=28 AND name<>''MS_DataCollectorInternalUser'''
EXEC sp_MSforeachdb @command
"`
RESULT=`echo "${RESULT}" | grep -v '^\s*$'`

if [ ! -z "${RESULT}" ]; then
        echo "WARNING - Orphaned database user(s) detected on ${HOST_NAME_TO_CHECK}: `echo ${RESULT} | tr '\n' ' '`"
        exit $STATE_WARNING
else
        echo "OK - No orphaned database user detected on ${HOST_NAME_TO_CHECK}"
        exit $STATE_OK
fi
}

fct_check_invalid_logins(){
RESULT=`fct_sqlcmd "
SET NOCOUNT ON
IF OBJECT_ID('tempdb..#invalidlogins') IS NOT NULL DROP TABLE #invalidlogins
CREATE TABLE #invalidlogins(ACCTSID VARBINARY(85), NTLOGIN SYSNAME)
INSERT INTO #invalidlogins EXEC sys.sp_validatelogins
SELECT SP.name FROM #invalidlogins IL JOIN sys.server_principals SP ON IL.NTLOGIN=SP.name WHERE SP.is_disabled=0
"`
RESULT=`echo "${RESULT}" | grep -v '^\s*$'`

if [ ! -z "${RESULT}" ]; then
        echo "WARNING - Enabled login(s) mapped to a removed/invalid Windows account on ${HOST_NAME_TO_CHECK}: `echo ${RESULT} | tr '\n' ' '`"
        exit $STATE_WARNING
else
        echo "OK - No enabled login mapped to an invalid Windows account on ${HOST_NAME_TO_CHECK}"
        exit $STATE_OK
fi
}

fct_check_encryption_status(){
RESULT=`fct_sqlcmd "SET NOCOUNT ON; SELECT db.name+':'+CAST(dm.encryption_state as varchar(2)) FROM sys.databases db JOIN sys.dm_database_encryption_keys dm ON db.database_id=dm.database_id WHERE dm.encryption_state NOT IN (0,3)"`
RESULT=`echo "${RESULT}" | grep -v '^\s*$'`

if [ ! -z "${RESULT}" ]; then
        echo "WARNING - Database(s) with TDE in a transitional/inconsistent state on ${HOST_NAME_TO_CHECK} (encryption_state<>3): `echo ${RESULT} | tr '\n' ' '`"
        exit $STATE_WARNING
else
        echo "OK - No database with an inconsistent TDE encryption state on ${HOST_NAME_TO_CHECK}"
        exit $STATE_OK
fi
}

fct_check_audit_level(){
RESULT=`fct_sqlcmd "
SET NOCOUNT ON
DECLARE @AuditLevel int
EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'AuditLevel', @AuditLevel OUTPUT
SELECT ISNULL(@AuditLevel,-1)
"`
VAL=`echo "${RESULT}" | tr -d ' \r\n'`

if [ "${VAL}" = "0" ] || [ "${VAL}" = "-1" ]; then
        echo "WARNING - Login audit level is None on ${HOST_NAME_TO_CHECK}"
        exit $STATE_WARNING
else
        echo "OK - Login audit level is configured (code ${VAL}) on ${HOST_NAME_TO_CHECK}"
        exit $STATE_OK
fi
}

fct_check_sqlserver_audit(){
MESSAGE=""
FOUND_ENABLED=0
while IFS=':' read -r ACTION AUDIT_ENABLED SPEC_ENABLED
do
        [ -z "${ACTION}" ] && continue
        AUDIT_ENABLED=`echo ${AUDIT_ENABLED} | tr -d ' \r'`
        SPEC_ENABLED=`echo ${SPEC_ENABLED} | tr -d ' \r'`
        if [ "${AUDIT_ENABLED}" = "1" ] && [ "${SPEC_ENABLED}" = "1" ]; then
                FOUND_ENABLED=$((FOUND_ENABLED+1))
        fi
done < <(fct_sqlcmd "
SET NOCOUNT ON
SELECT SAD.audit_action_name+':'+CAST(S.is_state_enabled as varchar(1))+':'+CAST(SA.is_state_enabled as varchar(1))
FROM sys.server_audit_specification_details SAD
JOIN sys.server_audit_specifications SA ON SAD.server_specification_id=SA.server_specification_id
JOIN sys.server_audits S ON SA.audit_guid=S.audit_guid
WHERE SAD.audit_action_id IN ('CNAU','LGFL','LGSD')
")

if [[ "${FOUND_ENABLED}" -eq 0 ]]; then
        echo "WARNING - No SQL Server Audit enabled for AUDIT_CHANGE_GROUP/FAILED_LOGIN_GROUP/SUCCESSFUL_LOGIN_GROUP on ${HOST_NAME_TO_CHECK}"
        exit $STATE_WARNING
else
        echo "OK - SQL Server Audit configured for ${FOUND_ENABLED} action group(s) on ${HOST_NAME_TO_CHECK}"
        exit $STATE_OK
fi
}

fct_check_public_permission(){
RESULT=`fct_sqlcmd "
SET NOCOUNT ON
SELECT pe.permission_name+':'+pe.state_desc
FROM sys.server_permissions pe
WHERE pe.grantee_principal_id = SUSER_SID(N'public') AND pe.state_desc LIKE 'GRANT%'
AND NOT (pe.state_desc='GRANT' AND pe.permission_name='VIEW ANY DATABASE' AND pe.class_desc='SERVER')
AND NOT (pe.state_desc='GRANT' AND pe.permission_name='CONNECT' AND pe.class_desc='ENDPOINT' AND pe.major_id IN (2,3,4,5))
"`
RESULT=`echo "${RESULT}" | grep -v '^\s*$'`

if [ ! -z "${RESULT}" ]; then
        echo "WARNING - Non-default permission(s) granted to public on ${HOST_NAME_TO_CHECK}: `echo ${RESULT} | tr '\n' ' '`"
        exit $STATE_WARNING
else
        echo "OK - public role has only default server permissions on ${HOST_NAME_TO_CHECK}"
        exit $STATE_OK
fi
}

fct_check_force_encryption(){
RESULT=`fct_sqlcmd "
SET NOCOUNT ON
DECLARE @getValue INT
EXEC master.sys.xp_instance_regread @rootkey=N'HKEY_LOCAL_MACHINE', @key=N'SOFTWARE\Microsoft\Microsoft SQL Server\MSSQLServer\SuperSocketNetLib', @value_name=N'ForceEncryption', @value=@getValue OUTPUT
SELECT ISNULL(@getValue,-1)
"`
VAL=`echo "${RESULT}" | tr -d ' \r\n'`

if [ "${VAL}" = "0" ] || [ "${VAL}" = "-1" ]; then
        echo "WARNING - ForceEncryption is not enabled on ${HOST_NAME_TO_CHECK} (registry value: ${VAL})"
        exit $STATE_WARNING
else
        echo "OK - ForceEncryption is enabled on ${HOST_NAME_TO_CHECK}"
        exit $STATE_OK
fi
}

fct_check_config_options(){
MESSAGE=""
while IFS=':' read -r OPT VAL
do
        [ -z "${OPT}" ] && continue
        VAL=`echo ${VAL} | tr -d ' \r'`
        case "${OPT}" in
                "Ad Hoc Distributed Queries"|"cross db ownership chaining"|"Ole Automation Procedures"|"remote access"|"scan for startup procs"|"remote admin connections")
                        [ "${VAL}" = "1" ] && MESSAGE="${MESSAGE} [${OPT}]=1(expected_0) /"
                        ;;
                "clr enabled")
                        [ "${VAL}" = "1" ] && MESSAGE="${MESSAGE} [${OPT}]=1(review_if_required) /"
                        ;;
                "default trace enabled"|"clr strict security")
                        [ "${VAL}" = "0" ] && MESSAGE="${MESSAGE} [${OPT}]=0(expected_1) /"
                        ;;
        esac
done < <(fct_sqlcmd "
SET NOCOUNT ON
SELECT name+':'+CAST(value_in_use as varchar(10))
FROM sys.configurations
WHERE name IN ('Ad Hoc Distributed Queries','clr enabled','cross db ownership chaining','Ole Automation Procedures','remote access','scan for startup procs','default trace enabled','clr strict security')
UNION ALL
SELECT name+':'+CAST(value_in_use as varchar(10)) FROM sys.configurations WHERE name='remote admin connections' AND SERVERPROPERTY('IsClustered')=0
")

if [ ! -z "${MESSAGE}" ]; then
        echo "WARNING - Insecure server configuration option(s) detected on ${HOST_NAME_TO_CHECK}: ${MESSAGE}"
        exit $STATE_WARNING
else
        echo "OK - All monitored server configuration options have expected values on ${HOST_NAME_TO_CHECK}"
        exit $STATE_OK
fi
}

fct_check_groups_permission(){
RESULT=`fct_sqlcmd "
SET NOCOUNT ON
SELECT pr.name+':'+pe.permission_name+':'+pe.state_desc
FROM sys.server_principals pr
JOIN sys.server_permissions pe ON pr.principal_id=pe.grantee_principal_id
WHERE pr.name LIKE 'BUILTIN%' OR (pr.type_desc='WINDOWS_GROUP' AND pr.name LIKE CAST(SERVERPROPERTY('MachineName') as nvarchar)+'%')
"`
RESULT=`echo "${RESULT}" | grep -v '^\s*$'`

if [ ! -z "${RESULT}" ]; then
        echo "WARNING - Windows group(s) with server permission(s) detected on ${HOST_NAME_TO_CHECK}: `echo ${RESULT} | tr '\n' ' '`"
        exit $STATE_WARNING
else
        echo "OK - No BUILTIN/local Windows group with server permissions on ${HOST_NAME_TO_CHECK}"
        exit $STATE_OK
fi
}

case "${MODE}" in
        check_sysadmin_members)
                fct_check_sysadmin_members
                ;;
        check_xp_cmdshell)
                fct_check_xp_cmdshell
                ;;
        check_trustworthy)
                fct_check_trustworthy
                ;;
        check_guest_connect)
                fct_check_guest_connect
                ;;
        check_orphaned_users)
                fct_check_orphaned_users
                ;;
        check_invalid_logins)
                fct_check_invalid_logins
                ;;
        check_encryption_status)
                fct_check_encryption_status
                ;;
        check_audit_level)
                fct_check_audit_level
                ;;
        check_sqlserver_audit)
                fct_check_sqlserver_audit
                ;;
        check_public_permission)
                fct_check_public_permission
                ;;
        check_force_encryption)
                fct_check_force_encryption
                ;;
        check_config_options)
                fct_check_config_options
                ;;
        check_groups_permission)
                fct_check_groups_permission
                ;;
        *)
                echo Invalid Option $"Usage: "
                echo "-m check_sysadmin_members -h HOSTNAME -u USERNAME -p PASSWORD -w WARNING -c CRITICAL (number of sysadmin members beyond sa)"
                echo "-m check_xp_cmdshell -h HOSTNAME -u USERNAME -p PASSWORD"
                echo "-m check_trustworthy -h HOSTNAME -u USERNAME -p PASSWORD (user databases with TRUSTWORTHY ON)"
                echo "-m check_guest_connect -h HOSTNAME -u USERNAME -p PASSWORD (databases granting CONNECT to guest)"
                echo "-m check_orphaned_users -h HOSTNAME -u USERNAME -p PASSWORD"
                echo "-m check_invalid_logins -h HOSTNAME -u USERNAME -p PASSWORD (enabled logins mapped to a removed AD account)"
                echo "-m check_encryption_status -h HOSTNAME -u USERNAME -p PASSWORD (databases with TDE in a transitional/inconsistent state)"
                echo "-m check_audit_level -h HOSTNAME -u USERNAME -p PASSWORD (instance login audit level)"
                echo "-m check_sqlserver_audit -h HOSTNAME -u USERNAME -p PASSWORD (SQL Server Audit change/login groups)"
                echo "-m check_public_permission -h HOSTNAME -u USERNAME -p PASSWORD (non-default permissions granted to public)"
                echo "-m check_force_encryption -h HOSTNAME -u USERNAME -p PASSWORD (registry ForceEncryption)"
                echo "-m check_config_options -h HOSTNAME -u USERNAME -p PASSWORD (hardening options; xp_cmdshell has its own mode)"
                echo "-m check_groups_permission -h HOSTNAME -u USERNAME -p PASSWORD (BUILTIN/local Windows groups with server permissions)"
                exit 1
esac
