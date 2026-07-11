//
//  ColumnConfigurationPopover.swift
//  ReTagger
//
//  Created by Claude Code
//

import AppKit
import SwiftUI

/// NSPopover 管理器：桥接 AppKit 和 SwiftUI 列配置视图
class ColumnConfigurationPopover {
    private var popover: NSPopover?

    /// 显示列配置 Popover
    /// - Parameters:
    ///   - view: 相对定位的视图（通常是表头视图）
    ///   - configuration: 当前的列配置
    ///   - columnDescriptors: 列描述符数组
    ///   - onSave: 保存回调，返回更新后的配置
    func show(
        relativeTo view: NSView,
        configuration: TableColumnConfiguration,
        columnDescriptors: [MetadataColumnDescriptor],
        localizationManager: LocalizationManager,
        onSave: @escaping (TableColumnConfiguration) -> Void
    ) {
        // 如果已经有打开的 Popover，先关闭
        if popover?.isShown == true {
            popover?.performClose(nil)
        }

        // 创建可变的配置绑定
        var currentConfiguration = configuration

        // 创建 SwiftUI 视图
        let contentView = ColumnConfigurationView(
            configuration: Binding(
                get: { currentConfiguration },
                set: { currentConfiguration = $0 }
            ),
            columnDescriptors: columnDescriptors,
            onSave: { [weak self] newConfig in
                onSave(newConfig)
                self?.close()
            }
        ).environmentObject(localizationManager)

        // 包装为 NSViewController
        let hostingController = NSHostingController(rootView: contentView)

        // 创建 Popover
        let popover = NSPopover()
        popover.contentViewController = hostingController
        popover.behavior = .semitransient // 点击外部关闭，但允许内部交互
        popover.animates = true

        // 显示在视图下方
        popover.show(
            relativeTo: view.bounds,
            of: view,
            preferredEdge: .minY
        )

        self.popover = popover
    }

    /// 关闭 Popover
    func close() {
        popover?.performClose(nil)
        popover = nil
    }
}
