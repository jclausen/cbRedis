CHANGELOG
=========

## 1.0.0 
* Initial Module Release
## 2.0.0-alpha.1

- Modernize to Jedis 8.0.1, Java 17+ and current CacheBox interfaces.
- Add TLS trust/hostname verification, ACL usernames, bounded isolated pools,
  deterministic shutdown, Lua and atomic expiring-lease helpers.
- Replace the shared key registry and global clearing with bucket-scoped SCAN.
- Add literal, case-aware `clearByKeyPrefix`, returning the removed count.
- Store JSON data with atomic absolute/idle expiry in minutes; no object deserialization.
- Move the installable module to the repository root; replace the old JavaLoader jars.
- Add focused real Valkey and ColdBox module lifecycle contracts.
