
IF NOT EXISTS(SELECT 1 FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_NAME = 'prc_Repl_PerfCounters' And ROUTINE_SCHEMA = 'dbo')
BEGIN
	EXEC('CREATE PROCedure dbo.prc_Repl_PerfCounters  as raiserror(''Empty Stored Procedure!!'', 16, 1) with seterror')
	IF (@@error = 0)
		PRINT 'Successfully created empty stored procedure dbo.prc_Repl_PerfCounters.'
	ELSE
	BEGIN
		PRINT 'FAILED to create stored procedure dbo.prc_Repl_PerfCounters.'
	END
END
GO

IF NOT EXISTS (Select name From sys.databases
	Where is_distributor = 1
	And name = 'Distribution')
Print 'Distibution database name is not Distribution, please alter the proc code manually to its actual name.'
GO

ALTER PROCEDURE dbo.prc_Repl_PerfCounters
as
begin

    set nocount on
	create table #qs_sysperfinfo	
	(counter_name nchar(128)											
	,instance_name nchar(128)
	, cntr_value bigint)
	
	create table #qs_perf_stats
	(job_id binary(16)
	,subscription_type int
	,subscriber_id int
	,delivery_latency bigint
	,delivered_commands bigint
	,delivered_transactions bigint
	,uploaded_changes bigint
	,downloaded_changes bigint
	,conflicts bigint)
	
    declare @db_name sysname
		,@cmd nvarchar(4000)
	
	insert into #qs_sysperfinfo
	select	counter_name
			,instance_name
			,cntr_value 
	from master.dbo.sysperfinfo 
	where object_name like '%Replication%'

	declare hCdatabase CURSOR LOCAL FAST_FORWARD FOR
		select name from master.dbo.sysdatabases 
			where
			category & 16 <> 0 and
			has_dbaccess(name) = 1
	for read only
	open hCdatabase
	fetch next from hCdatabase into @db_name
	while (@@fetch_status <> -1)
	begin
		declare @has_pm bit
		select @cmd = quotename(@db_name) + '.dbo.sp_executesql'
		exec @cmd
			N'if is_member(N''db_owner'') = 1 or is_member(N''replmonitor'') = 1 set @has_pm = 1', 
			N'@has_pm bit output',
			@has_pm output
		if @has_pm = 1
		begin	
			set @cmd = 
			'use ' + quotename(@db_name) +	
			'select	job_id  '+
			'		,case local_job when 1 then 0 else 1 end  subscription_type   '+
			'		,subscriber_id  '+
			'		,(select cntr_value from #qs_sysperfinfo where counter_name = ''Dist:Delivery Latency'' and instance_name = a.name) delivery_latency  '+
			'		,(select cntr_value from #qs_sysperfinfo where counter_name = ''Dist:Delivered Cmds/sec'' and instance_name = a.name) delivered_commands '+ 
			'		,(select cntr_value from #qs_sysperfinfo where counter_name = ''Dist:Delivered Trans/sec'' and instance_name = a.name) delivered_transactions	 '+
			'		,0 uploaded_changes  '+
			'		,0 downloaded_changes  '+
			'		,0 conflicts  '+
			'from MSdistribution_agents a  '+
			'UNION ALL  '+
			'select	job_id  '+
			'		,0 subscription_type  '+
			'		,NULL subscriber_id  '+
			'		,(select cntr_value from #qs_sysperfinfo where counter_name = ''Logreader:Delivery Latency'' and instance_name = a.name) delivery_latency '+
			'		,(select cntr_value from #qs_sysperfinfo where counter_name = ''Logreader:Delivered Cmds/sec'' and instance_name = a.name) delivered_commands '+
			'		,(select cntr_value from #qs_sysperfinfo where counter_name = ''Logreader:Delivered Trans/sec'' and instance_name = a.name) delivered_transactions  '+	
			'		,0 uploaded_changes  '+
			'		,0 downloaded_changes  '+
			'		,0 conflicts  '+
			'from MSlogreader_agents a  '+
			'UNION ALL  '+
			'select	job_id  '+
			'		,0 subscription_type  '+
			'		,NULL subscriber_id  '+
			'		, 0 delivery_latency  '+
			'		,(select cntr_value from #qs_sysperfinfo where counter_name = ''Snapshot:Delivered Cmds/sec'' and instance_name = a.name) delivered_commands  '+
			'		,(select cntr_value from #qs_sysperfinfo where counter_name = ''Snapshot:Delivered Trans/sec'' and instance_name = a.name) delivered_transactions	 '+
			'		,0 uploaded_changes  '+
			'		,0 downloaded_changes  '+
			'		,0 conflicts  '+
			'from MSsnapshot_agents a  '+
			'UNION ALL   
			select ma.job_id ' +
			'       , case ma.local_job when 1 then 0 else 1 end  subscription_type ' +
			'       , ma.subscriber_id ' +
            '       , 0 delivery_latency ' +
            '       , 0 delivered_commands ' +
            '       , 0 delivered_trasanctions ' +
            '       , ms.upload_inserts + ms.upload_updates + ms.upload_deletes uploaded_changes ' +
            '       , ms.download_inserts + ms.download_updates + ms.download_deletes downloaded_changes ' +
            '       , ms.upload_conflicts + ms.download_conflicts conflicts ' +
            'from MSmerge_agents ma, ' +
            '     MSmerge_history mh, ' +
            '     MSmerge_sessions ms ' +
            'where ma.id = mh.agent_id and mh.session_id = ms.session_id ' +
            '     and mh.timestamp = (select max(timestamp) from MSmerge_history mh2 ' +
            '                         where mh2.agent_id = ma.id)'
			insert into #qs_perf_stats 
			exec (@cmd)	
		end
		fetch next from hCdatabase into @db_name
	end
	
	close hCdatabase
	deallocate hCdatabase
	
	select	 coalesce(mda.name,msa.name,ma.name)
			,isnull(delivery_latency, 0) delivery_latency
			,isnull(delivered_commands, 0) delivered_commands
			,isnull(delivered_transactions, 0) delivered_transactions
			,isnull(uploaded_changes, 0) uploaded_changes
			,isnull(downloaded_changes, 0) downloaded_changes
			,isnull(conflicts, 0) conflicts
			,isnull(downloaded_changes + uploaded_changes, 0) all_changes
	from #qs_perf_stats s
	left join Distribution.dbo.MSdistribution_agents mda on mda.job_id = s.job_id
	left join Distribution.dbo.MSsnapshot_agents msa on msa.job_id = s.job_id
	left join Distribution.dbo.MSmerge_agents ma on ma.job_id = s.job_id
	where coalesce(mda.name,msa.name,ma.name) is not null
	and delivered_commands + downloaded_changes + uploaded_changes > 0
end
GO



