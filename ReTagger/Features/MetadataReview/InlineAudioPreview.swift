//
//  InlineAudioPreview.swift
//  ReTagger
//
//  冲突解决面板内的简易音频预览播放器，独立于主播放控制器
//

import AVFoundation
import Combine
import SwiftUI
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
                    guard let self = self else { return }
                    // 仅当会话版本未发生变化时，才处理播放完毕逻辑
                    guard self.playSessionVersion == currentVersion else { return }
                    if self.activeFileID == fileID {
                        self.isPlaying = false
                        self.currentTime = 0
                        self.timer?.cancel()
                        self.timer = nil
                    }
                }
            }
            
            duration = Double(file.length) / sampleRate
            currentTime = 0
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
        let wasPlaying = isPlaying
        
        playSessionVersion += 1
        let currentVersion = playSessionVersion
        
        playerNode.stop()
        
        let targetFrame = AVAudioFramePosition(time * sampleRate)
        let remainingFrames = file.length - targetFrame
        guard remainingFrames > 0 else { return }
        
        segmentStartFrame = targetFrame
        
        playerNode.scheduleSegment(file, startingFrame: targetFrame, frameCount: AVAudioFrameCount(remainingFrames), at: nil) { [weak self] in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard self.playSessionVersion == currentVersion else { return }
                self.isPlaying = false
                self.timer?.cancel()
                self.timer = nil
            }
        }
        
        if wasPlaying {
            playerNode.play()
        }
        currentTime = time
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
        activeFileID = nil
        timer?.cancel()
        timer = nil
        
        if let url = scopedURL {
            url.stopAccessingSecurityScopedResource()
            scopedURL = nil
        }
    }

    private func play() {
        playerNode?.play()
        isPlaying = true
        startTimer()
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

/// 简易播放控制条视图
struct InlinePlaybackBar: View {
    let metadata: AudioMetadata
    @ObservedObject var preview: InlineAudioPreview
    @EnvironmentObject var localizationManager: LocalizationManager
    @EnvironmentObject var coordinator: AppCoordinator

    private var isActive: Bool { preview.activeFileID == metadata.id }

    var body: some View {
        VStack(spacing: 4) {
            // 播放按钮
            Button {
                preview.togglePlayPause(for: metadata, coordinator: coordinator)
            } label: {
                Image(systemName: isActive && preview.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title3)
                    .foregroundColor(isActive && preview.isPlaying ? DesignSystem.Colors.primary : .secondary)
            }
            .buttonStyle(.plain)
            .help(localizationManager.string(isActive && preview.isPlaying ? "conflict.preview.pause" : "conflict.preview.play"))

            // 进度条（仅在当前文件激活时展示）
            if isActive && preview.duration > 0 {
                VStack(spacing: 2) {
                    Slider(
                        value: Binding(
                            get: { preview.currentTime },
                            set: { preview.seek(to: $0) }
                        ),
                        in: 0...max(preview.duration, 0.01)
                    )
                    .help(localizationManager.string("conflict.preview.seek"))

                    HStack {
                        Text(formatTime(preview.currentTime))
                        Spacer()
                        Text(formatTime(preview.duration))
                    }
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(.secondary)
                }
                .frame(maxWidth: 140)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(DesignSystem.Animation.fast, value: isActive)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let m = Int(time) / 60
        let s = Int(time) % 60
        return String(format: "%d:%02d", m, s)
    }
}
