//
//  DesignSystem.swift
//  ReTagger
//
//  Unified design system for consistent UI
//

import SwiftUI

/// ReTagger 应用设计系统
/// 提供统一的颜色、字体、间距、圆角等设计规范
enum DesignSystem {

    // MARK: - Colors

    /// 应用配色方案
    enum Colors {
        // 主题色
        static let primary = Color.blue
        static let secondary = Color.purple
        static let accent = Color.cyan

        // 语义颜色
        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let info = Color.blue

        // 中性色
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color.gray
        static let textDisabled = Color.gray.opacity(0.5)

        // 背景色
        static let background = Color(nsColor: .windowBackgroundColor)
        static let backgroundSecondary = Color.gray.opacity(0.05)
        static let backgroundTertiary = Color.gray.opacity(0.1)
        static let backgroundElevated = Color(nsColor: .controlBackgroundColor)

        // 边框色
        static let border = Color.gray.opacity(0.2)
        static let borderHover = Color.gray.opacity(0.4)

        // 叠加层
        static let overlay = Color.black.opacity(0.5)

        // 状态色（半透明背景）
        static func successBackground(_ opacity: Double = 0.1) -> Color {
            success.opacity(opacity)
        }

        static func warningBackground(_ opacity: Double = 0.1) -> Color {
            warning.opacity(opacity)
        }

        static func errorBackground(_ opacity: Double = 0.1) -> Color {
            error.opacity(opacity)
        }

        static func infoBackground(_ opacity: Double = 0.1) -> Color {
            info.opacity(opacity)
        }
    }

    // MARK: - Typography

    /// 字体系统
    enum Typography {
        // 标题
        static let largeTitle = Font.largeTitle.weight(.bold)
        static let title = Font.title.weight(.bold)
        static let title2 = Font.title2.weight(.bold)
        static let title3 = Font.title3.weight(.semibold)

        // 正文
        static let body = Font.body
        static let bodyBold = Font.body.weight(.semibold)
        static let callout = Font.callout
        static let subheadline = Font.subheadline

        // 辅助文本
        static let caption = Font.caption
        static let caption2 = Font.caption2
        static let footnote = Font.footnote

        // 等宽字体
        static let monoBody = Font.system(.body, design: .monospaced)
        static let monoCaption = Font.system(.caption, design: .monospaced)
    }

    // MARK: - Spacing

    /// 间距系统（基于 8pt 网格）
    enum Spacing {
        static let xxxs: CGFloat = 2
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 64

        // 常用组合
        static let cardPadding = md
        static let sectionSpacing = lg
        static let itemSpacing = sm
    }

    // MARK: - Corner Radius

    /// 圆角半径
    enum CornerRadius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
        static let full: CGFloat = 9999 // 完全圆形
    }

    // MARK: - Shadows

    /// 阴影样式
    enum Shadows {
        static let small = (color: Color.black.opacity(0.1), radius: CGFloat(4), x: CGFloat(0), y: CGFloat(2))
        static let medium = (color: Color.black.opacity(0.15), radius: CGFloat(8), x: CGFloat(0), y: CGFloat(4))
        static let large = (color: Color.black.opacity(0.2), radius: CGFloat(16), x: CGFloat(0), y: CGFloat(8))
    }

    // MARK: - Animation

    /// 动画配置
    enum Animation {
        static let fast = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let normal = SwiftUI.Animation.easeInOut(duration: 0.25)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.35)
        static let spring = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.7)
    }

    // MARK: - Layout

    /// 布局常量
    enum Layout {
        // 侧边栏
        static let sidebarMinWidth: CGFloat = 250
        static let sidebarIdealWidth: CGFloat = 280
        /// 侧边栏绝对最大宽度上限
        static let sidebarAbsoluteMax: CGFloat = 480
        /// 侧边栏最大宽度占窗口比例
        static let sidebarMaxWidthRatio: CGFloat = 0.35
        /// 迷你列宽度
        static let sidebarMiniWidth: CGFloat = 56
        /// 拖动宽度低于此阈值时自动折叠为迷你列
        static let sidebarCollapseThreshold: CGFloat = 200
        /// 侧边栏宽度小于此值时，标准模式进入紧凑状态（隐藏次要文字）
        static let sidebarCompactThreshold: CGFloat = 280

        /// 侧边栏尺寸等级，按阈值驱动而非像素级传递，减少拖拽时子视图重建
        enum SidebarSizeClass: Equatable {
            /// 迷你图标列（≤ sidebarMiniWidth）
            case mini
            /// 紧凑模式（展开但宽度不足，隐藏次要文字）
            case compact
            /// 标准模式（正常宽度）
            case regular

            /// 根据当前侧边栏宽度计算尺寸等级
            static func from(width: CGFloat) -> SidebarSizeClass {
                if width <= sidebarMiniWidth {
                    return .mini
                } else if width < sidebarCompactThreshold {
                    return .compact
                } else {
                    return .regular
                }
            }
        }

        /// 根据窗口总宽度动态计算侧边栏最大宽度
        static func sidebarMaxWidth(for totalWidth: CGFloat) -> CGFloat {
            min(sidebarAbsoluteMax, totalWidth * sidebarMaxWidthRatio)
        }
        static let directoryStepMinWidth: CGFloat = 520
        static let directoryStepMinHeight: CGFloat = 540

        // 主内容区域
        static let reviewTableMinWidth: CGFloat = 300
        static let reviewTableStackedMinHeight: CGFloat = 320
        static let detailPanelMinWidth: CGFloat = 240
        static let detailPanelDefaultWidth: CGFloat = 360
        static let detailPanelMaxWidth: CGFloat = 520
        static let detailPanelDragHandleWidth: CGFloat = 8
        static let detailMinWidth: CGFloat = reviewTableMinWidth + detailPanelMinWidth + detailPanelDragHandleWidth
        static let detailIdealWidth: CGFloat = reviewTableMinWidth + detailPanelDefaultWidth + detailPanelDragHandleWidth
        static let metadataCompactDetailMinWidth: CGFloat = reviewTableMinWidth
        static let detailInlineBreakpoint: CGFloat = detailMinWidth + 120
        static let detailPanelStackedMinHeight: CGFloat = 260
        static let metadataStepMinHeight: CGFloat = 620

        // 队列面板
        static let queuePanelWidth: CGFloat = 280
        static let queuePanelMaxHeight: CGFloat = 360

        // 搜索过滤器弹性宽度
        static let searchFilterMinWidth: CGFloat = 120
        static let searchFilterMaxWidth: CGFloat = 220

        // NavigationSplitView 分隔线估算宽度
        static let navigationDividerEstimate: CGFloat = 8

        // 卡片
        static let cardMaxWidth: CGFloat = 600
        static let cardMinHeight: CGFloat = 80

        // 按钮
        static let buttonMinWidth: CGFloat = 100
        static let buttonHeight: CGFloat = 44
        static let buttonHeightCompact: CGFloat = 36

        // 表格
        static let tableRowHeight: CGFloat = 44
        static let tableHeaderHeight: CGFloat = 32

        // 播放条
        enum PlaybackBar {
            /// 紧凑布局触发阈值（窗口宽度小于此值时切换为紧凑布局）
            /// - 取值范围：600-900（推荐 720）
            /// - 说明：过小会导致内联布局时控件拥挤，过大会过早切换到紧凑布局
            static let compactThreshold: CGFloat = 720

            /// 超紧凑布局触发阈值（窗口宽度小于此值时切换为超紧凑布局，控制区和曲目摘要折行）
            static let ultraCompactThreshold: CGFloat = 480

            /// 紧凑布局下的曲目摘要区域最小宽度
            /// - 取值范围：140-200（推荐 150）
            /// - 说明：确保标题与副标题在紧凑布局中仍可读
            static let trackSummaryMinWidth: CGFloat = 150

            /// 紧凑布局下的控制区最小宽度
            /// - 说明：保证上一首/播放/下一首及功能按钮（随机/循环/音量/队列）排列不拥挤
            static let controlSectionMinWidth: CGFloat = 260

            /// 曲目摘要区域总宽度（封面 + 标题两行）
            static let trackSummaryWidth: CGFloat = 180

            /// 曲目摘要滚动文本（标题/艺术家）可视宽度
            static let trackTitleTextWidth: CGFloat = 132

            /// 曲目主标题字号
            static let trackTitleFontSize: CGFloat = 13

            /// 曲目副标题（艺术家/专辑）字号
            static let trackSubtitleFontSize: CGFloat = 11

            /// 音量弹窗内滑杆宽度
            static let volumeSliderWidth: CGFloat = 140

            /// 控制按钮高度
            /// - 取值范围：36-52（推荐 44）
            /// - 说明：影响播放条内联布局的最小高度，需与 macOS 点击热区标准保持一致
            static let controlButtonHeight: CGFloat = 44

            /// 紧凑布局总高度
            /// - 取值范围：80-140（推荐 108）
            /// - 说明：需容纳进度条+控制区两行内容，确保各元素间距合理
            /// - 约束：应 ≥ (artworkSize + compactPadding * 2 + 时间标签高度 + 间距)
            static let compactHeight: CGFloat = 108

            /// 超紧凑布局总高度
            /// - 说明：需要容纳进度条+控制区+摘要区三行内容
            static let ultraCompactHeight: CGFloat = 136

            /// 内联布局总高度
            /// - 计算公式：controlButtonHeight + (inlinePadding * 2)
            /// - 取值范围：52-68（当前约 60）
            /// - 说明：自动计算，确保控制按钮上下有足够内边距
            static var inlineHeight: CGFloat {
                controlButtonHeight + (Spacing.xs * 2)
            }

            /// 内联布局垂直内边距
            /// - 取值：Spacing.xs (8pt)
            /// - 说明：控制区上下边距，影响 inlineHeight 计算
            static let inlinePadding = Spacing.xs

            /// 紧凑布局垂直内边距
            /// - 取值：Spacing.xxxs (2pt)
            /// - 说明：紧凑模式下的最小内边距，保持紧凑同时不显得拥挤
            static let compactPadding = Spacing.xxxs

            /// 水平内边距（内联单行模式）
            /// - 从 Spacing.xxxl (64pt) 减少到 Spacing.md (16pt)，使播放器能更充满所在区域并显著推迟切换到紧凑模式的阈值
            static let horizontalPadding = Spacing.md

            /// 紧凑布局水平内边距
            /// - 从 Spacing.lg (24pt) 减少到 Spacing.sm (12pt)，在窄窗口下释出更多水平可用空间，防止文字截断
            static let compactHorizontalPadding = Spacing.sm

            /// 时间标签最小宽度
            /// - 说明：作为 minWidth 使用，配合等宽数字字体，文本超出时按自然宽度扩展；
            ///   宽度仅在时间位数变化时才改变，既避免播放期间的频谱抖动，又消除标签两侧多余留白
            static let timeLabelWidth: CGFloat = 28

            /// 音乐图标尺寸
            /// - 取值范围：28-48（推荐 36）
            /// - 说明：方形图标边长，影响曲目摘要区域的视觉平衡
            /// - 约束：应小于 controlButtonHeight，建议为 controlButtonHeight 的 0.8-0.9 倍
            static let artworkSize: CGFloat = 36

            /// 主控制按钮尺寸（播放/暂停）
            /// - 取值范围：44-60（推荐 52）
            /// - 说明：圆形按钮直径，作为视觉焦点应最大
            /// - 约束：应 ≥ secondaryButtonSize，建议比 secondaryButtonSize 大 8-12pt
            static let primaryButtonSize: CGFloat = 52

            /// 次要控制按钮尺寸（上一首/下一首）
            /// - 取值范围：36-52（推荐 44）
            /// - 说明：圆形按钮直径，与 controlButtonHeight 一致
            /// - 约束：应 ≥ actionButtonSize，应 ≤ primaryButtonSize
            static let secondaryButtonSize: CGFloat = 44

            /// 功能按钮尺寸（随机/队列）
            /// - 取值范围：24-40（推荐 32）
            /// - 说明：方形按钮边长，作为辅助功能应最小
            /// - 约束：应 < secondaryButtonSize，建议为 secondaryButtonSize 的 0.7-0.8 倍
            static let actionButtonSize: CGFloat = 32

            /// 紧凑布局下播放条内容区域（不含左右边距）的最小宽度
            static var compactContentMinWidth: CGFloat {
                trackSummaryMinWidth + controlSectionMinWidth + DesignSystem.Spacing.sm
            }

            /// 紧凑布局下播放条的最小总宽度（含左右边距）
            static var compactMinimumWidth: CGFloat {
                compactContentMinWidth + (compactHorizontalPadding * 2)
            }

            /// 频谱可视化器参数（Winamp 经典风格）
            enum Spectrum {
                /// 频谱柱条数量（与 FFT 频带数对齐）
                static let barCount: Int = 40
                /// 柱条间隔（像素级间隔营造 LED 矩阵感）
                static let barGap: CGFloat = 1.0
                /// 每段高度（柱条由多段堆叠而成）
                static let segmentHeight: CGFloat = 2.0
                /// 段间距（暗缝强化像素化效果）
                static let segmentGap: CGFloat = 0.5
                /// 峰值保持时间（到达新高点后悬停）
                static let peakHoldDuration: TimeInterval = 0.5
                /// 峰值下落速度（归一化/秒，模拟重力）
                /// 峰值下落重力加速度（模拟自由落体，归一化/秒²）
                static let peakGravity: Float = 2.2
                /// 柱条上升平滑系数（快速响应）
                static let smoothingUp: Float = 0.8
                /// 柱条下降平滑系数（快速回落，迅速空出下落空间）
                static let smoothingDown: Float = 0.2
                /// 频谱淡入时长
                static let fadeInDuration: TimeInterval = 0.3
                /// 频谱淡出时长
                static let fadeOutDuration: TimeInterval = 1.5
                /// 频谱背景遮罩透明度（确保控件可读性）
                static let overlayOpacity: Double = 0.2

                // --- 交互与 hover 效果参数 ---
                /// Hover 状态下频谱淡出的目标透明度（降低火焰亮度以突显进度条）
                static let hoverOpacity: Double = 0.14
                /// 交互淡入淡出动画过渡时长
                static let hoverTransitionDuration: TimeInterval = 0.2

                // --- 双声道布局与视觉参数 ---
                /// 左右双声道频谱之间的间隔宽度
                static let dualChannelGap: CGFloat = 6.0
                /// 双声道中间垂直分割线的不透明度
                static let dividerOpacity: Double = 0.15
                
                // --- 声道背景与水印调配 ---
                /// 左声道专属冷色调背景色
                static let leftChannelBgColor = Color(red: 0.05, green: 0.07, blue: 0.15)
                /// 右声道专属暖色调背景色
                static let rightChannelBgColor = Color(red: 0.15, green: 0.05, blue: 0.05)
                
                /// 动态自适应频带分段时的每根柱子参考宽度（影响窄窗口降采样）
                static let barWidthDivisor: CGFloat = 12.0
                
                /// 水印字体大小
                static let watermarkFontSize: CGFloat = 16.0
                /// 水印字符距离顶部边界的内边距
                static let watermarkPadding: CGFloat = 8.0
                /// 水印字符距离中线的水平间距（L 在中线左侧、R 在中线右侧）
                static let watermarkCenterSpacing: CGFloat = 8.0
                /// 水印字符的不透明度
                static let watermarkOpacity: Double = 0.7
                /// 左声道 L 水印主体颜色（淡荧光蓝）
                static let leftWatermarkColor = Color(red: 0.45, green: 0.75, blue: 1.0)
                /// 右声道 R 水印主体颜色（淡荧光红）
                static let rightWatermarkColor = Color(red: 1.0, green: 0.45, blue: 0.45)
            }
        }
    }

    // MARK: - Icons

    /// 常用图标
    enum Icons {
        // 文件和文件夹
        static let folder = "folder.fill"
        static let file = "doc.fill"
        static let music = "music.note"
        static let musicList = "music.note.list"

        // 操作
        static let add = "plus"
        static let remove = "minus"
        static let edit = "pencil"
        static let delete = "trash"
        static let selectAll = "checkmark.square"
        static let deselectAll = "xmark.square"
        static let search = "magnifyingglass"
        static let filter = "line.3.horizontal.decrease.circle"
        static let sort = "arrow.up.arrow.down"
        static let refresh = "arrow.clockwise"

        // 状态
        static let success = "checkmark.circle.fill"
        static let warning = "exclamationmark.triangle.fill"
        static let error = "xmark.circle.fill"
        static let info = "info.circle.fill"
        static let loading = "hourglass"
        static let pending = "clock"

        // AI
        static let ai = "wand.and.stars"
        static let sparkle = "sparkles"

        // 导航
        static let back = "chevron.left"
        static let forward = "chevron.right"
        static let up = "chevron.up"
        static let down = "chevron.down"

        // 设置
        static let settings = "gear"
        static let reset = "arrow.counterclockwise"
    }
}

// MARK: - View Extensions

extension View {
    /// 应用卡片样式
    func cardStyle() -> some View {
        self
            .padding(DesignSystem.Spacing.cardPadding)
            .background(DesignSystem.Colors.backgroundElevated)
            .cornerRadius(DesignSystem.CornerRadius.md)
            .shadow(
                color: DesignSystem.Shadows.small.color,
                radius: DesignSystem.Shadows.small.radius,
                x: DesignSystem.Shadows.small.x,
                y: DesignSystem.Shadows.small.y
            )
    }

    /// 应用section样式
    func sectionStyle() -> some View {
        self
            .padding(DesignSystem.Spacing.md)
            .background(DesignSystem.Colors.backgroundSecondary)
            .cornerRadius(DesignSystem.CornerRadius.sm)
    }

    /// 应用主按钮样式
    func primaryButtonStyle() -> some View {
        self
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(DesignSystem.Colors.primary)
            .foregroundColor(.white)
            .cornerRadius(DesignSystem.CornerRadius.md)
    }

    /// 应用次要按钮样式
    func secondaryButtonStyle() -> some View {
        self
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background(DesignSystem.Colors.backgroundTertiary)
            .foregroundColor(DesignSystem.Colors.textPrimary)
            .cornerRadius(DesignSystem.CornerRadius.md)
    }
}
