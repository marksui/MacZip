import SwiftUI
import UniformTypeIdentifiers
import AppKit
import Darwin

private final class DropURLCollector {
    private let lock = NSLock()
    private var storage: [URL] = []

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var selectedItems: [URL] = []
    @Published var outputFolder: URL?
    @Published var statusText: String
    @Published var isWorking = false
    @Published var isDropTargeted = false
    @Published var compressionPassword = ""
    @Published var selectedCompressionFormat: ArchiveFormat = .zip
    @Published var outputArchiveName = AppStrings.defaultArchiveName
    @Published var progressFraction: Double?
    @Published var progressDetail = ""
    @Published var progressVisualState: ProgressVisualState = .idle

    private let archiveService: ArchiveService
    private let historyStore: HistoryStore
    private var language: AppLanguage
    private var hasManuallyChosenOutputFolder = false

    init(archiveService: ArchiveService, historyStore: HistoryStore, language: AppLanguage) {
        self.archiveService = archiveService
        self.historyStore = historyStore
        self.language = language
        self.statusText = AppStrings.idleStatus(for: language)
    }

    var availableCompressionFormats: [ArchiveFormat] {
        ArchiveFormat.allCases.filter { archiveService.supportsCompression(format: $0) }
    }

    var selectedItemSummary: String {
        if selectedItems.isEmpty {
            return AppStrings.noSelectedItems(for: language)
        }

        if selectedItems.count == 1 {
            return selectedItems[0].lastPathComponent
        }

        return AppStrings.selectedItemsCount(selectedItems.count, for: language)
    }

    var outputFolderPath: String {
        outputFolder?.path ?? AppStrings.noOutputFolder(for: language)
    }

    var canExtract: Bool {
        guard !isWorking, !selectedItems.isEmpty, outputFolder != nil else {
            return false
        }

        return selectedItems.allSatisfy {
            guard let format = ArchiveFormat.detect(from: $0) else {
                return false
            }
            return archiveService.supportsExtraction(format: format)
        }
    }

    var canCompress: Bool {
        guard !isWorking, !selectedItems.isEmpty, outputFolder != nil else {
            return false
        }

        guard archiveService.supportsCompression(format: selectedCompressionFormat) else {
            return false
        }

        if selectedCompressionFormat == .gzip {
            guard selectedItems.count == 1 else {
                return false
            }

            var isDirectory = ObjCBool(false)
            if FileManager.default.fileExists(atPath: selectedItems[0].path, isDirectory: &isDirectory), isDirectory.boolValue {
                return false
            }
        }

        return true
    }

    func updateLanguage(_ language: AppLanguage) {
        self.language = language

        if !isWorking {
            statusText = selectedItems.isEmpty ? AppStrings.idleStatus(for: language) : AppStrings.selectedStatus(for: language)
        }
    }

    func chooseItems() {
        let urls = FilePicker.chooseFilesOrFolders()
        applySelectedItems(urls)
    }

    func addItems() {
        let urls = FilePicker.chooseFilesOrFolders()

        guard !urls.isEmpty else {
            return
        }

        applySelectedItems(selectedItems + urls)
    }

    func removeSelectedItem(_ item: URL) {
        guard !isWorking else {
            return
        }

        selectedItems.removeAll { $0.path == item.path }
        statusText = selectedItems.isEmpty ? AppStrings.idleStatus(for: language) : AppStrings.selectedStatus(for: language)
    }

    func chooseOutputFolder() {
        if let folder = FilePicker.chooseOutputFolder() {
            hasManuallyChosenOutputFolder = true
            outputFolder = folder
            statusText = AppStrings.outputFolderReady(folder.lastPathComponent, for: language)
        }
    }

    func extractSelected() {
        guard let outputFolder else {
            statusText = AppStrings.missingOutputFolder(for: language)
            return
        }

        guard !selectedItems.isEmpty else {
            statusText = AppStrings.noSelectedItems(for: language)
            return
        }

        guard selectedItems.allSatisfy({
            guard let format = ArchiveFormat.detect(from: $0) else { return false }
            return archiveService.supportsExtraction(format: format)
        }) else {
            statusText = AppStrings.invalidArchiveSelection(for: language)
            return
        }

        beginOperation(with: selectedItems.count > 1 ? AppStrings.extractingMultipleStatus(for: language) : AppStrings.extractingStatus(for: language))

        let archives = selectedItems
        let service = self.archiveService
        let normalizedPassword = compressionPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let extractionPassword = normalizedPassword.isEmpty ? nil : normalizedPassword

        DispatchQueue.global(qos: .userInitiated).async {
            let startSnapshot = Self.captureResourceUsageSnapshot()
            let results = service.extractArchives(archives, to: outputFolder, password: extractionPassword) { progress in
                DispatchQueue.main.async { [weak self] in
                    self?.applyProgress(progress)
                }
            }
            let endSnapshot = Self.captureResourceUsageSnapshot()
            let elapsed = max(endSnapshot.timestamp.timeIntervalSince(startSnapshot.timestamp), 0.001)
            let cpuUsagePercent = max(((endSnapshot.totalCPUSeconds - startSnapshot.totalCPUSeconds) / elapsed) * 100, 0)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.finishOperation(results, elapsed: elapsed, cpuUsagePercent: cpuUsagePercent)
            }
        }
    }

    func compressSelected() {
        guard let outputFolder else {
            statusText = AppStrings.missingOutputFolder(for: language)
            return
        }

        guard !selectedItems.isEmpty else {
            statusText = AppStrings.noSelectedItems(for: language)
            return
        }

        if selectedCompressionFormat == .gzip {
            guard selectedItems.count == 1 else {
                statusText = AppStrings.unsupportedGzipInput(for: language)
                return
            }

            var isDirectory = ObjCBool(false)
            if FileManager.default.fileExists(atPath: selectedItems[0].path, isDirectory: &isDirectory), isDirectory.boolValue {
                statusText = AppStrings.unsupportedGzipInput(for: language)
                return
            }
        }

        guard archiveService.supportsCompression(format: selectedCompressionFormat) else {
            statusText = AppStrings.unsupportedSevenZip(for: language)
            return
        }

        beginOperation(with: AppStrings.compressingStatus(for: language, format: selectedCompressionFormat))

        let items = selectedItems
        let service = self.archiveService
        let format = selectedCompressionFormat
        let archiveBaseName = outputArchiveName
        let normalizedPassword = compressionPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let encryptionPassword = format.supportsPassword && !normalizedPassword.isEmpty ? normalizedPassword : nil

        DispatchQueue.global(qos: .userInitiated).async {
            let startSnapshot = Self.captureResourceUsageSnapshot()
            let results = service.compressItems(
                items,
                to: outputFolder,
                format: format,
                archiveBaseName: archiveBaseName,
                password: encryptionPassword
            ) { progress in
                DispatchQueue.main.async { [weak self] in
                    self?.applyProgress(progress)
                }
            }
            let endSnapshot = Self.captureResourceUsageSnapshot()
            let elapsed = max(endSnapshot.timestamp.timeIntervalSince(startSnapshot.timestamp), 0.001)
            let cpuUsagePercent = max(((endSnapshot.totalCPUSeconds - startSnapshot.totalCPUSeconds) / elapsed) * 100, 0)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.finishOperation(results, elapsed: elapsed, cpuUsagePercent: cpuUsagePercent)
            }
        }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }

        guard !fileProviders.isEmpty else {
            statusText = AppStrings.invalidDrop(for: language)
            return false
        }

        statusText = AppStrings.preparingDropStatus(for: language)

        let group = DispatchGroup()
        let loadedURLs = DropURLCollector()

        for provider in fileProviders {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                defer { group.leave() }

                guard let data else {
                    return
                }

                guard let url = NSURL(
                    absoluteURLWithDataRepresentation: data,
                    relativeTo: nil
                ) as URL? else {
                    return
                }

                loadedURLs.append(url)
            }
        }

        group.notify(queue: .main) {
            self.applySelectedItems(loadedURLs.urls)
        }

        return true
    }

    func progressStateText(for language: AppLanguage) -> String {
        switch progressVisualState {
        case .idle:
            return ""
        case .running:
            return progressDetail
        case .success:
            return AppStrings.progressCompleted(for: language)
        case .failure:
            return AppStrings.progressFailed(for: language)
        }
    }

    private func beginOperation(with message: String) {
        isWorking = true
        statusText = message
        progressDetail = message
        progressFraction = 0
        progressVisualState = .running
    }

    private func applyProgress(_ progress: ArchiveOperationProgress) {
        progressFraction = progress.fractionCompleted

        if !progress.detail.isEmpty {
            progressDetail = progress.detail
        }
    }

    private func applySelectedItems(_ urls: [URL]) {
        let cleanedItems = uniqueExistingURLs(from: urls)

        guard !cleanedItems.isEmpty else {
            statusText = AppStrings.invalidDrop(for: language)
            return
        }

        selectedItems = cleanedItems
        if !hasManuallyChosenOutputFolder || outputFolder == nil {
            outputFolder = suggestedOutputFolder(from: cleanedItems.last)
        }
        statusText = extractionToolMessage(for: cleanedItems) ?? AppStrings.selectedStatus(for: language)
        progressVisualState = .idle
        progressFraction = nil
        progressDetail = ""
    }

    private func extractionToolMessage(for urls: [URL]) -> String? {
        let formats = urls.compactMap { ArchiveFormat.detect(from: $0) }
        if formats.contains(.rar), !archiveService.supportsExtraction(format: .rar) {
            return AppStrings.unsupportedRar(for: language)
        }
        if formats.contains(.sevenZ), !archiveService.supportsExtraction(format: .sevenZ) {
            return AppStrings.unsupportedSevenZip(for: language)
        }
        return nil
    }

    private func suggestedOutputFolder(from url: URL?) -> URL? {
        guard let url else {
            return nil
        }

        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url
        }

        return url.deletingLastPathComponent()
    }

    private func uniqueExistingURLs(from urls: [URL]) -> [URL] {
        var seen = Set<String>()

        return urls.filter { url in
            let standardizedPath = url.standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: standardizedPath) else {
                return false
            }

            if seen.contains(standardizedPath) {
                return false
            }

            seen.insert(standardizedPath)
            return true
        }
    }

    private func finishOperation(_ results: [ArchiveOperationResult], elapsed: TimeInterval, cpuUsagePercent: Double) {
        isWorking = false

        for result in results {
            let metrics = metricsForResult(result, elapsed: elapsed, cpuUsagePercent: cpuUsagePercent)
            historyStore.record(
                HistoryItem(
                    fileName: result.sourceURL.lastPathComponent,
                    action: result.action,
                    outputLocation: result.destinationURL?.path ?? outputFolder?.path ?? "",
                    wasSuccessful: result.isSuccess,
                    detail: result.message,
                    metrics: metrics
                )
            )
        }

        let successCount = results.filter(\.isSuccess).count

        if successCount == results.count {
            progressVisualState = .success
            progressFraction = 1

            if results.first?.action == .extract {
                statusText = results.count == 1 ? AppStrings.successSingleExtract(for: language) : AppStrings.finishedExtracting(results.count, for: language)
            } else {
                statusText = AppStrings.successSingleCompress(for: language)
            }
            return
        }

        progressVisualState = .failure

        if successCount > 0 {
            statusText = AppStrings.partialSuccess(for: language)
            return
        }

        statusText = results.first?.message ?? AppStrings.failureSummary(for: language)
    }

    private func metricsForResult(_ result: ArchiveOperationResult, elapsed: TimeInterval, cpuUsagePercent: Double) -> OperationMetrics? {
        let inputBytes: Int64
        switch result.action {
        case .extract:
            inputBytes = fileSize(at: result.sourceURL)
        case .compress:
            inputBytes = selectedItems.reduce(0) { $0 + fileSize(at: $1) }
        }

        let outputBytes = fileSize(at: result.destinationURL)
        guard inputBytes > 0 else {
            return nil
        }

        let throughputMBps = (Double(inputBytes) / 1_048_576.0) / max(elapsed, 0.001)
        return OperationMetrics(
            latencySeconds: elapsed,
            throughputMBps: throughputMBps,
            cpuUsagePercent: cpuUsagePercent,
            inputBytes: inputBytes,
            outputBytes: outputBytes
        )
    }

    private func fileSize(at url: URL?) -> Int64 {
        guard let url else {
            return 0
        }

        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 0
        }

        if !isDirectory.boolValue {
            return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
        }

        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )

        var totalSize: Int64 = 0
        while let itemURL = enumerator?.nextObject() as? URL {
            guard let values = try? itemURL.resourceValues(forKeys: resourceKeys), values.isRegularFile == true else {
                continue
            }
            totalSize += Int64(values.fileSize ?? 0)
        }

        return totalSize
    }

    private struct ResourceUsageSnapshot {
        let timestamp: Date
        let totalCPUSeconds: Double
    }

    private nonisolated static func captureResourceUsageSnapshot() -> ResourceUsageSnapshot {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)

        let userSeconds = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let systemSeconds = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000

        return ResourceUsageSnapshot(
            timestamp: Date(),
            totalCPUSeconds: userSeconds + systemSeconds
        )
    }
}

struct ContentView: View {
    @ObservedObject private var historyStore: HistoryStore
    @Binding private var appThemeRawValue: String
    @Binding private var appLanguageRawValue: String
    @Binding private var appFontScale: Double
    @StateObject private var viewModel: ContentViewModel
    @State private var isSettingsPopoverPresented = false
    @State private var isAboutPopoverPresented = false

    private var selectedTheme: AppTheme {
        get { AppTheme(rawValue: appThemeRawValue) ?? .light }
        nonmutating set { appThemeRawValue = newValue.rawValue }
    }

    private var selectedLanguage: AppLanguage {
        get { AppLanguage(rawValue: appLanguageRawValue) ?? .simplifiedChinese }
        nonmutating set { appLanguageRawValue = newValue.rawValue }
    }

    private var themeBinding: Binding<AppTheme> {
        Binding(
            get: { selectedTheme },
            set: { selectedTheme = $0 }
        )
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { selectedLanguage },
            set: { selectedLanguage = $0 }
        )
    }

    init(
        historyStore: HistoryStore,
        appThemeRawValue: Binding<String>,
        appLanguageRawValue: Binding<String>,
        appFontScale: Binding<Double>
    ) {
        self.historyStore = historyStore
        _appThemeRawValue = appThemeRawValue
        _appLanguageRawValue = appLanguageRawValue
        _appFontScale = appFontScale

        let initialLanguage = AppLanguage(rawValue: appLanguageRawValue.wrappedValue) ?? .simplifiedChinese
        _viewModel = StateObject(
            wrappedValue: ContentViewModel(
                archiveService: ArchiveService(),
                historyStore: historyStore,
                language: initialLanguage
            )
        )
    }

    var body: some View {
        HStack(spacing: 20) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    dropArea
                    selectedItemsCard
                    controls
                    progressCard
                    statusCard
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            historyPanel
                .frame(width: 270)
        }
        .padding(24)
        .scaleEffect(CGFloat(appFontScale), anchor: .topLeading)
        .frame(minWidth: 980 * CGFloat(appFontScale), minHeight: 640 * CGFloat(appFontScale))
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            viewModel.updateLanguage(selectedLanguage)
        }
        .onChange(of: appLanguageRawValue) { _ in
            viewModel.updateLanguage(selectedLanguage)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppStrings.appTitle)
                    .font(.system(size: 30, weight: .bold))

                Text(AppStrings.subtitle(for: selectedLanguage))
                    .font(.title3)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Text(AppStrings.appVersion)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button {
                    isAboutPopoverPresented = true
                } label: {
                    Text("?")
                        .font(.headline.weight(.bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $isAboutPopoverPresented, arrowEdge: .top) {
                    aboutPopover
                }

                Button {
                    isSettingsPopoverPresented = true
                } label: {
                    Label(AppStrings.settingsButton(for: selectedLanguage), systemImage: "gearshape.fill")
                }
                .popover(isPresented: $isSettingsPopoverPresented, arrowEdge: .top) {
                    settingsPopover
                }
            }
        }
    }

    private var dropArea: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 42))
                .foregroundColor(viewModel.isDropTargeted ? Color.accentColor : .secondary)

            Text(AppStrings.dropTitle(for: selectedLanguage))
                .font(.title2.weight(.semibold))

            Text(AppStrings.dropSubtitle(for: selectedLanguage))
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 500)

            Text(viewModel.selectedItemSummary)
                .font(.headline)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 230)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    viewModel.isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.25),
                    style: StrokeStyle(lineWidth: 2, dash: [8, 8])
                )
        )
        .onDrop(
            of: FilePicker.acceptedDropTypeIdentifiers,
            isTargeted: $viewModel.isDropTargeted,
            perform: viewModel.handleDrop(providers:)
        )
    }

    private var selectedItemsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(viewModel.selectedItems, id: \.path) { item in
                    HStack(spacing: 10) {
                        let isArchive = ArchiveFormat.detect(from: item) != nil
                        Image(systemName: isArchive ? "doc.zipper" : "folder")
                            .foregroundColor(Color.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(item.lastPathComponent)
                                    .font(.headline)

                                if let format = ArchiveFormat.detect(from: item) {
                                    Text(format.title(for: selectedLanguage))
                                        .font(.caption2.weight(.bold))
                                        .foregroundColor(Color.accentColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            Capsule()
                                                .fill(Color.accentColor.opacity(0.12))
                                        )
                                }
                            }

                            Text(item.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        Button {
                            viewModel.removeSelectedItem(item)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help(AppStrings.removeSelectedItem(for: selectedLanguage))
                        .disabled(viewModel.isWorking)
                    }
                }

                if viewModel.selectedItems.isEmpty {
                    Text(AppStrings.noSelectedItems(for: selectedLanguage))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.trailing, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(AppStrings.selectedItemsTitle(for: selectedLanguage))
                .font(.headline)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    viewModel.chooseItems()
                } label: {
                    Label(AppStrings.selectFileButton(for: selectedLanguage), systemImage: "doc.badge.plus")
                }

                Button {
                    viewModel.addItems()
                } label: {
                    Label(AppStrings.addFileButton(for: selectedLanguage), systemImage: "plus.circle")
                }

                Button {
                    viewModel.chooseOutputFolder()
                } label: {
                    Label(AppStrings.chooseOutputButton(for: selectedLanguage), systemImage: "folder.badge.plus")
                }

                Button {
                    viewModel.extractSelected()
                } label: {
                    Label(AppStrings.extractButton(for: selectedLanguage), systemImage: "tray.and.arrow.down.fill")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(PrimaryActionButtonStyle(tint: Color.accentColor))
                .disabled(!viewModel.canExtract)

                Button {
                    viewModel.compressSelected()
                } label: {
                    Label(AppStrings.compressButton(for: selectedLanguage), systemImage: "archivebox.fill")
                }
                .buttonStyle(PrimaryActionButtonStyle(tint: Color.green))
                .disabled(!viewModel.canCompress)
            }

            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(AppStrings.outputFolderTitle(for: selectedLanguage))
                        .font(.headline)

                    Text(viewModel.outputFolderPath)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 12) {
                Text(AppStrings.archiveFormatTitle(for: selectedLanguage))
                    .font(.headline)

                Picker(AppStrings.archiveFormatTitle(for: selectedLanguage), selection: $viewModel.selectedCompressionFormat) {
                    ForEach(viewModel.availableCompressionFormats) { format in
                        Text(format.title(for: selectedLanguage)).tag(format)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(maxWidth: 220)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.archiveNameTitle(for: selectedLanguage))
                    .font(.headline)

                TextField(AppStrings.archiveNamePlaceholder(for: selectedLanguage), text: $viewModel.outputArchiveName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isWorking)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.archivePasswordTitle(for: selectedLanguage))
                    .font(.headline)

                SecureField(AppStrings.archivePasswordPlaceholder(for: selectedLanguage), text: $viewModel.compressionPassword)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isWorking)
            }
        }
    }

    private var progressCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: progressStateIconName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(progressStateColor)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle()
                                .fill(progressStateColor.opacity(0.12))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(progressHeadline)
                            .font(.headline)

                        Text(progressDetailText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 8)

                    Text(progressPercentageText)
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .foregroundColor(progressStateColor)
                        .frame(minWidth: 44, alignment: .trailing)
                }

                progressBar
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(AppStrings.progressTitle(for: selectedLanguage))
                .font(.headline)
        }
    }

    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.secondary.opacity(0.14))

                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(progressStateColor)
                    .frame(width: max(geometry.size.width * progressDisplayFraction, viewModel.progressVisualState == .idle ? 0 : 10))
            }
        }
        .frame(height: 10)
        .animation(.easeInOut(duration: 0.22), value: progressDisplayFraction)
    }

    private var progressDisplayFraction: Double {
        if let fraction = viewModel.progressFraction {
            return min(max(fraction, 0), 1)
        }

        if viewModel.isWorking {
            return 0.16
        }

        return viewModel.progressVisualState == .success ? 1 : 0
    }

    private var progressHeadline: String {
        switch viewModel.progressVisualState {
        case .idle:
            return AppStrings.progressReady(for: selectedLanguage)
        case .running:
            return AppStrings.progressWorking(for: selectedLanguage)
        case .success:
            return AppStrings.progressCompleted(for: selectedLanguage)
        case .failure:
            return AppStrings.progressFailed(for: selectedLanguage)
        }
    }

    private var progressDetailText: String {
        if !viewModel.progressDetail.isEmpty {
            return viewModel.progressDetail
        }

        if viewModel.isWorking {
            return AppStrings.progressIndeterminate(for: selectedLanguage)
        }

        return viewModel.statusText
    }

    private var progressPercentageText: String {
        guard let fraction = viewModel.progressFraction else {
            return viewModel.isWorking ? "--%" : "0%"
        }

        return "\(Int((min(max(fraction, 0), 1) * 100).rounded()))%"
    }

    private var progressStateIconName: String {
        switch viewModel.progressVisualState {
        case .idle:
            return "clock"
        case .running:
            return "arrow.triangle.2.circlepath"
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }

    private var progressStateColor: Color {
        switch viewModel.progressVisualState {
        case .success:
            return .green
        case .failure:
            return .red
        case .running:
            return Color.accentColor
        default:
            return .secondary
        }
    }

    private func formattedByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private var settingsPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppStrings.settingsTitle(for: selectedLanguage))
                .font(.headline)

            HStack(spacing: 12) {
                Text(AppStrings.themeTitle(for: selectedLanguage))
                    .frame(width: 72, alignment: .leading)

                Picker(AppStrings.themeTitle(for: selectedLanguage), selection: themeBinding) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.title(for: selectedLanguage)).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 250)
            }

            HStack(spacing: 12) {
                Text(AppStrings.languageTitle(for: selectedLanguage))
                    .frame(width: 72, alignment: .leading)

                Picker(AppStrings.languageTitle(for: selectedLanguage), selection: languageBinding) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 250)
            }

            HStack(spacing: 12) {
                Text(AppStrings.fontSizeTitle(for: selectedLanguage))
                    .frame(width: 72, alignment: .leading)

                Button {
                    appFontScale = max(0.85, appFontScale - 0.05)
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .disabled(appFontScale <= 0.85)

                Button {
                    appFontScale = min(1.35, appFontScale + 0.05)
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .disabled(appFontScale >= 1.35)

                Text("\(Int(appFontScale * 100))%")
                    .foregroundColor(.secondary)
                    .frame(width: 42, alignment: .trailing)
            }
        }
        .padding(14)
        .frame(width: 370)
    }

    private var aboutPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(AppStrings.aboutTitle(for: selectedLanguage))
                .font(.headline)

            Text(AppStrings.aboutBody(for: selectedLanguage))
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(AppStrings.appVersion)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(width: 320)
    }

    private var statusCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(viewModel.statusText)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(AppStrings.copyStatusButton(for: selectedLanguage)) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.statusText, forType: .string)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 2)
        } label: {
            Text(AppStrings.statusTitle(for: selectedLanguage))
                .font(.headline)
        }
    }

    private var historyPanel: some View {
        GroupBox {
            ScrollView(.vertical, showsIndicators: true) {
                if historyStore.items.isEmpty {
                    Text(AppStrings.noHistory(for: selectedLanguage))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(historyStore.items) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(item.fileName)
                                        .font(.headline)
                                        .lineLimit(1)

                                    Spacer()

                                    Text(AppStrings.historyResult(item.wasSuccessful, for: selectedLanguage))
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(item.wasSuccessful ? .green : .red)

                                    Button {
                                        historyStore.remove(item.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                    .help(AppStrings.removeHistoryItem(for: selectedLanguage))
                                }

                                Text(item.action.title(for: selectedLanguage))
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text(item.outputLocation)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)

                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if let metrics = item.metrics {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(AppStrings.latencyTitle(for: selectedLanguage)): \(String(format: "%.2fs", metrics.latencySeconds))")
                                        Text("\(AppStrings.throughputTitle(for: selectedLanguage)): \(String(format: "%.2f MB/s", metrics.throughputMBps))")
                                        Text("\(AppStrings.cpuUsageTitle(for: selectedLanguage)): \(String(format: "%.0f%%", metrics.cpuUsagePercent))")
                                        Text("\(AppStrings.compressionRatioTitle(for: selectedLanguage)): \(String(format: "%.2f", metrics.compressionRatio)) (\(formattedByteCount(metrics.inputBytes)) -> \(formattedByteCount(metrics.outputBytes)))")
                                    }
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                }
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(NSColor.controlBackgroundColor))
                            )
                        }
                    }
                }
            }
        } label: {
            Text(AppStrings.historyTitle(for: selectedLanguage))
                .font(.headline)
        }
    }
}

private struct PrimaryActionButtonStyle: ButtonStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.75 : 1))
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
