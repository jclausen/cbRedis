/********************************************************************************
Copyright 2005-2007 ColdBox Framework by Luis Majano and Ortus Solutions, Corp
www.coldbox.org | www.luismajano.com | www.ortussolutions.com
********************************************************************************

Author     :	Luis Majano
Date        :	9/3/2007
Description :
	Request service Test
**/
component extends="coldbox.system.testing.BaseTestCase"{
	
	//Mocks
	mockFactory  = getMockBox().createEmptyMock(className='coldbox.system.cache.CacheFactory');
	mockEventManager  = getMockBox().createEmptyMock(className='coldbox.system.core.events.EventPoolManager');
	mockLogBox	 = getMockBox().createEmptyMock("coldbox.system.logging.LogBox");
	mockLogger	 = getMockBox().createEmptyMock("coldbox.system.logging.Logger");	
	// Mock Methods
	mockFactory.$("getLogBox",mockLogBox);
	mockLogBox.$("getLogger", mockLogger);
	mockLogger.$("error").$("debug").$("info").$("canDebug",true).$("canInfo",true).$("canError",true);
	mockEventManager.$("processState");
	
	function setup(){
		config = {
	        objectDefaultTimeout = 15,
	        opQueueMaxBlockTime = 5000,
	        opTimeout = 5000,
	        timeoutExceptionThreshold = 5000,
	        ignoreRedisTimeouts = true,				
	    	bucket="default",
	    	password="",
	    	servers="127.0.0.1:11211",
	    	// This switches the internal provider from normal cacheBox to coldbox enabled cachebox
			coldboxEnabled = false,
			caseSensitiveKeys = false
	    };
		
		// Create Provider
		cache = getMockBox().createMock("RedisProvider.models.RedisProvider").init();
		// Decorate it
		cache.setConfiguration( config );
		cache.setCacheFactory( mockFactory );
		cache.setEventManager( mockEventManager );
		
		// Configure the provider
		cache.configure();
		cache.clearAll();
		super.setup();
	}
	
	function testShutdown(){
		//cache.shutdown();
	}
	
	function testLookup(){
		// null test
		cache.$("get");
		assertFalse( cache.lookup( 'invalid' ) );
		
		// something
		cache.$("get", this);
		assertTrue( cache.lookup( 'valid' ) );	
	}
	
	function testLookupQuiet(){
		// null test
		cache.$("get");
		assertFalse( cache.lookupQuiet( 'invalid' ) );
		
		// something
		cache.$("get", this);
		assertTrue( cache.lookupQuiet( 'valid' ) );	
	}
	
	function testGet(){
		// null value
		r = cache.get( 'invalid' );
		assertTrue( isNull( r ) );
			
		testVal = {name="luis", age=32};
		cache.set( "unittestkey", testVal );
		sleep( 2 );	
		results = cache.get( 'unittestkey' );
		assertTrue( !isNull( results ) );
		assertEquals( testVal, results );
	}
	
	function testGetQuiet(){
		testGet();
	}
	
	function testExpireObject(){
		var RedisClient = cache.getObjectStore();
		// test not valid object
		cache.expireObject( "invalid" );
		// test real object
		RedisClient.set( "unitTestKey", 'Testing' );
		cache.returnToPool( RedisClient );
		cache.expireObject( "unitTestKey" );
		sleep( 2 );
		results = cache.get( 'unitTestKey' );
		assertTrue( isNull( results ) );
	}
	
	function testExpireAll(){
		var RedisClient = cache.getObjectStore();
		RedisClient.set( "unitTestKey", 'Testing' );
		cache.returnToPool( RedisClient );
		cache.expireAll();
		// no asserts, just let it run
	}
	
	function testClear(){
		var RedisClient = cache.getObjectStore();
		RedisClient.set( "unitTestKey", 'Testing' );
		r = RedisClient.del( "unitTestKey" );
		assertTrue( isNull( RedisClient.get( "unitTestKey" ) ) );
		cache.returnToPool( RedisClient );
	}
	
	function testClearQuiet(){
		testClear();
	}
	
	function testReap(){
		cache.reap();
	}
	
	function testSetQuiet(){
		// not simple value
		testVal = {name="luis", age=32};
		cache.setQuiet( 'unitTestKey', testVal );
		
		results = cache.get( "unitTestKey" );

		assertFalse( isNull( results ) );
		
		assertTrue( isStruct( results ) );
		assertTrue( results.name == 'luis' );
		
		// simple values with different cases
		results = cache.setQuiet( 'anotherKey', 'Hello Redis' );
		assertTrue( results == "OK" );
		results = cache.get( 'anotherKey' );
		assertTrue( results == 'Hello Redis' );
	}
	
	function testSet(){
		
		// test our case senstivity setting
		testVal = {name="luis", age=32};
		cache.set( 'unitTestKey', testVal );
		
		results = cache.get( "unittestkey" );
		
		assertTrue( !isNull( results ) );
		assertTrue( isStruct( results ) );
		assertTrue( (results.name=="luis") );
		
		cache.set( 'anotherKey', 'Hello Redis');
		results = cache.get( "anotherKey" );
		assertTrue( !isNull( results ), "The results returned from the cache were unexpectedly null." );
		assertTrue( results == 'Hello Redis' )
	}
	
	function testGetCachedObjectMetadata(){
		cache.set( "unittestkey", 'Test Data' );
		r = cache.getCachedObjectMetadata( 'unittestkey' );
		assertFalse( r.isExpired );
	}

	// function testgetStoreMetadataReport(){
	// 	f = variables.RedisClient.set( "unittestkey", 'Test Data' );
	// 	cache.get("unittestkey");
	// 	r = cache.getStoreMetadataReport();
	// 	assertTrue( arrayFindNoCase( structKeyArray( r ), "unittestkey" ) );
	// }
	
}