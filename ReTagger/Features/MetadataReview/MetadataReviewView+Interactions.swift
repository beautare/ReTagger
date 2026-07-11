//
//  MetadataReviewView+Interactions.swift
//  ReTagger
//
//  表格交互、文件操作与 AI 处理触发
//

import SwiftUI
import AppKit

@MainActor
extension MetadataReviewView {

    // MARK: - Selection & Playback

    func handleDoubleTap(on metadata: AudioMetadata) {
        guard !currentFiles.isEmpty else { return }
        
        let ext = metadata.filePath.pathExtension.lowercased()
        if ["dsf", "dff"].contains(ext) {
            coordinator.setError(localizationManager.string("error.playback.unsupported_dsd"))
            return
        }

        playbackController.startPlayback(queue: currentFiles, from: metadata)
        tableSelection = [metadata.id]
    }

    func canPlaySelection(selection: Set<AudioMetadata.ID>) -> Bool {
        !resolveSelection(selection).isEmpty && !currentFiles.isEmpty
    }

    func playSelection(selection: Set<AudioMetadata.ID>) {
        let targets = resolveSelection(selection)
        guard let primary = targets.first else { return }
        
        let ext = primary.filePath.pathExtension.lowercased()
        if ["dsf", "dff"].contains(ext) {
            coordinator.setError(localizationManager.string("error.playback.unsupported_dsd"))
            return
        }

        playbackController.startPlayback(queue: currentFiles, from: primary)
        tableSelection = [primary.id]
    }

    /// 主动定位时调用：选中并滚动到当前播放曲目（双击播放条、初始加载等场景）
    func syncSelectionWithCurrentTrack() {
        guard let track = playbackController.state.currentTrack else {
            pendingScrollTarget = nil
            return
        }

        if let match = currentFiles.first(where: { $0.filePath == track.filePath }) {
            tableSelection = [match.id]
            pendingScrollTarget = match.id
        }
    }

    /// 自动切歌时调用：仅滚动到播放行，不覆盖用户当前的手动选择
    func scrollToCurrentTrack() {
        guard let track = playbackController.state.currentTrack else {
            return
        }

        if let match = currentFiles.first(where: { $0.filePath == track.filePath }) {
            pendingScrollTarget = match.id
        }
    }

    // MARK: - File Loading

    func loadFiles(from url: URL) {
        Task {
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let metadataList = try await coordinator.loadMetadata(
                    for: url,
                    includeSubdirectories: includeSubdirectories
                )

                await MainActor.run {
                    currentFiles = metadataList
                    coordinator.audioFiles = metadataList
                    applySortOrder(sortOrder)
                    synchronizeFieldSelectionsWithFiles()
                    syncSelectionWithCurrentTrack()
                }
            } catch {
                await MainActor.run {
                    coordinator.setError(
                        localizationManager.string("error.load_files_failed", arguments: error.localizedDescription as NSString)
                    )
                }
            }
        }
    }

    // MARK: - Finder & Trash

    func canRevealInFinder(selection: Set<AudioMetadata.ID>) -> Bool {
        !revealTargets(for: selection).isEmpty
    }

    func revealInFinder(selection: Set<AudioMetadata.ID>) {
        let targets = revealTargets(for: selection)
        guard !targets.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(targets)
    }

    func revealTargets(for selection: Set<AudioMetadata.ID>) -> [URL] {
        resolveSelection(selection)
            .map(\.filePath)
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// 将选中文件的完整路径复制到剪贴板（多选时按行分隔）
    func copyPaths(selection: Set<AudioMetadata.ID>) {
        let paths = resolveSelection(selection).map(\.filePath.path)
        guard !paths.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
    }

    func canMoveSelectionToTrash(selection: Set<AudioMetadata.ID>) -> Bool {
        !trashCandidates(for: selection).isEmpty
    }

    func prepareTrash(selection: Set<AudioMetadata.ID>) {
        let candidates = trashCandidates(for: selection)
        guard !candidates.isEmpty else { return }
        pendingTrashItems = candidates
        isShowingTrashConfirmation = true
    }

    func executeTrash(for items: [AudioMetadata]) {
        let fileManager = FileManager.default
        let candidates = items
        guard !candidates.isEmpty else { return }

             if let directory = currentDirectory,
            !coordinator.activateSecurityScope(for: directory) {
             coordinator.setError(
                 localizationManager.string("error.directory_access_missing", arguments: directory.path as NSString)
             )
             return
         }

        var removedIDs = Set<AudioMetadata.ID>()
        var failures: [(AudioMetadata, Error)] = []
        var permissionDenied: [AudioMetadata] = []

        for metadata in candidates {
            if playbackController.state.currentTrackID == metadata.id {
                playbackController.remove(metadata)
            }

            do {
                try fileManager.trashItem(at: metadata.filePath, resultingItemURL: nil)
                removedIDs.insert(metadata.id)
                playbackController.remove(metadata)
            } catch {
                let nsError = error as NSError
                if nsError.domain == NSCocoaErrorDomain && nsError.code == NSFileWriteNoPermissionError {
                    permissionDenied.append(metadata)
                } else {
                    failures.append((metadata, error))
                }
            }
        }

        if !removedIDs.isEmpty {
            currentFiles.removeAll { removedIDs.contains($0.id) }
            tableSelection.subtract(removedIDs)
            coordinator.audioFiles = currentFiles

            if let directory = currentDirectory {
                coordinator.invalidateCache(for: directory)
            }
        }

        if !permissionDenied.isEmpty {
            let names = permissionDenied.map(\.fileName).joined(separator: "、")
            coordinator.setError(
                localizationManager.string("error.trash_permission_denied", arguments: names as NSString)
            )
        }

        if let failure = failures.first {
            let failedNames = failures.map { $0.0.fileName }.joined(separator: "、")
            coordinator.setError(
                localizationManager.string("error.trash_failed", arguments: failedNames as NSString, failure.1.localizedDescription as NSString)
            )
        }
    }

    func describeWriteFailure(for metadata: AudioMetadata, error: Error) -> String {
        if let retaggerError = error as? ReTaggerError {
            switch retaggerError {
            case .metadataUnsupportedFormat:
                return localizationManager.string(
                    "error.write.unsupported_format",
                    arguments: metadata.fileName as NSString
                )
            case .metadataWriteError:
                return localizationManager.string(
                    "error.write.failed_permission",
                    arguments: metadata.fileName as NSString
                )
            case .fileSystemError(let message):
                return localizationManager.string(
                    "error.write.filesystem",
                    arguments: metadata.fileName as NSString,
                    message as NSString
                )
            case .permissionDenied:
                return localizationManager.string(
                    "error.write.permission_denied",
                    arguments: metadata.fileName as NSString
                )
            default:
                return localizationManager.string(
                    "error.write.generic",
                    arguments: metadata.fileName as NSString,
                    retaggerError.localizedDescription as NSString
                )
            }
        }
        return localizationManager.string(
            "error.write.generic",
            arguments: metadata.fileName as NSString,
            error.localizedDescription as NSString
        )
    }

    func trashCandidates(for selection: Set<AudioMetadata.ID>) -> [AudioMetadata] {
        resolveSelection(selection).filter { metadata in
            let path = metadata.filePath.path
            return FileManager.default.fileExists(atPath: path)
        }
    }

    // MARK: - AI Processing for Selection

    func canProcessWithAI(selection: Set<AudioMetadata.ID>) -> Bool {
        !resolveSelection(selection).isEmpty
    }
    
    /// 检查当前剩余点数是否足够处理指定数量的文件
    /// - Parameter requiredCount: 需要处理的文件数量
    /// - Returns: 包含检查结果和当前余额的元组
    private func checkQuotaAvailability(requiredCount: Int) -> (isAvailable: Bool, balance: Int?) {
        // 获取当前余额（无论登录与否，authService.balance 都会通过轮询保持更新）
        // 未登录时，设备配额会通过 /api/v1/tokens/check 获取并更新到 authService.balance
        let currentBalance = coordinator.authService.balance
        
        // 如果 balance 为 nil，说明还没有获取到配额信息，允许继续（由后端判断）
        guard let balance = currentBalance else {
            return (true, nil)
        }
        
        return (balance >= requiredCount, balance)
    }

    func processSelectionWithAI(selection: Set<AudioMetadata.ID>) {
        // 与右键菜单的启用条件保持一致：跳过处理中与待确认的条目，
        // 避免混合选择时把不该处理的行送去 AI（并多扣点数）
        let selectedItems = resolveSelection(selection).filter { metadata in
            [.pending, .failed, .userModified, .completed].contains(metadata.processingState)
        }
        guard !selectedItems.isEmpty else { return }
        
        // 点数前置检查
        let requiredCredits = selectedItems.count
        let (isQuotaAvailable, currentBalance) = checkQuotaAvailability(requiredCount: requiredCredits)
        
        if !isQuotaAvailable, let balance = currentBalance {
            // 点数不足，显示错误提示
            let userStatus = coordinator.authService.isAuthenticated
                ? localizationManager.string("account.status.authenticated")
                : localizationManager.string("account.status.guest")
            coordinator.setError(
                localizationManager.string(
                    "error.insufficient_credits",
                    arguments: requiredCredits, userStatus, balance
                )
            )
            return
        }

        isProcessing = true
        processingProgress = 0.0

        // 记录原始状态，便于失败时恢复
        let previousStates = Dictionary(uniqueKeysWithValues: selectedItems.map { ($0.id, $0.processingState) })
        // 行级处理提示：将待处理的曲目标记为 processing，驱动表格内的掠过动画
        for id in selectedItems.map(\.id) {
            if let index = currentFiles.firstIndex(where: { $0.id == id }) {
                currentFiles[index].processingState = .processing
            }
            if let index = coordinator.audioFiles.firstIndex(where: { $0.id == id }) {
                coordinator.audioFiles[index].processingState = .processing
            }
        }

        Task {
            do {
                let options = MetadataProcessingRequest.ProcessingOptions.default
                let updatedItems: [AudioMetadata]

                if selectedItems.count == 1 {
                    updatedItems = try await coordinator.aiMetadataService.processMetadata(
                        selectedItems,
                        options: options,
                        fileNamingFormat: coordinator.settings.fileNamingFormat
                    )
                } else {
                    updatedItems = try await coordinator.aiMetadataService.processBatch(
                        selectedItems,
                        options: options,
                        batchSize: Constants.Batch.defaultSize,
                        fileNamingFormat: coordinator.settings.fileNamingFormat
                    )
                }

                await MainActor.run {
                    for updatedItem in updatedItems {
                        if let index = currentFiles.firstIndex(where: { $0.id == updatedItem.id }) {
                            currentFiles[index] = updatedItem
                        }
                    }
                    coordinator.audioFiles = currentFiles
                    synchronizeFieldSelectionsWithFiles()

                    isProcessing = false
                    processingProgress = 1.0
                    coordinator.appendLog(.info, "AI 打标签完成：\(updatedItems.count) 条")
                }

            } catch {
                await MainActor.run {
                    isProcessing = false
                    processingProgress = 0.0
                    restoreProcessingStates(previousStates)

                    let feedback = humanizedAIError(error)
                    coordinator.appendLog(.error, feedback.logMessage)
                    coordinator.setError(feedback.userMessage)
                }
            }
        }
    }

    func resolveSelection(_ selection: Set<AudioMetadata.ID>) -> [AudioMetadata] {
        var activeSelection = selection
        if activeSelection.isEmpty {
            activeSelection = tableSelection
        }
        guard !activeSelection.isEmpty else { return [] }
        return currentFiles.filter { activeSelection.contains($0.id) }
    }
}
