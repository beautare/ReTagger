//
//  MetadataCacheService.swift
//  ReTagger
//
//  Provides caching for directory metadata reads with automatic invalidation
//

import Foundation

/// Cache manager for metadata reads to reduce repeated disk IO.
@MainActor
final class MetadataCacheService {

    struct CacheKey: Hashable {
        let directory: URL
        let includeSubdirectories: Bool

        init(directory: URL, includeSubdirectories: Bool) {
            self.directory = directory.standardizedFileURL
            self.includeSubdirectories = includeSubdirectories
        }
    }

    private struct CacheEntry {
        var files: [AudioMetadata]
        var monitor: DirectoryMonitor?
    }

    private let fileSystemService: FileSystemService
    private let metadataService: MetadataService

    private var cache: [CacheKey: CacheEntry] = [:]
    private var invalidKeys: Set<CacheKey> = []
    
    var onDirectoryChanged: ((URL) -> Void)?

    init(
        fileSystemService: FileSystemService,
        metadataService: MetadataService
    ) {
        self.fileSystemService = fileSystemService
        self.metadataService = metadataService
    }

    func metadata(
        for directory: URL,
        includeSubdirectories: Bool
    ) async throws -> [AudioMetadata] {
        let key = CacheKey(directory: directory, includeSubdirectories: includeSubdirectories)

        if let entry = cache[key], !invalidKeys.contains(key) {
            return entry.files
        }

        let audioURLs: [URL]
        if !directory.isDirectory {
            if directory.isSupportedAudioFile {
                audioURLs = [directory]
            } else {
                audioURLs = []
            }
        } else {
            if includeSubdirectories {
                audioURLs = try await fileSystemService.scanForAudioFiles(at: directory)
            } else {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles]
                )
                audioURLs = contents.filter { $0.isSupportedAudioFile }
            }
        }

        let metadataList = try await metadataService.batchReadMetadata(from: audioURLs)

        var entry = cache[key] ?? CacheEntry(files: [], monitor: nil)
        entry.files = metadataList

        entry.monitor?.stop()

        let monitorTarget = directory.isDirectory ? directory : directory.deletingLastPathComponent()
        let monitor = DirectoryMonitor(
            url: monitorTarget,
            includeSubdirectories: includeSubdirectories
        ) { [weak self] in
            Task { @MainActor in
                self?.invalidKeys.insert(key)
                self?.onDirectoryChanged?(directory)
            }
        }
        monitor.start()
        entry.monitor = monitor

        cache[key] = entry
        invalidKeys.remove(key)

        return metadataList
    }

    func invalidate(directory: URL) {
        cache.keys
            .filter { $0.directory.isSameOrDescendant(of: directory) }
            .forEach { invalidKeys.insert($0) }
    }

    func clearAll() {
        cache.values.forEach { $0.monitor?.stop() }
        cache.removeAll()
        invalidKeys.removeAll()
    }
}
