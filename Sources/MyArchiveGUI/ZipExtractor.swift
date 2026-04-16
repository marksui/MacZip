#if os(macOS)
import Foundation

enum ZipExtractorError: LocalizedError {
    case invalidZipPath
    case invalidDestination
    case unzipFailed(code: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidZipPath:
            return "Please select a valid .zip file."
        case .invalidDestination:
            return "Please select a valid destination folder."
        case let .unzipFailed(code, message):
            if message.isEmpty {
                return "Extraction failed with exit code \(code)."
            }
            return "Extraction failed (code \(code)): \(message)"
        }
    }
}

struct ZipExtractor {
    func extract(zipFilePath: String, destinationPath: String) throws {
        let fileManager = FileManager.default

        guard zipFilePath.lowercased().hasSuffix(".zip"), fileManager.fileExists(atPath: zipFilePath) else {
            throw ZipExtractorError.invalidZipPath
        }

        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: destinationPath, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ZipExtractorError.invalidDestination
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipFilePath, "-d", destinationPath]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData + outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ZipExtractorError.unzipFailed(code: process.terminationStatus, message: message)
        }
    }
}
#endif
