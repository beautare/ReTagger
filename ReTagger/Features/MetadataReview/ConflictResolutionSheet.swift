//
//  ConflictResolutionSheet.swift
//  ReTagger
//
//  冲突解决模态面板：卡片式瀑布流冲突管理器 (Grouped Conflict Cards View)
//

import SwiftUI
import OSLog

struct ConflictResolutionSheet: View {
    @Binding var conflicts: [ConflictGroup]
    @Binding var allFiles: [AudioMetadata]
    let onWriteAndKeep: (AudioMetadata) -> Void
    let onDelete: (AudioMetadata) -> Void
    let onClose: () -> Void

    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var coordinator: AppCoordinator
    @StateObject private var preview = InlineAudioPreview()

    @State private var hoveredRowID: AudioMetadata.ID? = nil
    @State private var isHoveringClose = false

    // MARK: - Banner 引导富文本

    private var guideTextView: Text {
        Text(localizationManager.string("conflict.guide.part1"))
        + Text(Image(systemName: "trash")).foregroundColor(DesignSystem.Colors.error)
        + Text(localizationManager.string("conflict.guide.part2"))
        + Text(Image(systemName: "checkmark.circle")).foregroundColor(DesignSystem.Colors.success)
        + Text(localizationManager.string("conflict.guide.part3"))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader

            // 💡 交互解决指南提示条
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(DesignSystem.Colors.info)
                    .font(.body)
                
                guideTextView
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, 10)
            .background(DesignSystem.Colors.infoBackground(0.08))
            .cornerRadius(DesignSystem.CornerRadius.sm)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            
            Divider()

            if !conflicts.isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 0) {
                        ForEach(conflicts) { group in
                            conflictGroupCard(group: group)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.md)
                }
            } else {
                Spacer()
                Text(localizationManager.string("conflict.resolved_all"))
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .frame(minWidth: 900, maxWidth: .infinity, minHeight: 600, maxHeight: .infinity)
        .onChange(of: allFiles) { newFiles in
            recalculateConflicts(with: newFiles)
        }
        .onDisappear { preview.stop() }
        .ignoresSafeArea(.container, edges: .top) // 贴紧窗口上边缘，消除宿主 Titlebar 安全区空白
    }

    // MARK: - Sheet 标题

    private var sheetHeader: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(DesignSystem.Colors.warning)
                .font(.title2)
            VStack(alignment: .leading, spacing: 2) {
                Text(localizationManager.string("conflict.title", arguments: conflicts.count))
                    .font(DesignSystem.Typography.title3)
                Text(localizationManager.string("conflict.subtitle"))
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
            
            HStack(spacing: DesignSystem.Spacing.md) {
                // 简化后的关闭按钮
                Button {
                    preview.stop()
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isHoveringClose ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle()
                                .fill(isHoveringClose ? DesignSystem.Colors.backgroundTertiary : DesignSystem.Colors.backgroundSecondary)
                        )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHoveringClose = hovering
                }
                .keyboardShortcut(.cancelAction)
                .help(localizationManager.string("conflict.close.help"))
            }
        }
        .padding(.leading, 70)
        .padding(.trailing, DesignSystem.Spacing.md)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    // MARK: - 冲突组卡片

    @ViewBuilder
    private func conflictGroupCard(group: ConflictGroup) -> some View {
        let groupFiles = group.memberIDs.compactMap { id in allFiles.first { $0.id == id } }
        
        let hasTitleDiff = Set(groupFiles.map { ($0.finalTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).count > 1
        let hasArtistDiff = Set(groupFiles.map { ($0.finalArtist ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).count > 1
        let hasAlbumDiff = Set(groupFiles.map { ($0.finalAlbum ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).count > 1
        let hasYearDiff = Set(groupFiles.map { ($0.finalYear ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).count > 1
        let hasDurationDiff = Set(groupFiles.map { $0.durationDisplay.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).count > 1
        let hasBitrateDiff = Set(groupFiles.map { $0.bitrateDisplay.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).count > 1
        let hasFileSizeDiff = Set(groupFiles.map { $0.fileSizeDisplay.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).count > 1

        VStack(alignment: .leading, spacing: 0) {
            // 卡片头部
            HStack(spacing: 8) {
                Image(systemName: group.matchKey.icon)
                    .foregroundColor(DesignSystem.Colors.primary)
                    .font(.headline)
                
                Text(group.displayDescription)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                
                Spacer()
                
                Text(group.typeLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(DesignSystem.Colors.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(DesignSystem.Colors.primary.opacity(0.1))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(DesignSystem.Colors.backgroundSecondary.opacity(0.8))
            
            Divider()
            
            // 组内冲突文件行列表
            VStack(spacing: 0) {
                ForEach(Array(groupFiles.enumerated()), id: \.offset) { idx, file in
                    if idx > 0 {
                        Divider()
                    }
                    
                    FileRowView(
                        file: file,
                        allFiles: $allFiles,
                        conflicts: conflicts,
                        onWriteAndKeep: onWriteAndKeep,
                        onDelete: onDelete,
                        preview: preview,
                        hoveredRowID: $hoveredRowID,
                        hasTitleDiff: hasTitleDiff,
                        hasArtistDiff: hasArtistDiff,
                        hasAlbumDiff: hasAlbumDiff,
                        hasYearDiff: hasYearDiff,
                        hasDurationDiff: hasDurationDiff,
                        hasFileSizeDiff: hasFileSizeDiff,
                        hasBitrateDiff: hasBitrateDiff
                    )
                }
            }
        }
        .background(DesignSystem.Colors.backgroundElevated)
        .cornerRadius(DesignSystem.CornerRadius.md)
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                .stroke(DesignSystem.Colors.border.opacity(0.7), lineWidth: 0.5)
        )
        .shadow(
            color: DesignSystem.Shadows.small.color,
            radius: DesignSystem.Shadows.small.radius,
            x: DesignSystem.Shadows.small.x,
            y: DesignSystem.Shadows.small.y
        )
        .padding(.bottom, DesignSystem.Spacing.md)
    }

    // MARK: - 辅助

    private func recalculateConflicts(with newFiles: [AudioMetadata]) {
        var updatedConflicts: [ConflictGroup] = []
        
        for group in conflicts {
            let activeMembers = group.memberIDs.compactMap { id in
                newFiles.first { $0.id == id }
            }
            
            guard activeMembers.count >= 2 else { continue }
            
            switch group.matchKey {
            case .titleArtist(_, _):
                let confirmables = activeMembers.filter { $0.processingState == .awaitingConfirmation }
                if confirmables.count >= 2 {
                    updatedConflicts.append(group)
                }
            case .fileName(_):
                var nameMap: [String: [AudioMetadata.ID]] = [:]
                for file in activeMembers {
                    let effectiveName = file.processingState == .awaitingConfirmation
                        ? (file.suggestedFileName ?? file.fileName)
                        : file.fileName
                    nameMap[effectiveName, default: []].append(file.id)
                }
                
                for (n, ids) in nameMap where ids.count >= 2 {
                     let updatedGroup = ConflictGroup(
                        matchKey: .fileName(name: n),
                        memberIDs: ids
                    )
                    updatedConflicts.append(updatedGroup)
                }
            }
        }
        
        DispatchQueue.main.async {
            self.conflicts = updatedConflicts
            if updatedConflicts.isEmpty {
                self.onClose()
            }
        }
    }
}

// MARK: - FileRowView (独立持状态文件名常态输入框行视图)

struct FileRowView: View {
    let file: AudioMetadata
    @Binding var allFiles: [AudioMetadata]
    let conflicts: [ConflictGroup]
    let onWriteAndKeep: (AudioMetadata) -> Void
    let onDelete: (AudioMetadata) -> Void
    
    @ObservedObject var preview: InlineAudioPreview
    @Binding var hoveredRowID: AudioMetadata.ID?
    
    @EnvironmentObject private var localizationManager: LocalizationManager
    @EnvironmentObject private var coordinator: AppCoordinator

    @State private var editingFileName: String = ""
    @State private var fileNameError: String? = nil
    @State private var isShowingDeleteConfirmation = false
    @State private var pendingDeleteID: AudioMetadata.ID? = nil
    
    @State private var isDraggingProgress = false
    @State private var isHoveringProgress = false
    
    // 差异性布尔值
    let hasTitleDiff: Bool
    let hasArtistDiff: Bool
    let hasAlbumDiff: Bool
    let hasYearDiff: Bool
    let hasDurationDiff: Bool
    let hasFileSizeDiff: Bool
    let hasBitrateDiff: Bool

    init(
        file: AudioMetadata,
        allFiles: Binding<[AudioMetadata]>,
        conflicts: [ConflictGroup],
        onWriteAndKeep: @escaping (AudioMetadata) -> Void,
        onDelete: @escaping (AudioMetadata) -> Void,
        preview: InlineAudioPreview,
        hoveredRowID: Binding<AudioMetadata.ID?>,
        hasTitleDiff: Bool,
        hasArtistDiff: Bool,
        hasAlbumDiff: Bool,
        hasYearDiff: Bool,
        hasDurationDiff: Bool,
        hasFileSizeDiff: Bool,
        hasBitrateDiff: Bool
    ) {
        self.file = file
        self._allFiles = allFiles
        self.conflicts = conflicts
        self.onWriteAndKeep = onWriteAndKeep
        self.onDelete = onDelete
        self.preview = preview
        self._hoveredRowID = hoveredRowID
        self.hasTitleDiff = hasTitleDiff
        self.hasArtistDiff = hasArtistDiff
        self.hasAlbumDiff = hasAlbumDiff
        self.hasYearDiff = hasYearDiff
        self.hasDurationDiff = hasDurationDiff
        self.hasFileSizeDiff = hasFileSizeDiff
        self.hasBitrateDiff = hasBitrateDiff
        
        // 核心初始化：常态输入框默认预填当前建议的文件名
        self._editingFileName = State(initialValue: file.suggestedFileName ?? file.fileName)
    }

    private var isCandidate: Bool {
        file.processingState == .awaitingConfirmation
    }

    private var isModified: Bool {
        let currentName = file.suggestedFileName ?? file.fileName
        return editingFileName.trimmingCharacters(in: .whitespacesAndNewlines) != currentName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        let isActive = preview.activeFileID == file.id
        
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                // A. 播放试听控制
                HoverIconButton(
                    iconName: isActive && preview.isPlaying ? "pause.circle.fill" : "play.circle.fill",
                    color: isActive && preview.isPlaying ? DesignSystem.Colors.primary : DesignSystem.Colors.textSecondary,
                    hoverColor: DesignSystem.Colors.primary,
                    size: 16,
                    tooltip: localizationManager.string(isActive && preview.isPlaying ? "conflict.preview.pause" : "conflict.preview.play"),
                    action: { preview.togglePlayPause(for: file, coordinator: coordinator) }
                )
                
                // B. 文件名与常态编辑态（统一使用 TextField，方便已知文件也能被修改以避开冲突）
                HStack(spacing: 4) {
                    TextField(localizationManager.string("conflict.new_filename"), text: $editingFileName)
                        .textFieldStyle(.roundedBorder)
                        .font(DesignSystem.Typography.subheadline)
                        .onSubmit { commitFileNameEdit() }
                        .frame(width: 200)
                        .onChange(of: editingFileName) { _ in
                            fileNameError = nil
                        }
                    
                    if !isCandidate {
                        // 依然保留“已有”标签以标识这是一个已有文件
                        Text(localizationManager.string("conflict.label.existing"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(DesignSystem.Colors.backgroundSecondary)
                            .cornerRadius(4)
                    }
                    
                    if file.processingState == .processing {
                        ProgressView().controlSize(.small)
                    } else if isCandidate || isModified {
                        // 内联随附确认绿勾，替代右侧孤立的蓝底白勾
                        HoverIconButton(
                            iconName: "checkmark.circle",
                            color: DesignSystem.Colors.textSecondary,
                            hoverColor: DesignSystem.Colors.success,
                            size: 15,
                            tooltip: localizationManager.string("conflict.action.write_keep.help"),
                            action: { commitFileNameEdit() }
                        )
                    } else if file.processingState == .completed {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(DesignSystem.Colors.success)
                            .font(.system(size: 15))
                            .help(localizationManager.string("conflict.status.written"))
                    } else {
                        HoverIconButton(
                            iconName: "checkmark.circle",
                            color: DesignSystem.Colors.textSecondary,
                            hoverColor: DesignSystem.Colors.success,
                            size: 15,
                            tooltip: localizationManager.string("conflict.action.write_keep.help"),
                            action: { commitFileNameEdit() }
                        )
                    }
                }
                
                if let error = fileNameError {
                    Text(error)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.error)
                        .lineLimit(1)
                }

                Spacer(minLength: DesignSystem.Spacing.md)
                
                // C & D. 元数据对比标签区与格式指标，包裹在水平滚动视图中，防止在窗口窄时被挤出屏幕
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            metadataBadge(label: localizationManager.string("conflict.badge.title"), val: file.finalTitle, diff: hasTitleDiff, width: 120)
                            metadataBadge(label: localizationManager.string("conflict.badge.artist"), val: file.finalArtist, diff: hasArtistDiff, width: 90)
                            metadataBadge(label: localizationManager.string("conflict.badge.album"), val: file.finalAlbum, diff: hasAlbumDiff, width: 100)
                            metadataBadge(label: localizationManager.string("conflict.badge.year"), val: file.finalYear, diff: hasYearDiff, width: 68)
                        }
                        
                        HStack(spacing: 4) {
                            technicalBadge(val: file.durationDisplay, diff: hasDurationDiff, width: 48)
                            technicalBadge(val: file.fileSizeDisplay, diff: hasFileSizeDiff, width: 80)
                            technicalBadge(val: file.bitrateDisplay, diff: hasBitrateDiff, width: 72)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .frame(height: 24)
                
                // E. 操作按钮区
                HStack(spacing: 8) {
                    if canDelete {
                        HoverIconButton(
                            iconName: "trash",
                            color: DesignSystem.Colors.textSecondary,
                            hoverColor: DesignSystem.Colors.error,
                            size: 15,
                            tooltip: localizationManager.string("conflict.action.delete.help"),
                            action: {
                                pendingDeleteID = file.id
                                isShowingDeleteConfirmation = true
                            }
                        )
                    }
                }
                .frame(width: 26, alignment: .trailing)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(rowBackground(isHovered: hoveredRowID == file.id))
            .onHover { isHovered in
                if isHovered {
                    hoveredRowID = file.id
                } else if hoveredRowID == file.id {
                    hoveredRowID = nil
                }
            }
            .alert(localizationManager.string("conflict.confirm_delete.title"), isPresented: $isShowingDeleteConfirmation) {
                Button(localizationManager.string("common.cancel"), role: .cancel) { pendingDeleteID = nil }
                Button(localizationManager.string("common.delete"), role: .destructive) {
                    if let id = pendingDeleteID, let f = allFiles.first(where: { $0.id == id }) {
                        onDelete(f)
                    }
                    pendingDeleteID = nil
                }
            } message: {
                if let id = pendingDeleteID, let f = allFiles.first(where: { $0.id == id }) {
                    Text(localizationManager.string("conflict.confirm_delete.message", arguments: f.fileName as NSString))
                }
            }
            
            // F. 隐藏式渐变播放进度条（热区扩大至 16px，支持高优先级 Drag 阻断拖拽窗口，支持 Hover 变手指并放大白色指示滑块）
            if isActive && preview.duration > 0 {
                GeometryReader { geo in
                    let totalWidth = geo.size.width
                    let progress = preview.currentTime / max(preview.duration, 0.01)
                    let handleSize: CGFloat = (isDraggingProgress || isHoveringProgress) ? 12 : 8
                    let xOffset = max(0, min(totalWidth - handleSize, totalWidth * CGFloat(progress) - handleSize / 2))
                    
                    ZStack(alignment: .leading) {
                        // 轨道背景
                        Capsule()
                            .fill(Color.gray.opacity(0.15))
                            .frame(height: 4)
                        
                        // 填充进度
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [DesignSystem.Colors.primary, DesignSystem.Colors.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, min(totalWidth, totalWidth * CGFloat(progress))), height: 4)
                        
                        // 白色圆形滑块指示器
                        Circle()
                            .fill(Color.white)
                            .shadow(color: Color.black.opacity(0.3), radius: 1.5, x: 0, y: 0.5)
                            .frame(width: handleSize, height: handleSize)
                            .offset(x: xOffset)
                    }
                    .frame(height: 16)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isDraggingProgress = true
                                let x = value.location.x
                                let pct = max(0, min(1, x / totalWidth))
                                preview.seek(to: Double(pct) * preview.duration)
                            }
                            .onEnded { _ in
                                isDraggingProgress = false
                            }
                    )
                    .onHover { inside in
                        isHoveringProgress = inside
                        if inside {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }
                .frame(height: 16)
                .transition(.opacity)
                .padding(.top, 2)
                .padding(.horizontal, 14) // 缩进 14pt 避开卡片底边圆角遮挡和裁剪缺陷
            }
        }
    }

    // MARK: - 内联组件与业务逻辑

    @ViewBuilder
    private func metadataBadge(label: String, val: String?, diff: Bool, width: CGFloat) -> some View {
        let hasValue = val != nil && !val!.isEmpty && val != "—"
        let displayVal = hasValue ? val! : localizationManager.string("conflict.badge.none")
        
        HStack(spacing: 2) {
            Text("\(label):")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(hasValue ? .secondary : .secondary.opacity(0.5))
            Text(displayVal)
                .font(.system(size: 10))
                .foregroundColor(
                    hasValue 
                        ? (diff ? DesignSystem.Colors.warning : DesignSystem.Colors.textPrimary)
                        : DesignSystem.Colors.textTertiary.opacity(0.4)
                )
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(width: width, height: 18, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    hasValue
                        ? (diff ? DesignSystem.Colors.warning.opacity(0.12) : DesignSystem.Colors.backgroundSecondary)
                        : DesignSystem.Colors.backgroundSecondary.opacity(0.15)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(
                    hasValue
                        ? (diff ? DesignSystem.Colors.warning.opacity(0.3) : Color.clear)
                        : DesignSystem.Colors.border.opacity(0.4),
                    style: StrokeStyle(lineWidth: 0.5, lineCap: .round, lineJoin: .round, miterLimit: 0, dash: hasValue ? [] : [2, 2])
                )
        )
    }

    @ViewBuilder
    private func technicalBadge(label: String = "", val: String?, diff: Bool, width: CGFloat) -> some View {
        let hasValue = val != nil && !val!.isEmpty && val != "—"
        let displayVal = hasValue ? val! : "—"
        
        Text(displayVal)
            .font(.system(size: 10, design: .monospaced))
            .foregroundColor(
                hasValue 
                    ? (diff ? DesignSystem.Colors.warning : .secondary)
                    : DesignSystem.Colors.textTertiary.opacity(0.4)
            )
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .frame(width: width, height: 18, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(
                        hasValue
                            ? (diff ? DesignSystem.Colors.warning.opacity(0.08) : Color.clear)
                            : Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        hasValue
                            ? (diff ? DesignSystem.Colors.warning.opacity(0.2) : DesignSystem.Colors.border.opacity(0.5))
                            : DesignSystem.Colors.border.opacity(0.3),
                        style: StrokeStyle(lineWidth: 0.5, lineCap: .round, lineJoin: .round, miterLimit: 0, dash: hasValue ? [] : [2, 2])
                    )
            )
    }

    private func commitFileNameEdit() {
        let trimmed = editingFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            fileNameError = localizationManager.string("conflict.error.empty_filename")
            return
        }
        if trimmed.unicodeScalars.contains(where: { CharacterSet(charactersIn: "/:\\").contains($0) }) {
            fileNameError = localizationManager.string("conflict.error.illegal_chars")
            return
        }
        
        // 1. 内存中查重（大小写不敏感）
        let dup = allFiles.contains { o in
            guard o.id != file.id else { return false }
            let n = o.processingState == .awaitingConfirmation ? (o.suggestedFileName ?? o.fileName) : o.fileName
            return n.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
        if dup {
            fileNameError = localizationManager.string("conflict.error.conflict_in_group")
            return
        }
        
        // 2. 物理磁盘上查重（仅在修改了名字的前提下）
        if trimmed.localizedCaseInsensitiveCompare(file.fileName) != .orderedSame {
            let targetURL = file.filePath.deletingLastPathComponent().appendingPathComponent(trimmed)
            if FileManager.default.fileExists(atPath: targetURL.path) {
                let isTracked = allFiles.contains { o in
                    o.filePath.standardizedFileURL.path.decomposedStringWithCanonicalMapping == targetURL.standardizedFileURL.path.decomposedStringWithCanonicalMapping
                }
                if !isTracked {
                    fileNameError = localizationManager.string("conflict.error.conflict_in_group")
                    return
                }
            }
        }
        
        if let i = allFiles.firstIndex(where: { $0.id == file.id }) {
            allFiles[i].suggestedFileName = trimmed
            // 💡 关键：若被修改的不是“待确认”状态（即它是只读已有文件），升级其状态为 awaitsConfirmation，保证可以通过底层的 writeConflictFile
            if allFiles[i].processingState != .awaitingConfirmation {
                allFiles[i].processingState = .awaitingConfirmation
            }
        }
        
        fileNameError = nil
        if let updated = allFiles.first(where: { $0.id == file.id }) {
            preview.stop()
            onWriteAndKeep(updated)
        }
    }

    private var canDelete: Bool {
        if file.processingState == .processing {
            return false
        }
        guard let group = conflicts.first(where: { $0.memberIDs.contains(file.id) }) else {
            return false
        }
        let activeMemberCount = group.memberIDs.filter { id in
            allFiles.contains { $0.id == id }
        }.count
        return activeMemberCount > 1
    }

    private func rowBackground(isHovered: Bool) -> Color {
        if isHovered {
            return DesignSystem.Colors.backgroundTertiary.opacity(0.6)
        }
        if isCandidate {
            return DesignSystem.Colors.primary.opacity(0.04)
        } else {
            return DesignSystem.Colors.backgroundSecondary.opacity(0.4)
        }
    }
}

// MARK: - HoverIconButton

private struct HoverIconButton: View {
    let iconName: String
    let color: Color
    let hoverColor: Color
    var size: CGFloat = 13
    let tooltip: String?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: iconName)
                .font(.system(size: size, weight: .regular))
                .foregroundColor(isHovered ? hoverColor : color)
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xs)
                        .fill(isHovered ? DesignSystem.Colors.backgroundTertiary : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tooltip ?? "")
    }
}

// MARK: - 列数据模型

private struct ColumnData {
    let header: String
    let values: [String]
    let highlights: [Bool]
}
