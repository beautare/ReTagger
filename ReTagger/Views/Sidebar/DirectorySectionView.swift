//
//  DirectorySectionView.swift
//  ReTagger
//
//  Directory tree section - improved with design system
//

import SwiftUI

/// 目录树区域组件
struct DirectorySectionView: View, Equatable {
    static func == (lhs: DirectorySectionView, rhs: DirectorySectionView) -> Bool {
        lhs.rootNodes == rhs.rootNodes &&
        lhs.selectedDirectory == rhs.selectedDirectory &&
        lhs.recentDirectories == rhs.recentDirectories &&
        lhs.sidebarSizeClass == rhs.sidebarSizeClass &&
        lhs.isHistoryPopoverPresented == rhs.isHistoryPopoverPresented &&
        lhs.tappedHistoryEntryID == rhs.tappedHistoryEntryID &&
        lhs.hoveredEntryID == rhs.hoveredEntryID
    }

    @EnvironmentObject var localizationManager: LocalizationManager
    @EnvironmentObject private var playbackController: PlaybackController
    let rootNodes: [DirectoryTreeNode]
    let selectedDirectory: URL?
    let onAddDirectory: () -> Void
    let onRemoveDirectory: (URL) -> Void
    let onNavigateToDirectory: (URL) -> Void
    let recentDirectories: [RecentDirectoryEntry]
    let onSelectRecentDirectory: (RecentDirectoryEntry) -> Void
    let onRemoveRecentDirectory: (RecentDirectoryEntry) -> Void
    let onClearRecentDirectories: () -> Void
    let onReset: () -> Void
    /// 侧边栏尺寸等级，按阈值驱动视图布局
    var sidebarSizeClass: DesignSystem.Layout.SidebarSizeClass = .regular
    @State private var isHistoryPopoverPresented = false
    @State private var tappedHistoryEntryID: String?
    @State private var hoveredEntryID: String? = nil

    /// 是否处于迷你列模式
    private var isMini: Bool {
        sidebarSizeClass == .mini
    }

    /// 是否处于紧凑模式（标准模式下宽度较窄）
    private var isCompact: Bool {
        sidebarSizeClass == .compact
    }

    /// 格式化的版本号字符串
    private var versionString: String {
        let version = AppConfiguration.InfoPlist.appVersion
        let build = AppConfiguration.InfoPlist.buildNumber
        return "v\(version) (\(build))"
    }

    private var logoIcon: some View {
        Image(systemName: DesignSystem.Icons.musicList)
            .font(.system(size: 20, weight: .regular))
            .foregroundColor(DesignSystem.Colors.primary)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isMini {
                miniHeaderView
                miniContentView
            } else {
                // 目录树标题栏
                headerView
                // 目录树内容
                contentView
            }
        }
    }

    // MARK: - 迷你模式 Header

    private var miniHeaderView: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            logoIcon
                .help("ReTagger \(versionString)")
            
            Divider()
                .padding(.horizontal, DesignSystem.Spacing.xs)
            
            Button(action: onAddDirectory) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 16))
                    .foregroundColor(DesignSystem.Colors.primary)
            }
            .buttonStyle(.plain)
            .help(localizationManager.string("action.add_folder"))

            Button(action: onReset) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 16))
                    .foregroundColor(rootNodes.isEmpty ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.primary)
            }
            .buttonStyle(.plain)
            .help(localizationManager.string("action.close_all"))
            .disabled(rootNodes.isEmpty)
            .opacity(rootNodes.isEmpty ? 0.4 : 1.0)

            Button(action: { isHistoryPopoverPresented.toggle() }) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 16))
                    .foregroundColor(DesignSystem.Colors.primary)
            }
            .buttonStyle(.plain)
            .help(localizationManager.string("action.history"))
            .popover(isPresented: $isHistoryPopoverPresented, arrowEdge: .trailing) {
                historyPopoverContent
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.backgroundSecondary)
    }

    // MARK: - 迷你模式内容：首字符缩略

    private var miniContentView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            if rootNodes.isEmpty {
                VStack {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 20))
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.lg)
            } else {
                VStack(spacing: DesignSystem.Spacing.sm) {
                    ForEach(rootNodes) { node in
                        miniDirectoryBadge(node)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.sm)
            }
        }
    }

    /// 迷你列中每个目录的首字符缩略 badge
    private func miniDirectoryBadge(_ node: DirectoryTreeNode) -> some View {
        let isAssociated = isCurrentPlayingNode(node)
        let isPlaying = isAssociated && playbackController.isPlaying
        
        let tooltipSuffix: String
        if isAssociated {
            tooltipSuffix = " (" + localizationManager.string(isPlaying ? "playback.status.playing" : "playback.status.selected") + ")"
        } else {
            tooltipSuffix = ""
        }
        
        return Button(action: { onNavigateToDirectory(node.url) }) {
            Text(isAssociated ? "🎵" : meaningfulInitial(from: node.name))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                        .fill(isAssociated ? DesignSystem.Colors.success : DesignSystem.Colors.primary.opacity(0.8))
                )
        }
        .buttonStyle(.plain)
        .help(node.url.path + tooltipSuffix)
    }

    /// 从目录名中提取有意义的首字符
    private func meaningfulInitial(from name: String) -> String {
        // 跳过 "." 开头的隐藏目录前缀
        let cleanName = name.hasPrefix(".") ? String(name.dropFirst()) : name
        guard let first = cleanName.first else { return "📁" }
        
        // 数字开头：取前两个字符
        if first.isNumber {
            return String(cleanName.prefix(2))
        }
        // 其他情况：取首字符大写
        return String(first).uppercased()
    }

    // MARK: - 标准模式 Header

    private var headerView: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            logoIcon
            
            if !isCompact {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localizationManager.string("ai.app_subtitle"))
                        .font(DesignSystem.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                    
                    Text(versionString)
                        .font(DesignSystem.Typography.caption2)
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            HStack(spacing: DesignSystem.Spacing.sm) {
                Button(action: onAddDirectory) {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.Colors.primary)
                }
                .buttonStyle(.plain)
                .help(localizationManager.string("action.add_folder"))

                Button(action: onReset) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 14))
                        .foregroundColor(rootNodes.isEmpty ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.primary)
                }
                .buttonStyle(.plain)
                .help(localizationManager.string("action.close_all"))
                .disabled(rootNodes.isEmpty)
                .opacity(rootNodes.isEmpty ? 0.4 : 1.0)

                Button(action: { isHistoryPopoverPresented.toggle() }) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14))
                        .foregroundColor(DesignSystem.Colors.primary)
                }
                .help(localizationManager.string("action.history"))
                .buttonStyle(.plain)
                .popover(isPresented: $isHistoryPopoverPresented, arrowEdge: .bottom) {
                    historyPopoverContent
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background(DesignSystem.Colors.backgroundSecondary)
    }

    // MARK: - 标准模式 Content

    private var contentView: some View {
        ScrollView(.vertical, showsIndicators: true) {
            if rootNodes.isEmpty {
                emptyStateView
            } else {
                VStack(spacing: DesignSystem.Spacing.xxs) {
                    ForEach(rootNodes) { node in
                        rootFolderSection(node)
                    }
                }
                .padding(.vertical, DesignSystem.Spacing.xxs)
            }
        }
    }
    
    private func rootFolderSection(_ rootNode: DirectoryTreeNode) -> some View {
        let isAssociated = isCurrentPlayingNode(rootNode)
        let isPlaying = isAssociated && playbackController.isPlaying
        
        return HStack(spacing: DesignSystem.Spacing.sm) {
            if #available(macOS 14.0, *) {
                Image(systemName: isPlaying ? "waveform" : (rootNode.isDirectory ? "folder.fill" : "music.note"))
                    .font(.system(size: 14))
                    .foregroundColor(isAssociated ? DesignSystem.Colors.success : DesignSystem.Colors.primary)
                    .contentTransition(.symbolEffect(.replace))
            } else {
                Image(systemName: isPlaying ? "waveform" : (rootNode.isDirectory ? "folder.fill" : "music.note"))
                    .font(.system(size: 14))
                    .foregroundColor(isAssociated ? DesignSystem.Colors.success : DesignSystem.Colors.primary)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(rootNode.name)
                    .font(isAssociated ? DesignSystem.Typography.body.bold() : DesignSystem.Typography.body)
                    .foregroundColor(isAssociated ? DesignSystem.Colors.success : DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                
                Text(rootNode.url.path)
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(isAssociated ? DesignSystem.Colors.success.opacity(0.8) : DesignSystem.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            if isAssociated {
                HStack(spacing: 4) {
                    Circle()
                        .fill(isPlaying ? DesignSystem.Colors.success : DesignSystem.Colors.textSecondary)
                        .frame(width: 6, height: 6)
                    Text(isPlaying ? localizationManager.string("playback.status.playing") : localizationManager.string("playback.status.selected"))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(isPlaying ? DesignSystem.Colors.success : DesignSystem.Colors.textSecondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(isPlaying ? DesignSystem.Colors.successBackground(0.12) : DesignSystem.Colors.backgroundTertiary.opacity(0.8))
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
            
            Button(action: { onRemoveDirectory(rootNode.url) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
            .buttonStyle(.plain)
            .help(localizationManager.string("action.remove_directory"))
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                .fill(isAssociated ? DesignSystem.Colors.successBackground(0.08) : DesignSystem.Colors.backgroundTertiary.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                .stroke(isAssociated ? DesignSystem.Colors.success.opacity(0.24) : Color.clear, lineWidth: 1)
        )
        .padding(.horizontal, DesignSystem.Spacing.sm)
    }

    private func isCurrentPlayingNode(_ rootNode: DirectoryTreeNode) -> Bool {
        guard let currentTrack = playbackController.state.currentTrack else {
            return false
        }
        
        let nodePath = rootNode.url.standardizedFileURL.path
        let trackPath = currentTrack.filePath.standardizedFileURL.path
        
        if rootNode.isDirectory {
            return trackPath.hasPrefix(nodePath + "/")
        } else {
            return trackPath == nodePath
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 36))
                .foregroundColor(DesignSystem.Colors.textTertiary)

            VStack(spacing: DesignSystem.Spacing.xxs) {
                Text(localizationManager.string("sidebar.empty_title"))
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundColor(DesignSystem.Colors.textSecondary)

                Text(localizationManager.string("sidebar.empty_hint"))
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignSystem.Spacing.lg)
    }

    private var historyPopoverContent: some View {
        let entries = Array(recentDirectories.prefix(50))

        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(localizationManager.string("sidebar.recent_title"))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            if entries.isEmpty {
                Text(localizationManager.string("sidebar.no_history"))
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 {
                                Divider()
                            }
                            HStack(spacing: 4) {
                                ZStack {
                                    if hoveredEntryID == entry.id {
                                        Button {
                                            onRemoveRecentDirectory(entry)
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 11))
                                                .foregroundColor(DesignSystem.Colors.textTertiary)
                                        }
                                        .buttonStyle(.plain)
                                        .transition(.opacity)
                                        .help(localizationManager.string("sidebar.remove_from_history"))
                                    }
                                }
                                .frame(width: 14)

                                Button {
                                    tappedHistoryEntryID = entry.id
                                    Task { @MainActor in
                                        try? await Task.sleep(nanoseconds: 200_000_000)
                                        if tappedHistoryEntryID == entry.id {
                                            tappedHistoryEntryID = nil
                                        }
                                    }
                                    isHistoryPopoverPresented = false
                                    onSelectRecentDirectory(entry)
                                } label: {
                                    HistoryRowLabel(
                                        title: entry.path,
                                        isHighlighted: tappedHistoryEntryID == entry.id,
                                        isPlayingMarquee: hoveredEntryID == entry.id
                                    )
                                }
                                .buttonStyle(HistoryRowButtonStyle())
                                .accessibilityLabel(Text(entry.displayName))
                            }
                            .contentShape(Rectangle())
                            .onHover { isHovered in
                                withAnimation(.easeOut(duration: 0.12)) {
                                    hoveredEntryID = isHovered ? entry.id : nil
                                }
                            }
                        }
                    }
                    .padding(.vertical, DesignSystem.Spacing.xxs)
                }
                .frame(maxHeight: 280)

                Divider()

                Button(action: {
                    isHistoryPopoverPresented = false
                    onClearRecentDirectories()
                }) {
                    HStack {
                        Spacer()
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                        Text(localizationManager.string("action.clear_all_history"))
                            .font(DesignSystem.Typography.caption)
                        Spacer()
                    }
                    .foregroundColor(DesignSystem.Colors.error)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.xs)
        .padding(.vertical, DesignSystem.Spacing.md)
        .frame(width: 260)
    }
}

private struct HistoryRowLabel: View {
    let title: String
    let isHighlighted: Bool
    let isPlayingMarquee: Bool

    var body: some View {
        HStack(spacing: 0) {
            MarqueeTextView(
                text: title,
                font: NSFont.systemFont(ofSize: 11, weight: .regular),
                textColor: NSColor.labelColor,
                width: 218,
                isPlaying: isPlayingMarquee
            )
            .frame(height: 16)
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
        .padding(.horizontal, 4) // 减小水平 padding 紧凑排布
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xs)
                .fill(DesignSystem.Colors.primary.opacity(isHighlighted ? 0.12 : 0))
        )
        .animation(DesignSystem.Animation.fast, value: isHighlighted)
    }
}

private struct HistoryRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xs)
                    .fill(DesignSystem.Colors.backgroundTertiary.opacity(configuration.isPressed ? 0.4 : 0))
                    .allowsHitTesting(false)
            )
            .animation(DesignSystem.Animation.fast, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

#Preview {
    DirectorySectionView(
        rootNodes: [],
        selectedDirectory: nil,
        onAddDirectory: {},
        onRemoveDirectory: { _ in },
        onNavigateToDirectory: { _ in },
        recentDirectories: [],
        onSelectRecentDirectory: { _ in },
        onRemoveRecentDirectory: { _ in },
        onClearRecentDirectories: {},
        onReset: {}
    )
    .environmentObject(PlaybackController(service: AudioPlaybackService(), defaultOrder: .sequential))
    .environmentObject(LocalizationManager(language: .simplifiedChinese))
    .frame(width: 280, height: 500)
}
