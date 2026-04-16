import Foundation

enum ArchiveAction: String, Codable {
    case extract
    case compress

    var title: String {
        switch self {
        case .extract:
            return AppStrings.extractButton
        case .compress:
            return AppStrings.compressButton
        }
    }
}

struct HistoryItem: Identifiable, Codable {
    let id = UUID()
    let fileName: String
    let action: ArchiveAction
    let outputLocation: String
    let wasSuccessful: Bool
    let detail: String
    let timestamp: Date

    init(
        fileName: String,
        action: ArchiveAction,
        outputLocation: String,
        wasSuccessful: Bool,
        detail: String,
        timestamp: Date = Date()
    ) {
        self.fileName = fileName
        self.action = action
        self.outputLocation = outputLocation
        self.wasSuccessful = wasSuccessful
        self.detail = detail
        self.timestamp = timestamp
    }
}

struct ArchiveOperationResult {
    let sourceURL: URL
    let destinationURL: URL?
    let action: ArchiveAction
    let isSuccess: Bool
    let message: String
}

enum AppStrings {
    // Keeping user-facing copy together makes future localization easier.
    static let appTitle = "EasyArchive"
    static let subtitle = "Zip and unzip files with a simple, friendly workflow."
    static let dropTitle = "Drop files or folders here"
    static let dropSubtitle = "You can drag a .zip file to extract, or drag files and folders to create a new zip."
    static let selectedItemsTitle = "Selected Items"
    static let noSelectedItems = "Nothing selected yet."
    static let outputFolderTitle = "Output Folder"
    static let noOutputFolder = "No output folder selected yet."
    static let historyTitle = "Recent Activity"
    static let noHistory = "No recent activity yet."
    static let selectFileButton = "Select File"
    static let chooseOutputButton = "Choose Output Folder"
    static let extractButton = "Extract"
    static let compressButton = "Compress"
    static let statusTitle = "Status"
    static let idleStatus = "Choose or drop files to get started."
    static let preparingDropStatus = "Reading dropped files..."
    static let selectedStatus = "Files are ready. Choose what you want to do next."
    static let missingOutputFolder = "Choose an output folder before continuing."
    static let invalidZipSelection = "Extraction only works with .zip files."
    static let invalidDrop = "That drop did not include any usable files or folders."
    static let extractingStatus = "Extracting archive..."
    static let extractingMultipleStatus = "Extracting archives..."
    static let compressingStatus = "Creating zip archive..."
    static let compressingMultipleStatus = "Creating zip archive from multiple items..."
    static let successSingleExtract = "Extraction finished successfully."
    static let successSingleCompress = "Compression finished successfully."
    static let partialSuccess = "Some items finished, but a few need attention."
    static let failureSummary = "The task could not be completed."
}
