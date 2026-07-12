//
//  SparkleUpdaterService.swift
//  ReTagger
//
//  直发渠道（GitHub Release DMG）的 Sparkle 自动更新服务。
//  仅当打包脚本以 SPARKLE_ENABLED 编译条件构建时参与编译，
//  App Store 渠道继续使用 AppUpdateService（iTunes Lookup + 跳转商店）。
//
//  更新源（SUFeedURL）、公钥（SUPublicEDKey）与安装器 XPC 开关由
//  scripts/package_direct.sh 在打包时写入 Info.plist，按架构指向
//  appcast-arm64.xml / appcast-x86_64.xml。
//

#if SPARKLE_ENABLED
import Foundation
import Combine
import OSLog
import Sparkle

@MainActor
final class SparkleUpdaterService: ObservableObject {

    /// 当前是否允许发起检查（检查进行中时 Sparkle 会置为 false）
    @Published private(set) var canCheckForUpdates = false

    /// 用户尚未对"自动检查更新"作出选择，首启时用于展示授权气泡
    @Published private(set) var needsPermissionDecision: Bool

    private let controller: SPUStandardUpdaterController
    private var cancellable: AnyCancellable?

    init() {
        // startingUpdater: true 立即启动后台调度；在用户作出选择前
        // automaticallyChecksForUpdates 尚未写入，Sparkle 不会自动检查，
        // 授权交互统一由 UpdatePermissionPromptView 完成。
        controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
        )
        needsPermissionDecision = UserDefaults.standard.object(forKey: "SUEnableAutomaticChecks") == nil

        cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }
        Logger.update.info("Sparkle 更新服务已启动，自动检查: \(self.controller.updater.automaticallyChecksForUpdates)")
    }

    /// 是否自动后台检查更新（写入即被 Sparkle 持久化到 UserDefaults）
    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set {
            objectWillChange.send()
            controller.updater.automaticallyChecksForUpdates = newValue
            needsPermissionDecision = false
        }
    }

    /// 自动检查间隔（秒），与设置页的 UpdateCheckInterval 联动
    var updateCheckInterval: TimeInterval {
        get { controller.updater.updateCheckInterval }
        set {
            objectWillChange.send()
            controller.updater.updateCheckInterval = newValue
        }
    }

    /// 上次检查时间（Sparkle 持久化，跨启动有效）
    var lastUpdateCheckDate: Date? {
        controller.updater.lastUpdateCheckDate
    }

    /// 手动检查更新，展示 Sparkle 标准更新界面（下载进度、安装重启一体）
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    /// 首启授权气泡的用户决定
    func resolvePermission(allowAutomaticChecks: Bool) {
        automaticallyChecksForUpdates = allowAutomaticChecks
        Logger.update.info("用户\(allowAutomaticChecks ? "开启" : "暂不开启")自动更新检查")
    }
}
#endif
