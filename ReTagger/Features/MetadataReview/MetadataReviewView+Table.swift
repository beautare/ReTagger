//
//  MetadataReviewView+Table.swift
//  ReTagger
//
//  文件列表与详情面板相关视图
//

import SwiftUI
import AppKit

extension MetadataReviewView {
    // MARK: - File Table

    var tableContainer: some View {
        GeometryReader { proxy in
            let totalWidth = proxy.size.width
            let contentHeight = proxy.size.height
            let tableMinWidth = DesignSystem.Layout.reviewTableMinWidth
            let shouldUseInlineLayout = totalWidth >= DesignSystem.Layout.detailInlineBreakpoint

            Group {
                if isInlineLayout {
                    InlineDetailSplitView(
                        configuration: .init(
                            tableMinWidth: tableMinWidth,
                            detailMinWidth: DesignSystem.Layout.detailPanelMinWidth,
                            detailDefaultWidth: DesignSystem.Layout.detailPanelDefaultWidth,
                            dividerWidth: DesignSystem.Layout.detailPanelDragHandleWidth,
                            restoredDetailWidth: savedDetailWidth
                        ),
                        left: fileTable
                            .frame(height: contentHeight)
                            .layoutPriority(1),
                        right: metadataDetailPanel
                            .background(DesignSystem.Colors.backgroundSecondary)
                            .frame(maxHeight: .infinity),
                        onDetailWidthChanged: { width in
                            savedDetailWidth = width
                        }
                    )
                    .frame(width: totalWidth, height: contentHeight, alignment: .leading)
                    .transition(.opacity)
                } else {
                    let handleHeight = DesignSystem.Layout.detailPanelDragHandleWidth
                    let resolvedDetailHeight = clampStackedDetailPanelHeight(
                        stackedDetailPanelHeight,
                        totalHeight: contentHeight
                    )
                    let tableHeight = max(
                        contentHeight - resolvedDetailHeight - handleHeight,
                        DesignSystem.Layout.reviewTableStackedMinHeight
                    )

                    VStack(spacing: 0) {
                        fileTable
                            .frame(minWidth: tableMinWidth, maxWidth: .infinity)
                            .frame(height: tableHeight)
                            .layoutPriority(1)

                        stackedDetailResizeHandle(totalHeight: contentHeight)
                            .frame(height: handleHeight)

                        metadataDetailPanel
                            .frame(maxWidth: .infinity)
                            .frame(height: resolvedDetailHeight)
                            .background(DesignSystem.Colors.backgroundSecondary)
                    }
                    .frame(width: totalWidth, height: contentHeight, alignment: .topLeading)
                    .overlay(alignment: .topLeading) {
                        // 拖拽中的预览分隔线：仅此 overlay 随鼠标移动，面板高度在松手时才提交
                        if let previewHeight = stackedDetailDragPreviewHeight {
                            Rectangle()
                                .fill(DesignSystem.Colors.primary.opacity(0.6))
                                .frame(height: handleHeight)
                                .frame(maxWidth: .infinity)
                                .offset(y: max(contentHeight - previewHeight - handleHeight, 0))
                                .allowsHitTesting(false)
                        }
                    }
                    .transition(.opacity)
                    .onAppear {
                        stackedDetailDragStartHeight = nil
                        stackedDetailDragPreviewHeight = nil
                        stackedDetailPanelHeight = resolvedDetailHeight
                    }
                    .onChange(of: contentHeight) { newHeight in
                        stackedDetailPanelHeight = clampStackedDetailPanelHeight(
                            stackedDetailPanelHeight,
                            totalHeight: newHeight
                        )
                    }
                }
            }
            .frame(width: totalWidth, height: proxy.size.height, alignment: .topLeading)
            .animation(DesignSystem.Animation.normal, value: isInlineLayout)
            .onChange(of: shouldUseInlineLayout) { newValue in
                withAnimation(DesignSystem.Animation.normal) {
                    isInlineLayout = newValue
                }
            }
            .onAppear {
                isInlineLayout = shouldUseInlineLayout
            }
            .simultaneousGesture(
                TapGesture().onEnded {
                    playbackController.dismissQueuePanelIfNeeded()
                },
                including: .gesture
            )
        }
    }

    private func stackedDetailResizeHandle(totalHeight: CGFloat) -> some View {
        PaneResizeHandle(
            axis: .horizontal,
            onDrag: { deltaY in
                // deltaY 为屏幕坐标（向上为正）；分隔线上移 → 下方详情面板变高
                if stackedDetailDragStartHeight == nil {
                    stackedDetailDragStartHeight = stackedDetailPanelHeight
                }
                let startHeight = stackedDetailDragStartHeight ?? stackedDetailPanelHeight
                // 拖拽中仅更新预览线位置，不触发表格与详情面板的重布局
                stackedDetailDragPreviewHeight = clampStackedDetailPanelHeight(
                    startHeight + deltaY,
                    totalHeight: totalHeight
                )
            },
            onDragEnd: {
                if let previewHeight = stackedDetailDragPreviewHeight {
                    stackedDetailPanelHeight = previewHeight
                }
                stackedDetailDragPreviewHeight = nil
                stackedDetailDragStartHeight = nil
            },
            onDoubleTap: {
                stackedDetailDragStartHeight = nil
                stackedDetailPanelHeight = clampStackedDetailPanelHeight(
                    DesignSystem.Layout.detailPanelStackedMinHeight,
                    totalHeight: totalHeight
                )
            }
        )
        .frame(maxWidth: .infinity)
        .help(localizationManager.string("review.detail_resize_hint"))
    }

    private func clampStackedDetailPanelHeight(_ proposedHeight: CGFloat, totalHeight: CGFloat) -> CGFloat {
        let handleHeight = DesignSystem.Layout.detailPanelDragHandleWidth
        let minTableHeight = DesignSystem.Layout.reviewTableStackedMinHeight
        let available = max(totalHeight - minTableHeight - handleHeight, 0)

        let designMin = DesignSystem.Layout.detailPanelStackedMinHeight
        let lowerBound = min(designMin, available)
        let upperBound = max(lowerBound, available)
        let sanitized = max(0, proposedHeight)

        guard upperBound > lowerBound else {
            return lowerBound
        }

        return min(max(sanitized, lowerBound), upperBound)
    }

    var fileTable: some View {
        // 直接读取缓存的过滤结果，避免计算属性被重复求值
        let displayFilesBinding = Binding<[AudioMetadata]>(
            get: { cachedFilteredFiles },
            set: { _ in } // 只读，展示用途
        )
        
        return MetadataTableView(
            files: displayFilesBinding,
            selection: $tableSelection,
            sortOrder: $sortOrder,
            columnConfiguration: $columnConfiguration,
            scrollTo: $pendingScrollTarget,
            searchText: searchText,
            onDoubleAction: { metadata in
                handleDoubleTap(on: metadata)
            },
            onMenuAction: { action, selection in
                switch action {
                case .revealInFinder:
                    revealInFinder(selection: selection)
                case .copyPath:
                    copyPaths(selection: selection)
                case .moveToTrash:
                    prepareTrash(selection: selection)
                case .play:
                    playSelection(selection: selection)
                case .processAI:
                    processSelectionWithAI(selection: selection)
                case .applyCorrections:
                    applyCorrections(selection: selection)
                case .discardCorrections:
                    discardSelection(selection: selection)
                case .undoCorrections:
                    undoSelection(selection: selection)
                }
            },
            onColumnConfigurationChange: { newConfig in
                // 使用异步更新避免在视图更新期间修改状态
                DispatchQueue.main.async {
                    columnConfiguration = newConfig
                }
            },
            onConfirmAction: { metadata in
                confirmTrack(metadata)
            },
            onDiscardAction: { metadata in
                discardTrack(metadata)
            },
            onUndoAction: { metadata in
                undoTrack(metadata)
            },
            canUndo: { metadata in
                canUndo(metadata)
            },
            onEditAction: { metadata, column, newValue in
                handleInlineEdit(metadata: metadata, column: column, newValue: newValue)
            },
            onDropFiles: { urls in
                Task { @MainActor in
                    await coordinator.addDroppedFiles(urls)
                }
            },
            currentPlayingTrackID: playbackController.state.currentTrackID,
            fontScale: coordinator.settings.metadataTableFontScale
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .simultaneousGesture(
            TapGesture().onEnded {
                playbackController.dismissQueuePanelIfNeeded()
            }
        )
    }

    @ViewBuilder
    var metadataDetailPanel: some View {
        if selectedMetadatas.isEmpty {
            detailPlaceholder
        } else {
            ScrollView {
                detailPanelContent
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    private var detailPanelContent: some View {
        let selectionItems = selectedMetadatas
        if selectionItems.count > 1 {
            multiSelectionDetail(for: selectionItems)
        } else if let metadata = selectionItems.first ?? primarySelection {
            let fields = MetadataField.relevantFields(for: metadata)
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                detailHeader(for: metadata)
                Divider()
                detailFieldList(for: metadata, fields: fields)
                detailActions(for: metadata, hasEditableFields: !fields.isEmpty)
            }
            .padding(DesignSystem.Spacing.md)
        } else {
            detailPlaceholder
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    var orderedSelectionIDs: [AudioMetadata.ID] {
        tableSelection.sorted { lhs, rhs in
            guard let leftIndex = currentFiles.firstIndex(where: { $0.id == lhs }),
                  let rightIndex = currentFiles.firstIndex(where: { $0.id == rhs }) else {
                return false
            }
            return leftIndex < rightIndex
        }
    }

    var primarySelection: AudioMetadata? {
        guard let firstID = orderedSelectionIDs.first,
              let metadata = currentFiles.first(where: { $0.id == firstID }) else {
            return nil
        }
        return metadata
    }

    var selectedMetadatas: [AudioMetadata] {
        orderedSelectionIDs.compactMap { id in
            currentFiles.first(where: { $0.id == id })
        }
    }

    @ViewBuilder
    func detailHeader(for metadata: AudioMetadata) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(metadata.fileName)
                .font(DesignSystem.Typography.title3)
                .lineLimit(2)
                .truncationMode(.middle)
            HStack(spacing: DesignSystem.Spacing.xs) {
                StatusBadge(state: metadata.processingState)
            }
            if let notes = metadata.aiNotes,
               !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(notes)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
    }

    @ViewBuilder
    func multiSelectionDetail(for items: [AudioMetadata]) -> some View {
        let selectionIDs = Set(items.map(\.id))
        let summary = statusSummary(for: items)
        let previewItems = Array(items.prefix(5))
        let remainingCount = max(items.count - previewItems.count, 0)

        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxxs) {
                Text(localizationManager.string("table.selected_count", arguments: items.count))
                    .font(DesignSystem.Typography.title3)
                Text(localizationManager.string("table.batch_apply_hint"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            if !summary.isEmpty {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxxs) {
                    ForEach(summary, id: \.0) { entry in
                        HStack(spacing: DesignSystem.Spacing.xs) {
                            StatusBadge(state: entry.0)
                            Text(localizationManager.string("table.item_count", arguments: entry.1))
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textSecondary)
                        }
                    }
                }
            }

            if !previewItems.isEmpty {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxxs) {
                    Text(localizationManager.string("table.contains"))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                    ForEach(previewItems, id: \.id) { metadata in
                        Text("• \(metadata.fileName)")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                            .lineLimit(1)
                    }
                    if remainingCount > 0 {
                        Text(localizationManager.string("table.and_more", arguments: remainingCount))
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.textSecondary)
                    }
                }
            }

            multiSelectionActions(selection: selectionIDs)
        }
        .padding(DesignSystem.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func statusSummary(for items: [AudioMetadata]) -> [(AudioMetadata.ProcessingState, Int)] {
        let grouped = Dictionary(grouping: items, by: \.processingState)
        let orderedStates: [AudioMetadata.ProcessingState] = [
            .awaitingConfirmation,
            .processing,
            .pending,
            .completed,
            .userModified,
            .failed
        ]

        var summary: [(AudioMetadata.ProcessingState, Int)] = []
        for state in orderedStates {
            if let count = grouped[state]?.count {
                summary.append((state, count))
            }
        }

        let remainingStates = grouped.keys.filter { !orderedStates.contains($0) }
        for state in remainingStates {
            if let count = grouped[state]?.count {
                summary.append((state, count))
            }
        }

        return summary
    }

    @ViewBuilder
    func multiSelectionActions(selection: Set<AudioMetadata.ID>) -> some View {
        let selectedFiles = currentFiles.filter { selection.contains($0.id) }
        let processingCount = selectedFiles.filter { $0.processingState == .processing }.count
        let awaitingConfirmationCount = selectedFiles.filter { $0.processingState == .awaitingConfirmation }.count
        let canUndoCount = selectedFiles.filter { canUndo($0) }.count
        
        let canRunAI = !selectedFiles.isEmpty && processingCount == 0
        
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            
            // 1. 优先显示确认操作
            if awaitingConfirmationCount > 0 {
                Button {
                    applyCorrections(selection: selection)
                } label: {
                    Label(localizationManager.string("action.confirm_write") + " (\(awaitingConfirmationCount))", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.green)
                .disabled(isProcessing || isApplyingCorrections)
                
                Button {
                    discardSelection(selection: selection)
                } label: {
                    Label(localizationManager.string("action.discard") + " (\(awaitingConfirmationCount))", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isProcessing || isApplyingCorrections)
            }
            
            // 2. AI 打标签 (如果没有待确认项，则作为主要操作，否则作为次要操作)
            if canRunAI {
                if awaitingConfirmationCount == 0 {
                    Button {
                        processSelectionWithAI(selection: selection)
                    } label: {
                        Label(localizationManager.string("ai.tagging"), systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isProcessing || isApplyingCorrections)
                } else {
                    Button {
                        processSelectionWithAI(selection: selection)
                    } label: {
                        Label(localizationManager.string("ai.tagging"), systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(isProcessing || isApplyingCorrections)
                }
            }
            
            // 3. 撤回操作
            if canUndoCount > 0 {
                Button {
                    undoSelection(selection: selection)
                } label: {
                    Label(localizationManager.string("action.undo") + " (\(canUndoCount))", systemImage: "arrow.uturn.backward.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(.orange)
                .disabled(isProcessing || isApplyingCorrections)
            }
            
            if processingCount > 0 {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(localizationManager.string("table.files_processing", arguments: processingCount))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
            }
            
            Divider()
            
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: "info.circle")
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                Text(localizationManager.string("table.batch_skip_invalid"))
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        }
    }

    @ViewBuilder
    func detailFieldList(for metadata: AudioMetadata, fields: [MetadataField]) -> some View {
        if fields.isEmpty {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(localizationManager.string("table.no_corrections"))
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                    Toggle(isOn: selectAllBinding(for: metadata, fields: fields)) {
                        Text(localizationManager.string("table.select_all"))
                            .font(DesignSystem.Typography.subheadline)
                            .fontWeight(.semibold)
                    }
                    .toggleStyle(.checkbox)
                    .padding(.vertical, DesignSystem.Spacing.xxs)
                    ForEach(fields, id: \.self) { field in
                        fieldComparisonRow(
                            for: metadata,
                            field: field,
                            highlight: field.hasChange(in: metadata)
                        )
                    }
                }
                .padding(.trailing, DesignSystem.Spacing.xs)
            }
        }
    }

    func fieldComparisonRow(
        for metadata: AudioMetadata,
        field: MetadataField,
        highlight: Bool
    ) -> some View {
        Toggle(isOn: selectionBinding(for: metadata.id, field: field)) {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                Text(localizationManager.string(field.localizationKey))
                    .font(DesignSystem.Typography.footnote)
                    .fontWeight(.semibold)
                    .frame(minWidth: 56, alignment: .leading)
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxxs) {
                    Text(localizationManager.string("table.original", arguments: displayText(field.originalValue(for: metadata)) as NSString))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(localizationManager.string("table.ai_corrected", arguments: displayText(field.correctedValue(for: metadata)) as NSString))
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(highlight ? DesignSystem.Colors.primary : DesignSystem.Colors.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .toggleStyle(.checkbox)
        .padding(.vertical, DesignSystem.Spacing.xxxs)
    }

    func selectionBinding(
        for metadataID: AudioMetadata.ID,
        field: MetadataField
    ) -> Binding<Bool> {
        Binding(
            get: {
                fieldSelections[metadataID]?.contains(field) ?? false
            },
            set: { newValue in
                var selections = fieldSelections[metadataID] ?? []
                if newValue {
                    selections.insert(field)
                } else {
                    selections.remove(field)
                }
                fieldSelections[metadataID] = selections
            }
        )
    }

    func displayText(_ value: String?) -> String {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return "—"
        }
        return trimmed
    }

    func areAllFieldsSelected(for metadata: AudioMetadata, fields: [MetadataField]) -> Bool {
        guard !fields.isEmpty else { return true }
        let available = Set(fields)
        let selections = fieldSelections[metadata.id] ?? available
        return available.isSubset(of: selections)
    }

    func selectAllBinding(
        for metadata: AudioMetadata,
        fields: [MetadataField]
    ) -> Binding<Bool> {
        Binding(
            get: {
                areAllFieldsSelected(for: metadata, fields: fields)
            },
            set: { newValue in
                toggleFieldSelection(for: metadata, fields: fields, selectAll: newValue)
            }
        )
    }

    func toggleFieldSelection(
        for metadata: AudioMetadata,
        fields: [MetadataField],
        selectAll: Bool
    ) {
        let available = Set(fields)
        if selectAll {
            fieldSelections[metadata.id] = available
        } else {
            fieldSelections[metadata.id] = Set<MetadataField>()
        }
    }

    func detailActions(
        for metadata: AudioMetadata,
        hasEditableFields: Bool
    ) -> some View {
        let selection = Set([metadata.id])
        
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            switch metadata.processingState {
            case .pending, .failed:
                // 未处理或失败状态：主要操作是 AI 打标签
                Button {
                    processSelectionWithAI(selection: selection)
                } label: {
                    Label(localizationManager.string("ai.tagging"), systemImage: "wand.and.stars")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isProcessing || isApplyingCorrections)
                
            case .processing:
                // 处理中状态
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(localizationManager.string("state.processing"))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(8)
                
            case .awaitingConfirmation:
                // 待确认状态：确认或放弃
                VStack(spacing: DesignSystem.Spacing.sm) {
                    Button {
                        confirmTrack(metadata)
                    } label: {
                        Label(localizationManager.string("action.confirm_write"), systemImage: "checkmark.circle")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.green)
                    .disabled(!hasEditableFields || !canConfirm(metadata))
                    
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        Button {
                            discardTrack(metadata)
                        } label: {
                            Label(localizationManager.string("action.discard"), systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        
                        Button {
                            processSelectionWithAI(selection: selection)
                        } label: {
                            Label(localizationManager.string("action.retry_ai"), systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                    }
                }
                .disabled(isProcessing || isApplyingCorrections)
                
            case .completed, .userModified:
                // 已完成状态：撤回或重新处理
                VStack(spacing: DesignSystem.Spacing.sm) {
                    if canUndo(metadata) {
                        Button {
                            undoTrack(metadata)
                        } label: {
                            Label(localizationManager.string("action.undo"), systemImage: "arrow.uturn.backward.circle")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.orange)
                    }
                    
                    Button {
                        processSelectionWithAI(selection: selection)
                    } label: {
                        Label(localizationManager.string("action.reprocess_ai"), systemImage: "wand.and.stars")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                .disabled(isProcessing || isApplyingCorrections)
            }

            if let record = coordinator.undoRecords[metadata.id] {
                HStack {
                    Image(systemName: "clock")
                    Text(localizationManager.string("table.confirmed_recently", arguments: formattedRelative(date: record.confirmedAt)))
                }
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, DesignSystem.Spacing.xs)
            }
        }
    }

    func formattedRelative(date: Date) -> String {
        MetadataReviewView.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    var detailPlaceholder: some View {
        VStack(alignment: .center, spacing: DesignSystem.Spacing.md) {
            Image(systemName: "rectangle.and.hand.point.up.left")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text(localizationManager.string("table.select_track_hint"))
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

extension MetadataReviewView {
    @ViewBuilder
    func fileNameCell(_ metadata: AudioMetadata) -> some View {
        HStack {
            Image(systemName: "music.note")
                .foregroundColor(.blue)
            Text(metadata.fileName)
                .font(.system(.body, design: .monospaced))
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    func titleCell(_ metadata: AudioMetadata) -> some View {
        Text(metadata.originalTitle ?? "—")
            .foregroundColor(metadata.originalTitle == nil ? .red : .primary)
    }

    @ViewBuilder
    func artistCell(_ metadata: AudioMetadata) -> some View {
        Text(metadata.originalArtist ?? "—")
            .foregroundColor(metadata.originalArtist == nil ? .red : .primary)
    }

    @ViewBuilder
    func albumCell(_ metadata: AudioMetadata) -> some View {
        Text(metadata.originalAlbum ?? "—")
            .foregroundColor(metadata.originalAlbum == nil ? .orange : .primary)
    }

    @ViewBuilder
    func genreCell(_ metadata: AudioMetadata) -> some View {
        Text(metadata.originalGenre ?? "—")
            .foregroundColor(metadata.originalGenre == nil ? .orange : .primary)
    }

    @ViewBuilder
    func yearCell(_ metadata: AudioMetadata) -> some View {
        Text(metadata.originalYear ?? "—")
            .foregroundColor(metadata.originalYear == nil ? .orange : .primary)
    }

    @ViewBuilder
    func durationCell(_ metadata: AudioMetadata) -> some View {
        Text(metadata.durationDisplay)
    }

    @ViewBuilder
    func statusCell(_ metadata: AudioMetadata) -> some View {
        StatusBadge(state: metadata.processingState)
    }

    @ViewBuilder
    func fileSizeCell(_ metadata: AudioMetadata) -> some View {
        Text(metadata.fileSizeDisplay)
            .font(.system(.body, design: .monospaced))
    }

    @ViewBuilder
    func bitrateCell(_ metadata: AudioMetadata) -> some View {
        Text(metadata.bitrateDisplay)
    }

    @ViewBuilder
    func sampleRateCell(_ metadata: AudioMetadata) -> some View {
        Text(metadata.sampleRateDisplay)
    }

    @ViewBuilder
    func formatCell(_ metadata: AudioMetadata) -> some View {
        Text(metadata.formatDisplay)
    }

    @ViewBuilder
    func creationDateCell(_ metadata: AudioMetadata) -> some View {
        Text(metadata.creationDateDisplay)
            .font(.caption)
    }

    @ViewBuilder
    func modificationDateCell(_ metadata: AudioMetadata) -> some View {
        Text(metadata.modificationDateDisplay)
            .font(.caption)
    }
    
    // MARK: - 内联编辑
    
    /// 处理内联编辑提交
    /// - Parameters:
    ///   - metadata: 被编辑的曲目
    ///   - column: 被编辑的列
    ///   - newValue: 新值
    func handleInlineEdit(metadata: AudioMetadata, column: MetadataColumn, newValue: String) {
        guard let index = currentFiles.firstIndex(where: { $0.id == metadata.id }) else { return }
        
        var updated = currentFiles[index]
        let trimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalValue: String?
        
        // 获取原始值并更新对应字段
        switch column {
        case .title:
            originalValue = updated.originalTitle
            updated.originalTitle = trimmedValue.isEmpty ? nil : trimmedValue
        case .artist:
            originalValue = updated.originalArtist
            updated.originalArtist = trimmedValue.isEmpty ? nil : trimmedValue
        case .album:
            originalValue = updated.originalAlbum
            updated.originalAlbum = trimmedValue.isEmpty ? nil : trimmedValue
        case .genre:
            originalValue = updated.originalGenre
            updated.originalGenre = trimmedValue.isEmpty ? nil : trimmedValue
        case .year:
            originalValue = updated.originalYear
            updated.originalYear = trimmedValue.isEmpty ? nil : trimmedValue
        default:
            return // 不支持编辑的列
        }
        
        // 如果值没有变化，不需要写入
        let newValueNormalized = trimmedValue.isEmpty ? nil : trimmedValue
        if originalValue == newValueNormalized {
            return
        }
        
        // 立即更新 UI 显示为"正在处理"
        updated.processingState = .processing
        currentFiles[index] = updated
        coordinator.audioFiles = currentFiles
        
        // 异步写入文件
        // 异步写入文件
        Task {
            await performInlineWrite(updated: updated, originalValue: originalValue, column: column)
        }
    }
    
    private func performInlineWrite(updated: AudioMetadata, originalValue: String?, column: MetadataColumn) async {
         do {
             // 直接写入元数据到文件
             try await coordinator.metadataService.writeMetadata(updated, to: updated.filePath)
             
             await MainActor.run {
                 // 写入成功，更新状态为已完成
                 if let idx = currentFiles.firstIndex(where: { $0.id == updated.id }) {
                     currentFiles[idx] = updated
                     currentFiles[idx].processingState = .completed
                     coordinator.audioFiles = currentFiles
                 }
             }
         } catch {
             await MainActor.run {
                 // 写入失败，恢复原值并标记错误
                 if let idx = currentFiles.firstIndex(where: { $0.id == updated.id }) {
                     // 恢复原值
                     switch column {
                     case .title:
                         currentFiles[idx].originalTitle = originalValue
                     case .artist:
                         currentFiles[idx].originalArtist = originalValue
                     case .album:
                         currentFiles[idx].originalAlbum = originalValue
                     case .genre:
                         currentFiles[idx].originalGenre = originalValue
                     case .year:
                         currentFiles[idx].originalYear = originalValue
                     default:
                         break
                     }
                     currentFiles[idx].processingState = .failed
                     currentFiles[idx].error = error.localizedDescription
                     coordinator.audioFiles = currentFiles
                 }
                 coordinator.setError(
                     localizationManager.string("error.write.failed_generic", arguments: error.localizedDescription as NSString)
                 )
             }
         }
    }
}

