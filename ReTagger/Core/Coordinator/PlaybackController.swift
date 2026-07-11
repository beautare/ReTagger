//
//  PlaybackController.swift
//  ReTagger
//
//  负责桥接播放服务与 SwiftUI 视图
//

import Combine
import Foundation
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var state: PlaybackState
    let timelineStore = PlaybackTimelineStore()
    @Published private(set) var isPlaying: Bool = false
    var timeline: PlaybackTimeline { timelineStore.timeline }
    /// 独立的频谱数据容器，避免高频更新触发 PlaybackBarView 全树重绘
    let spectrumDataStore = SpectrumDataStore()
    @Published var isQueuePanelVisible: Bool = false
    @Published var revealRequestToken: UUID = UUID()
    @Published var queueSelection: AudioMetadata.ID?
    @Published private(set) var hudMessage: String? = nil
    @Published private(set) var hudIcon: String = ""
    private var hudTask: Task<Void, Never>? = nil

    var onOrderChange: ((PlaybackOrder) -> Void)?
    var onTrackChange: ((AudioMetadata?) -> Void)?

    /// 播放音量（0-1），持久化到 UserDefaults
    @Published private(set) var volume: Float = 1.0
    private static let volumeDefaultsKey = "playbackVolume"
    private static let repeatModeDefaultsKey = "playbackRepeatMode"

    private let service: AudioPlaybackServicing
    private var cancellables: Set<AnyCancellable> = []
    private var queueRevision: Int
    private var isPlaybackBarVisible = true
#if canImport(AppKit)
    private var visibilityCancellables: Set<AnyCancellable> = []
    private var isApplicationActive = true
    private var isWindowMiniaturized = false
#endif

    init(service: AudioPlaybackServicing, defaultOrder: PlaybackOrder) {
        self.service = service
        self.state = service.state
        self.queueRevision = service.state.queueRevision
        self.isPlaying = service.timeline.isPlaying
        self.timelineStore.timeline = service.timeline

        service.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self else { return }
                let oldTrackID = self.state.currentTrackID
                let trackChanged = newState.currentTrackID != oldTrackID
                
                if newState.queueRevision != self.queueRevision {
                    self.queueRevision = newState.queueRevision
                    self.state = newState
                } else if trackChanged {
                    self.state.currentTrackID = newState.currentTrackID
                }
                
                if trackChanged {
                    self.onTrackChange?(self.state.currentTrack)
                }
            }
            .store(in: &cancellables)

        service.timelinePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newTimeline in
                guard let self else { return }
                
                let oldTimeInt = Int(self.timelineStore.timeline.currentTime)
                let newTimeInt = Int(newTimeline.currentTime)
                
                self.timelineStore.timeline = newTimeline
                if self.isPlaying != newTimeline.isPlaying {
                    self.isPlaying = newTimeline.isPlaying
                }
                
                // 只有当有当前曲目且秒数发生实质变化时，才记录时间戳，避免高频写入消耗 CPU/IO
                if self.state.currentTrackID != nil, oldTimeInt != newTimeInt {
                    UserDefaults.standard.set(newTimeline.currentTime, forKey: "lastPlayingTrackTime")
                }
            }
            .store(in: &cancellables)

        spectrumDataStore.bind(to: service.spectrumPublisher)

#if canImport(AppKit)
        setupVisibilityObservers()
#endif
        pushTimelineVisibility()

        if state.order != defaultOrder {
            toggleOrderIfNeeded(to: defaultOrder)
        }

        restoreVolumeAndRepeatMode()
    }

    private func restoreVolumeAndRepeatMode() {
        let savedVolume = UserDefaults.standard.object(forKey: Self.volumeDefaultsKey) as? Float ?? 1.0
        setVolume(savedVolume)

        if let rawMode = UserDefaults.standard.string(forKey: Self.repeatModeDefaultsKey),
           let mode = PlaybackRepeatMode(rawValue: rawMode) {
            service.setRepeatMode(mode)
        }
    }

    func setVolume(_ newVolume: Float) {
        let clamped = min(max(newVolume, 0), 1)
        volume = clamped
        service.setVolume(clamped)
        UserDefaults.standard.set(clamped, forKey: Self.volumeDefaultsKey)
    }

    /// 循环模式按 off → all → one → off 顺序切换
    func cycleRepeatMode() {
        let nextMode = state.repeatMode.next
        service.setRepeatMode(nextMode)
        UserDefaults.standard.set(nextMode.rawValue, forKey: Self.repeatModeDefaultsKey)
    }

    func startPlayback(queue: [AudioMetadata], from track: AudioMetadata) {
        UserDefaults.standard.removeObject(forKey: "lastPlayingTrackTime")
        service.load(queue: queue, startAt: track, order: state.order)
        service.play()
    }

    func restorePlaybackQueue(queue: [AudioMetadata], selectTrack track: AudioMetadata, time: TimeInterval) {
        service.load(queue: queue, startAt: track, order: state.order)
        if time > 0 {
            service.seek(to: time)
        }
    }

    func togglePlayPause() {
        if timeline.isPlaying {
            service.pause()
        } else {
            service.play()
        }
    }

    func playNext() {
        service.next()
    }

    func playPrevious() {
        service.previous()
    }

    func seek(to time: TimeInterval) {
        service.seek(to: time)
    }

    func seekBackward(seconds: TimeInterval = 5) {
        let target = max(0, timeline.currentTime - seconds)
        seek(to: target)
        showHUD(message: "-\(Int(seconds))s", icon: "gobackward.\(Int(seconds))")
    }

    func seekForward(seconds: TimeInterval = 5) {
        let target = min(timeline.duration, timeline.currentTime + seconds)
        seek(to: target)
        showHUD(message: "+\(Int(seconds))s", icon: "goforward.\(Int(seconds))")
    }

    func showHUD(message: String, icon: String) {
        hudMessage = message
        hudIcon = icon
        
        hudTask?.cancel()
        hudTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000) // 800ms
            guard !Task.isCancelled else { return }
            self.hudMessage = nil
        }
    }

    func toggleOrder() {
        // 以服务端状态为唯一判定来源：本地 state 镜像经异步发布更新，
        // 在同步调用链（如设置回写触发的 setOrder）中可能滞后一拍
        let target: PlaybackOrder = service.state.order == .sequential ? .shuffle : .sequential
        setOrder(target)
    }

    func setOrder(_ order: PlaybackOrder, notify: Bool = true) {
        guard service.state.order != order else { return }
        service.setOrder(order)
        if notify {
            onOrderChange?(service.state.order)
        }
    }

    func jump(to track: AudioMetadata) {
        UserDefaults.standard.removeObject(forKey: "lastPlayingTrackTime")
        service.jump(to: track)
    }

    /// 跳转到指定曲目并确保开始播放
    func jumpAndPlay(_ track: AudioMetadata) {
        UserDefaults.standard.removeObject(forKey: "lastPlayingTrackTime")
        service.jump(to: track)
        if !timeline.isPlaying {
            service.play()
        }
    }

    func remove(_ track: AudioMetadata) {
        service.remove(track)
    }

    func remove(where predicate: (AudioMetadata) -> Bool) {
        service.remove(where: predicate)
    }

    func append(_ tracks: [AudioMetadata]) {
        service.append(tracks)
    }

    /// 顺序播放模式下，按新排序重排播放队列
    func reorderQueue(_ newQueue: [AudioMetadata]) {
        service.reorderQueue(newQueue)
    }

    func clearQueue() {
        service.clear()
        isQueuePanelVisible = false
    }

    func releaseIfTrackActive(_ track: AudioMetadata) {
        guard state.currentTrackID == track.id else { return }
        clearQueue()
    }

    func updateQueueVisibility(_ visible: Bool) {
        guard state.isActive else {
            isQueuePanelVisible = false
            return
        }
        isQueuePanelVisible = visible
    }

    func dismissQueuePanelIfNeeded() {
        guard isQueuePanelVisible else { return }
        updateQueueVisibility(false)
    }

    func requestRevealCurrentTrack() {
        guard state.isActive else { return }
        revealRequestToken = UUID()
    }

    func setPlaybackBarVisible(_ visible: Bool) {
        guard isPlaybackBarVisible != visible else { return }
        isPlaybackBarVisible = visible
        pushTimelineVisibility()
    }

    private func toggleOrderIfNeeded(to target: PlaybackOrder) {
        guard state.order != target else { return }
        setOrder(target, notify: false)
    }

    private var isHoveringProgress = false

    func setProgressHovering(_ hovering: Bool) {
        guard isHoveringProgress != hovering else { return }
        isHoveringProgress = hovering
        pushTimelineVisibility()
    }

    private func pushTimelineVisibility() {
#if canImport(AppKit)
        if !isApplicationActive || isWindowMiniaturized {
            service.updateTimelineVisibility(.background)
            return
        }
#endif
        if isPlaybackBarVisible {
            service.updateTimelineVisibility(isHoveringProgress ? .interactive : .visible)
        } else {
            service.updateTimelineVisibility(.hidden)
        }
    }

#if canImport(AppKit)
    private func setupVisibilityObservers() {
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.isApplicationActive = true
                self?.pushTimelineVisibility()
            }
            .store(in: &visibilityCancellables)

        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                self?.isApplicationActive = false
                self?.pushTimelineVisibility()
            }
            .store(in: &visibilityCancellables)

        NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)
            .sink { [weak self] notification in
                guard let window = notification.object as? NSWindow else { return }
                guard NSApp.mainWindow === window || NSApp.keyWindow === window else { return }
                self?.isWindowMiniaturized = true
                self?.pushTimelineVisibility()
            }
            .store(in: &visibilityCancellables)

        NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)
            .sink { [weak self] notification in
                guard let window = notification.object as? NSWindow else { return }
                guard NSApp.mainWindow === window || NSApp.keyWindow === window else { return }
                self?.isWindowMiniaturized = false
                self?.pushTimelineVisibility()
            }
            .store(in: &visibilityCancellables)
    }
#endif
}

@MainActor
final class PlaybackTimelineStore: ObservableObject {
    @Published var timeline: PlaybackTimeline = PlaybackTimeline(currentTime: 0, duration: 0, isPlaying: false)
}
