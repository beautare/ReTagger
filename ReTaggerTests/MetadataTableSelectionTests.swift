import AppKit
import XCTest
@testable import ReTagger

@MainActor
final class MetadataTableSelectionTests: XCTestCase {
    private class TestWindow: NSWindow {
        override var isKeyWindow: Bool { true }
    }

    func testSelectedRowCreatedBeforeWindowAttachment() throws {
        let controller = MetadataTableViewController()
        controller.files = [AudioMetadata(
            filePath: URL(fileURLWithPath: "/tmp/selection-test/track.wav"),
            fileName: "track.wav"
        )]
        let table = NSTableView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(MetadataColumn.fileName.rawValue))
        table.addTableColumn(column)
        table.delegate = controller
        table.dataSource = controller
        table.reloadData()
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        let row = try XCTUnwrap(table.rowView(atRow: 0, makeIfNecessary: true))
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? MetadataTableCellView)
        XCTAssertNil(row.window)
        XCTAssertEqual(cell.backgroundStyle, .normal)

        let window = TestWindow(
            contentRect: table.frame, styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = table
        defer { window.close() }
        XCTAssertTrue(row.isSelected)
        XCTAssertEqual(row.interiorBackgroundStyle, .emphasized)

        // 复现滚动中行先生成、再挂载窗口的时序，调用真实的挂载回调。
        controller.tableView(table, didAdd: row, forRow: 0)
        XCTAssertEqual(cell.backgroundStyle, .emphasized)
        let label = try XCTUnwrap(cell.subviews.compactMap { $0 as? NSTextField }.first)
        XCTAssertEqual(
            label.attributedStringValue.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor,
            .alternateSelectedControlTextColor
        )
    }

    func testSelectionColorsSurviveScrollingAndReuse() throws {
        let controller = MetadataTableViewController()
        let window = TestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = controller.view
        defer { window.close() }

        let scrollView = try XCTUnwrap(controller.view as? NSScrollView)
        let table = try XCTUnwrap(scrollView.documentView as? NSTableView)
        scrollView.frame = window.contentLayoutRect
        let files = (0..<300).map { index in
            var file = AudioMetadata(
                filePath: URL(fileURLWithPath: "/tmp/selection-test/\(index).wav"),
                fileName: "\(index).wav", originalTitle: "Original \(index)"
            )
            file.correctedTitle = "Corrected \(index)"
            return file
        }
        let configuration = TableColumnConfiguration(
            visibleColumns: [.fileName, .title], columnOrder: [.fileName, .title]
        )
        controller.update(
            files: files, selection: Set(files.map(\.id)), sortOrder: [],
            columnConfiguration: configuration, scrollTo: nil, searchText: ""
        )

        // 全选后滚动：覆盖新建行，以及进入/离开可视区域后的复用行。
        for row in [0, 30, 100, 200, 290, 0, 290, 10, 0] {
            table.scrollRowToVisible(row)
            assertVisibleSelectionStyles(in: table)
        }

        // 模拟侧边栏单曲定位，再滚出/滚回选中曲目。
        controller.update(
            files: files, selection: [files[150].id], sortOrder: [],
            columnConfiguration: configuration, scrollTo: files[150].id, searchText: ""
        )
        for row in [150, 0, 150, 290, 150] {
            table.scrollRowToVisible(row)
            assertVisibleSelectionStyles(in: table)
        }
        XCTAssertEqual(table.selectedRowIndexes, IndexSet(integer: 150))
    }

    private func assertVisibleSelectionStyles(
        in table: NSTableView, file: StaticString = #filePath, line: UInt = #line
    ) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        table.layoutSubtreeIfNeeded()
        let visible = table.rows(in: table.visibleRect)
        XCTAssertNotEqual(visible.location, NSNotFound, file: file, line: line)
        XCTAssertGreaterThan(visible.length, 0, file: file, line: line)
        guard visible.location != NSNotFound else { return }
        for rowIndex in visible.location..<min(visible.location + visible.length, table.numberOfRows) {
            guard let row = table.rowView(atRow: rowIndex, makeIfNecessary: true) else {
                XCTFail("Missing row \(rowIndex)", file: file, line: line)
                continue
            }
            let expected: NSView.BackgroundStyle = row.isSelected ? .emphasized : .normal
            for column in 0..<table.numberOfColumns {
                guard let cell = table.view(atColumn: column, row: rowIndex, makeIfNecessary: true) as? MetadataTableCellView else { continue }
                XCTAssertEqual(cell.backgroundStyle, expected, "row \(rowIndex)", file: file, line: line)
                // 同时检查主文本和 AI 修正前的第二行文本。
                for label in cell.subviews.compactMap({ $0 as? NSTextField }) where !label.isHidden {
                    let text = label.attributedStringValue
                    XCTAssertGreaterThan(text.length, 0, file: file, line: line)
                    guard text.length > 0 else { continue }
                    let color = text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
                    if row.isSelected {
                        XCTAssertEqual(color, .alternateSelectedControlTextColor, "row \(rowIndex)", file: file, line: line)
                    } else {
                        XCTAssertNotEqual(color, .alternateSelectedControlTextColor, "row \(rowIndex)", file: file, line: line)
                    }
                }
            }
        }
    }
}
