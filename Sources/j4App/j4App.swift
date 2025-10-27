import AppBundle
import SwiftUI

// This file is shared between SPM and xcode project

@MainActor // macOS 13
@main
struct j4App: App {
    @MainActor // macOS 13
    @StateObject var viewModel = TrayMenuModel.shared

    init() {
        initAppBundle()
    }

    @MainActor // macOS 13
    var body: some Scene {
        menuBar(viewModel: viewModel)

        WindowGroup(id: "configuration") {
            AppBundle.ConfigurationWindow()
        }
        .defaultSize(width: 800, height: 600)
        .commands {
            CommandGroup(replacing: .appInfo) {} // Remove default About menu
        }
    }
}
