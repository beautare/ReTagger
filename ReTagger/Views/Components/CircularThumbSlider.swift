//
//  CircularThumbSlider.swift
//  ReTagger
//
//  正圆形 thumb 的自定义进度滑块，用于替换系统默认的药丸形滑块
//

import SwiftUI

struct CircularThumbSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double>
    var onEditingChanged: ((Bool) -> Void)?
    var tintColor: Color = DesignSystem.Colors.accent.opacity(0.75)
    var isDisabled: Bool = false

    // 正圆 thumb 直径
    private let thumbDiameter: CGFloat = 16
    // 轨道高度
    private let trackHeight: CGFloat = 4

    @State private var isDragging = false
    /// 拖拽期间的本地锚定值，用于在 seek 完成前保持 thumb 位置，避免跳动
    @State private var dragAnchor: Double?

    /// 渲染用的显示值：优先使用本地锚定值，否则使用外部绑定
    private var displayValue: Double {
        dragAnchor ?? value
    }

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let usableWidth = totalWidth - thumbDiameter
            let span = range.upperBound - range.lowerBound
            let fraction = span > 0 ? (displayValue - range.lowerBound) / span : 0
            let clampedFraction = max(0, min(1, fraction))
            let thumbCenterX = thumbDiameter / 2 + usableWidth * clampedFraction

            ZStack(alignment: .leading) {
                // 轨道背景
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: trackHeight)
                    .frame(maxWidth: .infinity)

                // 已播放进度
                Capsule()
                    .fill(tintColor)
                    .frame(width: max(0, thumbCenterX), height: trackHeight)

                // 正圆形 thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                    .offset(x: thumbCenterX - thumbDiameter / 2)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged?(true)
                        }
                        let newFraction = (gesture.location.x - thumbDiameter / 2) / usableWidth
                        let clampedNewFraction = max(0, min(1, newFraction))
                        let newValue = range.lowerBound + span * clampedNewFraction
                        dragAnchor = newValue
                        value = newValue
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged?(false)
                        // 不立即清除 dragAnchor，给 seek 时间完成
                        // 在 seek 过渡期间保持 thumb 停在目标位置
                        let anchoredValue = dragAnchor
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            guard !isDragging, dragAnchor == anchoredValue else { return }
                            dragAnchor = nil
                        }
                    }
            )
            .allowsHitTesting(!isDisabled)
        }
        .frame(height: thumbDiameter)
        .opacity(isDisabled ? 0.4 : 1)
    }
}
