/** Focused contracts against an explicitly supplied, owned local Valkey fixture. */
component {

	function run(
		required numeric port,
		required numeric tlsPort,
		required string caFile,
		required string wrongCaFile
	) {
		if ( port < 1024 || tlsPort < 1024 || port == tlsPort ) {
			throw(
				message = "Use distinct ephemeral local fixture ports"
			);
		}
		var root = variables.fileSystemUtil.resolvePath( "." );
		for ( var mapping in [
			"cbRedis",
			"testbox",
			"coldbox",
			"tests"
		] ) {
			variables
				.fileSystemUtil
				.createMapping(
					"/" & mapping,
					mapping == "cbRedis" ? root : root & "/" & mapping
				);
		}
		request.cbRedisFixture = {
			port        : port,
			tlsPort     : tlsPort,
			caFile      : variables.fileSystemUtil.resolvePath( caFile ),
			wrongCaFile : variables.fileSystemUtil.resolvePath( wrongCaFile )
		};
		variables
			.fileSystemUtil
			.createMapping( "/fixtureapp", root & "/tests/fixtureapp" );
		var installation = root & "/.tmp/module-installation/cbRedis";
		if ( !directoryExists( installation ) ) {
			directoryCreate( installation, true );
		}
		for ( var source in [ "ModuleConfig.cfc", "box.json" ] ) {
			fileCopy( root & "/" & source, installation & "/" & source );
		}
		for ( var source in [ "models", "lib" ] ) {
			directoryCopy(
				root & "/" & source,
				installation & "/" & source,
				true
			);
		}
		variables
			.fileSystemUtil
			.createMapping(
				"/fixturemodules",
				root & "/.tmp/module-installation"
			);
		var result = new testbox.system.TestBox(
			bundles = "tests.specs.modern.RedisSpec,tests.specs.modern.ModuleSpec"
		)
			.runRaw()
			.getMemento( includeDebugBuffer = true );
		for ( var bundle in result.bundleStats ) {
			for ( var suite in bundle.suiteStats ) {
				for ( var spec in suite.specStats ) {
					variables
						.print
						.line(
							spec.status & " " & spec.name & (
								len( spec.failMessage ) ? ": " & spec.failMessage : ""
							)
						);
					if ( spec.status == "Error" ) {
						variables
							.print
							.line( spec.error.message & " " & spec.error.detail );
					}
				}
			}
		}
		variables
			.print
			.line(
				"Passed: " & result.totalPass & "; failed: " & result.totalFail & "; errors: " & result.totalError
			);
		if ( result.totalFail || result.totalError || !result.totalPass ) {
			throw( message = "cbRedis contracts failed" );
		}
	}

}