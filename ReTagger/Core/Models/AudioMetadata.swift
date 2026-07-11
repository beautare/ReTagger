//
//  AudioMetadata.swift
//  ReTagger
//
//  Created by Claude Code
//

import Foundation
import CryptoKit

struct AudioMetadata: Identifiable, Codable, Equatable {
    let id: UUID
    var filePath: URL
    var fileName: String
    var fileSizeBytes: Int64?

    // 技术性元数据
    var duration: TimeInterval? // 时长（秒）
    var bitrate: Int? // 位速率（kbps）
    var sampleRate: Int? // 采样速率（Hz）
    var format: String? // 音频格式
    var fileCreationDate: Date? // 文件创建日期
    var fileModificationDate: Date? // 文件修改日期

    // 原始元数据（可能不准确）
    var originalTitle: String?
    var originalArtist: String?
    var originalAlbum: String?
    var originalGenre: String?
    var originalYear: String?
    var originalAlbumArtist: String?
    var originalComposer: String?
    var originalComment: String?
    // AI 修正后的元数据
    var correctedTitle: String?
    var correctedArtist: String?
    var correctedAlbum: String?
    var correctedGenre: String?
    var correctedYear: String?
    var correctedAlbumArtist: String?
    var correctedComposer: String?
    var correctedComment: String?

    // 建议的文件/文件夹操作
    var suggestedFileName: String?
    var suggestedFolderPath: String?

    // 处理状态
    var processingState: ProcessingState = .pending
    var confidence: Double?
    var error: String?
    var aiNotes: String?

    // 文件导入来源
    var importSource: ImportSource = .directory

    enum ProcessingState: String, Codable {
        case pending
        case processing
        case awaitingConfirmation
        case completed
        case failed
        case userModified

        /// 状态列排序序号，按工作流推进顺序排列
        var sortRank: Int {
            switch self {
            case .pending: return 0
            case .processing: return 1
            case .awaitingConfirmation: return 2
            case .completed: return 3
            case .userModified: return 4
            case .failed: return 5
            }
        }
    }

    /// 文件导入来源：通过目录扫描或外部拖放
    enum ImportSource: String, Codable {
        case directory  // 通过目录扫描导入
        case dropped    // 通过外部拖放导入
    }

    nonisolated init(id: UUID? = nil,
         filePath: URL,
         fileName: String,
         fileSizeBytes: Int64? = nil,
         originalTitle: String? = nil,
         originalArtist: String? = nil,
         originalAlbum: String? = nil,
         originalGenre: String? = nil,
         originalYear: String? = nil,
         originalAlbumArtist: String? = nil,
         originalComposer: String? = nil,
         originalComment: String? = nil) {
        if let id = id {
            self.id = id
        } else {
            self.id = AudioMetadata.generateStableUUID(from: filePath.standardizedFileURL.path)
        }
        self.filePath = filePath
        self.fileName = fileName
        self.fileSizeBytes = fileSizeBytes
        self.originalTitle = originalTitle
        self.originalArtist = originalArtist
        self.originalAlbum = originalAlbum
        self.originalGenre = originalGenre
        self.originalYear = originalYear
        self.originalAlbumArtist = originalAlbumArtist
        self.originalComposer = originalComposer
        self.originalComment = originalComment
    }

    nonisolated private static func generateStableUUID(from string: String) -> UUID {
        guard let data = string.data(using: .utf8) else { return UUID() }
        let digest = Insecure.MD5.hash(data: data)
        
        // Use the first 16 bytes of the MD5 hash to create a UUID
        // This is effectively a v3 UUID (MD5-based) without the namespace complexity for now
        var uuidBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0) as (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
        
        withUnsafeMutableBytes(of: &uuidBytes) { ptr in
            digest.withUnsafeBytes { digestPtr in
                ptr.copyMemory(from: UnsafeRawBufferPointer(start: digestPtr.baseAddress, count: min(16, digestPtr.count)))
            }
        }
        
        return UUID(uuid: uuidBytes)
    }

    /// Computed property to check if metadata has been corrected by AI
    var hasCorrectedMetadata: Bool {
        return correctedTitle != nil ||
               correctedArtist != nil ||
               correctedAlbum != nil ||
               correctedGenre != nil ||
               correctedYear != nil ||
               correctedAlbumArtist != nil ||
               correctedComposer != nil ||
               correctedComment != nil ||
               suggestedFileName != nil ||
               suggestedFolderPath != nil
    }

    /// 是否存在与原始值不同的有效修正
    var hasEffectiveCorrections: Bool {
        if AudioMetadata.hasMeaningfulChange(original: originalTitle, corrected: correctedTitle) {
            return true
        }
        if AudioMetadata.hasMeaningfulChange(original: originalArtist, corrected: correctedArtist) {
            return true
        }
        if AudioMetadata.hasMeaningfulChange(original: originalAlbum, corrected: correctedAlbum) {
            return true
        }
        if AudioMetadata.hasMeaningfulChange(original: originalGenre, corrected: correctedGenre) {
            return true
        }
        if AudioMetadata.hasMeaningfulChange(original: originalYear, corrected: correctedYear) {
            return true
        }
        if AudioMetadata.hasMeaningfulChange(original: originalAlbumArtist, corrected: correctedAlbumArtist) {
            return true
        }
        if AudioMetadata.hasMeaningfulChange(original: originalComposer, corrected: correctedComposer) {
            return true
        }
        if AudioMetadata.hasMeaningfulChange(original: originalComment, corrected: correctedComment) {
            return true
        }
        if AudioMetadata.hasMeaningfulChange(original: fileName, corrected: suggestedFileName) {
            return true
        }
        if let suggestedFolderPath,
           AudioMetadata.hasMeaningfulChange(
                original: filePath.deletingLastPathComponent().path,
                corrected: suggestedFolderPath
           ) {
            return true
        }
        return false
    }

    /// 是否存在待确认的修正
    var hasPendingConfirmation: Bool {
        processingState == .awaitingConfirmation && hasEffectiveCorrections
    }
    
    /// 清除所有 AI 修正并重置状态
    mutating func clearCorrections() {
        correctedTitle = nil
        correctedArtist = nil
        correctedAlbum = nil
        correctedGenre = nil
        correctedYear = nil
        correctedAlbumArtist = nil
        correctedComposer = nil
        correctedComment = nil
        suggestedFileName = nil
        suggestedFolderPath = nil
        aiNotes = nil
        confidence = nil
        error = nil
        
        // 如果当前是待确认状态，则重置为未处理
        // 如果是已完成或失败，通常不应该直接调用此方法，除非是强制重置
        if processingState == .awaitingConfirmation || processingState == .failed {
            processingState = .pending
        }
    }

    /// 文件大小（格式化为 MB）
    var fileSizeDisplay: String {
        guard let bytes = fileSizeBytes else {
            return "—"
        }
        let megabytes = Double(bytes) / 1_048_576.0
        return String(format: "%.2f MB", megabytes)
    }

    /// 时长（格式化为 分:秒）
    var durationDisplay: String {
        guard let duration = duration else {
            return "—"
        }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// 位速率（格式化为 kbps）
    var bitrateDisplay: String {
        guard let bitrate = bitrate else {
            return "—"
        }
        return "\(bitrate) kbps"
    }

    /// 采样速率（格式化为 kHz）
    var sampleRateDisplay: String {
        guard let sampleRate = sampleRate else {
            return "—"
        }
        let kHz = Double(sampleRate) / 1000.0
        return String(format: "%.1f kHz", kHz)
    }

    /// 格式显示
    var formatDisplay: String {
        format ?? "—"
    }

    /// 创建日期（格式化）
    var creationDateDisplay: String {
        guard let date = fileCreationDate else {
            return "—"
        }
        return Self.dateFormatter.string(from: date)
    }

    /// 修改日期（格式化）
    var modificationDateDisplay: String {
        guard let date = fileModificationDate else {
            return "—"
        }
        return Self.dateFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Final Metadata (corrected or original)

    /// The final title to use (corrected if available, otherwise original)
    var finalTitle: String? {
        return correctedTitle ?? originalTitle
    }

    /// The final artist to use (corrected if available, otherwise original)
    var finalArtist: String? {
        return correctedArtist ?? originalArtist
    }

    /// The final album to use (corrected if available, otherwise original)
    var finalAlbum: String? {
        return correctedAlbum ?? originalAlbum
    }

    /// The final genre to use (corrected if available, otherwise original)
    var finalGenre: String? {
        return correctedGenre ?? originalGenre
    }

    /// The final year to use (corrected if available, otherwise original)
    var finalYear: String? {
        return correctedYear ?? originalYear
    }

    /// The final album artist to use (corrected if available, otherwise original)
    var finalAlbumArtist: String? {
        return correctedAlbumArtist ?? originalAlbumArtist
    }

    /// The final composer to use (corrected if available, otherwise original)
    var finalComposer: String? {
        return correctedComposer ?? originalComposer
    }

    /// The final comment to use (corrected if available, otherwise original)
    var finalComment: String? {
        return correctedComment ?? originalComment
    }

    // MARK: - Sorting Helpers

    var sortableFileName: String {
        Self.languagePriorityKey(for: fileName)
    }

    var sortableOriginalTitle: String {
        Self.languagePriorityKey(for: originalTitle)
    }

    var sortableOriginalArtist: String {
        Self.languagePriorityKey(for: originalArtist)
    }

    var sortableOriginalAlbum: String {
        Self.languagePriorityKey(for: originalAlbum)
    }

    var sortableOriginalGenre: String {
        originalGenre?.localizedLowercase ?? ""
    }

    var sortableOriginalYear: String {
        originalYear ?? ""
    }

    var sortableDuration: TimeInterval {
        duration ?? 0
    }

    /// 状态列排序使用的序号（按工作流推进顺序，不依赖展示语言）
    var processingStateSortRank: Int {
        processingState.sortRank
    }

    var sortableFileSize: Int64 {
        fileSizeBytes ?? 0
    }

    var sortableBitrate: Int {
        bitrate ?? 0
    }

    var sortableSampleRate: Int {
        sampleRate ?? 0
    }

    var sortableFormat: String {
        format?.localizedLowercase ?? ""
    }

    var sortableCreationDate: Date {
        fileCreationDate ?? Date.distantPast
    }

    var sortableModificationDate: Date {
        fileModificationDate ?? Date.distantPast
    }

    private static func languagePriorityKey(for value: String) -> String {
        languagePriorityKey(for: Optional(value))
    }

    private static func languagePriorityKey(for value: String?) -> String {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return "2"
        }

        let normalized = raw.localizedLowercase
        let firstLetterScalar = normalized.unicodeScalars.first { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar)
        }

        let isEnglishLeading: Bool
        if let scalar = firstLetterScalar {
            if scalar.isASCII {
                switch scalar.value {
                case 48...57, // 0-9
                     65...90, // A-Z
                     97...122: // a-z
                    isEnglishLeading = true
                default:
                    isEnglishLeading = false
                }
            } else {
                isEnglishLeading = false
            }
        } else {
            isEnglishLeading = false
        }

        let prefix = isEnglishLeading ? "0" : "1"
        return "\(prefix)_\(normalized)"
    }

    // MARK: - Value Normalization

    static func hasMeaningfulChange(original: String?, corrected: String?) -> Bool {
        guard let normalizedCorrected = normalizedComparable(corrected) else {
            return false
        }
        let normalizedOriginal = normalizedComparable(original)
        return normalizedOriginal != normalizedCorrected
    }

    static func normalizedComparable(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed.lowercased()
    }
}
