//
//  SettingsView.swift
//  ReTagger
//
//  Application settings view
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var coordinator: AppCoordinator
    #if SPARKLE_ENABLED
    @EnvironmentObject var sparkleUpdater: SparkleUpdaterService
    #else
    @EnvironmentObject var updateService: AppUpdateService
    #endif
    @EnvironmentObject var localizationManager: LocalizationManager
    @Environment(\.presentationMode) var presentationMode
    
    @State private var selectedTab: Int = 0

    /// 四个设置分页的标题与图标，顺序即持久化的 tab 索引
    private let tabItems: [(titleKey: String, icon: String)] = [
        ("settings.tab.general_update", "gearshape"),
        ("settings.tab.processing_backup", "doc.badge.gearshape"),
        ("settings.tab.visuals", "flame.fill"),
        ("settings.tab.logs", "stethoscope")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(localizationManager.string("settings.title"))
                    .font(DesignSystem.Typography.title)
                Spacer()
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            tabBar
                .padding(.top, DesignSystem.Spacing.sm)

            Group {
                switch selectedTab {
                case 0: generalUpdateTab
                case 1: processingBackupTab
                case 2: visualsTab
                default: diagnosticsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(DesignSystem.Spacing.md)
        }
        .frame(width: 550, height: 480)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            let savedTab = coordinator.settings.selectedSettingsTab ?? 0
            selectedTab = min(max(savedTab, 0), 3)
        }
        .onDisappear {
            var updatedSettings = coordinator.settings
            updatedSettings.selectedSettingsTab = selectedTab
            coordinator.updateSettings(updatedSettings)
        }
    }
    
    // MARK: - Tabs

    /// 自定义 Tab 栏：图标与标题作为整体在高亮胶囊内对称留白，保证视觉居中
    private var tabBar: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            ForEach(tabItems.indices, id: \.self) { index in
                tabButton(at: index)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func tabButton(at index: Int) -> some View {
        let item = tabItems[index]
        let isSelected = selectedTab == index

        return Button {
            selectedTab = index
        } label: {
            HStack(spacing: DesignSystem.Spacing.xxs) {
                Image(systemName: item.icon)
                    .font(.system(size: 11, weight: .medium))
                Text(localizationManager.string(item.titleKey))
                    .font(DesignSystem.Typography.caption)
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.xxs + 2)
            .foregroundColor(isSelected ? .white : DesignSystem.Colors.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                    .fill(isSelected ? Color.accentColor : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                    .stroke(Color(NSColor.separatorColor).opacity(isSelected ? 0 : 0.8), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var generalUpdateTab: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.md) {
                // 基础偏好卡片
                SettingsCard(title: localizationManager.string("settings.group.general")) {
                    HStack {
                        Text(localizationManager.string("settings.general.language"))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        Spacer()
                        Picker("", selection: languageBinding) {
                            ForEach(AppLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 160)
                    }

                    Divider()
                        .padding(.vertical, 2)

                    HStack {
                        Text(localizationManager.string("settings.general.font_scale"))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        Spacer()
                        fontScaleRuler
                    }

                    Divider()
                        .padding(.vertical, 2)

                    Toggle(localizationManager.string("settings.general.restore_directory"), isOn: binding($coordinator.settings.restoreDirectoryOnLaunch))
                }
                
                // 软件更新卡片
                #if SPARKLE_ENABLED
                // 直发渠道：开关与频率直接读写 Sparkle 持久化状态，
                // 检查、下载与安装由 Sparkle 标准界面接管
                SettingsCard(title: localizationManager.string("settings.group.update")) {
                    Toggle(localizationManager.string("settings.update.auto_check"), isOn: sparkleAutoCheckBinding)

                    if sparkleUpdater.automaticallyChecksForUpdates {
                        Divider()
                            .padding(.vertical, 2)

                        HStack {
                            Text(localizationManager.string("settings.update.check_frequency"))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            Spacer()
                            Picker("", selection: sparkleIntervalBinding) {
                                ForEach(UpdateCheckInterval.allCases) { interval in
                                    Text(localizationManager.string(interval.localizationKey)).tag(interval)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 160)
                        }
                    }

                    Divider()
                        .padding(.vertical, 2)

                    HStack {
                        Text(localizationManager.string("settings.update.current_version_label"))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        Text("\(AppConfiguration.InfoPlist.appVersion) (\(AppConfiguration.InfoPlist.buildNumber))")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 2)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localizationManager.string("settings.update.last_check_label"))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            if let date = sparkleUpdater.lastUpdateCheckDate {
                                Text(lastCheckFormatted(date))
                                    .font(DesignSystem.Typography.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(localizationManager.string("settings.update.never_checked"))
                                    .font(DesignSystem.Typography.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        Button(localizationManager.string("settings.update.check_now")) {
                            sparkleUpdater.checkForUpdates()
                        }
                        .disabled(!sparkleUpdater.canCheckForUpdates)
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 2)
                }
                #else
                SettingsCard(title: localizationManager.string("settings.group.update")) {
                    Toggle(localizationManager.string("settings.update.auto_check"), isOn: binding($coordinator.settings.autoCheckForUpdates))

                    if coordinator.settings.autoCheckForUpdates {
                        Divider()
                            .padding(.vertical, 2)

                        HStack {
                            Text(localizationManager.string("settings.update.check_frequency"))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            Spacer()
                            Picker("", selection: binding($coordinator.settings.updateCheckInterval)) {
                                ForEach(UpdateCheckInterval.allCases) { interval in
                                    Text(localizationManager.string(interval.localizationKey)).tag(interval)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 160)
                        }

                        Divider()
                            .padding(.vertical, 2)

                        Toggle(localizationManager.string("settings.update.auto_prompt"), isOn: binding($coordinator.settings.showUpdateNotifications))
                    }

                    Divider()
                        .padding(.vertical, 2)

                    HStack {
                        Text(localizationManager.string("settings.update.current_version_label"))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        Text("\(AppConfiguration.InfoPlist.appVersion) (\(AppConfiguration.InfoPlist.buildNumber))")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 2)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localizationManager.string("settings.update.last_check_label"))
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                            if let date = updateService.lastCheckDate {
                                Text(lastCheckFormatted(date))
                                    .font(DesignSystem.Typography.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text(localizationManager.string("settings.update.never_checked"))
                                    .font(DesignSystem.Typography.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        Button(localizationManager.string("settings.update.check_now")) {
                            updateService.checkForUpdate()
                        }
                        .disabled(updateService.updateStatus == .checking)
                        .buttonStyle(.bordered)
                    }
                    .padding(.top, 2)
                }
                #endif
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 2)
            .padding(.top, 4)
        }
    }
    
    #if SPARKLE_ENABLED
    /// Sparkle 自动检查开关绑定（写入即由 Sparkle 持久化）
    private var sparkleAutoCheckBinding: Binding<Bool> {
        Binding(
            get: { sparkleUpdater.automaticallyChecksForUpdates },
            set: { sparkleUpdater.automaticallyChecksForUpdates = $0 }
        )
    }

    /// Sparkle 检查间隔与 UpdateCheckInterval 档位的映射绑定
    private var sparkleIntervalBinding: Binding<UpdateCheckInterval> {
        Binding(
            get: {
                UpdateCheckInterval.allCases.first { $0.timeInterval == sparkleUpdater.updateCheckInterval } ?? .monthly
            },
            set: { sparkleUpdater.updateCheckInterval = $0.timeInterval }
        )
    }
    #endif

    private var processingBackupTab: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.md) {
                // 文件与扫描卡片
                SettingsCard(title: localizationManager.string("settings.group.scan")) {
                    Toggle(localizationManager.string("settings.processing.include_subdirectories"), isOn: $coordinator.includeSubdirectories)
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    HStack {
                        Text(localizationManager.string("settings.processing.rename_format"))
                            .foregroundColor(DesignSystem.Colors.textPrimary)
                        Spacer()
                        Picker("", selection: binding($coordinator.settings.fileNamingFormat)) {
                            ForEach(FileNamingFormat.allCases) { format in
                                Text(localizationManager.string(format.localizationKey)).tag(format)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 180)
                    }
                    
                    if coordinator.settings.fileNamingFormat == .titleOnly {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(localizationManager.string("settings.processing.rename_warning"))
                                .font(.caption)
                                .foregroundColor(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 4)
                        .transition(.opacity)
                    }
                }
                
                // 安全与备份卡片
                SettingsCard(title: localizationManager.string("settings.group.backup")) {
                    Toggle(localizationManager.string("settings.backup.auto_backup"), isOn: binding($coordinator.settings.createBackups))
                    
                    if coordinator.settings.createBackups {
                        Divider()
                            .padding(.vertical, 2)
                        
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                            Text(localizationManager.string("settings.backup.location_label"))
                                .font(DesignSystem.Typography.caption2)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Text(currentBackupLocationDisplay)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .foregroundColor(.secondary)
                                    .font(DesignSystem.Typography.monoBody)
                                
                                Spacer()
                                
                                Button(localizationManager.string("settings.backup.change")) {
                                    selectBackupLocation()
                                }
                                
                                if coordinator.settings.backupLocation != nil {
                                    Button(localizationManager.string("settings.backup.reset_default")) {
                                        coordinator.resetBackupDirectoryToDefault()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 2)
            .padding(.top, 4)
        }
    }
    
    private var visualsTab: some View {
        ScrollView {
            VStack(spacing: DesignSystem.Spacing.md) {
                // 实时预览视窗
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    Text(localizationManager.string("settings.flame.preview_title"))
                        .font(DesignSystem.Typography.caption2)
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                    
                    ZStack {
                        SpectrumVisualizerView(
                            spectrumData: previewBands,
                            isPlaying: true
                        )
                        .frame(height: 48)
                        .cornerRadius(DesignSystem.CornerRadius.md)
                        
                        Color.black.opacity(DesignSystem.Layout.PlaybackBar.Spectrum.overlayOpacity)
                            .cornerRadius(DesignSystem.CornerRadius.md)
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
                    .cornerRadius(DesignSystem.CornerRadius.md)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                            .stroke(Color(NSColor.separatorColor).opacity(0.8), lineWidth: 1)
                    )
                }
                
                // 效果设置卡片
                SettingsCard(title: localizationManager.string("settings.tab.flame")) {
                    Toggle(localizationManager.string("settings.flame.color_mode"), isOn: boolBinding($coordinator.settings.flameColorMode))
                        .help(localizationManager.string("settings.flame.color_mode.help"))
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    Toggle(localizationManager.string("settings.flame.continuous"), isOn: boolBinding($coordinator.settings.continuousSpectrum))
                        .help(localizationManager.string("settings.flame.continuous.help"))
                    
                    Divider()
                        .padding(.vertical, 2)
                    
                    Toggle(localizationManager.string("settings.flame.dual_channel"), isOn: boolBinding($coordinator.settings.dualChannelSpectrum))
                        .help(localizationManager.string("settings.flame.dual_channel.help"))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 2)
            .padding(.top, 4)
        }
        .onAppear {
            startPreviewTimer()
        }
        .onDisappear {
            stopPreviewTimer()
        }
    }
    
    private var diagnosticsTab: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text(localizationManager.string("settings.logs.title"))
                    .font(DesignSystem.Typography.title3)
                Spacer()
                Button(localizationManager.string("settings.logs.clear_button")) {
                    coordinator.clearLogs()
                }
                .disabled(coordinator.activityLogs.isEmpty)
            }
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                    ForEach(coordinator.activityLogs) { entry in
                        HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                            Text(logTimestamp(entry.timestamp))
                                .font(DesignSystem.Typography.caption2)
                                .foregroundColor(.secondary)
                                .frame(width: 80, alignment: .leading)
                            Text(localizationManager.string(entry.level.localizationKey))
                                .font(DesignSystem.Typography.caption2)
                                .foregroundColor(color(for: entry.level))
                                .frame(width: 44, alignment: .leading)
                            Text(entry.message)
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.textPrimary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DesignSystem.Spacing.xs)
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
            )
        }
        .padding(.top, 4)
    }
    
    // MARK: - Helpers
    
    private var currentBackupLocationDisplay: String {
        if let path = coordinator.settings.backupLocation {
            return path
        } else {
            return localizationManager.string("settings.backup.default_location")
        }
    }
    
    private func selectBackupLocation() {
        Task {
            if let url = await coordinator.fileSystemService.selectDirectory() {
                await MainActor.run {
                    coordinator.setBackupDirectory(url)
                }
            }
        }
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { coordinator.localizationManager.language },
            set: { newValue in
                coordinator.setLanguage(newValue)
            }
        )
    }

    /// 曲目列表文字大小的标尺式选择器：柱条由矮到高排列，点击直接跳到对应档位
    private var fontScaleRuler: some View {
        let allCases = MetadataTableFontScale.allCases
        let current = coordinator.settings.metadataTableFontScale

        return HStack(spacing: 8) {
            Text("A")
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(.secondary)

            HStack(alignment: .bottom, spacing: 5) {
                ForEach(allCases) { step in
                    Button {
                        setFontScale(step)
                    } label: {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(step == current ? Color.accentColor : Color(NSColor.separatorColor))
                            .frame(width: 12, height: fontScaleBarHeight(for: step))
                    }
                    .buttonStyle(.plain)
                    .help(localizationManager.string(step.localizationKey))
                }
            }
            .frame(height: 22, alignment: .bottom)

            Text("A")
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.secondary)
        }
    }

    private func fontScaleBarHeight(for step: MetadataTableFontScale) -> CGFloat {
        let allCases = MetadataTableFontScale.allCases
        let minHeight: CGFloat = 6
        let maxHeight: CGFloat = 22
        let fraction = CGFloat(step.rawValue) / CGFloat(allCases.count - 1)
        return minHeight + fraction * (maxHeight - minHeight)
    }

    private func setFontScale(_ scale: MetadataTableFontScale) {
        var newSettings = coordinator.settings
        newSettings.metadataTableFontScale = scale
        coordinator.updateSettings(newSettings)
    }
    
    private func binding<T>(_ source: Binding<T>) -> Binding<T> {
        Binding(
            get: { source.wrappedValue },
            set: { newValue in
                source.wrappedValue = newValue
                coordinator.updateSettings(coordinator.settings)
            }
        )
    }
    
    private func boolBinding(_ source: Binding<Bool?>) -> Binding<Bool> {
        Binding(
            get: { source.wrappedValue ?? false },
            set: { newValue in
                source.wrappedValue = newValue
                coordinator.updateSettings(coordinator.settings)
            }
        )
    }

    private func logTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func color(for level: AppCoordinator.ActivityLogEntry.Level) -> Color {
        switch level {
        case .info: return .secondary
        case .warning: return .orange
        case .error: return .red
        }
    }
    
    private func lastCheckFormatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - 实时音频频谱模拟器
    
    @State private var previewBands: [Float] = [Float](repeating: 0, count: 80)
    @State private var previewTimer: Timer? = nil
    @State private var timeAccumulator: Double = 0

    private func startPreviewTimer() {
        timeAccumulator = 0
        previewTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { _ in
            timeAccumulator += 0.05
            var nextBands = [Float](repeating: 0, count: 80)
            
            for i in 0..<40 {
                let freqIdx = Float(i)
                let baseFactor = exp(-freqIdx / 12.0)
                
                // 模拟左声道
                let waveL = sin(timeAccumulator * 3.0 + Double(i) * 0.15) * 0.4 + 0.6
                let noiseL = Float.random(in: -0.08...0.08)
                let amplitudeL = Float(waveL) * baseFactor + noiseL
                nextBands[i] = max(0, min(1, amplitudeL))
                
                // 模拟右声道
                let waveR = sin(timeAccumulator * 2.6 + Double(i) * 0.18 + 0.8) * 0.45 + 0.55
                let noiseR = Float.random(in: -0.08...0.08)
                let amplitudeR = Float(waveR) * baseFactor + noiseR
                nextBands[i + 40] = max(0, min(1, amplitudeR))
            }
            previewBands = nextBands
        }
    }

    private func stopPreviewTimer() {
        previewTimer?.invalidate()
        previewTimer = nil
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(title)
                .font(DesignSystem.Typography.caption2)
                .foregroundColor(.secondary)
                .padding(.leading, 4)
                .padding(.bottom, 2)
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                content
            }
            .padding(DesignSystem.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(NSColor.separatorColor).opacity(0.8), lineWidth: 1)
            )
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppCoordinator())
        .environmentObject(AppUpdateService())
        .environmentObject(LocalizationManager(language: .simplifiedChinese))
}
