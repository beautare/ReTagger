//
//  AppSettings.swift
//  ReTagger
//
//  Created by Claude Code
//

import Foundation
import Combine

struct RecentDirectoryEntry: Codable, Equatable, Identifiable {
    var path: String
    var bookmarkData: Data?
    var lastOpened: Date

    var id: String { path }

    var displayName: String {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        return name.isEmpty ? path : name
    }
}

enum AIProvider: String, Codable, CaseIterable {
    case gemini = "Gemini"
    case chatgpt = "ChatGPT"
    case grok = "Grok"
}

enum FileNamingFormat: String, Codable, CaseIterable, Identifiable {
    case titleArtist = "歌名 - 歌手"
    case artistTitle = "歌手 - 歌名"
    case titleOnly = "仅歌名"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .titleArtist: return "歌名 - 歌手 (默认)"
        case .artistTitle: return "歌手 - 歌名"
        case .titleOnly: return "仅歌名"
        }
    }
    
    var localizationKey: String {
        switch self {
        case .titleArtist: return "settings.processing.format.title_artist"
        case .artistTitle: return "settings.processing.format.artist_title"
        case .titleOnly: return "settings.processing.format.title_only"
        }
    }
}

/// 更新检查频率
enum UpdateCheckInterval: String, Codable, CaseIterable, Identifiable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"

    var id: String { rawValue }

    /// 对应的时间间隔（秒）
    var timeInterval: TimeInterval {
        switch self {
        case .daily: return 86_400        // 24 小时
        case .weekly: return 604_800      // 7 天
        case .monthly: return 2_592_000   // 30 天
        }
    }

    /// 显示名称
    var displayName: String {
        switch self {
        case .daily: return "每天"
        case .weekly: return "每周"
        case .monthly: return "每月"
        }
    }

    /// 英文显示名称
    var displayNameEN: String {
        switch self {
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        }
    }

    var localizationKey: String {
        switch self {
        case .daily: return "settings.update.interval.daily"
        case .weekly: return "settings.update.interval.weekly"
        case .monthly: return "settings.update.interval.monthly"
        }
    }
}

/// 曲目表格文字大小档位（Cmd+/Cmd-/Cmd0 与设置页共用同一偏好）
enum MetadataTableFontScale: Int, Codable, CaseIterable, Identifiable {
    case extraSmall = 0
    case small = 1
    case medium = 2
    case large = 3
    case extraLarge = 4

    var id: Int { rawValue }

    /// 相对系统默认字号的点数偏移，应用于表格正文字体
    var pointDelta: CGFloat {
        switch self {
        case .extraSmall: return -2
        case .small: return -1
        case .medium: return 0
        case .large: return 2
        case .extraLarge: return 4
        }
    }

    var localizationKey: String {
        switch self {
        case .extraSmall: return "settings.display.font_scale.extra_small"
        case .small: return "settings.display.font_scale.small"
        case .medium: return "settings.display.font_scale.medium"
        case .large: return "settings.display.font_scale.large"
        case .extraLarge: return "settings.display.font_scale.extra_large"
        }
    }
}

/// 表格列定义
enum MetadataColumn: String, Codable, CaseIterable, Identifiable {
    // 必须展示的列（最小集合）
    case fileName = "文件名"
    case title = "标题"
    case artist = "艺术家"
    case album = "专辑"
    case status = "状态"

    // 默认展示的列
    case genre = "风格"
    case year = "年份"
    case duration = "时长"

    // 可选列
    case fileSize = "大小"
    case bitrate = "位速率"
    case sampleRate = "采样速率"
    case format = "格式"
    case modificationDate = "修改日期"
    case creationDate = "创建日期"

    var id: String { rawValue }

    /// 列的显示宽度（最小值）
    var minWidth: CGFloat {
        switch self {
        case .fileName: return 150
        case .title: return 100
        case .artist: return 60
        case .album: return 100
        case .status: return 60
        case .genre: return 60
        case .year: return 30
        case .duration: return 30
        case .fileSize: return 50
        case .bitrate: return 30
        case .sampleRate: return 30
        case .format: return 30
        case .modificationDate: return 100
        case .creationDate: return 100
        }
    }
    var localizationKey: String {
        switch self {
        case .fileName: return "column.filename"
        case .title: return "column.title"
        case .artist: return "column.artist"
        case .album: return "column.album"
        case .status: return "column.status"
        case .genre: return "column.genre"
        case .year: return "column.year"
        case .duration: return "column.duration"
        case .fileSize: return "column.filesize"
        case .bitrate: return "column.bitrate"
        case .sampleRate: return "column.samplerate"
        case .format: return "column.format"
        case .modificationDate: return "column.modified"
        case .creationDate: return "column.created"
        }
    }
}

/// 列所属分组，用于区分必选列、默认可见列和可选列
enum MetadataColumnGroup {
    case required
    case defaultVisible
    case optional
}

/// 列描述：统一提供标题、分组和默认顺序
struct MetadataColumnDescriptor: Identifiable {
    let column: MetadataColumn
    let title: String
    let group: MetadataColumnGroup
    let defaultOrder: Int

    var id: MetadataColumn { column }

    var isRequired: Bool {
        group == .required
    }
    
    var localizationKey: String {
        column.localizationKey
    }
}

/// 元数据列注册表：集中管理列顺序、可见性及便捷查询
enum MetadataColumnRegistry {
    private static let descriptorList: [MetadataColumnDescriptor] = [
        MetadataColumnDescriptor(column: .fileName, title: "文件名", group: .required, defaultOrder: 0),
        MetadataColumnDescriptor(column: .status, title: "状态", group: .required, defaultOrder: 1),
        MetadataColumnDescriptor(column: .title, title: "标题", group: .required, defaultOrder: 2),
        MetadataColumnDescriptor(column: .artist, title: "艺术家", group: .required, defaultOrder: 3),
        MetadataColumnDescriptor(column: .album, title: "专辑", group: .required, defaultOrder: 4),
        MetadataColumnDescriptor(column: .fileSize, title: "大小", group: .defaultVisible, defaultOrder: 5),
        MetadataColumnDescriptor(column: .duration, title: "时长", group: .defaultVisible, defaultOrder: 6),
        MetadataColumnDescriptor(column: .sampleRate, title: "采样速率", group: .optional, defaultOrder: 7),
        MetadataColumnDescriptor(column: .bitrate, title: "位速率", group: .optional, defaultOrder: 8),
        MetadataColumnDescriptor(column: .genre, title: "风格", group: .optional, defaultOrder: 9),
        MetadataColumnDescriptor(column: .year, title: "年份", group: .optional, defaultOrder: 10),
        MetadataColumnDescriptor(column: .format, title: "格式", group: .optional, defaultOrder: 11),
        MetadataColumnDescriptor(column: .creationDate, title: "创建日期", group: .optional, defaultOrder: 12),
        MetadataColumnDescriptor(column: .modificationDate, title: "修改日期", group: .optional, defaultOrder: 13)
    ]

    private static let descriptorsByColumn: [MetadataColumn: MetadataColumnDescriptor] = {
        Dictionary(uniqueKeysWithValues: descriptorList.map { ($0.column, $0) })
    }()

    private static let requiredColumnSet: Set<MetadataColumn> = {
        Set(descriptorList.filter { $0.group == .required }.map(\.column))
    }()

    /// 保持默认顺序的列描述列表
    static var descriptors: [MetadataColumnDescriptor] {
        descriptorList.sorted { $0.defaultOrder < $1.defaultOrder }
    }

    /// 保持默认顺序的列集合
    static var orderedColumns: [MetadataColumn] {
        descriptors.map(\.column)
    }

    /// 必须显示的列（带 `*` 标记）
    static var requiredColumns: [MetadataColumn] {
        descriptors.filter(\.isRequired).map(\.column)
    }

    /// 默认可见的列（必选列 + 默认可见列）
    static var defaultVisibleColumns: [MetadataColumn] {
        descriptors.filter { $0.group == .required || $0.group == .defaultVisible }.map(\.column)
    }

    /// 可选列（默认隐藏，可在菜单中打开）
    static var optionalColumns: [MetadataColumn] {
        descriptors.filter { $0.group == .optional }.map(\.column)
    }

    /// 快速判断给定列是否必选
    static func isRequired(_ column: MetadataColumn) -> Bool {
        requiredColumnSet.contains(column)
    }

    /// 获取指定列的描述
    static func descriptor(for column: MetadataColumn) -> MetadataColumnDescriptor? {
        descriptorsByColumn[column]
    }
}

extension MetadataColumn {
    /// 是否为必须展示的列（无法隐藏）
    var isRequired: Bool {
        MetadataColumnRegistry.isRequired(self)
    }
}

/// 表格列配置
struct TableColumnConfiguration: Codable, Equatable {
    var visibleColumns: Set<MetadataColumn>
    var columnOrder: [MetadataColumn] // 列的显示顺序（从左到右）
    var columnWidths: [MetadataColumn: CGFloat] // 列宽度缓存

    /// 配置版本号，用于处理迁移
    /// 版本 1: 调整 Status 列位置到 FileName 和 Title 之间
    static let currentVersion = 1
    var version: Int = TableColumnConfiguration.currentVersion

    private enum CodingKeys: String, CodingKey {
        case visibleColumns
        case columnOrder
        case columnWidths
        case version
    }

    /// 默认配置：必须列 + 默认列
    static let `default` = TableColumnConfiguration(
        visibleColumns: Set(MetadataColumnRegistry.defaultVisibleColumns),
        columnOrder: MetadataColumnRegistry.orderedColumns,
        columnWidths: [:]
    )

    /// 最小视图：仅必须列
    static let minimal = TableColumnConfiguration(
        visibleColumns: Set(MetadataColumnRegistry.requiredColumns),
        columnOrder: MetadataColumnRegistry.orderedColumns,
        columnWidths: [:]
    )

    /// 完整视图：所有列
    static let complete = TableColumnConfiguration(
        visibleColumns: Set(MetadataColumnRegistry.orderedColumns),
        columnOrder: MetadataColumnRegistry.orderedColumns,
        columnWidths: [:]
    )

    /// 推荐视图：常用列的优化组合
    static let recommended: TableColumnConfiguration = {
        let visible: [MetadataColumn] = MetadataColumnRegistry.requiredColumns + [.genre, .year, .duration, .bitrate]
        return TableColumnConfiguration(
            visibleColumns: Set(visible),
            columnOrder: MetadataColumnRegistry.orderedColumns,
            columnWidths: [:]
        )
    }()

    init(visibleColumns: Set<MetadataColumn>, columnOrder: [MetadataColumn], columnWidths: [MetadataColumn: CGFloat] = [:]) {
        self.visibleColumns = visibleColumns
        self.columnOrder = columnOrder
        self.columnWidths = columnWidths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaultConfig = TableColumnConfiguration.default
        
        // Decode version
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 0

        // 1. Decode visible columns
        let rawVisible = try container.decodeIfPresent([String].self, forKey: .visibleColumns) ?? []
        var resolvedVisible = Set(rawVisible.compactMap(MetadataColumn.init(rawValue:)))
        if resolvedVisible.isEmpty {
            resolvedVisible = defaultConfig.visibleColumns
        }
        resolvedVisible.formUnion(MetadataColumn.allCases.filter(\.isRequired))
        self.visibleColumns = resolvedVisible

        // 2. Decode column order
        let rawOrder = try container.decodeIfPresent([String].self, forKey: .columnOrder) ?? []
        var resolvedOrder = rawOrder.compactMap(MetadataColumn.init(rawValue:))
        
        // 如果是旧版本配置（version < 1）或顺序为空，强制使用新的默认顺序
        // 这样可以确保 Status 列的位置更新被应用，同时避免了复杂的硬编码迁移逻辑
        if version < TableColumnConfiguration.currentVersion || resolvedOrder.isEmpty {
            resolvedOrder = MetadataColumnRegistry.orderedColumns
        } else {
            // 如果是当前版本，则保留用户的自定义顺序，但需要确保包含所有已知列
            let knownColumns = Set(MetadataColumnRegistry.orderedColumns)
            let storedColumns = Set(resolvedOrder)
            let missingColumns = knownColumns.subtracting(storedColumns)
            
            // Append missing columns in their default relative order
            let missingSorted = MetadataColumnRegistry.orderedColumns.filter { missingColumns.contains($0) }
            resolvedOrder.append(contentsOf: missingSorted)
        }
        self.columnOrder = resolvedOrder
        
        // 3. Decode widths
        let rawWidths = try container.decodeIfPresent([String: CGFloat].self, forKey: .columnWidths) ?? [:]
        var resolvedWidths: [MetadataColumn: CGFloat] = [:]
        for (key, value) in rawWidths {
            if let column = MetadataColumn(rawValue: key) {
                resolvedWidths[column] = value
            }
        }
        self.columnWidths = resolvedWidths
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(visibleColumns.map(\.rawValue), forKey: .visibleColumns)
        
        // Optimization: Only encode column order if it differs from the default registry order.
        // This ensures that if the user hasn't customized the order, they will automatically
        // pick up any future changes to the default order defined in the code.
        if columnOrder != MetadataColumnRegistry.orderedColumns {
            try container.encode(columnOrder.map(\.rawValue), forKey: .columnOrder)
        }
        
        var rawWidths: [String: CGFloat] = [:]
        for (key, value) in columnWidths {
            rawWidths[key.rawValue] = value
        }
        try container.encode(rawWidths, forKey: .columnWidths)
    }

    /// 检查列是否可见
    func isVisible(_ column: MetadataColumn) -> Bool {
        column.isRequired || visibleColumns.contains(column)
    }

    /// 获取按顺序排列的可见列
    func orderedVisibleColumns() -> [MetadataColumn] {
        columnOrder.filter { isVisible($0) }
    }

    /// 更新列顺序
    mutating func reorderColumn(from sourceIndex: Int, to targetIndex: Int) {
        guard sourceIndex != targetIndex,
              sourceIndex >= 0, sourceIndex < columnOrder.count,
              targetIndex >= 0, targetIndex < columnOrder.count else {
            return
        }

        let column = columnOrder.remove(at: sourceIndex)
        columnOrder.insert(column, at: targetIndex)
    }
    
    /// 更新列宽度
    mutating func updateWidth(_ width: CGFloat, for column: MetadataColumn) {
        columnWidths[column] = width
    }
    
    /// 获取列宽度（如果未存储则返回默认值）
    func width(for column: MetadataColumn) -> CGFloat? {
        columnWidths[column]
    }
}

/// 可序列化的表格排序偏好
struct SortPreference: Codable, Equatable {
    var column: MetadataColumn
    var ascending: Bool

    static let defaultPreference = SortPreference(column: .fileName, ascending: true)
}

struct AppSettings: Codable {
    var backendURL: String = AppConfiguration.API.baseURL
    var selectedAIProvider: AIProvider = .gemini
    var apiKey: String = ""
    var batchSize: Int = 20
    var autoApplyHighConfidence: Bool = false
    var highConfidenceThreshold: Double = 0.9
    var createBackups: Bool = true
    var preferredPlaybackOrder: PlaybackOrder = .sequential
    var metadataWriteFieldDefaults: Set<String>? = nil
    var recentDirectories: [RecentDirectoryEntry] = []
    var tableColumnConfiguration: TableColumnConfiguration = .default
    /// 用户上次使用的表格排序偏好
    var tableSortPreference: SortPreference? = nil
    var backupLocation: String? = nil
    var backupLocationBookmark: Data? = nil
    var includeSubdirectories: Bool = true
    var preferredLanguage: AppLanguage = .simplifiedChinese
    var fileNamingFormat: FileNamingFormat = .titleArtist
    var restoreDirectoryOnLaunch: Bool = true
    /// 关闭时保存的工作区目录列表，用于下次启动时恢复完整工作区
    var lastWorkspaceDirectories: [RecentDirectoryEntry] = []
    /// 上次播放的曲目文件路径，用于下次启动恢复播放栏状态
    var lastPlayingTrackPath: String? = nil
    /// 上次打开设置界面时选中的 Tab
    var selectedSettingsTab: Int? = 0
    /// 曲目表格文字大小档位（Cmd+/Cmd-/Cmd0 与设置页共用）
    var metadataTableFontScale: MetadataTableFontScale = .medium

    // MARK: - 火焰/频谱效果配置

    /// 是否开启“纯火热”色彩模式（默认 false，即经典 Winamp 绿黄红）
    var flameColorMode: Bool? = false
    /// 是否开启连续渐变渲染模式（默认 false，即经典 LED 格子）
    var continuousSpectrum: Bool? = false
    /// 是否开启左右声道独立（默认 false）
    var dualChannelSpectrum: Bool? = false

    // MARK: - 更新偏好

    /// 是否自动检查更新（默认开启）
    var autoCheckForUpdates: Bool = true
    /// 更新检查频率
    var updateCheckInterval: UpdateCheckInterval = .monthly
    /// 发现新版本时是否自动提示
    var showUpdateNotifications: Bool = true
    /// 配置版本号，用于以后升级时的迁移
    var settingsVersion: Int? = 1

    // MARK: - Persistence

    private static let userDefaultsKey = "ReTagger.AppSettings"

    /// Load settings from UserDefaults
    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              var settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        
        #if DEBUG
        // In DEBUG mode, ALWAYS use the URL from AppConfiguration.
        // This ensures developers always use the correct environment URL based on
        // AppConfiguration.current (development/staging/production) regardless of
        // any stale URL values saved in UserDefaults from previous runs.
        settings.backendURL = AppConfiguration.API.baseURL
        #else
        // In RELEASE mode, only update if the saved URL is the default localhost
        // (which shouldn't happen in production) and the environment provides a different one.
        let currentEnvURL = AppConfiguration.API.baseURL
        if settings.backendURL == "http://localhost:8009" && currentEnvURL != "http://localhost:8009" {
            settings.backendURL = currentEnvURL
        }
        #endif
        
        return settings
    }

    /// Save settings to UserDefaults
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: AppSettings.userDefaultsKey)
        }
    }
}
