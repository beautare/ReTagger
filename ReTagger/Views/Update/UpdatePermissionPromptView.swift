//
//  UpdatePermissionPromptView.swift
//  ReTagger
//
//  首启"开启自动更新？"授权提示（参考 Ghostty 的胶囊按钮 + 气泡样式）。
//  仅直发渠道展示；用户作出选择后按钮消失，选择由 Sparkle 持久化。
//

#if SPARKLE_ENABLED
import SwiftUI

struct UpdatePermissionPromptView: View {
    @ObservedObject var updater: SparkleUpdaterService
    @EnvironmentObject var localizationManager: LocalizationManager
    @State private var showPopover = false

    var body: some View {
        if updater.needsPermissionDecision {
            Button {
                showPopover = true
            } label: {
                Label(
                    localizationManager.string("update.permission.badge"),
                    systemImage: "questionmark.circle"
                )
                .font(DesignSystem.Typography.caption)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                popoverContent
            }
            .task {
                // 启动后稍作停留再自动展开气泡，避免与窗口出场动画抢焦点
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                showPopover = true
            }
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text(localizationManager.string("update.permission.title"))
                .font(.headline)

            Text(localizationManager.string("update.permission.message"))
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(localizationManager.string("update.permission.not_now")) {
                    updater.resolvePermission(allowAutomaticChecks: false)
                    showPopover = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(localizationManager.string("update.permission.allow")) {
                    updater.resolvePermission(allowAutomaticChecks: true)
                    showPopover = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(DesignSystem.Spacing.lg)
        .frame(width: 320)
    }
}
#endif
