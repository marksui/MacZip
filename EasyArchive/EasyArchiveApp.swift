import SwiftUI

@main
struct EasyArchiveApp: App {
    @StateObject private var historyStore = HistoryStore()

    var body: some Scene {
        WindowGroup {
            ContentView(historyStore: historyStore)
        }
        .windowResizability(.contentSize)
    }
}
