import SwiftUI
import AppKit
import GRDB
import CodeForgeLib

/// Keeps the app alive when the last window is closed (standard macOS behavior).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ensure the app appears in the dock and accepts focus
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Re-open the main window when clicking the dock icon
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(self)
            }
        }
        return true
    }
}

@main
struct CodeForgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("hasCompletedSetup") private var hasCompletedSetup = false
    @State private var appDatabase: AppDatabase

    init() {
        do {
            let database = try AppDatabase.makeDefault()
            _appDatabase = State(initialValue: database)
        } catch {
            fatalError("Database initialization failed: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            if hasCompletedSetup {
                ContentView()
                    .environment(\.appDatabase, appDatabase)
            } else {
                SetupWizardView()
                    .environment(\.appDatabase, appDatabase)
            }
        }
        .defaultSize(width: 1200, height: 800)

        Settings {
            SettingsView()
                .environment(\.appDatabase, appDatabase)
        }
    }
}
