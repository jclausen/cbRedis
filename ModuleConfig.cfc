/** Redis/Valkey support. Pools belong to individual connection objects. */
component {
	this.title = "cbRedis";
	this.author = "Jon Clausen";
	this.version = "2.0.0-alpha.1";
	this.modelNamespace = "cbRedis";
	this.cfmapping = "cbRedis";
	this.autoMapModels = true;

	function configure() {
		settings = { connection : {} };
	}

	function onLoad() {
		variables
			.binder
			.map(
				[ "RedisConnection@cbRedis", "RedisConnection" ],
				true
			)
			.to( "#moduleMapping#.models.RedisConnection" )
			.initArg(
				name = "configuration",
				dsl  = "coldbox:moduleSettings:cbRedis:connection"
			)
			.asSingleton();
	}

	function onUnload() {
		// Do not create a connection merely to shut it down.
		var scope = variables.wirebox.getScope( "singleton" );
		var instances = scope.getSingletons();
		if ( instances.containsKey( "redisconnection@cbredis" ) ) {
			instances.get( "redisconnection@cbredis" ).close();
		}
	}

}