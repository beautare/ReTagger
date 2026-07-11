//
//  InlineDetailSplitView.swift
//  ReTagger
//
//  NSSplitView-backed container for the metadata表格与详情面板
//

import SwiftUI
import AppKit

struct InlineDetailSplitView<Left: View, Right: View>: NSViewRepresentable {
    struct Configuration {
        let tableMinWidth: CGFloat
        let detailMinWidth: CGFloat
        let detailDefaultWidth: CGFloat
        let dividerWidth: CGFloat
        /// 外部传入的恢复宽度（右栏绝对宽度），优先于默认值
        var restoredDetailWidth: CGFloat?
    }

    let configuration: Configuration
    let left: Left
    let right: Right
    /// 当 divider 位置变化时，回调右栏绝对宽度
    var onDetailWidthChanged: ((CGFloat) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(configuration: configuration, onDetailWidthChanged: onDetailWidthChanged)
    }

    func makeNSView(context: Context) -> DetailSplitView {
        let splitView = DetailSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .paneSplitter
        splitView.customDividerThickness = configuration.dividerWidth
        splitView.translatesAutoresizingMaskIntoConstraints = false
        // 不再使用 autosaveName，由外部 @State 管理宽度记忆
        context.coordinator.attach(splitView: splitView, left: left, right: right)
        return splitView
    }

    func updateNSView(_ splitView: DetailSplitView, context: Context) {
        // 同步回调
        context.coordinator.onDetailWidthChanged = onDetailWidthChanged
        // 仅更新 hosting view 的内容，不重建视图结构
        context.coordinator.updateContent(left: left, right: right)
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        private let configuration: Configuration
        private weak var splitView: DetailSplitView?
        private var leftHostingView: NSHostingView<AnyView>?
        private var rightHostingView: NSHostingView<AnyView>?
        private var hasAppliedInitialWidth = false
        private var isSystemResizing = false
        /// 初始宽度应用的重试计数：视图长期宽度为 0（如始终不可见）时停止自旋
        private var initialWidthRetryCount = 0
        private let maxInitialWidthRetries = 60
        var onDetailWidthChanged: ((CGFloat) -> Void)?

        init(configuration: Configuration, onDetailWidthChanged: ((CGFloat) -> Void)?) {
            self.configuration = configuration
            self.onDetailWidthChanged = onDetailWidthChanged
        }

        func attach(splitView: DetailSplitView, left: Left, right: Right) {
            let leftView = AnyView(left)
            let rightView = AnyView(right)

            if self.splitView !== splitView {
                self.splitView = splitView
                hasAppliedInitialWidth = false
                splitView.delegate = self
                splitView.onDividerDragEnded = { [weak self, weak splitView] in
                    guard let self, let splitView, self.hasAppliedInitialWidth else { return }
                    self.reportDetailWidth(of: splitView)
                }
            }

            if leftHostingView == nil || leftHostingView?.superview != splitView {
                let hosting = NSHostingView(rootView: leftView)
                hosting.translatesAutoresizingMaskIntoConstraints = false
                hosting.setContentHuggingPriority(.defaultLow, for: .horizontal)
                hosting.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                splitView.addArrangedSubview(hosting)
                leftHostingView = hosting
            } else {
                leftHostingView?.rootView = leftView
            }

            if rightHostingView == nil || rightHostingView?.superview != splitView {
                let hosting = NSHostingView(rootView: rightView)
                hosting.translatesAutoresizingMaskIntoConstraints = false
                hosting.setContentHuggingPriority(.defaultLow, for: .horizontal)
                hosting.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                splitView.addArrangedSubview(hosting)
                rightHostingView = hosting
            } else {
                rightHostingView?.rootView = rightView
            }

            DispatchQueue.main.async { [weak self] in
                self?.applyInitialWidthIfNeeded()
            }
        }

        /// 轻量级更新：仅刷新已有 hosting view 的 rootView，不触发视图结构重建
        func updateContent(left: Left, right: Right) {
            leftHostingView?.rootView = AnyView(left)
            rightHostingView?.rootView = AnyView(right)
        }

        deinit {
            splitView?.delegate = nil
        }

        private func applyInitialWidthIfNeeded() {
            guard
                let splitView,
                !hasAppliedInitialWidth,
                splitView.bounds.width > 0,
                splitView.subviews.count >= 2
            else {
                if let splitView, splitView.bounds.width == 0,
                   initialWidthRetryCount < maxInitialWidthRetries {
                    initialWidthRetryCount += 1
                    DispatchQueue.main.async { [weak self] in
                        self?.applyInitialWidthIfNeeded()
                    }
                }
                return
            }

            isSystemResizing = true
            hasAppliedInitialWidth = true

            let divider = splitView.dividerThickness
            let totalWidth = splitView.bounds.width
            let availableDetail = max(totalWidth - configuration.tableMinWidth - divider, 0)
            let minDetail = min(configuration.detailMinWidth, availableDetail)

            // 优先使用外部传入的恢复宽度，其次使用默认宽度
            let targetWidth = configuration.restoredDetailWidth ?? configuration.detailDefaultWidth
            let desiredDetail = min(max(targetWidth, minDetail), availableDetail)
            let tableWidth = totalWidth - divider - desiredDetail
            splitView.setPosition(tableWidth, ofDividerAt: 0)

            DispatchQueue.main.async { [weak self] in
                self?.isSystemResizing = false
            }
        }

        // MARK: - NSSplitViewDelegate

        func splitView(_ splitView: NSSplitView, resizeSubviewsWithOldSize oldSize: NSSize) {
            isSystemResizing = true
            defer { isSystemResizing = false }

            let totalWidth = splitView.bounds.width
            let divider = splitView.dividerThickness
            let subviews = splitView.subviews
            guard subviews.count >= 2 else {
                splitView.adjustSubviews()
                return
            }

            let left = subviews[0]
            let right = subviews[1]

            // 窗口 resize 时，我们倾向于保持右侧详情栏的绝对宽度不变，左侧表格宽度自适应
            let rightWidth = right.frame.width
            let leftWidth = totalWidth - divider - rightWidth

            let minLeft = configuration.tableMinWidth
            let minRight = configuration.detailMinWidth

            var finalLeftWidth = leftWidth
            var finalRightWidth = rightWidth

            if finalLeftWidth < minLeft {
                finalLeftWidth = minLeft
                finalRightWidth = totalWidth - divider - minLeft
            }

            if finalRightWidth < minRight {
                // 空间不足以同时满足两侧最小宽度时，优先保证左侧表格的最小宽度，
                // 右侧详情栏允许被压缩到可用剩余空间（≥0），避免互相覆盖导致表格被裁切
                let maxRight = max(totalWidth - divider - minLeft, 0)
                finalRightWidth = min(minRight, maxRight)
                finalLeftWidth = totalWidth - divider - finalRightWidth
            }

            left.frame = NSRect(x: 0, y: 0, width: max(0, finalLeftWidth), height: splitView.bounds.height)
            right.frame = NSRect(x: max(0, finalLeftWidth + divider), y: 0, width: max(0, finalRightWidth), height: splitView.bounds.height)
        }

        func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            guard dividerIndex == 0 else { return proposedPosition }
            return clampedLeftWidth(for: splitView, proposedLeftWidth: proposedPosition)
        }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            guard dividerIndex == 0 else { return proposedMinimumPosition }
            // divider 的最小坐标就是左侧面板(table)的最小宽度
            return max(proposedMinimumPosition, configuration.tableMinWidth)
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            guard dividerIndex == 0 else { return proposedMaximumPosition }
            // divider 的最大坐标就是总宽度减去右侧面板(detail)的最小宽度和分隔条宽度
            let totalWidth = splitView.bounds.width
            let divider = splitView.dividerThickness
            return min(proposedMaximumPosition, totalWidth - divider - configuration.detailMinWidth)
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard let splitView = notification.object as? DetailSplitView,
                  splitView.subviews.count >= 2,
                  hasAppliedInitialWidth,
                  !isSystemResizing,
                  // 拖拽进行中不回写宽度，避免每帧触发 SwiftUI 状态更新与 hosting view 重建；
                  // 最终宽度由 onDividerDragEnded 一次性上报
                  !splitView.isDraggingDivider else { return }

            reportDetailWidth(of: splitView)
        }

        /// 将右栏当前宽度上报给外部状态（过滤极端垃圾数据）
        fileprivate func reportDetailWidth(of splitView: NSSplitView) {
            guard splitView.subviews.count >= 2 else { return }
            let rightWidth = splitView.subviews[1].frame.width
            if rightWidth >= configuration.detailMinWidth * 0.9 {
                onDetailWidthChanged?(rightWidth)
            }
        }

        private func clampedLeftWidth(for splitView: NSSplitView, proposedLeftWidth: CGFloat) -> CGFloat {
            guard splitView.subviews.count >= 2 else { return proposedLeftWidth }
            let divider = splitView.dividerThickness
            let totalWidth = splitView.bounds.width
            guard totalWidth > 0 else { return proposedLeftWidth }

            let availableDetail = max(totalWidth - configuration.tableMinWidth - divider, 0)
            let minDetail = min(configuration.detailMinWidth, availableDetail)
            let maxDetail = availableDetail

            let proposedDetail = totalWidth - divider - proposedLeftWidth
            let clampedDetail = min(max(proposedDetail, minDetail), maxDetail)
            let sanitized = totalWidth - divider - clampedDetail
            return max(sanitized, configuration.tableMinWidth)
        }
    }
}

final class DetailSplitView: NSSplitView {
    var customDividerThickness: CGFloat = DesignSystem.Layout.detailPanelDragHandleWidth {
        didSet { needsDisplay = true }
    }

    /// 分隔条拖拽是否进行中。NSSplitView 的 divider 拖拽在 mouseDown 的
    /// 跟踪循环内完成，super.mouseDown 返回即拖拽结束。
    private(set) var isDraggingDivider = false
    /// 拖拽结束回调，用于一次性上报最终分栏宽度
    var onDividerDragEnded: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        isDraggingDivider = true
        super.mouseDown(with: event)
        isDraggingDivider = false
        onDividerDragEnded?()
    }

    override var dividerThickness: CGFloat {
        customDividerThickness
    }

    override func drawDivider(in rect: NSRect) {
        NSColor.clear.setFill()
        rect.fill()

        let lineWidth = max(1.0, 1.0 / (window?.backingScaleFactor ?? 1.0))
        let x = rect.midX - lineWidth / 2.0
        let lineRect = NSRect(x: floor(x), y: rect.minY, width: lineWidth, height: rect.height)
        NSColor.separatorColor.setFill()
        lineRect.fill()
    }
}
