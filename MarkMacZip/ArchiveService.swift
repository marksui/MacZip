import Foundation

enum ArchiveServiceError: LocalizedError {
    case invalidFileType
    case missingOutputFolder
    case permissionDenied(String)
    case extractionFailed(String)
    case compressionFailed(String)
    case unsupportedSelection

    var errorDescription: String? {
        switch self {
        case .invalidFileType:
            return "Please choose a .zip file to extract."
        case .missingOutputFolder:
            return AppStrings.missingOutputFolder
        case let .permissionDenied(path):
            return "MarkMacZip does not have permission to use \(path)."
        case let .extractionFailed(reason):
            return "MarkMacZip could not extract the archive. \(reason)"
        case let .compressionFailed(reason):
            return "MarkMacZip could not create the zip file. \(reason)"
        case .unsupportedSelection:
            return "Please choose at least one file or folder."
        }
    }
}

struct ArchiveService {
    private var fileManager: FileManager { .default }

    func extractArchives(_ archiveURLs: [URL], to outputFolder: URL) -> [ArchiveOperationResult] {
        archiveURLs.map { archiveURL in
            do {
                try validateOutputFolder(outputFolder)
                guard archiveURL.pathExtension.lowercased() == "zip" else {
                    throw ArchiveServiceError.invalidFileType
                }

                let folderName = archiveURL.deletingPathExtension().lastPathComponent
                let destinationFolder = uniqueDestination(
                    in: outputFolder,
                    baseName: folderName,
                    pathExtension: nil
                )

                try fileManager.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

                try runProcess(
                    executablePath: "/usr/bin/ditto",
                    arguments: ["-x", "-k", archiveURL.path, destinationFolder.path]
                )

                return ArchiveOperationResult(
                    sourceURL: archiveURL,
                    destinationURL: destinationFolder,
                    action: .extract,
                    isSuccess: true,
                    message: "Saved to \(destinationFolder.path)"
                )
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
    }

    func compressItems(_ itemURLs: [URL], to outputFolder: URL, password: String? = nil) -> [ArchiveOperationResult] {
        do {
            try validateOutputFolder(outputFolder)

            guard !itemURLs.isEmpty else {
                throw ArchiveServiceError.unsupportedSelection
            }

            let parentFolder = commonParentFolder(for: itemURLs)
            let archiveName = suggestedArchiveName(for: itemURLs)
            let destinationURL = uniqueDestination(
                in: outputFolder,
                baseName: archiveName,
                pathExtension: "zip"
            )

            let relativePaths = itemURLs.map { relativePath(for: $0, from: parentFolder) }

            var zipArguments = ["-r", "-y"]
            if let password, !password.isEmpty {
                zipArguments += ["-P", password]
            }
            zipArguments.append(destinationURL.path)
            zipArguments += relativePaths

            try runProcess(
                executablePath: "/usr/bin/zip",
                arguments: zipArguments,
                currentDirectory: parentFolder
            )

            return [
                ArchiveOperationResult(
                    sourceURL: itemURLs.first ?? parentFolder,
                    destinationURL: destinationURL,
                    action: .compress,
                    isSuccess: true,
                    message: "Saved to \(destinationURL.path)"
                )
            ]
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

    private func suggestedArchiveName(for itemURLs: [URL]) -> String {
        if itemURLs.count == 1 {
            return itemURLs[0].lastPathComponent
        }

        return "Archive"
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

    private func runProcess(
        executablePath: String,
        arguments: [String],
        currentDirectory: URL? = nil
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
            process.waitUntilExit()
        } catch let error as CocoaError where error.code == .fileWriteNoPermission || error.code == .fileReadNoPermission {
            throw ArchiveServiceError.permissionDenied(currentDirectory?.path ?? executablePath)
        } catch {
            throw ArchiveServiceError.compressionFailed(error.localizedDescription)
        }

        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()
        let outputText = String(data: outputData + errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            if executablePath.contains("ditto") {
                throw ArchiveServiceError.extractionFailed(outputText.isEmpty ? "Please check the archive and try again." : outputText)
            }

            throw ArchiveServiceError.compressionFailed(outputText.isEmpty ? "Please check the selected files and try again." : outputText)
        }
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
}
