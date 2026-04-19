import Foundation

enum ArchiveServiceError: LocalizedError {
    case invalidFileType
    case missingOutputFolder
    case permissionDenied(String)
    case extractionFailed(String)
    case compressionFailed(String)
    case unsupportedSelection
    case unsupportedGzipInput
    case sevenZipToolMissing

    private var currentLanguage: AppLanguage {
        let rawValue = UserDefaults.standard.string(forKey: "appLanguage") ?? ""
        return AppLanguage(rawValue: rawValue) ?? .simplifiedChinese
    }

    var errorDescription: String? {
        switch self {
        case .invalidFileType:
            return AppStrings.invalidArchiveSelection(for: currentLanguage)
        case .missingOutputFolder:
            return AppStrings.missingOutputFolder(for: currentLanguage)
        case let .permissionDenied(path):
            return "MarkMacZip does not have permission to use \(path)."
        case let .extractionFailed(reason):
            return "MarkMacZip could not extract the archive. \(reason)"
        case let .compressionFailed(reason):
            return "MarkMacZip could not create the archive. \(reason)"
        case .unsupportedSelection:
            return "Please choose at least one file or folder."
        case .unsupportedGzipInput:
            return AppStrings.unsupportedGzipInput(for: currentLanguage)
        case .sevenZipToolMissing:
            return AppStrings.unsupportedSevenZip(for: currentLanguage)
        }
    }
}

struct ArchiveService {
    private var fileManager: FileManager { .default }

    static func isSevenZipAvailable() -> Bool {
        sevenZipExecutablePath() != nil
    }

    func supportsCompression(format: ArchiveFormat) -> Bool {
        if format == .sevenZ {
            return Self.isSevenZipAvailable()
        }
        return true
    }

    func supportsExtraction(format: ArchiveFormat) -> Bool {
        if format == .sevenZ {
            return Self.isSevenZipAvailable()
        }
        return true
    }

    func extractArchives(
        _ archiveURLs: [URL],
        to outputFolder: URL,
        progressHandler: ((ArchiveOperationProgress) -> Void)? = nil
    ) -> [ArchiveOperationResult] {
        do {
            try validateOutputFolder(outputFolder)
        } catch {
            return archiveURLs.map {
                ArchiveOperationResult(
                    sourceURL: $0,
                    destinationURL: nil,
                    action: .extract,
                    isSuccess: false,
                    message: friendlyErrorMessage(for: error)
                )
            }
        }

        let totalArchives = max(archiveURLs.count, 1)
        var results: [ArchiveOperationResult] = []

        for (index, archiveURL) in archiveURLs.enumerated() {
            let result = extractSingleArchive(archiveURL, to: outputFolder) { itemProgress in
                guard let progressHandler else { return }

                if let itemFraction = itemProgress.fractionCompleted {
                    let overallFraction = (Double(index) + itemFraction) / Double(totalArchives)
                    progressHandler(
                        ArchiveOperationProgress(
                            fractionCompleted: min(max(overallFraction, 0), 1),
                            detail: itemProgress.detail
                        )
                    )
                } else {
                    progressHandler(itemProgress)
                }
            }

            results.append(result)

            progressHandler?(
                ArchiveOperationProgress(
                    fractionCompleted: Double(index + 1) / Double(totalArchives),
                    detail: result.message
                )
            )
        }

        return results
    }

    func compressItems(
        _ itemURLs: [URL],
        to outputFolder: URL,
        format: ArchiveFormat,
        archiveBaseName: String? = nil,
        password: String? = nil,
        progressHandler: ((ArchiveOperationProgress) -> Void)? = nil
    ) -> [ArchiveOperationResult] {
        do {
            try validateOutputFolder(outputFolder)

            guard !itemURLs.isEmpty else {
                throw ArchiveServiceError.unsupportedSelection
            }

            let normalizedPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines)
            let encryptionPassword = (normalizedPassword?.isEmpty == false) ? normalizedPassword : nil

            let result = try compressSingleArchive(
                itemURLs,
                to: outputFolder,
                format: format,
                archiveBaseName: archiveBaseName,
                password: encryptionPassword,
                progressHandler: progressHandler
            )

            return [result]
        } catch {
            return [
                ArchiveOperationResult(
                    sourceURL: itemURLs.first ?? outputFolder,
                    destinationURL: nil,
                    action: .compress,
                    isSuccess: false,
                    message: friendlyErrorMessage(for: error)
                )
            ]
        }
    }

    private func extractSingleArchive(
        _ archiveURL: URL,
        to outputFolder: URL,
        progressHandler: ((ArchiveOperationProgress) -> Void)?
    ) -> ArchiveOperationResult {
        do {
            guard let format = ArchiveFormat.detect(from: archiveURL) else {
                throw ArchiveServiceError.invalidFileType
            }

            guard supportsExtraction(format: format) else {
                throw ArchiveServiceError.sevenZipToolMissing
            }

            switch format {
            case .zip:
                return try extractZip(archiveURL, to: outputFolder, progressHandler: progressHandler)
            case .sevenZ:
                return try extractSevenZ(archiveURL, to: outputFolder, progressHandler: progressHandler)
            case .tar:
                return try extractTar(archiveURL, to: outputFolder, progressHandler: progressHandler)
            case .tarGz:
                return try extractTarGz(archiveURL, to: outputFolder, progressHandler: progressHandler)
            case .gzip:
                return try extractGzip(archiveURL, to: outputFolder, progressHandler: progressHandler)
            }
        } catch {
            return ArchiveOperationResult(
                sourceURL: archiveURL,
                destinationURL: nil,
                action: .extract,
                isSuccess: false,
                message: friendlyErrorMessage(for: error)
            )
        }
    }

    private func compressSingleArchive(
        _ itemURLs: [URL],
        to outputFolder: URL,
        format: ArchiveFormat,
        archiveBaseName: String?,
        password: String?,
        progressHandler: ((ArchiveOperationProgress) -> Void)?
    ) throws -> ArchiveOperationResult {
        guard supportsCompression(format: format) else {
            throw ArchiveServiceError.sevenZipToolMissing
        }

        let parentFolder = commonParentFolder(for: itemURLs)
        let archiveName = normalizedArchiveBaseName(archiveBaseName) ?? "Archive"
        let destinationURL = uniqueDestination(
            in: outputFolder,
            baseName: archiveName,
            pathExtension: format.fileExtension
        )

        switch format {
        case .zip:
            // For large single-file ZIP operations, ditto is usually more stable on macOS.
            if itemURLs.count == 1, password == nil {
                try runProcessStreaming(
                    executablePath: "/usr/bin/ditto",
                    arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", itemURLs[0].path, destinationURL.path],
                    currentDirectory: nil,
                    estimatedTotalUnits: nil,
                    shouldCountLine: { _ in false },
                    progressFromLine: nil,
                    progressHandler: progressHandler
                )
            } else {
                let relativePaths = itemURLs.map { relativePath(for: $0, from: parentFolder) }
                let progressTotal = totalProgressUnits(for: itemURLs)
                var zipArguments = ["-r", "-y"]
                if let password {
                    zipArguments += ["-P", password]
                }
                zipArguments.append(destinationURL.path)
                zipArguments += relativePaths

                try runProcessStreaming(
                    executablePath: "/usr/bin/zip",
                    arguments: zipArguments,
                    currentDirectory: parentFolder,
                    estimatedTotalUnits: progressTotal,
                    shouldCountLine: { line in line.contains("adding:") || line.contains("updating:") },
                    progressFromLine: nil,
                    progressHandler: progressHandler
                )
            }

        case .tar:
            let relativePaths = itemURLs.map { relativePath(for: $0, from: parentFolder) }
            let progressTotal = totalProgressUnits(for: itemURLs)
            var arguments = ["-cvf", destinationURL.path]
            arguments += relativePaths

            try runProcessStreaming(
                executablePath: "/usr/bin/tar",
                arguments: arguments,
                currentDirectory: parentFolder,
                estimatedTotalUnits: progressTotal,
                shouldCountLine: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                progressFromLine: nil,
                progressHandler: progressHandler
            )

        case .tarGz:
            let relativePaths = itemURLs.map { relativePath(for: $0, from: parentFolder) }
            let progressTotal = totalProgressUnits(for: itemURLs)
            var arguments = ["-czvf", destinationURL.path]
            arguments += relativePaths

            try runProcessStreaming(
                executablePath: "/usr/bin/tar",
                arguments: arguments,
                currentDirectory: parentFolder,
                estimatedTotalUnits: progressTotal,
                shouldCountLine: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                progressFromLine: nil,
                progressHandler: progressHandler
            )

        case .gzip:
            guard itemURLs.count == 1 else {
                throw ArchiveServiceError.unsupportedGzipInput
            }

            var isDirectory = ObjCBool(false)
            if fileManager.fileExists(atPath: itemURLs[0].path, isDirectory: &isDirectory), isDirectory.boolValue {
                throw ArchiveServiceError.unsupportedGzipInput
            }

            try runProcessWritingStdoutToFile(
                executablePath: "/usr/bin/gzip",
                arguments: ["-c", itemURLs[0].path],
                outputFile: destinationURL,
                progressHandler: progressHandler
            )

        case .sevenZ:
            guard let executablePath = Self.sevenZipExecutablePath() else {
                throw ArchiveServiceError.sevenZipToolMissing
            }

            let relativePaths = itemURLs.map { relativePath(for: $0, from: parentFolder) }
            var arguments = ["a", destinationURL.path]
            if let password {
                arguments.append("-p\(password)")
                arguments.append("-mhe=on")
            }
            arguments += relativePaths

            try runProcessStreaming(
                executablePath: executablePath,
                arguments: arguments,
                currentDirectory: parentFolder,
                estimatedTotalUnits: nil,
                shouldCountLine: { _ in false },
                progressFromLine: { line in
                    Self.parseSevenZipPercentage(from: line)
                },
                progressHandler: progressHandler
            )
        }

        return ArchiveOperationResult(
            sourceURL: itemURLs.first ?? parentFolder,
            destinationURL: destinationURL,
            action: .compress,
            isSuccess: true,
            message: "Saved to \(destinationURL.path)"
        )
    }

    private func extractZip(
        _ archiveURL: URL,
        to outputFolder: URL,
        progressHandler: ((ArchiveOperationProgress) -> Void)?
    ) throws -> ArchiveOperationResult {
        let destinationFolder = uniqueDestination(
            in: outputFolder,
            baseName: extractionBaseName(for: archiveURL, format: .zip),
            pathExtension: nil
        )

        try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let totalEntries = max((try? countOutputLines(executablePath: "/usr/bin/unzip", arguments: ["-Z1", archiveURL.path])) ?? 0, 1)

        try runProcessStreaming(
            executablePath: "/usr/bin/unzip",
            arguments: ["-o", archiveURL.path, "-d", destinationFolder.path],
            currentDirectory: nil,
            estimatedTotalUnits: totalEntries,
            shouldCountLine: { line in
                line.contains("inflating:") || line.contains("extracting:") || line.contains("creating:")
            },
            progressFromLine: nil,
            progressHandler: progressHandler
        )

        return ArchiveOperationResult(
            sourceURL: archiveURL,
            destinationURL: destinationFolder,
            action: .extract,
            isSuccess: true,
            message: "Saved to \(destinationFolder.path)"
        )
    }

    private func extractTar(
        _ archiveURL: URL,
        to outputFolder: URL,
        progressHandler: ((ArchiveOperationProgress) -> Void)?
    ) throws -> ArchiveOperationResult {
        let destinationFolder = uniqueDestination(
            in: outputFolder,
            baseName: extractionBaseName(for: archiveURL, format: .tar),
            pathExtension: nil
        )

        try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let totalEntries = max((try? countOutputLines(executablePath: "/usr/bin/tar", arguments: ["-tf", archiveURL.path])) ?? 0, 1)

        try runProcessStreaming(
            executablePath: "/usr/bin/tar",
            arguments: ["-xvf", archiveURL.path, "-C", destinationFolder.path],
            currentDirectory: nil,
            estimatedTotalUnits: totalEntries,
            shouldCountLine: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            progressFromLine: nil,
            progressHandler: progressHandler
        )

        return ArchiveOperationResult(
            sourceURL: archiveURL,
            destinationURL: destinationFolder,
            action: .extract,
            isSuccess: true,
            message: "Saved to \(destinationFolder.path)"
        )
    }

    private func extractTarGz(
        _ archiveURL: URL,
        to outputFolder: URL,
        progressHandler: ((ArchiveOperationProgress) -> Void)?
    ) throws -> ArchiveOperationResult {
        let destinationFolder = uniqueDestination(
            in: outputFolder,
            baseName: extractionBaseName(for: archiveURL, format: .tarGz),
            pathExtension: nil
        )

        try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let totalEntries = max((try? countOutputLines(executablePath: "/usr/bin/tar", arguments: ["-tzf", archiveURL.path])) ?? 0, 1)

        try runProcessStreaming(
            executablePath: "/usr/bin/tar",
            arguments: ["-xzvf", archiveURL.path, "-C", destinationFolder.path],
            currentDirectory: nil,
            estimatedTotalUnits: totalEntries,
            shouldCountLine: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            progressFromLine: nil,
            progressHandler: progressHandler
        )

        return ArchiveOperationResult(
            sourceURL: archiveURL,
            destinationURL: destinationFolder,
            action: .extract,
            isSuccess: true,
            message: "Saved to \(destinationFolder.path)"
        )
    }

    private func extractGzip(
        _ archiveURL: URL,
        to outputFolder: URL,
        progressHandler: ((ArchiveOperationProgress) -> Void)?
    ) throws -> ArchiveOperationResult {
        let destinationFile = uniqueDestination(
            in: outputFolder,
            baseName: extractionBaseName(for: archiveURL, format: .gzip),
            pathExtension: nil
        )

        try runProcessWritingStdoutToFile(
            executablePath: "/usr/bin/gunzip",
            arguments: ["-c", archiveURL.path],
            outputFile: destinationFile,
            progressHandler: progressHandler
        )

        return ArchiveOperationResult(
            sourceURL: archiveURL,
            destinationURL: destinationFile,
            action: .extract,
            isSuccess: true,
            message: "Saved to \(destinationFile.path)"
        )
    }

    private func extractSevenZ(
        _ archiveURL: URL,
        to outputFolder: URL,
        progressHandler: ((ArchiveOperationProgress) -> Void)?
    ) throws -> ArchiveOperationResult {
        guard let executablePath = Self.sevenZipExecutablePath() else {
            throw ArchiveServiceError.sevenZipToolMissing
        }

        let destinationFolder = uniqueDestination(
            in: outputFolder,
            baseName: extractionBaseName(for: archiveURL, format: .sevenZ),
            pathExtension: nil
        )

        try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        try runProcessStreaming(
            executablePath: executablePath,
            arguments: ["x", archiveURL.path, "-o\(destinationFolder.path)", "-y"],
            currentDirectory: nil,
            estimatedTotalUnits: nil,
            shouldCountLine: { _ in false },
            progressFromLine: { line in
                Self.parseSevenZipPercentage(from: line)
            },
            progressHandler: progressHandler
        )

        return ArchiveOperationResult(
            sourceURL: archiveURL,
            destinationURL: destinationFolder,
            action: .extract,
            isSuccess: true,
            message: "Saved to \(destinationFolder.path)"
        )
    }

    private func validateOutputFolder(_ folderURL: URL) throws {
        var isDirectory = ObjCBool(false)
        let exists = fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory)

        guard exists, isDirectory.boolValue else {
            throw ArchiveServiceError.missingOutputFolder
        }
    }

    private func uniqueDestination(in folder: URL, baseName: String, pathExtension: String?) -> URL {
        var attempt = 0

        while true {
            let suffix: String
            switch attempt {
            case 0:
                suffix = ""
            case 1:
                suffix = " copy"
            default:
                suffix = " copy \(attempt)"
            }

            let candidateName = baseName + suffix
            let candidateURL: URL

            if let pathExtension, !pathExtension.isEmpty {
                candidateURL = folder.appendingPathComponent(candidateName).appendingPathExtension(pathExtension)
            } else {
                candidateURL = folder.appendingPathComponent(candidateName)
            }

            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }

            attempt += 1
        }
    }

    private func extractionBaseName(for archiveURL: URL, format: ArchiveFormat) -> String {
        let lowercasedName = archiveURL.lastPathComponent.lowercased()

        switch format {
        case .tarGz:
            if lowercasedName.hasSuffix(".tar.gz") {
                return String(archiveURL.lastPathComponent.dropLast(7))
            }
            if lowercasedName.hasSuffix(".tgz") {
                return String(archiveURL.lastPathComponent.dropLast(4))
            }
            return archiveURL.deletingPathExtension().lastPathComponent

        case .gzip:
            return archiveURL.deletingPathExtension().lastPathComponent

        default:
            return archiveURL.deletingPathExtension().lastPathComponent
        }
    }

    private func normalizedArchiveBaseName(_ input: String?) -> String? {
        guard let input else {
            return nil
        }

        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let invalidCharacterSet = CharacterSet(charactersIn: "/\\:")
        let sanitized = trimmed.components(separatedBy: invalidCharacterSet).joined(separator: "_")
        return sanitized.isEmpty ? nil : sanitized
    }

    private func commonParentFolder(for urls: [URL]) -> URL {
        let parentComponents = urls.map { $0.deletingLastPathComponent().pathComponents }
        var commonComponents = parentComponents.first ?? ["/"]

        for components in parentComponents.dropFirst() {
            while !components.starts(with: commonComponents) && !commonComponents.isEmpty {
                commonComponents.removeLast()
            }
        }

        guard !commonComponents.isEmpty else {
            return URL(fileURLWithPath: "/")
        }

        return commonComponents.dropFirst().reduce(URL(fileURLWithPath: "/")) { partialURL, component in
            partialURL.appendingPathComponent(component)
        }
    }

    private func relativePath(for itemURL: URL, from parentFolder: URL) -> String {
        let parentComponents = parentFolder.pathComponents
        let itemComponents = itemURL.pathComponents
        let relativeComponents = itemComponents.dropFirst(parentComponents.count)
        return relativeComponents.joined(separator: "/")
    }

    private func totalProgressUnits(for itemURLs: [URL]) -> Int {
        let total = itemURLs.reduce(0) { partialResult, url in
            partialResult + progressUnits(for: url)
        }
        return max(total, 1)
    }

    private func progressUnits(for url: URL) -> Int {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return 1
        }

        if !isDirectory.boolValue {
            return 1
        }

        let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var count = 0
        while enumerator?.nextObject() != nil {
            count += 1
        }

        return max(count, 1)
    }

    private func countOutputLines(executablePath: String, arguments: [String]) throws -> Int {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw ArchiveServiceError.extractionFailed(error.localizedDescription)
        }

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData + errorData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw ArchiveServiceError.extractionFailed(output.trimmingCharacters(in: .whitespacesAndNewlines))
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
        currentDirectory: URL?,
        estimatedTotalUnits: Int?,
        shouldCountLine: @escaping (String) -> Bool,
        progressFromLine: ((String) -> Double?)?,
        progressHandler: ((ArchiveOperationProgress) -> Void)?
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let syncQueue = DispatchQueue(label: "MarkMacZip.ProcessStreaming")
        var stdoutBuffer = ""
        var stderrBuffer = ""
        var combinedOutput = ""
        var countedUnits = 0

        func handleLine(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            combinedOutput += trimmed + "\n"

            if let progressFromLine,
               let fraction = progressFromLine(trimmed) {
                progressHandler?(ArchiveOperationProgress(fractionCompleted: min(max(fraction, 0), 1), detail: trimmed))
                return
            }

            guard let estimatedTotalUnits, shouldCountLine(trimmed) else {
                progressHandler?(ArchiveOperationProgress(fractionCompleted: nil, detail: trimmed))
                return
            }

            countedUnits += 1
            let fraction = Double(countedUnits) / Double(max(estimatedTotalUnits, 1))
            progressHandler?(ArchiveOperationProgress(fractionCompleted: min(max(fraction, 0), 0.99), detail: trimmed))
        }

        func consume(_ data: Data, into bufferKeyPath: WritableKeyPath<(String, String), String>) {
            guard !data.isEmpty else { return }

            syncQueue.sync {
                var pair = (stdoutBuffer, stderrBuffer)
                var buffer = pair[keyPath: bufferKeyPath]
                buffer += String(decoding: data, as: UTF8.self)

                while let newlineRange = buffer.range(of: "\n") {
                    let line = String(buffer[..<newlineRange.lowerBound])
                    handleLine(line)
                    buffer.removeSubrange(...newlineRange.lowerBound)
                }

                pair[keyPath: bufferKeyPath] = buffer
                stdoutBuffer = pair.0
                stderrBuffer = pair.1
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            consume(data, into: \.0)
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            consume(data, into: \.1)
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch let error as CocoaError where error.code == .fileWriteNoPermission || error.code == .fileReadNoPermission {
            throw ArchiveServiceError.permissionDenied(currentDirectory?.path ?? executablePath)
        } catch {
            throw ArchiveServiceError.compressionFailed(error.localizedDescription)
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        consume(stdoutPipe.fileHandleForReading.readDataToEndOfFile(), into: \.0)
        consume(stderrPipe.fileHandleForReading.readDataToEndOfFile(), into: \.1)

        syncQueue.sync {
            if !stdoutBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                handleLine(stdoutBuffer)
                stdoutBuffer = ""
            }

            if !stderrBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                handleLine(stderrBuffer)
                stderrBuffer = ""
            }
        }

        progressHandler?(ArchiveOperationProgress(fractionCompleted: 1, detail: ""))

        guard process.terminationStatus == 0 else {
            let trimmedOutput = combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            if executablePath.contains("tar") || executablePath.contains("unzip") || executablePath.contains("gunzip") {
                throw ArchiveServiceError.extractionFailed(trimmedOutput.isEmpty ? "Please check the archive and try again." : trimmedOutput)
            }
            throw ArchiveServiceError.compressionFailed(trimmedOutput.isEmpty ? "Please check the selected files and try again." : trimmedOutput)
        }
    }

    private func runProcessWritingStdoutToFile(
        executablePath: String,
        arguments: [String],
        outputFile: URL,
        progressHandler: ((ArchiveOperationProgress) -> Void)?
    ) throws {
        fileManager.createFile(atPath: outputFile.path, contents: nil)
        let fileHandle = try FileHandle(forWritingTo: outputFile)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        progressHandler?(ArchiveOperationProgress(fractionCompleted: nil, detail: ""))

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            fileHandle.write(data)
        }

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            try? fileHandle.close()
            throw ArchiveServiceError.compressionFailed(error.localizedDescription)
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        let remainingData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        if !remainingData.isEmpty {
            fileHandle.write(remainingData)
        }

        try fileHandle.close()

        let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            try? fileManager.removeItem(at: outputFile)
            throw ArchiveServiceError.compressionFailed(errorText.isEmpty ? "Please check the selected files and try again." : errorText)
        }

        progressHandler?(ArchiveOperationProgress(fractionCompleted: 1, detail: ""))
    }

    private func friendlyErrorMessage(for error: Error) -> String {
        if let archiveError = error as? ArchiveServiceError {
            return archiveError.localizedDescription
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain,
           (nsError.code == CocoaError.fileWriteNoPermission.rawValue || nsError.code == CocoaError.fileReadNoPermission.rawValue) {
            return ArchiveServiceError.permissionDenied(nsError.userInfo[NSFilePathErrorKey] as? String ?? "this location").localizedDescription
        }

        return error.localizedDescription
    }

    private static func sevenZipExecutablePath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/7zz",
            "/usr/local/bin/7zz",
            "/opt/homebrew/bin/7z",
            "/usr/local/bin/7z"
        ]

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        return nil
    }

    private static func parseSevenZipPercentage(from line: String) -> Double? {
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
