IF NOT EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'prc_Repl_Publications' And ROUTINE_SCHEMA = 'dbo')
BEGIN
	EXEC('CREATE Procedure dbo.prc_Repl_Publications  as raiserror(''Empty Stored Procedure!!'', 10, 1) with seterror')
	IF (@@error = 0)
		PRINT 'Successfully created empty stored procedure dbo.prc_Repl_Publications.'
	ELSE
	BEGIN
		PRINT 'FAILED to create stored procedure dbo.prc_Repl_Publications.'
	END
END
GO

ALTER PROCEDURE dbo.prc_Repl_Publications
AS
BEGIN

SET NOCOUNT ON
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
	
BEGIN TRY
	-- PUBLICATIONS
	CREATE TABLE #tmp_publications (
		publisher			sysname not null,
		dbname				sysname not null,
		publication			sysname not null,
		publisher_type		sysname not null,
		publication_type	int not null,
		description			nvarchar(255) null,
		allow_queued		bit default 0 NOT NULL,
		enabled_for_p2p		bit default 0 NOT NULL,
		enabled_for_p2pconflictdetection		bit default 0 NOT NULL
	)

	DECLARE @DBID int
		,@DBName sysname
		,@DBStatus int
		,@Incr smallint
		,@MaxIncr smallint
		,@DBMode varchar(60)
		,@StatusMsg varchar(250)
		, @script nvarchar(MAX)

	DECLARE @DBList Table (ID smallint Identity(1,1), DBName sysname, [DBID] int, DBStatus int)

	Insert into @DBList (DBName, [DBID], DBStatus)
		SELECT name, dbid, status
		FROM master..sysdatabases
		WHERE [name] NOT IN ('tempdb', 'model')

	Select @MaxIncr = @@RowCount, @Incr = 1

	--Select * from @DBList

	While @Incr <= @MaxIncr
	BEGIN
		--Set variables
		SELECT @DBName = DBName, @DBID = [DBID], @DBStatus = DBStatus
		From @DBList
		Where ID = @Incr

		--Check Database Accessibility
		SELECT @DBMode = 'OK'

		IF DATABASEPROPERTY(@DBName, 'IsDetached') > 0 
			SELECT @DBMode = 'Detached'
		ELSE IF DATABASEPROPERTY(@DBName, 'IsInLoad') > 0 
			SELECT @DBMode = 'Loading'
		ELSE IF DATABASEPROPERTY(@DBName, 'IsNotRecovered') > 0 
			SELECT @DBMode = 'Not Recovered'
		ELSE IF DATABASEPROPERTY(@DBName, 'IsInRecovery') > 0 
			SELECT @DBMode = 'Recovering'
		ELSE IF DATABASEPROPERTY(@DBName, 'IsSuspect') > 0 
			SELECT @DBMode = 'Suspect'
		ELSE IF DATABASEPROPERTY(@DBName, 'IsOffline') > 0  	
			SELECT @DBMode = 'Offline'
		ELSE IF DATABASEPROPERTY(@DBName, 'IsEmergencyMode') > 0 
			SELECT @DBMode = 'Emergency Mode'
		ELSE IF DATABASEPROPERTY(@DBName, 'IsShutDown') > 0 
			SELECT @DBMode = 'Shut Down (problems during startup)'

		IF @DBMode <> 'OK'
		BEGIN
			Set @StatusMsg = 'Skipping database ' + @DBName + ' - Database is in '  + @DBMode + ' state.'
			--PRINT @StatusMsg
			Goto NextDB
		END

		--Put Code here for executing on each of the databases.
		SET @script = 'EXEC [' + @DBName + '].sys.sp_MSrepl_enumpublications @reserved = 1'
		--PRINT @script
		EXEC (@script)
		
		NextDB:
		Set @Incr = @Incr + 1
	END

	SELECT publisher, dbname, publication, publisher_type
		, publication_type 
		, description, allow_queued, enabled_for_p2p, enabled_for_p2pconflictdetection
	FROM #tmp_publications
	
	DROP TABLE #tmp_publications
	
	END TRY
	BEGIN CATCH
		PRINT 'Error catched. Please run the script step by step or contact a DBA.'
	END CATCH
END;
GO


