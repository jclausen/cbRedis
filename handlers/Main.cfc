/**
* My Event Handler Hint
*/
component accessors=true{
	property name="cachebox" inject="cachebox";

	// Index
	any function index( event, rc, prc ){

		var cache = getCachebox().getCache("template");
		var cache.set( "foo", "bar" );
		
		event.setView( "main/index" );
	}

	// Run on first init
	any function onAppInit( event, rc, prc ){

	}

}