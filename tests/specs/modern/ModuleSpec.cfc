component extends="testbox.system.BaseSpec" {

	function run() {
		describe(
			"Real ColdBox module lifecycle",
			() => {
				it(
					"honors application connection settings and closes its existing singleton on unload",
					() => verifyModule()
				);
			}
		);
	}

	private function verifyModule() {
		var preserved = {};
		for ( var key in [
			"cbController",
			"wirebox",
			"cachebox"
		] ) {
			if ( structKeyExists( application, key ) ) {
				preserved[ key ] = application[ key ];
			}
		}
		var fixtureApp = new coldbox.system.testing.VirtualApp(
			appMapping = "/fixtureapp",
			configPath = "fixtureapp.config.Coldbox"
		);
		try {
			var controller = fixtureApp.startup( force = true );
			controller
				.getModuleService()
				.registerAndActivateModule( "cbRedis", "fixturemodules" );
			var connection = controller
				.getWireBox()
				.getInstance( "RedisConnection@cbRedis" );
			expect( connection.ping() ).toBeTrue();
			expect( connection )
				.toBe(
					controller
						.getWireBox()
						.getInstance( "RedisConnection@cbRedis" )
				);
			controller.getModuleService().unload( "cbRedis" );
			expect( () => connection.client() ).toThrow( "cbRedis.Closed" );
		} finally {
			fixtureApp.shutdown();
			restoreApplication( preserved );
		}
	}

	private function restoreApplication( preserved ) {
		for ( var key in preserved ) {
			application[ key ] = preserved[ key ];
		}
	}

}