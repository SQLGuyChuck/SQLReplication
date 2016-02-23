IF NOT EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'prc_Repl_ReplicationSubscribers' And ROUTINE_SCHEMA = 'dbo')
BEGIN
	EXEC('CREATE Procedure dbo.prc_Repl_ReplicationSubscribers  as raiserror(''Empty Stored Procedure!!'', 10, 1) with seterror')
	IF (@@error = 0)
		PRINT 'Successfully created empty stored procedure dbo.prc_Repl_ReplicationSubscribers.'
	ELSE
	BEGIN
		PRINT 'FAILED to create stored procedure dbo.prc_Repl_ReplicationSubscribers.'
	END
END
GO

ALTER PROCEDURE [dbo].[prc_Repl_ReplicationSubscribers]
AS
BEGIN
SET NOCOUNT ON
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

BEGIN TRY
	-- SUBSCRIPTIONS
	CREATE TABLE #tmp_subscriptions (
		publisher			sysname not null,
		publisher_db		sysname not null,
		publication			sysname null,
		replication_type	int not NULL,
		subscription_type	int not NULL,
		last_updated		datetime null,
		subscriber_db		sysname not null,
		update_mode			smallint null,
		last_sync_status	int null,
		last_sync_summary	sysname null,
		last_sync_time		datetime null
		) 		
	DECLARE @DBID int
		,@DBName sysname
		,@DBStatus int
		,@Incr smallint
		,@MaxIncr smallint
		,@DBMode varchar(60)
		,@StatusMsg varchar(250)
		,@script nvarchar(MAX)

	DECLARE @DBList Table (ID smallint Identity(1,1), DBName sysname, [DBID] int, DBStatus int)

	Insert into @DBList (DBName, [DBID], DBStatus)
		SELECT name, dbid, status
		FROM master.dbo.sysdatabases
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
			PRINT @StatusMsg
			Goto NextDB
		END

		--Put Code here for executing on each of the databases.
		SET @script = 'EXEC [' + @DBName + '].sys.sp_MSenumsubscriptions @subscription_type = ''both'', @reserved = 1'
		
		EXEC (@script)
		
		NextDB:
		Set @Incr = @Incr + 1
	END

	SELECT publisher, publisher_db, publication
		  , CONVERT(varchar(20),CASE replication_type 
				when 0 then 'Transactional'
				when 1 then 'Snapshot'
				when 2 then 'Merge'
				END) replication_type
		  , CONVERT(varchar(20),CASE subscription_type 
				when 0 then 'Push'
				when 1 then 'Pull' 
				when 2 then 'Anonymous' 
				END) subscription_type
		  , last_updated, subscriber_db
		  , update_mode
		  , last_sync_status, last_sync_summary, last_sync_time
	FROM #tmp_subscriptions

	DROP TABLE #tmp_subscriptions
	
END TRY
BEGIN CATCH
	PRINT 'Error catched. Please run the script step by step or contact a DBA.'
END CATCH
END