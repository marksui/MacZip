import SwiftUI

@main
struct MarkMacZipApp: App {
    @StateObject private var historyStore = HistoryStore()
    @AppStorage("appTheme") private var appThemeRawValue = AppTheme.light.rawValue
    @AppStorage("appLanguage") private var appLanguageRawValue = AppLanguage.simplifiedChinese.rawValue

    private var selectedTheme: AppTheme {
        AppTheme(rawValue: appThemeRawValue) ?? .light
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                historyStore: historyStore,
                appThemeRawValue: $appThemeRawValue,
                appLanguageRawValue: $appLanguageRawValue
            )
            .preferredColorScheme(selectedTheme == .dark ? .dark : .light)
        }
        .windowResizability(.contentSize)
    }
}
