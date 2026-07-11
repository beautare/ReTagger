//
//  DirectorySelectionView.swift
//  ReTagger
//
//  Improved with unified design system
//

import SwiftUI
import AppKit

struct DirectorySelectionView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @State private var isScanning = false
    @State private var scanProgress: Double = 0.0
    @State private var hoveredEntryID: String? = nil

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: DesignSystem.Spacing.xxxl) {
                    // 顶部标题区
                    headerSection

                    Spacer()

                    // 中间操作区
                    actionSection

                    Spacer()

                    // 底部提示区
                    infoSection
                }
                .padding(DesignSystem.Spacing.xl)
                .frame(maxWidth: .infinity)
                .frame(minHeight: proxy.size.height, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: coordinator.scanRequest?.id) { newID in
            withAnimation {
                isScanning = (newID != nil)
            }
        }
        .task {
            if coordinator.scanRequest != nil {
                isScanning = true
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            headerIcon

            VStack(spacing: DesignSystem.Spacing.xs) {
                Text(localizationManager.string("directory.title"))
                    .font(DesignSystem.Typography.title)

                Text(localizationManager.string("directory.subtitle", arguments: AudioFormatSupport.displayNameList))
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
        .padding(.top, DesignSystem.Spacing.xl)
    }

    @ViewBuilder
    private var headerIcon: some View {
        let image = Image(systemName: DesignSystem.Icons.folder)
            .font(.system(size: 64, weight: .light))
            .foregroundColor(DesignSystem.Colors.primary)

        if #available(macOS 14.0, *) {
            image.symbolEffect(.bounce, value: coordinator.workspaceDirectories)
        } else {
            image
        }
    }

    // MARK: - Action Section

    private var actionSection: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // 选择目录按钮
            Button(action: selectDirectory) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: DesignSystem.Icons.folder)
                        .font(.system(size: 20))
                    Text(localizationManager.string("directory.select_button"))
                        .font(DesignSystem.Typography.bodyBold)
                }
                .frame(minWidth: 200)
                .primaryButtonStyle()
            }
            .buttonStyle(.plain)
            .disabled(isScanning)

            if !coordinator.recentDirectories.isEmpty {
                recentDirectoriesSection
            }

            // 已选择目录信息
            if !coordinator.workspaceDirectories.isEmpty {
                selectedDirectoryInfo(coordinator.workspaceDirectories)
            }

            // 扫描状态
            if isScanning {
                scanningProgress
            } else if !coordinator.workspaceDirectories.isEmpty && !coordinator.audioFiles.isEmpty {
                scanCompleteInfo
            }
        }
        .animation(DesignSystem.Animation.spring, value: isScanning)
        .animation(DesignSystem.Animation.spring, value: coordinator.workspaceDirectories)
    }

    // MARK: - Selected Directory Info
    private var recentDirectoriesSection: some View {
        let displayedEntries = Array(coordinator.recentDirectories.prefix(5))
        let hasEntries = !displayedEntries.isEmpty

        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            Text(localizationManager.string("directory.recent"))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            if !hasEntries {
                Text(localizationManager.string("directory.no_history"))
                    .font(DesignSystem.Typography.caption2)
                    .foregroundColor(DesignSystem.Colors.textTertiary)
            } else {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    ForEach(displayedEntries) { entry in
                        recentDirectoryButton(for: entry)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func recentDirectoryButton(for entry: RecentDirectoryEntry) -> some View {
        HStack(spacing: 0) {
            if hoveredEntryID == entry.id {
                Button(action: { coordinator.removeRecentDirectory(entry) }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .padding(.leading, DesignSystem.Spacing.md)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
                .help("从历史中移除")
            }

            Button(action: { openRecentDirectory(entry) }) {
                Text(entry.path)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .background(DesignSystem.Colors.backgroundTertiary.opacity(0.9))
        .cornerRadius(DesignSystem.CornerRadius.md)
        .onHover { isHovered in
            withAnimation(.easeOut(duration: 0.15)) {
                hoveredEntryID = isHovered ? entry.id : nil
            }
        }
    }

    private func selectedDirectoryInfo(_ directories: [URL]) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(localizationManager.string("directory.selected"))
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)

            if directories.count == 1 {
                Text(directories[0].path)
                    .font(DesignSystem.Typography.monoBody)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .padding(DesignSystem.Spacing.sm)
                    .frame(maxWidth: 500)
                    .background(DesignSystem.Colors.backgroundTertiary)
                    .cornerRadius(DesignSystem.CornerRadius.sm)
            } else {
                Text(localizationManager.string("directory.selected_multiple", arguments: directories.count))
                    .font(DesignSystem.Typography.bodyBold)
                    .padding(DesignSystem.Spacing.sm)
                    .frame(maxWidth: 500)
                    .background(DesignSystem.Colors.backgroundTertiary)
                    .cornerRadius(DesignSystem.CornerRadius.sm)
            }
        }
        .transition(.opacity.combined(with: .scale))
    }

    // MARK: - Scanning Progress

    private var scanningProgress: some View {
        let titleKey = coordinator.isRestoringWorkspace ? "restore.loading" : "directory.scanning"
        let detailText = coordinator.isRestoringWorkspace
            ? localizationManager.string("restore.loading_detail")
            : localizationManager.string("directory.found_files", arguments: coordinator.audioFiles.count)

        return ProgressBannerView(
            message: localizationManager.string(titleKey),
            progress: scanProgress,
            detail: detailText
        )
        .frame(maxWidth: 400)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - Scan Complete Info

    private var scanCompleteInfo: some View {
        StatusCardView(
            style: .success,
            title: localizationManager.string("directory.found_count", arguments: coordinator.audioFiles.count),
            message: localizationManager.string("directory.ready_next")
        )
        .frame(maxWidth: 400)
        .transition(.scale.combined(with: .opacity))
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            infoItem(
                icon: "arrow.down.circle",
                text: localizationManager.string("directory.info.recursive")
            )
            infoItem(
                icon: DesignSystem.Icons.music,
                text: localizationManager.string("directory.info.formats", arguments: AudioFormatSupport.displayNameList)
            )
            infoItem(
                icon: "tag",
                text: localizationManager.string("directory.info.read_tags")
            )
        }
        .font(DesignSystem.Typography.caption)
        .foregroundColor(DesignSystem.Colors.textSecondary)
    }

    private func infoItem(icon: String, text: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: icon)
                .frame(width: 20)
            Text(text)
        }
    }

    // MARK: - Actions

    @MainActor
    private func selectDirectory() {
        Task { @MainActor in
            guard let selectedURLs = await coordinator.fileSystemService.selectFilesOrDirectories() else {
                return
            }

            coordinator.triggerScan(
                for: selectedURLs,
                includeSubdirectories: coordinator.includeSubdirectories
            )
        }
    }

    @MainActor
    private func openRecentDirectory(_ entry: RecentDirectoryEntry) {
        Task { @MainActor in
            let coordinator = self.coordinator
            let resolvedURL = await Task.detached(priority: .userInitiated) {
                coordinator.resolveRecentDirectoryURL(entry)
            }.value
            
            guard let url = resolvedURL else {
                coordinator.removeRecentDirectory(entry)
                coordinator.setError(
                    localizationManager.string("error.directory_denied_path", arguments: entry.displayName)
                )
                return
            }

            let standardizedURL = url.standardizedFileURL
            
            // 激活安全域访问以确保 fileExists 检查能正确执行（防止因沙盒限制导致误判目录不存在而将其移出历史记录）
            let hasAccess = url.startAccessingSecurityScopedResource()
            let exists = await Task.detached(priority: .userInitiated) {
                FileManager.default.fileExists(atPath: standardizedURL.path)
            }.value
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }

            guard exists else {
                coordinator.removeRecentDirectory(entry)
                coordinator.setError(
                    localizationManager.string(
                        "error.directory_moved_or_deleted",
                        arguments: standardizedURL.lastPathComponent
                    )
                )
                return
            }

            coordinator.triggerScan(
                for: [url],
                includeSubdirectories: coordinator.includeSubdirectories
            )
        }
    }



    @EnvironmentObject private var localizationManager: LocalizationManager
}

#Preview {
    let localizationManager = LocalizationManager(language: .simplifiedChinese)
    DirectorySelectionView()
        .environmentObject(AppCoordinator(localizationManager: localizationManager))
        .environmentObject(localizationManager)
}
