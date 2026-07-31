/*==============================================================================
  mssql_healthcheck_legacy.sql
  Audit de configuration compatible SQL Server 2005 SP4 / 2008 SP2+
  ------------------------------------------------------------------------------
  Versions visees :
    - SQL Server 2005 : 9.00.x
    - SQL Server 2008 : 10.00.x
    - Compatible avec les versions plus recentes pour les controles generiques

  Execution :
    sqlcmd -S <serveur> -E -i mssql_healthcheck_legacy.sql -o rapport.txt

  Droits conseilles :
    VIEW SERVER STATE + VIEW ANY DEFINITION + lecture de msdb.
    Certains DBCC peuvent necessiter des droits superieurs.

  Lecture seule : aucune configuration ni donnee utilisateur n'est modifiee.
==============================================================================*/

SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @major_version int;
SET @major_version =
    CONVERT(int, LEFT(CONVERT(varchar(30), SERVERPROPERTY('ProductVersion')),
                      CHARINDEX('.', CONVERT(varchar(30), SERVERPROPERTY('ProductVersion'))) - 1));

PRINT '================================================================';
PRINT ' AUDIT CONFIGURATION SQL SERVER - VERSION LEGACY';
PRINT ' Serveur : ' + CONVERT(varchar(128), @@SERVERNAME)
    + '   |   ' + CONVERT(varchar(30), GETDATE(), 120);
PRINT ' Version majeure detectee : ' + CONVERT(varchar(10), @major_version);
PRINT '================================================================';

/*------------------------------------------------------------------
  1. IDENTITE INSTANCE
------------------------------------------------------------------*/
PRINT '';
PRINT '--- 1. IDENTITE INSTANCE -----------------------------------';

SELECT
      SERVERPROPERTY('MachineName')                            AS machine
    , SERVERPROPERTY('ServerName')                             AS instance
    , SERVERPROPERTY('Edition')                                AS edition
    , SERVERPROPERTY('ProductVersion')                         AS version
    , SERVERPROPERTY('ProductLevel')                           AS niveau_sp
    , SERVERPROPERTY('Collation')                              AS collation_srv
    , CAST(SERVERPROPERTY('IsClustered') AS int)               AS is_cluster
    , CAST(SERVERPROPERTY('IsIntegratedSecurityOnly') AS int)  AS auth_windows_only
    , osi.cpu_count
    , CAST(osi.physical_memory_in_bytes / 1024.0 / 1024 / 1024
           AS decimal(10,1))                                   AS ram_go
    , tempdb.create_date                                       AS demarrage_sql_estime
    , DATEDIFF(day, tempdb.create_date, GETDATE())              AS uptime_jours
FROM sys.dm_os_sys_info AS osi
CROSS JOIN
(
    SELECT create_date
    FROM sys.databases
    WHERE database_id = 2
) AS tempdb;

/*------------------------------------------------------------------
  2. PARAMETRES INSTANCE
------------------------------------------------------------------*/
PRINT '';
PRINT '--- 2. PARAMETRES INSTANCE ---------------------------------';

SELECT
      c.name
    , c.value_in_use
    , c.value AS value_configuree
    , CASE c.name
        WHEN 'max server memory (MB)'         THEN '< RAM totale, laisser une marge OS'
        WHEN 'min server memory (MB)'         THEN '0 sauf besoin specifique'
        WHEN 'max degree of parallelism'      THEN 'a adapter aux CPU et a la charge'
        WHEN 'cost threshold for parallelism' THEN 'souvent superieur au defaut 5'
        WHEN 'optimize for ad hoc workloads'  THEN '1 si disponible et pertinent'
        WHEN 'backup compression default'     THEN '1 si edition/version compatible'
        WHEN 'remote admin connections'       THEN '1 pour DAC distante'
        WHEN 'xp_cmdshell'                    THEN '0 sauf besoin justifie'
        WHEN 'Ad Hoc Distributed Queries'     THEN '0 sauf besoin justifie'
        WHEN 'Ole Automation Procedures'      THEN '0 sauf besoin justifie'
        WHEN 'max worker threads'             THEN '0 = automatique'
        WHEN 'fill factor (%)'                THEN '0/100 sauf tuning cible'
        ELSE ''
      END AS reference
FROM sys.configurations AS c
WHERE c.name IN
(
      'max server memory (MB)', 'min server memory (MB)',
      'max degree of parallelism', 'cost threshold for parallelism',
      'optimize for ad hoc workloads', 'backup compression default',
      'remote admin connections', 'xp_cmdshell',
      'Ad Hoc Distributed Queries', 'Ole Automation Procedures',
      'max worker threads', 'fill factor (%)',
      'default trace enabled', 'clr enabled', 'remote access'
)
ORDER BY c.name;

/*------------------------------------------------------------------
  3. PARAMETRES OS / MEMOIRE
------------------------------------------------------------------*/
PRINT '';
PRINT '--- 3. PARAMETRES OS / MEMOIRE -----------------------------';

SELECT
      cpu_count
    , hyperthread_ratio
    , CAST(physical_memory_in_bytes / 1024.0 / 1024 / 1024
           AS decimal(10,1)) AS ram_physique_go
    , CAST(virtual_memory_in_bytes / 1024.0 / 1024 / 1024
           AS decimal(10,1)) AS espace_adressage_virtuel_go
    , bpool_committed
    , bpool_commit_target
    , bpool_visible
FROM sys.dm_os_sys_info;

PRINT '  Note : IFI et LPIM ne sont pas exposes de maniere fiable par les DMV';
PRINT '         SQL Server 2005/2008. Ils doivent etre controles cote Windows.';

/*------------------------------------------------------------------
  4. TRACE FLAGS ACTIFS
------------------------------------------------------------------*/
PRINT '';
PRINT '--- 4. TRACE FLAGS GLOBAUX ---------------------------------';

IF OBJECT_ID('tempdb..#tf') IS NOT NULL
    DROP TABLE #tf;

CREATE TABLE #tf
(
      TraceFlag int
    , Status int
    , [Global] int
    , [Session] int
);

BEGIN TRY
    INSERT INTO #tf
    EXEC ('DBCC TRACESTATUS(-1) WITH NO_INFOMSGS');

    IF EXISTS (SELECT 1 FROM #tf)
    BEGIN
        SELECT
              TraceFlag
            , [Global]
            , [Session]
            , CASE TraceFlag
                WHEN 3226 THEN 'supprime les messages de backups reussis'
                WHEN 1117 THEN 'croissance uniforme de tous les fichiers'
                WHEN 1118 THEN 'allocation par extents uniformes'
                ELSE ''
              END AS note
        FROM #tf
        ORDER BY TraceFlag;
    END
    ELSE
        PRINT '  Aucun trace flag global actif.';
END TRY
BEGIN CATCH
    PRINT '  Lecture des trace flags impossible : ' + ERROR_MESSAGE();
END CATCH;

/*------------------------------------------------------------------
  5. TEMPDB
------------------------------------------------------------------*/
PRINT '';
PRINT '--- 5. TEMPDB (FICHIERS) -----------------------------------';

SELECT
      mf.file_id
    , mf.name
    , mf.type_desc
    , CAST(mf.size * 8 / 1024.0 AS decimal(12,1)) AS taille_mo
    , CASE
        WHEN mf.is_percent_growth = 1
            THEN CONVERT(varchar(30), mf.growth) + ' %'
        ELSE CONVERT(varchar(30), mf.growth * 8 / 1024) + ' Mo'
      END AS autogrowth
    , mf.physical_name
FROM sys.master_files AS mf
WHERE mf.database_id = 2
ORDER BY mf.type, mf.file_id;

PRINT '  Reco legacy : fichiers data de meme taille et autogrowth fixe en Mo.';
PRINT '  Sur SQL 2005/2008, verifier egalement les trace flags 1117 et 1118.';

/*------------------------------------------------------------------
  6. BASES - ETAT ET OPTIONS
------------------------------------------------------------------*/
PRINT '';
PRINT '--- 6. BASES - ETAT ET OPTIONS -----------------------------';

SELECT
      d.name
    , d.state_desc
    , d.recovery_model_desc AS recovery
    , d.compatibility_level AS compat
    , d.page_verify_option_desc AS page_verify
    , d.is_auto_close_on AS auto_close
    , d.is_auto_shrink_on AS auto_shrink
    , d.is_auto_create_stats_on AS auto_create_stats
    , d.is_auto_update_stats_on AS auto_update_stats
    , d.is_read_committed_snapshot_on AS rcsi
    , SUSER_SNAME(d.owner_sid) AS proprietaire
FROM sys.databases AS d
ORDER BY d.database_id;

/*------------------------------------------------------------------
  7. TAILLE DATA / LOG
------------------------------------------------------------------*/
PRINT '';
PRINT '--- 7. TAILLE DATA / LOG -----------------------------------';

SELECT
      DB_NAME(mf.database_id) AS base
    , CAST(SUM(CASE WHEN mf.type = 0 THEN mf.size ELSE 0 END)
           * 8 / 1024.0 AS decimal(14,1)) AS data_mo
    , CAST(SUM(CASE WHEN mf.type = 1 THEN mf.size ELSE 0 END)
           * 8 / 1024.0 AS decimal(14,1)) AS log_mo
FROM sys.master_files AS mf
GROUP BY mf.database_id
ORDER BY base;

PRINT '';
PRINT '  Utilisation du transaction log :';
DBCC SQLPERF(LOGSPACE);

/*------------------------------------------------------------------
  8. NOMBRE DE VLF - METHODE DBCC LOGINFO POUR SQL 2005/2008
------------------------------------------------------------------*/
PRINT '';
PRINT '--- 8. NOMBRE DE VLF PAR BASE ------------------------------';

IF OBJECT_ID('tempdb..#vlf_result') IS NOT NULL
    DROP TABLE #vlf_result;

IF OBJECT_ID('tempdb..#loginfo') IS NOT NULL
    DROP TABLE #loginfo;

CREATE TABLE #vlf_result
(
      base sysname
    , vlf_count int
    , erreur varchar(4000) NULL
);

CREATE TABLE #loginfo
(
      FileId int
    , FileSize numeric(38,0)
    , StartOffset numeric(38,0)
    , FSeqNo numeric(38,0)
    , [Status] int
    , Parity int
    , CreateLSN numeric(38,0)
);

DECLARE @vlf_db sysname;
DECLARE @vlf_cmd nvarchar(1000);

DECLARE cdb CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE state = 0;

OPEN cdb;
FETCH NEXT FROM cdb INTO @vlf_db;

WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        TRUNCATE TABLE #loginfo;

        SET @vlf_cmd =
            N'DBCC LOGINFO (' + QUOTENAME(@vlf_db, '''')
            + N') WITH NO_INFOMSGS';

        INSERT INTO #loginfo
        EXEC (@vlf_cmd);

        INSERT INTO #vlf_result(base, vlf_count, erreur)
        SELECT @vlf_db, COUNT(*), NULL
        FROM #loginfo;
    END TRY
    BEGIN CATCH
        INSERT INTO #vlf_result(base, vlf_count, erreur)
        VALUES (@vlf_db, NULL, ERROR_MESSAGE());
    END CATCH;

    FETCH NEXT FROM cdb INTO @vlf_db;
END

CLOSE cdb;
DEALLOCATE cdb;

SELECT
      base
    , vlf_count
    , CASE
        WHEN erreur IS NOT NULL THEN 'ERREUR : ' + erreur
        WHEN vlf_count > 1000 THEN 'ELEVE - correction a planifier'
        WHEN vlf_count > 300 THEN 'a surveiller'
        ELSE 'ok'
      END AS note
FROM #vlf_result
ORDER BY
      CASE WHEN vlf_count IS NULL THEN 1 ELSE 0 END
    , vlf_count DESC
    , base;

/*------------------------------------------------------------------
  9. DERNIERES SAUVEGARDES
------------------------------------------------------------------*/
PRINT '';
PRINT '--- 9. DERNIERES SAUVEGARDES -------------------------------';

SELECT
      d.name AS base
    , d.recovery_model_desc AS recovery
    , MAX(CASE WHEN b.type = 'D' THEN b.backup_finish_date END) AS dernier_full
    , MAX(CASE WHEN b.type = 'I' THEN b.backup_finish_date END) AS dernier_diff
    , MAX(CASE WHEN b.type = 'L' THEN b.backup_finish_date END) AS dernier_log
FROM sys.databases AS d
LEFT JOIN msdb.dbo.backupset AS b
    ON b.database_name = d.name
WHERE d.database_id <> 2
GROUP BY d.name, d.recovery_model_desc
ORDER BY dernier_full;

PRINT '  Alerte si le dernier FULL est ancien ou si une base FULL';
PRINT '  ne dispose pas de sauvegardes du journal recentes.';

/*------------------------------------------------------------------
  10. DERNIER DBCC CHECKDB CONNU
------------------------------------------------------------------*/
PRINT '';
PRINT '--- 10. DERNIER DBCC CHECKDB CONNU -------------------------';

IF OBJECT_ID('tempdb..#chk') IS NOT NULL
    DROP TABLE #chk;

IF OBJECT_ID('tempdb..#lkg') IS NOT NULL
    DROP TABLE #lkg;

CREATE TABLE #chk
(
      ParentObject varchar(255)
    , [Object] varchar(255)
    , Field varchar(255)
    , [Value] varchar(255)
);

CREATE TABLE #lkg
(
      base sysname
    , last_known_good varchar(255) NULL
    , last_known_good_dt datetime NULL
    , erreur varchar(4000) NULL
);

DECLARE @check_db sysname;
DECLARE @check_cmd nvarchar(1000);
DECLARE @last_good varchar(255);

DECLARE c2 CURSOR LOCAL FAST_FORWARD FOR
    SELECT name
    FROM sys.databases
    WHERE state = 0
      AND database_id <> 2;

OPEN c2;
FETCH NEXT FROM c2 INTO @check_db;

WHILE @@FETCH_STATUS = 0
BEGIN
    BEGIN TRY
        TRUNCATE TABLE #chk;

        SET @check_cmd =
            N'DBCC DBINFO (' + QUOTENAME(@check_db, '''')
            + N') WITH TABLERESULTS, NO_INFOMSGS';

        INSERT INTO #chk
        EXEC (@check_cmd);

        SET @last_good = NULL;

        SELECT @last_good = MAX([Value])
        FROM #chk
        WHERE Field = 'dbi_dbccLastKnownGood';

        INSERT INTO #lkg(base, last_known_good, last_known_good_dt, erreur)
        VALUES
        (
              @check_db
            , @last_good
            , CASE
                WHEN ISDATE(@last_good) = 1 THEN CONVERT(datetime, @last_good)
                ELSE NULL
              END
            , NULL
        );
    END TRY
    BEGIN CATCH
        INSERT INTO #lkg(base, last_known_good, last_known_good_dt, erreur)
        VALUES (@check_db, NULL, NULL, ERROR_MESSAGE());
    END CATCH;

    FETCH NEXT FROM c2 INTO @check_db;
END

CLOSE c2;
DEALLOCATE c2;

SELECT
      base
    , last_known_good
    , last_known_good_dt
    , CASE
        WHEN erreur IS NOT NULL THEN 'ERREUR : ' + erreur
        WHEN last_known_good IS NULL THEN 'aucune date trouvee'
        WHEN last_known_good_dt IS NULL THEN 'date non reconnue'
        WHEN last_known_good_dt < DATEADD(day, -7, GETDATE())
            THEN 'CHECKDB > 7 jours'
        ELSE 'ok'
      END AS note
FROM #lkg
ORDER BY
      CASE WHEN last_known_good_dt IS NULL THEN 1 ELSE 0 END
    , last_known_good_dt;

/*------------------------------------------------------------------
  11. SECURITE - COMPTES A PRIVILEGES
------------------------------------------------------------------*/
PRINT '';
PRINT '--- 11. MEMBRES DE sysadmin --------------------------------';

SELECT
      sp.name AS login_name
    , sp.type_desc
    , sp.is_disabled
    , sp.create_date
FROM sys.server_role_members AS rm
JOIN sys.server_principals AS r
    ON r.principal_id = rm.role_principal_id
JOIN sys.server_principals AS sp
    ON sp.principal_id = rm.member_principal_id
WHERE r.name = 'sysadmin'
ORDER BY sp.name;

PRINT '';
PRINT '--- 11b. COMPTE sa -----------------------------------------';

SELECT
      name AS compte_sa
    , is_disabled
    , CASE
        WHEN name = 'sa' THEN 'non renomme'
        ELSE 'renomme'
      END AS note
FROM sys.server_principals
WHERE sid = 0x01;

PRINT '';
PRINT '--- 11c. LOGINS SQL SANS POLITIQUE DE MDP ------------------';

SELECT
      name
    , is_policy_checked
    , is_expiration_checked
    , is_disabled
FROM sys.sql_logins
WHERE (is_policy_checked = 0 OR is_expiration_checked = 0)
  AND is_disabled = 0
ORDER BY name;

PRINT '';
PRINT '================= FIN AUDIT CONFIGURATION ==================';
GO


