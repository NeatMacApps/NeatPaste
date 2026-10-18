import AppKit
import Foundation
import MacKitLifecycle
import SwiftUI

@main
struct NeatPasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openSettings) private var openSettings

    init() {
        AutofillHeuristicGuard.install()
    }

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Color.clear
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                    .onAppear {
                        SettingsWindowController.shared.installPresenter {
                            openSettings()
                        }
                    }
            }
        }
    }
}
