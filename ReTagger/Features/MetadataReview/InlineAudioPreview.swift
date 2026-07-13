//
//  InlineAudioPreview.swift
//  ReTagger
//
//  冲突解决面板内的简易音频预览播放器，独立于主播放控制器
//

import AVFoundation
import Combine
import OSLog

@MainActor
final class InlineAudioPreview: ObservableObject {
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published private(set) var activeFileID: AudioMetadata.ID?

    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var currentFile: AVAudioFile?
    private var sampleRate: Double = 44100
    private var segmentStartFrame: AVAudioFramePosition = 0
    private var timer: AnyCancellable?
    private var scopedURL: URL?
    private var playSessionVersion: Int = 0
    /// 排程内容已播完：节点里没有待播数据，重播前必须重新排程
    private var isAtEnd = false

    func load(url: URL, fileID: AudioMetadata.ID, coordinator: AppCoordinator? = nil) {
        stop()
        
        playSessionVersion += 1
        let currentVersion = playSessionVersion
        
        let targetURL = coordinator?.resolveSecurityScopedURL(for: url) ?? url
        
        let isScoped = targetURL.startAccessingSecurityScopedResource()
        if isScoped {
            scopedURL = targetURL
        }
        do {
            let file = try AVAudioFile(forReading: targetURL)
            let newEngine = AVAudioEngine()
            let newNode = AVAudioPlayerNode()
            newEngine.attach(newNode)
            newEngine.connect(newNode, to: newEngine.mainMixerNode, format: file.processingFormat)
            try newEngine.start()
            
            engine = newEngine
            playerNode = newNode
            currentFile = file
            sampleRate = file.processingFormat.sampleRate > 0 ? file.processingFormat.sampleRate : 44100
            segmentStartFrame = 0
            
            newNode.scheduleFile(file, at: nil) { [weak self] in
                DispatchQueue.main.async {
                    self?.handlePlaybackReachedEnd(version: currentVersion)
                }
            }

            duration = Double(file.length) / sampleRate
            currentTime = 0
            isAtEnd = false
            activeFileID = fileID
        } catch {
            Logger.preview.error("InlineAudioPreview: Failed to load audio from \(targetURL.path). Error: \(error.localizedDescription)")
            if isScoped {
                targetURL.stopAccessingSecurityScopedResource()
                scopedURL = nil
            }
            duration = 0
            currentTime = 0
        }
    }

    func togglePlayPause(for metadata: AudioMetadata, coordinator: AppCoordinator? = nil) {
        if activeFileID == metadata.id && isPlaying {
            pause()
            return
        }
        if activeFileID != metadata.id {
            load(url: metadata.filePath, fileID: metadata.id, coordinator: coordinator)
        }
        play()
    }

    func seek(to time: TimeInterval) {
        guard let file = currentFile, let playerNode = playerNode else { return }
        // 先算目标帧再操作节点：拖到末端时钳制在最后一帧之前。
        // 若先 stop 再因越界提前返回，会留下“节点已停但 isPlaying 仍为真”的假播放状态
        let targetFrame = min(
            max(AVAudioFramePosition(time * sampleRate), 0),
            max(file.length - 1, 0)
        )
        let remainingFrames = file.length - targetFrame
        guard remainingFrames > 0 else { return }

        let wasPlaying = isPlaying
        playSessionVersion += 1
        let currentVersion = playSessionVersion

        playerNode.stop()
        segmentStartFrame = targetFrame
        isAtEnd = false

        playerNode.scheduleSegment(file, startingFrame: targetFrame, frameCount: AVAudioFrameCount(remainingFrames), at: nil) { [weak self] in
            DispatchQueue.main.async {
                self?.handlePlaybackReachedEnd(version: currentVersion)
            }
        }

        if wasPlaying {
            playerNode.play()
        }
        currentTime = Double(targetFrame) / sampleRate
    }

    func stop() {
        playSessionVersion += 1
        playerNode?.stop()
        engine?.stop()
        playerNode = nil
        engine = nil
        currentFile = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        isAtEnd = false
        activeFileID = nil
        timer?.cancel()
        timer = nil

        if let url = scopedURL {
            url.stopAccessingSecurityScopedResource()
            scopedURL = nil
        }
    }

    /// 排程播完后的统一收尾：复位播放标志并标记待重排程
    private func handlePlaybackReachedEnd(version: Int) {
        guard playSessionVersion == version else { return }
        isPlaying = false
        isAtEnd = true
        currentTime = 0
        timer?.cancel()
        timer = nil
    }

    private func play() {
        if isAtEnd {
            rescheduleFromStart()
        }
        playerNode?.play()
        isPlaying = true
        startTimer()
    }

    /// 播完后重播：节点内已无待播数据，从头重新排程整个文件
    private func rescheduleFromStart() {
        guard let file = currentFile, let playerNode else { return }
        playSessionVersion += 1
        let currentVersion = playSessionVersion

        playerNode.stop()
        segmentStartFrame = 0
        currentTime = 0
        isAtEnd = false

        playerNode.scheduleFile(file, at: nil) { [weak self] in
            DispatchQueue.main.async {
                self?.handlePlaybackReachedEnd(version: currentVersion)
            }
        }
    }

    private func pause() {
        playerNode?.pause()
        isPlaying = false
        timer?.cancel()
        timer = nil
    }

    private func startTimer() {
        timer = Timer.publish(every: 0.1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self, let playerNode = self.playerNode,
                      let nodeTime = playerNode.lastRenderTime,
                      nodeTime.isSampleTimeValid,
                      let playerTime = playerNode.playerTime(forNodeTime: nodeTime) else { return }
                
                let currentFrame = self.segmentStartFrame + playerTime.sampleTime
                let time = Double(currentFrame) / self.sampleRate
                self.currentTime = max(0, min(time, self.duration))
            }
    }
}

