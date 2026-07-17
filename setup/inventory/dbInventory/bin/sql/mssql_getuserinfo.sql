EXEC sp_MSforeachdb
	'
	 SELECT
	   CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),@@SERVERNAME),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
	   CHAR(34)+''?''+CHAR(34)+'',''+
	   CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),u.name),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
	   CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),CASE WHEN (r.principal_id IS NULL) THEN ''public'' ELSE r.name END),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
	   CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),l.name),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
	   CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),l.default_database_name),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
	   CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(128),u.default_schema_name),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
	   CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(20),u.principal_id),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)+'',''+
	   CHAR(34)+REPLACE(ISNULL(CONVERT(varchar(85),u.sid,1),'''') COLLATE DATABASE_DEFAULT,CHAR(34),CHAR(34)+CHAR(34))+CHAR(34)
	 FROM [?].sys.database_principals u
	   LEFT JOIN ([?].sys.database_role_members m
	   JOIN [?].sys.database_principals r
	   ON m.role_principal_id = r.principal_id)
	   ON m.member_principal_id = u.principal_id
	   LEFT JOIN [?].sys.server_principals l
	   ON u.sid = l.sid
	 WHERE u.TYPE <> ''R''
	   /*and u.name like ''tester''*/
	 order by u.name
	 '
