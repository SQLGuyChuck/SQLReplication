IF NOT EXISTS (SELECT * FROM sys.objects WHERE Name = 'prc_Repl_GetTransSchemaOptions')
	EXEC ('CREATE PROCEDURE dbo.prc_Repl_GetTransSchemaOptions AS SELECT 1')
GO

/****************************************************************************** 
**  Name: prc_Repl_GetTransSchemaOptions  
**  Procedure to list the options selected when publishing an article in a transactional publication on SQL Server 2005. 
**  Needs to be run in the Published database.
**  Based on scripts by Bert Corderman (also on www.replicationanswers.com)
**  Modified 15th March 2007 to cater for articles existing in multiple publications
**    
**
--if object_id('repltable') > 0
--	drop table repltable
--create table repltable(ID bigint, Description nvarchar(2000),table_name sysname,publication_name sysname) 
--
--DECLARE @table_name sysname,@publisher_name sysname
--DECLARE db_cursor CURSOR FOR 
--select sa.dest_table,sp.name from sysarticles sa
--  join syspublications sp
--    on sp.pubid = sa.pubid
--OPEN db_cursor 
--FETCH NEXT FROM db_cursor INTO @table_name,@publisher_name
--
--WHILE @@FETCH_STATUS = 0 
--BEGIN 
--insert into repltable
--exec prc_Repl_GetTransSchemaOptions @table_name,@publisher_name
--FETCH NEXT FROM db_cursor INTO @table_name,@publisher_name
--END 
--CLOSE db_cursor 
--DEALLOCATE db_cursor
--
--select * from repltable
**  
*******************************************************************************  
**  Change History  
*******************************************************************************  
**  Date:		Author:			Description:  
**  06/17/2009  Ganesh			Created  
*******************************************************************************/
ALTER PROCEDURE dbo.prc_Repl_GetTransSchemaOptions
@tablename varchar(200),
@PublicationName varchar(200)
as 
declare @pubid int, @schema_option varbinary(2000)
declare @t1 TABLE (ID bigint, Description nvarchar(2000),table_name sysname,publication_name sysname)

select @pubid = pubid from syspublications where [name] = @PublicationName
select @schema_option = schema_option from sysarticles where object_name(objid) = @tablename and pubid = @pubid

if (select @schema_option & 0) > 0 insert into @t1(id, description,table_name,publication_name) values (0, 'Disables scripting by the Snapshot Agent and uses creation_script.',@tablename,@PublicationName)
if (select @schema_option & 1) > 0 insert into @t1(id, description,table_name,publication_name) values (1, 'Generates the object creation script (CREATE TABLE, CREATE PROCEDURE, and so on). This value is the default for stored procedure articles.',@tablename,@PublicationName)
if (select @schema_option & 2) > 0 insert into @t1(id, description,table_name,publication_name) values (2, 'Generates the stored procedures that propagate changes for the article, if defined.',@tablename,@PublicationName)
if (select @schema_option & 4) > 0 insert into @t1(id, description,table_name,publication_name) values (4, 'Identity columns are scripted using the IDENTITY property.',@tablename,@PublicationName)
if (select @schema_option & 8) > 0 insert into @t1(id, description,table_name,publication_name) values (8, 'Replicate timestamp columns. If not set, timestamp columns are replicated as binary.',@tablename,@PublicationName)
if (select @schema_option & 16) > 0 insert into @t1(id, description,table_name,publication_name) values (16, 'Generates a corresponding clustered index. Even if this option is not set, indexes related to primary keys and unique constraints are generated if they are already defined on a published table.',@tablename,@PublicationName)
if (select @schema_option & 32) > 0 insert into @t1(id, description,table_name,publication_name) values (32, 'Converts user-defined data types (UDT) to base data types at the Subscriber. This option cannot be used when there is a CHECK or DEFAULT constraint on a UDT column, if a UDT column is part of the primary key, or if a computed column references a UDT column. Not supported for Oracle Publishers.',@tablename,@PublicationName)
if (select @schema_option & 64) > 0 insert into @t1(id, description,table_name,publication_name) values (64, 'Generates corresponding nonclustered indexes. Even if this option is not set, indexes related to primary keys and unique constraints are generated if they are already defined on a published table.',@tablename,@PublicationName)
if (select @schema_option & 128) > 0 insert into @t1(id, description,table_name,publication_name) values (128, 'Replicates primary key constraints. Any indexes related to the constraint are also replicated, even if options 0x10 and 0x40 are not enabled.',@tablename,@PublicationName)
if (select @schema_option & 256) > 0 insert into @t1(id, description,table_name,publication_name) values (256, 'Replicates user triggers on a table article, if defined. Not supported for Oracle Publishers.',@tablename,@PublicationName)
if (select @schema_option & 512) > 0 insert into @t1(id, description,table_name,publication_name) values (512, 'Replicates foreign key constraints. If the referenced table is not part of a publication, all foreign key constraints on a published table are not replicated. Not supported for Oracle Publishers.',@tablename,@PublicationName)
if (select @schema_option & 1024) > 0 insert into @t1(id, description,table_name,publication_name) values (1024, 'Replicates check constraints. Not supported for Oracle Publishers.',@tablename,@PublicationName)
if (select @schema_option & 2048) > 0 insert into @t1(id, description,table_name,publication_name) values (2048, 'Replicates defaults. Not supported for Oracle Publishers.',@tablename,@PublicationName)
if (select @schema_option & 4096) > 0 insert into @t1(id, description,table_name,publication_name) values (4096, 'Replicates column-level collation. ',@tablename,@PublicationName)
if (select @schema_option & 8192) > 0 insert into @t1(id, description,table_name,publication_name) values (8192, 'Replicates extended properties associated with the published article source object. Not supported for Oracle Publishers.',@tablename,@PublicationName)
if (select @schema_option & 16384) > 0 insert into @t1(id, description,table_name,publication_name) values (16384, 'Replicates UNIQUE constraints. Any indexes related to the constraint are also replicated, even if options 0x10 and 0x40 are not enabled.',@tablename,@PublicationName)
if (select @schema_option & 32768) > 0 insert into @t1(id, description,table_name,publication_name) values (32768, 'This option is not valid for SQL Server 2005 Publishers.',@tablename,@PublicationName)
if (select @schema_option & 65536) > 0 insert into @t1(id, description,table_name,publication_name) values (65536, 'Replicates CHECK constraints as NOT FOR REPLICATION so that the constraints are not enforced during synchronization.',@tablename,@PublicationName)
if (select @schema_option & 131072) > 0 insert into @t1(id, description,table_name,publication_name) values (131072, 'Replicates FOREIGN KEY constraints as NOT FOR REPLICATION so that the constraints are not enforced during synchronization.',@tablename,@PublicationName)
if (select @schema_option & 262144) > 0 insert into @t1(id, description,table_name,publication_name) values (262144, 'Replicates filegroups associated with a partitioned table or index.',@tablename,@PublicationName)
if (select @schema_option & 524288) > 0 insert into @t1(id, description,table_name,publication_name) values (524288, 'Replicates the partition scheme for a partitioned table. ',@tablename,@PublicationName)
if (select @schema_option & 1048576) > 0 insert into @t1(id, description,table_name,publication_name) values (1048576, 'Replicates the partition scheme for a partitioned index.',@tablename,@PublicationName)
if (select @schema_option & 2097152) > 0 insert into @t1(id, description,table_name,publication_name) values (2097152, 'Replicates table statistics.',@tablename,@PublicationName)
if (select @schema_option & 4194304) > 0 insert into @t1(id, description,table_name,publication_name) values (4194304, 'Default Bindings',@tablename,@PublicationName)
if (select @schema_option & 8388608) > 0 insert into @t1(id, description,table_name,publication_name) values (8388608, 'Rule Bindings',@tablename,@PublicationName)
if (select @schema_option & 16777216) > 0 insert into @t1(id, description,table_name,publication_name) values (16777216, 'Full-text index',@tablename,@PublicationName)
if (select @schema_option & 33554432) > 0 insert into @t1(id, description,table_name,publication_name) values (33554432, 'XML schema collections bound to xml columns are not replicated.',@tablename,@PublicationName)
if (select @schema_option & 67108864) > 0 insert into @t1(id, description,table_name,publication_name) values (67108864, 'Replicates indexes on xml columns.',@tablename,@PublicationName)
if (select @schema_option & 134217728) > 0 insert into @t1(id, description,table_name,publication_name) values (134217728, 'Create any schemas not already present on the subscriber.',@tablename,@PublicationName)
if (select @schema_option & 268435456) > 0 insert into @t1(id, description,table_name,publication_name) values (268435456, 'Converts xml columns to ntext on the Subscriber.',@tablename,@PublicationName)
if (select @schema_option & 536870912) > 0 insert into @t1(id, description,table_name,publication_name) values (536870912, 'Converts large object data types introduced in SQL Server 2005 to data types supported on earlier versions of Microsoft SQL Server',@tablename,@PublicationName)
if (select @schema_option & 1073741824) > 0 insert into @t1(id, description,table_name,publication_name) values (1073741824, 'Replicate permissions.',@tablename,@PublicationName)
if (select @schema_option & cast(2147483648 as bigint)) > 0 insert into @t1(id, description,table_name,publication_name) values (2147483648, 'Attempt to drop dependencies to any objects that are not part of the publication.',@tablename,@PublicationName)

select * from @t1
go
