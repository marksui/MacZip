import AppKit
import UniformTypeIdentifiers

enum FilePicker {
    private static var currentLanguage: AppLanguage {
        let rawValue = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        return AppLanguage(rawValue: rawValue) ?? .simplifiedChinese
    }

    static func chooseFilesOrFolders() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = AppStrings.selectFileButton(for: currentLanguage)
        panel.message = AppStrings.pickerSelectMessage(for: currentLanguage)
        panel.prompt = AppStrings.selectFileButton(for: currentLanguage)
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.resolvesAliases = true

        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseOutputFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = AppStrings.chooseOutputButton(for: currentLanguage)
        panel.message = AppStrings.pickerOutputMessage(for: currentLanguage)
        panel.prompt = AppStrings.chooseOutputButton(for: currentLanguage)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        return panel.runModal() == .OK ? panel.url : nil
    }

    static var acceptedDropTypeIdentifiers: [String] {
        [UTType.fileURL.identifier]
    }
}
