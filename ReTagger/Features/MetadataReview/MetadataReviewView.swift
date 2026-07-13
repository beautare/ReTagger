//
//  MetadataReviewView.swift
//  ReTagger
//
//  Metadata review with file list (directory tree now in ContentView sidebar)
//

import SwiftUI
import AppKit
import Combine
import OSLog
import AVFoundation

struct MetadataReviewView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var playbackController: PlaybackController
    @EnvironmentObject var localizationManager: LocalizationManager
    static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
    @State var isProcessing = false
    @State var processingProgress: Double = 0.0
    @State var selectedProvider: AIProvider = .gemini
    @State var includeSubdirectories = true
    @State var currentDirectory: URL?
    @State var currentFiles: [AudioMetadata] = []
    @State var tableSelection: Set<AudioMetadata.ID> = []
    @State var stackedDetailPanelHeight: CGFloat = DesignSystem.Layout.detailPanelStackedMinHeight
    @State var stackedDetailDragStartHeight: CGFloat?
    /// 拖拽中的预览高度：仅驱动一条轻量预览线，松手时一次性提交到 stackedDetailPanelHeight，
    /// 避免拖拽期间每帧触发表格与详情面板的全量重布局
    @State var stackedDetailDragPreviewHeight: CGFloat?
    @State var pendingScrollTarget: AudioMetadata.ID?
    @State var pendingTrashItems: [AudioMetadata] = []
    @State var isShowingTrashConfirmation = false
    @State var isApplyingCorrections = false
    @State var applyProgress: Double = 0.0
    @State var sortOrder: [KeyPathComparator<AudioMetadata>] = [
        KeyPathComparator(\AudioMetadata.sortableFileName, order: .forward)
    ]
    @State var fieldSelections: [AudioMetadata.ID: Set<MetadataField>] = [:]
    @State var pendingConfirmations: Set<AudioMetadata.ID> = []
    @State var pendingUndoRequests: Set<AudioMetadata.ID> = []
    @State var defaultFieldSelection: Set<MetadataField> = Set(MetadataField.allCases)
    @State var hasLoadedDefaultFieldSelection = false
    @State var pendingBulkAction: PendingBulkAction?
    @State var playbackBarHeight: CGFloat = 0
    @State var columnConfiguration: TableColumnConfiguration = .default
    @State var isApplyingColumnConfiguration = false
    @State var searchText: String = ""
    @State var isShowingBackupAccessDeniedAlert = false
    @State var isShowingConflictResolution = false
    @State var pendingConflicts: [ConflictGroup] = []
    /// 表格与详情面板是否使用左右分栏布局（由宽度断点驱动，带动画切换）
    @State var isInlineLayout: Bool = true
    /// 右侧详情面板的绝对宽度，在 inline ↔ stacked 布局切换时保持记忆
    @State var savedDetailWidth: CGFloat?
    /// 顶部栏的真实可用宽度，用于驱动自适应堆叠
    @State private var topBarWidth: CGFloat = 800
    /// 缓存的过滤结果，避免计算属性被多次求值
    @State var cachedFilteredFiles: [AudioMetadata] = []
    /// 防抖后的搜索文本，用于触发实际过滤计算
    @State var debouncedSearchText: String = ""
    
    /// 过滤后的文件列表（读取缓存，不再每次重新计算）
    var filteredFiles: [AudioMetadata] {
        cachedFilteredFiles
    }

    /// 在后台线程执行过滤计算，结果回到主线程更新缓存
    /// 执行过滤计算，更新缓存
    private func updateFilteredFiles() {
        let query = debouncedSearchText
        let files = currentFiles
        guard !query.isEmpty else {
            cachedFilteredFiles = files
            return
        }
        let visibleColumns = Set(columnConfiguration.orderedVisibleColumns())
        let lowercasedSearch = query.lowercased()
        let result = files.filter { file in
            let searchableFields = searchableValues(
                for: file,
                visibleColumns: visibleColumns,
                includePinyin: true
            )
            return searchableFields.contains { $0.contains(lowercasedSearch) }
        }
        cachedFilteredFiles = result
    }

    /// 构建用于过滤的字段集合，可选附加拼音索引
    private func searchableValues(
        for file: AudioMetadata,
        visibleColumns: Set<MetadataColumn>,
        includePinyin: Bool
    ) -> [String] {
        var values: [String] = []

        func append(_ raw: String?, allowPinyin: Bool = true) {
            guard let raw else { return }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            let normalized = trimmed.lowercased()
            values.append(normalized)

            guard includePinyin, allowPinyin else { return }
            let tokens = PinyinTransliterator.shared.tokens(for: trimmed)
            values.append(contentsOf: tokens)
        }

        if visibleColumns.contains(.fileName) {
            append(file.fileName)
        }
        if visibleColumns.contains(.title) {
            append(file.originalTitle)
            append(file.correctedTitle)
        }
        if visibleColumns.contains(.artist) {
            append(file.originalArtist)
            append(file.correctedArtist)
        }
        if visibleColumns.contains(.album) {
            append(file.originalAlbum)
            append(file.correctedAlbum)
        }
        if visibleColumns.contains(.genre) {
            append(file.originalGenre)
            append(file.correctedGenre)
        }
        if visibleColumns.contains(.year) {
            append(file.originalYear)
            append(file.correctedYear)
        }
        if visibleColumns.contains(.duration) {
            append(file.durationDisplay, allowPinyin: false)
        }
        if visibleColumns.contains(.fileSize) {
            append(file.fileSizeDisplay, allowPinyin: false)
        }
        if visibleColumns.contains(.bitrate) {
            append(file.bitrateDisplay, allowPinyin: false)
        }
        if visibleColumns.contains(.sampleRate) {
            append(file.sampleRateDisplay, allowPinyin: false)
        }
        if visibleColumns.contains(.format) {
            append(file.formatDisplay, allowPinyin: false)
        }
        if visibleColumns.contains(.creationDate) {
            append(file.creationDateDisplay, allowPinyin: false)
        }
        if visibleColumns.contains(.modificationDate) {
            append(file.modificationDateDisplay, allowPinyin: false)
        }
        if visibleColumns.contains(.status) {
            append(localizationManager.string(file.processingState.localizationKey), allowPinyin: false)
        }

        return values
    }

    let tableColumnDescriptors: [MetadataColumnDescriptor] = MetadataColumnRegistry.descriptors


    private var queuePanelTopPadding: CGFloat {
        playbackBarHeight > 0
            ? playbackBarHeight + DesignSystem.Spacing.md
            : DesignSystem.Spacing.lg
    }

    /// 顶栏区域：搜索过滤器 + 播放条，自适应宽度堆叠
    @ViewBuilder
    private var topBarArea: some View {
        let isTopBarCompact = topBarWidth < 600

        Group {
            if isTopBarCompact {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    SearchFilterView(text: $searchText)
                        .frame(maxWidth: .infinity)
                    
                    PlaybackBarView()
                        .frame(maxWidth: .infinity)
                }
                .padding(.trailing, DesignSystem.Spacing.md)
            } else {
                HStack(spacing: 12) {
                    SearchFilterView(text: $searchText)
                        .frame(minWidth: DesignSystem.Layout.searchFilterMinWidth, maxWidth: DesignSystem.Layout.searchFilterMaxWidth)
                    
                    PlaybackBarView()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.leading, DesignSystem.Spacing.md)
        .padding(.vertical, 8)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .preference(key: TopBarWidthPreferenceKey.self, value: proxy.size.width)
                    .preference(key: PlaybackBarHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(TopBarWidthPreferenceKey.self) { newWidth in
            topBarWidth = newWidth
        }
        .onPreferenceChange(PlaybackBarHeightPreferenceKey.self) { newHeight in
            playbackBarHeight = newHeight
        }
        .animation(DesignSystem.Animation.normal, value: isTopBarCompact)
        .alert(
            localizationManager.string("alert.backup_access_denied.title"),
            isPresented: $isShowingBackupAccessDeniedAlert
        ) {
            Button(localizationManager.string("alert.backup_access_denied.go_to_settings")) {
                NotificationCenter.default.post(
                    name: NSNotification.Name("ShowSettings"),
                    object: nil
                )
            }
            Button(localizationManager.string("alert.backup_access_denied.cancel"), role: .cancel) {
                // Just dismiss
            }
        }
    }

    /// 进度条与文件列表主内容区域，从 body 中提取以减轻类型检查压力
    @ViewBuilder
    private var mainContentArea: some View {
        // 处理进度条
        if isApplyingCorrections {
            VStack(spacing: 8) {
                ProgressView(value: applyProgress, total: Double(1.0))
                    .progressViewStyle(.linear)
                Text(localizationManager.string("review.progress.writing_ai", arguments: Int(applyProgress * 100)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.green.opacity(0.05))
        }

        // 文件列表
        ZStack {
            // 底层：正常内容
            if currentFiles.isEmpty && !coordinator.isRestoringWorkspace {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(currentDirectory == nil 
                         ? localizationManager.string("review.empty.select_directory") 
                         : localizationManager.string("review.empty.no_audio_files"))
                        .foregroundColor(.secondary)
                    
                    if currentDirectory == nil {
                        Text(localizationManager.string("review.empty.tip"))
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.top, 8)
                            .padding(.horizontal, 32)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !currentFiles.isEmpty {
                tableContainer
            } else {
                // 恢复中且还没有文件时，用空白占位
                Color.clear
            }

            // 顶层：恢复遮罩
            if coordinator.isRestoringWorkspace {
                Color(nsColor: .windowBackgroundColor).opacity(0.85)
                    .overlay(
                        VStack(spacing: 20) {
                            ZStack {
                                Circle()
                                    .fill(Color.accentColor.opacity(0.08))
                                    .frame(width: 100, height: 100)
                                Image(systemName: "folder.badge.gearshape")
                                    .font(.system(size: 40, weight: .light))
                                    .foregroundStyle(.secondary)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            ProgressView()
                                .controlSize(.large)

                            VStack(spacing: 8) {
                                Text(localizationManager.string("review.restore.workspace"))
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)

                                Button {
                                    coordinator.cancelRestore()
                                } label: {
                                    Text(localizationManager.string("review.restore.skip"))
                                        .padding(.horizontal, DesignSystem.Spacing.md)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.top, DesignSystem.Spacing.sm)
                        }
                    )
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: coordinator.isRestoringWorkspace)
        .alert(localizationManager.string("review.trash.confirm_title"), isPresented: $isShowingTrashConfirmation) {
            Button(localizationManager.string("common.cancel"), role: .cancel) {
                pendingTrashItems.removeAll()
            }
            Button(localizationManager.string("common.move_to_trash"), role: .destructive) {
                let itemsToDelete = pendingTrashItems
                pendingTrashItems.removeAll()
                executeTrash(for: itemsToDelete)
            }
        } message: {
            let count = pendingTrashItems.count
            if count <= 1, let item = pendingTrashItems.first {
                Text(localizationManager.string("review.trash.confirm_single", arguments: item.fileName as NSString))
            } else {
                Text(localizationManager.string("review.trash.confirm_multiple", arguments: count))
            }
        }
    }

    var body: some View {
        bodyWithDataSync
            .onAppear {
                if !hasLoadedDefaultFieldSelection {
                    loadDefaultFieldSelection()
                }
                columnConfiguration = coordinator.settings.tableColumnConfiguration
                if let pref = coordinator.settings.tableSortPreference {
                    if let comparator = sortComparator(for: pref.column, ascending: pref.ascending) {
                        sortOrder = [comparator]
                    }
                }
                if let selectedDir = coordinator.selectedDirectory {
                    currentDirectory = selectedDir
                    currentFiles = coordinator.audioFiles
                    applySortOrder(sortOrder)
                }
                synchronizeFieldSelectionsWithFiles()
                syncSelectionWithCurrentTrack()
                cachedFilteredFiles = currentFiles
            }
            .task(id: searchText) {
                do {
                    try await Task.sleep(nanoseconds: 200_000_000)
                    if !Task.isCancelled {
                        debouncedSearchText = searchText
                        updateFilteredFiles()
                    }
                } catch {
                    // Canceled
                }
            }
            .onChange(of: currentFiles) { _ in
                updateFilteredFiles()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DirectoryChanged"))) { notification in
                if let url = notification.object as? URL {
                    currentDirectory = url
                }
            }
    }

    /// 第二层：挂载数据同步和播放控制相关的事件监听
    private var bodyWithDataSync: some View {
        bodyCore
            .onReceive(coordinator.$audioFiles) { newFiles in
                let currentIDs = Set(currentFiles.map(\.id))
                let newOnly = newFiles.filter { !currentIDs.contains($0.id) }
                let removedIDs = currentIDs.subtracting(newFiles.map(\.id))
                
                var hasChanges = false
                
                if !newOnly.isEmpty || !removedIDs.isEmpty {
                    if !removedIDs.isEmpty {
                        currentFiles.removeAll { removedIDs.contains($0.id) }
                    }
                    if !newOnly.isEmpty {
                        var sortedNew = newOnly
                        sortedNew.sort(using: sortOrder)
                        currentFiles.append(contentsOf: sortedNew)
                    }
                    coordinator.audioFiles = currentFiles
                    if playbackController.state.isActive
                        && playbackController.state.order == .sequential {
                        playbackController.reorderQueue(currentFiles)
                    }
                    hasChanges = true
                } else {
                    // 同步属性的改变（如：处理状态、修正建议等属性变动）
                    for newFile in newFiles {
                        if let index = currentFiles.firstIndex(where: { $0.id == newFile.id }) {
                            if currentFiles[index] != newFile {
                                currentFiles[index] = newFile
                                hasChanges = true
                            }
                        }
                    }
                }
                
                // 如果检测到属性改变且 count 没变，此时不会被 count 的 onChange 捕获，
                // 我们在 onChange(of: currentFiles) 内部会捕获，但显式调用以防万一
                if hasChanges {
                    updateFilteredFiles()
                }
            }
            .onChange(of: playbackController.state.currentTrackID) { _ in
                scrollToCurrentTrack()
            }
            .onChange(of: playbackController.revealRequestToken) { _ in
                guard playbackController.state.isActive else { return }
                syncSelectionWithCurrentTrack()
            }
            .onChange(of: tableSelection) { _ in
                playbackController.dismissQueuePanelIfNeeded()
            }
            .onChange(of: includeSubdirectories) { _ in
                if let dir = currentDirectory {
                    loadFiles(from: dir)
                }
            }
            .onChange(of: sortOrder) { newOrder in
                applySortOrder(newOrder)
                persistSortPreference(newOrder)
            }
            .onReceive(coordinator.$settings.map(\.tableColumnConfiguration).removeDuplicates()) { newConfig in
                guard newConfig != columnConfiguration else { return }
                columnConfiguration = newConfig
            }
            .onChange(of: columnConfiguration) { newConfig in
                coordinator.settings.tableColumnConfiguration = newConfig
                coordinator.settings.save()
                // 搜索过滤依赖可见列集合，列显隐变化后需重算缓存
                updateFilteredFiles()
            }
            .onReceive(coordinator.aiMetadataService.$progress.removeDuplicates()) { newValue in
                processingProgress = newValue
            }
    }

    /// 核心视图结构（ZStack + toolbar），与事件修饰符分离以降低类型推导复杂度
    private var bodyCore: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                topBarArea
                mainContentArea
            }
            .contentShape(Rectangle())
            .simultaneousGesture(
                TapGesture().onEnded {
                    playbackController.dismissQueuePanelIfNeeded()
                }
            )

            if playbackController.isQueuePanelVisible && playbackController.state.isActive {
                PlaybackQueuePanel()
                    .padding(.trailing, DesignSystem.Spacing.lg)
                    .padding(.top, queuePanelTopPadding)
            }

            // Esc 清空曲目选择改由 MetadataReviewTableView.cancelOperation 处理：
            // SwiftUI 的 .keyboardShortcut(.cancelAction) 是 key equivalent，
            // 会在单元格编辑/搜索框聚焦时抢走 Esc，导致编辑无法取消
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                toolbarPrincipalContent
            }
            ToolbarItemGroup(placement: .automatic) {
                toolbarControls
            }
        }
        .alert(item: $pendingBulkAction) { pending in
            Alert(
                title: Text(localizationManager.string(pending.titleKey)),
                message: Text(localizationManager.string(pending.messageKey, arguments: pending.count)),
                primaryButton: .default(Text(localizationManager.string("common.continue"))) {
                    performBulkAction(pending)
                },
                secondaryButton: .cancel(Text(localizationManager.string("common.cancel")))
            )
        }
        .conflictResolutionWindow(
            isPresented: $isShowingConflictResolution,
            conflicts: $pendingConflicts,
            allFiles: $currentFiles,
            localizationManager: localizationManager,
            onWriteAndKeep: { metadata in
                writeConflictFile(metadata)
            },
            onDelete: { metadata in
                deleteConflictFile(metadata)
            },
            onClose: {
                isShowingConflictResolution = false
                pendingConflicts = []
            }
        )
    }
}


private struct PlaybackBarHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TopBarWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

extension MetadataReviewView {
    struct PendingBulkAction: Identifiable {
        enum Action {
            case aiProcess
            case confirmWrite
        }

        let id = UUID()
        let action: Action
        let count: Int
        let selection: Set<AudioMetadata.ID>

        var titleKey: String {
            switch action {
            case .aiProcess:
                return "review.bulk.ai_process.title"
            case .confirmWrite:
                return "review.bulk.confirm_write.title"
            }
        }

        var messageKey: String {
            switch action {
            case .aiProcess:
                return "review.bulk.ai_process.message"
            case .confirmWrite:
                return "review.bulk.confirm_write.message"
            }
        }
    }

    func performBulkAction(_ pending: PendingBulkAction) {
        switch pending.action {
        case .aiProcess:
            processWithAI()
        case .confirmWrite:
            applyCorrections(selection: pending.selection)
        }
    }
}


#Preview {
    let coordinator = AppCoordinator()
    coordinator.selectedDirectory = URL(fileURLWithPath: "/Users")
    coordinator.audioFiles = [
        AudioMetadata(
            filePath: URL(fileURLWithPath: "/path/song1.mp3"),
            fileName: "song1.mp3",
            fileSizeBytes: 5_120_000,
            originalTitle: "未知歌曲",
            originalArtist: "未知艺术家"
        )
    ]
    return MetadataReviewView()
        .environmentObject(coordinator)
        .environmentObject(coordinator.playbackController)
        .environmentObject(coordinator.playbackController.timelineStore)
        .environmentObject(coordinator.playbackController.spectrumDataStore)
}

// MARK: - Custom Floating Window for Conflict Resolution

struct ConflictResolutionWindowModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var conflicts: [ConflictGroup]
    @Binding var allFiles: [AudioMetadata]
    let localizationManager: LocalizationManager
    let onWriteAndKeep: (AudioMetadata) -> Void
    let onDelete: (AudioMetadata) -> Void
    let onClose: () -> Void

    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var windowController: NSWindowController?
    @State private var closeObserverToken: NSObjectProtocol?

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { show in
                if show {
                    presentWindow()
                } else {
                    dismissWindow()
                }
            }
    }

    private func presentWindow() {
        guard windowController == nil else { return }
        
        let sheetView = ConflictResolutionSheet(
            conflicts: $conflicts,
            allFiles: $allFiles,
            onWriteAndKeep: onWriteAndKeep,
            onDelete: onDelete,
            onClose: {
                isPresented = false
                onClose()
            }
        )
        .environmentObject(localizationManager)
        .environmentObject(coordinator)

        let hostingController = NSHostingController(rootView: sheetView)
        
        let newWindow = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newWindow.titleVisibility = .hidden
        newWindow.titlebarAppearsTransparent = true
        newWindow.isMovableByWindowBackground = true
        newWindow.backgroundColor = NSColor.windowBackgroundColor
        newWindow.contentViewController = hostingController
        newWindow.minSize = NSSize(width: 800, height: 450)
        newWindow.maxSize = NSSize(width: 1400, height: 900)
        newWindow.isReleasedWhenClosed = false
        newWindow.isFloatingPanel = false
        
        // 隐藏原生的红绿灯按钮，使其看起来像一个纯粹的弹窗(Sheet)
        newWindow.standardWindowButton(.closeButton)?.isHidden = true
        newWindow.standardWindowButton(.miniaturizeButton)?.isHidden = true
        newWindow.standardWindowButton(.zoomButton)?.isHidden = true
        
        let desiredSize = NSSize(width: 900, height: 600)
        newWindow.setContentSize(desiredSize)
        
        // 设置初始位置为居中（如果存在主窗口，则相对于主窗口居中）
        if let mainWindow = NSApp.windows.first(where: { $0.isMainWindow || $0.identifier?.rawValue == "MainWindow" }) {
            let centerX = mainWindow.frame.midX - (desiredSize.width / 2)
            let centerY = mainWindow.frame.midY - (desiredSize.height / 2)
            newWindow.setFrameOrigin(NSPoint(x: centerX, y: centerY))
        } else {
            newWindow.center()
        }
        
        // 设置 level 保证处于主窗口上层，类似于 modal 提示
        newWindow.level = .floating
        
        let controller = NSWindowController(window: newWindow)
        controller.showWindow(nil)
        
        self.windowController = controller

        // 监听窗口关闭通知；token 必须在触发后移除，
        // 否则反复开关冲突窗口会在 NotificationCenter 里累积观察者
        closeObserverToken = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: newWindow,
            queue: .main
        ) { _ in
            if isPresented {
                isPresented = false
                onClose()
            }
            self.windowController = nil
            removeCloseObserver()
        }
    }

    private func removeCloseObserver() {
        if let token = closeObserverToken {
            NotificationCenter.default.removeObserver(token)
            closeObserverToken = nil
        }
    }

    private func dismissWindow() {
        // close() 会同步触发 willClose 观察者，由其完成 token 清理
        windowController?.window?.close()
        windowController = nil
    }
}

extension View {
    func conflictResolutionWindow(
        isPresented: Binding<Bool>,
        conflicts: Binding<[ConflictGroup]>,
        allFiles: Binding<[AudioMetadata]>,
        localizationManager: LocalizationManager,
        onWriteAndKeep: @escaping (AudioMetadata) -> Void,
        onDelete: @escaping (AudioMetadata) -> Void,
        onClose: @escaping () -> Void
    ) -> some View {
        self.modifier(
            ConflictResolutionWindowModifier(
                isPresented: isPresented,
                conflicts: conflicts,
                allFiles: allFiles,
                localizationManager: localizationManager,
                onWriteAndKeep: onWriteAndKeep,
                onDelete: onDelete,
                onClose: onClose
            )
        )
    }
}
