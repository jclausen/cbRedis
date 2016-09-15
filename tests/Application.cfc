/**
* Copyright Since 2005 Ortus Solutions, Corp
* www.coldbox.org | www.luismajano.com | www.ortussolutions.com | www.gocontentbox.org
**************************************************************************************
*/
component{
	this.name = "A TestBox Runner Suite " & hash( getCurrentTemplatePath() );
	// any other application.cfc stuff goes below:
	this.sessionManagement = true;
	this.clientManagement  = true;

	// any mappings go here, we create one that points to the root called test.
	this.mappings[ "/tests" ] = getDirectoryFromPath( getCurrentTemplatePath() );
	rootPath = REReplaceNoCase( this.mappings[ "/tests" ], "tests(\\|/)", "" );
	this.mappings[ "/root" ]   		= rootPath;
	this.mappings[ "/cbjavaloader" ]  = rootPath & "/modules/cbjavaloader";
	this.mappings[ "/RedisProvider" ]  = rootPath & "/modules/cbredis";

	// request start
	public boolean function onRequestStart( String targetPage ){	
		return true;
	}
}