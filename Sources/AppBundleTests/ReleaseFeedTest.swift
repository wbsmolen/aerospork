@testable import AppBundle
import XCTest

/// A build refuses a feed without a valid signature and fails soft, by offering nothing, so each link has
/// to stay in place. `sign_update --verify` needs the key, so the signature itself is checked at publish.
final class ReleaseFeedTest: XCTestCase {
    func testABuildRequiresASignedFeed() throws {
        XCTAssertTrue(try readRepoFile("project.yml").contains("SURequireSignedFeed: true"))
        XCTAssertTrue(try readRepoFile("build-release.sh").contains("Print :SURequireSignedFeed"), "nothing asserts it is in the bundle")
    }

    func testTheFeedInTheRepoIsSigned() throws {
        XCTAssertTrue(try readRepoFile("updates-site/appcast.xml").contains("sparkle-signatures"))
    }

    func testPublishingSignsTheFeedAndChecksWhatIsServed() throws {
        let script = try readRepoFile("script/publish-release.sh")
        let sign = try XCTUnwrap(script.range(of: #"sign_update" updates-site/appcast.xml"#))
        let deploy = try XCTUnwrap(script.range(of: "./script/deploy-site.sh"))
        let served = try XCTUnwrap(script.range(of: #"--verify "$served_feed""#))
        XCTAssertLessThan(sign.lowerBound, deploy.lowerBound)
        XCTAssertLessThan(deploy.lowerBound, served.lowerBound)
    }

    /// A release from a stale tree, with a version that is not new, or onto a tag cut from other code must stop
    /// before the 20-minute build. A local feed that is not the live one would also drop the newest live item.
    func testPublishingRefusesAStaleTreeOrVersionBeforeTheBuild() throws {
        let script = try readRepoFile("script/publish-release.sh")
        let tests = try XCTUnwrap(script.range(of: "./run-tests.sh"))
        let checks = [
            #"!= "$(git rev-parse origin/main)""#,
            #"cmp -s "$live_feed" updates-site/appcast.xml"#,
            #"| sort -V | tail -1)" != "$build_version""#,
            #"git rev-parse -q --verify "refs/tags/v$build_version^{commit}""#,
        ]
        for check in checks {
            let range = try XCTUnwrap(script.range(of: check), check)
            XCTAssertLessThan(range.lowerBound, tests.lowerBound, check)
        }
    }

    /// A site deploy from a tree without the newest appcast serves the older, still validly signed feed, and
    /// clients stop being offered the new release. A feed that does not verify makes them offer nothing.
    func testASiteDeployRefusesARolledBackOrUnverifiedFeed() throws {
        let script = try readRepoFile("script/deploy-site.sh")
        let upload = try XCTUnwrap(script.range(of: "firebase-deploy.py"))
        let fetchLive = try XCTUnwrap(script.range(of: "https://aerospork.app/appcast.xml?deploy="))
        let compare = try XCTUnwrap(script.range(of: #"sort -V | tail -1)" != "$local_version""#))
        let verify = try XCTUnwrap(script.range(of: #"sign_update" --verify updates-site/appcast.xml"#))
        XCTAssertLessThan(fetchLive.lowerBound, upload.lowerBound)
        XCTAssertLessThan(compare.lowerBound, upload.lowerBound)
        XCTAssertLessThan(verify.lowerBound, upload.lowerBound)
    }
}
