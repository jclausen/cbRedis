/** ColdBox event/view cache support using the framework's key cleaner. */
component extends="RedisProvider" implements="coldbox.system.cache.providers.IColdBoxProvider" {

	function init() {
		super.init();
		variables.eventURLFacade = new coldbox.system.cache.util.EventURLFacade( this );
		return this;
	}

	function getViewCacheKeyPrefix() {
		return "cbredis_view-";
	}

	function getEventCacheKeyPrefix() {
		return "cbredis_event-";
	}

	function setColdBox( required coldbox ) {
		variables.coldbox = coldbox;
		return this;
	}

	function getColdBox() {
		return variables.coldbox;
	}

	function getEventURLFacade() {
		return variables.eventURLFacade;
	}

	function clearAllEvents( boolean async = false ) {
		variables.elementCleaner.clearAllEvents();
		return this;
	}

	function clearAllViews( boolean async = false ) {
		variables.elementCleaner.clearAllViews();
		return this;
	}

	function clearEvent( required eventSnippet, queryString = "" ) {
		variables
			.elementCleaner
			.clearEvent( argumentCollection = arguments );
		return this;
	}

	function clearEventMulti( required eventsnippets, queryString = "" ) {
		variables
			.elementCleaner
			.clearEventMulti( argumentCollection = arguments );
		return this;
	}

	function clearView( required viewSnippet ) {
		variables.elementCleaner.clearView( viewSnippet );
		return this;
	}

	function clearViewMulti( required viewSnippets ) {
		variables.elementCleaner.clearViewMulti( viewSnippets );
		return this;
	}

}