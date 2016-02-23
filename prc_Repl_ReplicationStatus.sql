IF NOT EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'prc_Repl_ReplicationStatus' And ROUTINE_SCHEMA = 'dbo')
BEGIN
	EXEC('CREATE Procedure dbo.prc_Repl_ReplicationStatus  as raiserror(''Empty Stored Procedure!!'', 10, 1) with seterror')
	IF (@@error = 0)
		PRINT 'Successfully created empty stored procedure dbo.prc_Repl_ReplicationStatus.'
	ELSE
	BEGIN
		PRINT 'FAILED to create stored procedure dbo.prc_Repl_ReplicationStatus.'
	END
END
GO

ALTER PROCEDURE dbo.prc_Repl_ReplicationStatus
AS
BEGIN
	IF (DB_ID('distribution') IS NOT NULL)
	BEGIN
		SELECT
		mda.name
		,mda.subscriber_db
		,mdh.time --convert(varchar(25),mdh.[time]) as lastTran
			,case
				 WHEN mdh.runstatus = '1' THEN 'Start'
				 WHEN mdh.runstatus = '2' THEN 'Succeed'
				 WHEN mdh.runstatus = '3' THEN 'InProgress'
				 WHEN mdh.runstatus = '4' THEN 'Idle'
				 WHEN mdh.runstatus = '5' THEN 'Retry'
				 WHEN mdh.runstatus = '6' THEN 'Fail'
				 WHEN mdh.runstatus = '0' AND mda.subscription_type = '0' THEN 'PushPublication'
			END as Status
		,und.UndelivCmdsInDistDB
		,CASE 
			 WHEN mda.subscription_type =  '0' THEN 'Push'
			 WHEN mda.subscription_type =  '1' THEN 'Pull'
			 WHEN mda.subscription_type =  '2' THEN 'Anonymous'
			END as 	ReplicationType
		FROM distribution.dbo.MSdistribution_agents mda
			JOIN distribution.dbo.MSdistribution_history mdh ON mdh.agent_id = mda.id
			JOIN (
				select max(time) MaxTimeValue, name
				From distribution.dbo.msdistribution_agents a
				join distribution.dbo.MSdistribution_history h on h.agent_id=a.id
				group by name) x on x.MaxTimeValue = mdh.Time and x.name = mda.name
			Join (		
					SELECT st.agent_id, SUM(st.UndelivCmdsInDistDB) as UndelivCmdsInDistDB
					FROM distribution.dbo.MSdistribution_status st
					GROUP BY st.agent_id 
				) und on mda.id = und.agent_id
	END
END
GO


