import SwiftUI

@main
struct MarkMacZipApp: App {
    @StateObject private var historyStore = HistoryStore()

    var body: some Scene {
        WindowGroup {
            ContentView(historyStore: historyStore)
        }
        .windowResizability(.contentSize)
    }
}
