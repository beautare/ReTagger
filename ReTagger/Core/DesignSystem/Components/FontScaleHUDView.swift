//
//  FontScaleHUDView.swift
//  ReTagger
//
//  曲目表格文字大小调整时的标尺式 HUD：直观展示当前档位在全部档位中的位置
//

import SwiftUI

struct FontScaleHUDView: View {
    let scale: MetadataTableFontScale
    @EnvironmentObject private var localizationManager: LocalizationManager

    private let allCases = MetadataTableFontScale.allCases
    private let minBarHeight: CGFloat = 8
    private let maxBarHeight: CGFloat = 26

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(allCases) { step in
                    Capsule()
                        .fill(step == scale ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 14, height: barHeight(for: step))
                }
            }
            .frame(height: maxBarHeight, alignment: .bottom)

            Text(localizationManager.string(scale.localizationKey))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.72))
        )
    }

    private func barHeight(for step: MetadataTableFontScale) -> CGFloat {
        let fraction = CGFloat(step.rawValue) / CGFloat(allCases.count - 1)
        return minBarHeight + fraction * (maxBarHeight - minBarHeight)
    }
}
