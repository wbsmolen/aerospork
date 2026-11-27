import Common
import Darwin
import Foundation

func hasStdin() -> Bool {
    isatty(STDIN_FILENO) != 1
}
