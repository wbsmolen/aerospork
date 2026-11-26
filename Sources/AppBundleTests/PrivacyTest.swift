import XCTest

/// The privacy page promises that the update check is AeroSpork's only network request, and Sparkle makes
/// that one from `ui/Updater.swift`. No unit test can watch a process for traffic, so this reads the source:
/// any other file that reaches for a network API breaks the promise.
final class PrivacyTest: XCTestCase {
    func testTheUpdateCheckIsTheOnlyNetworkRequest() throws {
        let networkApis = ["URLSession", "URLRequest", "NWConnection", "CFStream", "NSURLConnection"]
        for dir in ["Sources/AppBundle", "Sources/Common", "Sources/Cli"] {
            for file in try sourceFiles(in: dir) where !file.path.hasSuffix("Sources/AppBundle/ui/Updater.swift") {
                let code = try withoutComments(String(contentsOf: file, encoding: .utf8))
                for api in networkApis where code.contains(api) {
                    XCTFail("\(file.lastPathComponent) uses \(api). The privacy page says the update check is the only network request.")
                }
            }
        }
    }
}
