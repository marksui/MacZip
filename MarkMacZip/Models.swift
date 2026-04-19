import Foundation

enum AppTheme: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    func title(for language: AppLanguage) -> String {
        switch (self, language) {
        case (.light, .simplifiedChinese):
            return "白色"
        case (.dark, .simplifiedChinese):
            return "黑色"
        case (.light, .english):
            return "Light"
        case (.dark, .english):
            return "Dark"
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese
    case english

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .simplifiedChinese:
            return "简体中文"
        case .english:
            return "English"
        }
    }
}

enum ArchiveFormat: String, CaseIterable, Identifiable {
    case zip
    case sevenZ
    case tar
    case tarGz
    case gzip

    var id: String { rawValue }

    var fileExtension: String {
        switch self {
        case .zip:
            return "zip"
        case .sevenZ:
            return "7z"
        case .tar:
            return "tar"
        case .tarGz:
            return "tar.gz"
        case .gzip:
            return "gz"
        }
    }

    var supportsPassword: Bool {
        self == .zip || self == .sevenZ
    }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .zip:
            return "ZIP"
        case .sevenZ:
            return "7Z"
        case .tar:
            return "TAR"
        case .tarGz:
            return "TAR.GZ"
        case .gzip:
            return "GZIP"
        }
    }

    static func detect(from url: URL) -> ArchiveFormat? {
        let lowercasedName = url.lastPathComponent.lowercased()

        if lowercasedName.hasSuffix(".tar.gz") || lowercasedName.hasSuffix(".tgz") {
            return .tarGz
        }

        if lowercasedName.hasSuffix(".7z") {
            return .sevenZ
        }

        if lowercasedName.hasSuffix(".tar") {
            return .tar
        }

        if lowercasedName.hasSuffix(".zip") {
            return .zip
        }

        if lowercasedName.hasSuffix(".gz") {
            return .gzip
        }

        return nil
    }
}

enum ProgressVisualState {
    case idle
    case running
    case success
    case failure
}

struct ArchiveOperationProgress {
    let fractionCompleted: Double?
    let detail: String
}

enum ArchiveAction: String, Codable {
    case extract
    case compress

    func title(for language: AppLanguage) -> String {
        switch self {
        case .extract:
            return AppStrings.extractButton(for: language)
        case .compress:
            return AppStrings.compressButton(for: language)
        }
    }
}

struct HistoryItem: Identifiable, Codable {
    let id: UUID
    let fileName: String
    let action: ArchiveAction
    let outputLocation: String
    let wasSuccessful: Bool
    let detail: String
    let timestamp: Date
    let metrics: OperationMetrics?

    init(
        id: UUID = UUID(),
        fileName: String,
        action: ArchiveAction,
        outputLocation: String,
        wasSuccessful: Bool,
        detail: String,
        timestamp: Date = Date(),
        metrics: OperationMetrics? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.action = action
        self.outputLocation = outputLocation
        self.wasSuccessful = wasSuccessful
        self.detail = detail
        self.timestamp = timestamp
        self.metrics = metrics
    }
}

struct OperationMetrics: Codable {
    let latencySeconds: Double
    let throughputMBps: Double
    let cpuUsagePercent: Double
    let inputBytes: Int64
    let outputBytes: Int64

    var compressionRatio: Double {
        guard inputBytes > 0 else { return 0 }
        return Double(outputBytes) / Double(inputBytes)
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
    static let appTitle = "MarkMacZip"
    static let defaultArchiveName = "Archive"

    static func subtitle(for language: AppLanguage) -> String {
        isChinese(language) ? "用简单友好的方式压缩与解压文件。" : "Zip and unzip files with a simple, friendly workflow."
    }

    static func dropTitle(for language: AppLanguage) -> String {
        isChinese(language) ? "把文件或文件夹拖到这里" : "Drop files or folders here"
    }

    static func dropSubtitle(for language: AppLanguage) -> String {
        isChinese(language) ? "支持 ZIP、7Z、TAR、TAR.GZ/TGZ、GZIP。" : "Supports ZIP, 7Z, TAR, TAR.GZ/TGZ, and GZIP."
    }

    static func selectedItemsTitle(for language: AppLanguage) -> String {
        isChinese(language) ? "已选择项目" : "Selected Items"
    }

    static func removeSelectedItem(for language: AppLanguage) -> String {
        isChinese(language) ? "移除该文件" : "Remove this file"
    }

    static func noSelectedItems(for language: AppLanguage) -> String {
        isChinese(language) ? "还没有选择任何项目。" : "Nothing selected yet."
    }

    static func selectedItemsCount(_ count: Int, for language: AppLanguage) -> String {
        isChinese(language) ? "已选择 \(count) 项" : "\(count) items selected"
    }

    static func outputFolderTitle(for language: AppLanguage) -> String {
        isChinese(language) ? "输出文件夹" : "Output Folder"
    }

    static func archiveFormatTitle(for language: AppLanguage) -> String {
        isChinese(language) ? "格式" : "Format"
    }

    static func archiveNameTitle(for language: AppLanguage) -> String {
        isChinese(language) ? "压缩文件名" : "Archive Name"
    }

    static func archiveNamePlaceholder(for language: AppLanguage) -> String {
        isChinese(language) ? "默认 Archive" : "Default: Archive"
    }

    static func archivePasswordTitle(for language: AppLanguage) -> String {
        isChinese(language) ? "归档密码（可选）" : "Archive Password (Optional)"
    }

    static func archivePasswordPlaceholder(for language: AppLanguage) -> String {
        isChinese(language) ? "用于 ZIP/7Z 压缩或解压，留空表示不使用密码" : "Used for ZIP/7Z compression or extraction. Leave empty for no password."
    }

    static func copyStatusButton(for language: AppLanguage) -> String {
        isChinese(language) ? "复制" : "Copy"
    }

    static func noOutputFolder(for language: AppLanguage) -> String {
        isChinese(language) ? "尚未选择输出文件夹。" : "No output folder selected yet."
    }

    static func historyTitle(for language: AppLanguage) -> String {
        isChinese(language) ? "最近活动" : "Recent Activity"
    }

    static func noHistory(for language: AppLanguage) -> String {
        isChinese(language) ? "暂无最近活动。" : "No recent activity yet."
    }

    static func selectFileButton(for language: AppLanguage) -> String {
        isChinese(language) ? "选择文件" : "Select File"
    }

    static func addFileButton(for language: AppLanguage) -> String {
        isChinese(language) ? "添加文件" : "Add File"
    }

    static func chooseOutputButton(for language: AppLanguage) -> String {
        isChinese(language) ? "选择输出文件夹" : "Choose Output Folder"
    }

    static func pickerSelectMessage(for language: AppLanguage) -> String {
        isChinese(language) ? "选择文件、文件夹或支持的归档文件（ZIP/7Z/TAR/TAR.GZ/TGZ/GZ）。" : "Choose files, folders, or supported archives (ZIP/7Z/TAR/TAR.GZ/TGZ/GZ)."
    }

    static func pickerOutputMessage(for language: AppLanguage) -> String {
        isChinese(language) ? "选择 MarkMacZip 保存结果的位置。" : "Choose where MarkMacZip should save the result."
    }

    static func extractButton(for language: AppLanguage) -> String {
        isChinese(language) ? "解压" : "Extract"
    }

    static func compressButton(for language: AppLanguage) -> String {
        isChinese(language) ? "压缩" : "Compress"
    }

    static func statusTitle(for language: AppLanguage) -> String {
        isChinese(language) ? "状态" : "Status"
    }

    static func progressTitle(for language: AppLanguage) -> String {
        isChinese(language) ? "进度" : "Progress"
    }

    static func idleStatus(for language: AppLanguage) -> String {
        isChinese(language) ? "请选择文件或拖拽文件开始。" : "Choose or drop files to get started."
    }

    static func preparingDropStatus(for language: AppLanguage) -> String {
        isChinese(language) ? "正在读取拖入的文件..." : "Reading dropped files..."
    }

    static func selectedStatus(for language: AppLanguage) -> String {
        isChinese(language) ? "文件已就绪，请选择下一步操作。" : "Files are ready. Choose what you want to do next."
    }

    static func missingOutputFolder(for language: AppLanguage) -> String {
        isChinese(language) ? "请先选择输出文件夹。" : "Choose an output folder before continuing."
    }

    static func invalidArchiveSelection(for language: AppLanguage) -> String {
        isChinese(language) ? "仅支持 ZIP、7Z、TAR、TAR.GZ/TGZ、GZIP。" : "Only ZIP, 7Z, TAR, TAR.GZ/TGZ, and GZIP are supported."
    }

    static func invalidDrop(for language: AppLanguage) -> String {
        isChinese(language) ? "拖入内容中没有可用的文件或文件夹。" : "That drop did not include any usable files or folders."
    }

    static func extractingStatus(for language: AppLanguage) -> String {
        isChinese(language) ? "正在解压..." : "Extracting archive..."
    }

    static func extractingMultipleStatus(for language: AppLanguage) -> String {
        isChinese(language) ? "正在批量解压..." : "Extracting archives..."
    }

    static func compressingStatus(for language: AppLanguage) -> String {
        isChinese(language) ? "正在创建压缩包..." : "Creating archive..."
    }

    static func compressingStatus(for language: AppLanguage, format: ArchiveFormat) -> String {
        isChinese(language) ? "正在创建 \(format.title(for: language))..." : "Creating \(format.title(for: language)) archive..."
    }

    static func compressingMultipleStatus(for language: AppLanguage) -> String {
        isChinese(language) ? "正在从多个项目创建压缩包..." : "Creating archive from multiple items..."
    }

    static func successSingleExtract(for language: AppLanguage) -> String {
        isChinese(language) ? "解压完成。" : "Extraction finished successfully."
    }

    static func successSingleCompress(for language: AppLanguage) -> String {
        isChinese(language) ? "压缩完成。" : "Compression finished successfully."
    }

    static func finishedExtracting(_ count: Int, for language: AppLanguage) -> String {
        isChinese(language) ? "已完成解压 \(count) 个压缩包。" : "Finished extracting \(count) archives."
    }

    static func partialSuccess(for language: AppLanguage) -> String {
        isChinese(language) ? "部分项目成功，部分项目需要检查。" : "Some items finished, but a few need attention."
    }

    static func failureSummary(for language: AppLanguage) -> String {
        isChinese(language) ? "任务未能完成。" : "The task could not be completed."
    }

    static func outputFolderReady(_ folderName: String, for language: AppLanguage) -> String {
        isChinese(language) ? "输出文件夹已设置：\(folderName)" : "Output folder is ready: \(folderName)"
    }

    static func settingsTitle(for language: AppLanguage) -> String {
        isChinese(language) ? "设置" : "Settings"
    }

    static func settingsButton(for language: AppLanguage) -> String {
        isChinese(language) ? "设置" : "Settings"
    }

    static func themeTitle(for language: AppLanguage) -> String {
        isChinese(language) ? "主题" : "Theme"
    }

    static func languageTitle(for language: AppLanguage) -> String {
        isChinese(language) ? "语言" : "Language"
    }

    static func fontSizeTitle(for language: AppLanguage) -> String {
        isChinese(language) ? "字体大小" : "Font Size"
    }

    static func progressCompleted(for language: AppLanguage) -> String {
        isChinese(language) ? "已完成" : "Completed"
    }

    static func progressFailed(for language: AppLanguage) -> String {
        isChinese(language) ? "失败" : "Failed"
    }

    static func latencyTitle(for language: AppLanguage) -> String {
        isChinese(language) ? "耗时" : "Latency"
    }

    static func throughputTitle(for language: AppLanguage) -> String {
        isChinese(language) ? "吞吐量" : "Throughput"
    }

    static func cpuUsageTitle(for language: AppLanguage) -> String {
        isChinese(language) ? "CPU 使用率" : "CPU Usage"
    }

    static func compressionRatioTitle(for language: AppLanguage) -> String {
        isChinese(language) ? "压缩比" : "Compression Ratio"
    }

    static func historyResult(_ wasSuccessful: Bool, for language: AppLanguage) -> String {
        guard wasSuccessful else {
            return isChinese(language) ? "失败" : "Failed"
        }
        return isChinese(language) ? "成功" : "Success"
    }

    static func removeHistoryItem(for language: AppLanguage) -> String {
        isChinese(language) ? "删除这条记录" : "Delete this activity"
    }

    static func unsupportedGzipInput(for language: AppLanguage) -> String {
        isChinese(language) ? "GZIP 压缩仅支持单个文件。" : "GZIP compression supports only one file."
    }

    static func unsupportedSevenZip(for language: AppLanguage) -> String {
        isChinese(language) ? "未检测到 7z 命令行工具。可安装 p7zip 后重试。" : "7z command-line tool not found. Install p7zip and try again."
    }

    private static func isChinese(_ language: AppLanguage) -> Bool {
        language == .simplifiedChinese
    }
}
