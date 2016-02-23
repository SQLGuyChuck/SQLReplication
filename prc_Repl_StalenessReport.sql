IF (OBJECT_ID('dbo.prc_Repl_StalenessReport') IS NULL)
BEGIN
	EXEC('create procedure dbo.prc_Repl_StalenessReport  as raiserror(''Empty Stored Procedure!!'', 16, 1) with seterror')
	IF (@@error = 0)
		PRINT 'Successfully created empty stored procedure dbo.prc_Repl_StalenessReport.'
	ELSE
	BEGIN
		PRINT 'FAILED to create stored procedure dbo.prc_Repl_StalenessReport.'
	END
END
GO
ALTER PROCEDURE dbo.prc_Repl_StalenessReport 
   @UndelivCmdsInDistDB  INT = 1000, 
   @NotificationEmailAddress VARCHAR(200)
AS
BEGIN
/*************************************************************************************************
**
**  File: prc_Repl_StalenessReport
**
** Desc: Create HTML email report of all subscriptions that are greater than @UndelivCmdsInDistDB rows behind publisher.
**  Install: Put this as a job step on your distributor server. 
**     If your distribution database is not named distributor, change code below manually to its name.
**
**  11/1/2010		Chuck Lathrope  Utilized MSdistribution_status table
**   5/3/2012		Chuck Lathrope  Added query hint to help greatly.
**   7/1/2013		Chuck Lathrope  Ignore Virtual subscribers used with immediate_sync = on.
** 12/28/2013		Chuck Lathrope  Added notes on immediate_sync if you want to see its info.
**                                     And type conversion for int status values.
**   1/3/2013		Chuck Lathrope  Perf improvements; Addition of last time sync on dist agent
*************************************************************************************************/

   SET NOCOUNT ON;
   SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

   --Put this as a job step on your distributor.
   DECLARE @TableHTML NVARCHAR(MAX), @SubjectMsg VARCHAR(150), @HighPriority BIT

   SELECT @SubjectMsg = 'Half-Hourly Replication Status ' + CONVERT(VARCHAR(25),GETDATE()) + ' ' + @@servername 

   --Final data select statement:
   SELECT @TableHTML =    
       N'<H2>' + @SubjectMsg + '</H2>' + 
       N'<table border="1" cellpadding="0" cellspacing="2">' +    
       N'<tr><th>Status Code</th><th>Last Synchronized</th>' +
       N'<th>PublisherDB-Subscriber</th><th>Undelivered Cmds</th><th>Subscriber DB</th><th>Subscription Type</th></tr>' + 
       CAST ( ( SELECT
           td = CASE 
           --This 10000 value is arbitrary for your environment and just to help clue everyone this is a Severe latency message.
            WHEN und.UndelivCmdsInDistDB > 10000 AND mda.subscription_type > 0 THEN 'Severe Latency!' 
            WHEN mdh.runstatus = 1 THEN 'Start'
            WHEN mdh.runstatus = 2 THEN 'Succeed'
            WHEN mdh.runstatus = 3 THEN 'InProgress'
            WHEN mdh.runstatus = 4 THEN 'Idle'
            WHEN mdh.runstatus = 5 THEN 'Retry'
            WHEN mdh.runstatus = 6 THEN 'Fail'
            WHEN mdh.runstatus = 0 AND mda.subscription_type = 0 THEN 'PushPublication'
           END, '',
       td = CONVERT(VARCHAR(25),mdh.[time]), '',
       td = mda.name, '',
       td = und.UndelivCmdsInDistDB, '',
       td = mda.subscriber_db, '',
       td = CASE 
            WHEN mda.subscription_type = 0 THEN 'Push'
            WHEN mda.subscription_type = 1 THEN 'Pull'
            WHEN mda.subscription_type = 2 THEN 'Anonymous'
           END 
       FROM Distribution.dbo.MSdistribution_agents mda
       JOIN Distribution.dbo.MSdistribution_history mdh ON mdh.agent_id = mda.id
       JOIN (
           SELECT h.agent_id, MAX([time]) MaxTimeValue
           FROM Distribution.dbo.msdistribution_agents a
           JOIN Distribution.dbo.MSdistribution_history h ON h.agent_id=a.id
           WHERE a.subscriber_db <> 'virtual'--we don't care about immediate_sync storage.
               --If you do care, change to this: AND mda.subscriber_id >= -1
           GROUP BY h.agent_id) x ON x.MaxTimeValue = mdh.time AND x.agent_id = mda.id
       JOIN (       
               SELECT st.agent_id, SUM(st.UndelivCmdsInDistDB) AS UndelivCmdsInDistDB--select *
               FROM Distribution.dbo.MSdistribution_status st
               GROUP BY st.agent_id 
           ) und ON mda.id = und.agent_id
       WHERE (UndelivCmdsInDistDB > @UndelivCmdsInDistDB
       AND mda.subscriber_db <> 'virtual') --we don't care about immediate_sync storage.
           --If you do care, change to this: AND mda.subscriber_id >= -1
       OR MaxTimeValue < DATEADD(hh,-1,GETDATE()) --Nothing has happened in an hour on distribution agent
           FOR XML PATH('tr')
   ) AS NVARCHAR(MAX) ) +    
   N'</table><br />
Escalation notes:<br />
Severe Latency = Undelivered Cmds > Latency Limit.<br />
Last Synchronized time value should be less than an hour.<br />
If numbers continue to increase over subsequent alert emails, call on-call DBA to investigate.<br />
</HTML>' 

If @tableHTML LIKE '%Fail%' OR @tableHTML LIKE '%Severe Latency!%'
BEGIN
	SET @HighPriority = 1
END

If @tableHTML is not null
	exec dbo.prc_internalsendmail 
	@HighPriority=@HighPriority, 
	@address=@NotificationEmailAddress, 
	@subject=@subjectMsg, 
	@body=@tableHTML, @HTML=1

END --Proc creation.
