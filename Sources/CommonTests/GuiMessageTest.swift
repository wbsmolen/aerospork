@testable import Common
import Foundation
import XCTest

final class GuiMessageTest: XCTestCase {
    /// `osascript` compiled the message as source. A backslash was a syntax error, so no dialog at
    /// all, and a crafted message closed the string and ran what followed. A config error quotes the
    /// config, so a regex was enough to lose the dialog.
    func testTheMessageAndTitleAreDataNotPartOfTheScript() {
        let title = "a title"
        let message = #"x\" & (do shell script "id") --"#
        let args = osascriptDialogArguments(title: title, message: message)

        let statements = zip(args, args.dropFirst()).filter { $0.0 == "-e" }.map(\.1)
        XCTAssertFalse(statements.isEmpty)
        for statement in statements {
            XCTAssertFalse(statement.contains("do shell script"), statement)
            XCTAssertFalse(statement.contains(title), statement)
        }
        XCTAssertEqual(Array(args.suffix(3)), ["--", message, title])
    }

    /// A report holds a stack trace and window-manager state, and `/tmp` is shared with every other
    /// account on the Mac: whoever made the directory first owned it.
    func testRuntimeErrorReportsStayInThisUsersLibrary() {
        XCTAssertEqual(runtimeErrorReportDirectory.path, NSHomeDirectory() + "/Library/Logs/" + aeroSporkAppId)
    }
}
