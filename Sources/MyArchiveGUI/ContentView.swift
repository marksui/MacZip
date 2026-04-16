#if os(macOS)
import SwiftUI
import AppKit

struct ContentView: View {
    @State private var zipFilePath: String = ""
    @State private var destinationPath: String = ""
    @State private var statusMessage: String = "Idle"
    @State private var isExtracting: Bool = false

    private let extractor = ZipExtractor()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Mac ZIP Extractor")
                .font(.title2)
                .fontWeight(.semibold)

            GroupBox("ZIP file selector") {
                HStack {
                    TextField("Select a .zip file", text: $zipFilePath)
                    Button("Browse…", action: selectZipFile)
                }
            }

            GroupBox("Output folder selector") {
                HStack {
                    TextField("Select destination folder", text: $destinationPath)
                    Button("Browse…", action: selectOutputFolder)
                }
            }

            HStack {
                Button("Extract", action: extract)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isExtracting)

                if isExtracting {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            GroupBox("Status") {
                Text(statusMessage)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 260)
    }

    private func selectZipFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.zip]

        if panel.runModal() == .OK {
            zipFilePath = panel.url?.path ?? ""
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
        statusMessage = "Extracting..."
        isExtracting = true

        let selectedZip = zipFilePath
        let selectedDestination = destinationPath

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try extractor.extract(zipFilePath: selectedZip, destinationPath: selectedDestination)
                DispatchQueue.main.async {
                    statusMessage = "Success: archive extracted."
                    isExtracting = false
                }
            } catch {
                DispatchQueue.main.async {
                    statusMessage = "Error: \(error.localizedDescription)"
                    isExtracting = false
                }
            }
        }
    }
}
#endif
