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
//  返回结果按时间倒序（最新在前），并在遍历时边读边淘汰，避免时间窗口内
//  日志条数很多时一次性把全部条目载入内存。
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

    /// 读取本进程最近产生的日志（默认最近 1 小时内，最多 limit 条，按时间倒序排列，最新在前）
    static func fetchRecentEntries(limit: Int = 500) -> [DiagnosticsLogEntry] {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return [] }
        let position = store.position(timeIntervalSinceEnd: -3600)
        let predicate = NSPredicate(format: "subsystem == %@", subsystem)
        guard let entries = try? store.getEntries(at: position, matching: predicate) else { return [] }

        // 时间窗口内条目遍历顺序为由旧到新；用"攒到 2 倍上限就裁掉多余的旧条目"
        // 的方式滚动淘汰，避免窗口内日志量很大时把全部条目一次性载入内存。
        var buffer: [DiagnosticsLogEntry] = []
        buffer.reserveCapacity(limit * 2)
        for entry in entries {
            guard let logEntry = entry as? OSLogEntryLog else { continue }
            buffer.append(
                DiagnosticsLogEntry(
                    timestamp: logEntry.date,
                    level: level(for: logEntry.level),
                    category: logEntry.category,
                    message: logEntry.composedMessage
                )
            )
            if buffer.count >= limit * 2 {
                buffer.removeFirst(buffer.count - limit)
            }
        }
        if buffer.count > limit {
            buffer.removeFirst(buffer.count - limit)
        }
        return Array(buffer.reversed())
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
