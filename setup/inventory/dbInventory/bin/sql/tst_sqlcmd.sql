/*==============================================================================
  mssql_healthcheck.sql  --  Audit de configuration d'une instance SQL Server
  ------------------------------------------------------------------------------
  Cible      : SQL Server 2016+ (testé sur les DMV 2016/2019/2022)
  Exécution  : sqlcmd -S <serveur> -i mssql_healthcheck.sql -o rapport.txt
  Droits     : VIEW SERVER STATE + VIEW ANY DEFINITION + accès msdb.
               (idéalement sysadmin en read-only, ou un login dédié d'audit)
  Idempotent : lecture seule, aucune modification.
  ------------------------------------------------------------------------------
  Les sections sensibles à la version sont encadrées de TRY/CATCH : sur une
  instance plus ancienne, la section renvoie un message au lieu de casser tout
  le rapport.
==============================================================================*/
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;
PRINT '================================================================';
PRINT ' AUDIT CONFIGURATION SQL SERVER';
PRINT ' Serveur : ' + @@SERVERNAME + '   |   ' + CONVERT(varchar(30), SYSDATETIME(), 120);
PRINT '================================================================';

/*------------------------------------------------------------------
  1. IDENTITE INSTANCE
------------------------------------------------------------------*/
PRINT '';
PRINT '--- 1. IDENTITE INSTANCE -----------------------------------';
SELECT
      SERVERPROPERTY('MachineName')                         AS machine
    , SERVERPROPERTY('ServerName')                          AS instance
    , SERVERPROPERTY('Edition')                             AS edition
    , SERVERPROPERTY('ProductVersion')                      AS version
    , SERVERPROPERTY('ProductLevel')                        AS niveau_sp
    , SERVERPROPERTY('ProductUpdateLevel')                  AS cu
    , SERVERPROPERTY('Collation')                           AS collation_srv
    , CAST(SERVERPROPERTY('IsClustered')   AS int)          AS is_cluster
    , CAST(SERVERPROPERTY('IsHadrEnabled') AS int)          AS is_ag
    , CAST(SERVERPROPERTY('IsIntegratedSecurityOnly') AS int) AS auth_windows_only  -- 1 = Windows only, 0 = mixte
    , cpu_count
    , CAST(physical_memory_kb/1024.0/1024 AS decimal(9,1))  AS ram_go
    , sqlserver_start_time
    , DATEDIFF(day, sqlserver_start_time, SYSDATETIME())    AS uptime_jours
FROM sys.dm_os_sys_info;

/*------------------------------------------------------------------
  2. PARAMETRES INSTANCE (sp_configure / sys.configurations)
     Colonne "attendu" = valeur de reference courante, a adapter a ta cible.
------------------------------------------------------------------*/
PRINT '';
PRINT '--- 2. PARAMETRES INSTANCE ---------------------------------';
SELECT
      c.name
    , c.value_in_use
    , c.value            AS value_configuree
    , CASE c.name
        WHEN 'max server memory (MB)'        THEN '< RAM totale, laisser marge OS'
        WHEN 'min server memory (MB)'        THEN '0 sauf besoin specifique'
        WHEN 'max degree of parallelism'     THEN '<= nb coeurs par NUMA, souvent 4 a 8'
        WHEN 'cost threshold for parallelism'THEN '25 a 50 (defaut 5 trop bas)'
        WHEN 'optimize for ad hoc workloads' THEN '1 recommande'
        WHEN 'backup compression default'    THEN '1 recommande'
        WHEN 'remote admin connections'      THEN '1 (DAC a distance)'
        WHEN 'xp_cmdshell'                   THEN '0 (securite)'
        WHEN 'Ad Hoc Distributed Queries'    THEN '0 (securite)'
        WHEN 'Ole Automation Procedures'     THEN '0 (securite)'
        WHEN 'max worker threads'            THEN '0 = auto'
        WHEN 'fill factor (%)'               THEN '0/100 sauf tuning cible'
        ELSE ''
      END              AS reference
FROM sys.configurations c
WHERE c.name IN (
      'max server memory (MB)','min server memory (MB)',
      'max degree of parallelism','cost threshold for parallelism',
      'optimize for ad hoc workloads','backup compression default',
      'remote admin connections','xp_cmdshell','Ad Hoc Distributed Queries',
      'Ole Automation Procedures','max worker threads','fill factor (%)',
      'default trace enabled','clr enabled','remote access'
)
ORDER BY c.name;

/*------------------------------------------------------------------
  3. PARAMETRES OS / MEMOIRE (IFI, LPIM, modele memoire)
------------------------------------------------------------------*/
PRINT '';
PRINT '--- 3. PARAMETRES OS / MEMOIRE -----------------------------';
BEGIN TRY
    SELECT
          SERVERPROPERTY('InstantFileInitializationEnabled') AS ifi_active   -- 1 = OK (2016 SP1+)
        , sql_memory_model_desc                              AS modele_memoire -- LOCK_PAGES = LPIM actif
    FROM sys.dm_os_sys_info;
END TRY
BEGIN CATCH
    PRINT '  (proprietes IFI/LPIM indisponibles sur cette version)';
END CATCH;

/*------------------------------------------------------------------
  4. TRACE FLAGS ACTIFS
------------------------------------------------------------------*/
PRINT '';
PRINT '--- 4. TRACE FLAGS GLOBAUX ---------------------------------';
IF OBJECT_ID('tempdb..#tf') IS NOT NULL DROP TABLE #tf;
CREATE TABLE #tf (TraceFlag int, Status int, Global int, Session int);
INSERT INTO #tf EXEC ('DBCC TRACESTATUS(-1) WITH NO_INFOMSGS');
IF EXISTS (SELECT 1 FROM #tf)
    SELECT TraceFlag, Global, Session,
           CASE TraceFlag
             WHEN 3226 THEN 'supprime le log des backups reussis'
             WHEN 1117 THEN 'croissance uniforme fichiers (obsolete 2016+ pour tempdb)'
             WHEN 1118 THEN 'allocation extents uniformes (obsolete 2016+)'
             ELSE '' END AS note
    FROM #tf;
ELSE
    PRINT '  Aucun trace flag global actif.';

/*------------------------------------------------------------------
  5. TEMPDB
------------------------------------------------------------------*/
PRINT '';
PRINT '--- 5. TEMPDB (fichiers de donnees) ------------------------';
SELECT
      mf.file_id, mf.name, mf.type_desc,
      CAST(mf.size*8/1024.0 AS decimal(10,1))            AS taille_mo,
      mf.growth,
      CASE mf.is_percent_growth WHEN 1 THEN 'pourcentage (a eviter)' ELSE 'Mo' END AS type_growth,
      mf.physical_name
FROM sys.master_files mf
WHERE mf.database_id = 2
ORDER BY mf.type, mf.file_id;
PRINT '  Reco : plusieurs fichiers data de meme taille (1/coeur, plafond ~8),';
PRINT '         autogrowth en Mo fixe, pas en pourcentage.';

/*------------------------------------------------------------------
  6. BASES DE DONNEES - ETAT & OPTIONS
------------------------------------------------------------------*/
PRINT '';
PRINT '--- 6. BASES - ETAT & OPTIONS ------------------------------';
SELECT
      d.name,
      d.state_desc,
      d.recovery_model_desc                       AS recovery,
      d.compatibility_level                       AS compat,
      d.page_verify_option_desc                   AS page_verify,   -- doit etre CHECKSUM
      d.is_auto_close_on                          AS auto_close,    -- doit etre 0
      d.is_auto_shrink_on                         AS auto_shrink,   -- doit etre 0
      d.is_auto_create_stats_on                   AS auto_create_stats,
      d.is_auto_update_stats_on                   AS auto_update_stats,
      d.is_read_committed_snapshot_on             AS rcsi,
      SUSER_SNAME(d.owner_sid)                     AS proprietaire   -- attention aux bases owner = sa desactive
FROM sys.databases d
ORDER BY d.database_id;

/*------------------------------------------------------------------
  7. TAILLE FICHIERS & UTILISATION LOG
------------------------------------------------------------------*/
PRINT '';
PRINT '--- 7. TAILLE DATA / LOG -----------------------------------';
SELECT
      DB_NAME(mf.database_id)                            AS base,
      SUM(CASE WHEN mf.type=0 THEN mf.size END)*8/1024   AS data_mo,
      SUM(CASE WHEN mf.type=1 THEN mf.size END)*8/1024   AS log_mo
FROM sys.master_files mf
GROUP BY mf.database_id
ORDER BY base;

PRINT '';
PRINT '  Utilisation du transaction log (DBCC SQLPERF LOGSPACE) :';
DBCC SQLPERF(LOGSPACE);

/*------------------------------------------------------------------
  8. FRAGMENTATION DU LOG (VLF) -- 2016 SP2+/2017+
------------------------------------------------------------------*/
PRINT '';
PRINT '--- 8. NOMBRE DE VLF PAR BASE ------------------------------';
BEGIN TRY
    DECLARE @dbid int, @dbname sysname;
    IF OBJECT_ID('tempdb..#vlf') IS NOT NULL DROP TABLE #vlf;
    CREATE TABLE #vlf (base sysname, vlf_count int);
    DECLARE cdb CURSOR LOCAL FAST_FORWARD FOR
        SELECT database_id, name FROM sys.databases WHERE state = 0;
    OPEN cdb; FETCH NEXT FROM cdb INTO @dbid, @dbname;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        INSERT INTO #vlf(base, vlf_count)
        SELECT @dbname, COUNT(*) FROM sys.dm_db_log_info(@dbid);
        FETCH NEXT FROM cdb INTO @dbid, @dbname;
    END
    CLOSE cdb; DEALLOCATE cdb;
    SELECT base, vlf_count,
           CASE WHEN vlf_count > 1000 THEN 'ELEVE - envisager shrink+regrow log'
                WHEN vlf_count > 300  THEN 'a surveiller' ELSE 'ok' END AS note
    FROM #vlf ORDER BY vlf_count DESC;
END TRY
BEGIN CATCH
    PRINT '  sys.dm_db_log_info indisponible (version < 2016 SP2) - utiliser DBCC LOGINFO.';
END CATCH;

/*------------------------------------------------------------------
  9. SAUVEGARDES - DERNIERE PAR BASE ET PAR TYPE
------------------------------------------------------------------*/
PRINT '';
PRINT '--- 9. DERNIERES SAUVEGARDES -------------------------------';
SELECT
      d.name AS base,
      d.recovery_model_desc AS recovery,
      MAX(CASE WHEN b.type='D' THEN b.backup_finish_date END) AS dernier_full,
      MAX(CASE WHEN b.type='I' THEN b.backup_finish_date END) AS dernier_diff,
      MAX(CASE WHEN b.type='L' THEN b.backup_finish_date END) AS dernier_log
FROM sys.databases d
LEFT JOIN msdb.dbo.backupset b ON b.database_name = d.name
WHERE d.database_id <> 2   -- hors tempdb
GROUP BY d.name, d.recovery_model_desc
ORDER BY dernier_full;
PRINT '  Alerte si dernier_full ancien, ou recovery=FULL sans log recent.';

/*------------------------------------------------------------------
  10. INTEGRITE - DERNIER DBCC CHECKDB PROPRE
------------------------------------------------------------------*/
PRINT '';
PRINT '--- 10. DERNIER DBCC CHECKDB PROPRE ------------------------';
BEGIN TRY
    IF OBJECT_ID('tempdb..#chk') IS NOT NULL DROP TABLE #chk;
    CREATE TABLE #chk (ParentObject varchar(255), [Object] varchar(255),
                       Field varchar(255), [Value] varchar(255));
    IF OBJECT_ID('tempdb..#lkg') IS NOT NULL DROP TABLE #lkg;
    CREATE TABLE #lkg (base sysname, last_known_good varchar(50));
    DECLARE @db sysname, @cmd nvarchar(400);
    DECLARE c2 CURSOR LOCAL FAST_FORWARD FOR
        SELECT name FROM sys.databases WHERE state = 0 AND database_id <> 2;
    OPEN c2; FETCH NEXT FROM c2 INTO @db;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        TRUNCATE TABLE #chk;
        SET @cmd = N'DBCC DBINFO(' + QUOTENAME(@db,'''') + N') WITH TABLERESULTS, NO_INFOMSGS';
        INSERT INTO #chk EXEC (@cmd);
        INSERT INTO #lkg(base, last_known_good)
        SELECT @db, MAX([Value]) FROM #chk WHERE Field = 'dbi_dbccLastKnownGood';
        FETCH NEXT FROM c2 INTO @db;
    END
    CLOSE c2; DEALLOCATE c2;
    SELECT base, last_known_good,
           CASE WHEN TRY_CONVERT(datetime, last_known_good) < DATEADD(day,-7,GETDATE())
                THEN 'CHECKDB > 7 jours' ELSE 'ok' END AS note
    FROM #lkg ORDER BY last_known_good;
END TRY
BEGIN CATCH
    PRINT '  Lecture DBCC DBINFO impossible : ' + ERROR_MESSAGE();
END CATCH;

/*------------------------------------------------------------------
  11. SECURITE - COMPTES A PRIVILEGES
------------------------------------------------------------------*/
PRINT '';
PRINT '--- 11. MEMBRES DE sysadmin --------------------------------';
SELECT sp.name AS login_name, sp.type_desc, sp.is_disabled, sp.create_date
FROM sys.server_role_members rm
JOIN sys.server_principals r  ON r.principal_id  = rm.role_principal_id
JOIN sys.server_principals sp ON sp.principal_id = rm.member_principal_id
WHERE r.name = 'sysadmin'
ORDER BY sp.name;

PRINT '';
PRINT '--- 11b. COMPTE sa -----------------------------------------';
SELECT name AS compte_sa, is_disabled,
       CASE WHEN name = 'sa' THEN 'non renomme' ELSE 'renomme (bien)' END AS note
FROM sys.server_principals WHERE sid = 0x01;

PRINT '';
PRINT '--- 11c. LOGINS SQL SANS POLITIQUE DE MDP ------------------';
SELECT name, is_policy_checked, is_expiration_checked, is_disabled
FROM sys.sql_logins
WHERE (is_policy_checked = 0 OR is_expiration_checked = 0) AND is_disabled = 0
ORDER BY name;

PRINT '';
PRINT '================= FIN AUDIT CONFIGURATION ==================';
GO


