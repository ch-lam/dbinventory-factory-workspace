DECLARE @getValue INT;
EXEC master.sys.xp_instance_regread
@rootkey = N'HKEY_LOCAL_MACHINE',
@key = N'SOFTWARE\Microsoft\Microsoft SQL Server\MSSQLServer\SuperSocketNetLib',
@value_name = N'HideInstance',
@value = @getValue OUTPUT;
SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@Servername),''),'"','""')+'"'+','+
 '"'+'Hide Instance'+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(20),@getValue),''),'"','""')+'"';
GO
DECLARE @getValue INT;
EXEC master.sys.xp_instance_regread
@rootkey = N'HKEY_LOCAL_MACHINE',
@key = N'SOFTWARE\Microsoft\Microsoft SQL Server\MSSQLServer\SuperSocketNetLib',
@value_name = N'ForceEncryption',
@value = @getValue OUTPUT;
SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@Servername),''),'"','""')+'"'+','+
 '"'+'ForceEncryption'+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(20),@getValue),''),'"','""')+'"';
GO
DECLARE @value nvarchar(256);
EXECUTE master.dbo.xp_instance_regread
N'HKEY_LOCAL_MACHINE',
N'SOFTWARE\Microsoft\Microsoft SQL Server\MSSQLServer\SuperSocketNetLib\Tcp\IPAll',
N'TcpPort',
@value OUTPUT,
N'no_output';
SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@Servername),''),'"','""')+'"'+','+
 '"'+'TCP Port'+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(256),@value),''),'"','""')+'"'
GO
DECLARE @NumErrorLogs int;
EXEC master.sys.xp_instance_regread
N'HKEY_LOCAL_MACHINE',
N'Software\Microsoft\MSSQLServer\MSSQLServer',
N'NumErrorLogs',
@NumErrorLogs OUTPUT;
SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@Servername),''),'"','""')+'"'+','+
 '"'+'NumErrorlogFiles'+'"'+','+
 '"'+REPLACE(CONVERT(varchar(20),ISNULL(@NumErrorLogs, -1)),'"','""')+'"';
GO
