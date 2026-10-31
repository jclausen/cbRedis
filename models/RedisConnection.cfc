/**
 * One bounded, thread-safe Jedis pool per object. No application-wide pool or
 * borrowed resources to track. Requires Java 17+. No credentials are logged.
 */
component {

	function init( struct configuration = {} ) {
		variables.configuration = duplicate( configuration );
		variables.id = createUUID();
		variables.closed = false;
		variables.jars = directoryList(
			getDirectoryFromPath( getCurrentTemplatePath() ) & "../lib",
			false,
			"path",
			"*.jar"
		);
		return this;
	}

	function client() {
		lock name   ="cbredis.connection.#variables.id#" type   ="exclusive" timeout="10" {
			if ( variables.closed ) {
				throw(
					type    = "cbRedis.Closed",
					message = "The Redis connection is closed"
				);
			}
			if ( !structKeyExists( variables, "poolClient" ) ) {
				validate();
				try {
					variables.poolClient = buildClient();
				} catch (any failure) {
					throw(
						type    = "cbRedis.ConnectionUnavailable",
						message = "Unable to initialize the Redis connection"
					);
				}
			}
			return variables.poolClient;
		}
	}

	boolean function ping() {
		try {
			return client().ping() == "PONG";
		} catch (any failure) {
			throw(
				type    = "cbRedis.ConnectionUnavailable",
				message = "Redis is unavailable"
			);
		}
	}

	/** Lua uses Java Lists explicitly, avoiding engine-dependent varargs dispatch. */
	function eval(
		required string script,
		required array keys,
		required array args
	) {
		try {
			return client()
				.eval(
					script,
					createObject( "java", "java.util.ArrayList" ).init( keys ),
					createObject( "java", "java.util.ArrayList" ).init( args )
				);
		} catch (any failure) {
			throw(
				type    = "cbRedis.OperationFailed",
				message = "The Redis operation could not be completed"
			);
		}
	}

	/** Atomic lease acquisition, with a mandatory finite expiration in milliseconds. */
	boolean function setIfAbsent(
		required string key,
		required string value,
		required numeric milliseconds
	) {
		if ( milliseconds != fix( milliseconds ) || milliseconds < 1 || milliseconds > 3600000 ) {
			throw(
				type    = "cbRedis.InvalidConfiguration",
				message = "A lease must expire within one hour"
			);
		}
		return eval(
				"local result=redis.call('set',KEYS[1],ARGV[1],'NX','PX',ARGV[2]);if result then return 1 else return 0 end",
				[ key ],
				[ value, toString( milliseconds ) ]
			) ==
			1;
	}

	/** Terminal and idempotent; shutdown cannot silently recreate a pool. */
	function close() {
		lock name   ="cbredis.connection.#variables.id#" type   ="exclusive" timeout="10" {
			variables.closed = true;
			if ( structKeyExists( variables, "poolClient" ) ) {
				variables.poolClient.close();
				structDelete( variables, "poolClient" );
			}
		}
		return this;
	}

	private function buildClient() {
		var config = javaClass( "redis.clients.jedis.DefaultJedisClientConfig" )
			.builder()
			.connectionTimeoutMillis(
				javaCast( "int", variables.configuration.connectionTimeoutMillis )
			)
			.socketTimeoutMillis(
				javaCast( "int", variables.configuration.socketTimeoutMillis )
			)
			.database(
				javaCast( "int", variables.configuration.database )
			);
		if ( len( variables.configuration.username ) ) {
			config.user( variables.configuration.username );
		}
		if ( len( variables.configuration.password ) ) {
			config.password( variables.configuration.password );
		}
		if ( variables.configuration.tls ) {
			var parameters = createObject( "java", "javax.net.ssl.SSLParameters" ).init();
			parameters.setEndpointIdentificationAlgorithm( "HTTPS" );
			config.ssl( true ).sslParameters( parameters );
			if ( len( variables.configuration.caFile ) ) {
				config
					.sslSocketFactory(
						trustContext( variables.configuration.caFile )
							.getSocketFactory()
					);
			}
		}
		var pool = javaClass(
			"org.apache.commons.pool2.impl.GenericObjectPoolConfig"
		)
			.init();
		pool
			.setMaxTotal(
				javaCast( "int", variables.configuration.maxConnections )
			);
		pool
			.setMaxIdle(
				javaCast( "int", variables.configuration.maxConnections )
			);
		pool
			.setMaxWait(
				createObject( "java", "java.time.Duration" )
					.ofMillis(
						javaCast( "long", variables.configuration.poolWaitMillis )
					)
			);
		return javaClass( "redis.clients.jedis.RedisClient" )
			.builder()
			.hostAndPort(
				variables.configuration.host,
				javaCast( "int", variables.configuration.port )
			)
			.clientConfig( config.build() )
			.poolConfig( pool )
			.build();
	}

	private function trustContext( required string path ) {
		var input = createObject( "java", "java.io.FileInputStream" ).init( path );
		var store = createObject( "java", "java.security.KeyStore" )
			.getInstance( "PKCS12" );
		store.load( javaCast( "null", "" ), javaCast( "null", "" ) );
		try {
			var certificates = createObject( "java", "java.security.cert.CertificateFactory" )
				.getInstance( "X.509" )
				.generateCertificates( input );
			var index = 0;
			for ( var certificate in certificates ) {
				store.setCertificateEntry( "ca-" & ++index, certificate );
			}
			if ( !index ) {
				throw(
					type    = "cbRedis.InvalidConfiguration",
					message = "The Redis CA bundle is empty"
				);
			}
		} finally {
			input.close();
		}
		var managers = createObject( "java", "javax.net.ssl.TrustManagerFactory" )
			.getInstance( "PKIX" );
		managers.init( store );
		var context = createObject( "java", "javax.net.ssl.SSLContext" )
			.getInstance( "TLS" );
		context
			.init(
				javaCast( "null", "" ),
				managers.getTrustManagers(),
				javaCast( "null", "" )
			);
		return context;
	}

	private function javaClass( required string name ) {
		return createObject(
			"java",
			name,
			variables.jars
		);
	}

	private function validate() {
		var defaults = {
			host                    : "localhost",
			port                    : 6379,
			username                : "",
			password                : "",
			database                : 0,
			tls                     : true,
			caFile                  : "",
			maxConnections          : 8,
			poolWaitMillis          : 3000,
			connectionTimeoutMillis : 3000,
			socketTimeoutMillis     : 3000
		};
		structAppend(
			variables.configuration,
			defaults,
			false
		);
		var config = variables.configuration;
		if ( !len( trim( config.host ) ) || reFind( "[\s/@]", config.host ) ) {
			throw(
				type    = "cbRedis.InvalidConfiguration",
				message = "Supply a Redis hostname, not a credential-bearing URL"
			);
		}
		for ( var name in [
			"port",
			"database",
			"maxConnections",
			"poolWaitMillis",
			"connectionTimeoutMillis",
			"socketTimeoutMillis"
		] ) {
			if ( !isNumeric( config[ name ] ) || config[ name ] != fix( config[ name ] ) ) {
				throw(
					type    = "cbRedis.InvalidConfiguration",
					message = "Redis numeric settings must be integers"
				);
			}
		}
		if (
			config.port < 1 || config.port > 65535 || config.database < 0 || config.maxConnections < 1 ||
												config.maxConnections > 128 ||
											config.poolWaitMillis < 1 ||
										config.poolWaitMillis > 60000 ||
									config.connectionTimeoutMillis < 1 ||
								config.connectionTimeoutMillis > 60000 ||
							config.socketTimeoutMillis < 1 ||
						config.socketTimeoutMillis > 60000 ||
					!isBoolean( config.tls ) ||
				( !config.tls && len( config.caFile ) )
		) {
			throw(
				type    = "cbRedis.InvalidConfiguration",
				message = "Invalid Redis connection bounds or TLS settings"
			);
		}
		if ( len( config.caFile ) && !fileExists( config.caFile ) ) {
			throw(
				type    = "cbRedis.InvalidConfiguration",
				message = "The Redis CA bundle does not exist"
			);
		}
	}

}