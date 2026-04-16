import SwiftUI
import UniformTypeIdentifiers
import AppKit

@MainActor
final class ContentViewModel: ObservableObject {
    @Published var selectedItems: [URL] = []
    @Published var outputFolder: URL?
    @Published var statusText = AppStrings.idleStatus
    @Published var isWorking = false
    @Published var isDropTargeted = false

    private let archiveService: ArchiveService
    private let historyStore: HistoryStore

    init(archiveService: ArchiveService, historyStore: HistoryStore) {
        self.archiveService = archiveService
        self.historyStore = historyStore
    }

    var selectedItemSummary: String {
        if selectedItems.isEmpty {
            return AppStrings.noSelectedItems
        }

        if selectedItems.count == 1 {
            return selectedItems[0].lastPathComponent
        }

        return "\(selectedItems.count) items selected"
    }

    var outputFolderPath: String {
        outputFolder?.path ?? AppStrings.noOutputFolder
    }

    var canExtract: Bool {
        !isWorking && !selectedItems.isEmpty && selectedItems.allSatisfy { $0.pathExtension.lowercased() == "zip" } && outputFolder != nil
    }

    var canCompress: Bool {
        !isWorking && !selectedItems.isEmpty && outputFolder != nil
    }

    func chooseItems() {
        let urls = FilePicker.chooseFilesOrFolders()
        applySelectedItems(urls)
    }

    func chooseOutputFolder() {
        if let folder = FilePicker.chooseOutputFolder() {
            outputFolder = folder
            statusText = "Output folder is ready: \(folder.lastPathComponent)"
        }
    }

    func extractSelected() {
        guard let outputFolder else {
            statusText = AppStrings.missingOutputFolder
            return
        }

        guard !selectedItems.isEmpty else {
            statusText = AppStrings.noSelectedItems
            return
        }

        guard selectedItems.allSatisfy({ $0.pathExtension.lowercased() == "zip" }) else {
            statusText = AppStrings.invalidZipSelection
            return
        }

        isWorking = true
        statusText = selectedItems.count > 1 ? AppStrings.extractingMultipleStatus : AppStrings.extractingStatus

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
            statusText = AppStrings.missingOutputFolder
            return
        }

        guard !selectedItems.isEmpty else {
            statusText = AppStrings.noSelectedItems
            return
        }

        isWorking = true
        statusText = selectedItems.count > 1 ? AppStrings.compressingMultipleStatus : AppStrings.compressingStatus

        let items = selectedItems
        let archiveService = self.archiveService
        DispatchQueue.global(qos: .userInitiated).async {
            let results = archiveService.compressItems(items, to: outputFolder)

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
            statusText = AppStrings.invalidDrop
            return false
        }

        statusText = AppStrings.preparingDropStatus

        let group = DispatchGroup()
        let storageQueue = DispatchQueue(label: "EasyArchive.DropStorage")
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
            statusText = AppStrings.invalidDrop
            return
        }

        selectedItems = cleanedItems
        statusText = AppStrings.selectedStatus
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
                statusText = results.count == 1 ? AppStrings.successSingleExtract : "Finished extracting \(results.count) archives."
            } else {
                statusText = AppStrings.successSingleCompress
            }
            return
        }

        if successCount > 0 {
            statusText = AppStrings.partialSuccess
            return
        }

        statusText = results.first?.message ?? AppStrings.failureSummary
    }
}

struct ContentView: View {
    @ObservedObject private var historyStore: HistoryStore
    @StateObject private var viewModel: ContentViewModel

    init(historyStore: HistoryStore) {
        self.historyStore = historyStore
        _viewModel = StateObject(
            wrappedValue: ContentViewModel(
                archiveService: ArchiveService(),
                historyStore: historyStore
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
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppStrings.appTitle)
                .font(.system(size: 30, weight: .bold))

            Text(AppStrings.subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private var dropArea: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 42))
                .foregroundStyle(viewModel.isDropTargeted ? Color.accentColor : .secondary)

            Text(AppStrings.dropTitle)
                .font(.title2.weight(.semibold))

            Text(AppStrings.dropSubtitle)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 500)

            Text(viewModel.selectedItemSummary)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 230)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
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
                            .foregroundStyle(.accent)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.lastPathComponent)
                                .font(.headline)

                            Text(item.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                if viewModel.selectedItems.isEmpty {
                    Text(AppStrings.noSelectedItems)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text(AppStrings.selectedItemsTitle)
                .font(.headline)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button(AppStrings.selectFileButton) {
                    viewModel.chooseItems()
                }

                Button(AppStrings.chooseOutputButton) {
                    viewModel.chooseOutputFolder()
                }

                Button(AppStrings.extractButton) {
                    viewModel.extractSelected()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!viewModel.canExtract)

                Button(AppStrings.compressButton) {
                    viewModel.compressSelected()
                }
                .disabled(!viewModel.canCompress)
            }

            HStack(spacing: 10) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(AppStrings.outputFolderTitle)
                        .font(.headline)

                    Text(viewModel.outputFolderPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if viewModel.isWorking {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var statusCard: some View {
        GroupBox {
            Text(viewModel.statusText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(.vertical, 2)
        } label: {
            Text(AppStrings.statusTitle)
                .font(.headline)
        }
    }

    private var historyPanel: some View {
        GroupBox {
            if historyStore.items.isEmpty {
                Text(AppStrings.noHistory)
                    .foregroundStyle(.secondary)
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

                                    Text(item.wasSuccessful ? "Success" : "Failed")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(item.wasSuccessful ? .green : .red)
                                }

                                Text(item.action.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(item.outputLocation)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)

                                Text(item.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            )
                        }
                    }
                }
            }
        } label: {
            Text(AppStrings.historyTitle)
                .font(.headline)
        }
    }
}
