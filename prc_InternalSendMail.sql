
IF NOT EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'prc_InternalSendMail' And ROUTINE_SCHEMA = 'dbo')
BEGIN
	EXEC('CREATE Procedure dbo.prc_InternalSendMail  as raiserror(''Empty Stored Procedure!!'', 10, 1) with seterror')
	IF (@@error = 0)
		PRINT 'Successfully created empty stored procedure dbo.prc_InternalSendMail.'
	ELSE
	BEGIN
		PRINT 'FAILED to create stored procedure dbo.prc_InternalSendMail.'
	END
END
GO

--If current database is not trustworthy, make it so.
IF NOT EXISTS (select * from sys.databases Where database_id = db_id() and is_trustworthy_on = 1)
Begin
	Declare @sql varchar(500)
	Select @sql = 'Alter database ' + cast (db_name(db_id()) as varchar(100)) + ' SET TRUSTWORTHY ON'
	Exec (@sql)
END
GO

ALTER PROCEDURE dbo.prc_InternalSendMail
 @Address VARCHAR(1000) = 'alerts@yourdomain.com',
 @Subject VARCHAR(255),
 @Body VARCHAR(MAX),
 @From VARCHAR(50) = 'Notifications@yourdomain.com',
 @FromName VARCHAR(100) = NULL,
 @ReplyTo VARCHAR(100) = 'alerts@yourdomain.com',
 @BCC VARCHAR(300) = NULL,
 @CC VARCHAR(300) = NULL,
 @Attachment VARCHAR(MAX) = NULL, --supply path and filename.
 @HTML bit = 0,
 @HighPriority BIT = 0,
 @SMTPServer VARCHAR(100) = NULL,
 @Success bit = NULL OUTPUT-- 0 is failure
AS
BEGIN
/*****************************************************************************************
** Name: prc_InternalSendMail
** Desc: Internal mail alert proc that automatically creates necessary mail profiles and accounts.
**		Email from address will be like ServerName <@From> if @FromName is NULL.
** Compatibility: SQL 2005+
** Database needs to be trustworthy if other database procedures call it and cross database ownership is enabled.
**
** Created: 6/1/2007 Chuck Lathrope
**
** Example Usage:
--
--declare @success int
--EXEC dbo.prc_internalsendmail
-- @Address = 'chuck.lathrope@yourdomain.com',
-- @Subject = 'Test prc_InternalSendMail',
-- @Body = 'This is a test',
-- @Html = 1,
-- @HighPriority = 1,
-- --@smtpserver ='opsview',
-- @Success = @Success OUTPUT
--print @success
--
**
** To change default mail size from 1MB to 10MB run this:
**  EXECUTE msdb.dbo.sysmail_configure_sp 'MaxFileSize', '10485760' ;
*******************************************************************************
**  Change History
*******************************************************************************
** Date:  Author:   Description:
** 11/17/2008 Chuck Lathrope	Added optional @SMTPServer to override hardcoded value.
** 05/18/2009 Chuck Lathrope	Added execute as owner.
** 07/08/2010 Chuck Lathrope	email address updates, error message improvements.
** 09/02/2012 Chuck Lathrope	Improved error handling.
** 08/13/2013 Chuck Lathrope	Change defaults for Efinancial.
** 08/26/2013 Chuck Lathrope	Added hardcoded IP for default SMTP on non-domain servers.
** 08/27/2013 Chuck Lathrope	Added sysadmin checks.
** 05/14/2015 Chuck Lathrope	Initialized @Error = 0 so proc doesn't error on success!
*******************************************************************************/
SET NOCOUNT ON
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

DECLARE @MailServerName NVARCHAR(200)
	,@Env VARCHAR(30)
	,@ErrMessage NVARCHAR(MAX)
	,@Response varchar(255)
	,@Name varchar(130)
	,@body_format varchar(10)
	,@ProfileName sysname
	,@AccountID int
	,@ProfileID int
	,@MailItem_Id int
	,@Importance varchar(6)
	,@Error INT = 0
	,@SQLString nvarchar(500)
	,@ParmDefinition nvarchar(500)
	,@DefaultSMTPServer varchar(255)

IF @HighPriority = 1
	SET @Importance ='High'
Else
	SET @Importance ='Normal'
	
IF @HTML = 1
	SET @body_format='HTML'
Else
	SET @body_format='TEXT'


IF LTRIM(RTRIM(@FromName))='' OR @FromName IS NULL
	SET @FromName=@@ServerName

SET @ProfileName = @From + '/' + @FromName

--Try to lookup the environment
Begin Try
	SET @SQLString = N'Select @env = dbo.udf_GetProcessParameter (''Admin'',''Environment'')'
	SET @ParmDefinition = N'@env varchar(100) OUTPUT'

	Exec sp_executesql
		@SQLString,
		@ParmDefinition,
		@env = @env OUTPUT
End Try
Begin Catch
	Print 'Problem running udf_GetProcessParameter, so guessing environment.'
End Catch

--If udf_GetProcessParameter failed, let's guess by server name what env server is in.
IF @Env is NULL
BEGIN
	SET @Env = CASE WHEN @@SERVERNAME like '%QA%' Then 'QA'
											WHEN @@SERVERNAME like '%dev%' or @@SERVERNAME like 'HQ%'
												or @@ServerName like '%vm%' Then 'Dev'
											Else 'Production'
									 END
END

IF @env = 'Dev'
	SET @DefaultSMTPServer = 'devbuildserver' --I hard code in my environment, feel free to change
ELSE
	SET @DefaultSMTPServer = 'opsview' --I hard code in my environment, feel free to change

--Override the hardcoded value for mail relay server to use if provided.
SET @MailServerName = COALESCE(@SMTPServer, @DefaultSMTPServer)


--If server is not in prod, prefix subject line with environment name.
IF @Env NOT IN ('Production')
BEGIN
	SET @Subject = ISNULL(@Subject,'')+' ('+ISNULL(@Env,'null')+' environment)'
END

IF @ReplyTo IS NULL
	SET @ReplyTo = @From

/**************************************************
Make sure the account exists and it's part of this profile
**************************************************/
SELECT @AccountID=Account_ID FROM msdb.dbo.sysmail_account WHERE [name]=@profilename
SELECT @ProfileID=Profile_ID FROM msdb.dbo.sysmail_profile WHERE [name]=@profilename

--create the profile if needed
IF @ProfileID IS NULL
Begin
	EXEC msdb.dbo.sysmail_add_profile_sp
	@profile_name = @ProfileName,
	@description = @ProfileName,
	@profile_id =@ProfileID output

	--give everybody access to use this profile
	EXEC msdb.dbo.sysmail_add_principalprofile_sp
	@profile_id = @ProfileID,
	@principal_name = 'public',
	@is_default = 0 ;
End

--create the account (same name as profile) if needed
If @AccountID is null
	EXEC msdb.dbo.sysmail_add_account_sp
	@account_name = @ProfileName,
	@description = @From,
	@email_address = @From,
	@replyto_address = @ReplyTo,
	@display_name = @FromName,
	@mailserver_name = @MailServerName,
	@Account_ID = @AccountID OUTPUT;

--create the relationship of account to profile
IF NOT EXISTS (Select * from msdb.dbo.sysmail_profileaccount where Profile_Id=@ProfileID and Account_Id=@AccountID)
	EXEC msdb.dbo.sysmail_add_profileaccount_sp
	@Profile_id = @ProfileID ,
	@Account_Id = @AccountID,
	@Sequence_number=1; --first in line

/**********************************************************
Now, send the mail using the specific account
**********************************************************/
Begin Try

	EXEC msdb.dbo.sp_send_dbmail
		@Profile_name = @ProfileName,
		@Recipients = @Address,
		@Subject = @Subject,
		@Body = @Body,
		@Importance=@Importance,
		@copy_recipients=@CC,
		@blind_copy_recipients=@BCC,
		@body_format=@body_format,
		@file_attachments=@Attachment,
		@mailitem_id = @mailitem_id OUTPUT

End Try
Begin Catch

	Select @Error = ERROR_NUMBER(), @ErrMessage = ERROR_MESSAGE()

	--DB Mail is not enabled. Try enabling and running again.
	If ERROR_NUMBER()= 15281 and IS_SRVROLEMEMBER ('sysadmin') = 1
	Begin
		--Reset @Error, attempt fix and try again.
		Select @Error = 0
		exec ('sp_configure ''show advanced options'', 1')
		Reconfigure;
		exec ('sp_configure ''Database Mail XPs'', 1')
		exec ('sp_configure ''show advanced options'', 0')
		Reconfigure;
				
		Begin Try
		EXEC msdb.dbo.sp_send_dbmail
			@Profile_name = @ProfileName,
			@Recipients = @Address,
			@Subject = @Subject,
			@Body = @Body,
			@Importance=@Importance,
			@copy_recipients=@CC,
			@blind_copy_recipients=@BCC,
			@body_format=@body_format,
			@file_attachments=@Attachment,
			@mailitem_id = @mailitem_id OUTPUT
		End Try
		Begin Catch
			Select @Error = ERROR_NUMBER(), @ErrMessage = ERROR_MESSAGE()
		End Catch
	End

	--external mail queue is most likely disabled.
	If ERROR_NUMBER()= 14641 and IS_SRVROLEMEMBER ('sysadmin') = 1
	Begin
		--Reset @Error, attempt fix and try again.
		Select @Error = 0
		exec msdb.dbo.sysmail_start_sp
		
		Begin Try
		EXEC msdb.dbo.sp_send_dbmail
			@Profile_name = @ProfileName,
			@Recipients = @Address,
			@Subject = @Subject,
			@Body = @Body,
			@Importance=@Importance,
			@copy_recipients=@CC,
			@blind_copy_recipients=@BCC,
			@body_format=@body_format,
			@file_attachments=@Attachment,
			@mailitem_id = @mailitem_id OUTPUT
		End Try
		Begin Catch
				Select @Error = ERROR_NUMBER(), @ErrMessage = ERROR_MESSAGE()
		End Catch
	End

End Catch

ErrorCheck:
IF @ERROR = 0 AND @Mailitem_id > 0
	Set @Success = 1
ELSE
Begin
	SET @Success = 0
	If @mailitem_id > 0
		Print '@error = ' + cast(ISNULL(@error,'') as varchar(7))
			+ '; Error Message: ' + @ErrMessage
			+ '; @mailitem_id = ' + cast(ISNULL(@mailitem_id,'') as varchar(9))
	Else
		Print 'Error Message: ' + ISNULL(@ErrMessage,'No Error Message captured')
		+ '. IT Ops: If new server setup, run prc_Config_DBMail.'
End

Select @mailitem_id as MailItemID

IF @Success = 1
	RETURN 0
ELSE
	RETURN -1

END
GO
