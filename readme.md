# cbRedis 2 (alpha)

Redis and Valkey connections with verified TLS, ACL authentication and isolated
bounded Jedis pools, plus CacheBox 8 providers. Requires Java 17+, ColdBox 8+,
BoxLang with CFML compatibility or Lucee 6+. Adobe ColdFusion is unverified.

This is a breaking modernization of the 2016 provider. The repository root is
now the installable module. The old application/workbench and legacy tests are
historical fixtures, excluded from the package. Do not run their build or Travis
configuration for 2.x.

## Connection

CacheBox regions can optionally configure `operationGuard` as a synchronous
callback returning `{ key, token, milliseconds }` for a Redis lease owned by the
current operation. Data reads, replacement and deletion atomically check the
lease token and renew its expiry in the same Lua command as the data operation.
A missing/invalid guard or lost ownership fails closed; stale owners cannot
overwrite or delete newer data after their lease expires.

This hook does not acquire/release locks, sign cookies, or provide cross-system
transactions. The caller must acquire the shared lease before invoking storage
and release it with an owner-token check in `finally`. `milliseconds` is an
integer from 1 through 3,600,000. The callback must return the request's actual
lease; it must not silently acquire a replacement lease for a stale operation.
Raw `getRedisClient()` access bypasses this guard. Redis Cluster remains unsupported.

Configure `moduleSettings.cbRedis.connection` in ColdBox (or return the same
structure from `config/modules/cbRedis.cfc`):

```cfml
cbRedis = { connection = {
    host = getSystemSetting( "REDIS_HOST" ),
    port = getSystemSetting( "REDIS_PORT", "6379" ),
    username = getSystemSetting( "REDIS_USER", "default" ),
    password = getSystemSetting( "REDIS_PASSWORD" ),
    tls = true,
    caFile = getSystemSetting( "REDIS_CA_FILE", "" ),
    database = 0,
    maxConnections = 8,
    connectionTimeoutMillis = 3000,
    socketTimeoutMillis = 3000,
    poolWaitMillis = 3000
} }
```

Inject `RedisConnection@cbRedis`. `ping()` checks the endpoint. `client()` exposes
the thread-safe Jedis `RedisClient`; its commands borrow and return pooled
connections internally. Do not close this shared client. Module unload closes
its existing singleton without creating a new connection. Manually constructed
`new cbRedis.models.RedisConnection(config)` objects each own a separate pool;
their caller must `close()` them. Close is terminal and idempotent.

TLS defaults on. An empty `caFile` uses the JVM trust store; a supplied PEM bundle
creates a trust store containing those certificates. Both paths verify the server
hostname. There is no trust-all switch. Use `tls=false` explicitly only for a
trusted local fixture or a deliberately unencrypted endpoint. Credentials belong
in secret settings, never URLs or logs. Wrapper errors omit credentials; do not
log raw configuration or unfiltered native-client exceptions.

`eval(script, keys, args)` handles cross-engine Java List conversion and returns
Jedis results. `setIfAbsent(key, value, milliseconds)` atomically acquires an
expiring lease and returns a boolean. Release and mutation scripts must compare
the owner's token; a lease alone is not a distributed transaction or fencing
mechanism. Multi-key Lua on a cluster must use a common hash tag. This connection
supports a single endpoint, not Sentinel or client-managed cluster topology.

## CacheBox

Use provider `cbRedis.models.RedisProvider`, or
`cbRedis.models.RedisColdboxProvider` for ColdBox event/view caching:

```cfml
properties = {
    bucket = "my_app_cache_v2",
    connection = { host = "cache.example.com", port = 6379, tls = true },
    objectDefaultTimeout = 30,
    caseSensitiveKeys = true
}
```

A nonempty bucket isolates every key under `cbredis:<bucket>:`. Specify a unique
bucket for each application/provider/environment. Authentication/TLS options go
inside `connection`. Old `server`, global pool and JavaLoader settings are not
supported. Pools close independently when providers shut down.

Values must be JSON-compatible data; 2.x does not deserialize CFML/Java objects.
Old cached data is not reused. Timeouts are minutes for both `set` and `setMulti`;
zero means no absolute expiration. Idle expiration refreshes on reads and never
extends the absolute deadline. Both are enforced using Redis server time and one
atomic Lua command. Quote mapping keys when using case-sensitive keys: CFML may
uppercase unquoted struct keys. Runtime statistics are local to each provider.

```cfml
cache.set( "production:42:cast", castData, 10 )
removed = cache.clearByKeyPrefix( "production:42:" )
```

`clearByKeyPrefix` returns the number deleted. The prefix is literal, anchored
and respects the provider's case policy. Redis glob characters are escaped. An
empty prefix is rejected; use `clearAll()` explicitly. Clearing uses cursor-based
`SCAN MATCH`, never `KEYS` or `FLUSHDB`, and touches only the provider bucket.
`clearByKeySnippet` retains substring/regex matching for framework cleaners.
Invalidation is synchronous and is not a snapshot transaction: concurrent writes
can recreate entries during or after a clear. Version namespaces or coordinate
writers when stronger guarantees are needed.

## Build and focused verification

`lib/` contains the exact runtime jars so installing an immutable Git commit does
not require Maven or a network download at application startup. `pom.xml` declares
the source dependency versions; `lib/SHA256SUMS` records the shipped bytes.
Rebuild with `mvn --batch-mode package` and verify with
`shasum -a 256 -c lib/SHA256SUMS`. Remove obsolete jars deliberately when updating.

Install development dependencies with `box install`. Use only an owned local
Redis/Valkey fixture with ACL user `fixture`, password `cbredis-fixture-password`,
and distinct ephemeral localhost plaintext/TLS ports. Generate a private fixture
CA, a server certificate for `DNS:localhost`, and a second unrelated CA. Then:

```text
box task run taskFile=tasks/Test :port=32774 :tlsPort=32775 :caFile=/absolute/fixture/ca.crt :wrongCaFile=/absolute/fixture/wrong.crt
```

The focused suite covers ACL authentication, certificate/hostname rejection,
independent pool shutdown, finite leases, CacheBox interfaces, JSON/falsy values,
multi operations, namespace and prefix clearing, expiry, event/view clearing,
and real ColdBox module settings/unload. It never connects to production.
Hosted-provider, Adobe and production application behavior require separate
verification. No infrastructure is provisioned or deployed by these tests.

For the native BoxLang CLI contracts, set `CBREDIS_TEST_PORT`,
`CBREDIS_TEST_TLS_PORT`, `CBREDIS_TEST_CA_FILE`, and
`CBREDIS_TEST_WRONG_CA_FILE`, then run:

```text
boxlang --bx-config tests/boxlang.json tasks/Test.bxs
```

This runs the nine connection/cache contracts. The real module lifecycle contract
runs through CommandBox's web-compatible scopes; native CLI lacks CGI scope.
Actual BoxLang application HTTP integration remains a separate pending check.
