//
//  DiagnosticsLogStore.swift
//  ReTagger
//
//  为设置面板的"诊断"Tab 提供数据源：直接读取本进程通过 Logger+ReTagger.swift
//  写入统一日志（unified logging）的记录，无需另建一套内存日志缓冲区。
//  OSLogStore(scope: .currentProcessIdentifier) 读取的是本进程的活动日志，
//  即使消息未做 privacy: .public 标注也能读到明文（系统持久化日志才会脱敏），
//  但 OSLogType 本身不区分 warning 与 error（两者都记为 .error），因此展示
//  层按 debug/info/notice 归为「信息」、error/fault 归为「错误」两档。
//

import Foundation
import OSLog

struct DiagnosticsLogEntry: Identifiable {
    enum Level {
        case info
        case error
    }

    let id = UUID()
    let timestamp: Date
    let level: Level
    let category: String
    let message: String
}

enum DiagnosticsLogStore {
    private static let subsystem = "vip.retagger.macapp"

    /// 读取本进程最近产生的日志（默认最近 1 小时内，最多 limit 条，按时间正序排列）
    static func fetchRecentEntries(limit: Int = 500) -> [DiagnosticsLogEntry] {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return [] }
        let position = store.position(timeIntervalSinceEnd: -3600)
        let predicate = NSPredicate(format: "subsystem == %@", subsystem)
        guard let entries = try? store.getEntries(at: position, matching: predicate) else { return [] }

        let mapped: [DiagnosticsLogEntry] = entries.compactMap { entry in
            guard let logEntry = entry as? OSLogEntryLog else { return nil }
            return DiagnosticsLogEntry(
                timestamp: logEntry.date,
                level: level(for: logEntry.level),
                category: logEntry.category,
                message: logEntry.composedMessage
            )
        }
        return Array(mapped.suffix(limit))
    }

    private static func level(for osLevel: OSLogEntryLog.Level) -> DiagnosticsLogEntry.Level {
        switch osLevel {
        case .error, .fault:
            return .error
        default:
            return .info
        }
    }
}
