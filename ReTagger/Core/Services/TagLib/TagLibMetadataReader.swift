//
//  TagLibMetadataReader.swift
//  ReTagger
//
//  使用 TagLib 读取音频标签，支持 FLAC、Ogg、Opus 等 AVFoundation 支持不佳的格式。
//

import Foundation
import OSLog

/// TagLib 读取的原始元数据结果
nonisolated struct TagLibRawMetadata {
    let title: String?
    let artist: String?
    let album: String?
    let genre: String?
    let year: UInt
    let bitrate: Int
    let sampleRate: Int
    let channels: Int
    let duration: Int  // 秒
}

/// nonisolated：TagLib 桥接为无共享状态的同步 C 调用，需支持在后台执行器并发读取
nonisolated final class TagLibMetadataReader {
    
    /// 使用 TagLib 读取音频文件的元数据
    /// - Parameter url: 音频文件 URL
    /// - Returns: 读取到的原始元数据
    /// - Throws: 读取失败时抛出错误
    func read(from url: URL) throws -> TagLibRawMetadata {
        guard url.isSupportedAudioFile else {
            throw ReTaggerError.metadataReadError(url)
        }
        
        var bridgeError: NSError?
        guard let result = TagLibBridgeReadMetadata(url.path, &bridgeError) else {
            if let error = bridgeError {
                Logger.metadata.error("TagLib 读取失败 [\(error.code)]: \(error.localizedDescription, privacy: .public)")
                switch TagLibBridgeErrorCode(rawValue: error.code) {
                case .invalidInput:
                    throw ReTaggerError.fileSystemError("无效的音频文件路径")
                case .openFile:
                    throw ReTaggerError.metadataUnsupportedFormat(url)
                case .read:
                    throw ReTaggerError.metadataReadError(url)
                case .save, .none:
                    throw ReTaggerError.metadataReadError(url)
                @unknown default:
                    throw ReTaggerError.metadataReadError(url)
                }
            } else {
                Logger.metadata.error("TagLib 读取失败：未知错误")
                throw ReTaggerError.metadataReadError(url)
            }
        }
        
        Logger.metadata.debug("TagLib 读取音频标签成功：\(url.lastPathComponent, privacy: .public)")
        
        return TagLibRawMetadata(
            title: result.title,
            artist: result.artist,
            album: result.album,
            genre: result.genre,
            year: result.year,
            bitrate: result.bitrate,
            sampleRate: result.sampleRate,
            channels: result.channels,
            duration: result.duration
        )
    }
    
    /// 检查 TagLib 是否可用（库是否已加载）
    func isAvailable() -> Bool {
        // 尝试读取一个不存在的文件来触发库加载
        // 如果库加载失败，会返回特定错误
        var error: NSError?
        _ = TagLibBridgeReadMetadata("", &error)
        
        // 如果错误是 invalidInput，说明库已加载成功（只是输入无效）
        // 如果是 openFile 且包含 "libtag_c" 相关信息，说明库加载失败
        if let error = error {
            if error.code == TagLibBridgeErrorCode.invalidInput.rawValue {
                return true
            }
            if error.localizedDescription.contains("libtag_c") ||
               error.localizedDescription.contains("符号缺失") {
                return false
            }
        }
        return true
    }
}
