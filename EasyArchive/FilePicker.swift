import AppKit
import UniformTypeIdentifiers

enum FilePicker {
    static func chooseFilesOrFolders() -> [URL] {
        let panel = NSOpenPanel()
        panel.title = AppStrings.selectFileButton
        panel.message = "Choose files, folders, or zip archives."
        panel.prompt = AppStrings.selectFileButton
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.resolvesAliases = true

        return panel.runModal() == .OK ? panel.urls : []
    }

    static func chooseOutputFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.title = AppStrings.chooseOutputButton
        panel.message = "Choose where EasyArchive should save the result."
        panel.prompt = AppStrings.chooseOutputButton
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
