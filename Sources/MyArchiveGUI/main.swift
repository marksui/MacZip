#if os(macOS)
import SwiftUI
import AppKit
import ArchiveBridge

enum ArchiveMode: String, CaseIterable, Identifiable {
    case compress = "Compress"
    case extract = "Extract"

    var id: String { rawValue }
}

enum CompressionChoice: Int, CaseIterable, Identifiable {
    case fast = 1
    case normal = 2
    case high = 3

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .fast: return "Fast"
        case .normal: return "Normal"
        case .high: return "High"
        }
    }
}

@MainActor
final class ArchiveViewModel: ObservableObject {
    @Published var mode: ArchiveMode = .compress
    @Published var inputPath: String = ""
    @Published var outputPath: String = ""
    @Published var password: String = ""
    @Published var compression: CompressionChoice = .normal
    @Published var status: String = "Ready"
    @Published var isRunning: Bool = false

    func browseInput() {
        if mode == .compress {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseFiles = true
            panel.canChooseDirectories = true
            panel.canCreateDirectories = false
            if panel.runModal() == .OK {
                inputPath = panel.url?.path ?? ""
                if outputPath.isEmpty, let url = panel.url {
                    let base = url.deletingPathExtension().lastPathComponent
                    outputPath = url.deletingLastPathComponent().appendingPathComponent(base + ".myarc").path
                }
            }
        } else {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            if panel.runModal() == .OK {
                inputPath = panel.url?.path ?? ""
                if outputPath.isEmpty, let url = panel.url {
                    let name = url.deletingPathExtension().lastPathComponent
                    outputPath = url.deletingLastPathComponent().appendingPathComponent(name + "_out").path
                }
            }
        }
    }

    func browseOutput() {
        if mode == .compress {
            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.nameFieldStringValue = "archive.myarc"
            if panel.runModal() == .OK {
                outputPath = panel.url?.path ?? ""
            }
        } else {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            if panel.runModal() == .OK {
                outputPath = panel.url?.path ?? ""
            }
        }
    }

    func run() {
        guard !inputPath.isEmpty else {
            status = "Select an input path first."
            return
        }
        guard !outputPath.isEmpty else {
            status = "Select an output path first."
            return
        }
        guard !password.isEmpty else {
            status = "Password cannot be empty."
            return
        }

        isRunning = true
        status = mode == .compress ? "Compressing…" : "Extracting…"

        let mode = self.mode
        let inputPath = self.inputPath
        let outputPath = self.outputPath
        let password = self.password
        let compression = self.compression.rawValue

        Task.detached(priority: .userInitiated) {
            var buffer = [CChar](repeating: 0, count: 4096)
            let result: Int32 = inputPath.withCString { inputC in
                outputPath.withCString { outputC in
                    password.withCString { passwordC in
                        if mode == .compress {
                            return myarchive_pack(inputC, outputC, passwordC, Int32(compression), &buffer, buffer.count)
                        } else {
                            return myarchive_unpack(inputC, outputC, passwordC, &buffer, buffer.count)
                        }
                    }
                }
            }
            let message = String(cString: buffer)
            await MainActor.run {
                self.isRunning = false
                if result == 0 {
                    self.status = mode == .compress ? "Archive created." : "Archive extracted."
                } else {
                    self.status = message.isEmpty ? "Operation failed." : message
                }
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ArchiveViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("MyArchive")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Picker("Mode", selection: $viewModel.mode) {
                    ForEach(ArchiveMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(viewModel.mode == .compress ? "Input File or Folder" : "Archive File")
                HStack {
                    TextField("Path", text: $viewModel.inputPath)
                    Button("Browse…") { viewModel.browseInput() }
                }

                Text(viewModel.mode == .compress ? "Output Archive" : "Output Folder")
                HStack {
                    TextField("Path", text: $viewModel.outputPath)
                    Button("Browse…") { viewModel.browseOutput() }
                }

                Text("Password")
                SecureField("Required", text: $viewModel.password)

                if viewModel.mode == .compress {
                    Text("Compression Level")
                    Picker("Compression", selection: $viewModel.compression) {
                        ForEach(CompressionChoice.allCases) { choice in
                            Text(choice.label).tag(choice)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            HStack {
                Button(viewModel.mode == .compress ? "Compress" : "Extract") {
                    viewModel.run()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.isRunning)

                if viewModel.isRunning {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()
            }

            GroupBox("Status") {
                Text(viewModel.status)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(minWidth: 620, minHeight: 340)
    }
}

@main
struct MyArchiveGUIApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
    }
}

#else
import Foundation

@main
struct MyArchiveGUIStub {
    static func main() {
        print("MyArchiveGUI is macOS-only. Build this target on a Mac.")
    }
}
#endif
