//
//  ContentView.swift
//  ReTagger
//
//  Main application view with integrated directory tree sidebar
//

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    #if SPARKLE_ENABLED
    @EnvironmentObject private var sparkleUpdater: SparkleUpdaterService
    #else
    @EnvironmentObject private var updateService: AppUpdateService
    #endif
    @EnvironmentObject private var playbackController: PlaybackController
    @State private var rootNodes: [DirectoryTreeNode] = []
    @State private var selectedDirectory: URL?
    @State private var previousSelectedDirectory: URL?
    @State private var resolvedWindow: NSWindow?
    @State private var showSettings: Bool = false
    @State private var showAuth: Bool = false
    @StateObject private var authUIState = AuthUIState()
    /// 最近一次已处理的 scanRequest ID，用于防止 onAppear + onReceive 重复触发扫描
    @State private var handledScanRequestID: UUID?
    /// 是否已经设置了默认窗口尺寸（兼容 macOS 12.4）
    @State private var hasSetDefaultSize = false

    private var effectiveDirectory: URL? {
        selectedDirectory ?? coordinator.selectedDirectory
    }

    private var currentWindowTitle: String {
        "ReTagger"
    }

    @EnvironmentObject private var localizationManager: LocalizationManager

    var body: some View {
        contentLayout
        .frame(
            minWidth: currentMinWidth,
            minHeight: currentMinHeight
        )
        .background(
            WindowAccessor { window in
                resolvedWindow = window
                applyWindowConstraints(using: window)
                if !hasSetDefaultSize {
                    hasSetDefaultSize = true
                    // 如果窗口是默认的较小尺寸，将其调整为理想默认尺寸
                    let currentSize = window.frame.size
                    if currentSize.width < 800 || currentSize.height < 600 {
                        var frame = window.frame
                        frame.size = NSSize(width: 1100, height: 720)
                        window.setFrame(frame, display: true)
                    }
                }
            }
        )
        .alert(localizationManager.string("common.error"), isPresented: .constant(coordinator.errorMessage != nil)) {
            Button(localizationManager.string("common.got_it")) {
                coordinator.clearError()
            }
        } message: {
            if let errorMessage = coordinator.errorMessage {
                Text(errorMessage)
            }
        }
        .overlay(
            Group {
                if let hudMessage = playbackController.hudMessage {
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        PlaybackHUDIconView(icon: playbackController.hudIcon)
                            .foregroundColor(.white)
                        
                        Text(hudMessage)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                    }
                    .frame(width: 140, height: 140)
                    .background(
                        RoundedRectangle(cornerRadius: 22)
                            .fill(Color.black.opacity(0.72))
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .animation(.spring(response: 0.25, dampingFraction: 0.65, blendDuration: 0), value: playbackController.hudMessage)
        )
        .onAppear {
            WindowTitleManager.update(to: currentWindowTitle)
        }
        .onChange(of: coordinator.workspaceDirectories) { _ in
            WindowTitleManager.update(to: currentWindowTitle)
        }
        .onChange(of: coordinator.currentStep) { _ in
            applyWindowConstraints()
        }
        .onAppear {
            // 关键修复：View 挂载后主动检查是否有 scanRequest 待处理。
            // 若 AppCoordinator.init() 在 View 挂载前就设置了 scanRequest（竞态），
            // onChange(of: scanRequest?.id) 不会触发，需在此处补一次扫描执行。
            if let pendingRequest = coordinator.scanRequest,
               pendingRequest.id != handledScanRequestID {
                handledScanRequestID = pendingRequest.id
                Task {
                    await performScan(for: pendingRequest)
                }
            }
        }
        .onChange(of: coordinator.selectedDirectory) { newValue in
            previousSelectedDirectory = newValue

            guard let newDir = newValue else { return }
            
            // 尝试在现有的根节点中展开
            var handled = false
            for root in rootNodes {
                if newDir.isSameOrDescendant(of: root.url) {
                    selectedDirectory = newDir
                    root.expand(to: newDir)
                    NotificationCenter.default.post(
                        name: NSNotification.Name("DirectoryChanged"),
                        object: newDir
                    )
                    handled = true
                    break
                }
            }
            
            if !handled {
                 // 如果不在现有树中，理论上不应该发生，或者是新加的？
                 // 如果发生了，可能 Coordinator 还没把新的 dir 加到 workspaceRoots
                 // 但我们会通过 syncRootNodes 处理
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(coordinator)
                #if SPARKLE_ENABLED
                .environmentObject(sparkleUpdater)
                #else
                .environmentObject(updateService)
                #endif
        }
        .onReceive(coordinator.$workspaceDirectories) { dirs in
             syncRootNodes(with: dirs)
        }
        // 使用 onReceive 而非 onChange(of: id)，可以捕获到 View 挂载后的每次赋值。
        // 与 onAppear 中的补充检查一起，构成双重保障，避免竞态条件导致扫描请求丢失。
        .onReceive(coordinator.$scanRequest) { newRequest in
            guard let request = newRequest,
                  request.id != handledScanRequestID else { return }
            handledScanRequestID = request.id
            Task {
                await performScan(for: request)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowSettings"))) { _ in
            showSettings = true
        }
    }

    private var contentLayout: some View {
        NativeSidebarSplitView(
            configuration: .init(
                sidebarMinWidth: DesignSystem.Layout.sidebarMinWidth,
                sidebarMaxWidthFraction: 0.4,
                sidebarDefaultFraction: 0.25, // 左侧侧边栏默认占用总宽度的 25%
                sidebarMiniWidth: DesignSystem.Layout.sidebarMiniWidth,
                sidebarCollapseThreshold: DesignSystem.Layout.sidebarCollapseThreshold,
                dividerWidth: DesignSystem.Layout.navigationDividerEstimate
            ),
            sidebar: sidebar,
            detail: detailColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
    }

    private var sidebar: some View {
        GeometryReader { proxy in
            let sidebarSizeClass = DesignSystem.Layout.SidebarSizeClass.from(width: proxy.size.width)
            
            VStack(spacing: 0) {
                DirectorySectionView(
                    rootNodes: rootNodes,
                    selectedDirectory: selectedDirectory,
                    onAddDirectory: addDirectory,
                    onRemoveDirectory: removeDirectory,
                    onNavigateToDirectory: navigateToDirectory,
                    recentDirectories: coordinator.recentDirectories,
                    onSelectRecentDirectory: openRecentDirectory,
                    onRemoveRecentDirectory: { entry in
                        coordinator.removeRecentDirectory(entry)
                    },
                    onClearRecentDirectories: {
                        coordinator.clearRecentDirectories()
                    },
                    onReset: resetApp,
                    sidebarSizeClass: sidebarSizeClass
                )
                .equatable()

                Spacer()

                BottomButtonsView(
                    isAuthPresented: $showAuth,
                    authService: coordinator.authService,
                    authUIState: authUIState,
                    storeService: coordinator.storeService,
                    sidebarSizeClass: sidebarSizeClass
                )
                .equatable()
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .simultaneousGesture(
                TapGesture().onEnded {
                    coordinator.playbackController.dismissQueuePanelIfNeeded()
                }
            )
        }
    }

    private var detailColumn: some View {
        detailContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .frame(
                minWidth: detailColumnMinimumWidth,
                maxWidth: .infinity,
                maxHeight: .infinity
            )
    }

    private var detailContent: some View {
        VStack(spacing: 0) {
            Group {
                switch coordinator.currentStep {
                case .directorySelection:
                    DirectorySelectionView()
                case .metadataReview:
                    MetadataReviewView()
                }
            }
        }
    }

    private var currentMinWidth: CGFloat {
        let detailRequirement: CGFloat
        switch coordinator.currentStep {
        case .metadataReview:
            detailRequirement = DesignSystem.Layout.metadataCompactDetailMinWidth
        case .directorySelection:
            detailRequirement = DesignSystem.Layout.directoryStepMinWidth
        }
        // NativeSidebarSplitView 会负责约束侧边栏，这里最低按照迷你侧边栏宽度计算窗口下限
        return DesignSystem.Layout.sidebarMiniWidth
            + detailRequirement
            + DesignSystem.Layout.navigationDividerEstimate
            + DesignSystem.Spacing.sm
    }

    private var currentMinHeight: CGFloat {
        switch coordinator.currentStep {
        case .metadataReview:
            return DesignSystem.Layout.metadataStepMinHeight
        case .directorySelection:
            return DesignSystem.Layout.directoryStepMinHeight
        }
    }

    private var detailColumnMinimumWidth: CGFloat {
        switch coordinator.currentStep {
        case .metadataReview:
            return DesignSystem.Layout.metadataCompactDetailMinWidth
        case .directorySelection:
            return DesignSystem.Layout.directoryStepMinWidth
        }
    }

    private var detailColumnIdealWidth: CGFloat {
        switch coordinator.currentStep {
        case .metadataReview:
            return DesignSystem.Layout.detailIdealWidth
        case .directorySelection:
            return DesignSystem.Layout.directoryStepMinWidth
        }
    }

    private func applyWindowConstraints(using window: NSWindow? = nil) {
        guard let targetWindow = window ?? resolvedWindow else { return }
        let minSize = NSSize(width: currentMinWidth, height: currentMinHeight)
        if targetWindow.contentMinSize != minSize {
            targetWindow.contentMinSize = minSize
        }
    }

    // MARK: - Directory Management

    private func addDirectory() {
        Task {
            guard let selectedURLs = await coordinator.fileSystemService.selectFilesOrDirectories() else {
                return
            }
            await MainActor.run {
                coordinator.addWorkspaceDirectories(selectedURLs)
            }
        }
    }
    
    // 这里的 selectNewDirectory 已经被 onAddDirectory 替代了。

    private func openRecentDirectory(_ entry: RecentDirectoryEntry) {
        Task { @MainActor in
            let coordinator = self.coordinator
            let resolvedURL = await Task.detached(priority: .userInitiated) {
                coordinator.resolveRecentDirectoryURL(entry)
            }.value
            
            guard let resolvedURL = resolvedURL else {
                coordinator.removeRecentDirectory(entry)
                coordinator.setError(
                    localizationManager.string("error.history_directory_denied", arguments: entry.displayName)
                )
                return
            }

            // 激活安全域访问以确保 fileExists 检查能正确执行（防止因沙盒限制导致误判目录不存在而将其移出历史记录）
            let hasAccess = resolvedURL.startAccessingSecurityScopedResource()
            let exists = await Task.detached(priority: .userInitiated) {
                FileManager.default.fileExists(atPath: resolvedURL.path)
            }.value
            if hasAccess {
                resolvedURL.stopAccessingSecurityScopedResource()
            }

            guard exists else {
                coordinator.removeRecentDirectory(entry)
                coordinator.setError(
                    localizationManager.string(
                        "error.directory_moved_or_deleted",
                        arguments: resolvedURL.lastPathComponent
                    )
                )
                return
            }
            
            // Logic to add to workspace with permission handling
            if coordinator.activateSecurityScope(for: resolvedURL) {
                coordinator.addWorkspaceDirectories([resolvedURL])
                return
            }

            let message = localizationManager.string(
                "permission.directory_reauth_prompt",
                arguments: resolvedURL.lastPathComponent
            )
            if let granted = await coordinator.fileSystemService.requestAccess(
                to: resolvedURL,
                message: message
            ) {
                // If granted, add
                coordinator.addWorkspaceDirectories([granted])
            } else {
                coordinator.setError(
                    localizationManager.string("error.directory_denied_path", arguments: resolvedURL.path)
                )
            }
        }
    }
    
    private func removeDirectory(_ url: URL) {
        coordinator.removeWorkspaceDirectory(url)
    }

    private func syncRootNodes(with dirs: [URL]) {
        // 1. Remove nodes no longer in workspace
        rootNodes.removeAll { node in
            !dirs.contains(where: { $0.standardizedFileURL.path == node.url.standardizedFileURL.path })
        }
        
        // 2. Add new nodes
        for dir in dirs {
            if !rootNodes.contains(where: { $0.url.standardizedFileURL.path == dir.standardizedFileURL.path }) {
                 print("🌲 Initializing directory tree for: \(dir.path)")
                 _ = coordinator.activateSecurityScope(for: dir)
                 let node = DirectoryTreeNode(url: dir)
                 node.loadChildren(force: true)
                 node.isExpanded = true
                 rootNodes.append(node)
            }
        }
    }

    @discardableResult
    private func handleDirectorySelection(_ url: URL, triggerScan: Bool = false) -> Bool {
        guard coordinator.activateSecurityScope(for: url) else {
            coordinator.setError(
                localizationManager.string("error.directory_denied_path", arguments: url.path)
            )
            return false
        }
        let normalizedURL = url.standardizedFileURL
        selectedDirectory = url
        if let root = rootNodes.first(where: { normalizedURL.isSameOrDescendant(of: $0.url) }) {
            root.expand(to: normalizedURL)
        }
        coordinator.selectedDirectory = url
        // 目录不在工作区时加入工作区（内部会触发扫描），已在工作区时仅追加式重扫
        if !coordinator.workspaceDirectories.contains(where: { $0.path == normalizedURL.path }) {
             if triggerScan {
                  coordinator.addWorkspaceDirectories([url])
             }
        } else if triggerScan {
             coordinator.triggerScan(for: [url], includeSubdirectories: coordinator.includeSubdirectories, isAppend: true)
        }

        return true
    }

    @MainActor
    private func navigateToDirectory(_ targetURL: URL) {
        Task { @MainActor in
            switch await resolveAccessibleDirectory(for: targetURL) {
            case .granted(let accessibleURL):
                handleDirectorySelection(accessibleURL, triggerScan: true)
            case .cancelled:
                break
            case .denied(let deniedURL):
                coordinator.setError(
                    localizationManager.string("error.directory_denied_path", arguments: deniedURL.path)
                )
            }
        }
    }

    @MainActor
    private func resolveAccessibleDirectory(for url: URL) async -> DirectoryAccessResult {
        let permissions = coordinator.fileSystemService.checkPermissions(for: url)
        if permissions.canRead {
            return .granted(url)
        }

        let displayName = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        let promptMessage = localizationManager.string(
            "permission.request_directory",
            arguments: displayName
        )

        if let grantedURL = await coordinator.fileSystemService.requestAccess(
            to: url,
            message: promptMessage
        ) {
            let grantedPermissions = coordinator.fileSystemService.checkPermissions(for: grantedURL)
            if grantedPermissions.canRead {
                return .granted(grantedURL)
            } else {
                return .denied(grantedURL)
            }
        }

        return .cancelled
    }

    // MARK: - Scanning
    
    @MainActor
    private func performScan(for request: DirectoryScanRequest) async {
        guard !request.urls.isEmpty else {
            coordinator.clearScanRequest(id: request.id)
            return
        }
        
        if !request.isIncremental {
            coordinator.audioFiles = []
        }

        do {
            var allMetadata: [AudioMetadata] = []
            
            for url in request.urls {
                // 激活安全域访问
                let activated: Bool
                if !url.isDirectory {
                    activated = await coordinator.ensureParentDirectoryAccess(for: url) && coordinator.activateSecurityScope(for: url)
                } else {
                    activated = coordinator.activateSecurityScope(for: url)
                }
                
                guard activated else {
                    if url.isDirectory {
                        let message = localizationManager.string(
                            "permission.directory_reauth_prompt_brackets",
                            arguments: url.lastPathComponent
                        )
                        if let grantedURL = await coordinator.fileSystemService.requestAccess(
                            to: url,
                            message: message
                        ) {
                            coordinator.triggerScan(
                                for: [grantedURL],
                                includeSubdirectories: request.includeSubdirectories,
                                isAppend: true
                            )
                        } else {
                            coordinator.removeWorkspaceDirectory(url)
                            coordinator.setError(
                                localizationManager.string("error.directory_denied_path", arguments: url.path)
                            )
                        }
                    } else {
                        // 对于单文件导入，用户取消授权父目录时，静默清理左边栏（workspaceDirectories）中残留的该曲目路径，不再弹窗报错
                        coordinator.removeWorkspaceDirectory(url)
                    }
                    continue
                }

                let metadataList = try await coordinator.loadMetadata(
                    for: url,
                    includeSubdirectories: request.includeSubdirectories,
                    updateState: false
                )
                allMetadata.append(contentsOf: metadataList)
            }
            
            if coordinator.scanRequest?.id != request.id { return }

            if request.isIncremental {
                // 过滤掉已存在的文件，防止与 handleExternalDirectoryChange 竞态导致重复
                let existingIDs = Set(coordinator.audioFiles.map(\.id))
                let newFiles = allMetadata.filter { !existingIDs.contains($0.id) }
                if !newFiles.isEmpty {
                    coordinator.audioFiles.append(contentsOf: newFiles)
                    coordinator.playbackController.append(newFiles)
                }
            } else {
                coordinator.audioFiles = allMetadata
                if coordinator.isRestoringWorkspace {
                    if let lastTrackPath = coordinator.settings.lastPlayingTrackPath,
                       let targetTrack = allMetadata.first(where: { $0.filePath.path == lastTrackPath }) {
                        let lastTrackTime = UserDefaults.standard.double(forKey: "lastPlayingTrackTime")
                        coordinator.playbackController.restorePlaybackQueue(
                            queue: allMetadata,
                            selectTrack: targetTrack,
                            time: lastTrackTime
                        )
                    }
                }
            }
            
            coordinator.clearScanRequest(id: request.id)

            // 如果在目录选择步骤且有文件，自动进入下一步
            if coordinator.currentStep == .directorySelection && !coordinator.audioFiles.isEmpty {
                try? await Task.sleep(nanoseconds: 300_000_000)
                coordinator.nextStep()
            }
        } catch {
            coordinator.clearScanRequest(id: request.id)
            coordinator.setError(
                localizationManager.string("error.scan_directory_failed", arguments: error.localizedDescription)
            )
        }
    }

    private func resetApp() {
        coordinator.reset()
        rootNodes = []
        selectedDirectory = nil
    }
}

private enum DirectoryAccessResult {
    case granted(URL)
    case cancelled
    case denied(URL)
}

#Preview {
    let localizationManager = LocalizationManager(language: .simplifiedChinese)
    let coordinator = AppCoordinator(localizationManager: localizationManager)
    return ContentView()
        .environmentObject(coordinator)
        .environmentObject(coordinator.playbackController)
        .environmentObject(coordinator.playbackController.timelineStore)
        .environmentObject(coordinator.playbackController.spectrumDataStore)
        .environmentObject(localizationManager)
        .environmentObject(AppUpdateService())
        .frame(width: 1200, height: 800)
}
