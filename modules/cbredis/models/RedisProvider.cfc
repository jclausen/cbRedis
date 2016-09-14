/**
Author: Jon Clausen
Description:
	
This CacheBox provider communicates with a single Redis node or a 
cluster of Redis nodes for a distributed and highly scalable cache store.

*/
component name="RedisProvider" serializable="false" implements="coldbox.system.cache.ICacheProvider" accessors=true{
	property name="JavaLoader" inject="Loader@cbjavaloader";
	/**
    * Constructor
    **/
	function init() {
		//Store our clients at the application level to prevent re-creation since Wirebox scoping may or may not be available
		if( !structKeyExists( application, "RedisProvider" ) ) application[ "RedisProvider" ] = {};
		// prepare instance data
		instance = {
			// provider name
			name 				= "",
			// provider version
			version				= "1.0",
			// provider enable flag
			enabled 			= false,
			// reporting enabled flag
			reportingEnabled 	= false,
			// configuration structure
			configuration 		= {},
			// cacheFactory composition
			cacheFactory 		= "",
			// event manager composition
			eventManager		= "",
			// storage composition, even if it does not exist, depends on cache
			store				= "",
			// the cache identifier for this provider
			cacheID				= createObject('java','java.lang.System').identityHashCode( this ),
			// Element Cleaner Helper
			elementCleaner		= CreateObject("component","coldbox.system.cache.util.ElementCleaner").init( this ),
			// Utilities
			utility				= createObject("component","coldbox.system.core.util.Util"),
			// our UUID creation helper
			uuidHelper			= createobject("java", "java.util.UUID"),
			// Java URI class
			URIClass 			= createObject("java", "java.net.URI"),
			// Java Time Units
			timeUnitClass 		= createObject("java", "java.util.concurrent.TimeUnit"),
			// For serialization of complex values
			converter			= createObject("component","coldbox.system.core.conversion.ObjectMarshaller").init(),
			// Java System for Debug Messages
			JavaSystem 			= createObject("java","java.lang.System"),
			// Javaloader ID placeholder
			javaLoaderID		= "",
			// The design document which tracks our keys in use
			designDocumentName = 'CacheBox_allKeys'
		};

		// JavaLoader Static ID
		instance.javaLoaderID 		= "cbRedis-#instance.version#-loader";
		
		// Provider Property Defaults
		instance.DEFAULTS = {
			maxConnections = 10
			,defaultTimeoutUnit = "MINUTES"
			,objectDefaultTimeout = 30
            ,opQueueMaxBlockTime = 5000
	        ,opTimeout = 5000
	        ,timeoutExceptionThreshold = 5000
	        ,ignoreRedisTimeouts = true
			,bucket = "default"
			,server = "localhost:6379" // This can be an array
			,password = ""
			,caseSensitiveKeys : true
			,updateStats : true
			,debug = false
			,dbIndex = 0
		};		
		
		return this;
	}
	
	/**
    * get the cache name
    */    
	any function getName() output="false" {
		return instance.name;
	}
	
	/**
    * get the cache provider version
    */    
	any function getVersion() output="false" {
		return instance.version;
	}
	
	/**
    * set the cache name
    */    
	void function setName(required name) output="false" {
		instance.name = arguments.name;
	}
	
	/**
    * set the event manager
    */
    void function setEventManager(required any EventManager) output="false" {
    	instance.eventManager = arguments.eventManager;
    }
	
    /**
    * get the event manager
    */
    any function getEventManager() output="false" {
    	return instance.eventManager;
    }
    
	/**
    * get the cache configuration structure
    */
    any function getConfiguration() output="false" {
		return instance.config;
	}
	
	/**
    * set the cache configuration structure
    */
    void function setConfiguration(required any configuration) output="false" {
		instance.config = arguments.configuration;
	}
	
	/**
    * get the associated cache factory
    */
    any function getCacheFactory() output="false" {
		return instance.cacheFactory;
	}
		
	/**
    * set the associated cache factory
    */
    void function setCacheFactory(required any cacheFactory) output="false" {
		instance.cacheFactory = arguments.cacheFactory;
	}
		
	/**
    * get the Redis Client
    */
    any function getRedisClient() {
    	var ts = getTickCount();
		// lock creation	
		lock name="Provider.config.#instance.cacheID#" type="exclusive" throwontimeout="true" timeout="5"{
    		
    		if( !structKeyExists(application,'cbcontroller') || isNull( application.cbController.getWirebox() ) ) throw "Wirebox is required to use this provider";
		
			if( isNull( getJavaLoader() ) ) application.cbController.getWirebox().autowire(this);

			//try{
				if( !structKeyExists( application, "RedisPool" ) ){
					
					var serverArray = listToArray( instance.config.server, ":" );
					if( arraylen( serverArray ) < 2 ) arrayAppend( serverArray, 6379 );
					var PoolConfig = Javaloader.create( "org.apache.commons.pool2.impl.GenericObjectPoolConfig" );
					PoolConfig.setMaxWaitMillis( javacast( 'long', getConfiguration().timeoutExceptionThreshold ) );
					//PoolConfig.setMaxTotal( javacast( 'int', instance.config.maxConnections ) );
					//PoolConfig.setMaxIdle( javacast( 'int', ceiling( instance.config.maxConnections * .25 ) ) );
						
					if( !len( trim( instance.config.password ) ) ){
						application.RedisPool = Javaloader.create( "redis.clients.jedis.JedisPool" ).init( PoolConfig, javacast( "string", serverArray[ 1 ] ), javacast( 'int', serverArray[ 2 ] ) );	
					} else {
						application.RedisPool = Javaloader.create( "redis.clients.jedis.JedisPool" ).init( PoolConfig, javacast( "string", serverArray[ 1 ] ), javacast( 'int', serverArray[ 2 ] ), javacast( "string", instance.config.password ) );	
					}

					application[ "RedisActiveClients" ] = [];

					application.RedisPool.addObjects( javacast( 'int', instance.config.maxConnections ) );

					instance["RedisPool"] = application.RedisPool;

				} else {
					
					instance["RedisPool"] = application.RedisPool;
				
				}
			// } catch( Any e ){
			// 	instance.logger.error("There was an error creating the Redis Client: #e.message# #e.detail#", e );
			// 	throw(message='There was an error creating the Redis Client', detail=e.message & " " & e.detail);
			// }
		}

		//reap and restore our pool
		reapPool();

		var getActiveResource = function(){
			try{
				var resource = instance.RedisPool.getResource();
				resource.select( getConfiguration().dbIndex );
				arrayAppend( application.RedisActiveClients, resource );
				return resource;
			} catch( any e ){
				var te = getTickCount();
				if( getConfiguration().debug ) instance.JavaSystem.out.printLn( "Redis client failed become avaialable after #( te - ts )#ms. Pool sanitization initiated." );
				//try to clean up our pool if open connections were left out there
				if( e.type == 'redis.clients.jedis.exceptions.JedisException' ){
					try{
						for( var activeResource in application.RedisActiveClients ){
							try{							
								returnToPool( activeResource );	
							} catch( any e ){
								
							}
						}
						reapPool();
						return getRedisClient();	
					} catch( any e ){
						rethrow;
					}
				} else {
					rethrow;
				}
			}
		};
		
		return getActiveResource();

	}

	function returnToPool( any RedisClient ){
		instance.RedisPool.returnResource( RedisClient );
		arrayDelete( application.RedisActiveClients, arguments.RedisClient );
	}

	function reapPool(){
		var activeClients = instance.RedisPool.getNumActive();
		var idleClients = instance.RedisPool.getNumIdle();
		var maxClients = getConfiguration().maxConnections;

		if( (activeClients + idleClients) < maxClients ){
			instance.RedisPool.addObjects( maxClients - (activeClients + idleClients) );
		}
	}
				
	/**
    * configure the cache for operation
    */
    void function configure() output="false" {

		var config 	= getConfiguration();
		var props	= [];
		var URIs 	= [];
    	var i = 0;
		
		// Prepare the logger
		instance.logger = getCacheFactory().getLogBox().getLogger( this );
		instance.logger.debug("Starting up Provider Cache: #getName()# with configuration: #config.toString()#");
		
		// Validate the configuration
		validateConfiguration();

		// enabled cache
		instance.enabled = true;
		instance.reportingEnabled = true;
		instance.logger.info("Cache #getName()# started up successfully");
		
	}
	
	/**
    * shutdown the cache
    */
    void function shutdown() output="false" {
    	
    	instance.logger.info("Provider Cache: #getName()# has been shutdown.");
	}
	
	/*
	* Indicates if cache is ready for operation
	*/
	any function isEnabled() output="false" {
		return instance.enabled;
	} 

	/*
	* Indicates if cache is ready for reporting
	*/
	any function isReportingEnabled() output="false" {
		return instance.reportingEnabled;
	}
	
	/*
	* Get the cache statistics object as coldbox.system.cache.util.ICacheStats
	* @colddoc:generic coldbox.system.cache.util.ICacheStats
	*/
	any function getStats() output="false" {
		// Not yet implmented		
	}
	
	/**
    * clear the cache stats: 
    */
    void function clearStatistics() output="false" {
    	// Not yet implemented
	}
	
	/**
    * Returns the underlying cache engine represented by a Redisclient object
    * http://www.redis.com/autodocs/redis-java-client-1.1.5/index.html
    */
    any function getObjectStore() output="false" {
    	// This provider uses an external object store
    	return getRedisClient();
	}
	
	/**
    * get the cache's metadata report
    * @tested
    */
    any function getStoreMetadataReport() output="false" {	
		var md 		= {};
		var keys 	= getKeys();
		var item	= "";
		for( item in keys ){
			md[ item ] = getCachedObjectMetadata( item );
		}
		
		return md;
	}
	
	/**
	* Get a key lookup structure where cachebox can build the report on. Ex: [timeout=timeout,lastAccessTimeout=idleTimeout].  It is a way for the visualizer to construct the columns correctly on the reports
	* @tested
	*/
	any function getStoreMetadataKeyMap() output="false"{
		var keyMap = {
				LastAccessed = "LastAccessed",
				isExpired = "isExpired",
				timeout = "timeout",
				lastAccessTimeout = "lastAccessTimeout",
				hits = "hits",
				created = "createddate"
			};
		return keymap;
	}
	
	/**
    * get all the keys in this provider
    * @tested
    */
    any function getKeys() output="false" {
    	
    	local.allView = get( instance.designDocumentName );

    	if( isNull( local.allView ) ){
    		local.allView = [];
    		set( instance.designDocumentName, local.allView );
    	} else if( !isArray( local.allView ) ){
    		writeDump(var="BAD FORMAT",top=1);
    		writeDump(var=local.allView);
    		abort;
    	}

    	return local.allView;

	}

	void function appendCacheKey( objectKey ){

		var result = get( instance.designDocumentName );

		if( !isNull( result ) && isArray( result ) ) {
			if( isArray( arguments.objectKey ) ){
				arrayAppend( result, arguments.objectKey, true );
			} else if( !arrayFind( result, arguments.objectKey ) ){
				arrayAppend( result, arguments.objectKey );
				set( instance.designDocumentName, result );
			}
		} else {
			set( instance.designDocumentName, [ arguments.objectKey ] );
		}

	}
	
	/**
    * get an object's cached metadata
    * @tested
    */
    any function getCachedObjectMetadata(required any objectKey) output="false" {
    	// lower case the keys for case insensitivity
		if( !getConfiguration().caseSensitiveKeys )  arguments.objectKey = lcase( arguments.objectKey );
		
		// prepare stats return map
    	local.keyStats = {
			timeout = "",
			lastAccessed = "",
			timeExpires = "",
			isExpired = 0,
			isDirty = 0,
			isSimple = 1,
			createdDate = "",
			metadata = {},
			cas = "",
			dataAge = 0,
			// We don't track these two, but I need a dummy values
			// for the CacheBox item report.
			lastAccessTimeout = 0,
			hits = 0
		};

		var RedisClient = getRedisClient();
    	var local.object = RedisClient.get( arguments.objectKey );
    	returnToPool( RedisClient );
    	// item is no longer in cache, or it's not a JSON doc.  No metastats for us
    	if( structKeyExists( local, "object" ) && isJSON( local.object ) ){
    		
    		// inflate our object from JSON
			local.inflatedElement = deserializeJSON( local.object );
			local.stats = duplicate( local.inflatedElement );

			for( var key in local.keyStats ){
				if( structKeyExists( local.stats, key ) ) local.keyStats[ key ] = local.stats[ key ];
			}

    		// key_exptime
    		if( structKeyExists( local.stats, "key_exptime" ) and isNumeric( local.stats[ "key_exptime" ] ) ){
    			local.keyStats.timeExpires = dateAdd("s", local.stats[ "key_exptime" ], dateConvert( "utc2Local", "January 1 1970 00:00" ) ); 
    		}
    		// key_last_modification_time
    		if( structKeyExists( local.stats, "key_last_modification_time" ) and isNumeric( local.stats[ "key_last_modification_time" ] ) ){
    			local.keyStats.lastAccessed = dateAdd("s", local.stats[ "key_last_modification_time" ], dateConvert( "utc2Local", "January 1 1970 00:00" ) ); 
    		}
    		// state
    		if( structKeyExists( local.stats, "key_vb_state" ) ){
    			local.keyStats.isExpired = ( local.stats[ "key_vb_state" ] eq "active" ? false : true ); 
    		}
    		// dirty
			if( structKeyExists( local.stats, "key_is_dirty" ) ){
    			local.keyStats.isDirty = local.stats[ "key_is_dirty" ]; 
    		}
    		// data_age
			if( structKeyExists( local.stats, "key_data_age" ) ){
    			local.keyStats.dataAge = local.stats[ "key_data_age" ]; 
    		}
    		// cas
			if( structKeyExists( local.stats, "key_cas" ) ){
    			local.keyStats.cas = local.stats[ "key_cas" ]; 
    		}

			// Simple values like 123 might appear to be JSON, but not a struct
			if(!isStruct(local.inflatedElement)) {
	    		return local.keyStats;
			}
					
			// createdDate
			if( structKeyExists( local.inflatedElement, "createdDate" ) ){
	   			local.keyStats.createdDate = local.inflatedElement.createdDate;
			}
			// timeout
			if( structKeyExists( local.inflatedElement, "timeout" ) ){
	   			local.keyStats.timeout = local.inflatedElement.timeout;
			}
			// metadata
			if( structKeyExists( local.inflatedElement, "metadata" ) ){
	   			local.keyStats.metadata = local.inflatedElement.metadata;
			}
			// isSimple
			if( structKeyExists( local.inflatedElement, "isSimple" ) ){
	   			local.keyStats.isSimple = local.inflatedElement.isSimple;
			}
    	}		
		
    	
    	return local.keyStats;
	}
	
	/**
    * get an item from cache, returns null if not found.
    * @tested
    */
    any function get(required any objectKey) output="false" {
    	return getQuiet(argumentCollection=arguments);
	}
	
	/**
    * get an item silently from cache, no stats advised: Stats not available on Redis
    * @tested
    */
    any function getQuiet(required any objectKey) output="false" {
    	// lower case the keys for case insensitivity
		if( !getConfiguration().caseSensitiveKeys ) arguments.objectKey = lcase( arguments.objectKey );
		
		try {
			var RedisClient = getObjectStore();
    		// local.object will always come back as a string
    		local.object = RedisClient.get( javacast( "string", arguments.objectKey ) );
    		returnToPool( RedisClient );

			// item is no longer in cache, return null
			if( isNull( local.object ) ){
				return;
			}
			
			// return if not our JSON
			if( !isJSON( local.object ) ){
				return local.object;
			}
			
			// inflate our object from JSON

			local.inflatedElement = deserializeJSON( local.object );
			
			
			// Simple values like 123 might appear to be JSON, but not a struct
			if(!isStruct(local.inflatedElement)) {
				return local.object;
			}


			// Is simple or not?
			if( structKeyExists( local.inflatedElement, "isSimple" ) and local.inflatedElement.isSimple ){
				if( getConfiguration().updateStats ) updateObjectStats( arguments.objectKey, duplicate( local.inflatedElement ) );
				return local.inflatedElement.data;
			}

			// else we deserialize and return
			if( structKeyExists( local.inflatedElement, "data" ) ){
				local.inflatedElement.data = instance.converter.deserializeGeneric(binaryObject=local.inflatedElement.data);
				if( getConfiguration().updateStats ) updateObjectStats( arguments.objectKey, duplicate( local.inflatedElement ) );	
				return local.inflatedElement.data;
			}

			// who knows what this is?
			return local.object;
		}
		catch(any e) {
			
			if( isTimeoutException( e ) && getConfiguration().ignoreRedisTimeouts ) {
				// log it
				instance.logger.error( "Redis timeout exception detected: #e.message# #e.detail#", e );
				// Return nothing as though it wasn't even found in the cache
				return;
			}
			
			// For any other type of exception, rethrow.
			rethrow;
		}
	}

	any function getMulti( 
		required array objectKeys
	){
		var ts = getTickCount();
		var results = {};
		
		var RedisClient = getRedisClient();
		
		var t = RedisClient.multi();

		for( var key in arguments.objectKeys ){
			t.get( javacast('string',key) );
		}

		var transactionResult = t.exec();

		returnToPool( RedisClient );

		var i = 1;
		for( var item in transactionResult ){
			
			if( isNull(item) || findNoCase( "undefined array element", item ) ) continue;

			var entry = deSerializeJSON( item );
			
			if( !entry.isSimple ) entry.data = instance.converter.deserializeGeneric( binaryObject=entry.data );
			
			results[ arguments.objectKeys[ i ] ] = entry.data;

			i++;
		}

		var te = getTickCount();

		if( getConfiguration().debug ) instance.JavaSystem.out.printLn( "Redis getMulti() executed in #( te - ts )#ms" );

		return results;
	}
	
	/**
    * Not implemented by this cache
    */
    any function isExpired(required any objectKey) output="false" {
		return getCachedObjectMetadata( arguments.objectKey ).isExpired;
	}
	 
	/**
    * check if object in cache
    * @tested
    */
    any function lookup(required any objectKey) output="false" {
    	return ( isNull( get( objectKey ) ) ? false : true );
	}
	
	/**
    * check if object in cache with no stats: Stats not available on Redis
    * @tested
    */
    any function lookupQuiet(required any objectKey) output="false" {
		// not possible yet on Redis
		return lookup( arguments.objectKey );
	}
	
	/**
    * set an object in cache and returns an object future if possible
    * lastAccessTimeout.hint Not used in this provider
    * @tested
    */
    any function set(
    	required any objectKey,
		required any object,
		any timeout=instance.config.objectDefaultTimeout,
		any lastAccessTimeout=0, // Not in use for this provider
		any extra={}
	) output="false" {
		
    	var ts = getTickCount();

		var future = setQuiet(argumentCollection=arguments);
		
		//ColdBox events
		var iData = { 
			"cache"				= this,
			"cacheObject"			= arguments.object,
			"cacheObjectKey" 		= arguments.objectKey,
			"cacheObjectTimeout" 	= arguments.timeout,
			"cacheObjectLastAccessTimeout" = arguments.lastAccessTimeout,
			"redisFuture" 	= future
		};

		if( arguments.objectKey != instance.designDocumentName ) appendCacheKey( arguments.objectKey );

		getEventManager().processState( state="afterCacheElementInsert", interceptData=iData, async=true );
		

    	var te = getTickCount();

		if( getConfiguration().debug ) instance.JavaSystem.out.printLn( "Redis set( #objectKey# ) executed in #( te - ts )#ms" );

		return future;
	}

	void function updateObjectStats( required any objectKey, required any cacheObject ){
		
		if( !getConfiguration().caseSensitiveKeys ) arguments.objectKey = lcase( arguments.objectKey );
		if( !structKeyExists( cacheObject, "hits" ) ) cacheObject[ "hits" ] = 0;

		cacheObject[ "lastAccessed" ] = dateformat( now(), "mm/dd/yyyy") & " " & timeformat( now(), "full" );
		cacheObject[ "hits" ]++;

		// Do we need to serialize incoming obj
		if( !cacheObject.isSimple && !isSimpleValue( cacheObject.data ) ){
			cacheObject.data = instance.converter.serializeGeneric( cacheObject.data );
		}

		persistToCache( arguments.objectKey, cacheObject , true );
	}	
	
	/**
    * set an object in cache with no advising to events, returns a redis future if possible
    * lastAccessTimeout.hint Not used in this provider
    * @tested
    */
    any function setQuiet(
	    required any objectKey,
		required any object,
		any timeout=instance.config.objectDefaultTimeout,
		any lastAccessTimeout=0, //Not in use for this provider
		any extra={}
	) output="false" {
		
		return persistToCache( arguments.objectKey, formatCacheObject( argumentCollection=arguments ) );
	}	


	/**
    * Set multiple items in to the cache
    * lastAccessTimeout.hint Not used in this provider
    * @tested
    */
	any function setMulti( 
		required struct mapping,
		any timeout=instance.config.objectDefaultTimeout,
		any lastAccessTimeout=0, // Not in use for this provider
		any extra={}
	) output="false" {
		var ts = getTickCount();

		var RedisClient = getRedisClient();
		var t = RedisClient.multi();
		//Jedi handles bulk writes via transactions
		for( var key in arguments.mapping ){
			if( !getConfiguration().caseSensitiveKeys )  key = lcase( key );
			t.set( javacast("string",key), serializeJSON( formatCacheObject( arguments.mapping[ key ] ) ) );
			t.expire( key,  arguments.timeout );
			if( getConfiguration().debug ) instance.JavaSystem.out.println( "Appended #key# to setMulti() transaction" );
		}
		var transactionResult = t.exec();
		var te = getTickCount();
		if( getConfiguration().debug ) instance.JavaSystem.out.printLn( "Redis Cache Provider setMulti() executed in #( te - ts )#ms" );
		returnToPool( RedisClient );
		appendCacheKey( structKeyArray( arguments.mapping ) );
		return transactionResult;
	}

	any function formatCacheObject( 
		required any object,
		any timeout=instance.config.objectDefaultTimeout,
		any lastAccessTimeout=0, //Not in use for this provider
		any extra={}
	) output="false" {
		// create storage element
		var sElement = {
			"createdDate" = dateformat( now(), "mm/dd/yyyy") & " " & timeformat( now(), "full" ),
			"timeout" = arguments.timeout,
			"metadata" = ( !isNull(arguments.extra) && structKeyExists( arguments.extra, "metadata" ) ? arguments.extra.metadata : {} ),
			"isSimple" = isSimpleValue( arguments.object ),
			"data" = arguments.object,
			"hits" = 0
		};

		// Do we need to serialize incoming obj
		if( !sElement.isSimple ){
			sElement.data = instance.converter.serializeGeneric( sElement.data );
		}

		return sElement;
	}

	any function persistToCache( 
		required any objectKey,
		required any cacheObject,
		boolean replaceItem=false
		any extra
	) output="false" {

		if( !getConfiguration().caseSensitiveKeys )  arguments.objectKey = lcase( arguments.objectKey );	


		// Serialize element to JSON
		var sElement = serializeJSON( arguments.cacheObject );
		var RedisClient = getRedisClient();

    	try {
    		
			// You can pass in a net.spy.redis.transcoders.Transcoder to override the default
			if( structKeyExists( arguments, 'extra' ) && structKeyExists( arguments.extra, 'transcoder' ) ){
				var future = RedisClient.set( javaCast( "string", arguments.objectKey ), javaCast( "int", arguments.cacheObject.timeout*60 ), sElement, extra.transcoder );
				RedisClient.expire( javacast( "string", arguments.objectKey ), javacast( 'int', arguments.cacheObject.timeout*60 ) );
				returnToPool( RedisClient );
			}
			else {
				var future = RedisClient.set( javaCast( "string", arguments.objectKey ), sElement );
				RedisClient.expire( javacast( "string", arguments.objectKey ), javacast( 'int', arguments.cacheObject.timeout*60 ) );
				returnToPool( RedisClient );
			}

			
		}
		catch(any e) {
			
			if( isTimeoutException( e ) && getConfiguration().ignoreRedisTimeouts) {
				// log it
				instance.logger.error( "Redis timeout exception detected: #e.message# #e.detail#", e );
				// return nothing
				return;
			}
			
			// For any other type of exception, rethrow.
			rethrow;
		}
		
		return future;
	}
		
	/**
    * get cache size
    * @tested
    */
    any function getSize() output="false" {
 		// Not implemented
	}
	
	/**
    * Not implemented by this cache
    * @tested
    */
    void function reap() output="false" {
		// Not implemented by this provider
	}
	
	/**
    * clear all elements from cache
    * @tested
    */
    void function clearAll() output="false" {
		
		// If flush is not enabled for this bucket, no error will be thrown.  The call will simply return and nothing will happen.
		// Be very careful calling this.  It is an intensive asynch operation and the cache won't receive any new items until the flush
		// is finished which might take a few minutes.
		var RedisClient = getObjectStore();
		var future = RedisClient.flushDB();		
		returnToPool( RedisClient );
		var iData = {
			cache			= this,
			redisFuture = future
		};
		
		// notify listeners		
		getEventManager().processState("afterCacheClearAll",iData);
	}
	
	/**
    * clear an element from cache and returns the redis java future
    * @tested
    */
    any function clear(required any objectKey) output="false" {
		// lower case the keys for case insensitivity
		if( !getConfiguration().caseSensitiveKeys ) arguments.objectKey = lcase( arguments.objectKey );

		//allow an array of keys to be passed for multi clear
		if( isArray( arguments.objectKey ) ) arguments.objectKey = arrayToList( objectKey );
		
		// Delete from redis
		var RedisClient = getObjectStore();
		var future = RedisClient.del( arguments.objectKey );
		returnToPool( RedisClient );

		//ColdBox events
		var iData = { 
			cache				= this,
			cacheObjectKey 		= arguments.objectKey,
			redisFuture		= future
		};		
		getEventManager().processState( state="afterCacheElementRemoved", interceptData=iData, async=true );
		
		return future;
	}
	
	/**
    * Clear with no advising to events and returns with the redis java future
    * @tested
    */
    any function clearQuiet(required any objectKey) output="false" {
		// normal clear, not implemented by Redis
		return clear( arguments.objectKey );
	}
	
	/**
	* Clear by key snippet
	*/
	void function clearByKeySnippet(required keySnippet, regex=false, async=false) output="false" {

		var threadName = "clearByKeySnippet_#replace(instance.uuidHelper.randomUUID(),"-","","all")#";
		
		// Async? IF so, do checks
		if( arguments.async AND NOT instance.utility.inThread() ){
			thread name="#threadName#"{
				instance.elementCleaner.clearByKeySnippet(arguments.keySnippet,arguments.regex);
			}
		}
		else{
			instance.elementCleaner.clearByKeySnippet(arguments.keySnippet,arguments.regex);
		}
		
	}
	
	/**
    * Expiration not implemented by redis so clears are issued
    * @tested
    */
    void function expireAll() output="false"{ 
		clearAll();
	}
	
	/**
    * Expiration not implemented by redis so clear is issued
    * @tested
    */
    void function expireObject(required any objectKey) output="false"{
		clear( arguments.objectKey );
	}

	/************************************** PRIVATE *********************************************/
	
	/**
	* Validate the incoming configuration and make necessary defaults
	**/
	private void function validateConfiguration() output="false"{
		var cacheConfig = getConfiguration();
		var key			= "";
		
		// Validate configuration values, if they don't exist, then default them to DEFAULTS
		for(key in instance.DEFAULTS){
			if( !structKeyExists( cacheConfig, key) || ( !isBoolean(cacheConfig[ key ]) && isSimpleValue( cacheConfig[ key ] ) && !len( cacheConfig[ key ] ) ) ){
				cacheConfig[ key ] = instance.DEFAULTS[ key ];
			}
		}

		instance.designDocumentName &= "-" &  getName();

	}
	
	/**
    * Format the incoming simple couchbas server URL location strings into our format
    */
    private any function formatServers(required servers) {
    	var i = 0;

    	var formattedServers = createObject( "java", "java.util.ArrayList" );

		if( !isArray( servers ) ){
			servers = listToArray( servers );
		}

		for( var configServer in servers  ){
			var address = listToArray( configServer, ":" );
			if( !arraylen( address ) > 1 ) throw( "RedisProviderException", "The address provided ( #server# ) does not contain an address/port configuration" );
			var socketAddr = createObject("java", "java.net.InetSocketAddress" ).init( address[ 1 ], address[ 2 ] );
			formattedServers.add( socketAddr );
		}
		
		return formattedServers;
	}
	
	private boolean function isTimeoutException(required any exception){
    	return (exception.type == 'redis.clients.jedis.exceptions.JedisConnectionException' || exception.message == 'Exception waiting for value' || exception.message == 'Interrupted waiting for value');
	}
	
	/**
    * Deal with errors that came back from the cluster
    * rowErrors is an array of com.redis.client.protocol.views.RowError
    */
    private any function handleRowErrors(message, rowErrors) {
    	local.detail = '';
    	for(local.error in arguments.rowErrors) {
    		local.detail &= local.error.getFrom();
    		local.detail &= local.error.getReason();
    	}
    	
    	// It appears that there is still a useful result even if errors were returned so
    	// we'll just log it and not interrupt the request by throwing.  
    	instance.logger.warn(arguments.message, local.detail);
    	//Throw(message=arguments.message, detail=local.detail);
    	
    	return this;
    }

}
