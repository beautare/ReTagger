//
//  TagLibMetadataWriter.swift
//  ReTagger
//
//  使用 TagLib 写入音频标签，兼容多种编码与变种帧。
//

import Foundation
import OSLog

@MainActor
final class TagLibMetadataWriter: MetadataWriter {

    func write(_ metadata: AudioMetadata, to url: URL) async throws {
        guard url.isSupportedAudioFile else {
            throw ReTaggerError.metadataWriteError(url)
        }

        let title = metadata.finalTitle?.nonEmpty
        let artist = metadata.finalArtist?.nonEmpty
        let album = metadata.finalAlbum?.nonEmpty
        let genre = metadata.finalGenre?.nonEmpty
        let year = metadata.finalYear?.nonEmpty
        var bridgeError: NSError?
        let success = TagLibBridgeWriteMetadata(
            url.path,
            title,
            artist,
            album,
            genre,
            year,
            &bridgeError
        )

        if success {
            Logger.metadata.debug("TagLib 写入音频标签成功：\(url.lastPathComponent, privacy: .public)")
            return
        }

        if let error = bridgeError {
            Logger.metadata.error("TagLib 写入失败 [\(error.code)]: \(error.localizedDescription, privacy: .public)")
            switch TagLibBridgeErrorCode(rawValue: error.code) {
            case .invalidInput:
                throw ReTaggerError.fileSystemError("无效的音频文件路径")
            case .openFile:
                throw ReTaggerError.metadataUnsupportedFormat(url)
            case .save:
                throw ReTaggerError.metadataWriteError(url)
            case .read:
                // 读取错误在写入场景不应该发生，但如果发生则视为写入失败
                throw ReTaggerError.metadataWriteError(url)
            case .none:
                throw ReTaggerError.fileSystemError("TagLib 写入失败：\(error.localizedDescription)")
            @unknown default:
                throw ReTaggerError.fileSystemError("TagLib 写入失败：\(error.localizedDescription)")
            }
        } else {
            Logger.metadata.error("TagLib 写入失败：未知错误")
            throw ReTaggerError.metadataWriteError(url)
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
