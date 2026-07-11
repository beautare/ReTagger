//
//  ProgressBannerView.swift
//  ReTagger
//
//  扫描/恢复过程中的横幅式进度指示
//

import SwiftUI

struct ProgressBannerView: View {
    let message: String
    let progress: Double
    let detail: String?

    init(message: String, progress: Double, detail: String? = nil) {
        self.message = message
        self.progress = progress
        self.detail = detail
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            HStack {
                Text(message)
                    .font(DesignSystem.Typography.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text("\(Int(progress * 100))%")
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
            }

            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)

            if let detail = detail {
                Text(detail)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(DesignSystem.Colors.infoBackground(0.15))
        .animation(DesignSystem.Animation.normal, value: progress)
    }
}
