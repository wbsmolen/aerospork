import Foundation
import XCTest

/// Invariants for `updates-site/`, the directory deployed to `https://aerospork.app`.
///
/// Asserted against the files rather than against a live site because every failure here is
/// **silent**. A Content-Security-Policy that stops matching the markup does not error at deploy
/// time; the page simply renders unstyled, or the copy button stops working, for whoever loads it
/// next. Same for a mistyped asset path. The deploy reports success either way.
///
/// The one file that must never break is `appcast.xml`: it is the update channel for every
/// installed copy, it shares this directory, and Sparkle treats an unreachable feed as "nothing to
/// report" rather than as an error.
///
/// Same technique as `BrandingTest` and `PerfInvariantsTest.testHotPathsContainNoUnconditionalPrint`.
final class SiteInvariantsTest: XCTestCase {
    private var siteRoot: URL { projectRoot.appending(path: "updates-site") }

    private func htmlFiles() throws -> [(name: String, text: String)] {
        let urls = try FileManager.default
            .contentsOfDirectory(at: siteRoot, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "html" }
        XCTAssertFalse(urls.isEmpty, "updates-site matched no HTML -- the scan silently covered nothing")
        return try urls.map { ($0.lastPathComponent, try String(contentsOf: $0, encoding: .utf8)) }
    }

    /// The CSP is `style-src 'self'; script-src 'self'`, so an inline `<style>` or an inline
    /// `<script>` is refused by the browser and the page silently loses its styling or its
    /// behaviour. The alternatives are `'unsafe-inline'`, which defeats the policy, or a hash,
    /// which breaks on the next edit without anyone noticing. So: separate files.
    func testNoInlineStyleOrScriptBecauseTheCspForbidsThem() throws {
        for (name, text) in try htmlFiles() {
            XCTAssertFalse(
                text.contains("<style"),
                "\(name) has an inline <style>. The CSP sends style-src 'self', so the browser will "
                    + "refuse it and the page will render unstyled. Move it into site.css.",
            )
            // `<script src=...>` is fine; a `<script>` with a body is not.
            for match in text.ranges(ofHtmlTag: "script") {
                let tag = String(text[match])
                XCTAssertTrue(
                    tag.contains("src="),
                    "\(name) has an inline <script>. The CSP sends script-src 'self', so the browser "
                        + "will refuse it. Move it into copy.js, or another file next to it.",
                )
            }
        }
    }

    /// If the policy stops being `default-src 'none'`, `privacy.html` starts making a claim the
    /// site no longer enforces -- which for a privacy page is worse than saying nothing.
    func testContentSecurityPolicyStillDeniesByDefault() throws {
        let config = try String(
            contentsOf: siteRoot.appending(path: "staticwebapp.config.json"), encoding: .utf8,
        )
        XCTAssertTrue(
            config.contains("default-src 'none'"),
            "staticwebapp.config.json no longer sends default-src 'none'. privacy.html tells readers "
                + "the browser refuses any off-site request this page makes. Either restore the policy "
                + "or correct that page -- do not leave the claim standing without the mechanism.",
        )
    }

    /// A mistyped `href`/`src` is invisible until someone loads the page: the stylesheet 404s and
    /// the site renders as unstyled HTML.
    func testEveryLocalAssetReferencedByThePagesExists() throws {
        for (name, text) in try htmlFiles() {
            for path in text.localAssetPaths() {
                let file = siteRoot.appending(path: path)
                XCTAssertTrue(
                    FileManager.default.fileExists(atPath: file.path),
                    "\(name) references /\(path), which is not in updates-site/. It will 404 in "
                        + "production and the deploy will still report success.",
                )
            }
        }
    }

    /// The site's icon is a copy of the shipping app icon, not a redraw. If they diverge, the
    /// website is advertising an icon the app does not have.
    func testSiteIconIsTheShippingAppIcon() throws {
        let site = try Data(contentsOf: siteRoot.appending(path: "icon.png"))
        let app = try Data(
            contentsOf: projectRoot.appending(
                path: "resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png",
            ),
        )
        XCTAssertEqual(
            site, app,
            "updates-site/icon.png has drifted from the app icon. Copy it again rather than editing "
                + "it in place: resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png",
        )
    }

    /// The appcast shares this directory with the pages, so a site deploy republishes it. Losing it
    /// strands every installed copy on the version it already has, silently.
    func testAppcastIsStillPresentAndSigned() throws {
        let appcast = try String(contentsOf: siteRoot.appending(path: "appcast.xml"), encoding: .utf8)
        XCTAssertTrue(
            appcast.contains("sparkle:edSignature"),
            "appcast.xml carries no EdDSA signature. Every build refuses an update it cannot verify, "
                + "so an unsigned feed updates nobody.",
        )
    }
}

extension String {
    /// Ranges of complete `<tag ...>` opening tags, so the test can look at their attributes.
    fileprivate func ranges(ofHtmlTag tag: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var cursor = startIndex
        while let open = range(of: "<\(tag)", range: cursor ..< endIndex),
              let close = range(of: ">", range: open.upperBound ..< endIndex)
        {
            result.append(open.lowerBound ..< close.upperBound)
            cursor = close.upperBound
        }
        return result
    }

    /// Root-relative asset paths the page loads or links to, e.g. `/site.css` -> `site.css`.
    /// Off-site URLs and in-page anchors are not this test's business.
    fileprivate func localAssetPaths() -> [String] {
        var result: [String] = []
        for attribute in ["href=\"", "src=\""] {
            var cursor = startIndex
            while let open = range(of: attribute, range: cursor ..< endIndex),
                  let close = range(of: "\"", range: open.upperBound ..< endIndex)
            {
                let value = String(self[open.upperBound ..< close.lowerBound])
                cursor = close.upperBound
                // "/" alone is the landing page, not a file in this directory.
                guard value.hasPrefix("/"), value != "/" else { continue }
                result.append(String(value.dropFirst()))
            }
        }
        return result
    }
}
