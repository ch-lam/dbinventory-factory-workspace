-- NB : ce script est le plus fragile du lot (SQL dynamique multi-niveaux
-- avec SERVERPROPERTY, sous-requetes et parametre OUTPUT @ServiceAccount).
-- ATTENTION : le placeholder ''','',' present dans la branche SQL2008/legacy
-- (avant les 2 colonnes nodename) etait deja ambigu dans le script original
-- (nombre de colonnes potentiellement pas aligne avec la branche >=2012).
-- Je l'ai remplace par un vrai champ CSV vide "" pour ne pas casser le
-- comptage de colonnes en aval -- verifie ce point avant mise en prod.
--
-- Point verifie : les 2 branches legacy (@ver='10' et absence de
-- dm_os_windows_info) n'emettaient qu'UN champ vide la ou la branche >=2012
-- emet clusternode1 ET clusternode2, soit 17 champs au lieu de 18. Le
-- chargement etant positionnel (LOAD SQLcl sans header), tout se decalait a
-- partir de parallel_threshold sur une instance SQL2008 et service_account
-- restait vide. Les 2 branches emettent desormais 2 champs vides.
--
-- Les 3 branches emettent 19 champs, dans cet ordre :
--   hostname, mssql_edition, mssql_product_version, collation, is_clustered,
--   activenodename, clusternode1, clusternode2, parallel_threshold, max_dop,
--   min_memory, max_memory, xp_cmdshell_enabled, num_cpus, memory_gb, os_type,
--   install_date, service_account, is_integrated_security_only
-- get_info_mssql.sh les prefixe de 5 champs (collect_id, collect_target,
-- collect_port, environment, license_type) -> 24 colonnes = mssql_hosts.
--
-- is_integrated_security_only est ajoute EN DERNIER, et la colonne correspondante
-- en fin de mssql_hosts : le chargement etant positionnel, l'inserer au milieu
-- decalerait toutes les colonnes suivantes. SERVERPROPERTY renvoie 1 pour
-- l'authentification Windows seule, 0 pour le mode mixte. Disponible sur les 3
-- branches, y compris SQL2008.

DECLARE @ver nvarchar(128)
DECLARE @sqlstmt nvarchar(4000)
SET @ver = CAST(serverproperty('ProductVersion') AS nvarchar)
SET @ver = SUBSTRING(@ver, 1, CHARINDEX('.', @ver) - 1)

IF EXISTS (SELECT * FROM sys.all_views
WHERE name = N'dm_os_windows_info')
BEGIN
IF ( @ver = '10' )
(         select  @sqlstmt = '
      DECLARE @ServiceAccount varchar(100)
EXECUTE master.dbo.xp_instance_regread
            N''HKEY_LOCAL_MACHINE'',
            N''SYSTEM\CurrentControlSet\Services\MSSQLSERVER'',
            N''ObjectName'',
            @ServiceAccount OUTPUT,
            N''no_output''
          select
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),SERVERPROPERTY(''ServerName'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(60),SERVERPROPERTY(''Edition'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(60),SERVERPROPERTY(''ProductVersion'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),SERVERPROPERTY(''Collation'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(10),SERVERPROPERTY(''IsClustered'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),SERVERPROPERTY(''ComputerNamePhysicalNetBIOS'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+CHAR(34)+'',''+
          CHAR(34)+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),(select value from sys.configurations where name = ''cost threshold for parallelism'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),(select value from sys.configurations where name = ''max degree of parallelism'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),(select value from sys.configurations where name = ''min server memory (MB)'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),(select value from sys.configurations where name = ''max server memory (MB)'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),(select value from sys.configurations where name = ''xp_cmdshell'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),(select cpu_count from sys.dm_os_sys_info)),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),(select physical_memory_in_bytes/1024/1024/1024 from sys.dm_os_sys_info)),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(60),(SELECT windows_release FROM sys.dm_os_windows_info)),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
	  CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(10),(SELECT CONVERT(VARCHAR(10), createdate, 112) FROM  sys.syslogins where sid = 0x010100000000000512000000)),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(100),@ServiceAccount),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(10),SERVERPROPERTY(''IsIntegratedSecurityOnly'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)')
ELSE
(         select @sqlstmt = '
            DECLARE @ServiceAccount varchar(100)
EXECUTE master.dbo.xp_instance_regread
            N''HKEY_LOCAL_MACHINE'',
            N''SYSTEM\CurrentControlSet\Services\MSSQLSERVER'',
            N''ObjectName'',
            @ServiceAccount OUTPUT,
            N''no_output''
          select
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),SERVERPROPERTY(''ServerName'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(60),SERVERPROPERTY(''Edition'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(60),SERVERPROPERTY(''ProductVersion'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),SERVERPROPERTY(''Collation'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(10),SERVERPROPERTY(''IsClustered'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),SERVERPROPERTY(''ComputerNamePhysicalNetBIOS'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),(SELECT nodename FROM sys.dm_os_cluster_nodes ORDER BY 1 OFFSET 0 ROWS FETCH NEXT 1 ROWS ONLY)),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),(SELECT nodename FROM sys.dm_os_cluster_nodes ORDER BY 1 OFFSET 1 ROWS FETCH NEXT 1 ROWS ONLY)),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),(select value from sys.configurations where name = ''cost threshold for parallelism'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),(select value from sys.configurations where name = ''max degree of parallelism'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),(select value from sys.configurations where name = ''min server memory (MB)'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),(select value from sys.configurations where name = ''max server memory (MB)'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),(select value from sys.configurations where name = ''xp_cmdshell'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),(select cpu_count from sys.dm_os_sys_info)),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),(select physical_memory_kb/1024/1024 from sys.dm_os_sys_info)),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(60),(SELECT windows_release FROM sys.dm_os_windows_info)),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
	  CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(10),(SELECT CONVERT(VARCHAR(10), createdate, 112) FROM  sys.syslogins where sid = 0x010100000000000512000000)),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(100),@ServiceAccount),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(10),SERVERPROPERTY(''IsIntegratedSecurityOnly'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)'
          )
END
ELSE
BEGIN
select  @sqlstmt = '
      DECLARE @ServiceAccount varchar(100)
EXECUTE master.dbo.xp_instance_regread
            N''HKEY_LOCAL_MACHINE'',
            N''SYSTEM\CurrentControlSet\Services\MSSQLSERVER'',
            N''ObjectName'',
            @ServiceAccount OUTPUT,
            N''no_output''
          select
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),SERVERPROPERTY(''ServerName'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(60),SERVERPROPERTY(''Edition'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(60),SERVERPROPERTY(''ProductVersion'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),SERVERPROPERTY(''Collation'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(10),SERVERPROPERTY(''IsClustered'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),SERVERPROPERTY(''ComputerNamePhysicalNetBIOS'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+CHAR(34)+'',''+
          CHAR(34)+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),(select value from sys.configurations where name = ''cost threshold for parallelism'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),(select value from sys.configurations where name = ''max degree of parallelism'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),(select value from sys.configurations where name = ''min server memory (MB)'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),(select value from sys.configurations where name = ''max server memory (MB)'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),(select value from sys.configurations where name = ''xp_cmdshell'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),(select cpu_count from sys.dm_os_sys_info)),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),(select physical_memory_in_bytes/1024/1024/1024 from sys.dm_os_sys_info)),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+''6.1''+CHAR(34)+'',''+
	  CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(10),(SELECT CONVERT(VARCHAR(10), createdate, 112) FROM  sys.syslogins where sid = 0x010100000000000512000000)),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(100),@ServiceAccount),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
          CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(10),SERVERPROPERTY(''IsIntegratedSecurityOnly'')),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)'
END
EXEC (@sqlstmt)
