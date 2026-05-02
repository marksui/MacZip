#if os(macOS)
import SwiftUI
import AppKit

struct ContentView: View {
    @State private var archiveFilePath: String = ""
    @State private var destinationPath: String = ""
    @State private var statusMessage: String = "Idle"
    @State private var isExtracting: Bool = false
    @State private var progressFraction: Double? = nil

    private let extractor = ZipExtractor()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MarkMacZip")
                    .font(.largeTitle.weight(.bold))

                Text("Extract ZIP and RAR archives locally on your Mac.")
                    .foregroundColor(.secondary)
            }

            GroupBox("Archive") {
                HStack {
                    TextField("Select a .zip or .rar file", text: $archiveFilePath)
                    Button(action: selectArchiveFile) {
                        Label("Browse", systemImage: "doc.badge.plus")
                    }
                }
            }

            GroupBox("Output Folder") {
                HStack {
                    TextField("Select destination folder", text: $destinationPath)
                    Button(action: selectOutputFolder) {
                        Label("Choose", systemImage: "folder.badge.plus")
                    }
                }
            }

            HStack(spacing: 12) {
                Button(action: extract) {
                    Label("Extract", systemImage: "tray.and.arrow.down.fill")
                        .font(.headline)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isExtracting)

                Text(archiveKindLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.12))
                    )
            }

            GroupBox("Progress") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(progressTitle)
                            .font(.headline)

                        Spacer()

                        Text(progressPercentText)
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundColor(progressColor)
                    }

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.secondary.opacity(0.14))

                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(progressColor)
                                .frame(width: max(geometry.size.width * progressDisplayFraction, isExtracting ? 10 : 0))
                        }
                    }
                    .frame(height: 10)

                    Text(statusMessage)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 390)
    }

    private var archiveKindLabel: String {
        let lowercasedPath = archiveFilePath.lowercased()
        if lowercasedPath.hasSuffix(".rar") {
            return "RAR"
        }
        if lowercasedPath.hasSuffix(".zip") {
            return "ZIP"
        }
        return "ZIP / RAR"
    }

    private var progressTitle: String {
        if isExtracting {
            return "Extracting"
        }
        if progressFraction == 1 {
            return "Completed"
        }
        return "Ready"
    }

    private var progressPercentText: String {
        guard let progressFraction else {
            return isExtracting ? "--%" : "0%"
        }

        return "\(Int((min(max(progressFraction, 0), 1) * 100).rounded()))%"
    }

    private var progressDisplayFraction: Double {
        if let progressFraction {
            return min(max(progressFraction, 0), 1)
        }

        return isExtracting ? 0.16 : 0
    }

    private var progressColor: Color {
        progressFraction == 1 ? .green : .accentColor
    }

    private func selectArchiveFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK {
            archiveFilePath = panel.url?.path ?? ""
        }
    }

    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK {
            destinationPath = panel.url?.path ?? ""
        }
    }

    private func extract() {
        progressFraction = 0
        statusMessage = "Extracting..."
        isExtracting = true

        let selectedArchive = archiveFilePath
        let selectedDestination = destinationPath

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try extractor.extract(
                    archiveFilePath: selectedArchive,
                    destinationPath: selectedDestination
                ) { progress, detail in
                    DispatchQueue.main.async {
                        progressFraction = progress
                        if !detail.isEmpty {
                            statusMessage = detail
                        }
                    }
                }
                DispatchQueue.main.async {
                    statusMessage = "Success: archive extracted."
                    progressFraction = 1
                    isExtracting = false
                }
            } catch {
                DispatchQueue.main.async {
                    statusMessage = "Error: \(error.localizedDescription)"
                    progressFraction = nil
                    isExtracting = false
                }
            }
        }
    }
}
#endif
