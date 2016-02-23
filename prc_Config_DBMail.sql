IF NOT EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'prc_Config_DBMail' And ROUTINE_SCHEMA = 'dbo')
BEGIN
	EXEC('CREATE Procedure dbo.prc_Config_DBMail as raiserror(''Empty Stored Procedure!!'', 10, 1) with seterror')
	IF (@@error = 0)
		PRINT 'Successfully created empty stored procedure dbo.prc_Config_DBMail.'
	ELSE
	BEGIN
		PRINT 'FAILED to create stored procedure dbo.prc_Config_DBMail.'
	END
END
GO

ALTER PROCEDURE dbo.prc_Config_DBMail @FromAddress varchar(100) = NULL
	,@ReplyToAddress varchar(100) = NULL
	,@OverrideExistingSetup bit = 0
	,@MakePublic bit = 1
AS
BEGIN
/******************************************************************************
**    Name: prc_Config_DBMail
**
**    Desc: Sets DBMail configuration for SQL Agent Alerts and sp_send_dbmail use.
**		Conscious choice to set profile and account name the same.
**	  http://technet.microsoft.com/en-us/library/ms175100.aspx
**	  http://msdn.microsoft.com/en-us/library/ms187605.aspx
**
**	  NOTE: Read output to determine if there are any next steps.
**	  Example override: Exec dbops.dbo.prc_Config_DBMail @OverrideExistingSetup = 1
*******************************************************************************
**    Change History
*******************************************************************************
**  Date:       Author:         Description:
**  8/26/2013	Chuck Lathrope	Added default SMTP ip for non-domain servers.
**  8/27/2013	Chuck Lathrope	Major refactoring based on public setting not being needed.
**  6/28/2015	Chuck Lathrope	Switch use of sp_set_sqlagent_properties to work in SQL 2008.
******************************************************************************/
SET NOCOUNT ON
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

IF IS_SRVROLEMEMBER ('sysadmin') = 0
BEGIN
	RAISERROR ('ERROR: You must be a member of sysadmin role to run this proc.',16,1)
	RETURN 1
END

Declare @PrimaryFrom VARCHAR(100),
        @PrimaryFromName VARCHAR(100) ,
        @PrimaryReplyTo VARCHAR(100) ,
        @PrimarySMTPServer VARCHAR(100),
  --      @SecondaryFrom VARCHAR(100),
  --      @SecondaryFromName VARCHAR(100) ,
  --      @SecondaryReplyTo VARCHAR(100) ,
  --      @SecondarySMTPServer VARCHAR(100) ,
		@NewSetupProfileName nvarchar(200) ,
		@NewSetupAccountName nvarchar(200) ,
		@AccountID int ,
		@ProfileID int ,
		@AgentMailType int,
		@AgentMailProfile varchar(100)

--Check variables or populate them.
IF @FromAddress is null
BEGIN
	SELECT @FromAddress = ParameterValue --Select *
	FROM dbops.dbo.ProcessParameter 
	where ParameterName = 'IT Ops Team Escalation'
END

IF @ReplyToAddress is null
BEGIN
	SELECT @ReplyToAddress = ParameterValue--select *
	FROM dbops.dbo.ProcessParameter 
	where ParameterName = 'IT Ops Team Escalation'
END

--Bail if variables are still NULL
IF @FromAddress IS NULL OR @ReplyToAddress IS NULL
BEGIN
	RAISERROR ('ERROR: @FromAddress IS NULL OR @ReplyToAddress IS NULL. Populate dbops.dbo.ProcessParameters table or provide values to proc.',16,1)
	RETURN 1
END

--Populate variables
IF @@SERVERNAME LIKE 'HQ%'
	SET @PrimarySMTPServer = 'devbuildserver'
Else
	SET @PrimarySMTPServer = 'opsview'

SELECT  @PrimaryFromName=@@ServerName
            , @PrimaryFrom = @FromAddress
            , @PrimaryReplyTo = @ReplyToAddress

--If failure of email happens, SQL Agent will attempt with this configuration:
--No secondary SMTP server, so skipping
--SELECT  @SecondaryFromName=@@ServerName
--            , @SecondaryFrom  = 'alerts@yourdomainhere.com'
--            , @SecondaryReplyTo = @ReplyToAddress
--            , @SecondarySMTPServer  = 'opsview'

SELECT @NewSetupProfileName = @PrimaryFrom + '/' + @PrimaryFromName --Translates to: @FromAddress/@@ServerName
      , @NewSetupAccountName = @PrimaryFrom + '/' + @PrimaryFromName


--Is db mail enabled for use?
IF NOT EXISTS (SELECT value_in_use FROM sys.configurations Where name = 'Database Mail XPs' and value_in_use = 1)
BEGIN
	IF NOT EXISTS (SELECT value_in_use FROM sys.configurations Where name = 'show advanced options' and value_in_use = 1 )
	BEGIN
		EXEC ('sp_configure ''show advanced options'', 1')
		Reconfigure;
	END
	EXEC ('sp_configure ''Database Mail XPs'', 1')
	EXEC ('sp_configure ''show advanced options'', 0')
	Reconfigure;
END

--Is server ready to send mail from SQL Agent? If not, setup registry values to enable mail for SQL Agent.
EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent', N'UseDatabaseMail', @param = @AgentMailType OUT, @no_output = N'no_output'
IF @AgentMailType <> 1
BEGIN
	--Assume token replacement is off
	IF CAST(REPLACE(SUBSTRING(CAST(SERVERPROPERTY('PRODUCTVERSION') AS VARCHAR),1, 2), '.', '') AS TINYINT) >= 11
		EXEC msdb.dbo.sp_set_sqlagent_properties @use_databasemail=1, @alert_replace_runtime_tokens=1
	ELSE
	BEGIN
		EXECUTE master.dbo.xp_instance_regwrite N'HKEY_LOCAL_MACHINE',
        N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',
        N'UseDatabaseMail',
        N'REG_DWORD',
        1
		EXECUTE master.dbo.xp_instance_regwrite N'HKEY_LOCAL_MACHINE',
                                            N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',
                                            N'AlertReplaceRuntimeTokens',
                                            N'REG_DWORD',
                                            1 
	END
END

--Does the SQL Agent registry setting value for the mail profile to use exist?
--Declare @AgentMailProfile varchar(100)
EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE', N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent', N'DatabaseMailProfile', @param = @AgentMailProfile OUT, @no_output = N'no_output'
--Print @AgentMailProfile 

--Let's check accounts and profiles and create/change as requested.
IF @AgentMailProfile IS NULL OR @OverrideExistingSetup = 1
BEGIN
	--Does the profile exist?
	Select @ProfileID = profile_id 
	FROM msdb.dbo.sysmail_profile
	WHERE name = @NewSetupProfileName

	--Create profile if none exist already
	IF @ProfileID IS NULL
	BEGIN
		PRINT 'Creating profile: ' + @NewSetupProfileName
      
		EXEC msdb.dbo.sysmail_add_profile_sp
			@profile_name = @NewSetupProfileName,
			@description = 'IT Ops''s alert profile',
			@profile_id =@ProfileID output

		--Give everybody access to use this profile and make it the default
		IF @MakePublic = 1
		EXEC msdb.dbo.sysmail_add_principalprofile_sp
			@profile_id = @ProfileID,
			@principal_name = 'public',
			@is_default = 1
	END

	--Create the primary account (same name as profile)
	IF NOT EXISTS (select * from msdb.dbo.sysmail_account where name = @NewSetupAccountName)
	BEGIN
		  PRINT 'Creating Account: '+@NewSetupAccountName

		  EXEC msdb.dbo.sysmail_add_account_sp
		  @account_name = @NewSetupAccountName,
		  @description = 'IT Ops''s alert account',
		  @email_address = @PrimaryFrom,
		  @replyto_address = @PrimaryReplyTo,
		  @display_name = @PrimaryFromName,
		  @mailserver_name = @PrimarySMTPServer,
		  @Account_ID=@AccountID OUTPUT;

	END

	/* No secondary SMTP server, so skipping.
	--Create the secondary account for profile
	SET @NewSetupAccountName = @SecondaryFrom + '/' + @SecondaryFromName
      
	IF NOT EXISTS (select 1 from msdb.dbo.sysmail_account where name = @NewSetupAccountName)
	BEGIN
		  PRINT 'Creating Secondary Account ' + @NewSetupAccountName + ' for Profile: '+@NewSetupProfileName

		  EXEC msdb.dbo.sysmail_add_account_sp
		  @account_name = @NewSetupAccountName,
		  @description = @SecondaryFrom,
		  @email_address = @SecondaryFrom,
		  @replyto_address = @SecondaryReplyTo,
		  @display_name = @SecondaryFromName,
		  @mailserver_name = @SecondarySMTPServer,
		  @Account_ID=@AccountID OUTPUT;

		  --create the relationship of account to profile
		  EXEC msdb.dbo.sysmail_add_profileaccount_sp 
		  @Profile_name=@NewSetupProfileName ,
		  @Account_Id=@AccountID,
		  @Sequence_number=2 --second in line in case first fails.
	END
	*/

	IF @AccountID IS NULL --Existed already.
		SELECT @AccountID=account_id FROM msdb.dbo.sysmail_account WHERE name = @NewSetupAccountName

	--Create the Profile to Account relationship if it doesn't exist already.
	IF NOT EXISTS (Select *	FROM msdb.dbo.sysmail_profileaccount pa
					JOIN msdb.dbo.sysmail_account a on a.account_id=pa.account_id
					WHERE Sequence_number = 1 
					AND name = @NewSetupProfileName)
		EXEC msdb.dbo.sysmail_add_profileaccount_sp 
		@Profile_id = @ProfileID ,
		@Account_Id = @AccountID ,
		@Sequence_number=1

	--Set SQL Agent DBMail profile to our new profile.
	IF CAST(REPLACE(SUBSTRING(CAST(SERVERPROPERTY('PRODUCTVERSION') AS VARCHAR),1, 2), '.', '') AS TINYINT) >= 11
		EXEC msdb.dbo.sp_set_sqlagent_properties @databasemail_profile=@NewSetupProfileName
	ELSE
	BEGIN
		EXECUTE master.dbo.xp_instance_regwrite N'HKEY_LOCAL_MACHINE',
                                    N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent',
                                    N'DatabaseMailProfile',
                                    N'REG_SZ',
                                    @NewSetupProfileName
	END
	
	RAISERROR ('All setup! Modifying SQL Agent DBMail profile requires SQL Agent to be restarted, so do not forget.',10,1)
	RETURN 0
END
ELSE IF @AgentMailProfile <> @NewSetupProfileName AND @OverrideExistingSetup = 0
BEGIN --Override not set.
	--Is it setup with existing account and all should be okay?
	IF EXISTS (SELECT * FROM msdb.dbo.sysmail_profileaccount pa 
			Join msdb.dbo.sysmail_profile p on p.profile_id = pa.profile_id
			Join msdb.dbo.sysmail_account a on a.account_id=pa.account_id
			Where sequence_number = 1
			And p.name = @AgentMailProfile)
	BEGIN
		Print 'SQL Agent DBMail is properly setup with profile name (' + @AgentMailProfile + '), but it does not match server setup standard profile name' +
		' (' + @NewSetupProfileName + ') and @OverrideExistingSetup=0, so not overriding existing setup. Run again with override set if so desired.'
		RETURN 0
	END
	ELSE
	BEGIN
		RAISERROR ('DBMail profile (%s) does not match server setup standard (%s) and @OverrideExistingSetup=0, so not overriding existing setup. Run again with override set if so desired.',16,1,@AgentMailProfile,@NewSetupProfileName)
		RETURN 1
	END
END
ELSE
	RAISERROR ('All looks good. If you are still having issues, resetting SQL Agent DBMail profile requires SQL Agent to be restarted, so try that.',10,1)

END --Proc
go

