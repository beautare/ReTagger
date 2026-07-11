//
//  UpdateAlertView.swift
//  ReTagger
//
//  更新检查弹窗视图：展示版本信息、更新说明，引导跳转 App Store。
//  改进：增加错误状态下的重试按钮，Release Notes 使用富文本渲染。
//

import SwiftUI

struct UpdateAlertView: View {
    @ObservedObject var updateService: AppUpdateService
    @EnvironmentObject var localizationManager: LocalizationManager
    @Environment(\.dismiss) private var dismissSheet

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            switch updateService.updateStatus {
            case .checking:
                checkingView
            case .upToDate(let currentVersion):
                upToDateView(currentVersion: currentVersion)
            case .updateAvailable(let newVersion, let releaseNotes, _):
                updateAvailableView(newVersion: newVersion, releaseNotes: releaseNotes)
            case .error(let message, let retryable):
                errorView(message: message, retryable: retryable)
            case .idle:
                EmptyView()
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: 420)
    }

    // MARK: - 关闭弹窗

    /// 关闭 sheet（状态重置由 onDismiss 回调统一处理）
    private func closeSheet() {
        dismissSheet()
    }

    // MARK: - 检查中

    private var checkingView: some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            ProgressView()
                .scaleEffect(1.2)
            Text(localizationManager.string("update.checking"))
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(height: 100)
    }

    // MARK: - 已是最新版本

    private func upToDateView(currentVersion: String) -> some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundColor(.green)

            Text(localizationManager.string("update.up_to_date"))
                .font(.headline)

            Text(localizationManager.string("update.current_version", arguments: currentVersion))
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button(localizationManager.string("common.got_it")) {
                closeSheet()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - 有新版本可用

    private func updateAvailableView(newVersion: String, releaseNotes: String?) -> some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 40))
                .foregroundColor(.accentColor)

            Text(localizationManager.string("update.available_title"))
                .font(.headline)

            Text(localizationManager.string(
                "update.available_message",
                arguments: newVersion, AppConfiguration.InfoPlist.appVersion
            ))
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)

            // 更新说明（富文本渲染）
            if let notes = releaseNotes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(localizationManager.string("update.release_notes"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    ScrollView {
                        Text(formattedReleaseNotes(notes))
                            .font(.caption)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 180)
                    .padding(DesignSystem.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                }
            }

            // 操作按钮
            HStack(spacing: DesignSystem.Spacing.md) {
                Button(localizationManager.string("update.remind_later")) {
                    closeSheet()
                }
                .buttonStyle(.bordered)

                Button(localizationManager.string("update.go_to_app_store")) {
                    updateService.openAppStore()
                    closeSheet()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - 检查失败

    private func errorView(message: String, retryable: Bool) -> some View {
        VStack(spacing: DesignSystem.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text(localizationManager.string("update.error"))
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: DesignSystem.Spacing.md) {
                Button(localizationManager.string("common.got_it")) {
                    closeSheet()
                }
                .buttonStyle(.bordered)

                if retryable {
                    Button(localizationManager.string("update.retry")) {
                        updateService.retry()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    // MARK: - Release Notes 格式化

    /// 将 App Store 的纯文本 Release Notes 转换为更易读的格式
    private func formattedReleaseNotes(_ text: String) -> AttributedString {
        var result = AttributedString()
        let lines = text.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                // 空行保留为段落分隔
                result.append(AttributedString("\n"))
                continue
            }

            var attributed = AttributedString(trimmed)

            // 以 "- " 或 "• " 开头的行作为列表项，加上圆点前缀
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("• ") {
                let content = String(trimmed.dropFirst(2))
                attributed = AttributedString("  • \(content)")
            }

            result.append(attributed)

            // 非最后一行追加换行
            if index < lines.count - 1 {
                result.append(AttributedString("\n"))
            }
        }

        return result
    }
}
