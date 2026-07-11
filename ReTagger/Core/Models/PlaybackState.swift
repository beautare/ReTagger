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

    /// 循环按钮点击时的下一个模式：off → all → one → off
    var next: PlaybackRepeatMode {
        switch self {
        case .off: return .all
        case .all: return .one
        case .one: return .off
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
