//
//  AudioPlaybackService.swift
//  ReTagger
//
//  基于 AVAudioEngine + AVAudioPlayerNode 的音频播放服务。
//  通过 mainMixerNode 的 tap 提取实时 PCM 数据供 FFT 频谱分析。
//

import AVFoundation
import Combine
import Foundation
import OSLog

/// 播放定位快照：仅含跨线程计算播放时间所需的采样率与起始帧。
/// currentFile / segmentStartFrame 属于 MainActor 状态，不能从定时器线程直接读取，
/// 因此在每次 seek / 换曲时把这些值写入锁保护的容器供 timerQueue 读取。
private struct PositionSnapshot {
    let sampleRate: Double
    let segmentStartFrame: AVAudioFramePosition
}

private final class PositionSnapshotBox: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var snapshot: PositionSnapshot?

    nonisolated init() {}

    nonisolated func update(_ newSnapshot: PositionSnapshot?) {
        lock.lock()
        snapshot = newSnapshot
        lock.unlock()
    }

    nonisolated func read() -> PositionSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        return snapshot
    }
}

protocol AudioPlaybackServicing: AnyObject {
    var statePublisher: AnyPublisher<PlaybackState, Never> { get }
    var state: PlaybackState { get }
    var timelinePublisher: AnyPublisher<PlaybackTimeline, Never> { get }
    var timeline: PlaybackTimeline { get }

    /// 频谱数据流：bandCount 个归一化幅度值（0-1），30fps 发布
    var spectrumPublisher: AnyPublisher<[Float], Never> { get }

    func load(queue: [AudioMetadata], startAt track: AudioMetadata, order: PlaybackOrder)
    func play()
    func pause()
    func seek(to time: TimeInterval)
    func next()
    func previous()
    func setOrder(_ order: PlaybackOrder)
    func jump(to track: AudioMetadata)
    func remove(_ track: AudioMetadata)
    func remove(where predicate: (AudioMetadata) -> Bool)
    func append(_ tracks: [AudioMetadata])
    func clear()
    func reorderQueue(_ newQueue: [AudioMetadata])
    func updateTimelineVisibility(_ visibility: TimelineVisibility)

    /// 播放音量（0-1），作用于混音输出
    var volume: Float { get }
    func setVolume(_ volume: Float)
    /// 循环模式：关闭 / 列表循环 / 单曲循环
    func setRepeatMode(_ mode: PlaybackRepeatMode)
}

@MainActor
final class AudioPlaybackService: NSObject, AudioPlaybackServicing {
    // MARK: - 音频引擎

    private let engine = AVAudioEngine()
    nonisolated private let playerNode = AVAudioPlayerNode()
    private let spectrumAnalyzer = SpectrumAnalyzer()

    // MARK: - 队列管理

    private let queueManager: PlaybackQueueManager
    private let logger = Logger.playback

    // MARK: - 当前播放文件状态

    /// 当前加载的音频文件
    private var currentFile: AVAudioFile?
    /// 当前 segment 的起始帧（seek 后更新）
    private var segmentStartFrame: AVAudioFramePosition = 0
    /// 用于区分 scheduleFile 的 completionHandler 是否因 stop() 触发
    private var currentScheduleToken = UUID()
    /// 手动维护的播放状态（AVAudioPlayerNode 没有 timeControlStatus KVO）
    private var isNodePlaying = false

    // MARK: - 数据流

    private let stateSubject: CurrentValueSubject<PlaybackState, Never>
    private let timelineSubject: CurrentValueSubject<PlaybackTimeline, Never>
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - 调度与状态

    private var isSeeking = false
    private let timelineScheduler = TimelineScheduler()
    private var timelineVisibility: TimelineVisibility = .visible
    private var hasTap = false
    private var repeatMode: PlaybackRepeatMode = .off

    /// 连续加载失败计数：坏文件批量出现时限制自动跳曲次数，
    /// 避免深递归与（列表循环下的）无限循环
    private var consecutiveLoadFailures = 0
    private static let maxConsecutiveLoadFailures = 20

    // MARK: - 跨线程定位快照

    /// 供 TimelineScheduler 的 timerQueue 读取的定位快照容器。
    /// 定义在文件作用域（脱离 @MainActor），使其读写方法可从任意线程调用。
    nonisolated private let positionSnapshotBox = PositionSnapshotBox()

    // MARK: - 协议属性

    var statePublisher: AnyPublisher<PlaybackState, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    var state: PlaybackState {
        stateSubject.value
    }

    var timelinePublisher: AnyPublisher<PlaybackTimeline, Never> {
        timelineSubject.eraseToAnyPublisher()
    }

    var timeline: PlaybackTimeline {
        timelineSubject.value
    }

    var spectrumPublisher: AnyPublisher<[Float], Never> {
        spectrumAnalyzer.bandsPublisher
    }

    // MARK: - 初始化

    init(order: PlaybackOrder = .sequential) {
        self.queueManager = PlaybackQueueManager(order: order)
        self.stateSubject = CurrentValueSubject(
            PlaybackState(
                queueIDs: [],
                metadataLookup: [:],
                history: [],
                currentTrackID: nil,
                order: order
            )
        )
        self.timelineSubject = CurrentValueSubject(
            PlaybackTimeline(currentTime: 0, duration: 0, isPlaying: false)
        )
        super.init()
        logger.debug("AudioPlaybackService 初始化（AVAudioEngine），默认顺序：\(order.rawValue, privacy: .public)")
        setupEngine()
        configureTimelineScheduler()
    }

    // MARK: - 引擎配置

    private func setupEngine() {
        engine.attach(playerNode)
        // 初始连接使用默认格式；加载文件时会按文件格式重连
        let defaultFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(playerNode, to: engine.mainMixerNode, format: defaultFormat)
        logger.debug("AVAudioEngine 已配置")
    }

    private func startEngineIfNeeded() -> Bool {
        guard !engine.isRunning else { return true }
        do {
            try engine.start()
            logger.debug("AVAudioEngine 已启动")
            return true
        } catch {
            logger.error("AVAudioEngine 启动失败：\(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    private func configureTimelineScheduler() {
        timelineScheduler.configure(
            timeProvider: { [weak self] in
                // 此闭包在 timerQueue 调用，需要线程安全地访问播放时间
                guard let self else { return nil }
                return self.currentPlaybackTime()
            },
            handler: { [weak self] time in
                guard let self else { return }
                self.handleTimeUpdate(time)
            }
        )
        refreshTimelineActivity()
    }

    // MARK: - 当前播放时间计算

    /// 计算当前播放位置（秒）。可从任意线程安全调用：
    /// 采样率与起始帧来自锁保护的快照，playerNode 的时间查询由 AVFoundation 保证线程安全。
    nonisolated private func currentPlaybackTime() -> TimeInterval? {
        guard let snapshot = positionSnapshotBox.read(),
              let nodeTime = playerNode.lastRenderTime,
              nodeTime.isSampleTimeValid,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else {
            return nil
        }
        let currentFrame = snapshot.segmentStartFrame + playerTime.sampleTime
        let time = Double(currentFrame) / snapshot.sampleRate
        return max(0, time)
    }

    // MARK: - 协议方法实现

    func load(queue: [AudioMetadata], startAt track: AudioMetadata, order: PlaybackOrder) {
        logger.info("加载播放队列：总数 \(queue.count, privacy: .public)，起始曲目：\(track.fileName, privacy: .public)")
        queueManager.load(queue: queue, startAt: track, order: order)
        guard let currentTrack = queueManager.currentTrack() else {
            updateState { state in
                state.currentTrackID = nil
            }
            updateTimeline { timeline in
                timeline.isPlaying = false
                timeline.currentTime = 0
                timeline.duration = 0
            }
            return
        }
        preparePlayer(for: currentTrack, autoPlay: false)
        updateState { state in
            state.currentTrackID = currentTrack.id
            state.order = order
        }
    }

    func play() {
        logger.debug("触发播放")
        guard currentFile != nil else { return }
        guard startEngineIfNeeded() else { return }
        
        playerNode.play()
        isNodePlaying = true
        updateTimeline { timeline in
            timeline.isPlaying = true
        }
    }

    func pause() {
        logger.debug("触发暂停")
        playerNode.pause()
        engine.pause() // 挂起音频渲染引擎，释放硬件 I/O 线程
        isNodePlaying = false
        updateTimeline { timeline in
            timeline.isPlaying = false
        }
    }

    func seek(to time: TimeInterval) {
        guard let file = currentFile else { return }
        logger.debug("拖动进度至 \(time, privacy: .public) 秒")

        let wasPlaying = isNodePlaying
        let sampleRate = file.processingFormat.sampleRate
        guard sampleRate > 0 else { return }

        let totalFrames = file.length
        // 拖到末尾时钳制在最后一帧之前：暂停状态下不会意外触发自动切歌；
        // 播放状态下让剩余片段自然播完后再进入下一曲，与主流播放器一致
        let targetFrame = min(
            max(AVAudioFramePosition(time * sampleRate), 0),
            max(totalFrames - 1, 0)
        )
        let remainingFrames = totalFrames - targetFrame
        guard remainingFrames > 0 else { return }
        let clampedTime = Double(targetFrame) / sampleRate

        isSeeking = true

        // 停止当前播放（会触发旧 completionHandler，通过 token 忽略）
        playerNode.stop()
        let token = UUID()
        currentScheduleToken = token

        segmentStartFrame = targetFrame
        positionSnapshotBox.update(
            PositionSnapshot(sampleRate: sampleRate, segmentStartFrame: targetFrame)
        )

        // 从目标帧重新调度
        playerNode.scheduleSegment(
            file,
            startingFrame: targetFrame,
            frameCount: AVAudioFrameCount(remainingFrames),
            at: nil
        ) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.currentScheduleToken == token else { return }
                self.handlePlaybackEnded()
            }
        }

        if wasPlaying {
            playerNode.play()
        }

        isSeeking = false
        updateTimeline { timeline in
            timeline.currentTime = clampedTime
        }
    }

    func next() {
        let wasPlaying = isNodePlaying
        if let nextTrack = queueManager.advance() {
            preparePlayer(for: nextTrack, autoPlay: wasPlaying)
            updateQueueSnapshot()
        } else if repeatMode == .all, let firstTrack = queueManager.restartFromBeginning() {
            // 列表循环：队尾之后回到队首
            preparePlayer(for: firstTrack, autoPlay: wasPlaying)
            updateQueueSnapshot()
        } else {
            finishPlayback()
        }
    }

    func previous() {
        let wasPlaying = isNodePlaying
        guard let previousTrack = queueManager.retreat() else { return }
        preparePlayer(for: previousTrack, autoPlay: wasPlaying)
        updateQueueSnapshot()
    }

    func setOrder(_ order: PlaybackOrder) {
        guard queueManager.order != order else { return }
        queueManager.setOrder(order)
        updateQueueSnapshot(orderOverride: order)
    }

    func jump(to track: AudioMetadata) {
        let wasPlaying = isNodePlaying
        guard queueManager.jump(to: track) else { return }
        preparePlayer(for: track, autoPlay: wasPlaying)
        updateQueueSnapshot()
    }

    func remove(_ track: AudioMetadata) {
        let wasPlaying = isNodePlaying
        handleRemovalResult(queueManager.remove(track), wasPlaying: wasPlaying)
    }

    func remove(where predicate: (AudioMetadata) -> Bool) {
        let wasPlaying = isNodePlaying
        handleRemovalResult(queueManager.remove(where: predicate), wasPlaying: wasPlaying)
    }

    func append(_ tracks: [AudioMetadata]) {
        queueManager.append(tracks)
        updateQueueSnapshot()
    }

    func reorderQueue(_ newQueue: [AudioMetadata]) {
        guard queueManager.order == .sequential else { return }
        queueManager.reorder(to: newQueue)
        updateQueueSnapshot()
    }

    private func handleRemovalResult(_ result: PlaybackQueueManager.RemovalResult, wasPlaying: Bool) {
        switch result {
        case .notFound, .removed:
            updateQueueSnapshot()
        case .currentChanged(let newTrack):
            if let newTrack {
                preparePlayer(for: newTrack, autoPlay: wasPlaying)
            } else {
                clearCurrentItem()
            }
            updateQueueSnapshot()
        case .queueEmpty:
            clear()
        }
    }

    func clear() {
        playerNode.stop()
        engine.pause() // 挂起音频渲染引擎，释放硬件 I/O 线程
        clearCurrentItem()
        queueManager.reset()
        isNodePlaying = false
        currentScheduleToken = UUID()
        updateState { state in
            state.queueIDs = []
            state.metadataLookup = [:]
            state.history = []
            state.currentTrackID = nil
            state.order = .sequential
        }
        updateTimeline { timeline in
            timeline.currentTime = 0
            timeline.duration = 0
            timeline.isPlaying = false
        }
    }

    // MARK: - 准备播放

    private func preparePlayer(for track: AudioMetadata, autoPlay: Bool) {
        logger.info("准备播放曲目：\(track.fileName, privacy: .public)")

        // 停止当前播放并复位频谱分析数据
        playerNode.stop()
        spectrumAnalyzer.reset()
        let token = UUID()
        currentScheduleToken = token

        do {
            let file = try AVAudioFile(forReading: track.filePath)
            currentFile = file
            segmentStartFrame = 0
            consecutiveLoadFailures = 0

            let format = file.processingFormat
            positionSnapshotBox.update(
                format.sampleRate > 0
                    ? PositionSnapshot(sampleRate: format.sampleRate, segmentStartFrame: 0)
                    : nil
            )

            // 按文件格式重新连接节点
            engine.disconnectNodeOutput(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: format)

            // 调度整个文件
            playerNode.scheduleFile(file, at: nil) { [weak self] in
                DispatchQueue.main.async {
                    guard let self, self.currentScheduleToken == token else { return }
                    self.handlePlaybackEnded()
                }
            }

            let duration = Double(file.length) / format.sampleRate

            let didStartPlayback = autoPlay && startEngineIfNeeded()
            if didStartPlayback {
                playerNode.play()
                isNodePlaying = true
            } else {
                isNodePlaying = false
            }

            updateState { state in
                state.currentTrackID = track.id
            }
            updateTimeline { timeline in
                timeline.currentTime = 0
                timeline.duration = duration
                timeline.isPlaying = didStartPlayback
            }

        } catch {
            logger.error("文件加载失败：\(error.localizedDescription, privacy: .public)")
            positionSnapshotBox.update(nil)
            updateTimeline { timeline in
                timeline.isPlaying = false
            }
            // 尝试跳到下一曲；连续失败达到上限时停止，避免坏文件批量出现时无限跳曲
            consecutiveLoadFailures += 1
            if consecutiveLoadFailures >= Self.maxConsecutiveLoadFailures {
                logger.error("连续 \(Self.maxConsecutiveLoadFailures, privacy: .public) 个文件加载失败，停止自动跳曲")
                consecutiveLoadFailures = 0
                finishPlayback()
            } else {
                next()
            }
        }
    }

    private func clearCurrentItem() {
        currentFile = nil
        segmentStartFrame = 0
        positionSnapshotBox.update(nil)
    }

    // MARK: - 播放结束

    private func handlePlaybackEnded() {
        guard let currentTrack = queueManager.currentTrack() else {
            finishPlayback()
            return
        }

        // 单曲循环：重播当前曲目
        if repeatMode == .one {
            preparePlayer(for: currentTrack, autoPlay: true)
            return
        }

        if let nextTrack = queueManager.advance() {
            preparePlayer(for: nextTrack, autoPlay: true)
            updateQueueSnapshot()
        } else if repeatMode == .all, let firstTrack = queueManager.restartFromBeginning() {
            // 列表循环：整队播完后回到队首继续
            preparePlayer(for: firstTrack, autoPlay: true)
            updateQueueSnapshot()
        } else {
            finishPlayback()
        }
    }

    private func finishPlayback() {
        playerNode.stop()
        engine.pause() // 挂起音频渲染引擎，释放硬件 I/O 线程
        isNodePlaying = false
        currentScheduleToken = UUID()
        updateState { state in
            state.currentTrackID = nil
        }
        updateTimeline { timeline in
            timeline.currentTime = timeline.duration
            timeline.isPlaying = false
        }
    }

    // MARK: - 频谱 Tap 管理

    private func installSpectrumTap() {
        guard !hasTap else { return }
        let mixerNode = engine.mainMixerNode
        let format = mixerNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return }

        mixerNode.installTap(
            onBus: 0,
            bufferSize: UInt32(spectrumAnalyzer.fftSize),
            format: format
        ) { [weak self] buffer, _ in
            self?.spectrumAnalyzer.process(buffer: buffer)
        }
        hasTap = true
    }

    private func removeSpectrumTap() {
        guard hasTap else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        hasTap = false
        spectrumAnalyzer.reset()
    }

    // MARK: - 时间更新

    private func handleTimeUpdate(_ time: TimeInterval) {
        guard !isSeeking else { return }
        guard currentFile != nil else { return }
        updateTimeline { timeline in
            timeline.currentTime = time
        }
    }

    // MARK: - 状态管理

    private func updateQueueSnapshot(orderOverride: PlaybackOrder? = nil) {
        updateState { state in
            if let override = orderOverride {
                state.order = override
            }
        }
    }

    private func updateState(
        refreshQueueSnapshot: Bool = true,
        _ transform: (inout PlaybackState) -> Void
    ) {
        var state = stateSubject.value
        if refreshQueueSnapshot {
            populateQueueSnapshot(into: &state)
            state.history = queueManager.historySnapshot()
            if let current = queueManager.currentTrack() {
                state.currentTrackID = current.id
            } else if state.queueIDs.isEmpty {
                state.currentTrackID = nil
            }
            state.order = queueManager.order
            state.queueRevision &+= 1
        }
        transform(&state)
        stateSubject.send(state)
        refreshTimelineActivity()
    }

    private func populateQueueSnapshot(into state: inout PlaybackState) {
        let snapshot = queueManager.queueSnapshot()
        state.queueIDs = snapshot.map(\.id)
        state.metadataLookup = Dictionary(
            uniqueKeysWithValues: snapshot.map { ($0.id, $0) }
        )
    }

    // MARK: - 音量与循环模式

    var volume: Float {
        engine.mainMixerNode.outputVolume
    }

    func setVolume(_ volume: Float) {
        engine.mainMixerNode.outputVolume = min(max(volume, 0), 1)
    }

    func setRepeatMode(_ mode: PlaybackRepeatMode) {
        guard repeatMode != mode else { return }
        repeatMode = mode
        updateState { state in
            state.repeatMode = mode
        }
    }

    func updateTimelineVisibility(_ visibility: TimelineVisibility) {
        guard timelineVisibility != visibility else { return }
        timelineVisibility = visibility
        refreshTimelineActivity()
    }

    private func refreshTimelineActivity() {
        let timeline = timelineSubject.value
        let isPlaying = timeline.isPlaying
        let activity: TimelineScheduler.Activity
        if isPlaying {
            switch timelineVisibility {
            case .interactive:
                activity = .interactive
            case .visible:
                activity = .idle
            case .hidden:
                activity = .idle
            case .background:
                activity = .suspended
            }
        } else {
            activity = .suspended
        }
        
        // 根据播放状态和可见度，动态启用/停用频谱 Tap (FFT 计算)
        if isPlaying && (timelineVisibility == .interactive || timelineVisibility == .visible) {
            installSpectrumTap()
        } else {
            removeSpectrumTap()
        }
        
        timelineScheduler.updateActivity(activity)
    }

    private func updateTimeline(_ transform: (inout PlaybackTimeline) -> Void) {
        var timeline = timelineSubject.value
        transform(&timeline)
        timelineSubject.send(timeline)
        refreshTimelineActivity()
    }
}
