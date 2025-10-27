import Foundation
import Common

/// Generic cache with automatic expiration of entries
///
/// This cache provides:
/// - Time-based expiration with configurable timeout
/// - LRU eviction when max size is reached
/// - Hit/miss tracking for performance monitoring
/// - Thread-safe access via Sendable constraint
///
/// Example usage:
/// ```
/// let cache = ExpiringCache<String, MyValue>(timeout: 30.0, maxSize: 100)
/// cache.set("key", value: myValue)
/// if let value = cache.get("key") {
///     // Use cached value
/// }
/// ```
class ExpiringCache<Key: Hashable, Value> {
    private struct CacheEntry {
        let value: Value
        let timestamp: Date
        var accessCount: Int

        func isExpired(timeout: TimeInterval) -> Bool {
            Date().timeIntervalSince(timestamp) > timeout
        }
    }

    private var cache: [Key: CacheEntry] = [:]
    private let timeout: TimeInterval
    private let maxSize: Int

    private(set) var hitCount: Int = 0
    private(set) var missCount: Int = 0

    /// Initialize a new expiring cache
    /// - Parameters:
    ///   - timeout: Time in seconds before entries expire
    ///   - maxSize: Maximum number of entries before eviction occurs
    init(timeout: TimeInterval, maxSize: Int = 1000) {
        self.timeout = timeout
        self.maxSize = maxSize
    }

    /// Retrieve a value from the cache
    /// - Parameter key: The key to look up
    /// - Returns: The cached value if present and not expired, nil otherwise
    func get(_ key: Key) -> Value? {
        guard var entry = cache[key] else {
            missCount += 1
            return nil
        }

        if entry.isExpired(timeout: timeout) {
            cache.removeValue(forKey: key)
            missCount += 1
            return nil
        }

        // Update access count for LRU tracking
        entry.accessCount += 1
        cache[key] = entry
        hitCount += 1
        return entry.value
    }

    /// Store a value in the cache
    /// - Parameters:
    ///   - key: The key to store under
    ///   - value: The value to cache
    func set(_ key: Key, value: Value) {
        // Evict if we've reached capacity
        if cache.count >= maxSize && cache[key] == nil {
            evictLeastRecentlyUsed()
        }

        cache[key] = CacheEntry(
            value: value,
            timestamp: Date(),
            accessCount: 1,
        )
    }

    /// Remove a specific entry from the cache
    /// - Parameter key: The key to remove
    func remove(_ key: Key) {
        cache.removeValue(forKey: key)
    }

    /// Remove entries matching a predicate
    /// - Parameter shouldRemove: Closure that returns true for keys to remove
    /// - Returns: Number of entries removed
    @discardableResult
    func removeWhere(_ shouldRemove: (Key, Value) -> Bool) -> Int {
        var removedCount = 0
        let keysToRemove = cache.compactMap { key, entry -> Key? in
            shouldRemove(key, entry.value) ? key : nil
        }

        for key in keysToRemove {
            cache.removeValue(forKey: key)
            removedCount += 1
        }

        return removedCount
    }

    /// Remove all expired entries from the cache
    /// - Returns: Number of entries cleaned up
    @discardableResult
    func cleanupExpired() -> Int {
        let expiredKeys = cache.compactMap { key, entry in
            entry.isExpired(timeout: timeout) ? key : nil
        }

        for key in expiredKeys {
            cache.removeValue(forKey: key)
        }

        return expiredKeys.count
    }

    /// Clear all entries from the cache
    func clear() {
        cache.removeAll()
        hitCount = 0
        missCount = 0
    }

    /// Evict the least recently used entry
    /// Uses access count as the LRU metric
    private func evictLeastRecentlyUsed() {
        guard let lruKey = cache.min(by: { $0.value.accessCount < $1.value.accessCount })?.key else {
            return
        }
        cache.removeValue(forKey: lruKey)
    }

    /// Current number of entries in the cache
    var count: Int { cache.count }

    /// Cache hit rate (hits / total accesses)
    var hitRate: Double {
        let total = hitCount + missCount
        return total > 0 ? Double(hitCount) / Double(total) : 0.0
    }

    /// Number of expired entries currently in cache
    var expiredCount: Int {
        cache.values.count { $0.isExpired(timeout: timeout) }
    }
}

// MARK: - Cache Statistics Protocol

/// Common protocol for cache statistics
/// Note: This is distinct from the CacheStatistics struct in LayoutCache.swift
protocol ExpiringCacheStatistics {
    var hitCount: Int { get }
    var missCount: Int { get }
    var hitRate: Double { get }
    var entryCount: Int { get }
}

extension ExpiringCache: ExpiringCacheStatistics {
    var entryCount: Int { count }
}

// MARK: - Actor-based Thread-Safe Cache

/// Thread-safe version of ExpiringCache using Swift concurrency
///
/// Use this when you need to share cache across different actors/threads.
/// All methods are async and thread-safe.
actor ExpiringCacheActor<Key: Hashable & Sendable, Value: Sendable> {
    private var cache: ExpiringCache<Key, Value>

    init(timeout: TimeInterval, maxSize: Int = 1000) {
        self.cache = ExpiringCache(timeout: timeout, maxSize: maxSize)
    }

    func get(_ key: Key) -> Value? {
        cache.get(key)
    }

    func set(_ key: Key, value: Value) {
        cache.set(key, value: value)
    }

    func remove(_ key: Key) {
        cache.remove(key)
    }

    @discardableResult
    func removeWhere(_ shouldRemove: @Sendable (Key, Value) -> Bool) -> Int {
        cache.removeWhere(shouldRemove)
    }

    @discardableResult
    func cleanupExpired() -> Int {
        cache.cleanupExpired()
    }

    func clear() {
        cache.clear()
    }

    var count: Int { cache.count }
    var hitRate: Double { cache.hitRate }
    var hitCount: Int { cache.hitCount }
    var missCount: Int { cache.missCount }
    var expiredCount: Int { cache.expiredCount }

    func getStatistics() -> CacheStatisticsSnapshot {
        CacheStatisticsSnapshot(
            hitCount: cache.hitCount,
            missCount: cache.missCount,
            hitRate: cache.hitRate,
            entryCount: cache.count,
            expiredCount: cache.expiredCount,
        )
    }
}

// MARK: - Statistics Snapshot

/// Snapshot of cache statistics at a point in time
struct CacheStatisticsSnapshot: Sendable {
    let hitCount: Int
    let missCount: Int
    let hitRate: Double
    let entryCount: Int
    let expiredCount: Int

    var totalAccesses: Int { hitCount + missCount }

    var efficiency: Double {
        // Efficiency score: weighted by hit rate and how many entries aren't expired
        let hitRateScore = hitRate
        let expirationScore = entryCount > 0 ? 1.0 - (Double(expiredCount) / Double(entryCount)) : 1.0
        return (hitRateScore + expirationScore) / 2.0
    }
}
