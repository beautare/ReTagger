//
//  MetadataTableView.swift
//  ReTagger
//
//  Created by Claude Code
//

import SwiftUI
import AppKit
import QuartzCore

struct MetadataTableView: NSViewControllerRepresentable {
    @Binding var files: [AudioMetadata]
    @Binding var selection: Set<AudioMetadata.ID>
    @Binding var sortOrder: [KeyPathComparator<AudioMetadata>]
    @Binding var columnConfiguration: TableColumnConfiguration
    @Binding var scrollTo: AudioMetadata.ID?
    var searchText: String // New property
    
    // Inject LocalizationManager
    @EnvironmentObject var localizationManager: LocalizationManager
    
    let onDoubleAction: (AudioMetadata) -> Void
    let onMenuAction: (MetadataTableView.MenuAction, Set<AudioMetadata.ID>) -> Void
    let onColumnConfigurationChange: (TableColumnConfiguration) -> Void
    
    // New closures for status column actions
    var onConfirmAction: ((AudioMetadata) -> Void)?
    var onDiscardAction: ((AudioMetadata) -> Void)?
    var onUndoAction: ((AudioMetadata) -> Void)?
    var canUndo: ((AudioMetadata) -> Bool)?
    
    /// 内联编辑回调：(metadata, column, newValue)
    var onEditAction: ((AudioMetadata, MetadataColumn, String) -> Void)?
    
    /// 外部拖放文件回调
    var onDropFiles: (([URL]) -> Void)?
    
    /// 当前正在播放的曲目 ID，用于行视觉高亮
    var currentPlayingTrackID: AudioMetadata.ID?

    /// 表格正文文字大小档位（Cmd+/Cmd-/Cmd0 与设置页共用）
    var fontScale: MetadataTableFontScale = .medium

    enum MenuAction {
        case revealInFinder
        case copyPath
        case moveToTrash
        case play
        case processAI
        case applyCorrections
        case discardCorrections
        case undoCorrections
    }
    
    func makeNSViewController(context: Context) -> MetadataTableViewController {
        let controller = MetadataTableViewController()
        controller.localizationManager = localizationManager
        controller.onDoubleAction = onDoubleAction
        controller.onMenuAction = onMenuAction
        controller.onColumnConfigurationChange = onColumnConfigurationChange
        controller.onConfirmAction = onConfirmAction
        controller.onDiscardAction = onDiscardAction
        controller.onUndoAction = onUndoAction
        controller.canUndo = canUndo
        controller.onEditAction = onEditAction
        controller.onDropFiles = onDropFiles
        controller.currentSearchText = searchText
        controller.fontScale = fontScale
        return controller
    }

    func updateNSViewController(_ nsViewController: MetadataTableViewController, context: Context) {
        // Update localization manager
        nsViewController.localizationManager = localizationManager

        // Explicitly check if language changed to force column update
        if nsViewController.currentLanguage != localizationManager.language {
            nsViewController.updateLanguage(localizationManager.language)
        }

        // 文字大小档位变化时强制整表重刷，确保行高随字号重新计算
        if nsViewController.fontScale != fontScale {
            nsViewController.fontScale = fontScale
            nsViewController.reloadAllRows()
        }

        // Update closures in case they capture new state
        nsViewController.onConfirmAction = onConfirmAction
        nsViewController.onDiscardAction = onDiscardAction
        nsViewController.onUndoAction = onUndoAction
        nsViewController.canUndo = canUndo
        nsViewController.onEditAction = onEditAction
        nsViewController.onDropFiles = onDropFiles
        
        nsViewController.update(
            files: files,
            selection: selection,
            sortOrder: sortOrder,
            columnConfiguration: columnConfiguration,
            scrollTo: scrollTo,
            searchText: searchText,
            currentPlayingTrackID: currentPlayingTrackID
        )
        
        // Bind selection back to SwiftUI
        nsViewController.onSelectionChange = { newSelection in
            DispatchQueue.main.async {
                self.selection = newSelection
            }
        }
        
        nsViewController.onSortOrderChange = { newOrder in
            DispatchQueue.main.async {
                self.sortOrder = newOrder
            }
        }
        
        // Reset scroll binding after scrolling
        nsViewController.onDidScroll = {
            DispatchQueue.main.async {
                self.scrollTo = nil
            }
        }
    }
}

class MetadataReviewTableView: NSTableView {
    override func drawBackground(inClipRect dirtyRect: NSRect) {
        self.backgroundColor.set()
        dirtyRect.fill()
    }

    /// Esc 清空当前行选择。走响应链而非 SwiftUI 快捷键：
    /// 单元格编辑/搜索框聚焦时字段编辑器会先消费 Esc（取消编辑），互不抢占
    override func cancelOperation(_ sender: Any?) {
        guard !selectedRowIndexes.isEmpty else { return }
        deselectAll(nil)
    }
}

final class MetadataTableViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource, CustomTableHeaderViewDelegate {
    private let scrollView = NSScrollView()
    private let tableView = MetadataReviewTableView()
    
    var localizationManager: LocalizationManager?
    var currentLanguage: AppLanguage?
    var fontScale: MetadataTableFontScale = .medium

    var files: [AudioMetadata] = []
    var selection: Set<AudioMetadata.ID> = []
    var sortOrder: [KeyPathComparator<AudioMetadata>] = []
    var columnConfiguration: TableColumnConfiguration = .default
    var currentSearchText: String = ""
    /// 当前正在播放的曲目 ID，用于行视觉高亮
    var currentPlayingTrackID: AudioMetadata.ID?
    
    var onDoubleAction: ((AudioMetadata) -> Void)?
    var onMenuAction: ((MetadataTableView.MenuAction, Set<AudioMetadata.ID>) -> Void)?
    var onSelectionChange: ((Set<AudioMetadata.ID>) -> Void)?
    var onSortOrderChange: (([KeyPathComparator<AudioMetadata>]) -> Void)?
    var onColumnConfigurationChange: ((TableColumnConfiguration) -> Void)?
    var onDidScroll: (() -> Void)?
    
    // New actions
    var onConfirmAction: ((AudioMetadata) -> Void)?
    var onDiscardAction: ((AudioMetadata) -> Void)?
    var onUndoAction: ((AudioMetadata) -> Void)?
    var canUndo: ((AudioMetadata) -> Bool)?
    
    /// 内联编辑回调：(metadata, column, newValue)
    var onEditAction: ((AudioMetadata, MetadataColumn, String) -> Void)?
    
    /// 外部拖放文件回调
    var onDropFiles: (([URL]) -> Void)?
    
    /// 可编辑的列
    private let editableColumns: Set<MetadataColumn> = [.title, .artist, .album, .genre, .year]
    
    private var tableHeaderMenuDelegate: TableHeaderMenuDelegate?
    private var isResizingColumn: Bool = false  // Flag to prevent width reset during resize
    private weak var currentEditingCell: MetadataTableCellView?
    
    func updateLanguage(_ newLanguage: AppLanguage) {
        self.currentLanguage = newLanguage
        updateColumns()
    }

    /// 字号档位变化后整表重刷：usesAutomaticRowHeights 会据此重新计算每行高度
    func reloadAllRows() {
        tableView.reloadData()
        adjustStatusColumnWidth()
        // reloadData() 不会同步触发 automaticRowHeights 的布局与重绘，
        // 快捷键触发的刷新不经过表格自身的事件追踪循环，视觉上会一直空白到下次滚动才刷新
        tableView.layoutSubtreeIfNeeded()
    }
    
    override func loadView() {
        self.view = scrollView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        setupTableView()
    }
    
    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.style = .inset
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.wantsLayer = true
        
        // Dynamic row height support
        tableView.usesAutomaticRowHeights = true
        
        // Double action
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleAction)
        
        // Menu
        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu
        
        // 注册外部拖放支持（接受文件 URL）
        tableView.registerForDraggedTypes([.fileURL])
        
        // Custom Header View for Double-Click Resize
        let headerView = CustomTableHeaderView()
        headerView.customDelegate = self
        tableView.headerView = headerView
        
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        
        // Ensure columns are up to date with current configuration
        updateColumns()
        
        // Initial reload to display data if update() was called before viewDidLoad
        tableView.reloadData()
    }
    
    func update(
        files: [AudioMetadata],
        selection: Set<AudioMetadata.ID>,
        sortOrder: [KeyPathComparator<AudioMetadata>],
        columnConfiguration: TableColumnConfiguration,
        scrollTo: AudioMetadata.ID?,
        searchText: String,
        currentPlayingTrackID: AudioMetadata.ID? = nil
    ) {
        // Check if search text changed
        let isSearchChanged = searchText != self.currentSearchText
        self.currentSearchText = searchText
        
        // 检测播放状态是否变化
        let playingTrackChanged = self.currentPlayingTrackID != currentPlayingTrackID
        self.currentPlayingTrackID = currentPlayingTrackID

        // 检测是否有新增/删除/重排行
        let oldIDs = self.files.map(\.id)
        let newIDs = files.map(\.id)
        let idsChanged = oldIDs != newIDs
        let selectionChanged = self.selection != selection
        let configChanged = self.columnConfiguration != columnConfiguration
        
        let isReorderedOnly = idsChanged && self.files.count == files.count && Set(oldIDs) == Set(newIDs)
        let isMassiveChange = abs(self.files.count - files.count) > 500
        
        // 仅当行数一致且顺序未变时，才尝试按行增量刷新
        let changedRows: IndexSet? = (!idsChanged && !configChanged)
            ? differingRows(old: self.files, new: files)
            : nil
        
        let diff = (idsChanged && !isReorderedOnly && !isMassiveChange) ? files.difference(from: self.files) { $0.id == $1.id } : nil
        
        self.files = files
        self.selection = selection
        self.sortOrder = sortOrder
        self.columnConfiguration = columnConfiguration
        
        if configChanged {
            updateColumns()
        }
        
        if configChanged || (idsChanged && diff == nil) {
            // Fallback for massive changes, reorders, or config changes
            tableView.reloadData()
            adjustStatusColumnWidth()
            if isSearchChanged {
                tableView.scrollRowToVisible(0)
            }
            DispatchQueue.main.async { [weak self] in
                self?.updateProcessingRows()
            }
        } else if let diff = diff, idsChanged {
            // Use native table view updates for additions/removals
            // This natively preserves scroll positions without buggy manual anchor restoration
            tableView.beginUpdates()
            for change in diff {
                switch change {
                case .insert(let offset, _, _):
                    tableView.insertRows(at: IndexSet(integer: offset), withAnimation: [])
                case .remove(let offset, _, _):
                    tableView.removeRows(at: IndexSet(integer: offset), withAnimation: [])
                }
            }
            tableView.endUpdates()
            adjustStatusColumnWidth()
            updateProcessingRows()
        } else if let changedRows, !changedRows.isEmpty {
            let allColumns = IndexSet(integersIn: 0..<tableView.numberOfColumns)
            if !allColumns.isEmpty {
                tableView.reloadData(forRowIndexes: changedRows, columnIndexes: allColumns)
            } else {
                tableView.reloadData()
            }
            adjustStatusColumnWidth()
            updateProcessingRows(rows: changedRows)
        }
        
        // 播放曲目变化时刷新相关行的播放状态指示
        if playingTrackChanged && !idsChanged {
            updateProcessingRows()
        }
        
        if selectionChanged {
            syncSelectionToTable()
        }

        syncSortDescriptorsToTable()

        if let scrollToId = scrollTo, let index = files.firstIndex(where: { $0.id == scrollToId }) {
            tableView.scrollRowToVisible(index)
            onDidScroll?()
        }
    }

    /// 将 SwiftUI 侧的排序状态同步到表头（启动恢复排序偏好时补齐排序箭头，
    /// 并保证首次点击列头时从当前方向继续而非从升序重来）
    private var isSyncingSortDescriptors = false

    private func syncSortDescriptorsToTable() {
        let desired: [NSSortDescriptor] = sortOrder.compactMap { comparator in
            guard let column = MetadataColumn.allCases.first(where: {
                self.comparator(for: $0, ascending: true)?.keyPath == comparator.keyPath
            }) else { return nil }
            return NSSortDescriptor(key: column.rawValue, ascending: comparator.order == .forward)
        }
        guard !desired.isEmpty else { return }

        let current = tableView.sortDescriptors
        let matches = current.count == desired.count && zip(current, desired).allSatisfy {
            $0.key == $1.key && $0.ascending == $1.ascending
        }
        guard !matches else { return }

        isSyncingSortDescriptors = true
        tableView.sortDescriptors = desired
        isSyncingSortDescriptors = false
    }

    /// 找出内容有变化且无需全量刷新的行索引
    private func differingRows(old: [AudioMetadata], new: [AudioMetadata]) -> IndexSet {
        var indices = IndexSet()
        let count = min(old.count, new.count)
        for index in 0..<count {
            if old[index].id != new[index].id { continue }
            if hasDisplayImpactChange(old: old[index], new: new[index]) {
                indices.insert(index)
            }
        }
        return indices
    }

    /// 判断单行数据变化是否影响表格展示（文本/状态/时长等）
    private func hasDisplayImpactChange(old: AudioMetadata, new: AudioMetadata) -> Bool {
        return old.processingState != new.processingState ||
            old.fileName != new.fileName ||
            old.originalTitle != new.originalTitle ||
            old.correctedTitle != new.correctedTitle ||
            old.originalArtist != new.originalArtist ||
            old.correctedArtist != new.correctedArtist ||
            old.originalAlbum != new.originalAlbum ||
            old.correctedAlbum != new.correctedAlbum ||
            old.originalGenre != new.originalGenre ||
            old.correctedGenre != new.correctedGenre ||
            old.originalYear != new.originalYear ||
            old.correctedYear != new.correctedYear ||
            old.suggestedFileName != new.suggestedFileName ||
            old.suggestedFolderPath != new.suggestedFolderPath ||
            old.fileSizeBytes != new.fileSizeBytes ||
            old.duration != new.duration ||
            old.bitrate != new.bitrate ||
            old.sampleRate != new.sampleRate ||
            old.format != new.format ||
            old.fileCreationDate != new.fileCreationDate ||
            old.fileModificationDate != new.fileModificationDate ||
            old.aiNotes != new.aiNotes ||
            old.error != new.error ||
            old.confidence != new.confidence
    }

    private func configure(rowView: ProcessingRowView, for row: Int) {
        guard row >= 0, row < files.count else {
            rowView.isProcessing = false
            rowView.isRowSelected = false
            rowView.isDroppedFile = false
            rowView.isNowPlaying = false
            return
        }
        rowView.isProcessing = files[row].processingState == .processing
        rowView.isRowSelected = tableView.selectedRowIndexes.contains(row)
        rowView.isDroppedFile = files[row].importSource == .dropped
        rowView.isNowPlaying = (currentPlayingTrackID != nil && files[row].id == currentPlayingTrackID)
    }

    private func updateProcessingRows(rows: IndexSet? = nil) {
        let targetRows: IndexSet
        if let rows {
            targetRows = rows
        } else {
            let visibleRange = tableView.rows(in: tableView.visibleRect)
            if visibleRange.location == NSNotFound {
                targetRows = []
            } else {
                targetRows = IndexSet(integersIn: visibleRange.location ..< (visibleRange.location + visibleRange.length))
            }
        }
        for row in targetRows {
            if let rowView = tableView.rowView(atRow: row, makeIfNecessary: false) as? ProcessingRowView {
                configure(rowView: rowView, for: row)
            }
        }
    }
    
    private func adjustStatusColumnWidth() {
        guard let statusColumn = tableView.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(MetadataColumn.status.rawValue)) else {
            return
        }
        
        // Determine required width based on content
        // Standard width for text-only states
        let standardWidth: CGFloat = 100
        // Wider width for states with buttons (Confirm/Undo)
        // Icon(14) + Spacing(6) + Text(~40) + Spacing(6) + Button(~70) + Padding(12) ≈ 148
        // For Awaiting Confirmation, we have vertical buttons, so width might not need to be huge, but height will increase.
        // However, let's keep it wide enough for the buttons.
        let actionWidth: CGFloat = 120
        
        let hasActions = files.contains { file in
            file.processingState == .awaitingConfirmation ||
            (file.processingState == .completed && (canUndo?(file) ?? false))
        }
        
        let targetMinWidth = hasActions ? actionWidth : standardWidth
        
        // Only expand, never shrink automatically to avoid hiding content user might want to see
        // or fighting with user's manual resizing if they want it wide.
        // But if the user asked for "auto adjustment", maybe we should ensure it fits.
        // Strategy: If current width is less than target, expand it.
        
        if statusColumn.width < targetMinWidth {
            // NSTableColumn is not directly animatable via .animator()
            // We set the width directly. The TableView will handle the layout update.
            statusColumn.width = targetMinWidth
            
            // Update configuration to persist the new width
            columnConfiguration.updateWidth(targetMinWidth, for: .status)
            onColumnConfigurationChange?(columnConfiguration)
        }
    }
    
    private func updateColumns() {
        let newMetadataColumns = columnConfiguration.orderedVisibleColumns()
        guard let loc = localizationManager else { return }

        // 1. Remove columns that are no longer visible
        let newColumnIdentifiers = Set(newMetadataColumns.map(\.rawValue))
        let columnsToRemove = tableView.tableColumns.filter {
            !newColumnIdentifiers.contains($0.identifier.rawValue)
        }
        
        for column in columnsToRemove {
            tableView.removeTableColumn(column)
        }
        
        // 2. Add missing columns and update existing ones
        for (index, metadataColumn) in newMetadataColumns.enumerated() {
            let identifier = NSUserInterfaceItemIdentifier(metadataColumn.rawValue)
            // Use localization key for title
            let title = loc.string(metadataColumn.localizationKey)
            
            let column: NSTableColumn
            if let existing = tableView.tableColumn(withIdentifier: identifier) {
                column = existing
                // Always update title in case language changed
                if column.title != title {
                    column.title = title
                }
            } else {
                column = NSTableColumn(identifier: identifier)
                column.title = title
                column.minWidth = metadataColumn.minWidth
                column.sortDescriptorPrototype = NSSortDescriptor(key: metadataColumn.rawValue, ascending: true)
                // Set initial width
                if let storedWidth = columnConfiguration.width(for: metadataColumn) {
                    column.width = storedWidth
                } else {
                    column.width = max(metadataColumn.minWidth, 100)
                }
                tableView.addTableColumn(column)
            }
            
            // Update width if significantly different (prevents fighting with live resize)
            // Skip if user is actively resizing a column
            if !isResizingColumn, let storedWidth = columnConfiguration.width(for: metadataColumn) {
                if abs(column.width - storedWidth) > 2.0 {
                    column.width = storedWidth
                }
            }
            
            // Ensure correct order
            // Note: We must fetch the current index *after* potential moves/adds in previous iterations
            if let currentIndex = tableView.tableColumns.firstIndex(of: column), currentIndex != index {
                tableView.moveColumn(currentIndex, toColumn: index)
            }
        }
        
        // Setup header menu delegate if needed
        if tableHeaderMenuDelegate == nil, let headerView = tableView.headerView {
            let delegate = TableHeaderMenuDelegate(
                tableView: tableView,
                headerView: headerView,
                columnDescriptors: MetadataColumnRegistry.descriptors,
                localizationManager: loc,
                configurationProvider: { [weak self] in self?.columnConfiguration ?? .default },
                onConfigurationChange: { [weak self] newConfig in
                    self?.onColumnConfigurationChange?(newConfig)
                }
            )
            self.tableHeaderMenuDelegate = delegate
            headerView.menu = NSMenu()
            headerView.menu?.delegate = delegate
        }
    }
    
    private func syncSelectionToTable() {
        let indices = NSMutableIndexSet()
        for (index, file) in files.enumerated() {
            if selection.contains(file.id) {
                indices.add(index)
            }
        }
        
        if tableView.selectedRowIndexes != indices as IndexSet {
            tableView.selectRowIndexes(indices as IndexSet, byExtendingSelection: false)
        }
    }
    
    @objc private func handleDoubleAction() {
        let clickedRow = tableView.clickedRow
        let clickedColumn = tableView.clickedColumn
        guard clickedRow >= 0, clickedRow < files.count else { return }
        
        // 优先检查是否双击了可编辑列单元格，若是则直接进入编辑模式
        if clickedColumn >= 0, clickedColumn < tableView.tableColumns.count {
            let columnId = tableView.tableColumns[clickedColumn].identifier.rawValue
            if let column = MetadataColumn(rawValue: columnId), editableColumns.contains(column) {
                if let cellView = tableView.view(atColumn: clickedColumn, row: clickedRow, makeIfNecessary: false) as? MetadataTableCellView {
                    beginCellEditing(cellView: cellView, row: clickedRow, column: column)
                    return
                }
            }
        }
        
        // 默认行为：播放
        onDoubleAction?(files[clickedRow])
    }
    
    private func beginCellEditing(cellView: MetadataTableCellView, row: Int, column: MetadataColumn) {
        guard row >= 0, row < files.count else { return }

        // 如果有正在编辑的单元格，先结束编辑
        currentEditingCell?.endEditing(commit: true)

        let metadata = files[row]
        currentEditingCell = cellView
        
        // 设置编辑回调
        cellView.onEditCommit = { [weak self] newValue in
            guard let self = self else { return }
            self.currentEditingCell = nil
            self.onEditAction?(metadata, column, newValue)
        }
        cellView.onEditCancel = { [weak self] in
            self?.currentEditingCell = nil
        }
        
        // 开始编辑
        cellView.beginEditing()
    }
    
    // MARK: - NSTableViewDataSource
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return files.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0, row < files.count, let identifier = tableColumn?.identifier else { return nil }
        let file = files[row]
        let cellIdentifier = NSUserInterfaceItemIdentifier(rawValue: identifier.rawValue)
        
        // Special handling for Status column
        if identifier.rawValue == MetadataColumn.status.rawValue {
            var view = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? MetadataStatusCellView
            if view == nil {
                view = MetadataStatusCellView()
                view?.identifier = cellIdentifier
            }
            
            let isUndoable = canUndo?(file) ?? false
            // 点击时按 ID 重查最新数据：闭包捕获的 file 是配置单元格时的快照，
            // 状态可能已被其他入口（详情面板、批量操作）更新
            let fileID = file.id
            view?.configure(
                metadata: file,
                localizationManager: localizationManager,
                isUndoable: isUndoable,
                fontSize: scaledBodyFontSize,
                onConfirm: { [weak self] in
                    guard let self, let current = self.files.first(where: { $0.id == fileID }) else { return }
                    self.onConfirmAction?(current)
                },
                onDiscard: { [weak self] in
                    guard let self, let current = self.files.first(where: { $0.id == fileID }) else { return }
                    self.onDiscardAction?(current)
                },
                onUndo: { [weak self] in
                    guard let self, let current = self.files.first(where: { $0.id == fileID }) else { return }
                    self.onUndoAction?(current)
                }
            )
            return view
        }
        
        // Standard columns
        var view = tableView.makeView(withIdentifier: cellIdentifier, owner: self) as? MetadataTableCellView
        if view == nil {
            view = MetadataTableCellView()
            view?.identifier = cellIdentifier
        }
        
        if let column = MetadataColumn(rawValue: identifier.rawValue) {
            let content = makeCellContent(for: column, file: file)
            view?.configure(with: content)
            
            // 为可编辑列配置编辑按钮回调
            if editableColumns.contains(column) {
                view?.editButtonToolTip = localizationManager?.string("table.edit_tooltip")
                view?.onEditButtonClicked = { [weak self] cellView in
                    guard let self else { return }
                    // 行号必须在点击时现算：增量插入/删除行后，
                    // 配置单元格时捕获的行号已失效，会编辑到错误的文件
                    let currentRow = self.tableView.row(for: cellView)
                    guard currentRow >= 0, currentRow < self.files.count else { return }
                    self.beginCellEditing(cellView: cellView, row: currentRow, column: column)
                }
            } else {
                view?.onEditButtonClicked = nil
            }
        }
        
        return view
    }
    
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        // 程序化同步表头箭头时不回传，避免与 SwiftUI 侧排序状态互相触发
        guard !isSyncingSortDescriptors else { return }
        let newComparators: [KeyPathComparator<AudioMetadata>] = tableView.sortDescriptors.compactMap { descriptor in
            guard
                let key = descriptor.key,
                let column = MetadataColumn(rawValue: key)
            else {
                return nil
            }
            return comparator(for: column, ascending: descriptor.ascending)
        }
        
        guard !newComparators.isEmpty else { return }
        sortOrder = newComparators
        onSortOrderChange?(newComparators)
    }
    
    // MARK: - NSTableViewDelegate
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        // Use automatic height
        return -1 // -1 triggers automatic height calculation in modern macOS
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let identifier = NSUserInterfaceItemIdentifier("ProcessingRowView")
        let rowView: ProcessingRowView
        if let existing = tableView.makeView(withIdentifier: identifier, owner: self) as? ProcessingRowView {
            rowView = existing
        } else {
            rowView = ProcessingRowView()
            rowView.identifier = identifier
        }
        configure(rowView: rowView, for: row)
        return rowView
    }

    func tableView(_ tableView: NSTableView, didAdd rowView: NSTableRowView, forRow row: Int) {
        if let processingRow = rowView as? ProcessingRowView {
            configure(rowView: processingRow, for: row)
        }
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        let selectedIndices = tableView.selectedRowIndexes
        let newSelection = Set(selectedIndices.map { files[$0].id })
        if newSelection != selection {
            onSelectionChange?(newSelection)
        }
        updateProcessingRows()
    }
    
    private var columnResizeWorkItem: DispatchWorkItem?

    func tableViewColumnDidResize(_ notification: Notification) {
        guard let column = notification.userInfo?["NSTableColumn"] as? NSTableColumn,
              let metadataColumn = MetadataColumn(rawValue: column.identifier.rawValue) else {
            return
        }
        
        // Mark that we're resizing to prevent updateColumns() from resetting width
        isResizingColumn = true
        
        // Update local configuration immediately
        columnConfiguration.updateWidth(column.width, for: metadataColumn)
        
        // Debounce notification to avoid flooding SwiftUI updates and causing race conditions
        columnResizeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.isResizingColumn = false  // Clear flag after debounce completes
            self.onColumnConfigurationChange?(self.columnConfiguration)
        }
        columnResizeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
    }
    
    // MARK: - External Drop Support (NSDraggingDestination)
    
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        // 只接受来自外部的文件拖放
        guard info.draggingSource as? NSTableView !== tableView else { return [] }
        
        // 检查是否包含有效的音频文件 URL
        guard let items = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingContentsConformToTypes: AudioFormatSupport.supportedExtensions.map { "public." + $0 }
        ]) as? [URL], !items.isEmpty else {
            // 回退：检查是否有任何文件 URL
            guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
                .urlReadingFileURLsOnly: true
            ]) as? [URL] else { return [] }
            let hasAudio = urls.contains { $0.isSupportedAudioFile }
            return hasAudio ? .copy : []
        }
        
        return .copy
    }
    
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true
        ]) as? [URL] else { return false }
        
        let audioURLs = urls.filter { $0.isSupportedAudioFile }
        guard !audioURLs.isEmpty else { return false }
        
        onDropFiles?(audioURLs)
        return true
    }
    
    // MARK: - CustomTableHeaderViewDelegate
    
    func headerView(_ headerView: CustomTableHeaderView, didDoubleClickSeparatorAt columnIndex: Int) {
        resizeColumn(at: columnIndex)
    }
    
    // Re-use existing resize logic but tailored for direct call
    private func resizeColumn(at index: Int) {
        let preferredWidth = computePreferredWidth(for: index, in: tableView)
        guard preferredWidth > 0 else { return }
        
        let column = tableView.tableColumns[index]
        let targetWidth = max(preferredWidth, column.minWidth)
        column.width = targetWidth
        
        // Persist
        if let metadataColumn = MetadataColumn(rawValue: column.identifier.rawValue) {
            columnConfiguration.updateWidth(targetWidth, for: metadataColumn)
            onColumnConfigurationChange?(columnConfiguration)
        }
    }
}

extension MetadataTableViewController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.autoenablesItems = false
        guard let loc = localizationManager else { return }

        // 与菜单动作使用同一套选区解析，避免两处逻辑漂移
        let selection = currentContextSelection()
        guard !selection.isEmpty else { return }
        
        // Determine capabilities based on selection
        let selectedFiles = files.filter { selection.contains($0.id) }
        
        // AI Tagging: Enable if any item is pending, failed, userModified, or completed (allow re-tagging)
        // Exclude processing and awaitingConfirmation
        let canProcessAI = selectedFiles.contains { file in
            [.pending, .failed, .userModified, .completed].contains(file.processingState)
        }
        
        // Apply/Discard: Enable if any item is awaitingConfirmation
        let canApply = selectedFiles.contains { $0.processingState == .awaitingConfirmation }
        let canDiscard = selectedFiles.contains { $0.processingState == .awaitingConfirmation }
        
        // Undo: Enable if any item is undoable
        let enableUndo = selectedFiles.contains { self.canUndo?($0) ?? false }
        
        // Helper to create colored symbol image
        func coloredImage(systemName: String, color: NSColor) -> NSImage? {
            let config = NSImage.SymbolConfiguration(paletteColors: [color])
            return NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        }

        let revealItem = menu.addItem(withTitle: loc.string("action.reveal_in_finder"), action: #selector(revealInFinder), keyEquivalent: "")
        revealItem.image = coloredImage(systemName: "folder", color: .systemBlue)

        let copyPathItem = menu.addItem(withTitle: loc.string("action.copy_path"), action: #selector(copyPath), keyEquivalent: "")
        copyPathItem.image = coloredImage(systemName: "doc.on.doc", color: .systemBlue)

        menu.addItem(NSMenuItem.separator())
        
        let playItem = menu.addItem(withTitle: loc.string("action.play"), action: #selector(play), keyEquivalent: "") // Need to add action.play
        playItem.image = coloredImage(systemName: "play.fill", color: .systemGreen)
        
        menu.addItem(NSMenuItem.separator())
        
        let aiItem = menu.addItem(withTitle: loc.string("ai.tagging"), action: #selector(processAI), keyEquivalent: "")
        aiItem.image = coloredImage(systemName: "wand.and.stars", color: .systemPurple)
        aiItem.isEnabled = canProcessAI
        
        let applyItem = menu.addItem(withTitle: loc.string("action.confirm_write"), action: #selector(applyCorrections), keyEquivalent: "")
        applyItem.image = coloredImage(systemName: "checkmark.circle", color: .systemGreen)
        applyItem.isEnabled = canApply
        
        let discardItem = menu.addItem(withTitle: loc.string("action.discard"), action: #selector(discardCorrections), keyEquivalent: "") // Need to add action.discard
        discardItem.image = coloredImage(systemName: "xmark.circle", color: .systemRed)
        discardItem.isEnabled = canDiscard
        
        let undoItem = menu.addItem(withTitle: loc.string("action.undo"), action: #selector(undoCorrections), keyEquivalent: "") // Need to add action.undo
        undoItem.image = coloredImage(systemName: "arrow.uturn.backward.circle", color: .systemOrange)
        undoItem.isEnabled = enableUndo
        
        menu.addItem(NSMenuItem.separator())
        
        let trashItem = menu.addItem(withTitle: loc.string("trash.move_to_trash"), action: #selector(moveToTrash), keyEquivalent: "")
        trashItem.image = coloredImage(systemName: "trash", color: .systemRed)
    }
    
    @objc private func revealInFinder() {
        onMenuAction?(MetadataTableView.MenuAction.revealInFinder, currentContextSelection())
    }

    @objc private func copyPath() {
        onMenuAction?(MetadataTableView.MenuAction.copyPath, currentContextSelection())
    }
    
    @objc private func play() {
        onMenuAction?(MetadataTableView.MenuAction.play, currentContextSelection())
    }
    
    @objc private func processAI() {
        onMenuAction?(MetadataTableView.MenuAction.processAI, currentContextSelection())
    }
    
    @objc private func applyCorrections() {
        onMenuAction?(MetadataTableView.MenuAction.applyCorrections, currentContextSelection())
    }
    
    @objc private func discardCorrections() {
        onMenuAction?(MetadataTableView.MenuAction.discardCorrections, currentContextSelection())
    }
    
    @objc private func undoCorrections() {
        onMenuAction?(MetadataTableView.MenuAction.undoCorrections, currentContextSelection())
    }
    
    @objc private func moveToTrash() {
        onMenuAction?(MetadataTableView.MenuAction.moveToTrash, currentContextSelection())
    }
    
    private func currentContextSelection() -> Set<AudioMetadata.ID> {
        // 菜单打开期间 files 可能被异步收缩，clickedRow 需做上界校验
        let clickedRow = tableView.clickedRow
        if clickedRow >= 0, clickedRow < files.count,
           !tableView.selectedRowIndexes.contains(clickedRow) {
            return [files[clickedRow].id]
        }
        return selection
    }
}

private extension MetadataTableViewController {
    func makeCellContent(for column: MetadataColumn, file: AudioMetadata) -> MetadataCellContent {
        let (color, font) = baseTextStyle(for: file)
        let isEditable = editableColumns.contains(column)
        
        switch column {
        case .fileName:
            return makeComparisonContent(
                original: file.fileName,
                corrected: file.suggestedFileName,
                preferredColor: color,
                preferredFont: font
            )
        case .title:
            var content = makeComparisonContent(
                original: file.originalTitle,
                corrected: file.correctedTitle,
                preferredColor: color,
                preferredFont: font
            )
            content.isEditable = isEditable
            return content
        case .artist:
            var content = makeComparisonContent(
                original: file.originalArtist,
                corrected: file.correctedArtist,
                preferredColor: color,
                preferredFont: font
            )
            content.isEditable = isEditable
            return content
        case .album:
            var content = makeComparisonContent(
                original: file.originalAlbum,
                corrected: file.correctedAlbum,
                preferredColor: color,
                preferredFont: font
            )
            content.isEditable = isEditable
            return content
        case .genre:
            var content = makeComparisonContent(
                original: file.originalGenre,
                corrected: file.correctedGenre,
                preferredColor: color,
                preferredFont: font
            )
            content.isEditable = isEditable
            return content
        case .year:
            var content = makeComparisonContent(
                original: file.originalYear,
                corrected: file.correctedYear,
                preferredColor: color,
                preferredFont: font
            )
            content.isEditable = isEditable
            return content
        case .duration:
            return singleLineContent(file.durationDisplay, color: color, font: font)
        case .fileSize:
            return singleLineContent(file.fileSizeDisplay, color: color, font: font)
        case .bitrate:
            return singleLineContent(file.bitrateDisplay, color: color, font: font)
        case .sampleRate:
            return singleLineContent(file.sampleRateDisplay, color: color, font: font)
        case .format:
            return singleLineContent(file.formatDisplay, color: color, font: font)
        case .creationDate:
            return singleLineContent(file.creationDateDisplay, color: color, font: font)
        case .modificationDate:
            return singleLineContent(file.modificationDateDisplay, color: color, font: font)
        case .status:
            let label = localizationManager?.string(file.processingState.localizationKey) ?? file.processingState.rawValue
            return singleLineContent(label, color: color, font: font)
        }
    }
    
    func makeComparisonContent(
        original: String?,
        corrected: String?,
        preferredColor: NSColor,
        preferredFont: NSFont
    ) -> MetadataCellContent {
        let trimmedOriginal = original?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCorrected = corrected?.trimmingCharacters(in: .whitespacesAndNewlines)
        let originalDisplay = (trimmedOriginal?.isEmpty == false) ? trimmedOriginal! : "—"
        
        guard
            let correctedText = trimmedCorrected,
            !correctedText.isEmpty,
            AudioMetadata.hasMeaningfulChange(original: original, corrected: corrected)
        else {
            let missingOriginal = trimmedOriginal?.isEmpty ?? true
            let textColor: NSColor = missingOriginal ? .systemRed : preferredColor
            let textFont: NSFont = missingOriginal ? NSFont.systemFont(ofSize: scaledBodyFontSize) : preferredFont
            let attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: textColor,
                .font: textFont
            ]
            let tooltip = trimmedOriginal?.isEmpty == false ? trimmedOriginal : nil
            return MetadataCellContent(
                primary: NSAttributedString(string: originalDisplay, attributes: attributes),
                secondary: nil,
                toolTip: tooltip
            )
        }
        
        let newAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: preferredColor,
            .font: preferredFont
        ]
        let oldAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.secondaryLabelColor,
            .font: NSFont.systemFont(ofSize: scaledSecondaryFontSize),
            .strikethroughStyle: NSUnderlineStyle.single.rawValue
        ]
        let tooltipComponents = [correctedText, trimmedOriginal ?? ""].filter { !$0.isEmpty }
        let tooltip = tooltipComponents.isEmpty ? nil : tooltipComponents.joined(separator: "\n")
        return MetadataCellContent(
            primary: NSAttributedString(string: correctedText, attributes: newAttributes),
            secondary: NSAttributedString(string: originalDisplay, attributes: oldAttributes),
            toolTip: tooltip
        )
    }
    
    func singleLineContent(_ text: String, color: NSColor, font: NSFont) -> MetadataCellContent {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isPlaceholder = trimmed.isEmpty
        let display = isPlaceholder ? "—" : trimmed
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: isPlaceholder ? NSColor.secondaryLabelColor : color,
            .font: font
        ]
        let tooltip = isPlaceholder ? nil : trimmed
        return MetadataCellContent(
            primary: NSAttributedString(string: display, attributes: attributes),
            secondary: nil,
            toolTip: tooltip
        )
    }
    
    /// 表格正文字号：系统默认字号 + 当前档位偏移
    var scaledBodyFontSize: CGFloat {
        NSFont.systemFontSize + fontScale.pointDelta
    }

    /// 表格次要文字字号（已弃用值删除线等）：小号字号 + 当前档位偏移
    var scaledSecondaryFontSize: CGFloat {
        NSFont.smallSystemFontSize + fontScale.pointDelta
    }

    func baseTextStyle(for file: AudioMetadata) -> (NSColor, NSFont) {
        if file.processingState == .awaitingConfirmation {
            return (.systemBlue, .boldSystemFont(ofSize: scaledBodyFontSize))
        } else {
            return (.labelColor, .systemFont(ofSize: scaledBodyFontSize))
        }
    }
    
    func comparator(for column: MetadataColumn, ascending: Bool) -> KeyPathComparator<AudioMetadata>? {
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
}

// MARK: - Custom Cell Views

class ProcessingRowView: NSTableRowView {
    var isProcessing: Bool = false {
        didSet { updateAppearance() }
    }

    var isRowSelected: Bool = false {
        didSet { updateAppearance() }
    }

    /// 标记是否为外部拖放导入的文件
    var isDroppedFile: Bool = false {
        didSet { updateDropIndicator() }
    }

    /// 标记是否为当前正在播放的曲目
    var isNowPlaying: Bool = false {
        didSet { updateNowPlayingIndicator() }
    }

    private var shimmerLayer: CAGradientLayer?
    private var baseTintLayer: CALayer?
    private var dropIndicatorLayer: CALayer?
    private var nowPlayingBorderLayer: CALayer?
    private var nowPlayingTintLayer: CALayer?
    private let baseTintAlpha: CGFloat = 0.08
    private let baseTintAlphaSelected: CGFloat = 0.28
    private let highlightAlpha: CGFloat = 0.25
    private let highlightAlphaSelected: CGFloat = 0.75

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.masksToBounds = true
        applyBaseTint()
    }

    override func layout() {
        super.layout()
        let insetRect = selectionInsetRect
        shimmerLayer?.frame = insetRect
        shimmerLayer?.cornerRadius = 8.0
        
        baseTintLayer?.frame = insetRect
        baseTintLayer?.cornerRadius = 8.0
        
        nowPlayingTintLayer?.frame = insetRect
        nowPlayingTintLayer?.cornerRadius = 8.0
        
        dropIndicatorLayer?.frame = CGRect(x: insetRect.minX, y: 1, width: 3, height: bounds.height - 2)
        updateNowPlayingBorderFrame()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        let insetRect = selectionInsetRect
        let path = NSBezierPath(roundedRect: insetRect, xRadius: 8.0, yRadius: 8.0)
        
        let selectionColor: NSColor
        if self.window?.isKeyWindow == true {
            selectionColor = NSColor.selectedContentBackgroundColor
        } else {
            selectionColor = NSColor.unemphasizedSelectedContentBackgroundColor
        }
        
        selectionColor.set()
        path.fill()
    }

    override func drawBackground(in dirtyRect: NSRect) {
        if isSelected {
            if self.window?.isKeyWindow != true {
                let insetRect = selectionInsetRect
                let path = NSBezierPath(roundedRect: insetRect, xRadius: 8.0, yRadius: 8.0)
                NSColor.unemphasizedSelectedContentBackgroundColor.set()
                path.fill()
            }
            // For keyWindow selection, we let drawSelection(in:) handle the active blue background.
            // We do not call super.drawBackground to prevent macOS from drawing any default straight-corner selection.
        } else {
            var drawnCustomBackground = false
            if let tableView = self.superview as? NSTableView ?? parentTableView {
                if tableView.usesAlternatingRowBackgroundColors {
                    let row = tableView.row(for: self)
                    if row != -1 {
                        let colors = NSColor.alternatingContentBackgroundColors
                        if colors.count > 1 {
                            let color = colors[row % colors.count]
                            let insetRect = selectionInsetRect
                            let path = NSBezierPath(roundedRect: insetRect, xRadius: 8.0, yRadius: 8.0)
                            color.set()
                            path.fill()
                            drawnCustomBackground = true
                        }
                    }
                }
            }
            if !drawnCustomBackground {
                super.drawBackground(in: dirtyRect)
            }
        }
    }

    private var parentTableView: NSTableView? {
        var view = self.superview
        while view != nil {
            if let tableView = view as? NSTableView {
                return tableView
            }
            view = view?.superview
        }
        return nil
    }

    /// 获取系统蓝色选中背景的圆角矩形区域（macOS inset 样式下水平内缩）
    private var selectionInsetRect: CGRect {
        // macOS Big Sur+ 的 inset 样式中，NSTableRowView 内部在左右各缩进约 8pt
        // 使用系统方法获取实际绘制区域
        let insetX: CGFloat = 8.0
        return bounds.insetBy(dx: insetX, dy: 0)
    }

    /// 更新流动彩带的尺寸与遮罩
    private func updateNowPlayingBorderFrame() {
        guard let container = nowPlayingBorderLayer else { return }
        let insetRect = selectionInsetRect
        if container.frame == insetRect { return }
        container.frame = insetRect
        // 容器层的静态遮罩跟随行尺寸
        container.mask = createBorderMask(for: insetRect.size)
        // 内部线性渐变层贴合容器尺寸
        if let gradient = container.sublayers?.first as? CAGradientLayer {
            gradient.frame = CGRect(origin: .zero, size: insetRect.size)
        }
    }

    private func updateAppearance() {
        updateBaseTint()
        if isProcessing {
            startShimmer()
        } else {
            stopShimmer()
        }
        // 播放状态也需要同步刷新（选中变化时底色透明度不同）
        updateNowPlayingIndicator()
    }

    private func updateBaseTint() {
        baseTintLayer?.removeFromSuperlayer()
        baseTintLayer = nil
        if isProcessing {
            applyBaseTint()
        }
    }

    private func applyBaseTint() {
        baseTintLayer?.removeFromSuperlayer()
        baseTintLayer = nil
        guard isProcessing else { return }
        guard let baseLayer = layer else { return }
        let tintAlpha = isRowSelected ? baseTintAlphaSelected : baseTintAlpha
        let tintColor = (isRowSelected ? NSColor.white : NSColor.controlAccentColor).withAlphaComponent(tintAlpha).cgColor
        let tintLayer = CALayer()
        let insetRect = selectionInsetRect
        tintLayer.frame = insetRect
        tintLayer.cornerRadius = 8.0
        tintLayer.backgroundColor = tintColor
        tintLayer.zPosition = 1
        baseLayer.insertSublayer(tintLayer, at: 0)
        baseTintLayer = tintLayer
    }

    private func startShimmer() {
        stopShimmer()
        guard let baseLayer = layer else { return }

        let highlightColor = (isRowSelected ? NSColor.white : NSColor.controlAccentColor)
            .withAlphaComponent(isRowSelected ? highlightAlphaSelected : highlightAlpha)
            .cgColor
        let transparent = NSColor.clear.cgColor

        let gradient = CAGradientLayer()
        gradient.colors = [transparent, transparent, highlightColor, transparent, transparent]
        gradient.locations = [0.0, 0.2, 0.5, 0.8, 1.0]
        gradient.startPoint = CGPoint(x: -0.8, y: 0.5)
        gradient.endPoint = CGPoint(x: 0.2, y: 0.5)
        let insetRect = selectionInsetRect
        gradient.frame = insetRect
        gradient.cornerRadius = 8.0
        gradient.zPosition = 2

        let startAnimation = CABasicAnimation(keyPath: "startPoint")
        startAnimation.fromValue = NSValue(point: gradient.startPoint)
        startAnimation.toValue = NSValue(point: CGPoint(x: 1.4, y: 0.5))

        let endAnimation = CABasicAnimation(keyPath: "endPoint")
        endAnimation.fromValue = NSValue(point: gradient.endPoint)
        endAnimation.toValue = NSValue(point: CGPoint(x: 2.4, y: 0.5))

        let animationGroup = CAAnimationGroup()
        animationGroup.animations = [startAnimation, endAnimation]
        animationGroup.duration = 1.9
        animationGroup.repeatCount = .infinity
        animationGroup.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        gradient.add(animationGroup, forKey: "shimmer")
        baseLayer.addSublayer(gradient)
        shimmerLayer = gradient
    }

    private func stopShimmer() {
        shimmerLayer?.removeAllAnimations()
        shimmerLayer?.removeFromSuperlayer()
        shimmerLayer = nil
        // 保留/更新底色在 updateBaseTint 中处理
    }

    // MARK: - 拖入文件标记条

    private func updateDropIndicator() {
        dropIndicatorLayer?.removeFromSuperlayer()
        dropIndicatorLayer = nil

        guard isDroppedFile, let baseLayer = layer else { return }

        let indicator = CALayer()
        let insetRect = selectionInsetRect
        indicator.frame = CGRect(x: insetRect.minX, y: 1, width: 3, height: bounds.height - 2)
        indicator.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.7).cgColor
        indicator.cornerRadius = 1.5
        indicator.zPosition = 10
        baseLayer.addSublayer(indicator)
        dropIndicatorLayer = indicator
    }

    // MARK: - 正在播放行指示（流动彩带）

    private func updateNowPlayingIndicator() {
        nowPlayingBorderLayer?.sublayers?.forEach { $0.removeAllAnimations() }
        nowPlayingBorderLayer?.removeFromSuperlayer()
        nowPlayingBorderLayer = nil
        nowPlayingTintLayer?.removeFromSuperlayer()
        nowPlayingTintLayer = nil

        guard isNowPlaying, let baseLayer = layer else { return }

        // 1. 容器层：持有静态的边框遮罩，确保矩形形状不随动画变形
        let insetRect = selectionInsetRect
        let container = CALayer()
        container.frame = insetRect
        container.masksToBounds = true
        container.mask = createBorderMask(for: insetRect.size)
        container.zPosition = 12

        // 2. 内部线性对角线渐变层
        let gradient = CAGradientLayer()
        gradient.type = .axial
        gradient.frame = CGRect(origin: .zero, size: insetRect.size)
        gradient.startPoint = CGPoint(x: 0, y: 0)
        gradient.endPoint = CGPoint(x: 1, y: 1)

        // 柔和霓虹彩带色彩基础色
        let baseColors = [
            NSColor(red: 0.40, green: 0.85, blue: 1.00, alpha: 0.90).cgColor,  // 青蓝
            NSColor(red: 0.55, green: 0.50, blue: 1.00, alpha: 0.90).cgColor,  // 蓝紫
            NSColor(red: 0.90, green: 0.40, blue: 0.95, alpha: 0.90).cgColor,  // 品红
            NSColor(red: 1.00, green: 0.45, blue: 0.55, alpha: 0.90).cgColor,  // 粉红
            NSColor(red: 1.00, green: 0.70, blue: 0.30, alpha: 0.90).cgColor,  // 金橙
            NSColor(red: 0.45, green: 1.00, blue: 0.50, alpha: 0.90).cgColor,  // 翠绿
        ]

        // 构造颜色无缝轮转的关键帧数组
        var keyframes: [[CGColor]] = []
        let numColors = baseColors.count
        for i in 0...numColors {
            var shiftedColors: [CGColor] = []
            for j in 0...numColors {
                let index = (i + j) % numColors
                shiftedColors.append(baseColors[index])
            }
            keyframes.append(shiftedColors)
        }

        gradient.colors = keyframes[0]
        container.addSublayer(gradient)

        // 3. 颜色轮转动画：实现实线沿着对角线方向顺畅流动的视觉效果
        let colorAnim = CAKeyframeAnimation(keyPath: "colors")
        colorAnim.values = keyframes
        colorAnim.duration = 4.0
        colorAnim.repeatCount = .infinity
        colorAnim.calculationMode = .linear
        gradient.add(colorAnim, forKey: "rainbowFlow")

        baseLayer.addSublayer(container)
        nowPlayingBorderLayer = container

        // 4. 淡色底色：增强播放行的可辨识度
        let tintLayer = CALayer()
        tintLayer.frame = insetRect
        tintLayer.cornerRadius = 8.0
        let tintAlpha: CGFloat = isRowSelected ? 0.12 : 0.04
        tintLayer.backgroundColor = NSColor.systemCyan.withAlphaComponent(tintAlpha).cgColor
        tintLayer.zPosition = 0
        baseLayer.insertSublayer(tintLayer, at: 0)
        nowPlayingTintLayer = tintLayer
    }

    /// 创建边框遮罩：仅露出 1.5pt 宽的实线四周边框
    private func createBorderMask(for size: CGSize) -> CAShapeLayer {
        let mask = CAShapeLayer()
        let borderWidth: CGFloat = 1.5
        let outerRect = CGRect(origin: .zero, size: size)
        let innerRect = outerRect.insetBy(dx: borderWidth, dy: borderWidth)
        let outerPath = CGMutablePath()
        outerPath.addRoundedRect(in: outerRect, cornerWidth: 5.0, cornerHeight: 5.0)
        outerPath.addRoundedRect(in: innerRect, cornerWidth: 3.5, cornerHeight: 3.5)
        mask.path = outerPath
        mask.fillRule = .evenOdd
        return mask
    }
}

/// 在自定义 bounds 内部精准垂直居中绘制文本的 NSTextFieldCell
final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func titleRect(forBounds rect: NSRect) -> NSRect {
        var titleRect = super.titleRect(forBounds: rect)
        
        // 优先从富文本属性获取字体，无富文本则获取 cell.font
        let attributed = attributedStringValue
        let effectiveFont = (attributed.length > 0 ? attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil) ?? font
        
        guard let font = effectiveFont else { return titleRect }
        
        // 轻量 O(1) 浮点数计算文本精准行高，避免高频触发 CoreText 文本布局引擎
        let textHeight = ceil(font.ascender - font.descender + font.leading)

        if titleRect.height > textHeight {
            titleRect.origin.y += floor((titleRect.height - textHeight) / 2)
            titleRect.size.height = textHeight
        }
        return titleRect
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        return titleRect(forBounds: rect)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        let newRect = titleRect(forBounds: rect)
        super.select(withFrame: newRect, in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        let newRect = titleRect(forBounds: rect)
        super.edit(withFrame: newRect, in: controlView, editor: textObj, delegate: delegate, event: event)
    }
}

fileprivate struct MetadataCellContent {
    let primary: NSAttributedString
    let secondary: NSAttributedString?
    let toolTip: String?
    var isEditable: Bool = false
}

class MetadataTableCellView: NSTableCellView, NSTextFieldDelegate {
    private let primaryLabel = MetadataTableCellView.makeLabel()
    private let secondaryLabel = MetadataTableCellView.makeLabel()
    private let editButton = NSButton()
    private let editButtonBackground = NSView()  // hover 高亮背景

    /// primaryLabel/secondaryLabel 两行文本之间的垂直间距
    private static let lineSpacing: CGFloat = 2

    // 以下均为直接锚定在 primaryLabel/secondaryLabel 自身上的约束（不经过任何 NSStackView）。
    // NSTableView 的行内容重排布对被约束拉伸的 NSStackView 有未文档化的底部对齐副作用——
    // 同样的 GTE/LTE + centerY 约束加在 NSStackView 上会失效并整体贴底，
    // 直接加在叶子控件（NSTextField/NSView）上则能正确居中，已用独立测试反复验证过。
    private var primaryCenterY: NSLayoutConstraint!
    private var primaryLeadingNoButton: NSLayoutConstraint!
    private var primaryLeadingWithButton: NSLayoutConstraint!
    private var secondaryTopConstraint: NSLayoutConstraint!
    private var secondaryLeadingConstraint: NSLayoutConstraint!
    private var secondaryTrailingConstraint: NSLayoutConstraint!
    private var secondaryBottomConstraint: NSLayoutConstraint!

    /// 编辑按钮的提示文案（由控制器注入本地化字符串）
    var editButtonToolTip: String? {
        get { editButton.toolTip }
        set { editButton.toolTip = newValue }
    }
    
    // 编辑状态
    private var originalValue: String = ""
    /// 进入编辑前的完整富文本（含颜色/字号/是否加粗），取消编辑时用于精确还原
    private var originalAttributedValue: NSAttributedString?
    private var isInEditMode: Bool = false
    private var isSettingUpEdit: Bool = false  // 防止 controlTextDidEndEditing 过早触发
    var onEditCommit: ((String) -> Void)?
    var onEditCancel: (() -> Void)?
    /// 点击编辑图标的回调，由 Controller 为可编辑列设置
    var onEditButtonClicked: ((MetadataTableCellView) -> Void)?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }
    
    private func commonInit() {
        wantsLayer = true
        layer?.masksToBounds = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        
        // 编辑按钮容器（背景 + 按钮）
        editButtonBackground.translatesAutoresizingMaskIntoConstraints = false
        editButtonBackground.wantsLayer = true
        editButtonBackground.layer?.cornerRadius = 10
        editButtonBackground.layer?.backgroundColor = NSColor.clear.cgColor
        editButtonBackground.isHidden = true
        
        // 编辑按钮（铅笔图标）
        editButton.translatesAutoresizingMaskIntoConstraints = false
        editButton.bezelStyle = .inline
        editButton.isBordered = false
        editButton.image = NSImage(systemSymbolName: "pencil", accessibilityDescription: nil)
        editButton.contentTintColor = .systemOrange
        editButton.imageScaling = .scaleProportionallyDown
        editButton.target = self
        editButton.action = #selector(editButtonTapped)
        editButton.alphaValue = 0.6
        
        editButtonBackground.addSubview(editButton)
        editButtonBackground.setContentHuggingPriority(.required, for: .horizontal)
        editButtonBackground.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(editButtonBackground)

        // Hover 效果
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: ["target": "editButton"]
        )
        editButtonBackground.addTrackingArea(trackingArea)
        NSLayoutConstraint.activate([
            editButtonBackground.widthAnchor.constraint(equalToConstant: 20),
            editButtonBackground.heightAnchor.constraint(equalToConstant: 20),
            editButton.centerXAnchor.constraint(equalTo: editButtonBackground.centerXAnchor),
            editButton.centerYAnchor.constraint(equalTo: editButtonBackground.centerYAnchor),
            editButton.widthAnchor.constraint(equalToConstant: 14),
            editButton.heightAnchor.constraint(equalToConstant: 14)
        ])
        
        addSubview(primaryLabel)
        addSubview(secondaryLabel)
        secondaryLabel.isHidden = true

        // 设置 delegate 处理键盘事件
        primaryLabel.delegate = self

        // primaryLabel/secondaryLabel 直接锚定在 self 上，centerY 决定垂直位置，
        // top/bottom 仅作为越界保护。双行对比时 primaryCenterY 的 constant 会上移半个
        // secondaryLabel 行高，使 [primary+secondary] 整体仍以 self 的正中为中心。
        primaryCenterY = primaryLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        primaryLeadingNoButton = primaryLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2)
        primaryLeadingWithButton = primaryLabel.leadingAnchor.constraint(equalTo: editButtonBackground.trailingAnchor, constant: 2)
        secondaryTopConstraint = secondaryLabel.topAnchor.constraint(equalTo: primaryLabel.bottomAnchor, constant: Self.lineSpacing)
        secondaryLeadingConstraint = secondaryLabel.leadingAnchor.constraint(equalTo: primaryLabel.leadingAnchor)
        secondaryTrailingConstraint = secondaryLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2)
        secondaryBottomConstraint = secondaryLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4)

        NSLayoutConstraint.activate([
            editButtonBackground.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            editButtonBackground.centerYAnchor.constraint(equalTo: centerYAnchor),
            primaryCenterY,
            primaryLeadingNoButton,
            primaryLabel.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 4),
            primaryLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -4),
            primaryLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2)
        ])

        textField = primaryLabel
    }

    @objc private func editButtonTapped() {
        onEditButtonClicked?(self)
    }
    
    /// 手型光标是否已入栈：视图在悬停中被复用/移除时 mouseExited 不会触发，
    /// 需在 viewWillMove(toWindow:) 兜底 pop，保证 push/pop 严格配对
    private var isPointerCursorActive = false

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil, isPointerCursorActive {
            NSCursor.pop()
            isPointerCursorActive = false
        }
    }

    override func mouseEntered(with event: NSEvent) {
        if let info = event.trackingArea?.userInfo as? [String: String],
           info["target"] == "editButton" {
            if !isPointerCursorActive {
                NSCursor.pointingHand.push()
                isPointerCursorActive = true
            }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.allowsImplicitAnimation = true
                // 透明度提升
                editButton.animator().alphaValue = 1.0
                // 圆形背景高亮
                editButtonBackground.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.15).cgColor
            }
            // 弹跳缩放效果
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                editButton.animator().layer?.setAffineTransform(CGAffineTransform(scaleX: 1.2, y: 1.2))
            } completionHandler: { [weak self] in
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.1
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    self?.editButton.animator().layer?.setAffineTransform(.identity)
                }
            }
        } else {
            super.mouseEntered(with: event)
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        if let info = event.trackingArea?.userInfo as? [String: String],
           info["target"] == "editButton" {
            if isPointerCursorActive {
                NSCursor.pop()
                isPointerCursorActive = false
            }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.allowsImplicitAnimation = true
                editButton.animator().alphaValue = 0.6
                editButtonBackground.layer?.backgroundColor = NSColor.clear.cgColor
                editButton.layer?.setAffineTransform(.identity)
            }
        } else {
            super.mouseExited(with: event)
        }
    }

    fileprivate func configure(with content: MetadataCellContent) {
        // 如果正在编辑，不更新内容
        guard !isInEditMode else { return }

        primaryLabel.attributedStringValue = content.primary
        primaryLabel.toolTip = content.toolTip

        // 同步更新控件本身的 font，确保 Auto Layout intrinsicContentSize 的精准计算
        if content.primary.length > 0, let primaryFont = content.primary.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
            primaryLabel.font = primaryFont
        }

        if let secondary = content.secondary {
            secondaryLabel.isHidden = false
            secondaryLabel.attributedStringValue = secondary
            secondaryLabel.toolTip = content.toolTip
            if secondary.length > 0, let secFont = secondary.attribute(.font, at: 0, effectiveRange: nil) as? NSFont {
                secondaryLabel.font = secFont
            }
            secondaryTopConstraint.isActive = true
            secondaryLeadingConstraint.isActive = true
            secondaryTrailingConstraint.isActive = true
            secondaryBottomConstraint.isActive = true
            // primaryLabel 上移半个 secondaryLabel 行高，使双行整体仍居中于 self
            let secondaryFont = (secondary.length > 0 ? secondary.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil) ?? NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
            let secondaryLineHeight = ceil(secondaryFont.ascender - secondaryFont.descender + secondaryFont.leading)
            primaryCenterY.constant = -(secondaryLineHeight + Self.lineSpacing) / 2
        } else {
            secondaryLabel.isHidden = true
            secondaryLabel.stringValue = ""
            secondaryLabel.toolTip = nil
            secondaryTopConstraint.isActive = false
            secondaryLeadingConstraint.isActive = false
            secondaryTrailingConstraint.isActive = false
            secondaryBottomConstraint.isActive = false
            primaryCenterY.constant = 0
        }

        // 根据是否可编辑控制铅笔图标容器，并联动文本的前导约束
        let isEditable = content.isEditable
        editButtonBackground.isHidden = !isEditable
        primaryLeadingWithButton.isActive = isEditable
        primaryLeadingNoButton.isActive = !isEditable

        needsLayout = true
    }
    
    // MARK: - 编辑模式
    
    /// 开始编辑
    func beginEditing() {
        guard !isInEditMode else { return }
        isInEditMode = true
        isSettingUpEdit = true  // 防止 controlTextDidEndEditing 过早触发
        
        // 保存原始值（纯文本 + 完整富文本，取消编辑时分别用于比较和还原）
        originalValue = primaryLabel.stringValue
        originalAttributedValue = primaryLabel.attributedStringValue

        // 隐藏 secondary 标签（如果有旧值显示），编辑状态下始终按单行居中
        secondaryLabel.isHidden = true
        secondaryTopConstraint.isActive = false
        secondaryLeadingConstraint.isActive = false
        secondaryTrailingConstraint.isActive = false
        secondaryBottomConstraint.isActive = false
        primaryCenterY.constant = 0

        // 设置为可编辑状态 - 保持简洁外观
        primaryLabel.isEditable = true
        primaryLabel.isSelectable = true
        primaryLabel.isBordered = false  // 不使用边框，保持简洁
        primaryLabel.drawsBackground = true
        primaryLabel.focusRingType = .none  // 禁用蓝色焦点环
        
        // 编辑模式使用橙黄色调 - 表示"正在修改"
        let editColor = NSColor.systemOrange
        primaryLabel.backgroundColor = editColor.withAlphaComponent(0.12)
        // 字号取自进入编辑前富文本里实际生效的字体（跟随当前文字大小档位），仅去除可能的加粗样式。
        // 注意：NSTextField.font 不会随 attributedStringValue 同步更新，必须从富文本属性里读，
        // 否则复用中的 cell 可能拿到过期/未缩放的默认字号
        let displayedFontSize = (originalAttributedValue?.length ?? 0) > 0
            ? (originalAttributedValue?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize
            : nil
        primaryLabel.font = .systemFont(ofSize: displayedFontSize ?? NSFont.systemFontSize)
        primaryLabel.textColor = .textColor
        
        // 启用滚动（允许输入）但不使用边框
        if let cell = primaryLabel.cell as? NSTextFieldCell {
            cell.isBordered = false
            cell.isBezeled = false
            cell.isScrollable = true
        }
        
        // 单元格级别的高亮效果 - 简洁的单层边框
        if layer == nil {
            wantsLayer = true
        }
        if let layer = self.layer {
            layer.borderWidth = 2
            layer.borderColor = editColor.cgColor
            layer.cornerRadius = 4
            layer.backgroundColor = editColor.withAlphaComponent(0.05).cgColor
        }
        
        // 强制刷新视图
        needsDisplay = true
        needsLayout = true
        
        // 延迟设置焦点，确保视图完全更新且不会立即触发 endEditing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self = self, self.isInEditMode else { return }
            self.window?.makeFirstResponder(self.primaryLabel)
            self.primaryLabel.selectText(nil)
            
            // 焦点设置完成后才允许 controlTextDidEndEditing 生效
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.isSettingUpEdit = false
            }
        }
    }
    
    /// 结束编辑
    /// - Parameter commit: true 提交修改，false 取消修改
    func endEditing(commit: Bool) {
        guard isInEditMode else { return }
        isInEditMode = false
        
        let newValue = primaryLabel.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // 恢复不可编辑状态
        primaryLabel.isEditable = false
        primaryLabel.isSelectable = false
        primaryLabel.isBordered = false
        primaryLabel.drawsBackground = false
        primaryLabel.backgroundColor = .clear
        
        // 恢复 cell 样式
        if let cell = primaryLabel.cell as? NSTextFieldCell {
            cell.isBordered = false
            cell.isBezeled = false
            cell.isScrollable = false  // 恢复原始状态
        }
        
        // 移除高亮边框
        layer?.borderWidth = 0
        layer?.borderColor = nil
        layer?.cornerRadius = 0
        layer?.backgroundColor = nil
        
        // 退出动画
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.allowsImplicitAnimation = true
            self.layoutSubtreeIfNeeded()
        }
        
        if commit && newValue != originalValue {
            onEditCommit?(newValue)
        } else {
            // 取消：恢复完整原始富文本（颜色/字号/是否加粗），而非仅恢复纯文本，
            // 否则会丢失缩放后的字号与 AI 建议行的高亮样式
            if let originalAttributedValue {
                primaryLabel.attributedStringValue = originalAttributedValue
            } else {
                primaryLabel.stringValue = originalValue
            }
            onEditCancel?()
        }
        
        // 放弃焦点
        window?.makeFirstResponder(nil)
    }
    
    var isEditing: Bool {
        isInEditMode
    }
    
    // MARK: - NSTextFieldDelegate
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(cancelOperation(_:)) { // Esc
            endEditing(commit: false)
            return true
        }
        if commandSelector == #selector(insertNewline(_:)) { // Enter
            endEditing(commit: true)
            return true
        }
        if commandSelector == #selector(insertTab(_:)) { // Tab - 提交并可能移动到下一个单元格
            endEditing(commit: true)
            return false // 让系统处理 Tab 移动焦点
        }
        return false
    }
    
    // 当失去焦点时自动提交（但不在设置期间）
    func controlTextDidEndEditing(_ obj: Notification) {
        // 如果正在设置编辑，忽略这个回调
        guard !isSettingUpEdit, isInEditMode else { return }
        endEditing(commit: true)
    }
    
    private static func makeLabel() -> NSTextField {
        let label = NSTextField()
        label.cell = VerticallyCenteredTextFieldCell()
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        label.usesSingleLineMode = true
        label.maximumNumberOfLines = 1
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.required, for: .vertical)
        if let cell = label.cell as? NSTextFieldCell {
            cell.wraps = false
            cell.isScrollable = false
            cell.truncatesLastVisibleLine = true
        }
        return label
    }
}

class MetadataStatusCellView: NSTableCellView {
    private let containerView = NSView()
    private let stackView = NSStackView()
    private let statusInfoStack = NSStackView() // New nested stack for icon + label
    private let statusIcon = NSImageView()
    private let statusLabel = NSTextField()
    private let actionButton = HoverButton()
    private let discardButton = HoverButton()
    
    private var onConfirm: (() -> Void)?
    private var onDiscard: (() -> Void)?
    private var onUndo: (() -> Void)?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        wantsLayer = true
        
        // Container View (The "Pill")
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 4
        containerView.layer?.masksToBounds = true
        addSubview(containerView)
        
        // Main Stack View (Vertical or Horizontal depending on state)
        stackView.orientation = .horizontal
        stackView.spacing = 6
        stackView.alignment = .centerY
        stackView.distribution = .fill
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.setContentCompressionResistancePriority(.required, for: .vertical)
        stackView.setContentHuggingPriority(.required, for: .vertical)
        containerView.addSubview(stackView)
        
        // Status Info Stack (Icon + Label)
        statusInfoStack.orientation = .horizontal
        statusInfoStack.spacing = 6
        statusInfoStack.alignment = .centerY
        statusInfoStack.translatesAutoresizingMaskIntoConstraints = false
        
        // Status Icon
        statusIcon.translatesAutoresizingMaskIntoConstraints = false
        statusIcon.imageScaling = .scaleProportionallyDown
        statusIcon.contentTintColor = .labelColor
        NSLayoutConstraint.activate([
            statusIcon.widthAnchor.constraint(equalToConstant: 14),
            statusIcon.heightAnchor.constraint(equalToConstant: 14)
        ])
        
        // Status Label
        statusLabel.cell = VerticallyCenteredTextFieldCell()
        statusLabel.isEditable = false
        statusLabel.isBordered = false
        statusLabel.drawsBackground = false
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.font = .systemFont(ofSize: 12)
        if let cell = statusLabel.cell as? NSTextFieldCell {
            cell.wraps = false
            cell.isScrollable = false
            cell.truncatesLastVisibleLine = true
        }
        
        // Add Icon and Label to Info Stack
        statusInfoStack.addArrangedSubview(statusIcon)
        statusInfoStack.addArrangedSubview(statusLabel)
        
        // Action Button (Confirm/Undo)
        actionButton.bezelStyle = .inline
        actionButton.controlSize = .small
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        actionButton.target = self
        actionButton.action = #selector(buttonClicked)
        actionButton.setContentCompressionResistancePriority(.required, for: .vertical)
        
        // Discard Button
        discardButton.bezelStyle = .inline
        discardButton.controlSize = .small
        discardButton.translatesAutoresizingMaskIntoConstraints = false
        discardButton.target = self
        discardButton.action = #selector(discardClicked)
        // 标题由 configure(metadata:) 按当前语言设置
        discardButton.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Discard")
        discardButton.imagePosition = .imageLeading
        discardButton.contentTintColor = .systemRed
        discardButton.tag = 3
        discardButton.setContentCompressionResistancePriority(.required, for: .vertical)
        
        // Add layouts to Main Stack
        stackView.addArrangedSubview(statusInfoStack)
        stackView.addArrangedSubview(actionButton)
        stackView.addArrangedSubview(discardButton)
        
        // Constraints
        NSLayoutConstraint.activate([
            containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            containerView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            containerView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            containerView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
            
            stackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 6),
            stackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -6),
            stackView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 4),
            stackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -4)
        ])
    }
    
    func configure(metadata: AudioMetadata, localizationManager: LocalizationManager?, isUndoable: Bool, fontSize: CGFloat, onConfirm: @escaping () -> Void, onDiscard: @escaping () -> Void, onUndo: @escaping () -> Void) {
        self.onConfirm = onConfirm
        self.onDiscard = onDiscard
        self.onUndo = onUndo

        let loc = localizationManager

        // Reset all state first
        statusInfoStack.isHidden = false
        statusIcon.isHidden = false
        statusLabel.isHidden = false
        actionButton.isHidden = true
        discardButton.isHidden = true

        // Default: Horizontal layout
        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 6

        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.layer?.borderWidth = 0
        containerView.layer?.borderColor = nil

        switch metadata.processingState {
        case .pending:
            statusIcon.image = NSImage(systemSymbolName: "circle", accessibilityDescription: nil)
            statusIcon.contentTintColor = .tertiaryLabelColor
            statusLabel.stringValue = loc?.string("state.pending") ?? "未处理"
            statusLabel.textColor = .tertiaryLabelColor
            statusLabel.font = .systemFont(ofSize: fontSize)

        case .processing:
            statusIcon.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: nil)
            statusIcon.contentTintColor = .systemBlue
            statusLabel.stringValue = loc?.string("state.processing") ?? "处理中"
            statusLabel.textColor = .systemBlue
            statusLabel.font = .systemFont(ofSize: fontSize)
            
        case .awaitingConfirmation:
            // Style: Blue Pill - Horizontal Layout
            containerView.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.1).cgColor
            containerView.layer?.borderColor = NSColor.systemBlue.withAlphaComponent(0.2).cgColor
            containerView.layer?.borderWidth = 1
            
            // Hide info stack, show buttons
            statusInfoStack.isHidden = true
            
            // Horizontal Layout: [Action Button] [Discard Button]
            stackView.orientation = .horizontal
            stackView.alignment = .centerY
            stackView.spacing = 8
            
            actionButton.isHidden = false
            actionButton.title = loc?.string("action.write_short") ?? "修正"
            actionButton.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
            actionButton.imagePosition = .imageLeading
            actionButton.contentTintColor = .systemBlue
            actionButton.tag = 1
            
            discardButton.isHidden = false
            discardButton.title = loc?.string("action.discard_short") ?? "放弃"
            
        case .completed:
            // Style: Green Pill
            containerView.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.1).cgColor
            
            statusIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = .systemGreen
            
            statusLabel.stringValue = loc?.string("state.completed") ?? "已完成"
            statusLabel.textColor = .systemGreen
            statusLabel.font = .systemFont(ofSize: fontSize, weight: .medium)
            
            if isUndoable {
                // Vertical Layout: [Status Info]
                //                  [Undo Button]
                stackView.orientation = .vertical
                stackView.alignment = .leading
                stackView.spacing = 4
                
                actionButton.isHidden = false
                actionButton.title = loc?.string("action.undo_short") ?? "撤回"
                actionButton.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
                actionButton.imagePosition = .imageLeading
                actionButton.contentTintColor = .secondaryLabelColor
                actionButton.tag = 2
            }
            
        case .failed:
            // Style: Red Pill
            containerView.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.1).cgColor
            
            statusIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = .systemRed
            
            statusLabel.stringValue = loc?.string("state.failed") ?? "失败"
            statusLabel.textColor = .systemRed
            statusLabel.font = .systemFont(ofSize: fontSize)

        case .userModified:
            statusIcon.image = NSImage(systemSymbolName: "pencil.circle", accessibilityDescription: nil)
            statusIcon.contentTintColor = .secondaryLabelColor
            statusLabel.stringValue = loc?.string("state.user_modified") ?? "已修改"
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.font = .systemFont(ofSize: fontSize)
        }
        
        // Force layout update to ensure correct height calculation
        layoutSubtreeIfNeeded()
    }
    
    @objc private func buttonClicked() {
        if actionButton.tag == 1 {
            onConfirm?()
        } else if actionButton.tag == 2 {
            onUndo?()
        }
    }
    
    @objc private func discardClicked() {
        onDiscard?()
    }
    
    override func layout() {
        super.layout()
        // Ensure container doesn't exceed bounds
        if let container = containerView.layer {
            container.backgroundColor = container.backgroundColor // Trigger redraw if needed
        }
    }
}

// MARK: - Hover Button
class HoverButton: NSButton {
    private var trackingArea: NSTrackingArea?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        wantsLayer = true
        layer?.cornerRadius = 4
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        // Add a subtle background on hover
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
        // Slightly darken/lighten content if needed, but background is usually enough for inline buttons
    }
    
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}
