//
//  ReTaggerApp.swift
//  ReTagger
//
//

import SwiftUI

@main
struct ReTaggerApp: App {
    @StateObject private var localizationManager: LocalizationManager
    @StateObject private var coordinator: AppCoordinator
    #if SPARKLE_ENABLED
    @StateObject private var sparkleUpdater = SparkleUpdaterService()
    #else
    @StateObject private var updateService = AppUpdateService()
    @State private var showUpdateAlert = false
    #endif
    
    init() {
        AppConfiguration.printConfiguration()
        let initialSettings = AppSettings.load()
        let manager = LocalizationManager(language: initialSettings.preferredLanguage)
        _localizationManager = StateObject(wrappedValue: manager)
        _coordinator = StateObject(wrappedValue: AppCoordinator(settings: initialSettings, localizationManager: manager))
    }

    private var windowTitle: String {
        guard let directory = coordinator.selectedDirectory else {
            return "ReTagger"
        }
        let name = directory.lastPathComponent
        return name.isEmpty ? directory.path : name
    }

    var body: some Scene {
        WindowGroup(windowTitle) {
            ContentView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.playbackController)
                .environmentObject(coordinator.playbackController.timelineStore)
                .environmentObject(coordinator.playbackController.spectrumDataStore)
                .environmentObject(localizationManager)
                .environment(\.locale, localizationManager.locale)
                #if SPARKLE_ENABLED
                .environmentObject(sparkleUpdater)
                .overlay(alignment: .topTrailing) {
                    // 首启"开启自动更新？"授权气泡（参考 1.jpg / Ghostty），
                    // 后续检查、下载与安装由 Sparkle 标准界面接管
                    UpdatePermissionPromptView(updater: sparkleUpdater)
                        .padding(.top, DesignSystem.Spacing.xs)
                        .padding(.trailing, DesignSystem.Spacing.md)
                }
                #else
                .environmentObject(updateService)
                .onAppear {
                    // 启动时自动后台检查更新（尊重用户偏好中的频率设置）
                    updateService.checkForUpdateIfNeeded(settings: coordinator.settings)
                }
                .onReceive(updateService.$updateStatus) { status in
                    // 有新版本时自动弹出更新提示
                    if case .updateAvailable = status {
                        showUpdateAlert = true
                    }
                }
                .sheet(isPresented: $showUpdateAlert, onDismiss: {
                    // sheet 关闭动画结束后再重置服务状态，避免闪白
                    updateService.dismiss()
                }) {
                    UpdateAlertView(updateService: updateService)
                        .environmentObject(localizationManager)
                }
                #endif
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(action: {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowSettings"), object: nil)
                }) {
                    Label(localizationManager.string("action.settings"), systemImage: "gear")
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .appInfo) {
                Button(action: {
                    NSApp.orderFrontStandardAboutPanel(
                        options: [
                            NSApplication.AboutPanelOptionKey.credits: NSAttributedString(
                                string: "Support: support@retagger.vip\n\n© 2026 ReTagger. All rights reserved.",
                                attributes: [
                                    .font: NSFont.systemFont(ofSize: 11),
                                    .foregroundColor: NSColor.labelColor
                                ]
                            ),
                            NSApplication.AboutPanelOptionKey.applicationName: "ReTagger"
                        ]
                    )
                }) {
                    Label(localizationManager.string("menu.about"), systemImage: "info.circle")
                }
            }
            CommandGroup(after: .appInfo) {
                #if SPARKLE_ENABLED
                Button(action: {
                    sparkleUpdater.checkForUpdates()
                }) {
                    Label(localizationManager.string("update.check_for_updates"), systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(!sparkleUpdater.canCheckForUpdates)
                #else
                Button(action: {
                    showUpdateAlert = true
                    updateService.checkForUpdate()
                }) {
                    Label(localizationManager.string("update.check_for_updates"), systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(updateService.updateStatus == .checking)
                #endif
            }
        }
    }
}
