//
//  NativeSidebarSplitView.swift
//  ReTagger
//
//  基于 NSSplitView 的左侧侧边栏拖拽组件，用于解决 SwiftUI State 驱动带来的拖动卡顿问题
//

import SwiftUI
import AppKit

private enum SidebarCollapseConstants {
    /// 展开宽度的持久化键，与 NSSplitView 的 autosave 分开存储：
    /// autosave 记录的是"当前"位置（折叠后即为迷你宽度），这里记录的是"折叠前"宽度
    static let expandedWidthKey = "SidebarExpandedWidth"
    static let animationDuration: TimeInterval = 0.22
}

/// 左侧侧边栏容器。
///
/// 手势语义严格分离：拖动分隔条只改变宽度（下限为 `sidebarMinWidth`，永不折叠），
/// 折叠交由侧边栏按钮与 ⌘⌃S 显式触发。折叠时记住展开宽度，展开后原样恢复。
/// 折叠态下分隔条完全锁死——拖动热区归零、光标不变形，只能点图标恢复。
struct NativeSidebarSplitView<Sidebar: View, Detail: View>: NSViewRepresentable {
    struct Configuration {
        let sidebarMinWidth: CGFloat
        let sidebarDefaultFraction: CGFloat // 初始宽度占总宽度的比例
        let sidebarMiniWidth: CGFloat
        /// 右侧详情区的最小宽度，决定侧边栏可拖动的上限
        let detailMinWidth: CGFloat
        let dividerWidth: CGFloat
    }

    let configuration: Configuration
    /// 折叠状态，由外部持久化
    let isCollapsed: Bool
    /// 折叠动画期间锁定侧边栏内容的布局宽度，避免内容在动画中反复重排
    let setLayoutWidth: (CGFloat?) -> Void
    let sidebar: Sidebar
    let detail: Detail

    func makeCoordinator() -> Coordinator {
        Coordinator(configuration: configuration)
    }

    func makeNSView(context: Context) -> SidebarSplitViewClass {
        let splitView = SidebarSplitViewClass()
        splitView.isVertical = true
        splitView.dividerStyle = .paneSplitter
        splitView.customDividerThickness = configuration.dividerWidth
        splitView.translatesAutoresizingMaskIntoConstraints = false
        // 自动保存分隔条位置
        splitView.autosaveName = "MainSidebarSplitView"

        splitView.onDoubleTapDivider = { [weak coordinator = context.coordinator] in
            coordinator?.resetToDefaultWidth()
        }

        context.coordinator.attach(splitView: splitView, sidebar: sidebar, detail: detail)
        return splitView
    }

    func updateNSView(_ splitView: SidebarSplitViewClass, context: Context) {
        context.coordinator.configuration = configuration
        context.coordinator.setLayoutWidth = setLayoutWidth
        context.coordinator.updateContent(sidebar: sidebar, detail: detail)
        context.coordinator.applyCollapsed(isCollapsed)
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        var configuration: Configuration
        var setLayoutWidth: (CGFloat?) -> Void = { _ in }

        private weak var splitView: SidebarSplitViewClass?
        private var sidebarHostingView: NSHostingView<AnyView>?
        private var detailHostingView: NSHostingView<AnyView>?
        private var hasAppliedInitialWidth = false
        private var hasSyncedInitialCollapse = false
        private var isCollapsed = false

        init(configuration: Configuration) {
            self.configuration = configuration
        }

        func attach(splitView: SidebarSplitViewClass, sidebar: Sidebar, detail: Detail) {
            let leftView = AnyView(sidebar)
            let rightView = AnyView(detail)

            if self.splitView !== splitView {
                self.splitView = splitView
                hasAppliedInitialWidth = false
                splitView.delegate = self
            }

            if sidebarHostingView == nil || sidebarHostingView?.superview != splitView {
                let hosting = NSHostingView(rootView: leftView)
                hosting.translatesAutoresizingMaskIntoConstraints = false
                hosting.setContentHuggingPriority(.defaultLow, for: .horizontal)
                hosting.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                splitView.addArrangedSubview(hosting)
                sidebarHostingView = hosting
            } else {
                sidebarHostingView?.rootView = leftView
            }

            if detailHostingView == nil || detailHostingView?.superview != splitView {
                let hosting = NSHostingView(rootView: rightView)
                hosting.translatesAutoresizingMaskIntoConstraints = false
                hosting.setContentHuggingPriority(.defaultLow, for: .horizontal)
                hosting.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                splitView.addArrangedSubview(hosting)
                detailHostingView = hosting
            } else {
                detailHostingView?.rootView = rightView
            }

            DispatchQueue.main.async { [weak self] in
                self?.applyInitialWidthIfNeeded()
            }
        }

        private func applyInitialWidthIfNeeded() {
            guard let splitView = splitView, !hasAppliedInitialWidth else { return }
            guard splitView.bounds.width > 0, splitView.subviews.count >= 2 else {
                DispatchQueue.main.async { [weak self] in
                    self?.applyInitialWidthIfNeeded()
                }
                return
            }

            hasAppliedInitialWidth = true

            let defaultsKey = "NSSplitView Subview Frames MainSidebarSplitView"
            if UserDefaults.standard.string(forKey: defaultsKey) == nil {
                splitView.setPosition(defaultExpandedWidth(), ofDividerAt: 0)
            }
        }

        func updateContent(sidebar: Sidebar, detail: Detail) {
            sidebarHostingView?.rootView = AnyView(sidebar)
            detailHostingView?.rootView = AnyView(detail)
        }

        deinit {
            splitView?.delegate = nil
        }

        // MARK: - 折叠

        /// 同步外部折叠状态。首次调用只对齐标志位——此时 autosave 已经把分隔条恢复到
        /// 上次退出的位置，再跑一遍动画会造成启动时的可见跳动。
        func applyCollapsed(_ collapsed: Bool) {
            guard hasSyncedInitialCollapse else {
                hasSyncedInitialCollapse = true
                isCollapsed = collapsed
                if collapsed {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, let splitView = self.splitView else { return }
                        splitView.setPosition(self.configuration.sidebarMiniWidth, ofDividerAt: 0)
                    }
                }
                return
            }

            guard collapsed != isCollapsed else { return }
            isCollapsed = collapsed

            if collapsed {
                persistExpandedWidth(currentSidebarWidth())
                // 折叠：内容维持展开态布局并被容器裁切，像抽屉一样收进去
                animatePosition(to: configuration.sidebarMiniWidth, lockedLayoutWidth: currentSidebarWidth())
            } else {
                // 展开：内容先按目标宽度排好版，再把容器拉开，避免在 56pt 里挤压重排
                let target = targetExpandedWidth()
                animatePosition(to: target, lockedLayoutWidth: target)
            }
        }

        /// 双击分隔条恢复默认宽度
        func resetToDefaultWidth() {
            guard let splitView = splitView, !isCollapsed else { return }
            splitView.setPosition(defaultExpandedWidth(), ofDividerAt: 0)
        }

        private func animatePosition(to target: CGFloat, lockedLayoutWidth: CGFloat) {
            setLayoutWidth(lockedLayoutWidth)
            // 让 SwiftUI 先按锁定宽度提交一帧，再开始容器动画
            DispatchQueue.main.async { [weak self] in
                guard let self, let splitView = self.splitView else { return }
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = SidebarCollapseConstants.animationDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    splitView.animator().setPosition(target, ofDividerAt: 0)
                }, completionHandler: { [weak self] in
                    self?.setLayoutWidth(nil)
                })
            }
        }

        private func currentSidebarWidth() -> CGFloat {
            guard let splitView = splitView, splitView.subviews.count >= 2 else {
                return configuration.sidebarMinWidth
            }
            return splitView.subviews[0].frame.width
        }

        private func maxSidebarWidth() -> CGFloat {
            guard let splitView = splitView, splitView.bounds.width > 0 else {
                return configuration.sidebarMinWidth
            }
            return max(configuration.sidebarMiniWidth, splitView.bounds.width - configuration.detailMinWidth)
        }

        private func defaultExpandedWidth() -> CGFloat {
            let totalWidth = splitView?.bounds.width ?? 0
            let ideal = max(configuration.sidebarMinWidth, totalWidth * configuration.sidebarDefaultFraction)
            return min(ideal, maxSidebarWidth())
        }

        private func targetExpandedWidth() -> CGFloat {
            let stored = UserDefaults.standard.object(forKey: SidebarCollapseConstants.expandedWidthKey) as? Double
            let base = stored.map { CGFloat($0) } ?? defaultExpandedWidth()
            return min(max(base, configuration.sidebarMinWidth), maxSidebarWidth())
        }

        private func persistExpandedWidth(_ width: CGFloat) {
            guard width > configuration.sidebarMiniWidth else { return }
            UserDefaults.standard.set(Double(width), forKey: SidebarCollapseConstants.expandedWidthKey)
        }

        // MARK: - NSSplitViewDelegate

        func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            guard dividerIndex == 0, splitView.bounds.width > 0 else { return proposedPosition }
            // 折叠态钉死在迷你宽度，展开只能靠图标按钮或 ⌘⌃S
            guard !isCollapsed else { return configuration.sidebarMiniWidth }

            let clamped = min(max(proposedPosition, configuration.sidebarMinWidth), maxSidebarWidth())
            persistExpandedWidth(clamped)
            return clamped
        }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            guard dividerIndex == 0 else { return proposedMinimumPosition }
            // 展开态的下限就是标准最小宽度，从根本上杜绝拖动误折叠；
            // 折叠态上下限同为迷你宽度，可拖动区间为零。
            return isCollapsed ? configuration.sidebarMiniWidth : configuration.sidebarMinWidth
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            guard dividerIndex == 0 else { return proposedMaximumPosition }
            return isCollapsed ? configuration.sidebarMiniWidth : maxSidebarWidth()
        }

        /// 折叠态把分隔条的拖动热区归零：鼠标移上去不会变成左右箭头，也拖不动。
        /// 仅靠 constrain 系列只能限制结果位置，光标与按下反馈仍在，看着像"坏了"。
        func splitView(_ splitView: NSSplitView, effectiveRect proposedEffectiveRect: NSRect, forDrawnRect drawnRect: NSRect, ofDividerAt dividerIndex: Int) -> NSRect {
            guard dividerIndex == 0, isCollapsed else { return proposedEffectiveRect }
            return .zero
        }
    }
}

final class SidebarSplitViewClass: NSSplitView {
    var customDividerThickness: CGFloat = 1.0 {
        didSet { needsDisplay = true }
    }

    var onDoubleTapDivider: (() -> Void)?

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

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            let location = convert(event.locationInWindow, from: nil)
            let dividersCount = arrangedSubviews.count - 1
            for i in 0..<dividersCount {
                let leftView = arrangedSubviews[i]
                let rect = NSRect(x: leftView.frame.maxX, y: bounds.minY, width: dividerThickness, height: bounds.height)
                let clickRect = rect.insetBy(dx: -4, dy: 0)
                if clickRect.contains(location) {
                    onDoubleTapDivider?()
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }
}
