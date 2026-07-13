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

    /// 文件名冲突键归一化：APFS 默认大小写不敏感，外部文件又常见 NFC/NFD 混杂，
    /// 检测与查重必须统一按 NFD + 小写比较，否则漏检的冲突会在改名时被静默加后缀
    static func normalizedFileNameKey(_ name: String) -> String {
        name.decomposedStringWithCanonicalMapping.lowercased()
    }
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
