import SwiftUI
import UniformTypeIdentifiers
import AppKit

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var selectedItems: [URL] = []
    @Published var outputFolder: URL?
    @Published var statusText: String
    @Published var isWorking = false
    @Published var isDropTargeted = false
    @Published var compressionPassword = ""

    private let archiveService: ArchiveService
    private let historyStore: HistoryStore
    private var language: AppLanguage

    init(archiveService: ArchiveService, historyStore: HistoryStore, language: AppLanguage) {
        self.archiveService = archiveService
        self.historyStore = historyStore
        self.language = language
        self.statusText = AppStrings.idleStatus(for: language)
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
        !isWorking && !selectedItems.isEmpty && selectedItems.allSatisfy { $0.pathExtension.lowercased() == "zip" } && outputFolder != nil
    }

    var canCompress: Bool {
        !isWorking && !selectedItems.isEmpty && outputFolder != nil
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

    func chooseOutputFolder() {
        if let folder = FilePicker.chooseOutputFolder() {
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

        guard selectedItems.allSatisfy({ $0.pathExtension.lowercased() == "zip" }) else {
            statusText = AppStrings.invalidZipSelection(for: language)
            return
        }

        isWorking = true
        statusText = selectedItems.count > 1 ? AppStrings.extractingMultipleStatus(for: language) : AppStrings.extractingStatus(for: language)

        let archives = selectedItems
        let archiveService = self.archiveService
        DispatchQueue.global(qos: .userInitiated).async {
            let results = archiveService.extractArchives(archives, to: outputFolder)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.finishOperation(results)
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

        isWorking = true
        statusText = selectedItems.count > 1 ? AppStrings.compressingMultipleStatus(for: language) : AppStrings.compressingStatus(for: language)

        let items = selectedItems
        let archiveService = self.archiveService
        let normalizedPassword = compressionPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        let encryptionPassword = normalizedPassword.isEmpty ? nil : normalizedPassword

        DispatchQueue.global(qos: .userInitiated).async {
            let results = archiveService.compressItems(items, to: outputFolder, password: encryptionPassword)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.finishOperation(results)
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
        let storageQueue = DispatchQueue(label: "MarkMacZip.DropStorage")
        var loadedURLs: [URL] = []

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

                storageQueue.sync {
                    loadedURLs.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            self.applySelectedItems(loadedURLs)
        }

        return true
    }

    private func applySelectedItems(_ urls: [URL]) {
        let cleanedItems = uniqueExistingURLs(from: urls)

        guard !cleanedItems.isEmpty else {
            statusText = AppStrings.invalidDrop(for: language)
            return
        }

        selectedItems = cleanedItems
        statusText = AppStrings.selectedStatus(for: language)
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

    private func finishOperation(_ results: [ArchiveOperationResult]) {
        isWorking = false

        for result in results {
            historyStore.record(
                HistoryItem(
                    fileName: result.sourceURL.lastPathComponent,
                    action: result.action,
                    outputLocation: result.destinationURL?.path ?? outputFolder?.path ?? "",
                    wasSuccessful: result.isSuccess,
                    detail: result.message
                )
            )
        }

        let successCount = results.filter(\.isSuccess).count

        if successCount == results.count {
            if results.first?.action == .extract {
                statusText = results.count == 1 ? AppStrings.successSingleExtract(for: language) : AppStrings.finishedExtracting(results.count, for: language)
            } else {
                statusText = AppStrings.successSingleCompress(for: language)
            }
            return
        }

        if successCount > 0 {
            statusText = AppStrings.partialSuccess(for: language)
            return
        }

        statusText = results.first?.message ?? AppStrings.failureSummary(for: language)
    }
}

struct ContentView: View {
    @ObservedObject private var historyStore: HistoryStore
    @Binding private var appThemeRawValue: String
    @Binding private var appLanguageRawValue: String
    @StateObject private var viewModel: ContentViewModel

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

    init(historyStore: HistoryStore, appThemeRawValue: Binding<String>, appLanguageRawValue: Binding<String>) {
        self.historyStore = historyStore
        _appThemeRawValue = appThemeRawValue
        _appLanguageRawValue = appLanguageRawValue

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
            VStack(alignment: .leading, spacing: 18) {
                header
                dropArea
                selectedItemsCard
                controls
                statusCard
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            historyPanel
                .frame(width: 270)
        }
        .padding(24)
        .frame(minWidth: 980, minHeight: 640)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            viewModel.updateLanguage(selectedLanguage)
        }
        .onChange(of: appLanguageRawValue) { _ in
            viewModel.updateLanguage(selectedLanguage)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppStrings.appTitle)
                .font(.system(size: 30, weight: .bold))

            Text(AppStrings.subtitle(for: selectedLanguage))
                .font(.title3)
                .foregroundColor(.secondary)
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
                        Image(systemName: item.pathExtension.lowercased() == "zip" ? "doc.zipper" : "folder")
                            .foregroundColor(Color.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.lastPathComponent)
                                .font(.headline)

                            Text(item.path)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                if viewModel.selectedItems.isEmpty {
                    Text(AppStrings.noSelectedItems(for: selectedLanguage))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(AppStrings.selectedItemsTitle(for: selectedLanguage))
                .font(.headline)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button(AppStrings.selectFileButton(for: selectedLanguage)) {
                    viewModel.chooseItems()
                }

                Button(AppStrings.addFileButton(for: selectedLanguage)) {
                    viewModel.addItems()
                }

                Button(AppStrings.chooseOutputButton(for: selectedLanguage)) {
                    viewModel.chooseOutputFolder()
                }

                Button(AppStrings.extractButton(for: selectedLanguage)) {
                    viewModel.extractSelected()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canExtract)

                Button(AppStrings.compressButton(for: selectedLanguage)) {
                    viewModel.compressSelected()
                }
                .disabled(!viewModel.canCompress)
            }

            settingsCard

            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.zipPasswordTitle(for: selectedLanguage))
                    .font(.headline)

                SecureField(AppStrings.zipPasswordPlaceholder(for: selectedLanguage), text: $viewModel.compressionPassword)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isWorking)
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

            if viewModel.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var settingsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Text(AppStrings.themeTitle(for: selectedLanguage))
                        .frame(width: 60, alignment: .leading)

                    Picker(AppStrings.themeTitle(for: selectedLanguage), selection: themeBinding) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title(for: selectedLanguage)).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 260)
                }

                HStack(spacing: 12) {
                    Text(AppStrings.languageTitle(for: selectedLanguage))
                        .frame(width: 60, alignment: .leading)

                    Picker(AppStrings.languageTitle(for: selectedLanguage), selection: languageBinding) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 260)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(AppStrings.settingsTitle(for: selectedLanguage))
                .font(.headline)
        }
    }

    private var statusCard: some View {
        GroupBox {
            Text(viewModel.statusText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
        } label: {
            Text(AppStrings.statusTitle(for: selectedLanguage))
                .font(.headline)
        }
    }

    private var historyPanel: some View {
        GroupBox {
            if historyStore.items.isEmpty {
                Text(AppStrings.noHistory(for: selectedLanguage))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
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
