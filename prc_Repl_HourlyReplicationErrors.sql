IF (OBJECT_ID('dbo.prc_Repl_HourlyReplicationErrors') IS NULL)
BEGIN
	EXEC('create procedure dbo.prc_Repl_HourlyReplicationErrors  as raiserror(''Empty Stored Procedure!!'', 16, 1) with seterror')
	IF (@@error = 0)
		PRINT 'Successfully created empty stored procedure dbo.prc_Repl_HourlyReplicationErrors.'
	ELSE
	BEGIN
		PRINT 'FAILED to create stored procedure dbo.prc_Repl_HourlyReplicationErrors.'
	END
END
GO

ALTER PROCEDURE dbo.prc_Repl_HourlyReplicationErrors 
   @NotificationEmailAddress VARCHAR(200) = 'alerts@?.com', --Default to your distribution list here.
   @IgnorePushedPublications BIT = 1
AS
BEGIN
/*************************************************************************************************
**
**  File: prc_Repl_HourlyReplicationErrors
**
** Desc: Find latest replication errors and send email.
** Install: Put this as a job step on your distributor server. 
**     If your distribution database is not named distributor, change code below manually to its name.
**  
**  11/1/2010  Chuck Lathrope  Added more error tables to capture non-errors, but true issues.
**  11/23/2010  Chuck Lathrope  Bug fix for sections that have 0 rows becomes a NULL in email.
**  9/4/2012   Chuck Lathrope  Added AND mda.subscriber_id > 0 to remove "virtual" subscribers that SQL engine uses.
**  11/21/2012  Chuck Lathrope  Removed date restriction from job status check table results.
**  11/26/2012 Chuck Lathrope  Added exception for RunStatus = 0 which is for Immediate_Sync subscriptions
**  12/28/2013 Chuck Lathrope  Minor changes/bug fixes and note additions
**  5/11/2015  Chuck Lathrope  Added @IgnorePushedPublications parameter to ignore Pull check.
*************************************************************************************************/
   SET NOCOUNT ON;
   SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

   DECLARE @TableHTML NVARCHAR(MAX)
       ,@SubjectMsg VARCHAR(150)
       ,@ErrorText VARCHAR(MAX)
       ,@BadJobStatus VARCHAR(MAX)
       ,@OrphanedErrors VARCHAR(MAX)
       ,@PushedPublications VARCHAR(MAX)

   SELECT @SubjectMsg = 'Hourly Replication Errors Reported on ' + CONVERT(VARCHAR(25), GETDATE()) + ' by server ' + @@servername

   SET @ErrorText = N'<HTML><H2>' + @SubjectMsg + '</H2>' + N'<table border="1" cellpadding="0" cellspacing="2">' 
       + N'<th>PublisherDB-Subscriber</th><th>subscriber_db</th><th>StatusDesc</th><th>LastSynchronized</th><th>Comments</th><th>Query to get more info</th></tr>' 
       + CAST((
           --See all errors in table form:
           SELECT td = mda.Name,''
               ,td = mda.subscriber_db,''
               ,td = CASE 
                 WHEN mdh.runstatus = 1 THEN 'Start'  
                 WHEN mdh.runstatus = 2 THEN 'Succeed/Stopped'  
                 WHEN mdh.runstatus = 3 THEN 'InProgress'  
                 WHEN mdh.runstatus = 4 THEN 'Idle'  
                 WHEN mdh.runstatus = 5 THEN 'Retry'  
                 WHEN mdh.runstatus = 6 THEN 'Failure'  
                END,''
               ,td = mdh.TIME,''
               ,td = mdh.comments,''
               ,td = 'SELECT * FROM Distribution.dbo.msrepl_errors WITH (NOLOCK) WHERE id = ' + CAST(mdh.error_id AS VARCHAR(8))
           FROM Distribution.dbo.MSdistribution_agents mda
           JOIN Distribution.dbo.MSdistribution_history mdh ON mdh.agent_id = mda.id
           JOIN (
               SELECT agent_id
                   ,MAX(error_id) AS MaxError_id
               FROM Distribution.dbo.MSdistribution_history mdh
               WHERE start_time > DATEADD(hh, - 1, GETDATE())
               GROUP BY agent_id
               ) AS MaxErrorID ON MaxErrorID.agent_id = mda.id
                   AND MaxErrorID.MaxError_id = mdh.error_id
           WHERE start_time > DATEADD(hh, - 1, GETDATE())
               AND error_id <> 0
           FOR XML PATH('tr')
       ) AS NVARCHAR(MAX)) + N'</table><br />'

   -- Add another table that shows all the recent errors that can contain errors from orphaned agent jobs.
   SET @OrphanedErrors = N'<table border="0" cellpadding="0" cellspacing="2">' 
       + N'<th><H3>Last Hours Logged Replication Errors</H3></th></tr>' 
       + CAST((
               SELECT DISTINCT CAST(error_text AS VARCHAR(200)) AS td
               FROM Distribution.dbo.msrepl_errors
               WHERE [Time] > DATEADD(hh, - 1, GETDATE())
                   AND source_type_id <> 1 --Not very helpful typically. Does show path.
               FOR XML PATH('tr')
           ) AS NVARCHAR(MAX)) + N'</table><br />'

   -- Add another table that shows all the jobs that are in a bad job state.
   SET @BadJobStatus = N'<table border="0" cellpadding="0" cellspacing="2">' 
       + N'<th>Agent Name</th><th>History Comment</th><th>Job Status</th><th>Time Recorded</th></tr>' 
       + CAST((
               SELECT td = a.Name,''
                   ,td = Comments,''
                   ,td = CASE 
                       WHEN runstatus = 1 THEN 'Start'
                       WHEN runstatus = 2 THEN 'Succeed/Stopped'
                       WHEN runstatus = 3 THEN 'InProgress'
                       WHEN runstatus = 4 THEN 'Idle'
                       WHEN runstatus = 5 THEN 'Retry'
                       WHEN runstatus = 6 THEN 'Failure'
                       END,''
                   ,td = [Time]
               FROM Distribution.dbo.MSdistribution_agents a
               JOIN Distribution.dbo.MSdistribution_history h ON h.agent_id = a.id
               JOIN (
                   SELECT MAX([Time]) MaxTimeValue
                       ,Name
                   FROM Distribution.dbo.MSdistribution_agents a
                   JOIN Distribution.dbo.MSdistribution_history h ON h.agent_id = a.id
                   GROUP BY Name
                   ) x ON x.MaxTimeValue = h.[Time]
                   AND x.Name = a.Name
               WHERE runstatus NOT IN (0,1,3,4) --Assuming continuous replication is desired, else add 2 here.
               FOR XML PATH('tr')
           ) AS NVARCHAR(MAX)) + N'</table><br />'

	IF @IgnorePushedPublications = 0
   --Find push publications (For small environments (e.g. < ~10 subscribers), push is fine, just comment out).
   SET @PushedPublications = N'<table border="0" cellpadding="0" cellspacing="2">' 
       + N'<th>Agent Name</th><th>Subscription Type (Should only be Pull)</th><th>Date Created</th></tr>' 
       + CAST((
               SELECT td = mda.NAME,''
                   ,td = CASE 
                       WHEN mda.subscription_type = 0 THEN 'Push'
                       WHEN mda.subscription_type = 2 THEN 'Anonymous'
                       END,''
                   ,td = creation_date
               FROM Distribution.dbo.MSdistribution_agents mda
               WHERE mda.subscription_type <> 1 --0 = Push. 1 = Pull. 2 = Anonymous.
                   AND mda.subscriber_id > 0 --0 is for Virtual subscribers used in Immediate_Sync = on and/or Anonymous subs
               FOR XML PATH('tr')
           ) AS NVARCHAR(MAX)) + N'</table></HTML>'
   
   SET @TableHTML = ISNULL(@ErrorText, '') + ISNULL(@BadJobStatus, '') + ISNULL(@OrphanedErrors, '') + ISNULL(@PushedPublications, '')


If @tableHTML is not null and @tableHTML <> ''
	exec dbo.prc_internalsendmail 
	@HighPriority=1, 
	@address=@NotificationEmailAddress, 
	@subject=@subjectMsg, 
	@body=@tableHTML, 
	@HTML=1

END --Proc creation.
GO