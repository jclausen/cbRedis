component {

	function configure() {
		coldbox = {
			appName                 : "cbRedis isolated fixture",
			handlersIndexAutoReload : false
		};
		modules = {
			include : [],
			exclude : []
		};
		moduleSettings = {
			cbRedis : {
				connection : {
					host     : "localhost",
					port     : request.cbRedisFixture.port,
					username : "fixture",
					password : "cbredis-fixture-password",
					tls      : false
				}
			}
		};
		logBox = {
			root      : {
				levelMax  : "OFF",
				appenders : "*"
			},
			appenders : {}
		};
	}

}