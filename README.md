# SQL Server Replication Code Repository
SQL Server Replication information, scripts, and procedures for custom alerting.

##Chuck Lathrope an Author in Tribal SQL
Redgate and MidnightDBA organized a bunch of new authors to create a book on SQL Server topics, called "<a href="http://www.amazon.com/Tribal-SQL-Tony-Davis/dp/1906434808/" target="_blank">Tribal SQL</a>". I wrote the "Taming Replication" chapter on transactional replication, which covers all aspects of setup, performance, and troubleshooting. The book really covers what each of us authors thought was important tribal knowledge that we are passionate about. The books website is <a href="http://www.tribalsql.com" target="_blank">www.tribalsql.com</a> and all proceeds go to Computers 4 Africa charity.

I hope you enjoy the book, I know I spent a lot of time writing and re-writing the Taming Replication chapter with lots of help from Tony Davis the lead editor.

Cheers,
Chuck Lathrope

10/21/2013 - Review of Fundamentals of SQL Server 2012 Replication

I volunteered to review the book, "<a href="http://rd.gt/1befofV" target="_blank">Fundamentals of SQL Server 2012 Replication</a>" written by Sebastian Meine, Ph.D. and published in August 2013 by SimpleTalk publishing.

Sebastian does a great job at giving an overview of transactional and merge replication concepts, geared towards new users of replication. Each chapter reviews concepts and definitions to help solidify for the new user the knowledge you need to create your own replication environment. One of the aspects of the book that jumped out at me that differentiates it from other references on replication is the coverage of security in replication and using the least privilege access paradigm. Security in replication with least privilege access isn't that easy, but he covers it extensively in Chapter 6 - The Publication Access List and uses it as the basis for the chapter on troubleshooting replication.

He walks through examples of setting up both transactional and merge replication with lots of screen shots and explanations of what each option the replication setup wizard's ask of you. All the replication agents are covered and their purpose is explained well including how security works for each. There is even good coverage on Push vs. Pull distribution agents and why you should choose one or the other. Replication Monitor use is covered along with how to setup alerts with it and caveat's on how easy it is to miss issues with Replication Monitor. By the end of the book, you will have an excellent foundation on implementing transactional or merge replication. Some of the advanced settings and configurations are not covered in the book like custom agent profiles, scripting, advanced troubleshooting by diving into distribution database, and how you can easily get into trouble with wizards creating immediate sync publications. I cover these advanced topics in my chapter "Taming Replication" in Tribal SQL <span>(<a href="http://rd.gt/1befi7Y" target="_blank">http://rd.gt/1befi7Y</a>) </span>also published by SimpleTalk publishing in October 2013.

Overall, I highly recommend this book for people wanting to implement replication for the first time and want more detail than books online and a chapter of a book like Tribal SQL. Once you get going with replication, you will want to turn to my chapter on &ldquo;Taming Replication&rdquo; for transactional replication, but you will need to turn to other resources for merge replication.

Cheers,
Chuck Lathrope
	
