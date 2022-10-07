IF NOT EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'prc_Repl_Articles' And ROUTINE_SCHEMA = 'dbo')
BEGIN
	EXEC('Create Procedure dbo.prc_Repl_Articles  as raiserror(''Empty Stored Procedure!!'', 10, 1) with seterror')
	IF (@@error = 0)
		PRINT 'Successfully created empty stored procedure dbo.prc_Repl_Articles.'
	ELSE
	BEGIN
		PRINT 'FAILED to create stored procedure dbo.prc_Repl_Articles.'
	END
END
GO

ALTER PROCEDURE dbo.prc_Repl_Articles
AS
BEGIN
	IF (DB_ID('distribution') IS NOT NULL)
	BEGIN
		SELECT s.publisher_id, ss2.data_source, a.publisher_db, p.publication
		 , s.subscriber_id, ss.srvname as SubscriberServer, s.subscriber_db
		 , a.source_owner, a.source_object 
		 , ISNULL(a.destination_owner, a.source_owner) destination_owner -- if NULL, schema name remains same at subscriber side 
		 , a.destination_object 
		FROM distribution.dbo.MSarticles AS a 
			INNER JOIN distribution.dbo.MSsubscriptions AS s ON a.publication_id = s.publication_id AND a.article_id = s.article_id 
			INNER JOIN distribution.[dbo].[MSreplservers] AS ss ON s.subscriber_id = ss.srvid 
			INNER JOIN distribution.dbo.MSpublications AS p ON s.publication_id = p.publication_id 
			LEFT JOIN master.sys.servers AS ss2 ON p.publisher_id = ss2.server_id 
		WHERE s.subscriber_db <> 'virtual'
		ORDER BY ss2.data_source, a.publisher_db, p.publication
			, ss.srvname, a.source_owner, a.source_object 
	END
	ELSE
	BEGIN
		PRINT 'Database  ''distribution'' doesn''t exists.'
	END
END
GO


