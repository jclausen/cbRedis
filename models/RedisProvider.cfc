/**
 * CacheBox 8 provider. Cache values are JSON data, with Redis-owned absolute and
 * idle expiration in one hash. Each bucket is isolated; clearing never FLUSHDBs.
 * 2.x intentionally does not deserialize Java/CFML objects from shared Redis.
 */
component
    extends="coldbox.system.cache.AbstractCacheBoxProvider"
    implements="coldbox.system.cache.providers.ICacheProvider"
{

    function init() {
        super.init();
        variables.stats = new coldbox.system.cache.util.CacheStats(this);
        variables.elementCleaner = new coldbox.system.cache.util.ElementCleaner(this);
        return this;
    }

    function configure() {
        var config = getConfiguration();
        structAppend(
            config,
            {
                bucket: getName(),
                objectDefaultTimeout: 30,
                caseSensitiveKeys: true,
                operationGuard: '',
                connection: {}
            },
            false
        );
        if (
            !reFind('^[a-zA-Z0-9_-]{1,80}$', config.bucket) || !isNumeric(config.objectDefaultTimeout) ||
            config.objectDefaultTimeout < 0
        ) {
            throw(
                type = 'cbRedis.InvalidConfiguration',
                message = 'A safe, nonempty Redis bucket and nonnegative default timeout are required'
            );
        }
        variables.prefix = 'cbredis:' & config.bucket & ':';
        if (
            !isCustomFunction(config.operationGuard) && !(
                isSimpleValue(config.operationGuard) && config.operationGuard == ''
            )
        ) {
            throw(
                type = 'cbRedis.InvalidConfiguration',
                message = 'operationGuard must be a callback or an empty string'
            );
        }
        variables.connection = new RedisConnection(config.connection);
        try {
            variables.connection.ping();
            variables.enabled = true;
            variables.reportingEnabled = true;
        } catch (any failure) {
            variables.connection.close();
            rethrow;
        }
        return this;
    }

    function shutdown() {
        variables.enabled = false;
        if (structKeyExists(variables, 'connection')) {
            variables.connection.close();
        }
        return this;
    }

    /** Thread-safe pooled client; callers must not close it. */
    function getRedisClient() {
        return variables.connection.client();
    }

    function getObjectStore() {
        return getRedisClient();
    }

    function get(required objectKey) {
        var value = getQuiet(objectKey);
        if (isNull(value)) {
            variables.stats.miss();
            return;
        }
        variables.stats.hit();
        return value;
    }

    function getQuiet(required objectKey) {
        var result = entry(objectKey, true);
        if (!isNull(result)) {
            return deserializeJSON(result);
        }
    }

    boolean function lookup(required objectKey) {
        var found = lookupQuiet(objectKey);
        if (found) {
            variables.stats.hit();
        } else {
            variables.stats.miss();
        }
        return found;
    }

    boolean function lookupQuiet(required objectKey) {
        return !isNull(entry(objectKey, false));
    }

    boolean function isExpired(required objectKey) {
        return !lookupQuiet(objectKey);
    }

    function set(
        required objectKey,
        required object,
        timeout = '',
        lastAccessTimeout = '',
        struct extra = {}
    ) {
        setQuiet(argumentCollection = arguments);
        announce(
            'afterCacheElementInsert',
            {
                cache: this,
                cacheObject: object,
                cacheObjectKey: objectKey,
                cacheObjectTimeout: timeout,
                cacheObjectLastAccessTimeout: lastAccessTimeout
            }
        );
        return this;
    }

    function setQuiet(
        required objectKey,
        required object,
        timeout = '',
        lastAccessTimeout = '',
        struct extra = {}
    ) {
        var absolute = milliseconds(timeout, getConfiguration().objectDefaultTimeout);
        var idle = milliseconds(lastAccessTimeout, 0);
        // Server time avoids differences between application host clocks. One Lua
        // command replaces both data and expiry, including persistent overwrite.
        guardedEval(
            'local time=redis.call(''TIME'');local now=time[1]*1000+math.floor(time[2]/1000);' & 'local ttl=tonumber(ARGV[2]);local idle=tonumber(ARGV[3]);local deadline=0;' & 'if ttl>0 then deadline=now+ttl end;redis.call(''del'',KEYS[1]);' & 'redis.call(''hset'',KEYS[1],''value'',ARGV[1],''deadline'',deadline,''idle'',idle,''created'',now,''accessed'',now,''hits'',0);' & 'if idle>0 and (ttl==0 or idle<ttl) then ttl=idle end;if ttl>0 then redis.call(''pexpire'',KEYS[1],ttl) end;return 1',
            [key(objectKey)],
            [serializeJSON(object), toString(absolute), toString(idle)]
        );
        return this;
    }

    function setMulti(
        required struct mapping,
        timeout = '',
        lastAccessTimeout = '',
        prefix = ''
    ) {
        for (var name in mapping) {
            this.set(
                prefix & name,
                mapping[name],
                timeout,
                lastAccessTimeout
            );
        }
        return this;
    }

    struct function getMulti(required keys, prefix = '') {
        var result = {};
        for (var name in isArray(keys) ? keys : listToArray(keys)) {
            result[prefix & name] = this.get(prefix & name);
        }
        return result;
    }

    array function getKeys() {
        return scanKeys('');
    }

    private array function scanKeys(required string keyPrefix) {
        var found = createObject('java', 'java.util.LinkedHashSet').init();
        var cursor = '0';
        var params = javaClass('redis.clients.jedis.params.ScanParams')
            .init()
            .match(variables.prefix & literalPattern(keyPrefix) & '*')
            .count(javacast('int', 200));
        do {
            var page = getRedisClient().scan(cursor, params);
            cursor = page.getCursor();
            for (var name in page.getResult()) {
                found.add(removeChars(name, 1, len(variables.prefix)));
            }
        } while (cursor != '0');
        var result = [];
        for (var name in found) {
            arrayAppend(result, name);
        }
        return result;
    }

    numeric function getSize() {
        return arrayLen(getKeys());
    }

    /** Literal, case-aware prefix. An empty prefix must use explicit clearAll(). */
    numeric function clearByKeyPrefix(required string keyPrefix) {
        if (!len(keyPrefix)) {
            throw(type = 'cbRedis.InvalidKey', message = 'A nonempty cache key prefix is required');
        }
        var prefix = getConfiguration().caseSensitiveKeys ? keyPrefix : lCase(keyPrefix);
        var count = 0;
        for (var name in scanKeys(prefix)) {
            if (compare(left(name, len(prefix)), prefix) == 0 && clear(name)) {
                count++;
            }
        }
        return count;
    }

    private string function literalPattern(required string value) {
        var pattern = '';
        for (var index = 1; index <= len(value); index++) {
            var character = mid(value, index, 1);
            if (find(character, '\*?[]')) {
                pattern &= '\';
            }
            pattern &= character;
        }
        return pattern;
    }

    boolean function clearQuiet(required objectKey) {
        return guardedEval('return redis.call(''del'',KEYS[1])', [key(objectKey)], []) >
        0;
    }

    boolean function clear(required objectKey) {
        var removed = clearQuiet(objectKey);
        if (removed) {
            announce('afterCacheElementRemoved', {cache: this, cacheObjectKey: objectKey});
        }
        return removed;
    }

    function clearAll() {
        for (var name in getKeys()) {
            clearQuiet(name);
        }
        announce('afterCacheClearAll', {cache: this});
        return this;
    }

    function expireAll() {
        return clearAll();
    }

    function expireObject(required objectKey) {
        clear(objectKey);
        return this;
    }

    function reap() {
        variables.stats.setLastReapDatetime(now());
        return this;
    }

    function clearByKeySnippet(required keySnippet, boolean regex = false, boolean async = false) {
        // Scanning is synchronous. No background thread can outlive its owner.
        variables.elementCleaner.clearByKeySnippet(keySnippet, regex);
        return this;
    }

    struct function getCachedObjectMetadata(required objectKey) {
        var data = getRedisClient().hgetAll(key(objectKey));
        if (data.isEmpty()) {
            return {};
        }
        return {
            timeout: val(data.get('deadline')) > 0
             ? (val(data.get('deadline')) - val(data.get('created'))) / 60000
             : 0,
            lastAccessTimeout: val(data.get('idle')) / 60000,
            hits: val(data.get('hits')),
            created: val(data.get('created')),
            lastAccessed: val(data.get('accessed')),
            isExpired: false
        };
    }

    struct function getStoreMetadataReport() {
        var report = {};
        for (var name in getKeys()) {
            report[name] = getCachedObjectMetadata(name);
        }
        return report;
    }

    struct function getStoreMetadataKeyMap() {
        return {
            timeout: 'timeout',
            lastAccessTimeout: 'lastAccessTimeout',
            hits: 'hits',
            created: 'created',
            lastAccessed: 'lastAccessed',
            isExpired: 'isExpired'
        };
    }

    /** Fence data reads/writes against a lease in the same Redis command; stale owners cannot mutate data. */
    private function guardedEval(required string script, required array keys, required array args) {
        var config = getConfiguration();
        if (!isCustomFunction(config.operationGuard)) {
            return variables.connection.eval(argumentCollection = arguments);
        }
        var guard = config.operationGuard();
        if (
            !isStruct(guard) || !isSimpleValue(guard.key ?: {}) || !len(guard.key ?: '') || len(guard.key) > 512 ||
            !isSimpleValue(guard.token ?: {}) || !len(guard.token ?: '') || len(guard.token) > 256 ||
            !isNumeric(guard.milliseconds ?: '') || guard.milliseconds != fix(guard.milliseconds) || guard.milliseconds < 1 || guard.milliseconds > 3600000
        ) {
            throw(type = 'cbRedis.InvalidGuard', message = 'A valid Redis lease guard is required');
        }
        var guardedKeys = duplicate(arguments.keys);
        var guardedArgs = duplicate(arguments.args);
        guardedKeys.append(guard.key);
        guardedArgs.append(guard.token);
        guardedArgs.append(toString(guard.milliseconds));
        var keyIndex = guardedKeys.len();
        var tokenIndex = guardedArgs.len() - 1;
        var renewalIndex = guardedArgs.len();
        return variables.connection.eval(
            'if redis.call(''get'',KEYS[' & keyIndex & '])~=ARGV[' & tokenIndex & '] then return redis.error_reply(''LOCK_OWNERSHIP_LOST'') end;redis.call(''pexpire'',KEYS[' & keyIndex & '],ARGV[' & renewalIndex & ']);' & arguments.script,
            guardedKeys,
            guardedArgs
        );
    }

    private function entry(required string objectKey, required boolean touch) {
        return guardedEval(
            'if redis.call(''exists'',KEYS[1])==0 then return nil end;' & 'local time=redis.call(''TIME'');local now=time[1]*1000+math.floor(time[2]/1000);' & 'local deadline=tonumber(redis.call(''hget'',KEYS[1],''deadline''));if deadline>0 and deadline<=now then redis.call(''del'',KEYS[1]);return nil end;' & 'if ARGV[1]==''1'' then local idle=tonumber(redis.call(''hget'',KEYS[1],''idle''));if idle>0 then local ttl=idle;' & 'if deadline>0 then ttl=math.min(ttl,deadline-now) end;redis.call(''pexpire'',KEYS[1],ttl) end;' & 'redis.call(''hset'',KEYS[1],''accessed'',now);redis.call(''hincrby'',KEYS[1],''hits'',1) end;return redis.call(''hget'',KEYS[1],''value'')',
            [key(objectKey)],
            [touch ? '1' : '0']
        );
    }

    private function key(required string name) {
        if (!len(name) || len(name) > 1024) {
            throw(type = 'cbRedis.InvalidKey', message = 'Invalid cache key');
        }
        return variables.prefix & (getConfiguration().caseSensitiveKeys ? name : lCase(name));
    }

    private numeric function milliseconds(required any value, required numeric fallback) {
        var minutes = isSimpleValue(value) && value == '' ? fallback : value;
        if (!isNumeric(minutes) || minutes < 0 || minutes > 525600) {
            throw(type = 'cbRedis.InvalidTimeout', message = 'Cache timeouts are nonnegative minutes, at most one year');
        }
        return ceiling(minutes * 60000);
    }

    private function javaClass(name) {
        return createObject(
            'java',
            name,
            directoryList(
                getDirectoryFromPath(getCurrentTemplatePath()) & '../lib',
                false,
                'path',
                '*.jar'
            )
        );
    }

    private function announce(name, data) {
        if (isObject(variables.eventManager)) {
            variables.eventManager.announce(name, data);
        }
    }

}
