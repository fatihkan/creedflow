import SwiftUI
import GRDB
import CodeForgeLib

@main
struct CodeForgeApp: App {
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
            ContentView()
                .environment(\.appDatabase, appDatabase)
        }
        .defaultSize(width: 1200, height: 800)

        Settings {
            SettingsView()
                .environment(\.appDatabase, appDatabase)
        }
    }
}
