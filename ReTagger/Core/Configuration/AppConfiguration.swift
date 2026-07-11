//
//  AppConfiguration.swift
//  ReTagger
//
//  Application configuration management with environment support
//

import Foundation

/// 应用程序配置管理
enum AppConfiguration {

    // MARK: - Environment

    /// 应用程序运行环境
    enum Environment {
        case development
        case staging
        case production

        /// 当前环境的后端 API URL
        var backendURL: String {
            switch self {
            case .development:
                #if DEBUG
                // 开发环境：优先从 .env 文件读取，回退到硬编码值
                return EnvironmentParser.getValue(for: "BACKEND_URL", defaultValue: "http://localhost:8009")
                #else
                return "http://localhost:8009"
                #endif
            case .staging:
                #if DEBUG
                return EnvironmentParser.getValue(for: "STAGING_BACKEND_URL", defaultValue: "https://proxy.retagger.vip")
                #else
                return "https://proxy.retagger.vip"
                #endif
            case .production:
                #if DEBUG
                return EnvironmentParser.getValue(for: "PRODUCTION_BACKEND_URL", defaultValue: "https://proxy.retagger.vip")
                #else
                return "https://proxy.retagger.vip"
                #endif
            }
        }

        /// 环境名称（用于日志）
        var name: String {
            switch self {
            case .development: return "Development"
            case .staging: return "Staging"
            case .production: return "Production"
            }
        }

        /// 是否启用调试功能
        var isDebugEnabled: Bool {
            switch self {
            case .development: return true
            case .staging: return true
            case .production: return false
            }
        }

        /// 日志级别
        var logLevel: LogLevel {
            switch self {
            case .development: return .debug
            case .staging: return .info
            case .production: return .error
            }
        }
    }

    /// 日志级别
    enum LogLevel: String {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
    }

    // MARK: - Current Environment

    /// 当前运行环境
    static let current: Environment = {
        #if DEBUG
        // 开发环境：使用本地服务器或staging环境
        // 可以通过环境变量 RETAGGER_ENV 来覆盖
        if let envString = ProcessInfo.processInfo.environment["RETAGGER_ENV"] {
            switch envString.lowercased() {
            case "staging": return .staging
            case "production": return .production
            default: return .development
            }
        }
        return .development
        #else
        // 生产环境
        return .production
        #endif
    }()

    // MARK: - API Configuration

    /// API 配置
    enum API {
        /// 默认后端 URL（基于当前环境）
        static var baseURL: String {
            return current.backendURL
        }

        /// 元数据处理端点
        static let metadataProcessEndpoint = "/api/v1/metadata/process"

        /// 健康检查端点
        static let healthCheckEndpoint = "/api/v1/metadata/health"

        /// 默认请求超时（秒）
        static let defaultTimeout: TimeInterval = 30

        /// AI 处理超时（秒）
        static let aiProcessingTimeout: TimeInterval = 120

        /// 最大重试次数
        static let maxRetries = 3
    }

    // MARK: - File System Configuration

    /// 文件系统配置
    enum FileSystem {
        /// 支持的音频文件扩展名
        nonisolated static let supportedAudioExtensions: Set<String> = AudioFormatSupport.supportedExtensions

        /// 备份文件夹名称
        static let backupFolderName = "ReTagger"

        /// 最大并发文件操作数
        static let maxConcurrentOperations = 5

        /// 文件扫描批次大小
        static let scanBatchSize = 100
    }

    // MARK: - AI Configuration

    /// AI 处理配置
    enum AI {
        /// 默认 AI 提供商
        static let defaultProvider: AIProvider = .gemini

        /// 默认批处理大小
        static let defaultBatchSize = 20

        /// 高置信度阈值
        static let highConfidenceThreshold: Double = 0.9

        /// 中等置信度阈值
        static let mediumConfidenceThreshold: Double = 0.7

        /// 低置信度阈值
        static let lowConfidenceThreshold: Double = 0.5

        /// 各 AI 提供商的最大批次大小
        static func maxBatchSize(for provider: AIProvider) -> Int {
            switch provider {
            case .gemini: return 50
            case .chatgpt: return 30
            case .grok: return 40
            }
        }
    }

    // MARK: - UI Configuration

    /// UI 配置
    enum UI {
        /// 主窗口最小宽度
        static let windowMinWidth: CGFloat = 1000

        /// 主窗口最小高度
        static let windowMinHeight: CGFloat = 700

        /// 动画持续时间
        static let animationDuration: Double = 0.3
    }

    // MARK: - Cache Configuration

    /// 缓存配置
    enum Cache {
        /// 元数据缓存过期时间（秒）
        static let metadataCacheExpiration: TimeInterval = 3600 // 1 hour

        /// 最大缓存条目数
        static let maxCacheEntries = 1000

        /// 是否启用缓存
        static let isCacheEnabled = true
    }

    // MARK: - Update Configuration

    /// 软件更新配置
    enum Update {
        /// App Store 数字 ID
        static let appStoreId = "6757285866"

        /// App Store 页面 URL（用于引导跳转）
        static let appStoreURL = URL(string: "macappstore://apps.apple.com/app/id\(appStoreId)")!

        /// iTunes Lookup API 查询地址
        static var lookupURL: URL {
            let bundleId = InfoPlist.bundleIdentifier
            return URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleId)")!
        }

        /// 默认自动检查间隔：24 小时
        static let defaultCheckInterval: TimeInterval = 86_400

        /// UserDefaults 键：上次自动检查时间
        static let lastAutoCheckKey = "AppUpdateService.lastAutoCheckDate"

        /// 最大重试次数
        static let maxRetries = 2

        /// 重试间隔（秒）
        static let retryDelay: TimeInterval = 3
    }

    // MARK: - Debug Configuration

    /// 调试配置
    enum Debug {
        /// 是否启用详细日志
        static var isVerboseLoggingEnabled: Bool {
            return current.isDebugEnabled
        }

        /// 是否显示开发者选项
        static var showDeveloperOptions: Bool {
            return current.isDebugEnabled
        }

        /// 是否启用网络请求模拟
        static let enableNetworkMocking = false

        /// 是否打印 JSON 请求/响应
        static var printJSON: Bool {
            return current == .development
        }
    }

    // MARK: - Info.plist Access

    /// 从 Info.plist 读取配置
    enum InfoPlist {
        /// 应用版本号
        static var appVersion: String {
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        }

        /// 构建版本号
        static var buildNumber: String {
            Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        }

        /// 应用标识符
        static var bundleIdentifier: String {
            Bundle.main.bundleIdentifier ?? "vip.retagger.macapp"
        }

        /// 应用名称
        static var appName: String {
            Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "ReTagger"
        }
    }

    // MARK: - Helper Methods

    /// 打印当前配置（用于调试）
    static func printConfiguration() {
        var configSource = "Hardcoded Defaults"
        var backendSource = "Fallback"
        
        #if DEBUG
        if let envPath = EnvironmentParser.loadedFilePath {
            configSource = ".env.local (\(envPath))"
        } else {
            configSource = "None (No .env.local found)"
        }
        
        let backendKey = current == .staging ? "STAGING_BACKEND_URL" : 
                         (current == .production ? "PRODUCTION_BACKEND_URL" : "BACKEND_URL")
        
        if EnvironmentParser.hasKey(backendKey) {
            backendSource = ".env.local"
        }
        #endif
        
        print("""
        ═══════════════════════════════════════
        ReTagger Configuration
        ═══════════════════════════════════════
        Environment:    \(current.name)
        Config Source:  \(configSource)
        Backend URL:    \(API.baseURL)
        Backend Source: \(backendSource)
        App Version:    \(InfoPlist.appVersion) (\(InfoPlist.buildNumber))
        Bundle ID:      \(InfoPlist.bundleIdentifier)
        Debug Enabled:  \(current.isDebugEnabled)
        Log Level:      \(current.logLevel.rawValue)
        ═══════════════════════════════════════
        """)
    }
}
