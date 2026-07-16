//
//  PlaybackQueueManager.swift
//  ReTagger
//
//  播放队列与顺序管理
//

import Foundation

@MainActor
final class PlaybackQueueManager {
    enum RemovalResult {
        case notFound
        case removed
        case currentChanged(AudioMetadata?)
        case queueEmpty
    }

    private(set) var order: PlaybackOrder

    private var orderedQueue: [AudioMetadata] = []
    private var shuffledQueue: [AudioMetadata] = []
    private var currentIndex: Int?
    private var history: [UUID] = []

    init(order: PlaybackOrder = .sequential) {
        self.order = order
    }

    func reset() {
        orderedQueue = []
        shuffledQueue = []
        currentIndex = nil
        history.removeAll()
        order = .sequential
    }

    func load(queue: [AudioMetadata], startAt startTrack: AudioMetadata, order: PlaybackOrder) {
        orderedQueue = queue
        history.removeAll()

        guard !queue.isEmpty else {
            shuffledQueue = []
            currentIndex = nil
            self.order = order
            return
        }

        let startIndex = queue.firstIndex(where: { $0.id == startTrack.id }) ?? 0
        prepareShuffledQueue(startIndex: startIndex)
        self.order = order

        switch order {
        case .sequential:
            currentIndex = queue.isEmpty ? nil : startIndex
        case .shuffle:
            currentIndex = shuffledQueue.isEmpty ? nil : 0
        }
        trimHistory()
    }

    func queueSnapshot() -> [AudioMetadata] {
        activeQueue
    }

    func historySnapshot() -> [UUID] {
        history
    }

    func currentTrack() -> AudioMetadata? {
        guard
            let index = currentIndex,
            activeQueue.indices.contains(index)
        else {
            return nil
        }
        return activeQueue[index]
    }

    @discardableResult
    func advance() -> AudioMetadata? {
        guard let index = currentIndex,
              activeQueue.indices.contains(index)
        else {
            currentIndex = nil
            return nil
        }

        let queue = activeQueue
        history.append(queue[index].id)

        let nextIndex = index + 1
        guard nextIndex < queue.count else {
            currentIndex = nil
            return nil
        }

        currentIndex = nextIndex
        return queue[nextIndex]
    }

    @discardableResult
    func retreat() -> AudioMetadata? {
        let queue = activeQueue

        while let lastID = history.popLast() {
            if let index = queue.firstIndex(where: { $0.id == lastID }) {
                currentIndex = index
                return queue[index]
            }
        }

        guard
            let index = currentIndex,
            queue.indices.contains(index)
        else {
            return nil
        }
        return queue[index]
    }

    /// 队列播完后回到队首（列表循环）。返回队首曲目；队列为空时返回 nil。
    func restartFromBeginning() -> AudioMetadata? {
        guard !activeQueue.isEmpty else { return nil }
        currentIndex = 0
        return activeQueue[0]
    }

    func setOrder(_ newOrder: PlaybackOrder) {
        guard newOrder != order else { return }
        let currentTrack = currentTrack()
        order = newOrder
        if newOrder == .shuffle {
            let startIndex = currentTrack.flatMap { track in
                orderedQueue.firstIndex(where: { $0.id == track.id })
            } ?? 0
            prepareShuffledQueue(startIndex: startIndex)
            currentIndex = shuffledQueue.isEmpty ? nil : 0
        } else {
            if let track = currentTrack,
               let index = orderedQueue.firstIndex(where: { $0.id == track.id }) {
                currentIndex = index
            } else {
                currentIndex = orderedQueue.isEmpty ? nil : 0
            }
        }
        trimHistory()
    }

    func jump(to track: AudioMetadata) -> Bool {
        let queue = activeQueue
        guard let index = queue.firstIndex(where: { $0.id == track.id }) else {
            return false
        }

        if let current = currentTrack(),
           current.id != track.id {
            history.append(current.id)
        }

        currentIndex = index
        return true
    }

    func remove(_ track: AudioMetadata) -> RemovalResult {
        let queueBeforeRemoval = activeQueue
        guard let removalIndex = queueBeforeRemoval.firstIndex(where: { $0.id == track.id }) else {
            return .notFound
        }

        let currentID = currentTrack()?.id
        let wasCurrent = currentID == track.id

        if let index = orderedQueue.firstIndex(where: { $0.id == track.id }) {
            orderedQueue.remove(at: index)
        }

        if let index = shuffledQueue.firstIndex(where: { $0.id == track.id }) {
            shuffledQueue.remove(at: index)
        }

        history.removeAll { $0 == track.id }

        guard !orderedQueue.isEmpty else {
            currentIndex = nil
            return .queueEmpty
        }

        let queue = activeQueue
        guard !queue.isEmpty else {
            currentIndex = nil
            return .queueEmpty
        }

        if wasCurrent {
            let targetIndex = min(removalIndex, queue.count - 1)
            currentIndex = queue.indices.contains(targetIndex) ? targetIndex : nil
            trimHistory()
            return .currentChanged(currentTrack())
        }

        if let currentID,
           let index = queue.firstIndex(where: { $0.id == currentID }) {
            currentIndex = index
        }
        trimHistory()
        return .removed
    }

    func remove(where predicate: (AudioMetadata) -> Bool) -> RemovalResult {
        let currentID = currentTrack()?.id

        // Store IDs to be removed for updating history
        let idsToRemove = Set(activeQueue.filter(predicate).map(\.id))
        guard !idsToRemove.isEmpty else { return .notFound }

        orderedQueue.removeAll(where: predicate)
        shuffledQueue.removeAll(where: predicate)
        history.removeAll(where: { idsToRemove.contains($0) })

        guard !orderedQueue.isEmpty else {
            currentIndex = nil
            return .queueEmpty
        }

        let queue = activeQueue
        guard !queue.isEmpty else {
            currentIndex = nil
            return .queueEmpty
        }

        // If current track was not removed, update index
        if let oldCurrentID = currentID, !idsToRemove.contains(oldCurrentID) {
            if let index = queue.firstIndex(where: { $0.id == oldCurrentID }) {
                currentIndex = index
                return .removed
            }
        }

        // Current track was removed, find new valid index
        // Try to keep same numeric index or clamp to end
        let targetIndex = min(currentIndex ?? 0, queue.count - 1)
        currentIndex = queue.indices.contains(targetIndex) ? targetIndex : nil
        trimHistory()

        if currentID != currentTrack()?.id {
            return .currentChanged(currentTrack())
        }

        return .removed
    }

    func append(_ tracks: [AudioMetadata]) {
        guard !tracks.isEmpty else { return }
        
        // 过滤掉已存在于队列中的曲目，避免重复 ID
        let existingIDs = Set(orderedQueue.map(\.id))
        let newTracks = tracks.filter { !existingIDs.contains($0.id) }
        guard !newTracks.isEmpty else { return }
        
        // Append to ordered queue
        orderedQueue.append(contentsOf: newTracks)
        
        if order == .shuffle {
            // In shuffle mode, reshuffle the entire playlist including new tracks
            // Ensure the currently playing track stays at the top (or current position)
            if let current = currentTrack(),
               let index = orderedQueue.firstIndex(where: { $0.id == current.id }) {
                prepareShuffledQueue(startIndex: index)
                currentIndex = 0 // Current track is now at index 0 of shuffled queue
            } else {
                // If nothing playing, just shuffle everything
                shuffledQueue = orderedQueue.shuffled()
                currentIndex = nil
            }
        } else {
            // In sequential mode, just append (shuffled relative to themselves)
            // so they are at the end waiting to be played
            shuffledQueue.append(contentsOf: newTracks.shuffled())
        }
        
        // If queue was empty, we need to set the index to 0 to make it "Ready"
        // But logic usually relies on `load` for the first start.
        // If we append to empty, we probably shouldn't auto-start, but we should ensure valid state.
        if currentIndex == nil && !activeQueue.isEmpty {
             // User might not want to auto-select. 
             // But if `currentTrack()` relies on `currentIndex`, it remains nil.
             // This is correct: queue has items, but none selected/playing.
        }
    }

    /// 根据新的排序列表重排顺序队列，保持当前播放位置不变
    func reorder(to newQueue: [AudioMetadata]) {
        guard !newQueue.isEmpty else { return }
        let currentTrackID = currentTrack()?.id

        orderedQueue = newQueue

        // 如果当前是顺序播放模式，更新 currentIndex 指向同一曲目
        if order == .sequential {
            if let id = currentTrackID,
               let newIndex = orderedQueue.firstIndex(where: { $0.id == id }) {
                currentIndex = newIndex
            }
        }
        // shuffle 模式下 orderedQueue 变了不影响 shuffledQueue 当前的播放
    }

    private var activeQueue: [AudioMetadata] {
        switch order {
        case .sequential:
            return orderedQueue
        case .shuffle:
            return shuffledQueue
        }
    }

    private func prepareShuffledQueue(startIndex: Int) {
        guard !orderedQueue.isEmpty else {
            shuffledQueue = []
            return
        }

        var remaining = orderedQueue
        let safeIndex = min(max(startIndex, 0), remaining.count - 1)
        let startTrack = remaining.remove(at: safeIndex)
        remaining.shuffle()
        shuffledQueue = [startTrack] + remaining
    }

    private func trimHistory() {
        let validIDs = Set(activeQueue.map(\.id))
        history = history.filter { validIDs.contains($0) }
    }
}
