import Foundation

/// Not `/tmp`: a report holds a stack trace and window-manager state, /tmp is shared with every other
/// account on the Mac, and whoever makes a directory there first owns it.
var runtimeErrorReportDirectory: URL {
    URL.libraryDirectory.appending(path: "Logs/\(aeroSporkAppId)", directoryHint: .isDirectory)
}

/// The text goes in argv, where it is data. Interpolated into the script it was source: a backslash
/// was a syntax error, so no dialog at all, and a crafted message closed the string and ran what
/// followed. `--` because a message can start with a dash.
func osascriptDialogArguments(title: String, message: String) -> [String] {
    [
        "-e", "on run argv",
        "-e", "display dialog (item 1 of argv) with title (item 2 of argv)",
        "-e", "end run",
        "--", message, title,
    ]
}

// Lives in Common because `die()` does, and `die()` is called from both processes. Moving it to
// AppBundle would need `die()` to take an injected reporter -- a protocol and a global to hold it,
// to save one file from importing AppKit. Not worth it while there is exactly one caller.
public func showMessageInGui(filenameIfConsoleApp: String?, title: String, message: String) {
    let titleAndMessage = "##### \(title) #####\n\n" + message
    if isCli {
        print(titleAndMessage)
    } else if let filenameIfConsoleApp {
        Result { try FileManager.default.createDirectory(at: runtimeErrorReportDirectory, withIntermediateDirectories: true) }.getOrDie()
        let file = runtimeErrorReportDirectory.appending(component: filenameIfConsoleApp)
        Result { try (titleAndMessage + "\n").write(to: file, atomically: true, encoding: .utf8) }.getOrDie()

        file.absoluteURL.open(with: URL(filePath: "/System/Applications/Utilities/Console.app"))
    } else {
        Result { try? Process.run(URL(filePath: "/usr/bin/osascript"), arguments: osascriptDialogArguments(title: title, message: message)) }.getOrDie()
        // === Alternatives ===
        // let myPopup = NSAlert()
        // myPopup.messageText = message
        // myPopup.alertStyle = NSAlert.Style.informational
        // myPopup.addButton(withTitle: "OK")
        // myPopup.runModal()

        // let alert = UIAlertController(title: "Alert", message: message, preferredStyle: UIAlertControllerStyle.alert)
        // alert.addAction(UIAlertAction(title: "Click", style: UIAlertActionStyle.default, handler: nil))
        // self.present(alert, animated: true, completion: nil)

        // file.absoluteURL.open(with: URL(filePath: "/System/Applications/Utilities/Console.app"))
        // file.absoluteURL.open(with: URL(filePath: "/System/Applications/TextEdit.app"))
    }
}
