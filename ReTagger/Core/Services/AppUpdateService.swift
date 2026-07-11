//
//  AppUpdateService.swift
//  ReTagger
//
//  通过 iTunes Lookup API 检查 App Store 最新版本，
//  并引导用户跳转 App Store 完成更新。
//
//  改进点（借鉴 Sparkle 工程实践）：
//  - 配置集中到 AppConfiguration.Update
//  - 使用 SemanticVersion 进行语义化版本比较
//  - 读取 AppSettings 中的更新偏好（频率、开关）
//  - 支持重试机制和错误恢复
//

import Foundation
import AppKit
import Combine
import OSLog

/// 更新检查状态
enum UpdateStatus: Equatable {
    /// 未检查
    case idle
    /// 正在检查
    case checking
    /// 当前已是最新版本
    case upToDate(currentVersion: String)
    /// 有新版本可用
    case updateAvailable(newVersion: String, releaseNotes: String?, storeURL: URL)
    /// 检查失败（附带可重试标记）
    case error(String, retryable: Bool)

    static func == (lhs: UpdateStatus, rhs: UpdateStatus) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle): return true
        case (.checking, .checking): return true
        case (.upToDate(let a), .upToDate(let b)): return a == b
        case (.updateAvailable(let a1, let a2, let a3), .updateAvailable(let b1, let b2, let b3)):
            return a1 == b1 && a2 == b2 && a3 == b3
        case (.error(let a, let ar), .error(let b, let br)): return a == b && ar == br
        default: return false
        }
    }
}

/// iTunes Lookup API 响应
private struct ITunesLookupResponse: Decodable {
    let resultCount: Int
    let results: [ITunesAppInfo]
}

/// App Store 应用信息
private struct ITunesAppInfo: Decodable {
    let version: String
    let trackViewUrl: String
    let releaseNotes: String?
    let currentVersionReleaseDate: String?
}

@MainActor
final class AppUpdateService: ObservableObject {

    // MARK: - Published 状态

    @Published private(set) var updateStatus: UpdateStatus = .idle

    /// 上次检查时间（格式化后用于设置界面展示）
    @Published private(set) var lastCheckDate: Date?

    // MARK: - 初始化

    init() {
        // 从 UserDefaults 恢复上次检查时间
        let timestamp = UserDefaults.standard.double(forKey: AppConfiguration.Update.lastAutoCheckKey)
        if timestamp > 0 {
            lastCheckDate = Date(timeIntervalSince1970: timestamp)
        }
    }

    // MARK: - 公开方法

    /// 手动触发检查更新（菜单栏 / 设置面板调用）
    func checkForUpdate() {
        Task {
            await performCheck()
        }
    }

    /// 启动时自动后台检查（尊重用户偏好中的频率设置）
    func checkForUpdateIfNeeded(settings: AppSettings) {
        guard settings.autoCheckForUpdates else {
            Logger.update.info("用户已关闭自动检查更新")
            return
        }

        let lastCheck = UserDefaults.standard.double(forKey: AppConfiguration.Update.lastAutoCheckKey)
        let now = Date().timeIntervalSince1970
        let interval = settings.updateCheckInterval.timeInterval

        guard now - lastCheck >= interval else {
            Logger.update.info("距上次自动检查不足设定间隔，跳过")
            return
        }

        Task {
            await performCheck(isAutomatic: true, showNotification: settings.showUpdateNotifications)
        }
    }

    /// 跳转到 App Store 页面
    func openAppStore() {
        // 优先使用 API 返回的 trackViewUrl，降级到固定 macappstore:// URL
        if case .updateAvailable(_, _, let storeURL) = updateStatus {
            NSWorkspace.shared.open(storeURL)
        } else {
            NSWorkspace.shared.open(AppConfiguration.Update.appStoreURL)
        }
    }

    /// 关闭更新提示（用户选择"稍后提醒"）
    func dismiss() {
        updateStatus = .idle
    }

    /// 重试上次失败的检查
    func retry() {
        checkForUpdate()
    }

    // MARK: - 内部实现

    private func performCheck(isAutomatic: Bool = false, showNotification: Bool = true, retryCount: Int = 0) async {
        updateStatus = .checking

        do {
            let url = AppConfiguration.Update.lookupURL

            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                // 网络错误可重试
                if retryCount < AppConfiguration.Update.maxRetries {
                    Logger.update.info("服务器返回异常，\(AppConfiguration.Update.retryDelay)秒后重试 (\(retryCount + 1)/\(AppConfiguration.Update.maxRetries))")
                    try? await Task.sleep(nanoseconds: UInt64(AppConfiguration.Update.retryDelay * 1_000_000_000))
                    await performCheck(isAutomatic: isAutomatic, showNotification: showNotification, retryCount: retryCount + 1)
                    return
                }
                updateStatus = .error("服务器返回异常", retryable: true)
                return
            }

            let lookupResponse = try JSONDecoder().decode(ITunesLookupResponse.self, from: data)

            guard let appInfo = lookupResponse.results.first else {
                updateStatus = .error("未找到应用信息", retryable: true)
                return
            }

            // 记录本次检查时间
            let now = Date()
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: AppConfiguration.Update.lastAutoCheckKey)
            lastCheckDate = now

            let currentVersionString = AppConfiguration.InfoPlist.appVersion
            let storeVersionString = appInfo.version

            // 使用语义化版本比较
            guard let currentVersion = SemanticVersion(currentVersionString),
                  let storeVersion = SemanticVersion(storeVersionString) else {
                // 解析失败时降级到字符串比较
                Logger.update.warning("版本号解析失败，降级到字符串比较: current=\(currentVersionString) store=\(storeVersionString)")
                if currentVersionString.compare(storeVersionString, options: .numeric) == .orderedAscending {
                    let storeURL = URL(string: appInfo.trackViewUrl) ?? AppConfiguration.Update.appStoreURL
                    updateStatus = .updateAvailable(
                        newVersion: storeVersionString,
                        releaseNotes: appInfo.releaseNotes,
                        storeURL: storeURL
                    )
                } else {
                    handleUpToDate(currentVersion: currentVersionString, isAutomatic: isAutomatic)
                }
                return
            }

            if currentVersion.isOlderThan(storeVersion) {
                let storeURL = URL(string: appInfo.trackViewUrl) ?? AppConfiguration.Update.appStoreURL
                updateStatus = .updateAvailable(
                    newVersion: storeVersionString,
                    releaseNotes: appInfo.releaseNotes,
                    storeURL: storeURL
                )
                Logger.update.info("发现新版本: \(storeVersionString)，当前: \(currentVersionString)")

                // 自动检查且用户关闭了通知，则不弹窗
                if isAutomatic && !showNotification {
                    Logger.update.info("用户关闭了更新通知，静默记录")
                }
            } else {
                handleUpToDate(currentVersion: currentVersionString, isAutomatic: isAutomatic)
            }
        } catch {
            Logger.update.error("检查更新失败: \(error.localizedDescription)")

            // 网络错误可重试
            if retryCount < AppConfiguration.Update.maxRetries {
                Logger.update.info("检查失败，\(AppConfiguration.Update.retryDelay)秒后重试 (\(retryCount + 1)/\(AppConfiguration.Update.maxRetries))")
                try? await Task.sleep(nanoseconds: UInt64(AppConfiguration.Update.retryDelay * 1_000_000_000))
                await performCheck(isAutomatic: isAutomatic, showNotification: showNotification, retryCount: retryCount + 1)
                return
            }

            updateStatus = .error(error.localizedDescription, retryable: true)

            // 自动检查失败时不打扰用户
            if isAutomatic {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                updateStatus = .idle
            }
        }
    }

    /// 处理"已是最新版本"状态
    private func handleUpToDate(currentVersion: String, isAutomatic: Bool) {
        updateStatus = .upToDate(currentVersion: currentVersion)
        Logger.update.info("当前已是最新版本: \(currentVersion)")

        // 自动检查时如果已是最新，不弹窗，静默恢复 idle
        if isAutomatic {
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                updateStatus = .idle
            }
        }
    }
}
