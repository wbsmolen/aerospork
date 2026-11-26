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

    /// A site deploy from a tree without the newest appcast serves the older, still validly signed feed, and
    /// clients stop being offered the new release. A feed that does not verify makes them offer nothing.
    func testASiteDeployRefusesARolledBackOrUnverifiedFeed() throws {
        let script = try read("script/deploy-site.sh")
        let upload = try XCTUnwrap(script.range(of: "firebase-deploy.py"))
        let fetchLive = try XCTUnwrap(script.range(of: "https://aerospork.app/appcast.xml?deploy="))
        let compare = try XCTUnwrap(script.range(of: #"sort -V | tail -1)" != "$local_version""#))
        let verify = try XCTUnwrap(script.range(of: #"sign_update" --verify updates-site/appcast.xml"#))
        XCTAssertLessThan(fetchLive.lowerBound, upload.lowerBound)
        XCTAssertLessThan(compare.lowerBound, upload.lowerBound)
        XCTAssertLessThan(verify.lowerBound, upload.lowerBound)
    }
}
