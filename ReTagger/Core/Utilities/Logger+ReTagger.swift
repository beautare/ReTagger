//
//  Logger+ReTagger.swift
//  ReTagger
//
//  Created by Claude Code
//

import Foundation
import OSLog

/// ReTagger 应用的统一日志系统
/// 使用 Apple 的 OSLog 框架提供结构化日志记录
extension Logger {
    /// 子系统标识符
    private static let subsystem = "vip.retagger.macapp"

    // MARK: - 日志分类

    /// 文件系统操作日志（目录选择、文件扫描、文件操作）
    nonisolated static let fileSystem = Logger(subsystem: subsystem, category: "FileSystem")

    /// 元数据处理日志（ID3 标签读写、元数据验证）
    nonisolated static let metadata = Logger(subsystem: subsystem, category: "Metadata")

    /// 网络请求日志（API 调用、响应处理）
    nonisolated static let network = Logger(subsystem: subsystem, category: "Network")

    /// 鉴权与令牌管理日志
    nonisolated static let auth = Logger(subsystem: subsystem, category: "Auth")

    /// AI 处理日志（AI 引擎交互、批处理）
    nonisolated static let ai = Logger(subsystem: subsystem, category: "AI")

    /// 应用协调器日志（导航、状态变更）
    nonisolated static let coordinator = Logger(subsystem: subsystem, category: "Coordinator")

    /// UI 交互日志（用户操作、视图生命周期）
    nonisolated static let ui = Logger(subsystem: subsystem, category: "UI")

    /// 缓存操作日志（缓存命中、失效）
    nonisolated static let cache = Logger(subsystem: subsystem, category: "Cache")

    /// 性能监控日志（耗时操作、性能指标）
    nonisolated static let performance = Logger(subsystem: subsystem, category: "Performance")

    /// 播放流程日志（队列管理、播放事件、错误）
    nonisolated static let playback = Logger(subsystem: subsystem, category: "Playback")

    /// 试听流程日志（行级单独试听）
    nonisolated static let preview = Logger(subsystem: subsystem, category: "Preview")

    /// 配置管理日志（环境变量、配置文件）
    nonisolated static let config = Logger(subsystem: subsystem, category: "Config")

    /// 软件更新日志（版本检查、App Store 跳转）
    nonisolated static let update = Logger(subsystem: subsystem, category: "Update")
}

// MARK: - 便捷日志方法

extension Logger {
    /// 记录操作开始（用于性能监控）
    /// - Parameter operation: 操作名称
    /// - Returns: 操作开始时间（用于计算耗时）
    func logOperationStart(_ operation: String) -> Date {
        let startTime = Date()
        self.debug("[\(operation)] Started")
        return startTime
    }

    /// 记录操作结束（自动计算耗时）
    /// - Parameters:
    ///   - operation: 操作名称
    ///   - startTime: 操作开始时间
    func logOperationEnd(_ operation: String, startTime: Date) {
        let duration = Date().timeIntervalSince(startTime)
        self.info("[\(operation)] Completed in \(String(format: "%.3f", duration))s")
    }

    /// 记录操作失败
    /// - Parameters:
    ///   - operation: 操作名称
    ///   - error: 错误信息
    func logOperationFailed(_ operation: String, error: Error) {
        self.error("[\(operation)] Failed: \(error.localizedDescription)")
    }
}

// MARK: - 使用示例

/*
 使用方式：

 // 1. 基本日志记录
 Logger.fileSystem.info("Scanning directory: \(url.path)")
 Logger.metadata.debug("Read metadata: title=\(title ?? "nil")")
 Logger.network.error("API request failed: \(error)")

 // 2. 性能监控
 let startTime = Logger.performance.logOperationStart("ScanAudioFiles")
 // ... 执行耗时操作
 Logger.performance.logOperationEnd("ScanAudioFiles", startTime: startTime)

 // 3. 操作失败记录
 do {
     try await operation()
 } catch {
     Logger.fileSystem.logOperationFailed("RenameFile", error: error)
     throw error
 }

 // 4. 日志级别说明
 // - debug: 调试信息（开发环境可见）
 // - info: 一般信息（重要操作记录）
 // - notice: 重要通知（需要关注的事件）
 // - error: 错误信息（操作失败）
 // - fault: 严重错误（系统级问题）
 */
