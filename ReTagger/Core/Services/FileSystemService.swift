//
//  FileSystemService.swift
//  ReTagger
//
//  Service for file system operations
//

import Foundation
import AppKit
import OSLog

/// Protocol defining file system operations
protocol FileSystemServiceProtocol {
    func selectDirectory() async -> URL?
    func selectFilesOrDirectories() async -> [URL]?
    func scanForAudioFiles(at url: URL) async throws -> [URL]
    func checkPermissions(for url: URL) -> FilePermissions
    func renameFile(from: URL, to: String) async throws -> URL
    func moveFile(from: URL, toDirectory: URL) async throws -> URL
    func createDirectory(at url: URL) async throws
    func createBackup(of url: URL, backupLocation: URL?, workspaceRoot: URL?) async throws -> URL
    func restoreBackup(from backupURL: URL, to destinationURL: URL) async throws
    func requestAccess(to directory: URL, message: String?) async -> URL?
}

/// File permission information
struct FilePermissions {
    let canRead: Bool
    let canWrite: Bool

    var description: String {
        switch (canRead, canWrite) {
        case (true, true): return "Read/Write"
        case (true, false): return "Read Only"
        case (false, true): return "Write Only"
        case (false, false): return "No Access"
        }
    }
}

// MARK: - FileSystemService Implementation

@MainActor
class FileSystemService: FileSystemServiceProtocol {

    private let fileManager = FileManager.default
    private let localizationManager: LocalizationManager

    init(localizationManager: LocalizationManager? = nil) {
        self.localizationManager = localizationManager ?? LocalizationManager(language: .simplifiedChinese)
    }
    
    func selectDirectory() async -> URL? {
        await withCheckedContinuation { continuation in
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true

            let response = panel.runModal()
            if response == .OK {
                continuation.resume(returning: panel.url)
            } else {
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Directory Selection

    func selectFilesOrDirectories() async -> [URL]? {
        Logger.fileSystem.info("Opening file/directory selection dialog")

        let panel = NSOpenPanel()
        panel.message = localizationManager.string("filesystem.select_directory.message")
        panel.prompt = localizationManager.string("filesystem.select_directory.confirm")
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = true

        let response = panel.runModal()

        if response == .OK, !panel.urls.isEmpty {
            Logger.fileSystem.info("Items selected: \(panel.urls.map(\.path))")
            return panel.urls
        } else {
            Logger.fileSystem.debug("Selection cancelled")
            return nil
        }
    }

    // MARK: - File Scanning

    func scanForAudioFiles(at url: URL) async throws -> [URL] {
        let startTime = Logger.performance.logOperationStart("ScanAudioFiles")
        Logger.fileSystem.info("Scanning directory for audio files: \(url.path)")

        guard url.isDirectory || url.isSupportedAudioFile else {
            Logger.fileSystem.error("Selected path is neither a directory nor a supported audio file: \(url.path)")
            throw ReTaggerError.fileSystemError("Selected path is neither a directory nor a supported audio file")
        }

        // Start security-scoped access
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let permissions = checkPermissions(for: url)
        Logger.fileSystem.debug("Directory permissions: \(permissions.description)")

        guard permissions.canRead else {
            Logger.fileSystem.error("Permission denied for directory: \(url.path)")
            throw ReTaggerError.permissionDenied(url)
        }

        let targetURL = url
        // Use a local logger in the detached task to avoid MainActor isolation issues with the static logger
        let audioFiles: [URL] = try await Task.detached(priority: .userInitiated) {
            let logger = Logger(subsystem: "vip.retagger.macapp", category: "FileSystem")
            
            // 子线程也必须显式激活 security-scoped 授权，确保在沙盒环境下能读取文件
            let threadHasAccess = targetURL.startAccessingSecurityScopedResource()
            defer {
                if threadHasAccess {
                    targetURL.stopAccessingSecurityScopedResource()
                }
            }

            var results: [URL] = []
            
            if !targetURL.isDirectory {
                if targetURL.isSupportedAudioFile {
                    results.append(targetURL)
                }
                return results
            }

            let enumerationManager = FileManager()

            guard let enumerator = enumerationManager.enumerator(
                at: targetURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                throw ReTaggerError.fileSystemError("Failed to create directory enumerator")
            }

            while let next = enumerator.nextObject() as? URL {
                do {
                    let resourceValues = try next.resourceValues(forKeys: [.isRegularFileKey])
                    // Use local helper to avoid MainActor isolation check on URL extension if it persists
                    if resourceValues.isRegularFile == true {
                        let ext = next.pathExtension.lowercased()
                        if AudioFormatSupport.contains(extension: ext) {
                             results.append(next)
                        }
                    }
                } catch {
                    logger.debug("Skipping inaccessible file: \(next.path)")
                    continue
                }
            }

            return results
        }.value

        Logger.fileSystem.info("Found \(audioFiles.count) supported audio files in directory")
        Logger.performance.logOperationEnd("ScanAudioFiles", startTime: startTime)

        return audioFiles
    }

    // MARK: - Permissions

    func checkPermissions(for url: URL) -> FilePermissions {
        let canRead = fileManager.isReadableFile(atPath: url.path)
        let canWrite = fileManager.isWritableFile(atPath: url.path)
        return FilePermissions(canRead: canRead, canWrite: canWrite)
    }

    // MARK: - File Operations

    func renameFile(from sourceURL: URL, to newName: String) async throws -> URL {
        Logger.fileSystem.info("Renaming file: \(sourceURL.lastPathComponent) -> \(newName)")

        let directory = sourceURL.deletingLastPathComponent()
        var destinationURL = directory.appendingPathComponent(newName)

        let isCaseOnlyChange = sourceURL.lastPathComponent.lowercased() == newName.lowercased()

        // Handle file conflict if destination already exists and it's not a case-only change
        if !isCaseOnlyChange && fileManager.fileExists(atPath: destinationURL.path) {
            destinationURL = try resolveFileConflict(at: destinationURL)
        }

        do {
            if isCaseOnlyChange && sourceURL.lastPathComponent != newName {
                // macOS APFS is case-insensitive but case-preserving.
                // A direct move from "song.mp3" to "Song.mp3" might fail or be ignored.
                // We use a temporary name to force the case change.
                let tempName = ".\(UUID().uuidString)_\(newName)"
                let tempURL = directory.appendingPathComponent(tempName)
                try fileManager.moveItem(at: sourceURL, to: tempURL)
                try fileManager.moveItem(at: tempURL, to: destinationURL)
            } else {
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
            }
            Logger.fileSystem.info("File renamed successfully")
            return destinationURL
        } catch {
            Logger.fileSystem.logOperationFailed("RenameFile", error: error)
            throw ReTaggerError.fileSystemError("Failed to rename file: \(error.localizedDescription)")
        }
    }

    func moveFile(from sourceURL: URL, toDirectory directoryURL: URL) async throws -> URL {
        // Ensure destination directory exists
        try await createDirectory(at: directoryURL)

        let fileName = sourceURL.lastPathComponent
        let destinationURL = directoryURL.appendingPathComponent(fileName)

        // Handle file conflict
        let finalDestination = try resolveFileConflict(at: destinationURL)

        do {
            try fileManager.moveItem(at: sourceURL, to: finalDestination)
            return finalDestination
        } catch {
            throw ReTaggerError.fileSystemError("Failed to move file: \(error.localizedDescription)")
        }
    }

    func createDirectory(at url: URL) async throws {
        guard !fileManager.fileExists(atPath: url.path) else {
            return // Directory already exists
        }

        do {
            try fileManager.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw ReTaggerError.fileSystemError("Failed to create directory: \(error.localizedDescription)")
        }
    }

    // MARK: - Backup

    func createBackup(of url: URL, backupLocation: URL? = nil, workspaceRoot: URL? = nil) async throws -> URL {
        Logger.fileSystem.info("Creating backup for file: \(url.lastPathComponent)")

        var backupDir: URL
        if let customBackupLocation = backupLocation {
            if customBackupLocation.lastPathComponent == "ReTagger" {
                backupDir = customBackupLocation
            } else {
                backupDir = customBackupLocation.appendingPathComponent("ReTagger")
            }
        } else {
            // Use user's Desktop/ReTagger folder by default
            backupDir = defaultBackupDirectory()
        }

        if let root = workspaceRoot {
            let rootParentPath = root.standardizedFileURL.deletingLastPathComponent().path
            let filePath = url.standardizedFileURL.path
            if filePath.hasPrefix(rootParentPath), filePath.count > rootParentPath.count {
                let relativePath = String(filePath.dropFirst(rootParentPath.count))
                let cleanRelativePath = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
                let relativeDirectory = (cleanRelativePath as NSString).deletingLastPathComponent
                if !relativeDirectory.isEmpty {
                    backupDir = backupDir.appendingPathComponent(relativeDirectory)
                }
            }
        }

        // Create backup directory if needed
        do {
            try await createDirectory(at: backupDir)
        } catch {
            // Attempt to request permission if creation fails
            Logger.fileSystem.warning("Failed to create backup directory, attempting to request permission: \(error.localizedDescription)")
            
            let message = localizationManager.string(
                "filesystem.backup_permission_prompt",
                arguments: backupDir.lastPathComponent
            )
            if let grantedURL = await requestAccess(to: backupDir, message: message) {
                // Retry creation with granted permission
                let _ = grantedURL.startAccessingSecurityScopedResource()
                defer { grantedURL.stopAccessingSecurityScopedResource() }
                
                // If the user selected a parent directory, we still need to ensure the target directory exists
                try await createDirectory(at: backupDir)
            } else {
                throw error
            }
        }

        // Create timestamped backup
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = dateFormatter.string(from: Date())

        let fileName = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension
        let backupFileName = "\(fileName)_backup_\(timestamp).\(fileExtension)"
        let backupURL = backupDir.appendingPathComponent(backupFileName)

        do {
            try fileManager.copyItem(at: url, to: backupURL)
            Logger.fileSystem.info("Backup created successfully at: \(backupURL.path)")
            return backupURL
        } catch {
            Logger.fileSystem.logOperationFailed("CreateBackup", error: error)
            throw ReTaggerError.backupFailed(url)
        }
    }

    func restoreBackup(from backupURL: URL, to destinationURL: URL) async throws {
        Logger.fileSystem.info("Restoring backup for file: \(destinationURL.lastPathComponent)")
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: backupURL, to: destinationURL)
            Logger.fileSystem.info("Backup restored to: \(destinationURL.path)")
        } catch {
            Logger.fileSystem.logOperationFailed("RestoreBackup", error: error)
            throw ReTaggerError.fileSystemError("无法从备份恢复文件：\(error.localizedDescription)")
        }
    }

    // MARK: - Helper Methods

    private func resolveFileConflict(at url: URL) throws -> URL {
        var destinationURL = url
        var counter = 1

        while fileManager.fileExists(atPath: destinationURL.path) {
            let fileName = url.deletingPathExtension().lastPathComponent
            let fileExtension = url.pathExtension
            let newFileName = "\(fileName)_\(counter).\(fileExtension)"
            destinationURL = url.deletingLastPathComponent().appendingPathComponent(newFileName)
            counter += 1

            // Safety check to avoid infinite loop
            if counter > 1000 {
                throw ReTaggerError.fileSystemError("Too many file conflicts")
            }
        }

        return destinationURL
    }

    // MARK: - Permissions Helpers

    func requestAccess(to directory: URL, message: String? = nil) async -> URL? {
        let panel = NSOpenPanel()
        panel.message = message ?? localizationManager.string("filesystem.request_access.message")
        panel.prompt = localizationManager.string("filesystem.request_access.confirm")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        // 直接定位到该父目录本身，以便用户能够直接一键点击“确认/授权”
        panel.directoryURL = directory

        let suggestedName = directory.lastPathComponent.isEmpty ? directory.path : directory.lastPathComponent
        panel.nameFieldStringValue = suggestedName

        let response = panel.runModal()
        guard response == .OK, let selectedURL = panel.url else {
            return nil
        }
        return selectedURL
    }
    private func defaultBackupDirectory() -> URL {
        let desktopPath = fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first!
        return desktopPath.appendingPathComponent("ReTagger")
    }

    private func preferredParentDirectory(for directory: URL) -> URL? {
        let standardizedDirectory = directory.standardizedFileURL
        let defaultBackupDirectoryURL = defaultBackupDirectory().standardizedFileURL

        if standardizedDirectory == defaultBackupDirectoryURL {
            return defaultBackupDirectoryURL.deletingLastPathComponent()
        }

        let parentDirectory = directory.deletingLastPathComponent()
        guard parentDirectory.path != directory.path else {
            return nil
        }
        return parentDirectory
    }
}


