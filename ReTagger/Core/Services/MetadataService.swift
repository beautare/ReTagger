//
//  MetadataService.swift
//  ReTagger
//
//  Service for reading and writing audio metadata across supported formats
//

import Foundation
import AVFoundation
import OSLog
import CoreMedia

/// Protocol defining metadata operations
protocol MetadataServiceProtocol {
    func readMetadata(from url: URL) async throws -> AudioMetadata
    func writeMetadata(_ metadata: AudioMetadata, to url: URL) async throws
    func batchReadMetadata(from urls: [URL]) async throws -> [AudioMetadata]
    func validateMetadata(_ metadata: AudioMetadata) -> ValidationResult
}

/// Metadata validation result
struct ValidationResult {
    let isValid: Bool
    let errors: [String]
    let warnings: [String]

    static let valid = ValidationResult(isValid: true, errors: [], warnings: [])
}

// MARK: - MetadataService Implementation

@MainActor
class MetadataService: MetadataServiceProtocol {

    private let writer: any MetadataWriter

    init(writer: (any MetadataWriter)? = nil) {
        if let writer {
            self.writer = writer
        } else {
            let tagLibWriter = TagLibMetadataWriter()
            let fallbackWriter = AVFoundationMetadataWriter()
            self.writer = CompositeMetadataWriter(
                primary: tagLibWriter,
                fallback: fallbackWriter
            )
        }
    }

    // MARK: - Read Metadata

    /// 读取单个文件的元数据。
    /// nonisolated：TagLib 为同步 C 调用，放到后台执行器避免占用主线程。
    nonisolated func readMetadata(from url: URL) async throws -> AudioMetadata {
        guard url.isSupportedAudioFile else {
            throw ReTaggerError.metadataReadError(url)
        }

        // 获取文件属性
        let fileAttributes = try? FileManager.default.attributesOfItem(atPath: url.path)

        var metadata = AudioMetadata(
            filePath: url,
            fileName: url.lastPathComponent,
            fileSizeBytes: url.fileSize
        )

        // 提取文件日期
        if let fileAttributes = fileAttributes {
            metadata.fileCreationDate = fileAttributes[.creationDate] as? Date
            metadata.fileModificationDate = fileAttributes[.modificationDate] as? Date
        }

        // 默认格式为文件扩展名
        metadata.format = url.pathExtension.uppercased()

        // 第一步：尝试使用 TagLib 读取标签字段（对 FLAC/Ogg/Opus 等格式支持更好）
        let tagLibReader = TagLibMetadataReader()
        var tagLibSucceeded = false
        
        do {
            let tagLibResult = try tagLibReader.read(from: url)
            
            // 应用 TagLib 读取的标签
            metadata.originalTitle = tagLibResult.title
            metadata.originalArtist = tagLibResult.artist
            metadata.originalAlbum = tagLibResult.album
            metadata.originalGenre = tagLibResult.genre
            
            // 年份处理
            if tagLibResult.year > 0 {
                metadata.originalYear = String(tagLibResult.year)
            }
            
            // TagLib 也可以提供音频属性
            if tagLibResult.duration > 0 {
                metadata.duration = TimeInterval(tagLibResult.duration)
            }
            if tagLibResult.bitrate > 0 {
                metadata.bitrate = tagLibResult.bitrate
            }
            if tagLibResult.sampleRate > 0 {
                metadata.sampleRate = tagLibResult.sampleRate
            }
            
            tagLibSucceeded = true
            Logger.metadata.debug("TagLib 读取成功：\(url.lastPathComponent, privacy: .public)")
        } catch {
            Logger.metadata.debug("TagLib 读取失败，将使用 AVFoundation 回退：\(error.localizedDescription, privacy: .public)")
        }

        // 第二步：使用 AVFoundation 补充或回退读取
        // 即使 TagLib 成功，AVFoundation 也可能提供更精确的技术性元数据
        do {
            let asset = AVURLAsset(url: url)
            
            // 读取技术性元数据（AVFoundation 通常更精确）
            if let tracks = try? await asset.load(.tracks), let audioTrack = tracks.first {
                // 提取时长（如果 TagLib 没有提供或值为0）
                if metadata.duration == nil || metadata.duration == 0 {
                    if let duration = try? await asset.load(.duration) {
                        let durationSeconds = CMTimeGetSeconds(duration)
                        if durationSeconds.isFinite && durationSeconds > 0 {
                            metadata.duration = durationSeconds
                        }
                    }
                }

                // 提取位速率
                if metadata.bitrate == nil || metadata.bitrate == 0 {
                    if let estimatedDataRate = try? await audioTrack.load(.estimatedDataRate),
                       estimatedDataRate.isFinite,
                       estimatedDataRate > 0 {
                        metadata.bitrate = Int((estimatedDataRate / 1000.0).rounded())
                    }
                }

                // 提取采样率和格式
                if let formatDescriptions = try? await audioTrack.load(.formatDescriptions) {
                    for description in formatDescriptions {
                        guard let streamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description) else {
                            continue
                        }

                        let sampleRate = Double(streamBasicDescription.pointee.mSampleRate)
                        if sampleRate > 0 && (metadata.sampleRate == nil || metadata.sampleRate == 0) {
                            metadata.sampleRate = Int(sampleRate)
                        }

                        // 使用 AVFoundation 的格式标识（更准确）
                        let formatID = streamBasicDescription.pointee.mFormatID
                        let avFormat = formatIDToString(formatID)
                        if avFormat != "Unknown" {
                            metadata.format = avFormat
                        }

                        // 计算位速率（作为回退）
                        if metadata.bitrate == nil || metadata.bitrate == 0 {
                            let bytesPerFrame = Double(streamBasicDescription.pointee.mBytesPerFrame)
                            if sampleRate > 0, bytesPerFrame > 0 {
                                let bytesPerSecond = sampleRate * bytesPerFrame
                                let calculated = Int((bytesPerSecond * 8 / 1000.0).rounded())
                                if calculated > 0 {
                                    metadata.bitrate = calculated
                                }
                            }
                        }
                    }
                }
            }

            // 如果 TagLib 失败，使用 AVFoundation 读取标签字段作为回退
            if !tagLibSucceeded {
                let commonMetadata = try await asset.load(.commonMetadata)
                
                for item in commonMetadata {
                    guard let key = item.commonKey,
                          let value = try? await item.load(.stringValue) else {
                        continue
                    }

                    switch key {
                    case .commonKeyTitle:
                        metadata.originalTitle = value
                    case .commonKeyArtist:
                        metadata.originalArtist = value
                    case .commonKeyAlbumName:
                        metadata.originalAlbum = value
                    case .commonKeyType:
                        metadata.originalGenre = value
                    case .commonKeyCreationDate:
                        metadata.originalYear = extractYear(from: value)
                    default:
                        break
                    }
                }
                
                Logger.metadata.debug("AVFoundation 回退读取完成：\(url.lastPathComponent, privacy: .public)")
            }
        } catch {
            // AVFoundation 读取失败不是致命错误，如果 TagLib 已成功
            if !tagLibSucceeded {
                Logger.metadata.error("元数据读取完全失败：\(url.lastPathComponent, privacy: .public)")
                throw ReTaggerError.metadataReadError(url)
            }
            Logger.metadata.warning("AVFoundation 补充读取失败，但 TagLib 已成功：\(error.localizedDescription, privacy: .public)")
        }

        return metadata
    }

    /// 批量读取元数据：限流并发执行，结果保持输入顺序，扫描任务被取消时立即整体退出。
    /// 单文件读取失败不阻断批次，降级为 failed 状态占位。
    nonisolated func batchReadMetadata(from urls: [URL]) async throws -> [AudioMetadata] {
        let maxConcurrentReads = 4
        var results = [AudioMetadata?](repeating: nil, count: urls.count)

        try await withThrowingTaskGroup(of: (Int, AudioMetadata).self) { group in
            func addReadTask(at index: Int) {
                let url = urls[index]
                group.addTask {
                    do {
                        return (index, try await self.readMetadata(from: url))
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        var errorMetadata = AudioMetadata(
                            filePath: url,
                            fileName: url.lastPathComponent,
                            fileSizeBytes: url.fileSize
                        )
                        errorMetadata.processingState = .failed
                        errorMetadata.error = error.localizedDescription
                        return (index, errorMetadata)
                    }
                }
            }

            var nextIndex = 0
            while nextIndex < min(maxConcurrentReads, urls.count) {
                addReadTask(at: nextIndex)
                nextIndex += 1
            }

            while let (index, metadata) = try await group.next() {
                results[index] = metadata
                try Task.checkCancellation()
                if nextIndex < urls.count {
                    addReadTask(at: nextIndex)
                    nextIndex += 1
                }
            }
        }

        return results.compactMap { $0 }
    }

    // MARK: - Write Metadata

    func writeMetadata(_ metadata: AudioMetadata, to url: URL) async throws {
        try await writer.write(metadata, to: url)
    }

    // MARK: - Validation

    func validateMetadata(_ metadata: AudioMetadata) -> ValidationResult {
        var errors: [String] = []
        var warnings: [String] = []

        // Check for missing essential fields
        if metadata.finalTitle?.isEmpty ?? true {
            warnings.append("Title is missing")
        }

        if metadata.finalArtist?.isEmpty ?? true {
            warnings.append("Artist is missing")
        }

        // Validate year format
        if let year = metadata.finalYear, !isValidYear(year) {
            errors.append("Invalid year format: \(year)")
        }

        let isValid = errors.isEmpty
        return ValidationResult(isValid: isValid, errors: errors, warnings: warnings)
    }

    // MARK: - Helper Methods

    nonisolated private func extractYear(from dateString: String) -> String {
        // Try to extract 4-digit year
        let pattern = #"\d{4}"#
        if let range = dateString.range(of: pattern, options: .regularExpression) {
            return String(dateString[range])
        }
        return dateString
    }

    private func isValidYear(_ year: String) -> Bool {
        guard let yearInt = Int(year), year.count == 4 else {
            return false
        }
        return yearInt >= 1900 && yearInt <= Calendar.current.component(.year, from: Date()) + 1
    }

    nonisolated private func formatIDToString(_ formatID: AudioFormatID) -> String {
        switch formatID {
        case kAudioFormatLinearPCM:
            return "PCM"
        case kAudioFormatMPEGLayer3:
            return "MP3"
        case kAudioFormatMPEG4AAC:
            return "AAC"
        case kAudioFormatAppleLossless:
            return "ALAC"
        case kAudioFormatFLAC:
            return "FLAC"
        default:
            // 将 FourCC 转换为字符串
            let bytes = [
                UInt8((formatID >> 24) & 0xFF),
                UInt8((formatID >> 16) & 0xFF),
                UInt8((formatID >> 8) & 0xFF),
                UInt8(formatID & 0xFF)
            ]
            if let string = String(bytes: bytes, encoding: .ascii) {
                return string
            }
            return "Unknown"
        }
    }
}
