-- Database properties judged by the compliance rules: AUTO_CLOSE, TRUSTWORTHY,
-- and the Query Store state.
--
-- query_store_state is sys.database_query_store_options.actual_state_desc
-- (OFF, READ_ONLY, READ_WRITE, ERROR), read in each database's own context.
-- It is left empty, i.e. not judged, when it cannot be meaningful:
--   * before SQL Server 2016 (major 13): no Query Store at all. The view is only
--     named inside dynamic SQL, so older instances never compile a reference to
--     it -- a static one would fail the whole file on 2012/2014;
--   * system databases, offline databases, and databases that are not
--     READ_WRITE (AG secondaries, read-only databases);
--   * a database whose read fails (TRY/CATCH): one bad database must not cost
--     the file of the whole instance.
SET NOCOUNT ON;
DECLARE @major int = CAST(PARSENAME(CONVERT(varchar(32), SERVERPROPERTY('ProductVersion')), 4) AS int);
DECLARE @id int, @name sysname, @sql nvarchar(max), @state nvarchar(60);
CREATE TABLE #qs (database_id int PRIMARY KEY, state nvarchar(60));
IF @major >= 13
BEGIN
   DECLARE dbs CURSOR LOCAL FAST_FORWARD FOR
      SELECT database_id, name
        FROM sys.databases
       WHERE database_id > 4
         AND state = 0
         AND CONVERT(varchar(20), DATABASEPROPERTYEX(name, 'Updateability')) = 'READ_WRITE';
   OPEN dbs;
   FETCH NEXT FROM dbs INTO @id, @name;
   WHILE @@FETCH_STATUS = 0
   BEGIN
      SET @state = NULL;
      BEGIN TRY
         SET @sql = N'SELECT @s = actual_state_desc FROM ' + QUOTENAME(@name)
                  + N'.sys.database_query_store_options';
         EXEC sp_executesql @sql, N'@s nvarchar(60) OUTPUT', @s = @state OUTPUT;
      END TRY
      BEGIN CATCH
         SET @state = NULL;
      END CATCH;
      INSERT INTO #qs ( database_id, state ) VALUES ( @id, @state );
      FETCH NEXT FROM dbs INTO @id, @name;
   END;
   CLOSE dbs;
   DEALLOCATE dbs;
END;
SELECT
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),@@servername),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(128),d.name),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),d.is_auto_close_on),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(10),d.is_trustworthy_on),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'+','+
 '"'+REPLACE(ISNULL(CONVERT(varchar(60),q.state),'') COLLATE DATABASE_DEFAULT,'"','""')+'"'
FROM sys.databases d
LEFT JOIN #qs q ON q.database_id = d.database_id;
DROP TABLE #qs;
GO
