#if os(macOS)
import Foundation

enum ZipExtractorError: LocalizedError {
    case invalidArchivePath
    case invalidDestination
    case missingRarTool
    case extractionFailed(code: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidArchivePath:
            return "Please select a valid .zip or .rar file."
        case .invalidDestination:
            return "Please select a valid destination folder."
        case .missingRarTool:
            return "RAR extraction requires unar, unrar, 7z, or 7zz."
        case let .extractionFailed(code, message):
            if message.isEmpty {
                return "Extraction failed with exit code \(code)."
            }
            return "Extraction failed (code \(code)): \(message)"
        }
    }
}

struct ZipExtractor {
    private enum ArchiveKind {
        case zip
        case rar
    }

    private enum RarBackend {
        case unar(String)
        case unrar(String)
        case sevenZip(String)
    }

    func extract(
        archiveFilePath: String,
        destinationPath: String,
        progressHandler: @escaping (Double?, String) -> Void
    ) throws {
        let fileManager = FileManager.default

        guard let kind = archiveKind(for: archiveFilePath), fileManager.fileExists(atPath: archiveFilePath) else {
            throw ZipExtractorError.invalidArchivePath
        }

        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: destinationPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ZipExtractorError.invalidDestination
        }

        switch kind {
        case .zip:
            try extractZip(archiveFilePath: archiveFilePath, destinationPath: destinationPath, progressHandler: progressHandler)
        case .rar:
            try extractRar(archiveFilePath: archiveFilePath, destinationPath: destinationPath, progressHandler: progressHandler)
        }
    }

    private func archiveKind(for path: String) -> ArchiveKind? {
        let lowercasedPath = path.lowercased()
        if lowercasedPath.hasSuffix(".zip") {
            return .zip
        }
        if lowercasedPath.hasSuffix(".rar") {
            return .rar
        }
        return nil
    }

    private func extractZip(
        archiveFilePath: String,
        destinationPath: String,
        progressHandler: @escaping (Double?, String) -> Void
    ) throws {
        let totalEntries = max((try? countOutputLines(executablePath: "/usr/bin/unzip", arguments: ["-Z1", archiveFilePath])) ?? 0, 1)

        try runProcessStreaming(
            executablePath: "/usr/bin/unzip",
            arguments: ["-o", archiveFilePath, "-d", destinationPath],
            estimatedTotalUnits: totalEntries,
            shouldCountLine: { line in
                line.contains("inflating:") || line.contains("extracting:") || line.contains("creating:")
            },
            progressFromLine: nil,
            progressHandler: progressHandler
        )
    }

    private func extractRar(
        archiveFilePath: String,
        destinationPath: String,
        progressHandler: @escaping (Double?, String) -> Void
    ) throws {
        guard let backend = Self.rarBackend() else {
            throw ZipExtractorError.missingRarTool
        }

        switch backend {
        case let .unar(executablePath):
            try runProcessStreaming(
                executablePath: executablePath,
                arguments: ["-force-overwrite", "-output-directory", destinationPath, archiveFilePath],
                estimatedTotalUnits: nil,
                shouldCountLine: { _ in false },
                progressFromLine: Self.parsePercentage(from:),
                progressHandler: progressHandler
            )

        case let .unrar(executablePath):
            let totalEntries = max((try? countOutputLines(executablePath: executablePath, arguments: ["lb", "-p-", archiveFilePath])) ?? 0, 1)
            try runProcessStreaming(
                executablePath: executablePath,
                arguments: ["x", "-o+", "-p-", archiveFilePath, destinationPath + "/"],
                estimatedTotalUnits: totalEntries,
                shouldCountLine: { line in
                    line.contains("Extracting") || line.contains("Creating") || line.hasSuffix("OK")
                },
                progressFromLine: Self.parsePercentage(from:),
                progressHandler: progressHandler
            )

        case let .sevenZip(executablePath):
            try runProcessStreaming(
                executablePath: executablePath,
                arguments: ["x", archiveFilePath, "-o\(destinationPath)", "-y"],
                estimatedTotalUnits: nil,
                shouldCountLine: { _ in false },
                progressFromLine: Self.parsePercentage(from:),
                progressHandler: progressHandler
            )
        }
    }

    private func countOutputLines(executablePath: String, arguments: [String]) throws -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData + errorData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            return 0
        }

        return output
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .count
    }

    private func runProcessStreaming(
        executablePath: String,
        arguments: [String],
        estimatedTotalUnits: Int?,
        shouldCountLine: @escaping (String) -> Bool,
        progressFromLine: ((String) -> Double?)?,
        progressHandler: @escaping (Double?, String) -> Void
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        let queue = DispatchQueue(label: "MarkMacZip.SimpleExtractor")
        var outputBuffer = ""
        var errorBuffer = ""
        var combinedOutput = ""
        var countedUnits = 0

        func handleLine(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            combinedOutput += trimmed + "\n"

            if let fraction = progressFromLine?(trimmed) {
                progressHandler(min(max(fraction, 0), 1), trimmed)
                return
            }

            guard let estimatedTotalUnits, shouldCountLine(trimmed) else {
                progressHandler(nil, trimmed)
                return
            }

            countedUnits += 1
            let fraction = Double(countedUnits) / Double(max(estimatedTotalUnits, 1))
            progressHandler(min(max(fraction, 0), 0.99), trimmed)
        }

        func consume(_ data: Data, isError: Bool) {
            guard !data.isEmpty else { return }

            queue.sync {
                var buffer = isError ? errorBuffer : outputBuffer
                buffer += String(decoding: data, as: UTF8.self)

                while let newlineRange = buffer.range(of: "\n") {
                    let line = String(buffer[..<newlineRange.lowerBound])
                    handleLine(line)
                    buffer.removeSubrange(...newlineRange.lowerBound)
                }

                if isError {
                    errorBuffer = buffer
                } else {
                    outputBuffer = buffer
                }
            }
        }

        progressHandler(0, "Starting extraction...")

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            consume(handle.availableData, isError: false)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            consume(handle.availableData, isError: true)
        }

        try process.run()
        process.waitUntilExit()

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil

        consume(outputPipe.fileHandleForReading.readDataToEndOfFile(), isError: false)
        consume(errorPipe.fileHandleForReading.readDataToEndOfFile(), isError: true)

        queue.sync {
            if !outputBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                handleLine(outputBuffer)
                outputBuffer = ""
            }
            if !errorBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                handleLine(errorBuffer)
                errorBuffer = ""
            }
        }

        guard process.terminationStatus == 0 else {
            throw ZipExtractorError.extractionFailed(
                code: process.terminationStatus,
                message: combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        progressHandler(1, "Extraction complete.")
    }

    private static func rarBackend() -> RarBackend? {
        for path in ["/opt/homebrew/bin/unar", "/usr/local/bin/unar", "/usr/bin/unar"] where FileManager.default.isExecutableFile(atPath: path) {
            return .unar(path)
        }

        for path in ["/opt/homebrew/bin/unrar", "/usr/local/bin/unrar", "/usr/bin/unrar"] where FileManager.default.isExecutableFile(atPath: path) {
            return .unrar(path)
        }

        for path in ["/opt/homebrew/bin/7zz", "/usr/local/bin/7zz", "/opt/homebrew/bin/7z", "/usr/local/bin/7z"] where FileManager.default.isExecutableFile(atPath: path) {
            return .sevenZip(path)
        }

        return nil
    }

    private static func parsePercentage(from line: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: "([0-9]{1,3})%") else {
            return nil
        }

        let nsLine = line as NSString
        let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: nsLine.length))
        guard let match, match.numberOfRanges > 1 else {
            return nil
        }

        let valueString = nsLine.substring(with: match.range(at: 1))
        guard let value = Double(valueString) else {
            return nil
        }

        return min(max(value / 100, 0), 1)
    }
}
#endif
