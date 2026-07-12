//
//  PlaybackState.swift
//  ReTagger
//
//  播放流程核心模型
//

import Foundation

enum PlaybackOrder: String, Codable, CaseIterable {
    case sequential
    case shuffle
}

/// 循环模式：关闭 / 列表循环 / 单曲循环
enum PlaybackRepeatMode: String, Codable, CaseIterable {
    case off
    case all
    case one
}

/// 播放模式：顺序 → 列表循环 → 单曲循环 → 随机，由单按钮轮换。
/// 底层仍拆解为 order + repeatMode 两个维度，本枚举定义四种规范组合。
enum PlaybackMode: CaseIterable {
    case sequential
    case repeatAll
    case repeatOne
    case shuffle

    /// 模式按钮点击时的下一个模式
    var next: PlaybackMode {
        switch self {
        case .sequential: return .repeatAll
        case .repeatAll: return .repeatOne
        case .repeatOne: return .shuffle
        case .shuffle: return .sequential
        }
    }

    var order: PlaybackOrder {
        self == .shuffle ? .shuffle : .sequential
    }

    /// 随机模式循环整个队列，播完不停止
    var repeatMode: PlaybackRepeatMode {
        switch self {
        case .sequential: return .off
        case .repeatAll: return .all
        case .repeatOne: return .one
        case .shuffle: return .all
        }
    }

    /// 从底层两个维度归并出播放模式；随机优先于循环维度
    init(order: PlaybackOrder, repeatMode: PlaybackRepeatMode) {
        if order == .shuffle {
            self = .shuffle
        } else {
            switch repeatMode {
            case .off: self = .sequential
            case .all: self = .repeatAll
            case .one: self = .repeatOne
            }
        }
    }
}

struct PlaybackState {
    var queueIDs: [UUID]
    var metadataLookup: [UUID: AudioMetadata]
    var history: [UUID]
    var currentTrackID: UUID?
    var order: PlaybackOrder
    var repeatMode: PlaybackRepeatMode = .off
    var queueRevision: Int = 0

    static let empty = PlaybackState(
        queueIDs: [],
        metadataLookup: [:],
        history: [],
        currentTrackID: nil,
        order: .sequential,
        queueRevision: 0
    )

    var currentTrack: AudioMetadata? {
        guard let id = currentTrackID else { return nil }
        return metadataLookup[id]
    }

    var isActive: Bool {
        currentTrackID != nil && !queueIDs.isEmpty
    }

    var queue: [AudioMetadata] {
        queueIDs.compactMap { metadataLookup[$0] }
    }

    func metadata(for id: UUID) -> AudioMetadata? {
        metadataLookup[id]
    }
}

struct PlaybackTimeline: Equatable {
    var currentTime: TimeInterval
    var duration: TimeInterval
    var isPlaying: Bool
}

extension TimeInterval {
    var asPlaybackTimeString: String {
        guard self.isFinite else { return "--:--" }
        let totalSeconds = max(Int(self.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
