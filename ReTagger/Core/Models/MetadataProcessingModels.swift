// ReTagger/Core/Models/MetadataProcessingModels.swift
//
// 元数据处理相关数据模型

import Foundation

// MARK: - 元数据处理请求

/// 元数据处理请求
struct MetadataProcessingRequest: Codable {
    let files: [FileMetadata]
    let options: ProcessingOptions

    struct FileMetadata: Codable {
        // 文件标识
        let filePath: String
        let fileName: String
        let fileSize: Int64?

        // 当前元数据
        let title: String?
        let artist: String?
        let album: String?
        let genre: String?
        let year: String?
        let albumArtist: String?
        let composer: String?
        let comment: String?

        // 音频信息
        let duration: Int?
        let bitrate: Int?
        let format: String?
    }

    struct ProcessingOptions: Codable {
        let includeFileRenaming: Bool
        let includeFolderReorganization: Bool
        let preserveOriginalFiles: Bool
        let language: String
        let enableCache: Bool
        let confidenceThreshold: Double
        let preferredProvider: String?

        static let `default` = ProcessingOptions(
            includeFileRenaming: true,
            includeFolderReorganization: true,
            preserveOriginalFiles: true,
            language: "zh-CN",
            enableCache: true,
            confidenceThreshold: 0.7,
            preferredProvider: nil
        )
    }
}

// MARK: - 元数据处理响应

/// 元数据处理响应
struct MetadataProcessingResponse: Codable {
    let results: [CorrectedMetadata]
    let stats: ProcessingStats
    let fromCache: Bool

    struct CorrectedMetadata: Codable {
        // 文件标识（与请求对应）
        let filePath: String

        // 修正后的元数据
        let correctedTitle: String?
        let correctedArtist: String?
        let correctedAlbum: String?
        let correctedGenre: String?
        let correctedYear: String?
        let correctedAlbumArtist: String?
        let correctedComposer: String?
        let correctedComment: String?

        // 文件操作建议
        let suggestedFileName: String?
        let suggestedFolderPath: String?

        // 置信度与说明
        let confidence: Double?
        let notes: String?
        let fieldConfidence: FieldConfidence?

        // 处理状态
        let status: String
        let errorMessage: String?
    }

    struct FieldConfidence: Codable {
        let title: Double?
        let artist: Double?
        let album: Double?
        let genre: Double?
        let year: Double?
    }

    struct ProcessingStats: Codable {
        let totalFiles: Int
        let successCount: Int
        let partialCount: Int?
        let failedCount: Int
        let noChangeCount: Int?

        let processingTimeMs: Int64?
        let tokensUsed: Int?
        let aiProvider: String?
        let modelName: String?

        let averageConfidence: Double?
    }
}
