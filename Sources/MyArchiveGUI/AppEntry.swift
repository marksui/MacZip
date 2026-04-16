#if os(macOS)
import SwiftUI

@main
struct MyArchiveGUIApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
    }
}
#endif
