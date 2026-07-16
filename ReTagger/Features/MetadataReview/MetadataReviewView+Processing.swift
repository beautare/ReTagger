//
//  MetadataReviewView+Processing.swift
//  ReTagger
//
//  与 AI 写入、撤回及字段选择相关的业务逻辑
//

import SwiftUI
import AVFoundation
import OSLog

extension MetadataReviewView {
    // MARK: - 批量/单条确认与撤回

    func canApplyCorrections(selection: Set<AudioMetadata.ID>) -> Bool {
        resolveSelection(selection).contains { metadata in
            guard metadata.processingState == .awaitingConfirmation else { return false }
            return !MetadataField.relevantFields(for: metadata).isEmpty &&
                !pendingConfirmations.contains(metadata.id)
        }
    }

    func shouldShowConfirmOption(selection: Set<AudioMetadata.ID>) -> Bool {
        resolveSelection(selection).contains { metadata in
            metadata.processingState == .awaitingConfirmation &&
            !MetadataField.relevantFields(for: metadata).isEmpty
        }
    }

    func shouldShowUndoOption(selection: Set<AudioMetadata.ID>) -> Bool {
        resolveSelection(selection).contains { metadata in
            metadata.processingState == .completed &&
            coordinator.undoRecords[metadata.id] != nil
        }
    }

    func canUndoSelection(selection: Set<AudioMetadata.ID>) -> Bool {
        resolveSelection(selection).contains { metadata in
            canUndo(metadata)
        }
    }

    func undoSelection(selection: Set<AudioMetadata.ID>) {
        let targets = resolveSelection(selection).filter { canUndo($0) }
        guard !targets.isEmpty else {
            coordinator.setError(
                localizationManager.string("error.undo.selection_required")
            )
            return
        }
        for metadata in targets {
            undoTrack(metadata)
        }
    }

    @MainActor
    func confirmTrack(_ metadata: AudioMetadata) {
        guard metadata.processingState == .awaitingConfirmation else {
            coordinator.setError(
                localizationManager.string("error.confirmation.not_needed")
            )
            return
        }

        let availableFields = Set(MetadataField.relevantFields(for: metadata))
        guard !availableFields.isEmpty else {
            coordinator.setError(
                localizationManager.string("error.confirmation.no_fields")
            )
            return
        }

        let selectedFields = (fieldSelections[metadata.id] ?? availableFields)
            .intersection(availableFields)

        guard !selectedFields.isEmpty else {
            coordinator.setError(
                localizationManager.string("error.confirmation.field_selection_required")
            )
            return
        }

        // 冲突检测：单条确认时也需要检查是否与列表中其他文件冲突。
        // 检测基于“实际将写入”的形态——未勾选字段的建议不会落盘，不参与判定
        var effectiveMetadata = metadata
        for field in availableFields.subtracting(selectedFields) {
            field.discardSuggestion(on: &effectiveMetadata)
        }
        let detection = detectConflicts(in: [effectiveMetadata])
        registerDiscoveredDiskFiles(detection.discoveredDiskFiles)
        if !detection.groups.isEmpty {
            pendingConflicts = detection.groups
            isShowingConflictResolution = true
            return
        }

        updateDefaultFieldSelection(to: selectedFields)

        pendingConfirmations.insert(metadata.id)
        updateProcessingState(metadataID: metadata.id, to: .processing)

        Task {
            // Ensure backup access
            if await !coordinator.ensureBackupDirectoryAccess() {
                await MainActor.run {
                    pendingConfirmations.remove(metadata.id)
                    updateProcessingState(metadataID: metadata.id, to: .awaitingConfirmation)
                    isShowingBackupAccessDeniedAlert = true
                }
                return
            }

            do {
                let (updatedMetadata, affectedDirectories) = try await applyMetadataToDisk(
                    metadata,
                    applying: selectedFields
                )
                await MainActor.run {
                    pendingConfirmations.remove(metadata.id)
                    commitUpdatedMetadata(updatedMetadata)
                    tableSelection = [updatedMetadata.id]
                    for directory in affectedDirectories {
                        coordinator.invalidateCache(for: directory)
                    }
                }
            } catch {
                await MainActor.run {
                    pendingConfirmations.remove(metadata.id)
                    updateProcessingState(metadataID: metadata.id, to: .awaitingConfirmation)
                    let message: String
                    if let retaggerError = error as? ReTaggerError {
                        message = ErrorPresenter.present(retaggerError, localization: localizationManager).message
                    } else {
                        message = localizationManager.string(
                            "error.write.failed_generic",
                            arguments: error.localizedDescription
                        )
                    }
                    coordinator.setError(message)
                }
            }
        }
    }

    func undoTrack(_ metadata: AudioMetadata) {
        guard coordinator.undoRecords[metadata.id] != nil else {
            coordinator.setError(
                localizationManager.string("error.undo.no_record")
            )
            return
        }

        pendingUndoRequests.insert(metadata.id)

        Task {
            do {
                let (restoredMetadata, affectedDirectories) = try await coordinator.undoAppliedMetadata(for: metadata.id)
                await MainActor.run {
                    pendingUndoRequests.remove(metadata.id)
                    if let index = currentFiles.firstIndex(where: { $0.id == restoredMetadata.id }) {
                        currentFiles[index] = restoredMetadata
                    }
                    if let index = coordinator.audioFiles.firstIndex(where: { $0.id == restoredMetadata.id }) {
                        coordinator.audioFiles[index] = restoredMetadata
                    }
                    synchronizeFieldSelectionsWithFiles()
                    tableSelection = [restoredMetadata.id]
                    for directory in affectedDirectories {
                        coordinator.invalidateCache(for: directory)
                    }
                }
            } catch {
                await MainActor.run {
                    pendingUndoRequests.remove(metadata.id)
                    coordinator.setError(
                        localizationManager.string("error.undo.failed", arguments: error.localizedDescription)
                    )
                }
            }
        }
    }
    
    @MainActor
    func discardTrack(_ metadata: AudioMetadata) {
        guard metadata.processingState == .awaitingConfirmation else { return }
        
        var updated = metadata
        updated.clearCorrections()
        
        commitUpdatedMetadata(updated)
        fieldSelections.removeValue(forKey: metadata.id)
    }
    
    func discardSelection(selection: Set<AudioMetadata.ID>) {
        let targets = resolveSelection(selection).filter { $0.processingState == .awaitingConfirmation }
        guard !targets.isEmpty else { return }
        
        Task { @MainActor in
            for metadata in targets {
                discardTrack(metadata)
            }
        }
    }

    func confirmableTargets(for selection: Set<AudioMetadata.ID>) -> [AudioMetadata] {
        resolveSelection(selection).filter { metadata in
            metadata.processingState == .awaitingConfirmation &&
                !MetadataField.relevantFields(for: metadata).isEmpty &&
                !pendingConfirmations.contains(metadata.id)
        }
    }

    func applyCorrections(selection: Set<AudioMetadata.ID>) {
        let targets = confirmableTargets(for: selection)

        guard !targets.isEmpty else {
            coordinator.setError(
                localizationManager.string("error.confirmation.selection_required")
            )
            return
        }

        // 冲突检测：批量确认时检查所有待写入文件之间的冲突。
        // 检测基于“实际将写入”的形态——剔除未勾选字段的建议后再判定
        let effectiveTargets = targets.map { metadata -> AudioMetadata in
            let available = Set(MetadataField.relevantFields(for: metadata))
            let selected = (fieldSelections[metadata.id] ?? available).intersection(available)
            var effective = metadata
            for field in available.subtracting(selected) {
                field.discardSuggestion(on: &effective)
            }
            return effective
        }

        let detection = detectConflicts(in: effectiveTargets)
        registerDiscoveredDiskFiles(detection.discoveredDiskFiles)

        // 冲突文件交给处理窗口，其余文件继续本次批量写入，不再整批中断
        var writeTargets = targets
        if !detection.groups.isEmpty {
            pendingConflicts = detection.groups
            isShowingConflictResolution = true
            let conflictedIDs = Set(detection.groups.flatMap(\.memberIDs))
            writeTargets = targets.filter { !conflictedIDs.contains($0.id) }
            guard !writeTargets.isEmpty else { return }
        }

        isApplyingCorrections = true
        applyProgress = 0.0

        Task {
            // Ensure backup access
            if await !coordinator.ensureBackupDirectoryAccess() {
                await MainActor.run {
                    isApplyingCorrections = false
                    applyProgress = 0.0
                    isShowingBackupAccessDeniedAlert = true
                }
                return
            }

            var successes: Int = 0
            var failures: [(AudioMetadata, Error)] = []
            let totalCount = Double(writeTargets.count)

            for (index, metadata) in writeTargets.enumerated() {
                let availableFields = Set(MetadataField.relevantFields(for: metadata))
                let selectedFields = (fieldSelections[metadata.id] ?? availableFields)
                    .intersection(availableFields)

                guard !selectedFields.isEmpty else {
                    failures.append((metadata, ReTaggerError.fileSystemError("未选择写入字段")))
                    await MainActor.run {
                        applyProgress = Double(index + 1) / totalCount
                    }
                    continue
                }

                await MainActor.run {
                    updateDefaultFieldSelection(to: selectedFields)
                    pendingConfirmations.insert(metadata.id)
                    updateProcessingState(metadataID: metadata.id, to: .processing)
                }

                do {
                    let (updatedMetadata, affectedDirectories) = try await applyMetadataToDisk(
                        metadata,
                        applying: selectedFields
                    )

                    await MainActor.run {
                        successes += 1
                        pendingConfirmations.remove(metadata.id)
                        commitUpdatedMetadata(updatedMetadata)
                        for directory in affectedDirectories {
                            coordinator.invalidateCache(for: directory)
                        }
                        applyProgress = Double(index + 1) / totalCount
                    }
                } catch {
                    await MainActor.run {
                        pendingConfirmations.remove(metadata.id)
                        markMetadataAsFailed(metadataID: metadata.id, error: error)
                        failures.append((metadata, error))
                        applyProgress = Double(index + 1) / totalCount
                    }
                }
            }

            await MainActor.run {
                isApplyingCorrections = false
                applyProgress = 0.0

                if !failures.isEmpty {
                    let message = failures
                        .map { describeWriteFailure(for: $0.0, error: $0.1) }
                        .joined(separator: "；")
                    coordinator.setError(
                        localizationManager.string("error.batch.partial_write_failure", arguments: message)
                    )
                } else {
                    Logger.ai.info("成功确认 \(successes) 个文件的 AI 修正")
                }
            }
        }
    }

    func canConfirm(_ metadata: AudioMetadata) -> Bool {
        guard metadata.processingState == .awaitingConfirmation else { return false }
        guard !pendingConfirmations.contains(metadata.id),
              !pendingUndoRequests.contains(metadata.id),
              !isApplyingCorrections,
              !isProcessing else { return false }
        let fields = MetadataField.relevantFields(for: metadata)
        guard !fields.isEmpty else { return false }
        let selections = fieldSelections[metadata.id] ?? Set(fields)
        return !selections.isEmpty
    }

    func canUndo(_ metadata: AudioMetadata) -> Bool {
        guard metadata.processingState == .completed else { return false }
        guard let record = coordinator.undoRecords[metadata.id] else { return false }
        // Only allow undo if a backup exists
        guard record.backupURL != nil else { return false }
        
        return !pendingUndoRequests.contains(metadata.id) &&
            !pendingConfirmations.contains(metadata.id)
    }

    @MainActor
    func applyMetadataToDisk(
        _ metadata: AudioMetadata,
        applying fields: Set<MetadataField>
    ) async throws -> (AudioMetadata, Set<URL>) {
        guard !fields.isEmpty else {
            throw ReTaggerError.fileSystemError("未选择写入字段")
        }

        let originalState = metadata
        var updated = metadata
        var currentURL = metadata.filePath
        let parentDir = currentURL.deletingLastPathComponent()
        var affectedDirectories: Set<URL> = [parentDir]

        // 抑制目录监听在写入过程中把瞬时磁盘状态误判为外部删除，
        // 写入结束后（无论成功或失败）对受影响目录补做一次外部变更重扫描
        coordinator.beginManagedFileOperation()
        defer { coordinator.endManagedFileOperation(affecting: affectedDirectories) }

        if !coordinator.activateSecurityScope(for: parentDir) {
            let message = localizationManager.string("permission.request_directory", arguments: parentDir.lastPathComponent)
            if let granted = await coordinator.fileSystemService.requestAccess(to: parentDir, message: message) {
                coordinator.registerOpenedDirectory(granted)
                _ = coordinator.activateSecurityScope(for: granted)
            } else {
                throw ReTaggerError.fileSystemError(localizationManager.string("error.directory_access_missing", arguments: parentDir.lastPathComponent))
            }
        }

        playbackController.releaseIfTrackActive(metadata)

        let allRelevant = Set(MetadataField.relevantFields(for: metadata))
        let skippedFields = allRelevant.subtracting(fields)

        var metadataForWrite = updated
        for field in skippedFields {
            field.discardSuggestion(on: &metadataForWrite)
        }

        var backupURL: URL?
        if coordinator.settings.createBackups {
            let backupLocation: URL?
            if let active = coordinator.activeBackupDirectory {
                backupLocation = active
            } else if let customPath = coordinator.settings.backupLocation {
                backupLocation = URL(fileURLWithPath: customPath)
            } else {
                backupLocation = nil // Let FileSystemService use default
            }
            
            let workspaceRoot = coordinator.workspaceDirectories.first { dir in
                currentURL.standardizedFileURL.path.hasPrefix(dir.standardizedFileURL.path)
            }
            
            backupURL = try await coordinator.fileSystemService.createBackup(
                of: currentURL,
                backupLocation: backupLocation,
                workspaceRoot: workspaceRoot
            )
        }

        do {
            try await coordinator.metadataService.writeMetadata(metadataForWrite, to: currentURL)
        } catch {
            if let backup = backupURL {
                try await coordinator.fileSystemService.restoreBackup(from: backup, to: currentURL)
            }
            throw error
        }

        let verificationAsset = AVURLAsset(url: currentURL)
        do {
            let isPlayable = try await verificationAsset.load(.isPlayable)
            guard isPlayable else {
                throw ReTaggerError.metadataWriteError(currentURL)
            }
        } catch {
            if let backup = backupURL {
                try await coordinator.fileSystemService.restoreBackup(from: backup, to: currentURL)
            }
            throw error
        }

        if fields.contains(.fileName),
           let suggestedFileName = updated.suggestedFileName,
           !suggestedFileName.isEmpty,
           suggestedFileName != updated.fileName {
            do {
                currentURL = try await coordinator.fileSystemService.renameFile(
                    from: currentURL,
                    to: suggestedFileName
                )
                affectedDirectories.insert(currentURL.deletingLastPathComponent())
                coordinator.syncWorkspaceDirectoryPath(from: updated.filePath, to: currentURL)
                updated.filePath = currentURL
                updated.fileName = currentURL.lastPathComponent
            } catch {
                if let backup = backupURL {
                    try await coordinator.fileSystemService.restoreBackup(from: backup, to: currentURL)
                }
                throw error
            }
        } else if skippedFields.contains(.fileName) {
            updated.suggestedFileName = nil
        }

        propagateCorrections(
            into: &updated,
            applying: fields,
            discarding: skippedFields
        )

        updated.processingState = .completed
        updated.error = nil

        coordinator.registerUndoRecord(
            originalState: originalState,
            appliedState: updated,
            backupURL: backupURL
        )

        Logger.ai.info("已确认 AI 修正到文件: \(updated.fileName, privacy: .public)")

        return (updated, affectedDirectories)
    }

    @MainActor
    func updateProcessingState(
        metadataID: AudioMetadata.ID,
        to state: AudioMetadata.ProcessingState
    ) {
        if let index = currentFiles.firstIndex(where: { $0.id == metadataID }) {
            currentFiles[index].processingState = state
        }
        if let index = coordinator.audioFiles.firstIndex(where: { $0.id == metadataID }) {
            coordinator.audioFiles[index].processingState = state
        }
    }

    @MainActor
    func commitUpdatedMetadata(_ metadata: AudioMetadata) {
        if let index = currentFiles.firstIndex(where: { $0.id == metadata.id }) {
            currentFiles[index] = metadata
        }
        if let index = coordinator.audioFiles.firstIndex(where: { $0.id == metadata.id }) {
            coordinator.audioFiles[index] = metadata
        }
        synchronizeFieldSelectionsWithFiles()
    }

    @MainActor
    func markMetadataAsFailed(metadataID: AudioMetadata.ID, error: Error) {
        let message = error.localizedDescription

        if let index = currentFiles.firstIndex(where: { $0.id == metadataID }) {
            currentFiles[index].processingState = .failed
            currentFiles[index].error = message
        }
        if let index = coordinator.audioFiles.firstIndex(where: { $0.id == metadataID }) {
            coordinator.audioFiles[index].processingState = .failed
            coordinator.audioFiles[index].error = message
        }

        Logger.ai.error("应用 AI 修正失败: \(message, privacy: .public)")
    }

    func propagateCorrections(
        into metadata: inout AudioMetadata,
        applying fields: Set<MetadataField>,
        discarding skippedFields: Set<MetadataField>
    ) {
        for field in fields {
            field.applySelection(to: &metadata)
        }
        for field in skippedFields {
            field.discardSuggestion(on: &metadata)
        }
    }

    // MARK: - AI 处理与字段选择

    func processWithAI() {
        guard !isProcessing else { return }

        // 点数前置检查：与右键选择路径保持一致的失败反馈
        let requiredCredits = currentFiles.count
        let (isQuotaAvailable, currentBalance) = checkQuotaAvailability(requiredCount: requiredCredits)
        if !isQuotaAvailable, let balance = currentBalance {
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
        let previousStates = Dictionary(uniqueKeysWithValues: currentFiles.map { ($0.id, $0.processingState) })

        // 行级处理提示：整体处理时先标记所有曲目为 processing，驱动表格内的掠过动画
        for index in currentFiles.indices {
            currentFiles[index].processingState = .processing
        }
        coordinator.audioFiles = currentFiles

        if selectedProvider != coordinator.settings.selectedAIProvider {
            var newSettings = coordinator.settings
            newSettings.selectedAIProvider = selectedProvider
            coordinator.updateSettings(newSettings)
        }

        Task {
            // Ensure backup access
            if await !coordinator.ensureBackupDirectoryAccess() {
                await MainActor.run {
                    isProcessing = false
                    processingProgress = 0.0
                    restoreProcessingStates(previousStates)
                    isShowingBackupAccessDeniedAlert = true
                }
                return
            }

            do {
                try await coordinator.processMetadataWithAI()

                await MainActor.run {
                    isProcessing = false
                    processingProgress = 1.0
                    currentFiles = coordinator.audioFiles
                    applySortOrder(sortOrder)
                    synchronizeFieldSelectionsWithFiles()
                    
                    // Auto-scroll to the first item awaiting confirmation
                    if let firstProcessed = currentFiles.first(where: { $0.processingState == .awaitingConfirmation }) {
                        pendingScrollTarget = firstProcessed.id
                    }

                    Logger.ai.info("AI 打标签完成：\(currentFiles.count, privacy: .public) 条")
                }

            } catch {
                await MainActor.run {
                    isProcessing = false
                    processingProgress = 0.0
                    restoreProcessingStates(previousStates)

                    let feedback = humanizedAIError(error)
                    Logger.ai.error("\(feedback.logMessage, privacy: .public)")
                    coordinator.setError(feedback.userMessage)
                }
            }
        }
    }

    func applySortOrder(_ order: [KeyPathComparator<AudioMetadata>]) {
        guard !order.isEmpty else { return }
        currentFiles.sort(using: order)
        coordinator.audioFiles = currentFiles

        // 顺序播放模式下，排序变更同步到播放队列
        if playbackController.state.isActive
            && playbackController.state.order == .sequential {
            playbackController.reorderQueue(currentFiles)
        }
    }

    /// 将当前排序偏好持久化到设置中
    func persistSortPreference(_ order: [KeyPathComparator<AudioMetadata>]) {
        guard let first = order.first else { return }
        let ascending = first.order == .forward

        // keyPath → MetadataColumn 反向映射
        let mapping: [PartialKeyPath<AudioMetadata>: MetadataColumn] = [
            \AudioMetadata.sortableFileName: .fileName,
            \AudioMetadata.sortableOriginalTitle: .title,
            \AudioMetadata.sortableOriginalArtist: .artist,
            \AudioMetadata.sortableOriginalAlbum: .album,
            \AudioMetadata.sortableOriginalGenre: .genre,
            \AudioMetadata.sortableOriginalYear: .year,
            \AudioMetadata.sortableDuration: .duration,
            \AudioMetadata.sortableFileSize: .fileSize,
            \AudioMetadata.sortableBitrate: .bitrate,
            \AudioMetadata.sortableSampleRate: .sampleRate,
            \AudioMetadata.sortableFormat: .format,
            \AudioMetadata.sortableCreationDate: .creationDate,
            \AudioMetadata.sortableModificationDate: .modificationDate,
            \AudioMetadata.processingStateSortRank: .status,
        ]

        if let column = mapping[first.keyPath] {
            coordinator.settings.tableSortPreference = SortPreference(
                column: column,
                ascending: ascending
            )
            coordinator.settings.save()
        }
    }

    /// 根据列名和排序方向构造对应的 KeyPathComparator
    func sortComparator(for column: MetadataColumn, ascending: Bool) -> KeyPathComparator<AudioMetadata>? {
        let order: SortOrder = ascending ? .forward : .reverse
        switch column {
        case .fileName:
            return KeyPathComparator(\AudioMetadata.sortableFileName, order: order)
        case .title:
            return KeyPathComparator(\AudioMetadata.sortableOriginalTitle, order: order)
        case .artist:
            return KeyPathComparator(\AudioMetadata.sortableOriginalArtist, order: order)
        case .album:
            return KeyPathComparator(\AudioMetadata.sortableOriginalAlbum, order: order)
        case .genre:
            return KeyPathComparator(\AudioMetadata.sortableOriginalGenre, order: order)
        case .year:
            return KeyPathComparator(\AudioMetadata.sortableOriginalYear, order: order)
        case .duration:
            return KeyPathComparator(\AudioMetadata.sortableDuration, order: order)
        case .fileSize:
            return KeyPathComparator(\AudioMetadata.sortableFileSize, order: order)
        case .bitrate:
            return KeyPathComparator(\AudioMetadata.sortableBitrate, order: order)
        case .sampleRate:
            return KeyPathComparator(\AudioMetadata.sortableSampleRate, order: order)
        case .format:
            return KeyPathComparator(\AudioMetadata.sortableFormat, order: order)
        case .creationDate:
            return KeyPathComparator(\AudioMetadata.sortableCreationDate, order: order)
        case .modificationDate:
            return KeyPathComparator(\AudioMetadata.sortableModificationDate, order: order)
        case .status:
            return KeyPathComparator(\AudioMetadata.processingStateSortRank, order: order)
        }
    }

    /// 将错误转化为更友好的提示，并返回详尽日志信息
    func humanizedAIError(_ error: Error) -> (userMessage: String, logMessage: String) {
        let raw = error.localizedDescription

        // Helper to extract apiError from ReTaggerError
        func extractApiError(_ err: Error) -> (Int, String)? {
            if let reError = err as? ReTaggerError {
                if case .apiError(let code, let msg) = reError { return (code, msg) }
            }
            return nil
        }
        
        if let (code, message) = extractApiError(error) {
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            if code == 429 {
                let isAuthenticated = coordinator.authService.isAuthenticated
                if isAuthenticated {
                    return (
                        localizationManager.string("error.ai.rate_limit.authenticated"),
                        "API 429（已登录）：\(trimmed)"
                    )
                } else {
                    return (
                        localizationManager.string("error.ai.rate_limit.guest"),
                        "API 429（游客）：\(trimmed)"
                    )
                }
            } else if (400...499).contains(code) {
                let isJSON = trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
                let displayMsg = isJSON ? localizationManager.string("error.ai.invalid_request_payload") : trimmed
                return (
                    localizationManager.string("error.ai.client_error", arguments: code, displayMsg),
                    "API \(code) 客户端错误：\(trimmed)"
                )
            } else if (500...599).contains(code) {
                let isJSON = trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
                let displayMsg = isJSON ? localizationManager.string("error.ai.service_overloaded") : trimmed
                return (
                    localizationManager.string("error.ai.server_error", arguments: code, displayMsg),
                    "API \(code) 服务端错误：\(trimmed)"
                )
            }
            return (
                localizationManager.string("error.ai.unknown_code", arguments: code, trimmed),
                "API 异常 \(code)：\(trimmed)"
            )
        }

        // Handle specific aiProcessingFailed if any
        if let reError = error as? ReTaggerError, case .aiProcessingFailed(let msg) = reError {
            return (
                localizationManager.string("error.ai.processing_failed", arguments: msg),
                "AI 处理失败：\(msg)"
            )
        }

        return (
            localizationManager.string("error.ai.generic_exception", arguments: raw),
            "AI 处理异常：\(raw)"
        )
    }

    /// 恢复指定曲目的 processing 状态，用于失败或中断时撤回行内动画
    func restoreProcessingStates(_ states: [AudioMetadata.ID: AudioMetadata.ProcessingState]) {
        for index in currentFiles.indices {
            if let original = states[currentFiles[index].id] {
                currentFiles[index].processingState = original
            }
        }
        for index in coordinator.audioFiles.indices {
            if let original = states[coordinator.audioFiles[index].id] {
                coordinator.audioFiles[index].processingState = original
            }
        }
    }

    @MainActor
    func synchronizeFieldSelectionsWithFiles() {
        var updatedSelections: [AudioMetadata.ID: Set<MetadataField>] = [:]

        for metadata in currentFiles where metadata.processingState == .awaitingConfirmation {
            let available = Set(MetadataField.relevantFields(for: metadata))
            if available.isEmpty {
                updateProcessingState(metadataID: metadata.id, to: .completed)
                continue
            }
            let defaultSelection = available
            let existing = fieldSelections[metadata.id] ?? defaultSelection
            let sanitized = existing.intersection(available)
            updatedSelections[metadata.id] = sanitized.isEmpty ? defaultSelection : sanitized
        }

        fieldSelections = updatedSelections
    }

    func loadDefaultFieldSelection() {
        hasLoadedDefaultFieldSelection = true
        let storedRawValues = coordinator.settings.metadataWriteFieldDefaults
        let mappedFields = storedRawValues?.compactMap(MetadataField.init(rawValue:)) ?? MetadataField.allCases
        let selection = sanitizeDefaultFieldSelection(Set(mappedFields))
        defaultFieldSelection = selection
    }

    func updateDefaultFieldSelection(to newSelection: Set<MetadataField>) {
        let sanitized = sanitizeDefaultFieldSelection(newSelection)
        guard sanitized != defaultFieldSelection else { return }

        let previousDefault = defaultFieldSelection
        defaultFieldSelection = sanitized
        propagateDefaultFieldSelectionChange(from: previousDefault, to: sanitized)
        persistDefaultFieldSelectionIfNeeded(sanitized)
    }

    func sanitizeDefaultFieldSelection(_ selection: Set<MetadataField>) -> Set<MetadataField> {
        let allFields = Set(MetadataField.allCases)
        let validated = selection.intersection(allFields)
        return validated.isEmpty ? allFields : validated
    }

    func normalizedFieldSelection(
        _ selection: Set<MetadataField>,
        for available: Set<MetadataField>
    ) -> Set<MetadataField> {
        selection.intersection(available)
    }

    func propagateDefaultFieldSelectionChange(
        from oldSelection: Set<MetadataField>,
        to newSelection: Set<MetadataField>
    ) {
        guard oldSelection != newSelection else { return }

        for metadata in currentFiles where metadata.processingState == .awaitingConfirmation {
            let available = Set(MetadataField.relevantFields(for: metadata))
            if available.isEmpty {
                updateProcessingState(metadataID: metadata.id, to: .completed)
                continue
            }

            let oldNormalized = normalizedFieldSelection(oldSelection, for: available)
            let currentSelection = fieldSelections[metadata.id] ?? oldNormalized
            guard currentSelection == oldNormalized else { continue }

            fieldSelections[metadata.id] = available
        }
    }

    func persistDefaultFieldSelectionIfNeeded(_ selection: Set<MetadataField>) {
        let allFields = Set(MetadataField.allCases)
        let rawValues: Set<String>? = selection == allFields
            ? nil
            : Set(selection.map(\.rawValue))

        if coordinator.settings.metadataWriteFieldDefaults != rawValues {
            var settings = coordinator.settings
            settings.metadataWriteFieldDefaults = rawValues
            coordinator.updateSettings(settings)
        }
    }

    // MARK: - 同名冲突检测与解决

    /// 检测即将写入的文件中是否存在同名冲突。
    /// 检测维度：1) finalTitle + finalArtist 逻辑重复；2) 目标文件名完全相同。
    /// 纯检测无副作用：磁盘上发现的未跟踪同名文件通过 discoveredDiskFiles 返回，
    /// 由调用方决定是否并入列表
    func detectConflicts(
        in targets: [AudioMetadata]
    ) -> (groups: [ConflictGroup], discoveredDiskFiles: [AudioMetadata]) {
        let targetIDs = Set(targets.map(\.id))
        // 目标文件用调用方传入的“实际将写入”副本参与判定，
        // 而非 currentFiles 里含全部建议的原始数据
        let targetsByID = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })

        // ── 维度 1：逻辑重复 — finalTitle + finalArtist ──
        // 仅在 .awaitingConfirmation 文件之间检测（它们即将被修正）
        let allConfirmable = currentFiles
            .map { targetsByID[$0.id] ?? $0 }
            .filter { $0.processingState == .awaitingConfirmation }
        var titleArtistMap: [String: [AudioMetadata.ID]] = [:]
        for metadata in allConfirmable {
            let title = (metadata.finalTitle ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let artist = (metadata.finalArtist ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            guard !title.isEmpty && !artist.isEmpty else { continue }
            let key = "\(artist)||||\(title)"
            titleArtistMap[key, default: []].append(metadata.id)
        }

        // ── 维度 2：磁盘真实存在性检查 ──
        let fileManager = FileManager.default
        var newDiskFiles: [AudioMetadata] = []
        for metadata in targets {
            let effectiveFileName = (metadata.suggestedFileName ?? metadata.fileName).decomposedStringWithCanonicalMapping
            let isCaseOnlyChange = metadata.filePath.lastPathComponent.lowercased() == effectiveFileName.lowercased()
            
            if !isCaseOnlyChange && metadata.fileName.decomposedStringWithCanonicalMapping != effectiveFileName {
                let destURL = metadata.filePath.deletingLastPathComponent().appendingPathComponent(effectiveFileName)
                if fileManager.fileExists(atPath: destURL.path) {
                    let destPathNFD = destURL.standardizedFileURL.path.decomposedStringWithCanonicalMapping
                    let alreadyTracked = currentFiles.contains(where: { 
                        $0.filePath.standardizedFileURL.path.decomposedStringWithCanonicalMapping == destPathNFD 
                    })
                    let alreadyAdded = newDiskFiles.contains(where: { 
                        $0.filePath.standardizedFileURL.path.decomposedStringWithCanonicalMapping == destPathNFD 
                    })
                    
                    if !alreadyTracked && !alreadyAdded {
                        let secureDestURL = coordinator.resolveSecurityScopedURL(for: destURL)
                        
                        var onDiskMetadata = AudioMetadata(
                            filePath: secureDestURL,
                            fileName: effectiveFileName,
                            fileSizeBytes: (try? fileManager.attributesOfItem(atPath: secureDestURL.path)[.size] as? Int64) ?? 0
                        )
                        onDiskMetadata.processingState = .completed
                        newDiskFiles.append(onDiskMetadata)
                    }
                }
            }
        }
        
        // ── 维度 3：文件名重复 ──
        // 检测范围为 currentFiles 全列表加上磁盘上新发现的同名文件：
        //   - 待确认文件的有效目标文件名 = suggestedFileName ?? fileName
        //   - 其他状态文件的有效目标文件名 = fileName（当前实际文件名）
        // 键做大小写 + Unicode 规范化归一，与 APFS 的同名判定保持一致
        var fileNameMap: [String: [AudioMetadata.ID]] = [:]
        var fileNameDisplay: [String: String] = [:]
        for metadata in currentFiles.map({ targetsByID[$0.id] ?? $0 }) + newDiskFiles {
            let effectiveFileName: String
            if metadata.processingState == .awaitingConfirmation {
                effectiveFileName = metadata.suggestedFileName ?? metadata.fileName
            } else {
                effectiveFileName = metadata.fileName
            }
            let key = ConflictGroup.normalizedFileNameKey(effectiveFileName)
            fileNameMap[key, default: []].append(metadata.id)
            if fileNameDisplay[key] == nil {
                fileNameDisplay[key] = effectiveFileName
            }
        }

        var groups: [ConflictGroup] = []
        var coveredIDs: Set<AudioMetadata.ID> = []

        // 逻辑重复组（仅保留包含至少一个待写入目标的组）
        for (key, ids) in titleArtistMap where ids.count >= 2 {
            guard ids.contains(where: { targetIDs.contains($0) }) else { continue }
            let parts = key.components(separatedBy: "||||")
            let group = ConflictGroup(
                matchKey: .titleArtist(title: parts[1], artist: parts[0]),
                memberIDs: ids
            )
            groups.append(group)
            coveredIDs.formUnion(ids)
        }

        // 文件名重复组（排除已被逻辑重复覆盖的，仅保留包含待写入目标的组）
        for (key, ids) in fileNameMap where ids.count >= 2 {
            guard ids.contains(where: { targetIDs.contains($0) }) else { continue }
            let uncoveredIDs = ids.filter { !coveredIDs.contains($0) }
            if uncoveredIDs.count >= 2 {
                groups.append(ConflictGroup(
                    matchKey: .fileName(name: fileNameDisplay[key] ?? key),
                    memberIDs: uncoveredIDs
                ))
            }
        }

        return (groups, newDiskFiles)
    }

    /// 将冲突检测中在磁盘上发现的未跟踪文件并入当前列表（冲突面板依赖 allFiles 呈现它们）
    @MainActor
    func registerDiscoveredDiskFiles(_ files: [AudioMetadata]) {
        guard !files.isEmpty else { return }
        currentFiles.append(contentsOf: files)
        coordinator.audioFiles = currentFiles

        // 检测阶段构造的占位条目只有路径与大小，异步补读真实标签：
        // 冲突面板“删谁留谁”的决策依赖标题/歌手/时长等信息
        Task { @MainActor in
            for placeholder in files {
                guard let real = try? await coordinator.metadataService.readMetadata(from: placeholder.filePath) else {
                    continue
                }
                applyDiscoveredFileMetadata(real, toFileWithID: placeholder.id)
            }
        }
    }

    /// 把补读到的真实标签合并到占位条目上，保留原有 ID 与处理状态
    @MainActor
    private func applyDiscoveredFileMetadata(_ real: AudioMetadata, toFileWithID id: AudioMetadata.ID) {
        func merge(into list: inout [AudioMetadata]) {
            guard let index = list.firstIndex(where: { $0.id == id }) else { return }
            var updated = list[index]
            updated.originalTitle = real.originalTitle
            updated.originalArtist = real.originalArtist
            updated.originalAlbum = real.originalAlbum
            updated.originalGenre = real.originalGenre
            updated.originalYear = real.originalYear
            updated.originalAlbumArtist = real.originalAlbumArtist
            updated.originalComposer = real.originalComposer
            updated.originalComment = real.originalComment
            updated.duration = real.duration
            updated.bitrate = real.bitrate
            updated.sampleRate = real.sampleRate
            updated.format = real.format
            updated.fileSizeBytes = real.fileSizeBytes
            updated.fileCreationDate = real.fileCreationDate
            updated.fileModificationDate = real.fileModificationDate
            list[index] = updated
        }
        merge(into: &currentFiles)
        merge(into: &coordinator.audioFiles)
    }

    /// 从冲突解决面板写入单个文件（绕过冲突检测，因为用户已在面板中处理了冲突）。
    /// 面板中被改名的“已有文件”（completed / pending 等状态）也走此入口
    func writeConflictFile(_ metadata: AudioMetadata) {
        let originalState = metadata.processingState
        guard originalState != .processing else { return }

        let availableFields = Set(MetadataField.relevantFields(for: metadata))
        guard !availableFields.isEmpty else { return }

        let selectedFields = (fieldSelections[metadata.id] ?? availableFields)
            .intersection(availableFields)
        guard !selectedFields.isEmpty else { return }

        // 仅候选文件的字段选择计入默认偏好：
        // “已有文件”改名只有 fileName 一个字段，不应覆盖用户的全局默认勾选
        if originalState == .awaitingConfirmation {
            updateDefaultFieldSelection(to: selectedFields)
        }
        pendingConfirmations.insert(metadata.id)
        updateProcessingState(metadataID: metadata.id, to: .processing)

        Task {
            if await !coordinator.ensureBackupDirectoryAccess() {
                await MainActor.run {
                    pendingConfirmations.remove(metadata.id)
                    restoreConflictWriteFailure(metadata: metadata, originalState: originalState)
                    isShowingBackupAccessDeniedAlert = true
                }
                return
            }

            do {
                let (updatedMetadata, affectedDirectories) = try await applyMetadataToDisk(
                    metadata,
                    applying: selectedFields
                )
                await MainActor.run {
                    pendingConfirmations.remove(metadata.id)
                    commitUpdatedMetadata(updatedMetadata)
                    for directory in affectedDirectories {
                        coordinator.invalidateCache(for: directory)
                    }
                }
            } catch {
                await MainActor.run {
                    pendingConfirmations.remove(metadata.id)
                    restoreConflictWriteFailure(metadata: metadata, originalState: originalState)
                    let message: String
                    if let retaggerError = error as? ReTaggerError {
                        message = ErrorPresenter.present(retaggerError, localization: localizationManager).message
                    } else {
                        message = localizationManager.string(
                            "error.write.failed_generic",
                            arguments: error.localizedDescription
                        )
                    }
                    coordinator.setError(message)
                }
            }
        }
    }

    /// 冲突面板写入失败的回滚：候选文件回到待确认；
    /// “已有文件”还原原状态并撤销面板注入的改名建议，避免凭空多出待确认项
    @MainActor
    private func restoreConflictWriteFailure(
        metadata: AudioMetadata,
        originalState: AudioMetadata.ProcessingState
    ) {
        if originalState == .awaitingConfirmation {
            updateProcessingState(metadataID: metadata.id, to: .awaitingConfirmation)
            return
        }
        if let index = currentFiles.firstIndex(where: { $0.id == metadata.id }) {
            currentFiles[index].suggestedFileName = nil
            currentFiles[index].processingState = originalState
        }
        if let index = coordinator.audioFiles.firstIndex(where: { $0.id == metadata.id }) {
            coordinator.audioFiles[index].suggestedFileName = nil
            coordinator.audioFiles[index].processingState = originalState
        }
    }

    /// 从冲突解决面板删除单个文件
    func deleteConflictFile(_ metadata: AudioMetadata) {
        executeTrash(for: [metadata])
    }
}
