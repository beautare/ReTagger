//
//  MetadataReviewView+TableSupport.swift
//  ReTagger
//
//  Created by Claude Code
//

import SwiftUI
import AppKit

// MARK: - Table Header Menu Delegate

final class TableHeaderMenuDelegate: NSObject, NSMenuDelegate {
    weak var tableView: NSTableView?
    weak var headerView: NSTableHeaderView?
    let columnDescriptors: [MetadataColumnDescriptor]
    let localizationManager: LocalizationManager
    private let configurationProvider: () -> TableColumnConfiguration
    private let onConfigurationChange: (TableColumnConfiguration) -> Void
    private let popoverManager = ColumnConfigurationPopover()
    private var contextColumnIndex: Int?

    init(
        tableView: NSTableView,
        headerView: NSTableHeaderView,
        columnDescriptors: [MetadataColumnDescriptor],
        localizationManager: LocalizationManager,
        configurationProvider: @escaping () -> TableColumnConfiguration,
        onConfigurationChange: @escaping (TableColumnConfiguration) -> Void
    ) {
        self.tableView = tableView
        self.headerView = headerView
        self.columnDescriptors = columnDescriptors
        self.localizationManager = localizationManager
        self.configurationProvider = configurationProvider
        self.onConfigurationChange = onConfigurationChange
        super.init()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // 关闭自动启用，否则下方手动设置的 isEnabled 会被 AppKit 校验机制覆盖
        menu.autoenablesItems = false

        updateContextColumnIndex()

        let autoResizeItem = NSMenuItem(
            title: localizationManager.string("header.menu.auto_size"),
            action: #selector(autoAdjustCurrentColumn),
            keyEquivalent: ""
        )
        autoResizeItem.target = self
        autoResizeItem.isEnabled = contextColumnIndex != nil
        menu.addItem(autoResizeItem)

        let autoResizeAllItem = NSMenuItem(
            title: localizationManager.string("header.menu.auto_size_all"),
            action: #selector(autoAdjustAllColumns),
            keyEquivalent: ""
        )
        autoResizeAllItem.target = self
        autoResizeAllItem.isEnabled = (tableView?.tableColumns.contains { !$0.isHidden } ?? false)
        menu.addItem(autoResizeAllItem)

        menu.addItem(NSMenuItem.separator())

        let manageItem = NSMenuItem(
            title: localizationManager.string("header.menu.manage_columns"),
            action: #selector(showColumnConfiguration),
            keyEquivalent: ""
        )
        manageItem.target = self
        menu.addItem(manageItem)
        
        let restoreItem = NSMenuItem(
            title: localizationManager.string("header.menu.restore_defaults"),
            action: #selector(restoreDefaultConfiguration),
            keyEquivalent: ""
        )
        restoreItem.target = self
        menu.addItem(restoreItem)

        menu.addItem(NSMenuItem.separator())

        let configuration = configurationProvider()
        var orderedColumns = configuration.columnOrder
        let definedColumns = columnDescriptors.map(\.column)
        for column in definedColumns where !orderedColumns.contains(column) {
            orderedColumns.append(column)
        }

        let shouldShowScrollIndicators = needsScrollIndicators(forColumnCount: orderedColumns.count)

        if shouldShowScrollIndicators {
            menu.addItem(createScrollIndicatorItem(direction: .up, in: menu))
        }

        for metadataColumn in orderedColumns {
            guard let descriptor = columnDescriptors.first(where: { $0.column == metadataColumn }) else { continue }
            // Use localized title from descriptor (which should also get it from localization manager if updated, but descriptor is static structs.
            // Actually descriptor has 'localizationKey'. We should use that.
            let title = localizationManager.string(descriptor.localizationKey)
            
            let displayTitle = descriptor.isRequired ? "\(title) *" : title
            let menuItem = NSMenuItem(
                title: displayTitle,
                action: descriptor.isRequired ? nil : #selector(toggleColumn(_:)),
                keyEquivalent: ""
            )
            menuItem.target = self
            menuItem.representedObject = descriptor.column
            // autoenablesItems 关闭后必选列需显式置灰（其 action 为 nil，不可切换）
            menuItem.isEnabled = !descriptor.isRequired

            let isVisible = configuration.isVisible(descriptor.column)
            menuItem.state = (descriptor.isRequired || isVisible) ? .on : .off

            menu.addItem(menuItem)
        }

        if shouldShowScrollIndicators {
            menu.addItem(createScrollIndicatorItem(direction: .down, in: menu))
        }
    }

    @objc
    func toggleColumn(_ sender: NSMenuItem) {
        guard
            let metadataColumn = sender.representedObject as? MetadataColumn,
            !metadataColumn.isRequired
        else { return }

        var configuration = configurationProvider()
        let isCurrentlyVisible = configuration.isVisible(metadataColumn)
        if isCurrentlyVisible {
            configuration.visibleColumns.remove(metadataColumn)
        } else {
            configuration.visibleColumns.insert(metadataColumn)
        }
        sender.state = isCurrentlyVisible ? .off : .on

        onConfigurationChange(configuration)
    }

    @objc
    func showColumnConfiguration() {
        guard let headerView = headerView else { return }

        popoverManager.show(
            relativeTo: headerView,
            configuration: configurationProvider(),
            columnDescriptors: columnDescriptors,
            localizationManager: localizationManager,
            onSave: { [weak self] newConfig in
                self?.onConfigurationChange(newConfig)
            }
        )
    }
    
    @objc
    func restoreDefaultConfiguration() {
        onConfigurationChange(.default)
    }

    @objc
    private func autoAdjustCurrentColumn() {
        guard
            let tableView = tableView,
            let columnIndex = contextColumnIndex,
            columnIndex >= 0,
            columnIndex < tableView.numberOfColumns
        else { return }

        resizeColumn(at: columnIndex, in: tableView)
    }

    @objc
    private func autoAdjustAllColumns() {
        guard let tableView = tableView else { return }
        for (index, column) in tableView.tableColumns.enumerated() where !column.isHidden {
            resizeColumn(at: index, in: tableView)
        }
    }

    private func resizeColumn(at index: Int, in tableView: NSTableView) {
        let preferredWidth = computePreferredWidth(for: index, in: tableView)
        guard preferredWidth > 0 else { return }
        let column = tableView.tableColumns[index]
        let targetWidth = max(preferredWidth, column.minWidth)
        column.width = targetWidth
        
        // Persist the change
        if let metadataColumn = MetadataColumn(rawValue: column.identifier.rawValue) {
            var config = configurationProvider()
            config.updateWidth(targetWidth, for: metadataColumn)
            onConfigurationChange(config)
        }
    }

    private func updateContextColumnIndex() {
        if let clicked = tableView?.clickedColumn, clicked != -1 {
            contextColumnIndex = clicked
            return
        }

        if let headerView = headerView,
           let event = NSApp.currentEvent {
            let location = headerView.convert(event.locationInWindow, from: nil)
            let column = headerView.column(at: location)
            if column != -1 {
                contextColumnIndex = column
                return
            }
        }

        contextColumnIndex = tableView?.tableColumns.firstIndex(where: { !$0.isHidden })
    }

    private func needsScrollIndicators(forColumnCount count: Int) -> Bool {
        guard count > 0 else { return false }
        let staticItemCount = 6 // 两个自动调整项 + “管理列...” + 分隔线 + 滚动指示器潜在占位
        let estimatedRowHeight: CGFloat = 24
        let totalItems = count + staticItemCount
        let estimatedHeight = CGFloat(totalItems) * estimatedRowHeight
        let availableHeight = headerView?.window?.screen?.visibleFrame.height
            ?? NSScreen.main?.visibleFrame.height
            ?? 800
        return estimatedHeight > availableHeight * 0.85
    }

    private func createScrollIndicatorItem(direction: HoverScrollIndicatorView.Direction, in menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.isEnabled = false
        item.view = HoverScrollIndicatorView(direction: direction, menu: menu)
        return item
    }
}

// MARK: - Column Autosizing Support

func computePreferredWidth(for columnIndex: Int, in tableView: NSTableView) -> CGFloat {
    guard columnIndex >= 0, columnIndex < tableView.tableColumns.count else {
        return 0
    }

    let column = tableView.tableColumns[columnIndex]
    let rowCount = tableView.numberOfRows

    // Start with minimum width only - don't use header cell size as it can be misleadingly wide
    // (header cells may include sorting indicators, padding, etc.)
    var maxWidth = column.minWidth

    if rowCount == 0 {
        // No data - use header width as fallback
        return max(column.headerCell.cellSize.width, column.minWidth)
    }

    let sampleLimit = min(300, rowCount)
    for row in 0..<sampleLimit {
        guard let cellView = tableView.view(atColumn: columnIndex, row: row, makeIfNecessary: true) as? NSTableCellView else {
            continue
        }
        
        // Measure text width more accurately
        var cellMaxWidth: CGFloat = 0
        
        // Find all text fields in the cell view (handles both single and dual-line cells)
        let textFields = findTextFields(in: cellView)
        for textField in textFields {
            // Method 1: Use cell's cellSize which accounts for internal padding
            if let cell = textField.cell as? NSTextFieldCell {
                let cellSize = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
                cellMaxWidth = max(cellMaxWidth, cellSize.width)
            } else {
                // Fallback: Use boundingRect with usesLineFragmentOrigin for accurate measurement
                let attrString = textField.attributedStringValue
                if attrString.length > 0 {
                    let rect = attrString.boundingRect(
                        with: NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading]
                    )
                    // NSTextField typically adds ~4px internal padding (2px each side)
                    cellMaxWidth = max(cellMaxWidth, ceil(rect.width) + 4)
                }
            }
        }
        
        if cellMaxWidth > 0 {
            // Add cell internal padding from stackView constraints: 2pt leading + 2pt trailing = 4pt
            let stackViewPadding: CGFloat = 4
            let width = cellMaxWidth + stackViewPadding
            if width > maxWidth {
                maxWidth = width
            }
        } else {
            // Fallback for non-text cells (e.g., status cells with buttons)
            cellView.layoutSubtreeIfNeeded()
            let fitting = cellView.fittingSize.width
            if fitting.isFinite, fitting > 0, fitting > maxWidth {
                maxWidth = fitting
            }
        }
    }

    // Only add intercell spacing
    let intercellSpacing = tableView.intercellSpacing.width
    let finalWidth = ceil(maxWidth + intercellSpacing)
    if column.maxWidth > 0 {
        return max(min(finalWidth, column.maxWidth), column.minWidth)
    }
    return max(finalWidth, column.minWidth)
}

/// Recursively find all NSTextField instances in a view hierarchy
private func findTextFields(in view: NSView) -> [NSTextField] {
    var textFields: [NSTextField] = []
    for subview in view.subviews {
        if let textField = subview as? NSTextField, !textField.isHidden {
            textFields.append(textField)
        }
        textFields.append(contentsOf: findTextFields(in: subview))
    }
    return textFields
}

// MARK: - Header Menu Scroll Indicator

final class HoverScrollIndicatorView: NSView {
    enum Direction {
        case up
        case down
    }

    weak var targetMenu: NSMenu?
    private let direction: Direction
    private var trackingArea: NSTrackingArea?
    private var scrollTimer: Timer?
    private let label: NSTextField

    init(direction: Direction, menu: NSMenu) {
        self.direction = direction
        self.targetMenu = menu
        let text = direction == .up ? "向上查看更多" : "向下查看更多"
        label = NSTextField(labelWithString: text)
        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        label.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        label.textColor = NSColor.secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 220, height: 24)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .activeAlways,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        startScrolling()
    }

    override func mouseExited(with event: NSEvent) {
        stopScrolling()
    }

    deinit {
        stopScrolling()
    }

    private func startScrolling() {
        guard scrollTimer == nil else { return }
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.sendScrollStep()
        }
        if let scrollTimer {
            RunLoop.main.add(scrollTimer, forMode: .common)
        }
    }

    private func stopScrolling() {
        scrollTimer?.invalidate()
        scrollTimer = nil
    }

    private func sendScrollStep() {
        guard let menu = targetMenu else { return }
        ensureInitialHighlight(in: menu)

        let keyCode: UInt16 = direction == .up ? 126 : 125
        let arrowValue = UInt32(direction == .up ? NSUpArrowFunctionKey : NSDownArrowFunctionKey)
        guard let scalar = UnicodeScalar(arrowValue) else { return }
        let characters = String(Character(scalar))

        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: -1,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: true,
            keyCode: keyCode
        ) else { return }

        _ = menu.performKeyEquivalent(with: event)
    }

    private func ensureInitialHighlight(in menu: NSMenu) {
        guard menu.highlightedItem == nil else { return }

        let arrowValue = UInt32(NSDownArrowFunctionKey)
        guard let scalar = UnicodeScalar(arrowValue) else { return }
        let characters = String(Character(scalar))

        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: -1,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: 125
        ) else { return }

        _ = menu.performKeyEquivalent(with: event)
    }
}



// MARK: - Shared Helpers

fileprivate func resolveDescriptor(
    for column: NSTableColumn,
    from descriptors: [MetadataColumnDescriptor]
) -> MetadataColumnDescriptor? {
    if let resolvedColumn = MetadataColumn(rawValue: column.identifier.rawValue),
       let descriptor = descriptors.first(where: { $0.column == resolvedColumn }) {
        return descriptor
    }

    if let descriptor = descriptors.first(where: { $0.title == column.title }) {
        return descriptor
    }

    let headerTitle = column.headerCell.stringValue
    if let descriptor = descriptors.first(where: { $0.title == headerTitle }) {
        return descriptor
    }

    return nil
}
