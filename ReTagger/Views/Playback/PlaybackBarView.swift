//
//  PlaybackBarView.swift
//  ReTagger
//
//  底部迷你播放控件
//

import SwiftUI
import AppKit
import QuartzCore

struct PlaybackBarView: View {
    @EnvironmentObject private var playbackController: PlaybackController
    @EnvironmentObject private var timelineStore: PlaybackTimelineStore
    @EnvironmentObject private var localizationManager: LocalizationManager
    @State private var sliderEditingValue: TimeInterval?
    /// 播放条实测宽度，紧凑/超紧凑布局的唯一来源。
    /// 初始为无穷大 → 首帧按内联布局渲染，onAppear 立即回填真实宽度
    @State private var measuredBarWidth: CGFloat = .greatestFiniteMagnitude
    @State private var isHoveringProgress = false
    @Namespace private var playbackBarNamespace
    @State private var keyMonitor: Any? = nil
    /// 手型光标是否已入栈，保证 NSCursor push/pop 严格配对
    @State private var isPointingHandCursorActive = false
    @State private var isVolumePopoverPresented = false

    private var state: PlaybackState { playbackController.state }
    private var timeline: PlaybackTimeline { timelineStore.timeline }
    private var shouldHideSlider: Bool {
        timeline.isPlaying && !isHoveringProgress
    }

    /// 由实测宽度派生的布局标记，避免维护多份镜像状态导致的不同步
    private var isCompactLayout: Bool {
        measuredBarWidth < DesignSystem.Layout.PlaybackBar.compactThreshold
    }

    private var isUltraCompactLayout: Bool {
        measuredBarWidth < DesignSystem.Layout.PlaybackBar.ultraCompactThreshold
    }

    var body: some View {
        let isVisible = state.isActive

        return GeometryReader { proxy in
            let width = proxy.size.width
            let currentPadding = isCompactLayout
                ? DesignSystem.Layout.PlaybackBar.compactPadding
                : DesignSystem.Layout.PlaybackBar.inlinePadding
            let currentHorizontalPadding = isCompactLayout
                ? DesignSystem.Layout.PlaybackBar.compactHorizontalPadding
                : DesignSystem.Layout.PlaybackBar.horizontalPadding

            VStack(spacing: 0) {
                if isVisible {
                    VStack(spacing: isCompactLayout ? DesignSystem.Spacing.xxs : DesignSystem.Spacing.md) {
                        if isCompactLayout {
                            progressContainer
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        Group {
                            if isUltraCompactLayout {
                                VStack(spacing: DesignSystem.Spacing.xs) {
                                    controlSection
                                    trackSummary
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                HStack(alignment: .center, spacing: DesignSystem.Spacing.xxs) {
                                    trackSummary

                                    if !isCompactLayout {
                                        progressContainer
                                            .transition(.move(edge: .leading).combined(with: .opacity))
                                    }

                                    controlSection
                                }
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .center)
                        .padding(.vertical, currentPadding)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            TapGesture()
                                .onEnded {
                                    if shouldRevealForCurrentEvent() {
                                        playbackController.requestRevealCurrentTrack()
                                    }
                                }
                        )
                        .onHover { hovering in
                            // 播放条空白区域显示手型指针，暗示可点击定位。
                            // 用状态标记保证 push/pop 严格配对：悬停中视图被隐藏时
                            // onHover(false) 不会触发，需在 onDisappear 兜底 pop
                            if hovering, !isPointingHandCursorActive {
                                NSCursor.pointingHand.push()
                                isPointingHandCursorActive = true
                            } else if !hovering, isPointingHandCursorActive {
                                NSCursor.pop()
                                isPointingHandCursorActive = false
                            }
                        }
                        .onDisappear {
                            if isPointingHandCursorActive {
                                NSCursor.pop()
                                isPointingHandCursorActive = false
                            }
                        }
                    }
                    .padding(.horizontal, currentHorizontalPadding)
                    .animation(DesignSystem.Animation.normal, value: isCompactLayout)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .background(barBackground)
            .overlay(Color(nsColor: .separatorColor).frame(height: 1), alignment: .top)
            .shadow(
                color: isVisible ? Color.black.opacity(0.06) : .clear,
                radius: 12,
                x: 0,
                y: -4
            )
            .onAppear {
                measuredBarWidth = width
                playbackController.setPlaybackBarVisible(isVisible)
                setupKeyMonitor()
            }
            .onChange(of: width) { newWidth in
                // 单一宽度来源：布局标记全部由 measuredBarWidth 派生。
                // 仅在跨越断点时带弹簧动画，避免连续 resize 过程反复触发动画
                let wasCompact = isCompactLayout
                let wasUltraCompact = isUltraCompactLayout
                let willCompact = newWidth < DesignSystem.Layout.PlaybackBar.compactThreshold
                let willUltraCompact = newWidth < DesignSystem.Layout.PlaybackBar.ultraCompactThreshold

                if state.isActive, (wasCompact != willCompact || wasUltraCompact != willUltraCompact) {
                    withAnimation(.interpolatingSpring(stiffness: 160, damping: 18)) {
                        measuredBarWidth = newWidth
                    }
                } else {
                    measuredBarWidth = newWidth
                }
            }
            .onDisappear {
                playbackController.setPlaybackBarVisible(false)
                removeKeyMonitor()
            }
            .onChange(of: isVisible) { newVisibility in
                playbackController.setPlaybackBarVisible(newVisibility)
            }
        }
        .coordinateSpace(name: "PlaybackBar")
        .frame(
            height: isVisible
                ? (isCompactLayout
                    ? (isUltraCompactLayout ? DesignSystem.Layout.PlaybackBar.ultraCompactHeight : DesignSystem.Layout.PlaybackBar.compactHeight)
                    : DesignSystem.Layout.PlaybackBar.inlineHeight)
                : 0
        )
    }

    private var trackSummary: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .fill(trackArtworkGradient)
                .frame(
                    width: DesignSystem.Layout.PlaybackBar.artworkSize,
                    height: DesignSystem.Layout.PlaybackBar.artworkSize
                )
                .overlay(
                    Image(systemName: DesignSystem.Icons.music)
                        .foregroundColor(.white.opacity(0.9))
                )

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                MarqueeTextView(
                    text: primaryTitle,
                    font: .systemFont(ofSize: DesignSystem.Layout.PlaybackBar.trackTitleFontSize, weight: .semibold),
                    textColor: .labelColor,
                    width: DesignSystem.Layout.PlaybackBar.trackTitleTextWidth,
                    isPlaying: timeline.isPlaying
                )

                MarqueeTextView(
                    text: secondaryTitle,
                    font: .systemFont(ofSize: DesignSystem.Layout.PlaybackBar.trackSubtitleFontSize, weight: .regular),
                    textColor: .secondaryLabelColor,
                    width: DesignSystem.Layout.PlaybackBar.trackTitleTextWidth,
                    isPlaying: timeline.isPlaying
                )
            }
        }
        .frame(width: DesignSystem.Layout.PlaybackBar.trackSummaryWidth, alignment: isUltraCompactLayout ? .center : .leading)
        .help(state.currentTrack?.fileName ?? "")
        .matchedGeometryEffect(id: "trackSummary", in: playbackBarNamespace)
    }

    private var progressSection: some View {
        Group {
            if isCompactLayout {
                compactProgressSection
            } else {
                inlineProgressSection
            }
        }
    }

    private var inlineProgressSection: some View {
        HStack(spacing: DesignSystem.Spacing.xxs) {
            Text(currentTimeText)
                .font(DesignSystem.Typography.caption.monospacedDigit())
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .frame(minWidth: DesignSystem.Layout.PlaybackBar.timeLabelWidth, alignment: .trailing)
                .lineLimit(1)

            CircularThumbSlider(
                value: sliderBinding,
                range: 0...max(timeline.duration, 1),
                onEditingChanged: handleSliderEditing,
                tintColor: DesignSystem.Colors.accent.opacity(0.75),
                isDisabled: timeline.duration <= 0
            )
            .opacity(timeline.isPlaying ? (isHoveringProgress ? 1.0 : 0.0) : 1.0)
            .allowsHitTesting(!timeline.isPlaying || isHoveringProgress)
            .animation(.easeInOut(duration: DesignSystem.Layout.PlaybackBar.Spectrum.hoverTransitionDuration), value: timeline.isPlaying)
            .animation(.easeInOut(duration: DesignSystem.Layout.PlaybackBar.Spectrum.hoverTransitionDuration), value: isHoveringProgress)

            Text(remainingTimeText)
                .font(DesignSystem.Typography.caption.monospacedDigit())
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .frame(minWidth: DesignSystem.Layout.PlaybackBar.timeLabelWidth, alignment: .leading)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var compactProgressSection: some View {
        return HStack(spacing: DesignSystem.Spacing.xxs) {
            Text(currentTimeText)
                .font(DesignSystem.Typography.caption.monospacedDigit())
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .frame(minWidth: DesignSystem.Layout.PlaybackBar.timeLabelWidth, alignment: .trailing)
                .lineLimit(1)

            CircularThumbSlider(
                value: sliderBinding,
                range: 0...max(timeline.duration, 1),
                onEditingChanged: handleSliderEditing,
                tintColor: DesignSystem.Colors.accent.opacity(0.75),
                isDisabled: timeline.duration <= 0
            )
            .opacity(timeline.isPlaying ? (isHoveringProgress ? 1.0 : 0.0) : 1.0)
            .allowsHitTesting(!timeline.isPlaying || isHoveringProgress)
            .animation(.easeInOut(duration: DesignSystem.Layout.PlaybackBar.Spectrum.hoverTransitionDuration), value: timeline.isPlaying)
            .animation(.easeInOut(duration: DesignSystem.Layout.PlaybackBar.Spectrum.hoverTransitionDuration), value: isHoveringProgress)

            Text(remainingTimeText)
                .font(DesignSystem.Typography.caption.monospacedDigit())
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .frame(minWidth: DesignSystem.Layout.PlaybackBar.timeLabelWidth, alignment: .leading)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var progressContainer: some View {
        let spectrumSpec = DesignSystem.Layout.PlaybackBar.Spectrum.self
        let isSpectrumActive = timeline.isPlaying

        let progressContent = progressSection
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity, alignment: .center)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: spectrumSpec.hoverTransitionDuration)) {
                    isHoveringProgress = hovering
                }
                playbackController.setProgressHovering(hovering)
            }
            .background(
                Group {
                    if state.isActive {
                        HStack(spacing: DesignSystem.Spacing.xxs) {
                            // 隐藏的左侧时间文本占位符，强制频谱左边缘与 Slider 轨道左边缘像素级对齐
                            Text(currentTimeText)
                                .font(DesignSystem.Typography.caption.monospacedDigit())
                                .frame(minWidth: DesignSystem.Layout.PlaybackBar.timeLabelWidth, alignment: .trailing)
                                .lineLimit(1)
                                .opacity(0)

                            // 中间的频谱视窗，它的宽度跟 Slider 完全一致
                            ZStack {
                                LiveSpectrumView(
                                    isPlaying: timeline.isPlaying
                                )
                                .id(state.currentTrackID)
                                .cornerRadius(DesignSystem.CornerRadius.md)
                                .opacity(isSpectrumActive ? (isHoveringProgress ? spectrumSpec.hoverOpacity : 1.0) : 0)

                                Color.black.opacity(isSpectrumActive ? spectrumSpec.overlayOpacity : 0)
                                    .cornerRadius(DesignSystem.CornerRadius.md)
                            }

                            // 隐藏的右侧时间文本占位符，强制频谱右边缘与 Slider 轨道右边缘像素级对齐
                            Text(remainingTimeText)
                                .font(DesignSystem.Typography.caption.monospacedDigit())
                                .frame(minWidth: DesignSystem.Layout.PlaybackBar.timeLabelWidth, alignment: .leading)
                                .lineLimit(1)
                                .opacity(0)
                        }
                    }
                }
                .animation(
                    isSpectrumActive
                        ? .easeIn(duration: spectrumSpec.fadeInDuration)
                        : .easeOut(duration: spectrumSpec.fadeOutDuration),
                    value: isSpectrumActive
                )
            )

        progressContent
            .matchedGeometryEffect(id: "progressSection", in: playbackBarNamespace, properties: .position)
    }

    private var controlSection: some View {
        let isActive = state.isActive
        let isPlaying = timeline.isPlaying
        let canGoPrevious = !state.history.isEmpty
        let canGoNext = nextTrackAvailable
        let isQueueVisible = playbackController.isQueuePanelVisible

        return HStack(spacing: DesignSystem.Spacing.xs) {
            controlButton(
                icon: "backward.end.fill",
                isPrimary: false,
                disabled: !(isActive && canGoPrevious),
                action: playbackController.playPrevious
            )
            .help(localizationManager.string("playback.tooltip.previous"))
            .keyboardShortcut(.leftArrow, modifiers: [.command])

            controlButton(
                icon: isPlaying ? "pause.fill" : "play.fill",
                isPrimary: true,
                disabled: !isActive,
                action: playbackController.togglePlayPause
            )
            .help(localizationManager.string(isPlaying ? "playback.tooltip.pause" : "playback.tooltip.play"))
            .keyboardShortcut(.space, modifiers: [])

            controlButton(
                icon: "forward.end.fill",
                isPrimary: false,
                disabled: !(isActive && canGoNext),
                action: playbackController.playNext
            )
            .help(localizationManager.string("playback.tooltip.next"))
            .keyboardShortcut(.rightArrow, modifiers: [.command])

            Divider()
                .frame(height: 28)

            Button(action: playbackController.toggleOrder) {
                // 图标固定为 shuffle，用高亮色表示随机是否开启；repeat 图标留给循环按钮
                Image(systemName: "shuffle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(state.order == .shuffle ? DesignSystem.Colors.accent : freshControlIcon)
                    .frame(
                        width: DesignSystem.Layout.PlaybackBar.actionButtonSize,
                        height: DesignSystem.Layout.PlaybackBar.actionButtonSize
                    )
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                            .fill(controlBadgeGradient(isActive: state.order == .shuffle))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(localizationManager.string(state.order == .shuffle ? "playback.tooltip.shuffle_off" : "playback.tooltip.shuffle_on"))
            .keyboardShortcut("s", modifiers: [.option])
            .disabled(!isActive)
            .opacity(isActive ? 1 : 0.4)

            Button(action: playbackController.cycleRepeatMode) {
                Image(systemName: state.repeatMode == .one ? "repeat.1" : "repeat")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(state.repeatMode != .off ? DesignSystem.Colors.accent : freshControlIcon)
                    .frame(
                        width: DesignSystem.Layout.PlaybackBar.actionButtonSize,
                        height: DesignSystem.Layout.PlaybackBar.actionButtonSize
                    )
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                            .fill(controlBadgeGradient(isActive: state.repeatMode != .off))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(localizationManager.string(repeatTooltipKey))
            .keyboardShortcut("r", modifiers: [.option])
            .disabled(!isActive)
            .opacity(isActive ? 1 : 0.4)

            Button(action: { isVolumePopoverPresented.toggle() }) {
                Image(systemName: volumeIconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(freshControlIcon)
                    .frame(
                        width: DesignSystem.Layout.PlaybackBar.actionButtonSize,
                        height: DesignSystem.Layout.PlaybackBar.actionButtonSize
                    )
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                            .fill(controlBadgeGradient(isActive: isVolumePopoverPresented))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(localizationManager.string("playback.tooltip.volume"))
            .popover(isPresented: $isVolumePopoverPresented, arrowEdge: .top) {
                volumePopoverContent
            }

            Button(action: toggleQueuePanel) {
                Image(systemName: "list.number")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isQueueVisible ? DesignSystem.Colors.accent : freshControlIcon)
                    .frame(
                        width: DesignSystem.Layout.PlaybackBar.actionButtonSize,
                        height: DesignSystem.Layout.PlaybackBar.actionButtonSize
                    )
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                            .fill(controlBadgeGradient(isActive: isQueueVisible))
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(localizationManager.string("playback.tooltip.show_queue"))
            .disabled(!isActive)
            .opacity(isActive ? 1 : 0.4)
        }
        .frame(
            minWidth: isUltraCompactLayout ? nil : DesignSystem.Layout.PlaybackBar.controlSectionMinWidth,
            alignment: isUltraCompactLayout ? .center : .trailing
        )
        .frame(maxHeight: .infinity, alignment: .center)
        .matchedGeometryEffect(id: "controlSection", in: playbackBarNamespace)
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: {
                if let editingValue = sliderEditingValue {
                    return editingValue
                }
                return timeline.currentTime
            },
            set: { newValue in
                sliderEditingValue = newValue
            }
        )
    }

    private func handleSliderEditing(_ isEditing: Bool) {
        if isEditing {
            sliderEditingValue = timeline.currentTime
        } else {
            let target = sliderEditingValue ?? timeline.currentTime
            sliderEditingValue = nil
            playbackController.seek(to: target)
        }
    }

    private func controlButton(
        icon: String,
        isPrimary: Bool,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        let buttonSize = isPrimary
            ? DesignSystem.Layout.PlaybackBar.primaryButtonSize
            : DesignSystem.Layout.PlaybackBar.secondaryButtonSize

        return Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: isPrimary ? 20 : 20, weight: .bold))
                .frame(
                    width: buttonSize,
                    height: DesignSystem.Layout.PlaybackBar.controlButtonHeight
                )
                .foregroundColor(isPrimary ? .white : freshControlIcon)
                .background(
                    Circle()
                        .fill(controlButtonBackground(isPrimary: isPrimary))
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }

    private func toggleQueuePanel() {
        let targetVisibility = !playbackController.isQueuePanelVisible
        playbackController.updateQueueVisibility(targetVisibility)
    }

    // MARK: - 循环与音量

    private var repeatTooltipKey: String {
        switch state.repeatMode {
        case .off: return "playback.tooltip.repeat_off"
        case .all: return "playback.tooltip.repeat_all"
        case .one: return "playback.tooltip.repeat_one"
        }
    }

    private var volumeIconName: String {
        if playbackController.volume <= 0 {
            return "speaker.slash.fill"
        }
        return playbackController.volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { Double(playbackController.volume) },
            set: { playbackController.setVolume(Float($0)) }
        )
    }

    private var volumePopoverContent: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: "speaker.fill")
                .font(.system(size: 11))
                .foregroundColor(DesignSystem.Colors.textSecondary)

            CircularThumbSlider(
                value: volumeBinding,
                range: 0...1,
                onEditingChanged: nil,
                tintColor: DesignSystem.Colors.accent.opacity(0.75),
                isDisabled: false
            )
            .frame(width: DesignSystem.Layout.PlaybackBar.volumeSliderWidth, height: 20)

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 11))
                .foregroundColor(DesignSystem.Colors.textSecondary)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.xs)
    }

    private var primaryTitle: String {
        guard let track = state.currentTrack else {
            return localizationManager.string("playback.track.none")
        }
        return track.finalTitle ?? track.fileName
    }

    private var secondaryTitle: String {
        guard let track = state.currentTrack else {
            return localizationManager.string("playback.track.select")
        }
        let artist = track.finalArtist ?? localizationManager.string("common.unknown_artist")
        let album = track.finalAlbum ?? localizationManager.string("common.unknown_album")
        if artist.isEmpty && album.isEmpty {
            return track.fileName
        }
        if artist.isEmpty {
            return album
        }
        if album.isEmpty {
            return artist
        }
        return "\(artist) / \(album)"
    }

    private var currentTimeText: String {
        let current = sliderEditingValue ?? timeline.currentTime
        return current.asPlaybackTimeString
    }

    private var remainingTimeText: String {
        let current = sliderEditingValue ?? timeline.currentTime
        let duration = timeline.duration
        guard duration > 0 else { return "--:--" }
        let remaining = max(duration - current, 0)
        return "-\(remaining.asPlaybackTimeString)"
    }

    private var nextTrackAvailable: Bool {
        guard
            let currentID = state.currentTrackID,
            let currentIndex = state.queueIDs.firstIndex(of: currentID)
        else {
            return false
        }
        return currentIndex + 1 < state.queueIDs.count
    }

    private var barBackground: some View {
        let isSpectrumActive = timeline.isPlaying

        return ZStack {
            // macOS 原生毛玻璃磨砂背景
            VisualEffectView(material: .hudWindow, blendingMode: .withinWindow)
            
            // 极其克制的蓝青空气感流光渐变（静止时 0.03，播放时 0.08）
            LinearGradient(
                colors: [
                    Color(red: 0.28, green: 0.36, blue: 0.94).opacity(isSpectrumActive ? 0.08 : 0.03),
                    Color(red: 0.38, green: 0.82, blue: 0.98).opacity(isSpectrumActive ? 0.06 : 0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .animation(.easeInOut(duration: 0.35), value: isSpectrumActive)
    }

    private func controlButtonBackground(isPrimary: Bool) -> LinearGradient {
        if isPrimary {
            return LinearGradient(
                colors: [
                    Color(red: 0.31, green: 0.52, blue: 1.0),
                    Color(red: 0.46, green: 0.82, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            return LinearGradient(
                colors: [
                    Color(red: 0.25, green: 0.34, blue: 0.96).opacity(0.35),
                    Color(red: 0.39, green: 0.8, blue: 0.97).opacity(0.28)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var freshControlIcon: Color {
        Color.white.opacity(0.9)
    }

    private func controlBadgeGradient(isActive: Bool) -> LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.24, green: 0.33, blue: 0.92).opacity(isActive ? 0.42 : 0.28),
                Color(red: 0.38, green: 0.79, blue: 0.96).opacity(isActive ? 0.38 : 0.22)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var trackArtworkGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.29, green: 0.36, blue: 0.94),
                Color(red: 0.52, green: 0.85, blue: 1.0)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func shouldRevealForCurrentEvent() -> Bool {
        guard let event = NSApp.currentEvent,
              let window = event.window,
              let hitView = window.contentView?.hitTest(event.locationInWindow)
        else {
            return true
        }
        return !isInteractiveControl(hitView)
    }

    private func isInteractiveControl(_ view: NSView?) -> Bool {
        guard let view else { return false }
        if view is NSControl {
            return true
        }
        return isInteractiveControl(view.superview)
    }

    private func setupKeyMonitor() {
        #if canImport(AppKit)
        guard keyMonitor == nil else { return }
        let controller = self.playbackController
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak controller] event in
            guard let controller else { return event }
            // 如果音频不是 active，则不处理
            guard controller.state.isActive else { return event }

            // 如果当前的焦点是文本输入（字段编辑器为 NSTextView，普通输入框为 NSTextField），
            // 则不拦截按键；用类型判断替代类名字符串匹配，避免漏判子类
            if let window = NSApp.keyWindow,
               let responder = window.firstResponder,
               responder is NSText || responder is NSTextField {
                return event
            }

            // 确保没有修饰键（比如 Command / Option / Control / Shift）
            let hasModifiers = !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            if hasModifiers {
                return event
            }

            // Left Arrow: 123
            // Right Arrow: 124
            // Space Key: 49
            if event.keyCode == 123 {
                controller.seekBackward()
                return nil // 消耗事件，不传递
            } else if event.keyCode == 124 {
                controller.seekForward()
                return nil // 消耗事件，不传递
            } else if event.keyCode == 49 {
                controller.togglePlayPause()
                return nil // 消耗事件，瞬发无延迟
            }

            return event
        }
        #endif
    }

    private func removeKeyMonitor() {
        #if canImport(AppKit)
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
        #endif
    }
}

// MARK: - VisualEffectView

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

/// 频谱数据隔离视图：通过直接传入 PlaybackController 解耦高频更新数据源，
/// 利用底层的 Combine 闭包独立消费，从而实现 SwiftUI 全树播放期间零重绘。
struct LiveSpectrumView: View {
    @EnvironmentObject private var playbackController: PlaybackController

    let isPlaying: Bool

    var body: some View {
        SpectrumVisualizerView(
            controller: playbackController,
            isPlaying: isPlaying
        )
    }
}

struct MarqueeTextView: View {
    let text: String
    let font: NSFont
    let textColor: NSColor
    let width: CGFloat
    var isPlaying: Bool = true

    var body: some View {
        MarqueeNSViewRepresentable(
            text: text,
            font: font,
            textColor: textColor,
            isPlaying: isPlaying
        )
        .frame(width: width)
    }
}

struct MarqueeNSViewRepresentable: NSViewRepresentable {
    let text: String
    let font: NSFont
    let textColor: NSColor
    let isPlaying: Bool

    func makeNSView(context: Context) -> MarqueeNSView {
        let view = MarqueeNSView()
        view.text = text
        view.font = font
        view.textColor = textColor
        view.isPlaying = isPlaying
        return view
    }

    func updateNSView(_ nsView: MarqueeNSView, context: Context) {
        nsView.text = text
        nsView.font = font
        nsView.textColor = textColor
        nsView.isPlaying = isPlaying
    }
}

class MarqueeNSView: NSView {
    var text: String = "" {
        didSet {
            if oldValue != text {
                updateContent()
            }
        }
    }
    
    var font: NSFont = NSFont.systemFont(ofSize: 13) {
        didSet {
            updateContent()
        }
    }
    
    var textColor: NSColor = NSColor.labelColor {
        didSet {
            updateContent()
        }
    }
    
    var isPlaying: Bool = true {
        didSet {
            if oldValue != isPlaying {
                updateAnimationState()
            }
        }
    }
    
    var speed: Double = 35.0
    var spacing: CGFloat = 30.0
    
    private let containerLayer = CALayer()
    private let scrollLayer = CALayer()
    private let textLayer1 = CATextLayer()
    private let textLayer2 = CATextLayer()
    private var textWidth: CGFloat = 0
    private var isAppActive: Bool = true
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
        setupNotificationObservers()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
        setupNotificationObservers()
    }
    
    private func setupLayers() {
        wantsLayer = true
        layer?.masksToBounds = true
        
        containerLayer.masksToBounds = true
        containerLayer.anchorPoint = .zero
        layer?.addSublayer(containerLayer)
        
        scrollLayer.anchorPoint = .zero
        containerLayer.addSublayer(scrollLayer)
        
        for layer in [textLayer1, textLayer2] {
            layer.anchorPoint = .zero
            layer.alignmentMode = .left
            layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
            scrollLayer.addSublayer(layer)
        }
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidResignActive), name: NSApplication.didResignActiveNotification, object: nil)
    }
    
    @objc private func appDidBecomeActive() {
        isAppActive = true
        updateAnimationState()
    }
    
    @objc private func appDidResignActive() {
        isAppActive = false
        updateAnimationState()
    }
    
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        containerLayer.frame = bounds
        updateContent()
        CATransaction.commit()
    }
    
    /// 外观（浅色/深色）切换时重建图层颜色：
    /// CATextLayer 的 foregroundColor 是解析后的 CGColor，语义色（labelColor 等）
    /// 不会随系统外观自动更新，必须在此回调里重新解析
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateContent()
    }

    private func updateContent() {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let size = (text as NSString).size(withAttributes: attributes)
        textWidth = size.width

        // 在当前生效外观下解析语义色，保证深色模式取到正确的 CGColor
        var resolvedTextColor = textColor.cgColor
        effectiveAppearance.performAsCurrentDrawingAppearance {
            resolvedTextColor = textColor.cgColor
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for (layer, label) in [(textLayer1, text), (textLayer2, text)] {
            layer.string = label
            layer.font = font
            layer.fontSize = font.pointSize
            layer.foregroundColor = resolvedTextColor
            layer.frame = CGRect(x: 0, y: (bounds.height - size.height) / 2.0, width: textWidth + 10, height: size.height)
        }
        
        let containerWidth = bounds.width
        if textWidth > containerWidth {
            textLayer2.isHidden = false
            textLayer2.frame.origin.x = textWidth + spacing
            scrollLayer.frame = CGRect(x: 0, y: 0, width: (textWidth + spacing) * 2, height: bounds.height)
        } else {
            textLayer2.isHidden = true
            scrollLayer.frame = CGRect(x: 0, y: 0, width: containerWidth, height: bounds.height)
            scrollLayer.frame.origin.x = 0
        }
        
        CATransaction.commit()
        updateAnimationState()
    }
    
    private func updateAnimationState() {
        scrollLayer.removeAnimation(forKey: "marquee")
        
        let shouldAnimate = isPlaying && isAppActive && textWidth > bounds.width
        if shouldAnimate {
            let totalWidth = textWidth + spacing
            let duration = Double(totalWidth) / speed
            
            let anim = CABasicAnimation(keyPath: "position.x")
            anim.fromValue = 0
            anim.toValue = -totalWidth
            anim.duration = duration
            anim.repeatCount = .infinity
            anim.isRemovedOnCompletion = false
            anim.fillMode = .forwards
            
            scrollLayer.add(anim, forKey: "marquee")
        } else {
            scrollLayer.frame.origin.x = 0
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
