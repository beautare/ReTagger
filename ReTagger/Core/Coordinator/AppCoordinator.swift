//
//  AppCoordinator.swift
//  ReTagger
//
//  Created by Claude Code
//

import Foundation
import SwiftUI
import Combine
import OSLog

struct DirectoryScanRequest: Identifiable, Equatable {
    let id: UUID
    let urls: [URL]
    let includeSubdirectories: Bool
    let isIncremental: Bool
}

struct MetadataUndoRecord: Identifiable {
    let id: UUID = UUID()
    let metadataID: AudioMetadata.ID
    let originalState: AudioMetadata
    let appliedState: AudioMetadata
    let confirmedAt: Date
    let backupURL: URL?
}

@MainActor
class AppCoordinator: ObservableObject {
    // MARK: - Published Properties

    @Published var currentStep: AppStep = .directorySelection
    @Published var selectedDirectory: URL? // 当前选中的/最后操作的目录
    @Published var workspaceDirectories: [URL] = [] // 所有已添加的工作区目录
    @Published var audioFiles: [AudioMetadata] = []
    @Published var settings: AppSettings
    @Published var isLoading: Bool = false
    /// 启动时正在恢复上次工作区目录
    @Published private(set) var isRestoringWorkspace: Bool = false
    /// 恢复完成后短暂展示的成功徽章
    @Published private(set) var showRestoreBadge: Bool = false
    /// 追踪恢复扫描请求的 ID
    private var restoreScanRequestID: UUID?
    @Published var errorMessage: String?
    @Published private(set) var recentDirectories: [RecentDirectoryEntry] = []
    @Published var includeSubdirectories: Bool = true {
        didSet {
            if settings.includeSubdirectories != includeSubdirectories {
                var newSettings = settings
                newSettings.includeSubdirectories = includeSubdirectories
                updateSettings(newSettings)
            }
        }
    }
    @Published private(set) var scanRequest: DirectoryScanRequest?
    @Published private(set) var undoRecords: [AudioMetadata.ID: MetadataUndoRecord] = [:]
    @Published private(set) var activityLogs: [ActivityLogEntry] = []

    // MARK: - Security Scope

    private(set) var activeSecurityScopedResources: [String: URL] = [:]
    
    private(set) var activeBackupDirectory: URL?
    let localizationManager: LocalizationManager
    
    // ... (Services) ...

    // MARK: - Backup Directory Management
    
    func setBackupDirectory(_ url: URL) {
        // 1. Activate security scope immediately
        if url.startAccessingSecurityScopedResource() {
            activeBackupDirectory = url
        }
        
        // 2. Save bookmark and path
        saveBackupDirectoryBookmark(for: url)
        
        var newSettings = settings
        newSettings.backupLocation = url.path
        updateSettings(newSettings)
    }
    
    func resetBackupDirectoryToDefault() {
        if let active = activeBackupDirectory {
            active.stopAccessingSecurityScopedResource()
            activeBackupDirectory = nil
        }
        var newSettings = settings
        newSettings.backupLocation = nil
        newSettings.backupLocationBookmark = nil
        updateSettings(newSettings)
    }
    
    func ensureBackupDirectoryAccess() async -> Bool {
        guard settings.createBackups else { return true }
        
        // Determine target backup path
        let targetPath: String
        if let customPath = settings.backupLocation {
            targetPath = customPath
        } else {
            // Default: ~/Desktop/ReTagger
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
            targetPath = desktop.appendingPathComponent("ReTagger").path
        }
        
        let targetURL = URL(fileURLWithPath: targetPath)
        
        // 1. Check if we already have active access
        if let active = activeBackupDirectory, active.path == targetURL.path {
            return true
        }
        
        // 2. Try to resolve existing bookmark
        if let bookmarkData = settings.backupLocationBookmark {
            var isStale = false
            if let resolved = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if resolved.path == targetURL.path {
                    if resolved.startAccessingSecurityScopedResource() {
                        activeBackupDirectory = resolved
                        if isStale {
                            saveBackupDirectoryBookmark(for: resolved)
                        }
                        return true
                    }
                }
            }
        }
        
        // 3. If no bookmark or failed to resolve, check if we can write (e.g. inside sandbox or already accessible)
        if FileManager.default.isWritableFile(atPath: targetURL.path) {
            // Even if writable, we might want to secure a bookmark for future if it's outside sandbox
            // But for now, just return true
            return true
        }
        
        // 4. Request access
        let message = localizationManager.string(
            "filesystem.backup_root_permission_prompt",
            arguments: targetURL.lastPathComponent
        )
        if let grantedURL = await fileSystemService.requestAccess(to: targetURL, message: message) {
            if grantedURL.startAccessingSecurityScopedResource() {
                activeBackupDirectory = grantedURL
                saveBackupDirectoryBookmark(for: grantedURL)
                
                // Update settings if it was a custom location, or if we want to save the default one too
                if settings.backupLocation != nil {
                     var newSettings = settings
                     newSettings.backupLocation = grantedURL.path
                     updateSettings(newSettings)
                }
                return true
            }
        }
        
        return false
    }
    
    private func saveBackupDirectoryBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            var newSettings = settings
            newSettings.backupLocationBookmark = bookmarkData
            updateSettings(newSettings)
        } catch {
            Logger.fileSystem.error("Failed to create bookmark for backup directory: \(error.localizedDescription)")
        }
    }

    // MARK: - Localization

    func setLanguage(_ language: AppLanguage) {
        guard language != settings.preferredLanguage else {
            localizationManager.updateLanguage(language)
            return
        }

        localizationManager.updateLanguage(language)
        var newSettings = settings
        newSettings.preferredLanguage = language
        updateSettings(newSettings)
    }

    // MARK: - Services

    let fileSystemService: FileSystemService
    let metadataService: MetadataService
    let deviceTokenManager: DeviceTokenManager
    let authService: AuthService
    let networkService: NetworkService
    let aiProviderService: AIProviderService
    let aiMetadataService: AIMetadataService
    let metadataCacheService: MetadataCacheService
    let playbackService: AudioPlaybackServicing
    let playbackController: PlaybackController
    let storeService: StoreKitService

    // MARK: - Initialization

    init(settings loadedSettings: AppSettings? = nil,
         localizationManager: LocalizationManager? = nil) {
        let loadedSettings = loadedSettings ?? AppSettings.load()
        self.settings = loadedSettings
        self.recentDirectories = loadedSettings.recentDirectories
        self.includeSubdirectories = loadedSettings.includeSubdirectories
        let resolvedLocalizationManager = localizationManager ?? LocalizationManager(language: loadedSettings.preferredLanguage)
        resolvedLocalizationManager.updateLanguage(loadedSettings.preferredLanguage)
        self.localizationManager = resolvedLocalizationManager

        // Initialize services with loaded settings
        self.fileSystemService = FileSystemService(localizationManager: resolvedLocalizationManager)
        self.metadataService = MetadataService()
        
        let tokenManager = DeviceTokenManager(baseURL: loadedSettings.backendURL)
        self.deviceTokenManager = tokenManager
        
        // Initialize AuthService
        let authService = AuthService(deviceTokenManager: tokenManager)
        self.authService = authService
        
        // Initialize NetworkService with AuthService as provider
        self.networkService = NetworkService(
            baseURL: loadedSettings.backendURL,
            tokenProvider: authService
        )
        
        // Break circular dependency
        authService.networkService = self.networkService
        
        self.aiProviderService = AIProviderService(
            provider: loadedSettings.selectedAIProvider,
            apiKey: loadedSettings.apiKey,
            networkService: networkService
        )
        self.aiMetadataService = AIMetadataService(
            networkService: networkService,
            metadataService: metadataService
        )
        self.metadataCacheService = MetadataCacheService(
            fileSystemService: fileSystemService,
            metadataService: metadataService
        )
        self.playbackService = AudioPlaybackService(order: loadedSettings.preferredPlaybackOrder)
        self.playbackController = PlaybackController(
            service: playbackService,
            defaultOrder: loadedSettings.preferredPlaybackOrder
        )
        
        // Initialize StoreKitService (必须在使用 self 的闭包之前)
        self.storeService = StoreKitService(
            authService: authService,
            networkService: self.networkService
        )
        
        self.playbackController.onOrderChange = { [weak self] newOrder in
            guard let self else { return }
            var updatedSettings = self.settings
            updatedSettings.preferredPlaybackOrder = newOrder
            self.updateSettings(updatedSettings)
        }

        self.playbackController.onTrackChange = { [weak self] track in
            guard let self else { return }
            var updatedSettings = self.settings
            updatedSettings.lastPlayingTrackPath = track?.filePath.path
            self.updateSettings(updatedSettings)
            if track == nil {
                UserDefaults.standard.removeObject(forKey: "lastPlayingTrackTime")
            }
        }
        
        self.metadataCacheService.onDirectoryChanged = { [weak self] url in
            self?.handleExternalDirectoryChange(url)
        }
        
        // 启动时，无论是否登录，都主动拉取一次最新配额或用户信息
        Task {
            try? await authService.fetchProfile()
        }

        if loadedSettings.restoreDirectoryOnLaunch {
            Task { @MainActor in
                await self.restoreWorkspaceDirectories(from: loadedSettings)
            }
        }
    }
    
    // MARK: - 工作区恢复与保存
    
    /// 启动时恢复上次关闭前的完整工作区目录
    private func restoreWorkspaceDirectories(from loadedSettings: AppSettings) async {
        // 优先使用 lastWorkspaceDirectories（多目录完整快照）
        let entriesToRestore = loadedSettings.lastWorkspaceDirectories
        if entriesToRestore.isEmpty {
            return
        }
        
        isRestoringWorkspace = true
        
        // 使用 TaskGroup 并行解析所有目录的书签并进行存在性验证，从而在多核上并行处理，避免主线程逐个等待导致的卡顿与Beachball
        let results = await withTaskGroup(of: (RecentDirectoryEntry, URL?, Bool).self) { group in
            for entry in entriesToRestore {
                group.addTask { [weak self] in
                    guard let self = self,
                          let resolvedURL = self.resolveRecentDirectoryURL(entry) else {
                        return (entry, nil, false)
                    }
                    
                    let exists = FileManager.default.fileExists(atPath: resolvedURL.path)
                    return (entry, resolvedURL, exists)
                }
            }
            
            var collected: [(RecentDirectoryEntry, URL, Bool)] = []
            for await result in group {
                if let url = result.1 {
                    collected.append((result.0, url, result.2))
                }
            }
            return collected
        }
        
        // 维持原本在 entriesToRestore 中的相对顺序，并在本地局部变量里收集，避免循环中途不断触发 SwiftUI 刷新
        var tempWorkspaceDirectories = self.workspaceDirectories
        var resolvedURLs: [URL] = []
        var skippedAny = false
        
        for entry in entriesToRestore {
            guard let match = results.first(where: { $0.0.path == entry.path }) else { continue }
            let resolvedURL = match.1
            let exists = match.2
            
            let standardized = resolvedURL.standardizedFileURL
            if tempWorkspaceDirectories.contains(where: { $0.standardizedFileURL.path == standardized.path }) {
                continue
            }
            
            guard activateSecurityScope(for: resolvedURL) else { continue }
            
            if !exists {
                Logger.fileSystem.warning("恢复工作区目录时，物理路径不存在：\(resolvedURL.path, privacy: .public)")
                resolvedURL.stopAccessingSecurityScopedResource()
                let normalizedPath = resolvedURL.standardizedFileURL.path
                self.activeSecurityScopedResources.removeValue(forKey: normalizedPath)
                self.removeRecentDirectory(entry)
                skippedAny = true
                continue
            }
            
            // 如果恢复 of 项是一个单文件，且其父目录已在 recentDirectories 中有授权记录，则自动恢复并激活其父目录权限
            if !resolvedURL.isDirectory {
                let parentDir = resolvedURL.deletingLastPathComponent()
                _ = activateSecurityScope(for: parentDir)
            }
            
            if !tempWorkspaceDirectories.contains(where: { $0.path == resolvedURL.path }) {
                tempWorkspaceDirectories.append(resolvedURL)
            }
            resolvedURLs.append(resolvedURL)
        }
        
        // 一次性更新状态，避免多次触发 SwiftUI 渲染刷新与列表滚动
        self.workspaceDirectories = tempWorkspaceDirectories
        
        if skippedAny {
            saveWorkspaceState()
        }
        
        // 阶段 2：一次性触发包含所有 URL 的批量扫描请求
        if !resolvedURLs.isEmpty {
            // 既然是恢复上次的工作区，直接跳到主审查页面以展示全屏加载动画
            currentStep = .metadataReview
            
            let request = DirectoryScanRequest(
                id: UUID(),
                urls: resolvedURLs,
                includeSubdirectories: includeSubdirectories,
                isIncremental: false
            )
            restoreScanRequestID = request.id
            scanRequest = request
            // isRestoringWorkspace 将在 clearScanRequest 中检测到扫描完成后关闭
            
            // 超时保护：若 30 秒内扫描仍未完成（UI 竞态导致 performScan 从未被触发），
            // 自动解除 isRestoringWorkspace，避免 UI 永远卡在恢复加载界面。
            let capturedRequestID = request.id
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                // 若 restoreScanRequestID 仍然是当前请求，说明扫描从未完成
                if self.restoreScanRequestID == capturedRequestID {
                    Logger.fileSystem.warning("恢复工作区扫描超时（30s），强制解除恢复状态")
                    self.restoreScanRequestID = nil
                    self.scanRequest = nil
                    self.isRestoringWorkspace = false
                }
            }
        } else {
            isRestoringWorkspace = false
        }
    }
    
    /// 将当前工作区目录快照保存到 settings，用于下次启动恢复
    func saveWorkspaceState() {
        var updatedSettings = settings
        updatedSettings.lastWorkspaceDirectories = workspaceDirectories.map { url in
            RecentDirectoryEntry(
                path: url.path,
                bookmarkData: try? url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ),
                lastOpened: Date()
            )
        }
        updateSettings(updatedSettings)
    }
    
    private func handleExternalDirectoryChange(_ url: URL) {
        // Debounce external reloads a bit if there are bursts of changes
        Task { @MainActor in
            do {
                // Check if the changed URL affects our workspace
                let isIncluded = self.workspaceDirectories.contains { $0.isSameOrDescendant(of: url) || url.isSameOrDescendant(of: $0) }
                guard isIncluded else { return }

                // Fetch new state for the affected directories
                var newAudioFiles: [AudioMetadata] = []
                var removedDirs: [URL] = []
                
                for dir in self.workspaceDirectories {
                    let hasAccess = dir.startAccessingSecurityScopedResource()
                    let exists = FileManager.default.fileExists(atPath: dir.path)
                    if hasAccess {
                        dir.stopAccessingSecurityScopedResource()
                    }
                    
                    if !exists {
                        removedDirs.append(dir)
                        continue
                    }
                    
                    let files = try await self.metadataCacheService.metadata(
                        for: dir,
                        includeSubdirectories: self.includeSubdirectories
                    )
                    newAudioFiles.append(contentsOf: files)
                }
                
                // 处理外部删除的目录
                if !removedDirs.isEmpty {
                    for dir in removedDirs {
                        Logger.fileSystem.warning("外部删除了工作区目录：\(dir.path, privacy: .public)")
                        self.workspaceDirectories.removeAll(where: { $0.path == dir.path })
                        
                        // 释放安全域资源
                        let normalizedPath = dir.standardizedFileURL.path
                        if let activeURL = self.activeSecurityScopedResources.removeValue(forKey: normalizedPath) {
                            activeURL.stopAccessingSecurityScopedResource()
                        }
                    }
                    
                    // 保存更新后的工作区快照
                    self.saveWorkspaceState()
                    
                    let dirNames = removedDirs.map { $0.lastPathComponent }.joined(separator: ", ")
                    self.setError(self.localizationManager.string("error.directory_moved_or_deleted", arguments: dirNames))
                    
                    if self.workspaceDirectories.isEmpty {
                        self.currentStep = .directorySelection
                    }
                }

                // Merge into self.audioFiles while preserving AI edits
                let oldFilesDict = Dictionary(self.audioFiles.map { ($0.fileName, $0) }, uniquingKeysWith: { first, _ in first }) // Use fileName as fallback matching
                let oldFilesByID = Dictionary(self.audioFiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                
                var finalFiles: [AudioMetadata] = []
                for newFile in newAudioFiles {
                    // Try exact match by ID first, then by filename if ID changed (e.g. renamed externally)
                    let matchedOldFile = oldFilesByID[newFile.id] ?? oldFilesDict[newFile.fileName]
                    
                    if let oldFile = matchedOldFile {
                        // Preserve AI modifications but take the fresh file's real tags/path
                        var merged = newFile
                        merged.processingState = oldFile.processingState
                        merged.correctedTitle = oldFile.correctedTitle
                        merged.correctedArtist = oldFile.correctedArtist
                        merged.correctedAlbum = oldFile.correctedAlbum
                        merged.correctedGenre = oldFile.correctedGenre
                        merged.correctedYear = oldFile.correctedYear
                        merged.suggestedFileName = oldFile.suggestedFileName
                        merged.suggestedFolderPath = oldFile.suggestedFolderPath
                        merged.aiNotes = oldFile.aiNotes
                        merged.confidence = oldFile.confidence
                        merged.error = oldFile.error
                        
                        // We also keep the old file's ID if we want, but using new ID is safer because it matches the new filePath
                        finalFiles.append(merged)
                    } else {
                        finalFiles.append(newFile)
                    }
                }

                // 找出被外部删除的文件路径集合
                let oldPaths = Set(self.audioFiles.map { $0.filePath.standardizedFileURL.path })
                let newPaths = Set(finalFiles.map { $0.filePath.standardizedFileURL.path })
                let removedPaths = oldPaths.subtracting(newPaths)
                
                if !removedPaths.isEmpty {
                    Logger.playback.info("有音频文件被外部删除，从播放队列中移除对应曲目数量：\(removedPaths.count)")
                    self.playbackController.remove(where: { removedPaths.contains($0.filePath.standardizedFileURL.path) })
                }

                // Actually we just set audioFiles
                self.audioFiles = finalFiles
            } catch {
                Logger.fileSystem.error("Failed to merge external directory changes: \(error)")
            }
        }
    }

    enum AppStep: Int, CaseIterable, Hashable {
        case directorySelection = 0
        case metadataReview = 1

        var title: String {
            switch self {
            case .directorySelection:
                return "选择目录"
            case .metadataReview:
                return "元数据审查"
            }
        }

        var icon: String {
            switch self {
            case .directorySelection:
                return "folder"
            case .metadataReview:
                return "magnifyingglass"
            }
        }
    }

    func nextStep() {
        guard currentStep == .directorySelection else { return }
        currentStep = .metadataReview
    }

    func previousStep() {
        guard currentStep == .metadataReview else { return }
        currentStep = .directorySelection
    }

    func canGoNext() -> Bool {
        switch currentStep {
        case .directorySelection:
            return selectedDirectory != nil && !audioFiles.isEmpty
        case .metadataReview:
            return false
        }
    }

    func canGoPrevious() -> Bool {
        return currentStep == .metadataReview
    }

    // MARK: - State Management

    func reset() {
        currentStep = .directorySelection
        selectedDirectory = nil
        workspaceDirectories = []
        audioFiles = []
        isLoading = false
        errorMessage = nil
        scanRequest = nil
        restoreScanRequestID = nil
        isRestoringWorkspace = false
        metadataCacheService.clearAll()
        playbackController.clearQueue()
        releaseSecurityScope()
        undoRecords.removeAll()
    }

    func cancelRestore() {
        reset()
    }

    func registerOpenedDirectory(_ url: URL) {
        let normalizedURL = url.standardizedFileURL
        // 如果是新添加的工作区目录，确保也保存到历史记录
        if !workspaceDirectories.contains(where: { $0.path == normalizedURL.path }) {
            // Note: 这里只是注册历史，真正添加到 workspaceDirectories 在 handleDirectorySelection 或 addWorkspaceDirectory
        }
        
        let existingBookmark = recentDirectories.first { $0.path == normalizedURL.path }?.bookmarkData
        let bookmarkSourceURL = url
        let bookmark: Data?
        if let data = try? bookmarkSourceURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            bookmark = data
        } else if bookmarkSourceURL != normalizedURL,
                  let data = try? normalizedURL.bookmarkData(
                      options: [.withSecurityScope],
                      includingResourceValuesForKeys: nil,
                      relativeTo: nil
                  ) {
            bookmark = data
        } else {
            bookmark = existingBookmark
        }
        let newEntry = RecentDirectoryEntry(
            path: normalizedURL.path,
            bookmarkData: bookmark,
            lastOpened: Date()
        )

        var updatedList = recentDirectories.filter { $0.path != newEntry.path }
        updatedList.insert(newEntry, at: 0)
        if updatedList.count > 50 {
            updatedList = Array(updatedList.prefix(50))
        }

        var updatedSettings = settings
        updatedSettings.recentDirectories = updatedList
        updatedSettings.save()
        settings = updatedSettings
        recentDirectories = updatedList
    }

    nonisolated func resolveRecentDirectoryURL(_ entry: RecentDirectoryEntry) -> URL? {
        if let data = entry.bookmarkData {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if isStale {
                    Task { @MainActor in
                        self.registerOpenedDirectory(resolvedURL)
                    }
                }
                return resolvedURL
            }
        }
        return URL(fileURLWithPath: entry.path)
    }

    func removeRecentDirectory(_ entry: RecentDirectoryEntry) {
        let updatedList = recentDirectories.filter { $0.path != entry.path }
        guard updatedList.count != recentDirectories.count else { return }

        var updatedSettings = settings
        updatedSettings.recentDirectories = updatedList
        updatedSettings.save()
        settings = updatedSettings
        recentDirectories = updatedList
    }

    func clearRecentDirectories() {
        recentDirectories = []
        var updatedSettings = settings
        updatedSettings.recentDirectories = []
        updatedSettings.save()
        settings = updatedSettings
    }

    func triggerScan(for urls: [URL], includeSubdirectories overrideInclude: Bool? = nil, isAppend: Bool = false) {
        if !isAppend {
            selectedDirectory = urls.first
            workspaceDirectories = urls
        } else {
            for url in urls {
                if !workspaceDirectories.contains(where: { $0.path == url.path }) {
                    workspaceDirectories.append(url)
                }
            }
        }

        let request = DirectoryScanRequest(
            id: UUID(),
            urls: urls,
            includeSubdirectories: overrideInclude ?? includeSubdirectories,
            isIncremental: isAppend
        )
        scanRequest = request
        saveWorkspaceState()
    }
    
    func addWorkspaceDirectories(_ urls: [URL]) {
        var validURLs: [URL] = []
        for url in urls {
            // 1. 检查是否存在
            let standardized = url.standardizedFileURL
            if workspaceDirectories.contains(where: { $0.standardizedFileURL.path == standardized.path }) {
                continue
            }
            
            // 3. 激活权限
            guard activateSecurityScope(for: url) else {
                setError(localizationManager.string("error.directory_denied_path", arguments: url.path))
                continue
            }
            // 如果添加的项是一个单文件，且其父目录已在 recentDirectories 中有授权记录，则自动恢复并激活其父目录权限
            if !url.isDirectory {
                let parentDir = url.deletingLastPathComponent()
                _ = activateSecurityScope(for: parentDir)
            }
            validURLs.append(url)
        }
        
        guard !validURLs.isEmpty else { return }
        
        // 4. 触发增量扫描
        triggerScan(for: validURLs, isAppend: true)
        
        // 5. 保存工作区快照，确保下次启动可恢复
        saveWorkspaceState()
    }
    
    func removeWorkspaceDirectory(_ url: URL) {
        workspaceDirectories.removeAll(where: { $0.path == url.path })
        
        let removedPath = url.standardizedFileURL.path
        let prefix = removedPath.hasSuffix("/") ? removedPath : removedPath + "/"
        
        let shouldRemove: (URL) -> Bool = { fileURL in
            let path = fileURL.standardizedFileURL.path
            return path == removedPath || path.hasPrefix(prefix)
        }
        
        // 1. Remove from audioFiles
        audioFiles.removeAll(where: { shouldRemove($0.filePath) })
        
        // 2. Remove from PlaybackController queue
        playbackController.remove(where: { shouldRemove($0.filePath) })
        
        if workspaceDirectories.isEmpty {
            selectedDirectory = nil
            currentStep = .directorySelection
            playbackController.clearQueue()
        } else if selectedDirectory?.path == url.path {
            selectedDirectory = workspaceDirectories.first
        }
        
        releaseSecurityScope(for: url)
        
        // 保存工作区快照
        saveWorkspaceState()
    }

    func clearScanRequest(id: UUID) {
        guard scanRequest?.id == id else { return }
        scanRequest = nil
        
        // 检测恢复扫描完成
        if id == restoreScanRequestID {
            restoreScanRequestID = nil
            isRestoringWorkspace = false
            // 展示成功徽章，3 秒后自动消失
            showRestoreBadge = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                withAnimation(.easeOut(duration: 0.5)) {
                    showRestoreBadge = false
                }
            }
        }
    }

    func updateSettings(_ newSettings: AppSettings) {
        let previousSettings = settings
        settings = newSettings
        settings.save()

        // Reinitialize services with new settings
        aiProviderService.configure(
            provider: newSettings.selectedAIProvider,
            apiKey: newSettings.apiKey
        )

        if newSettings.backendURL != previousSettings.backendURL {
            networkService.updateBaseURL(newSettings.backendURL)
        }

        if newSettings.preferredPlaybackOrder != previousSettings.preferredPlaybackOrder {
            playbackController.setOrder(newSettings.preferredPlaybackOrder, notify: false)
        }

        if localizationManager.language != newSettings.preferredLanguage {
            localizationManager.updateLanguage(newSettings.preferredLanguage)
        }
    }

    func loadMetadata(
        for directory: URL,
        includeSubdirectories: Bool,
        updateState: Bool = true
    ) async throws -> [AudioMetadata] {
        let metadataList = try await metadataCacheService.metadata(
            for: directory,
            includeSubdirectories: includeSubdirectories
        )
        if updateState {
            audioFiles = metadataList
        }
        return metadataList
    }

    func invalidateCache(for directory: URL) {
        metadataCacheService.invalidate(directory: directory)
    }

    func setError(_ message: String) {
        errorMessage = message
        isLoading = false
        appendLog(.error, message)
    }

    func clearError() {
        errorMessage = nil
    }

    @discardableResult
    func activateSecurityScope(for url: URL) -> Bool {
        // Prefer bookmark-resolved URL to retain sandbox access even if caller passes plain path
        var resolvedURL = url
        var normalizedPath = resolvedURL.standardizedFileURL.path
        var needsBookmarkRefresh = false

        if let entry = recentDirectories.first(where: { $0.path == normalizedPath }),
           let data = entry.bookmarkData {
            var isStale = false
            if let bookmarkURL = try? URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                resolvedURL = bookmarkURL
                normalizedPath = bookmarkURL.standardizedFileURL.path
                needsBookmarkRefresh = isStale
            }
        }

        if let _ = activeSecurityScopedResources[normalizedPath] {
             print("✅ Security scope already active for: \(normalizedPath)")
             return true
        }
        
        // Check if covered by an ancestor
        for (activePath, _) in activeSecurityScopedResources {
            if normalizedPath.hasPrefix(activePath + "/") {
                print("✅ Using existing security scope from ancestor: \(activePath) for: \(normalizedPath)")
                return true
            }
        }

        let didStart = resolvedURL.startAccessingSecurityScopedResource()
        print("🔐 Attempting to activate security scope for: \(normalizedPath), result: \(didStart)")

        if didStart {
            activeSecurityScopedResources[normalizedPath] = resolvedURL
            
            registerOpenedDirectory(resolvedURL)

            if needsBookmarkRefresh {
                Logger.fileSystem.info("Refreshed stale security bookmark for: \(normalizedPath)")
            }
            return true
        }

        print("❌ Failed to activate security scope for: \(normalizedPath)")
        return false
    }

    func releaseSecurityScope() {
        for url in activeSecurityScopedResources.values {
            url.stopAccessingSecurityScopedResource()
        }
        activeSecurityScopedResources.removeAll()
    }
    
    func releaseSecurityScope(for url: URL) {
        let path = url.standardizedFileURL.path
        if let storedURL = activeSecurityScopedResources[path] {
            storedURL.stopAccessingSecurityScopedResource()
            activeSecurityScopedResources.removeValue(forKey: path)
        }
    }

    // MARK: - Undo Management

    func registerUndoRecord(
        originalState: AudioMetadata,
        appliedState: AudioMetadata,
        backupURL: URL?
    ) {
        undoRecords[originalState.id] = MetadataUndoRecord(
            metadataID: originalState.id,
            originalState: originalState,
            appliedState: appliedState,
            confirmedAt: Date(),
            backupURL: backupURL
        )
    }

    func clearUndoRecord(for metadataID: AudioMetadata.ID) {
        undoRecords.removeValue(forKey: metadataID)
    }

    func undoAppliedMetadata(
        for metadataID: AudioMetadata.ID
    ) async throws -> (AudioMetadata, Set<URL>) {
        guard let record = undoRecords[metadataID] else {
            throw ReTaggerError.fileSystemError("未找到可撤回的记录。")
        }

        guard let currentIndex = audioFiles.firstIndex(where: { $0.id == metadataID }) else {
            undoRecords.removeValue(forKey: metadataID)
            throw ReTaggerError.fileSystemError("曲目已被移除，无法撤回。")
        }

        var restoredMetadata = record.originalState
        let appliedState = record.appliedState

        var affectedDirectories: Set<URL> = [
            appliedState.filePath.deletingLastPathComponent(),
            restoredMetadata.filePath.deletingLastPathComponent()
        ]

        for directory in affectedDirectories {
            _ = activateSecurityScope(for: directory)
        }

        var workingURL = appliedState.filePath
        let targetURL = restoredMetadata.filePath
        let targetDirectory = targetURL.deletingLastPathComponent()

        if workingURL.deletingLastPathComponent() != targetDirectory {
            workingURL = try await fileSystemService.moveFile(
                from: workingURL,
                toDirectory: targetDirectory
            )
            affectedDirectories.insert(workingURL.deletingLastPathComponent())
        }

        if workingURL.lastPathComponent != targetURL.lastPathComponent {
            workingURL = try await fileSystemService.renameFile(
                from: workingURL,
                to: targetURL.lastPathComponent
            )
            affectedDirectories.insert(workingURL.deletingLastPathComponent())
        }

        restoredMetadata.filePath = workingURL
        restoredMetadata.fileName = workingURL.lastPathComponent

        let fileManager = FileManager.default
        var restoredFromBackup = false
        if let backupURL = record.backupURL,
           fileManager.fileExists(atPath: backupURL.path) {
            do {
                if fileManager.fileExists(atPath: workingURL.path) {
                    try fileManager.removeItem(at: workingURL)
                }
                try fileManager.copyItem(at: backupURL, to: workingURL)
                restoredFromBackup = true
                Logger.fileSystem.info("Restored file from backup: \(workingURL.lastPathComponent)")
            } catch {
                Logger.fileSystem.logOperationFailed("RestoreBackup", error: error)
            }
        }

        if !restoredFromBackup {
            var metadataForWrite = restoredMetadata
            metadataForWrite.correctedTitle = nil
            metadataForWrite.correctedArtist = nil
            metadataForWrite.correctedAlbum = nil
            metadataForWrite.correctedGenre = nil
            metadataForWrite.correctedYear = nil
            metadataForWrite.suggestedFileName = nil
            metadataForWrite.suggestedFolderPath = nil

            try await metadataService.writeMetadata(metadataForWrite, to: workingURL)
        }

        restoredMetadata.processingState = .awaitingConfirmation
        restoredMetadata.error = nil

        audioFiles[currentIndex] = restoredMetadata
        undoRecords.removeValue(forKey: metadataID)

        return (restoredMetadata, affectedDirectories)
    }

    // MARK: - AI Metadata Processing

    /// 使用AI处理元数据
    func processMetadataWithAI(
        options: MetadataProcessingRequest.ProcessingOptions? = nil
    ) async throws {
        guard !self.audioFiles.isEmpty else {
            Logger.ai.warning("没有可处理的文件")
            throw ReTaggerError.aiProcessingFailed("没有可处理的文件")
        }

        self.isLoading = true
        defer { self.isLoading = false }

        Logger.ai.info("开始AI元数据处理，文件数: \(self.audioFiles.count)")

        do {
            // 使用提供的选项或默认选项
            let processingOptions = options ?? buildProcessingOptions()

            // 根据文件数量选择处理方式
            let updatedMetadata: [AudioMetadata]
            if self.audioFiles.count > self.settings.batchSize {
                // 大批量使用批处理
                updatedMetadata = try await aiMetadataService.processBatch(
                    self.audioFiles,
                    options: processingOptions,
                    batchSize: self.settings.batchSize,
                    fileNamingFormat: self.settings.fileNamingFormat
                )
            } else {
                // 小批量直接处理
                updatedMetadata = try await aiMetadataService.processMetadata(
                    self.audioFiles,
                    options: processingOptions,
                    fileNamingFormat: self.settings.fileNamingFormat
                )
            }

            // 更新元数据列表
            self.audioFiles = updatedMetadata

            Logger.ai.info("AI元数据处理完成，成功更新: \(updatedMetadata.count) 个文件")

        } catch {
            Logger.ai.error("AI元数据处理失败: \(error.localizedDescription)")
            throw error
        }
    }

    /// 应用AI修正到文件
    func applyAICorrections(writeToFiles: Bool = true) async throws {
        guard !self.audioFiles.isEmpty else {
            Logger.ai.warning("没有可应用的修正")
            throw ReTaggerError.aiProcessingFailed("没有可应用的修正")
        }

        self.isLoading = true
        defer { self.isLoading = false }

        Logger.ai.info("开始应用AI修正，文件数: \(self.audioFiles.count), 写入文件: \(writeToFiles)")

        do {
            let updatedMetadata = try await aiMetadataService.applyCorrections(
                self.audioFiles,
                writeToFiles: writeToFiles
            )

            // 更新元数据列表
            self.audioFiles = updatedMetadata

            Logger.ai.info("成功应用AI修正")

        } catch {
            Logger.ai.error("应用AI修正失败: \(error.localizedDescription)")
            throw error
        }
    }

    /// 构建处理选项（基于应用设置）
    private func buildProcessingOptions() -> MetadataProcessingRequest.ProcessingOptions {
        return MetadataProcessingRequest.ProcessingOptions(
            includeFileRenaming: true,
            includeFolderReorganization: true,
            preserveOriginalFiles: settings.createBackups,
            language: "zh-CN",
            enableCache: true,
            confidenceThreshold: settings.highConfidenceThreshold,
            preferredProvider: settings.selectedAIProvider.rawValue.lowercased()
        )
    }

    /// 根据当前已激活的沙盒资源列表，尝试将传入的普通 URL 还原为带沙盒授权凭据的 URL 实例（符合 D.R.Y 原则）
    func resolveSecurityScopedURL(for url: URL) -> URL {
        let fullPath = url.standardizedFileURL.path.decomposedStringWithCanonicalMapping
        var bestActivePath: String? = nil
        var bestActiveURL: URL? = nil
        
        for (activePath, activeURL) in activeSecurityScopedResources {
            let normalizedActivePath = activePath.decomposedStringWithCanonicalMapping
            if fullPath.hasPrefix(normalizedActivePath) {
                if fullPath == normalizedActivePath || fullPath.hasPrefix(normalizedActivePath + "/") {
                    if bestActivePath == nil || normalizedActivePath.count > bestActivePath!.count {
                        bestActivePath = normalizedActivePath
                        bestActiveURL = activeURL
                    }
                }
            }
        }
        
        if let activeURL = bestActiveURL, let activePath = bestActivePath {
            let relative = String(fullPath.dropFirst(activePath.count))
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return activeURL.appendingPathComponent(relative)
        }
        
        return url
    }

    /// 确保传入的文件 URL 的父目录具备沙盒访问权限。若不具备，则弹出系统选择框向用户请求授权。
    @discardableResult
    func ensureParentDirectoryAccess(for fileURL: URL) async -> Bool {
        let parentDir = fileURL.deletingLastPathComponent()
        let normalizedParentPath = parentDir.standardizedFileURL.path.decomposedStringWithCanonicalMapping
        
        // 1. 检查当前是否已被某一个已激活的沙盒作用域覆盖
        for (activePath, _) in activeSecurityScopedResources {
            let normalizedActive = activePath.decomposedStringWithCanonicalMapping
            if normalizedParentPath == normalizedActive || normalizedParentPath.hasPrefix(normalizedActive + "/") {
                return true
            }
        }
        
        // 2. 确实没有该父目录的访问权，弹出系统授权面板
        let message = localizationManager.string(
            "permission.request_directory",
            arguments: parentDir.lastPathComponent as NSString
        )
        
        if let grantedURL = await fileSystemService.requestAccess(to: parentDir, message: message) {
            return activateSecurityScope(for: grantedURL)
        }
        
        return false
    }

    // MARK: - External Drop Support

    /// 处理从外部（如 Finder）拖入的音频文件，仅读取元数据不移动文件
    func addDroppedFiles(_ urls: [URL]) async {
        let audioURLs = urls.filter { $0.isSupportedAudioFile }
        guard !audioURLs.isEmpty else { return }

        var newFiles: [AudioMetadata] = []
        for url in audioURLs {
            // 确保其父目录拥有沙盒访问授权
            guard await ensureParentDirectoryAccess(for: url) else {
                continue
            }
            
            // 去重：跳过已存在的文件
            let standardized = url.standardizedFileURL
            guard !audioFiles.contains(where: { $0.filePath.standardizedFileURL == standardized }) else {
                continue
            }

            do {
                var metadata = try await metadataService.readMetadata(from: url)
                metadata.importSource = .dropped
                newFiles.append(metadata)
            } catch {
                Logger.fileSystem.error("读取拖入文件元数据失败: \(url.lastPathComponent, privacy: .public) — \(error.localizedDescription, privacy: .public)")
            }
        }

        guard !newFiles.isEmpty else { return }

        audioFiles.append(contentsOf: newFiles)
        playbackController.append(newFiles)
        appendLog(.info, "拖入了 \(newFiles.count) 个音频文件")

        // 自动进入元数据审查步骤
        if currentStep == .directorySelection {
            currentStep = .metadataReview
        }
    }
}

// MARK: - Activity Log

extension AppCoordinator {
    struct ActivityLogEntry: Identifiable {
        enum Level: String {
            case info = "信息"
            case warning = "警告"
            case error = "错误"

            var localizationKey: String {
                switch self {
                case .info: return "logs.level.info"
                case .warning: return "logs.level.warning"
                case .error: return "logs.level.error"
                }
            }
        }
        let id = UUID()
        let timestamp: Date
        let level: Level
        let message: String
    }

    func appendLog(_ level: ActivityLogEntry.Level, _ message: String) {
        let entry = ActivityLogEntry(timestamp: Date(), level: level, message: message)
        activityLogs.append(entry)
        let maxEntries = 500
        if activityLogs.count > maxEntries {
            activityLogs.removeFirst(activityLogs.count - maxEntries)
        }
    }

    func clearLogs() {
        activityLogs.removeAll()
    }
}
