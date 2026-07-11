//
//  URL+Extensions.swift
//  ReTagger
//
//  Extensions for URL
//

import Foundation

extension URL {
    /// 判断 URL 是否指向支持的音频文件
    nonisolated var isSupportedAudioFile: Bool {
        Constants.FileSystem.supportedAudioExtensions.contains(pathExtension.lowercased())
    }

    /// 判断是否为 MP3 文件（向后兼容）
    nonisolated var isMP3File: Bool {
        pathExtension.compare("mp3", options: .caseInsensitive) == .orderedSame
    }

    /// Check if URL is a directory
    nonisolated var isDirectory: Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return isDir.boolValue
    }

    /// Get file size in bytes
    nonisolated var fileSize: Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? Int64 else {
            return nil
        }
        return size
    }

    /// Format file size as human-readable string
    var fileSizeFormatted: String {
        guard let size = fileSize else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    /// Check whether the URL is the same as or a descendant of a directory URL.
    func isSameOrDescendant(of directory: URL) -> Bool {
        let selfComponents = standardizedFileURL.pathComponents
        let directoryComponents = directory.standardizedFileURL.pathComponents

        guard directoryComponents.count <= selfComponents.count else {
            return false
        }

        return selfComponents.starts(with: directoryComponents)
    }

    /// Convert URL to the exact filesystem representation (NFD on macOS) to avoid sandbox access issues caused by NFC/NFD normalization mismatch.
    var fileSystemNormalized: URL {
        let isDir = self.isDirectory
        return self.withUnsafeFileSystemRepresentation { ptr in
            guard let ptr = ptr else { return self }
            return URL(fileURLWithFileSystemRepresentation: ptr, isDirectory: isDir, relativeTo: nil)
        }
    }
}
