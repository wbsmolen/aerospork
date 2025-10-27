import XCTest
@testable import AppBundle

final class ExpiringCacheTests: XCTestCase {
    func testBasicGetSet() {
        let cache = ExpiringCache<String, Int>(timeout: 10.0, maxSize: 100)

        // Test cache miss
        XCTAssertNil(cache.get("key1"))
        XCTAssertEqual(cache.missCount, 1)

        // Test cache set and hit
        cache.set("key1", value: 42)
        XCTAssertEqual(cache.get("key1"), 42)
        XCTAssertEqual(cache.hitCount, 1)
        XCTAssertEqual(cache.count, 1)
    }

    func testExpiration() async {
        let cache = ExpiringCache<String, Int>(timeout: 0.1, maxSize: 100)

        cache.set("key1", value: 42)
        XCTAssertEqual(cache.get("key1"), 42)

        // Wait for expiration
        try? await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds

        // Should be expired
        XCTAssertNil(cache.get("key1"))
        XCTAssertEqual(cache.count, 0) // Entry removed on access
    }

    func testLRUEviction() {
        let cache = ExpiringCache<String, Int>(timeout: 10.0, maxSize: 3)

        cache.set("key1", value: 1)
        cache.set("key2", value: 2)
        cache.set("key3", value: 3)

        // Access key1 and key2 to increase their access counts
        _ = cache.get("key1")
        _ = cache.get("key1")
        _ = cache.get("key2")

        // Add a fourth item - should evict key3 (lowest access count)
        cache.set("key4", value: 4)

        XCTAssertNotNil(cache.get("key1"))
        XCTAssertNotNil(cache.get("key2"))
        XCTAssertNil(cache.get("key3")) // Evicted
        XCTAssertNotNil(cache.get("key4"))
    }

    func testCleanupExpired() async {
        let cache = ExpiringCache<String, Int>(timeout: 0.1, maxSize: 100)

        cache.set("key1", value: 1)
        cache.set("key2", value: 2)
        cache.set("key3", value: 3)

        XCTAssertEqual(cache.count, 3)

        // Wait for expiration
        try? await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds

        // Cleanup expired entries
        let cleaned = cache.cleanupExpired()
        XCTAssertEqual(cleaned, 3)
        XCTAssertEqual(cache.count, 0)
    }

    func testHitRate() {
        let cache = ExpiringCache<String, Int>(timeout: 10.0, maxSize: 100)

        cache.set("key1", value: 1)

        // 2 hits, 1 miss
        _ = cache.get("key1")
        _ = cache.get("key1")
        _ = cache.get("key2")

        XCTAssertEqual(cache.hitCount, 2)
        XCTAssertEqual(cache.missCount, 1)
        XCTAssertEqual(cache.hitRate, 2.0 / 3.0, accuracy: 0.001)
    }

    func testRemoveWhere() {
        let cache = ExpiringCache<String, Int>(timeout: 10.0, maxSize: 100)

        cache.set("user:1", value: 100)
        cache.set("user:2", value: 200)
        cache.set("product:1", value: 300)
        cache.set("product:2", value: 400)

        // Remove all user entries
        let removed = cache.removeWhere { key, _ in
            key.hasPrefix("user:")
        }

        XCTAssertEqual(removed, 2)
        XCTAssertEqual(cache.count, 2)
        XCTAssertNil(cache.get("user:1"))
        XCTAssertNil(cache.get("user:2"))
        XCTAssertNotNil(cache.get("product:1"))
        XCTAssertNotNil(cache.get("product:2"))
    }

    func testClear() {
        let cache = ExpiringCache<String, Int>(timeout: 10.0, maxSize: 100)

        cache.set("key1", value: 1)
        cache.set("key2", value: 2)
        _ = cache.get("key1")

        XCTAssertEqual(cache.count, 2)
        XCTAssertEqual(cache.hitCount, 1)

        cache.clear()

        XCTAssertEqual(cache.count, 0)
        XCTAssertEqual(cache.hitCount, 0)
        XCTAssertEqual(cache.missCount, 0)
    }

    func testExpiredCount() async {
        let cache = ExpiringCache<String, Int>(timeout: 0.1, maxSize: 100)

        cache.set("key1", value: 1)
        cache.set("key2", value: 2)

        XCTAssertEqual(cache.expiredCount, 0)

        // Wait for expiration
        try? await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds

        XCTAssertEqual(cache.expiredCount, 2)
        XCTAssertEqual(cache.count, 2) // Still in cache, just expired
    }
}

final class ExpiringCacheActorTests: XCTestCase {
    func testActorBasicOperations() async {
        let cache = ExpiringCacheActor<String, Int>(timeout: 10.0, maxSize: 100)

        await cache.set("key1", value: 42)
        let value = await cache.get("key1")

        XCTAssertEqual(value, 42)

        let stats = await cache.getStatistics()
        XCTAssertEqual(stats.hitCount, 1)
        XCTAssertEqual(stats.entryCount, 1)
    }

    func testActorConcurrency() async {
        let cache = ExpiringCacheActor<String, Int>(timeout: 10.0, maxSize: 100)

        // Simulate concurrent access
        await withTaskGroup(of: Void.self) { group in
            for i in 0 ..< 10 {
                group.addTask {
                    await cache.set("key\(i)", value: i)
                }
            }
        }

        let count = await cache.count
        XCTAssertEqual(count, 10)
    }

    func testStatisticsSnapshot() async {
        let cache = ExpiringCacheActor<String, Int>(timeout: 10.0, maxSize: 100)

        await cache.set("key1", value: 1)
        await cache.set("key2", value: 2)
        _ = await cache.get("key1")
        _ = await cache.get("key1")
        _ = await cache.get("key3") // Miss

        let stats = await cache.getStatistics()

        XCTAssertEqual(stats.entryCount, 2)
        XCTAssertEqual(stats.hitCount, 2)
        XCTAssertEqual(stats.missCount, 1)
        XCTAssertEqual(stats.totalAccesses, 3)
        XCTAssertEqual(stats.hitRate, 2.0 / 3.0, accuracy: 0.001)
    }
}
