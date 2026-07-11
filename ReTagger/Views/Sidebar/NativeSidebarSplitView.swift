//
//  NativeSidebarSplitView.swift
//  ReTagger
//
//  基于 NSSplitView 的左侧侧边栏拖拽组件，用于解决 SwiftUI State 驱动带来的拖动卡顿问题
//

import SwiftUI
import AppKit

struct NativeSidebarSplitView<Sidebar: View, Detail: View>: NSViewRepresentable {
    struct Configuration {
        let sidebarMinWidth: CGFloat
        let sidebarMaxWidthFraction: CGFloat // 侧边栏最大宽度比例，通常为 0.4
        let sidebarDefaultFraction: CGFloat // 初始宽度占总宽度的比例
        let sidebarMiniWidth: CGFloat
        let sidebarCollapseThreshold: CGFloat
        let dividerWidth: CGFloat
    }

    let configuration: Configuration
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

        splitView.onDoubleTapDivider = { [weak splitView] in
            guard let splitView = splitView else { return }
            let totalWidth = splitView.bounds.width
            let defaultWidth = max(configuration.sidebarMinWidth, totalWidth * configuration.sidebarDefaultFraction)
            splitView.setPosition(defaultWidth, ofDividerAt: 0)
        }

        context.coordinator.attach(splitView: splitView, sidebar: sidebar, detail: detail)
        return splitView
    }

    func updateNSView(_ splitView: SidebarSplitViewClass, context: Context) {
        context.coordinator.updateContent(sidebar: sidebar, detail: detail)
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        private let configuration: Configuration
        private weak var splitView: SidebarSplitViewClass?
        private var sidebarHostingView: NSHostingView<AnyView>?
        private var detailHostingView: NSHostingView<AnyView>?
        private var hasAppliedInitialWidth = false

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
                let totalWidth = splitView.bounds.width
                let defaultWidth = max(configuration.sidebarMinWidth, totalWidth * configuration.sidebarDefaultFraction)
                splitView.setPosition(defaultWidth, ofDividerAt: 0)
            }
        }

        func updateContent(sidebar: Sidebar, detail: Detail) {
            sidebarHostingView?.rootView = AnyView(sidebar)
            detailHostingView?.rootView = AnyView(detail)
        }

        deinit {
            splitView?.delegate = nil
        }

        func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            guard dividerIndex == 0 else { return proposedPosition }
            
            let totalWidth = splitView.bounds.width
            guard totalWidth > 0 else { return proposedPosition }
            
            let minWidth = configuration.sidebarMinWidth
            let miniWidth = configuration.sidebarMiniWidth
            let collapseThreshold = configuration.sidebarCollapseThreshold
            // 移除硬编码的 maxWidth 限制，给予拖拽完全自由，右侧面板如果设了 minWidth 会由 NSSplitView 自动处理约束冲突，为了安全留出 100 的右侧最小空间
            let maxWidth = totalWidth - 100 
            
            let currentWidth = splitView.subviews[0].frame.width
            let isCurrentlyMini = currentWidth < collapseThreshold

            if isCurrentlyMini {
                if proposedPosition >= minWidth {
                    return minWidth
                } else {
                    return miniWidth
                }
            } else {
                if proposedPosition < collapseThreshold {
                    return miniWidth
                } else {
                    return max(minWidth, min(proposedPosition, maxWidth))
                }
            }
        }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            guard dividerIndex == 0 else { return proposedMinimumPosition }
            // 必须返回 miniWidth 作为绝对最小坐标，否则在拖拽时 constrainSplitPosition 无法将其吸附到 miniWidth，导致迷你模式失效
            return configuration.sidebarMiniWidth
        }
        
        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            guard dividerIndex == 0 else { return proposedMaximumPosition }
            let totalWidth = splitView.bounds.width
            return totalWidth - 100
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
