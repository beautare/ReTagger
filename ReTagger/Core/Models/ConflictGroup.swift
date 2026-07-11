//
//  ConflictGroup.swift
//  ReTagger
//
//  同名歌曲冲突组模型及冲突解决操作定义
//

import Foundation

/// 同名冲突组：包含多个即将同名的文件
struct ConflictGroup: Identifiable {
    let id = UUID()

    /// 冲突匹配键（用于展示冲突原因）
    let matchKey: MatchKey

    /// 组内所有冲突文件的 ID
    var memberIDs: [AudioMetadata.ID]

    /// 冲突匹配键类型
    enum MatchKey: Hashable {
        /// 逻辑重复：同标题 + 同艺术家
        case titleArtist(title: String, artist: String)
        /// 文件名重复：完全相同的目标文件名
        case fileName(name: String)
    }

    /// 人类可读的冲突描述
    var displayDescription: String {
        switch matchKey {
        case .titleArtist(let title, let artist):
            return "\(artist) - \(title)"
        case .fileName(let name):
            return name
        }
    }

    /// 冲突类型的简短标签
    var typeLabel: String {
        switch matchKey {
        case .titleArtist:
            return "同歌手同歌名"
        case .fileName:
            return "同文件名"
        }
    }
}

/// 用户对冲突组中单个文件的操作
enum ConflictAction: Equatable {
    /// 保持不变，正常写入（保留此文件）
    case keep
    /// 移至废纸篓
    case remove
    /// 手动修改建议的文件名
    case rename(newFileName: String)
}

/// 冲突解决结果
struct ConflictResolution {
    /// 对每个文件 ID 的操作决定
    var actions: [AudioMetadata.ID: ConflictAction] = [:]

    /// 是否已对所有冲突组做出处理
    var isFullyResolved: Bool {
        !actions.isEmpty
    }
}

/// 整个冲突解决会话的结果
enum ConflictSessionResult {
    /// 用户取消了整个操作
    case cancelled
    /// 用户已处理完所有冲突，返回最终解决方案
    case resolved(ConflictResolution)
}

// MARK: - MatchKey 扩展

extension ConflictGroup.MatchKey {
    /// 冲突类型对应的 SF Symbol 图标名
    var icon: String {
        switch self {
        case .titleArtist:
            return "person.2.fill"
        case .fileName:
            return "doc.on.doc.fill"
        }
    }
}
