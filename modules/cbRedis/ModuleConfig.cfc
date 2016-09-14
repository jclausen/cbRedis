/**
*********************************************************************************
* Your Copyright
********************************************************************************
*/
component{

	// Module Properties
	this.title 				= "cbRedis";
	this.author 			= "Jon Clausen";
	this.webURL 			= "";
	this.description 		= "Cachebox Redis Provider Module for Coldbox";
	this.version			= "@build.version@+@build.number@";
	// If true, looks for views in the parent first, if not found, then in the module. Else vice-versa
	this.viewParentLookup 	= true;
	// If true, looks for layouts in the parent first, if not found, then in module. Else vice-versa
	this.layoutParentLookup = true;
	// Module Entry Point
	this.entryPoint			= "cbRedis";
	// Model Namespace
	this.modelNamespace		= "cbRedis";
	// CF Mapping
	this.cfmapping			= "cbRedis";
	// Auto-map models
	this.autoMapModels		= true;
	// Module Dependencies That Must Be Loaded First, use internal names or aliases
	this.dependencies		= [ 'cbjavaloader' ];

	/**
	* Configure module
	*/
	function configure(){
	}

	/**
	* Fired when the module is registered and activated.
	*/
	function onLoad(){
		var jLoader = Wirebox.getInstance("Loader@cbjavaloader");
		jLoader.appendPaths( modulePath & '/lib/' );
	}

	/**
	* Fired when the module is unregistered and unloaded
	*/
	function onUnload(){
		
	}

}
