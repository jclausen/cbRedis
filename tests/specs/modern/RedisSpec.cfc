component extends="testbox.system.BaseSpec" {

    function run() {
        describe('Modern Redis/Valkey contracts', () => {
            beforeEach(() => {
                variables.connections = [];
                variables.providers = [];
                variables.prefix = 'fixture:' & replace(createUUID(), '-', '', 'all') & ':';
            });
            afterEach(() => {
                for (var provider in variables.providers) {
                    provider.clearAll();
                    provider.shutdown();
                }
                for (var connection in variables.connections) {
                    connection.close();
                }
            });
            it('authenticates with ACL username and password, with separate pools', () => {
                var first = connection();
                var second = connection();
                expect(first.ping()).toBeTrue();
                first.close();
                expect(second.ping()).toBeTrue();
                expect(() => first.client()).toThrow('cbRedis.Closed');
                expect(() => connection({password: 'wrong'}).ping()).toThrow('cbRedis.ConnectionUnavailable');
            });
            it('fences cache reads, replacements and deletion against a lost lease', () => {
                var raw = connection();
                var leaseKey = variables.prefix & 'guard';
                var owner = {token: 'first-owner'};
                raw.setIfAbsent(leaseKey, owner.token, 10000);
                var cache = provider(
                    overrides = {
                        operationGuard: () => {
                            return {key: leaseKey, token: owner.token, milliseconds: 10000};
                        }
                    }
                );
                try {
                    cache.set('protected', {value: 1});
                    expect(cache.get('protected').value).toBe(1);
                    raw.eval('redis.call(''set'',KEYS[1],ARGV[1],''PX'',10000);return 1', [leaseKey], ['next-owner']);
                    expect(() => cache.set('protected', {value: 999})).toThrow('cbRedis.OperationFailed');
                    expect(() => cache.clear('protected')).toThrow('cbRedis.OperationFailed');
                    expect(() => cache.get('protected')).toThrow('cbRedis.OperationFailed');
                    owner.token = 'next-owner';
                    expect(cache.get('protected').value).toBe(1);
                    expect(cache.clear('protected')).toBeTrue();
                } finally {
                    cache.getConfiguration().operationGuard = '';
                    raw.eval('return redis.call(''del'',KEYS[1])', [leaseKey], []);
                }
            });
            it('fails closed when a configured guard is missing or its callback fails', () => {
                var cache = provider(
                    overrides = {
                        operationGuard: () => {
                            return {};
                        }
                    }
                );
                try {
                    expect(() => cache.set('unsafe', 1)).toThrow('cbRedis.InvalidGuard');
                    cache.getConfiguration().operationGuard = () => {
                        throw(type = 'Fixture.GuardUnavailable');
                    };
                    expect(() => cache.get('unsafe')).toThrow('Fixture.GuardUnavailable');
                } finally {
                    cache.getConfiguration().operationGuard = '';
                }
            });
            it('verifies TLS trust and hostname, rejecting missing trust and a mismatched host', () => {
                var config = {port: request.cbRedisFixture.tlsPort, tls: true, caFile: request.cbRedisFixture.caFile};
                expect(connection(config).ping()).toBeTrue();
                config.caFile = request.cbRedisFixture.wrongCaFile;
                expect(() => connection(config).ping()).toThrow('cbRedis.ConnectionUnavailable');
                config.caFile = request.cbRedisFixture.caFile;
                config.host = '127.0.0.1';
                expect(() => connection(config).ping()).toThrow('cbRedis.ConnectionUnavailable');
            });
            it('rejects invalid numeric settings and credential-bearing URLs without printing credentials', () => {
                expect(() => connection({maxConnections: 0}).client()).toThrow('cbRedis.InvalidConfiguration');
                expect(() => connection({port: '6379junk'}).client()).toThrow('cbRedis.InvalidConfiguration');
                expect(() => connection({host: 'redis://user:secret@localhost'}).client()).toThrow('cbRedis.InvalidConfiguration');
                try {
                    connection({password: 'sensitive-fixture-value'}).ping();
                } catch (any failure) {
                    expect(failure.message & failure.detail).notToInclude('sensitive-fixture-value');
                }
            });
            it('acquires atomic expiring leases and cannot release another owner''s lease', () => {
                var first = connection();
                var second = connection();
                var name = variables.prefix & 'lease';
                expect(first.setIfAbsent(name, 'owner-one', 200)).toBeTrue();
                expect(second.setIfAbsent(name, 'owner-two', 200)).toBeFalse();
                expect(
                    second.eval(
                        'if redis.call(''get'',KEYS[1])==ARGV[1] then return redis.call(''del'',KEYS[1]) end return 0',
                        [name],
                        ['owner-two']
                    )
                ).toBe(0);
                sleep(300);
                expect(second.setIfAbsent(name, 'owner-two', 200)).toBeTrue();
                second.client().del(name);
            });
            it('implements the CacheBox 8 interface and round trips JSON, falsy values and multi operations', () => {
                var cache = provider();
                expect(isInstanceOf(cache, 'coldbox.system.cache.providers.ICacheProvider')).toBeTrue();
                cache.set('complex', {nested: [1, 'two', false]});
                cache.set('false', false);
                cache.set('zero', 0);
                cache.set('empty', '');
                expect(cache.get('complex').nested[2]).toBe('two');
                expect(cache.get('false')).toBeFalse();
                expect(cache.get('zero')).toBe(0);
                expect(cache.get('empty')).toBe('');
                expect(isNull(cache.get('missing'))).toBeTrue();
                cache.setMulti({'one': 1, 'two': 2}, 1);
                expect(cache.get('two')).toBe(2);
                expect(cache.getMulti(['one', 'two']).two).toBe(2);
                expect(cache.getStats().getHits()).toBeGTE(4);
            });
            it('isolates namespace clearing and scans more than one batch without a global key registry', () => {
                var first = provider();
                var second = provider();
                for (var i = 1; i <= 251; i++) {
                    first.setQuiet('key-' & i, i);
                }
                second.set('survivor', 'other bucket');
                var native = connection();
                native.client().set(variables.prefix & 'unrelated', 'external');
                try {
                    expect(first.getSize()).toBe(251);
                    first.clearAll();
                    expect(first.getSize()).toBe(0);
                    expect(second.get('survivor')).toBe('other bucket');
                    expect(native.client().get(variables.prefix & 'unrelated')).toBe('external');
                } finally {
                    native.client().del(variables.prefix & 'unrelated');
                }
            });
            it('clears a literal prefix without matching snippets, glob patterns or other buckets', () => {
                var cache = provider();
                var other = provider();
                cache.set('show:one', 1);
                cache.set('show:two', 2);
                cache.set('Show:one', 3);
                cache.set('archived:show:one', 4);
                cache.set('show:*[literal]', 5);
                other.set('show:one', 6);
                expect(cache.clearByKeyPrefix('show:*[')).toBe(1);
                expect(cache.clearByKeyPrefix('show:')).toBe(2);
                expect(cache.get('Show:one')).toBe(3);
                expect(cache.get('archived:show:one')).toBe(4);
                expect(other.get('show:one')).toBe(6);
                expect(() => cache.clearByKeyPrefix('')).toThrow('cbRedis.InvalidKey');
                var insensitive = provider(false, {caseSensitiveKeys: false});
                insensitive.set('Show:One', 7);
                expect(insensitive.clearByKeyPrefix('SHOW:')).toBe(1);
            });
            it('uses minutes for both single and multi expiry, preserves persistence and caps idle refresh at the absolute deadline', () => {
                var cache = provider();
                cache.set('absolute', 'value', .01, .005);
                cache.setMulti({'multi': 1}, .005);
                expect(cache.get('multi')).toBe(1);
                cache.set('permanent', 'value', 0);
                sleep(200);
                expect(cache.get('absolute')).toBe('value');
                sleep(200);
                expect(cache.get('absolute')).toBe('value');
                expect(cache.lookup('multi')).toBeFalse();
                sleep(250);
                expect(cache.lookup('absolute')).toBeFalse();
                expect(cache.get('permanent')).toBe('value');
                expect(cache.getRedisClient().pttl('cbredis:' & cache.getConfiguration().bucket & ':permanent')).toBe(
                    -1
                );
                expect(() => cache.set('bad', 1, -1)).toThrow('cbRedis.InvalidTimeout');
            });
            it('provides ColdBox view/event prefixes and synchronous scoped invalidation', () => {
                var cache = provider(true);
                expect(isInstanceOf(cache, 'coldbox.system.cache.providers.IColdBoxProvider')).toBeTrue();
                cache.set(cache.getViewCacheKeyPrefix() & 'show-123', 'view');
                cache.set('other', 'value');
                cache.clearAllViews();
                expect(cache.getSize()).toBe(1);
                expect(cache.get('other')).toBe('value');
            });
        });
    }

    private function configuration() {
        return {
            host: 'localhost',
            port: request.cbRedisFixture.port,
            username: 'fixture',
            password: 'cbredis-fixture-password',
            tls: false
        };
    }

    private function connection(struct overrides = {}) {
        var config = configuration();
        structAppend(config, overrides, true);
        var result = new cbRedis.models.RedisConnection(config);
        arrayAppend(variables.connections, result);
        return result;
    }

    private function provider(boolean coldbox = false, struct overrides = {}) {
        var result = coldbox ? new cbRedis.models.RedisColdboxProvider() : new cbRedis.models.RedisProvider();
        result.setName('fixture' & replace(createUUID(), '-', '', 'all'));
        var config = {connection: configuration()};
        structAppend(config, overrides, true);
        result.setConfiguration(config);
        result.configure();
        arrayAppend(variables.providers, result);
        return result;
    }

}
