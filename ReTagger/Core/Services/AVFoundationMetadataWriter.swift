//
//  AVFoundationMetadataWriter.swift
//  ReTagger
//
//  默认使用 AVFoundation 导出策略写入元数据。
//

import Foundation
import AVFoundation
import UniformTypeIdentifiers
import OSLog

@MainActor
final class AVFoundationMetadataWriter: MetadataWriter {
    private let supportedFileExtensions: Set<String> = [
        "mp3",
        "m4a",
        "wav",
        "wave",
        "aif",
        "aiff",
        "caf"
    ]

    func write(_ metadata: AudioMetadata, to url: URL) async throws {
        let fileExtension = url.pathExtension.lowercased()
        guard supportedFileExtensions.contains(fileExtension) else {
            throw ReTaggerError.metadataUnsupportedFormat(url)
        }
        let preferredExtension = normalizedFileExtension(fileExtension)

        let asset = AVURLAsset(url: url)

        var metadataItems: [AVMetadataItem] = []

        if let title = metadata.finalTitle {
            metadataItems.append(createMetadataItem(for: .commonKeyTitle, value: title))
        }

        if let artist = metadata.finalArtist {
            metadataItems.append(createMetadataItem(for: .commonKeyArtist, value: artist))
        }

        if let album = metadata.finalAlbum {
            metadataItems.append(createMetadataItem(for: .commonKeyAlbumName, value: album))
        }

        if let genre = metadata.finalGenre {
            metadataItems.append(createMetadataItem(for: .commonKeyType, value: genre))
        }

        if let year = metadata.finalYear {
            metadataItems.append(createMetadataItem(for: .commonKeyCreationDate, value: year))
        }

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw ReTaggerError.metadataWriteError(url)
        }

        let supportedTypes = exportSession.supportedFileTypes
        let supportedTypeNames = supportedTypes.map(\.rawValue).joined(separator: ",")
        Logger.metadata.debug("Export supported types for \(url.lastPathComponent): \(supportedTypeNames)")

        let outputType = try resolveOutputType(
            for: url,
            preferredExtension: preferredExtension,
            supportedTypes: supportedTypes
        )
        Logger.metadata.debug("Using export output type: \(outputType.rawValue)")

        let tempURL = makeTemporaryURL(for: outputType)

        exportSession.metadata = metadataItems

        do {
            try await exportSession.export(to: tempURL, as: outputType)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw ReTaggerError.metadataWriteError(url)
        }

        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw ReTaggerError.metadataWriteError(url)
        }
    }

    // MARK: - Helpers

    private func createMetadataItem(for key: AVMetadataKey, value: String) -> AVMetadataItem {
        let item = AVMutableMetadataItem()
        item.keySpace = .common
        item.key = key as NSString
        item.value = value as NSString
        return item
    }

    private func resolveOutputType(
        for url: URL,
        preferredExtension: String,
        supportedTypes: [AVFileType]
    ) throws -> AVFileType {
        guard !supportedTypes.isEmpty else {
            throw ReTaggerError.metadataWriteError(url)
        }

        if preferredExtension == "mp3" {
            if supportedTypes.contains(.mp3) {
                return .mp3
            }
            if let mp3Like = supportedTypes.first(where: { $0.rawValue.lowercased().contains("mp3") }) {
                return mp3Like
            }
            Logger.metadata.error("AVFoundation cannot export metadata for \(url.lastPathComponent, privacy: .public)")
            throw ReTaggerError.metadataUnsupportedFormat(url)
        }

        if !preferredExtension.isEmpty {
            for type in supportedTypes {
                guard let utType = UTType(type.rawValue) else { continue }
                if utType.tags[.filenameExtension]?.contains(preferredExtension) == true {
                    return type
                }
            }
        }

        guard let fallback = supportedTypes.first else {
            throw ReTaggerError.metadataWriteError(url)
        }
        return fallback
    }

    private func makeTemporaryURL(for fileType: AVFileType) -> URL {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let filename = UUID().uuidString
        let preferredExtension: String = {
            if let utType = UTType(fileType.rawValue),
               let ext = utType.preferredFilenameExtension {
                return ext
            }
            return fileType.pathExtensionFallback
        }()
        return temporaryDirectory
            .appendingPathComponent(filename)
            .appendingPathExtension(preferredExtension)
    }

    private func normalizedFileExtension(_ ext: String) -> String {
        switch ext {
        case "wave":
            return "wav"
        case "aif":
            return "aiff"
        default:
            return ext
        }
    }
}

private extension AVFileType {
    var pathExtensionFallback: String {
        switch self {
        case .mp3:
            return "mp3"
        case .m4a:
            return "m4a"
        case .wav:
            return "wav"
        case .aiff:
            return "aiff"
        case .caf:
            return "caf"
        default:
            if rawValue.contains("m4a") {
                return "m4a"
            }
            if rawValue.contains("wav") {
                return "wav"
            }
            return "tmp"
        }
    }
}
