# Generic Cache Infrastructure

## Overview

This document describes the generic cache infrastructure (`ExpiringCache`) that provides a reusable foundation for all caching needs in AeroSpork.

## Files

- **ExpiringCache.swift** - Generic cache implementation with time-based expiration and LRU eviction

## Design Decisions

### 1. Generic Type Parameters

The cache is generic over `Key` and `Value` types:
```swift
class ExpiringCache<Key: Hashable, Value>
```

- **Key**: Must be `Hashable` for dictionary-based storage
- **Value**: No constraints for maximum flexibility

### 2. Dual Implementation Strategy

Two implementations are provided:

#### ExpiringCache (Class)
- Non-thread-safe, fast access
- Use for `@MainActor` contexts (LayoutMemoizer, WindowPropertyCache)
- Zero async overhead
- Direct property access

#### ExpiringCacheActor (Actor)
- Thread-safe via Swift concurrency
- Use for cross-actor sharing (LayoutCache)
- All methods are async
- Wraps ExpiringCache internally

### 3. Time-Based Expiration

Each cache entry tracks:
- `timestamp`: Creation time
- `timeout`: Configurable per-cache instance

Entries automatically expire when `Date() - timestamp > timeout`.

### 4. LRU Eviction Strategy

When cache reaches `maxSize`:
- Tracks `accessCount` per entry
- Evicts entry with lowest access count
- Access count incremented on each `get()`

This balances recency with frequency of use.

### 5. Statistics Tracking

Built-in metrics for performance monitoring:
- `hitCount`: Successful cache retrievals
- `missCount`: Cache misses
- `hitRate`: Computed as `hitCount / (hitCount + missCount)`
- `expiredCount`: Number of expired entries still in cache

### 6. Flexible Removal

Multiple removal strategies:
- `remove(key)`: Remove single entry
- `removeWhere(predicate)`: Remove entries matching condition
- `cleanupExpired()`: Remove all expired entries
- `clear()`: Remove everything and reset stats

## Usage Examples

### Basic Usage (Main Actor)

```swift
@MainActor
class MyCache {
    private let cache = ExpiringCache<String, MyValue>(
        timeout: 30.0,  // 30 seconds
        maxSize: 100    // Max 100 entries
    )

    func getValue(key: String) -> MyValue? {
        if let cached = cache.get(key) {
            return cached
        }

        // Compute value...
        let value = computeExpensiveValue(key)
        cache.set(key, value: value)
        return value
    }
}
```

### Thread-Safe Usage (Actor)

```swift
actor MySharedCache {
    private let cache = ExpiringCacheActor<String, MyValue>(
        timeout: 5.0,
        maxSize: 50
    )

    func getValue(key: String) async -> MyValue? {
        if let cached = await cache.get(key) {
            return cached
        }

        let value = await computeExpensiveValue(key)
        await cache.set(key, value: value)
        return value
    }
}
```

### Pattern-Based Invalidation

```swift
// Remove all entries for a specific workspace
cache.removeWhere { key, _ in
    key.hasPrefix("workspace-1")
}

// Remove entries matching complex criteria
cache.removeWhere { key, value in
    value.isStale || key.contains("temp")
}
```

### Periodic Cleanup

```swift
Task {
    while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(60))
        let cleaned = await cache.cleanupExpired()
        print("Cleaned \(cleaned) expired entries")
    }
}
```

### Statistics Monitoring

```swift
// For class-based cache
let stats = CacheStatisticsSnapshot(
    hitCount: cache.hitCount,
    missCount: cache.missCount,
    hitRate: cache.hitRate,
    entryCount: cache.count,
    expiredCount: cache.expiredCount
)

// For actor-based cache
let stats = await cache.getStatistics()
print("Hit rate: \(stats.hitRate * 100)%")
print("Efficiency: \(stats.efficiency * 100)%")
```

## Migration Guide

### From WindowPropertyCache

**Before:**
```swift
private var stableCache: [UInt32: CachedProperties] = [:]
private var volatileCache: [UInt32: VolatileProperties] = [:]
```

**After:**
```swift
private let stableCache = ExpiringCache<UInt32, CachedProperties>(
    timeout: 5.0,
    maxSize: 1000
)
private let volatileCache = ExpiringCache<UInt32, VolatileProperties>(
    timeout: 0.5,
    maxSize: 1000
)
```

### From LayoutMemoizer

**Before:**
```swift
private var memoCache: [LayoutFingerprint: MemoizedLayout] = [:]

func getMemoizedLayout(for fingerprint: LayoutFingerprint) -> LayoutResult? {
    guard let memoized = memoCache[fingerprint], !memoized.isExpired else {
        memoCache.removeValue(forKey: fingerprint)
        return nil
    }
    memoCache[fingerprint] = memoized.withIncrementedAccess()
    return memoized.result
}
```

**After:**
```swift
private let cache = ExpiringCache<LayoutFingerprint, LayoutResult>(
    timeout: 30.0,
    maxSize: config.performanceConfig.layoutCacheSize
)

func getMemoizedLayout(for fingerprint: LayoutFingerprint) -> LayoutResult? {
    cache.get(fingerprint)  // Handles expiration, access tracking automatically
}
```

### From LayoutCache (Actor)

**Before:**
```swift
actor LayoutCache {
    private var cache: [String: CachedLayout] = [:]

    func getCachedLayout(for layoutId: String) -> LayoutResult? {
        guard let cached = cache[layoutId], !cached.isExpired else {
            cache.removeValue(forKey: layoutId)
            return nil
        }
        cache[layoutId] = cached.withIncrementedAccess()
        return cached.result
    }
}
```

**After:**
```swift
actor LayoutCache {
    private let cache = ExpiringCacheActor<String, LayoutResult>(
        timeout: 30.0,
        maxSize: 100
    )

    func getCachedLayout(for layoutId: String) async -> LayoutResult? {
        await cache.get(layoutId)
    }
}
```

## Performance Characteristics

### Time Complexity

| Operation | Best Case | Average Case | Worst Case |
|-----------|-----------|--------------|------------|
| get()     | O(1)      | O(1)         | O(1)       |
| set()     | O(1)      | O(1)         | O(n)*      |
| remove()  | O(1)      | O(1)         | O(1)       |
| cleanupExpired() | O(n) | O(n)     | O(n)       |
| removeWhere() | O(n)    | O(n)         | O(n)       |

\* When eviction is needed, O(n) to find LRU entry

### Space Complexity

- O(n) where n = number of cached entries
- Bounded by `maxSize` parameter
- Additional O(1) per entry for metadata (timestamp, accessCount)

### Memory Usage

Each entry stores:
- Key (variable size)
- Value (variable size)
- Date (8 bytes)
- Int (8 bytes)
- Total overhead: ~16 bytes + key/value sizes

## Thread Safety

### ExpiringCache (Class)
- **NOT thread-safe**
- Must be used from a single actor/thread
- Typical use: `@MainActor` contexts

### ExpiringCacheActor (Actor)
- **Thread-safe** via actor isolation
- Safe to call from any actor/thread
- All methods are async
- Typical use: shared state across multiple actors

## Testing

Comprehensive test suite in `ExpiringCacheTests.swift`:

- Basic get/set operations
- Expiration behavior
- LRU eviction
- Cleanup operations
- Hit rate calculation
- Pattern-based removal
- Actor concurrency
- Statistics snapshots

Run tests:
```bash
swift test --filter ExpiringCacheTests
swift test --filter ExpiringCacheActorTests
```

## Future Enhancements

Potential improvements for future iterations:

1. **TTL per entry**: Allow different timeouts per entry
2. **Size-based eviction**: Evict based on memory size, not count
3. **Write-through caching**: Automatic persistence layer
4. **Async values**: Support async value computation within cache
5. **Multi-tier caching**: L1/L2 cache hierarchy
6. **Metrics export**: Integration with system monitoring
7. **Compression**: Automatic value compression for large values
8. **Serialization**: Disk persistence for cache warmup

## Related Files

- `/Users/billy/git/aerospork/Sources/AppBundle/cache/LayoutMemoizer.swift` - To be migrated
- `/Users/billy/git/aerospork/Sources/AppBundle/cache/WindowPropertyCache.swift` - To be migrated
- `/Users/billy/git/aerospork/Sources/AppBundle/layout/LayoutCache.swift` - To be migrated
- `/Users/billy/git/aerospork/Sources/AppBundleTests/ExpiringCacheTests.swift` - Test suite
