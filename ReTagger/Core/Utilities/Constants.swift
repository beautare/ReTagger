//
//  Constants.swift
//  ReTagger
//
//  Application constants
//

import Foundation

enum Constants {
    // MARK: - API

    enum API {
        // 元数据处理端点
        static let metadataProcess = "/api/v1/metadata/process"
        static let metadataBatch = "/api/v1/metadata/process/batch"
        static let metadataHistory = "/api/v1/metadata/history"
        static let metadataHealth = "/api/v1/metadata/health"
        static let metadataStats = "/api/v1/metadata/stats"
        static let deviceToken = "/api/v1/tokens/device"

        // 遗留端点（向后兼容）
        static let endpoint = "/api/v1/metadata/process"
        static let healthCheckEndpoint = metadataHealth

        // 超时配置
        static let defaultTimeout: TimeInterval = 30
        static let aiProcessingTimeout: TimeInterval = 120
        static let metadataProcessingTimeout: TimeInterval = 180  // 3分钟（处理大批量时）
    }

    // MARK: - File System

    enum FileSystem {
        nonisolated static let supportedAudioExtensions: Set<String> = AudioFormatSupport.supportedExtensions
        static let backupFolderName = "ReTagger"
        static let maxConcurrentOperations = 5
    }

    // MARK: - Metadata

    enum Metadata {
        static let defaultTitle = "Unknown Title"
        static let defaultArtist = "Unknown Artist"
        static let defaultAlbum = "Unknown Album"
    }

    // MARK: - UI

    enum UI {
        static let minWindowWidth: CGFloat = 800
        static let minWindowHeight: CGFloat = 600
        static let sidebarWidth: CGFloat = 200
    }

    // MARK: - Batch Processing

    enum Batch {
        static let minSize = 1
        static let maxSize = 100
        static let defaultSize = 20
    }

    // MARK: - Confidence

    enum Confidence {
        static let high: Double = 0.9
        static let medium: Double = 0.7
        static let low: Double = 0.5
    }
}
