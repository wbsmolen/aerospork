@testable import AppBundle
import XCTest

/// A build refuses a feed without a valid signature and fails soft, by offering nothing, so each link has
/// to stay in place. `sign_update --verify` needs the key, so the signature itself is checked at publish.
final class ReleaseFeedTest: XCTestCase {
    private func read(_ path: String) throws -> String {
        try String(contentsOf: projectRoot.appending(path: path), encoding: .utf8)
    }

    func testABuildRequiresASignedFeed() throws {
        XCTAssertTrue(try read("project.yml").contains("SURequireSignedFeed: true"))
        XCTAssertTrue(try read("build-release.sh").contains("Print :SURequireSignedFeed"), "nothing asserts it is in the bundle")
    }

    func testTheFeedInTheRepoIsSigned() throws {
        XCTAssertTrue(try read("updates-site/appcast.xml").contains("sparkle-signatures"))
    }

    func testPublishingSignsTheFeedAndChecksWhatIsServed() throws {
        let script = try read("script/publish-release.sh")
        let sign = try XCTUnwrap(script.range(of: #"sign_update" updates-site/appcast.xml"#))
        let deploy = try XCTUnwrap(script.range(of: "./script/deploy-site.sh"))
        let served = try XCTUnwrap(script.range(of: #"--verify "$served_feed""#))
        XCTAssertLessThan(sign.lowerBound, deploy.lowerBound)
        XCTAssertLessThan(deploy.lowerBound, served.lowerBound)
    }
}
