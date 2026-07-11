//
//  PaneResizeHandle.swift
//  ReTagger
//
//  可拖拽的面板分隔线手柄（支持水平/垂直两个方向）
//  使用 NSView 直接处理鼠标事件，彻底绕过 SwiftUI 手势系统的延迟
//

import SwiftUI
import AppKit

/// 面板拖拽分隔线
///
/// 使用 NSViewRepresentable 嵌入原生 NSView 来处理鼠标拖拽，
/// 避免 SwiftUI DragGesture 与 TapGesture 的冲突和手势识别延迟。
struct PaneResizeHandle: View {
    /// 分隔方向：`.vertical` 为竖直分隔线（左右拖动），`.horizontal` 为水平分隔线（上下拖动）
    enum Axis {
        case vertical
        case horizontal

        var cursor: NSCursor {
            switch self {
            case .vertical: return .resizeLeftRight
            case .horizontal: return .resizeUpDown
            }
        }
    }

    let axis: Axis
    /// 拖拽时持续回调累计偏移量（相对于拖拽起点；水平分隔线为屏幕坐标 Y 偏移，向上为正）
    let onDrag: (CGFloat) -> Void
    /// 拖拽结束时回调
    let onDragEnd: () -> Void
    /// 双击恢复理想尺寸
    let onDoubleTap: () -> Void

    /// 手柄可交互热区厚度
    private let hitAreaThickness: CGFloat = 8
    /// 手柄可见线条厚度
    private let lineThickness: CGFloat = 1

    @State private var isHovering = false
    @State private var isDragging = false

    init(
        axis: Axis = .vertical,
        onDrag: @escaping (CGFloat) -> Void,
        onDragEnd: @escaping () -> Void,
        onDoubleTap: @escaping () -> Void
    ) {
        self.axis = axis
        self.onDrag = onDrag
        self.onDragEnd = onDragEnd
        self.onDoubleTap = onDoubleTap
    }

    var body: some View {
        ZStack {
            // 可见的分隔线
            line

            // 原生拖拽热区（负责光标管理 + 鼠标事件）
            hitArea
        }
        .frame(
            width: axis == .vertical ? hitAreaThickness : nil,
            height: axis == .horizontal ? hitAreaThickness : nil
        )
    }

    @ViewBuilder
    private var line: some View {
        if axis == .vertical {
            Rectangle()
                .fill(lineColor)
                .frame(width: lineThickness)
        } else {
            Rectangle()
                .fill(lineColor)
                .frame(height: lineThickness)
        }
    }

    private var hitArea: some View {
        ResizeHandleNSView(
            axis: axis,
            onHoverChanged: { hovering in
                isHovering = hovering
            },
            onDragStart: {
                isDragging = true
            },
            onDragChanged: { totalDelta in
                onDrag(totalDelta)
            },
            onDragEnded: {
                isDragging = false
                onDragEnd()
            },
            onDoubleTap: onDoubleTap
        )
        .frame(
            width: axis == .vertical ? hitAreaThickness : nil,
            height: axis == .horizontal ? hitAreaThickness : nil
        )
    }

    private var lineColor: Color {
        if isDragging {
            return DesignSystem.Colors.primary.opacity(0.6)
        } else if isHovering {
            return DesignSystem.Colors.primary.opacity(0.4)
        } else {
            return Color(NSColor.separatorColor)
        }
    }
}

// MARK: - 原生 NSView 拖拽处理

/// 使用 NSViewRepresentable 包装的原生拖拽视图，直接接收 mouseDown/Dragged/Up 事件，
/// 实现零延迟、像素级跟踪的面板 resize。
/// 光标完全由 resetCursorRects 管理，AppKit 自动处理 enter/exit，堆栈绝对平衡。
private struct ResizeHandleNSView: NSViewRepresentable {
    let axis: PaneResizeHandle.Axis
    let onHoverChanged: (Bool) -> Void
    let onDragStart: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: () -> Void
    let onDoubleTap: () -> Void

    func makeNSView(context: Context) -> _ResizeHandleView {
        let view = _ResizeHandleView()
        view.axis = axis
        view.onHoverChanged = onHoverChanged
        view.onDragStart = onDragStart
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        view.onDoubleTap = onDoubleTap
        return view
    }

    func updateNSView(_ nsView: _ResizeHandleView, context: Context) {
        if nsView.axis != axis {
            nsView.axis = axis
            // 光标由 resetCursorRects 声明，axis 变化后需让系统重新评估
            nsView.window?.invalidateCursorRects(for: nsView)
        }
        nsView.onHoverChanged = onHoverChanged
        nsView.onDragStart = onDragStart
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
        nsView.onDoubleTap = onDoubleTap
    }
}

/// 实际处理鼠标事件的 NSView 子类
///
/// 光标管理策略：
/// - 使用 `resetCursorRects` + `addCursorRect` 声明整个视图区域使用方向对应的 resize 光标
///   由 AppKit 在鼠标进入/离开时自动 push/pop，保证堆栈永远平衡
/// - 拖拽进行中：调用 `set()` 强制保持 resize 光标（防止被其他视图覆盖）
/// - 拖拽结束：调用 `window.invalidateCursorRects` 让系统重新评估当前位置的光标
private final class _ResizeHandleView: NSView {
    var axis: PaneResizeHandle.Axis = .vertical
    var onHoverChanged: ((Bool) -> Void)?
    var onDragStart: (() -> Void)?
    var onDragChanged: ((CGFloat) -> Void)?
    var onDragEnded: (() -> Void)?
    var onDoubleTap: (() -> Void)?

    /// 拖拽起点在拖动方向上的全局坐标
    private var dragStartCoordinate: CGFloat = 0
    private var isDragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // 开启鼠标进入/离开追踪（用于回调 onHoverChanged 驱动分隔线颜色）
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .inVisibleRect, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 光标声明（AppKit 标准方式，自动平衡 stack）

    override func resetCursorRects() {
        // 在整个视图区域声明 resize 光标
        // AppKit 会在鼠标进入时 push、离开时 pop，堆栈永远平衡
        addCursorRect(bounds, cursor: axis.cursor)
    }

    // MARK: - Hover 追踪（仅用于分隔线颜色）

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged?(false)
    }

    // MARK: - 鼠标拖拽

    override func mouseDown(with event: NSEvent) {
        // 双击检测：NSEvent.clickCount == 2 直接触发，无需等待手势超时
        if event.clickCount == 2 {
            onDoubleTap?()
            return
        }

        // 记录拖拽起点（全局屏幕坐标）
        guard let screenPoint = screenPoint(for: event) else { return }
        dragStartCoordinate = coordinate(of: screenPoint)
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let screenPoint = screenPoint(for: event) else { return }

        if !isDragging {
            isDragging = true
            // 拖拽中强制保持 resize 光标，防止鼠标移出热区时被其他视图的 cursorRect 覆盖
            axis.cursor.set()
            onDragStart?()
        }

        // 基于全局坐标的增量，不受视图自身移动影响
        let totalDelta = coordinate(of: screenPoint) - dragStartCoordinate
        onDragChanged?(totalDelta)
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false
        // 通知系统重新评估当前鼠标位置的 cursorRect，恢复正确光标
        // 若鼠标仍在本视图内 → resize 光标；若已移出 → 系统默认箭头
        window?.invalidateCursorRects(for: self)
        onDragEnded?()
    }

    private func screenPoint(for event: NSEvent) -> NSPoint? {
        window?.convertPoint(toScreen: event.locationInWindow)
    }

    private func coordinate(of point: NSPoint) -> CGFloat {
        axis == .vertical ? point.x : point.y
    }
}
