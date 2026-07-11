//
//  StatusCardView.swift
//  ReTagger
//
//  Reusable status card for success, warning, error states
//

import SwiftUI

/// 状态卡片视图
struct StatusCardView: View {
    enum Style {
        case success
        case warning
        case error
        case info

        var color: Color {
            switch self {
            case .success: return DesignSystem.Colors.success
            case .warning: return DesignSystem.Colors.warning
            case .error: return DesignSystem.Colors.error
            case .info: return DesignSystem.Colors.info
            }
        }

        var backgroundColor: Color {
            switch self {
            case .success: return DesignSystem.Colors.successBackground(0.15)
            case .warning: return DesignSystem.Colors.warningBackground(0.15)
            case .error: return DesignSystem.Colors.errorBackground(0.15)
            case .info: return DesignSystem.Colors.infoBackground(0.15)
            }
        }

        var icon: String {
            switch self {
            case .success: return DesignSystem.Icons.success
            case .warning: return DesignSystem.Icons.warning
            case .error: return DesignSystem.Icons.error
            case .info: return DesignSystem.Icons.info
            }
        }
    }

    let style: Style
    let title: String
    let message: String?
    var dismissAction: (() -> Void)?

    init(style: Style, title: String, message: String? = nil, dismissAction: (() -> Void)? = nil) {
        self.style = style
        self.title = title
        self.message = message
        self.dismissAction = dismissAction
    }

    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
            // 图标
            Image(systemName: style.icon)
                .font(.system(size: 24))
                .foregroundColor(style.color)

            // 内容
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
                Text(title)
                    .font(DesignSystem.Typography.bodyBold)
                    .foregroundColor(DesignSystem.Colors.textPrimary)

                if let message = message {
                    Text(message)
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(DesignSystem.Colors.textSecondary)
                }
            }

            Spacer()

            // 关闭按钮（可选）
            if let dismissAction = dismissAction {
                Button(action: dismissAction) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DesignSystem.Spacing.md)
        .background(style.backgroundColor)
        .cornerRadius(DesignSystem.CornerRadius.md)
    }
}

/// 内联状态标签（小型）
struct StatusBadgeView: View {
    enum Style {
        case success
        case warning
        case error
        case info
        case neutral

        var color: Color {
            switch self {
            case .success: return DesignSystem.Colors.success
            case .warning: return DesignSystem.Colors.warning
            case .error: return DesignSystem.Colors.error
            case .info: return DesignSystem.Colors.info
            case .neutral: return DesignSystem.Colors.textTertiary
            }
        }

        var backgroundColor: Color {
            switch self {
            case .success: return DesignSystem.Colors.successBackground(0.2)
            case .warning: return DesignSystem.Colors.warningBackground(0.2)
            case .error: return DesignSystem.Colors.errorBackground(0.2)
            case .info: return DesignSystem.Colors.infoBackground(0.2)
            case .neutral: return DesignSystem.Colors.backgroundTertiary
            }
        }
    }

    let style: Style
    let text: String
    var icon: String?

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.xxs) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(.system(size: 10))
            }
            Text(text)
                .font(DesignSystem.Typography.caption)
        }
        .padding(.horizontal, DesignSystem.Spacing.xs)
        .padding(.vertical, DesignSystem.Spacing.xxs)
        .background(style.backgroundColor)
        .foregroundColor(style.color)
        .cornerRadius(DesignSystem.CornerRadius.xs)
    }
}

#Preview("Success Card") {
    StatusCardView(
        style: .success,
        title: "处理完成",
        message: "成功处理了 42 个文件",
        dismissAction: {}
    )
    .padding()
    .frame(width: 400)
}

#Preview("Warning Card") {
    StatusCardView(
        style: .warning,
        title: "部分文件处理失败",
        message: "3 个文件因权限问题无法处理，建议检查文件权限"
    )
    .padding()
    .frame(width: 400)
}

#Preview("Error Card") {
    StatusCardView(
        style: .error,
        title: "网络连接失败",
        message: "无法连接到后端服务器，请检查网络设置",
        dismissAction: {}
    )
    .padding()
    .frame(width: 400)
}

#Preview("Info Card") {
    StatusCardView(
        style: .info,
        title: "提示",
        message: "建议先备份文件再进行批量修改操作"
    )
    .padding()
    .frame(width: 400)
}

#Preview("Badges") {
    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
        StatusBadgeView(style: .success, text: "已完成", icon: "checkmark")
        StatusBadgeView(style: .warning, text: "警告", icon: "exclamationmark.triangle")
        StatusBadgeView(style: .error, text: "失败", icon: "xmark")
        StatusBadgeView(style: .info, text: "处理中", icon: "hourglass")
        StatusBadgeView(style: .neutral, text: "未处理", icon: "clock")
    }
    .padding()
}
