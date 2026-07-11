//
//  SpectrumVisualizerView.swift
//  ReTagger
//
//  Winamp 经典频谱可视化器：LED 矩阵风格的频谱柱条 + 峰值指示块缓慢下落。
//  已升级：支持纯火热色彩模式、连续流体渐变模式、自适应频带数、以及左右声道独立双声道并排。
//
//  性能优化：使用 AppKit NSView 局部绘图代替 SwiftUI Canvas/TimelineView。
//  极致优化：实现零分配重采样与段矩形缓存，通过 Combine 直接订阅解耦 SwiftUI body 高频刷新。
//  终极优化：在播放期间移除常规 Timer，由数据源直推重绘；暂停时启动 0.5 秒临时 Timer 平滑回零，之后自动销毁，实现绝对精简。
//

import SwiftUI
import AppKit
import QuartzCore
import Combine

struct SpectrumVisualizerView: View {
    @EnvironmentObject private var coordinator: AppCoordinator

    /// 频谱数据（兼容预览，在普通播放时可为空）
    let spectrumData: [Float]?
    /// 播放控制器（在播放栏播放时传入，用于实现高能 Combine 订阅）
    let controller: PlaybackController?
    /// 是否正在播放
    let isPlaying: Bool

    // 向后兼容的初始化（用于设置预览等）
    init(spectrumData: [Float], isPlaying: Bool) {
        self.spectrumData = spectrumData
        self.controller = nil
        self.isPlaying = isPlaying
    }

    // 播放条专用的高效初始化（无 SwiftUI 刷新）
    init(controller: PlaybackController, isPlaying: Bool) {
        self.spectrumData = nil
        self.controller = controller
        self.isPlaying = isPlaying
    }

    private var flameColorMode: Bool {
        coordinator.settings.flameColorMode ?? false
    }

    private var continuousSpectrum: Bool {
        coordinator.settings.continuousSpectrum ?? false
    }

    private var dualChannelSpectrum: Bool {
        coordinator.settings.dualChannelSpectrum ?? false
    }

    var body: some View {
        SpectrumNSViewRepresentable(
            spectrumData: spectrumData,
            controller: controller,
            isPlaying: isPlaying,
            flameColorMode: flameColorMode,
            continuousSpectrum: continuousSpectrum,
            dualChannelSpectrum: dualChannelSpectrum
        )
    }
}

struct SpectrumNSViewRepresentable: NSViewRepresentable {
    let spectrumData: [Float]?
    let controller: PlaybackController?
    let isPlaying: Bool
    let flameColorMode: Bool
    let continuousSpectrum: Bool
    let dualChannelSpectrum: Bool

    func makeNSView(context: Context) -> SpectrumNSView {
        let view = SpectrumNSView()
        if let controller = controller {
            view.bind(to: controller)
        } else if let spectrumData = spectrumData {
            view.spectrumData = spectrumData
        }
        view.isPlaying = isPlaying
        view.flameColorMode = flameColorMode
        view.continuousSpectrum = continuousSpectrum
        view.dualChannelSpectrum = dualChannelSpectrum
        return view
    }

    func updateNSView(_ nsView: SpectrumNSView, context: Context) {
        // 在播放模式下，数据由 Combine 回调更新，updateNSView 只同步非数据状态
        if let spectrumData = spectrumData {
            nsView.spectrumData = spectrumData
        }
        nsView.isPlaying = isPlaying
        nsView.flameColorMode = flameColorMode
        nsView.continuousSpectrum = continuousSpectrum
        nsView.dualChannelSpectrum = dualChannelSpectrum
    }
}

class SpectrumNSView: NSView {
    // 外部参数
    var spectrumData: [Float] = [] {
        didSet {
            guard oldValue != spectrumData else { return }
            updateBands(newData: spectrumData)
        }
    }
    
    var isPlaying: Bool = false {
        didSet {
            if oldValue != isPlaying {
                if !isPlaying {
                    startDecayTimerIfNeeded()
                } else {
                    stopDecayTimer()
                }
            }
        }
    }
    
    var flameColorMode: Bool = false {
        didSet {
            if oldValue != flameColorMode {
                triggerRepaint()
            }
        }
    }
    
    var continuousSpectrum: Bool = false {
        didSet {
            if oldValue != continuousSpectrum {
                triggerRepaint()
            }
        }
    }
    
    var dualChannelSpectrum: Bool = false {
        didSet {
            if oldValue != dualChannelSpectrum {
                triggerRepaint()
            }
        }
    }

    override var isFlipped: Bool {
        return false // 显式声明未翻转，左下角为 (0,0)
    }
    
    // 内部动画状态
    private var bandCount = 40
    private var smoothedBands: [Float] = []
    private var peakLevels: [Float] = []
    private var peakHoldTimers: [CFTimeInterval] = []
    private var peakVelocities: [Float] = []
    private var lastFrameTime: CFTimeInterval = 0
    private var initialized = false
    
    // 时钟与 Combine 订阅
    private var decayTimer: DispatchSourceTimer?
    private var isAppActive: Bool = true
    private var cancellable: AnyCancellable?
    
    // 零分配优化缓存，避免在每一帧的 draw/resample 过程中分配和释放内存
    private var smoothResampleBuffer: [Float] = []
    private var peaksResampleBuffer: [Float] = []
    private var rectsBySegmentCache: [[CGRect]] = []
    private var peakRectsCache: [CGRect] = []
    
    // 缓存颜色与渐变
    private var cachedColorLUT: [NSColor] = []
    private var cachedSegmentCount: Int = 0
    private var cachedIsFlame: Bool = false
    
    private var flameGradient: CGGradient? = nil
    private var classicGradient: CGGradient? = nil
    
    // NSColor 物理映射，免去 SwiftUI Color 跨框架转换开销
    private let leftChannelBgNSColor = NSColor(red: 0.05, green: 0.07, blue: 0.15, alpha: 1.0)
    private let rightChannelBgNSColor = NSColor(red: 0.15, green: 0.05, blue: 0.05, alpha: 1.0)
    private let leftWatermarkNSColor = NSColor(red: 0.45, green: 0.75, blue: 1.0, alpha: 1.0)
    private let rightWatermarkNSColor = NSColor(red: 1.0, green: 0.45, blue: 0.45, alpha: 1.0)
    
    // 水印文本图层，免去每一帧的文本排版底噪
    private let leftWatermarkLayer = CATextLayer()
    private let rightWatermarkLayer = CATextLayer()
    
    private let cellWidthPercentage: CGFloat = 0.72

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupLayers()
        setupNotificationObservers()
        resetAnimation()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
        setupNotificationObservers()
        resetAnimation()
    }
    
    func bind(to controller: PlaybackController) {
        // 直接在 AppKit 层面订阅频谱高频数据流，彻底切断 SwiftUI Body 在前台播放时的重绘联动
        cancellable = controller.spectrumDataStore.$spectrumData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newData in
                guard let self = self, self.isPlaying && self.isAppActive else { return }
                self.spectrumData = newData
            }
    }
    
    private func setupLayers() {
        wantsLayer = true
        layer?.masksToBounds = true
        
        let spec = DesignSystem.Layout.PlaybackBar.Spectrum.self
        let font = NSFont.monospacedSystemFont(ofSize: spec.watermarkFontSize, weight: .bold)
        
        for (layer, text) in [(leftWatermarkLayer, "L"), (rightWatermarkLayer, "R")] {
            layer.string = text
            layer.font = font
            layer.fontSize = spec.watermarkFontSize
            layer.alignmentMode = .center
            layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
            layer.opacity = 0
            self.layer?.addSublayer(layer)
        }
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(appDidBecomeActive), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appDidResignActive), name: NSApplication.didResignActiveNotification, object: nil)
    }
    
    @objc private func appDidBecomeActive() {
        isAppActive = true
    }
    
    @objc private func appDidResignActive() {
        isAppActive = false
        stopDecayTimer()
        resetAnimation()
    }
    
    override func layout() {
        super.layout()
        let spec = DesignSystem.Layout.PlaybackBar.Spectrum.self
        let size = spec.watermarkFontSize + 4
        let y = bounds.height - spec.watermarkPadding - size

        // 与 draw(_:) 中双声道分割逻辑一致，求出物理像素对齐的中线位置，
        // L / R 水印分别贴靠在中线两侧
        let scale = self.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        let totalPhysicalWidth = bounds.width * scale
        let gapPhysical = round(spec.dualChannelGap * scale)
        let leftPhysicalWidth = floor((totalPhysicalWidth - gapPhysical) / 2.0)
        let dividerX = (leftPhysicalWidth + gapPhysical / 2.0) / scale

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        leftWatermarkLayer.frame = CGRect(x: dividerX - spec.watermarkCenterSpacing - size, y: y, width: size, height: size)
        rightWatermarkLayer.frame = CGRect(x: dividerX + spec.watermarkCenterSpacing, y: y, width: size, height: size)
        CATransaction.commit()
    }
    
    private func resetAnimation() {
        smoothedBands = [Float](repeating: 0, count: bandCount)
        peakLevels = [Float](repeating: 0, count: bandCount)
        peakHoldTimers = [CFTimeInterval](repeating: 0, count: bandCount)
        peakVelocities = [Float](repeating: 0, count: bandCount)
        initialized = false
        triggerRepaint()
    }
    
    private func triggerRepaint() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.setNeedsDisplay(self.bounds)
        }
    }
    
    private func startDecayTimerIfNeeded() {
        stopDecayTimer()
        
        // 检查是否已经都回零了，如果本来就都回零了，就不用开了
        guard smoothedBands.contains(where: { $0 > 0 }) || peakLevels.contains(where: { $0 > 0 }) else {
            resetAnimation()
            return
        }
        
        let source = DispatchSource.makeTimerSource(queue: DispatchQueue.main)
        source.schedule(deadline: .now(), repeating: 0.033)
        source.setEventHandler { [weak self] in
            self?.decayTick()
        }
        source.resume()
        decayTimer = source
    }
    
    private func stopDecayTimer() {
        decayTimer?.cancel()
        decayTimer = nil
    }
    
    private func decayTick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastFrameTime, 0.1)
        lastFrameTime = now
        
        let spec = DesignSystem.Layout.PlaybackBar.Spectrum.self
        var hasActiveElement = false
        
        for i in 0..<bandCount {
            if smoothedBands[i] > 0 {
                smoothedBands[i] = max(0, smoothedBands[i] - Float(dt) * 5.0)
            }
            
            if smoothedBands[i] > peakLevels[i] {
                peakLevels[i] = smoothedBands[i]
                peakHoldTimers[i] = spec.peakHoldDuration
                peakVelocities[i] = 0.0
            } else if peakHoldTimers[i] > 0 {
                peakHoldTimers[i] -= dt
                peakVelocities[i] = 0.0
            } else {
                peakVelocities[i] += spec.peakGravity * Float(dt)
                peakLevels[i] = max(0, peakLevels[i] - peakVelocities[i] * Float(dt))
                
                if peakLevels[i] < smoothedBands[i] {
                    peakLevels[i] = smoothedBands[i]
                    peakVelocities[i] = 0.0
                }
            }
            
            if peakLevels[i] < 0.005 {
                peakLevels[i] = 0.0
                peakVelocities[i] = 0.0
            }
            if smoothedBands[i] < 0.005 {
                smoothedBands[i] = 0.0
            }
            
            if smoothedBands[i] > 0 || peakLevels[i] > 0 {
                hasActiveElement = true
            }
        }
        
        self.setNeedsDisplay(self.bounds)
        
        if !hasActiveElement {
            stopDecayTimer()
            resetAnimation()
        }
    }
    
    private func updateBands(newData: [Float]) {
        let now = CACurrentMediaTime()
        let dt: CFTimeInterval
        if !initialized {
            initialized = true
            lastFrameTime = now
            dt = 0.033
        } else {
            dt = min(now - lastFrameTime, 0.1)
            lastFrameTime = now
        }
        
        let currentBands = newData
        let isDual = dualChannelSpectrum && currentBands.count >= 80
        let targetCount = isDual ? 80 : 40
        
        if smoothedBands.count != targetCount {
            bandCount = targetCount
            smoothedBands = [Float](repeating: 0, count: targetCount)
            peakLevels = [Float](repeating: 0, count: targetCount)
            peakHoldTimers = [CFTimeInterval](repeating: 0, count: targetCount)
            peakVelocities = [Float](repeating: 0, count: targetCount)
        }
        
        let spec = DesignSystem.Layout.PlaybackBar.Spectrum.self
        
        var rawBands = [Float](repeating: 0, count: targetCount)
        if isDual {
            for i in 0..<80 {
                rawBands[i] = i < currentBands.count ? currentBands[i] : 0
            }
        } else {
            if currentBands.count >= 80 {
                for i in 0..<40 {
                    rawBands[i] = (currentBands[i] + currentBands[i + 40]) / 2.0
                }
            } else {
                for i in 0..<40 {
                    rawBands[i] = i < currentBands.count ? currentBands[i] : 0
                }
            }
        }
        
        for i in 0..<targetCount {
            let target = rawBands[i]
            let current = smoothedBands[i]
            
            if target > current {
                smoothedBands[i] = current + (target - current) * Float(spec.smoothingUp)
            } else {
                smoothedBands[i] = current + (target - current) * Float(spec.smoothingDown)
            }
            
            if smoothedBands[i] < 0.005 {
                smoothedBands[i] = 0.0
            }
            
            if smoothedBands[i] > peakLevels[i] {
                peakLevels[i] = smoothedBands[i]
                peakHoldTimers[i] = spec.peakHoldDuration
                peakVelocities[i] = 0.0
            } else if peakHoldTimers[i] > 0 {
                peakHoldTimers[i] -= dt
                peakVelocities[i] = 0.0
            } else {
                peakVelocities[i] += spec.peakGravity * Float(dt)
                peakLevels[i] = max(0, peakLevels[i] - peakVelocities[i] * Float(dt))
                
                if peakLevels[i] < smoothedBands[i] {
                    peakLevels[i] = smoothedBands[i]
                    peakVelocities[i] = 0.0
                }
            }
            
            if peakLevels[i] < 0.005 {
                peakLevels[i] = 0.0
                peakVelocities[i] = 0.0
            }
        }
        
        self.setNeedsDisplay(self.bounds)
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        
        let size = bounds.size
        
        // 1. 绘制深色背景
        context.setFillColor(NSColor(white: 0.05, alpha: 1.0).cgColor)
        context.fill(bounds)
        
        let spec = DesignSystem.Layout.PlaybackBar.Spectrum.self
        let isDual = dualChannelSpectrum && bandCount >= 80
        
        // 2. 更新水印可见性与颜色
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if isDual {
            leftWatermarkLayer.opacity = Float(spec.watermarkOpacity)
            rightWatermarkLayer.opacity = Float(spec.watermarkOpacity)
            leftWatermarkLayer.foregroundColor = leftWatermarkNSColor.cgColor
            rightWatermarkLayer.foregroundColor = rightWatermarkNSColor.cgColor
        } else {
            leftWatermarkLayer.opacity = 0
            rightWatermarkLayer.opacity = 0
        }
        CATransaction.commit()
        
        if isDual {
            let leftSmooth = Array(smoothedBands[0..<40])
            let leftPeak = Array(peakLevels[0..<40])
            let rightSmooth = Array(smoothedBands[40..<80])
            let rightPeak = Array(peakLevels[40..<80])
            
            // 像素对齐双声道分配
            let scale = self.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
            let totalPhysicalWidth = size.width * scale
            let gapPhysical = round(spec.dualChannelGap * scale)
            
            // 物理左声道宽度向下取整，保证左右声道在物理像素上网格完全平分对齐
            let leftPhysicalWidth = floor((totalPhysicalWidth - gapPhysical) / 2.0)
            
            let leftRect = CGRect(
                x: 0,
                y: 0,
                width: leftPhysicalWidth / scale,
                height: size.height
            )
            let rightRect = CGRect(
                x: (leftPhysicalWidth + gapPhysical) / scale,
                y: 0,
                width: (totalPhysicalWidth - leftPhysicalWidth - gapPhysical) / scale,
                height: size.height
            )
            
            // 左右声道微弱冷暖背景色区别
            context.setFillColor(leftChannelBgNSColor.cgColor)
            context.fill(leftRect)
            context.setFillColor(rightChannelBgNSColor.cgColor)
            context.fill(rightRect)
            
            // 中间垂直分界线位置对齐物理像素
            let dividerX = (leftPhysicalWidth + gapPhysical / 2.0) / scale
            context.setStrokeColor(NSColor.white.withAlphaComponent(CGFloat(spec.dividerOpacity)).cgColor)
            context.setLineWidth(1.0)
            context.move(to: CGPoint(x: dividerX, y: 0))
            context.addLine(to: CGPoint(x: dividerX, y: size.height))
            context.strokePath()
            
            // 绘制左声道
            context.saveGState()
            context.clip(to: leftRect)
            drawSingleSpectrum(in: context, rect: leftRect, smoothed: leftSmooth, peaks: leftPeak, spec: spec)
            context.restoreGState()
            
            // 绘制右声道
            context.saveGState()
            context.clip(to: rightRect)
            drawSingleSpectrum(in: context, rect: rightRect, smoothed: rightSmooth, peaks: rightPeak, spec: spec)
            context.restoreGState()
        } else {
            let smoothed = bandCount >= 40 ? Array(smoothedBands[0..<40]) : smoothedBands
            let peaks = bandCount >= 40 ? Array(peakLevels[0..<40]) : peakLevels
            drawSingleSpectrum(in: context, rect: bounds, smoothed: smoothed, peaks: peaks, spec: spec)
        }
    }
    
    private func drawSingleSpectrum(
        in context: CGContext,
        rect: CGRect,
        smoothed: [Float],
        peaks: [Float],
        spec: DesignSystem.Layout.PlaybackBar.Spectrum.Type
    ) {
        guard !smoothed.isEmpty else { return }
        
        let targetBarCount = spec.barCount
        
        // 零分配重采样：写入预分配好的全局成员 buffer
        resample(smoothed, to: targetBarCount, result: &smoothResampleBuffer)
        resample(peaks, to: targetBarCount, result: &peaksResampleBuffer)
        
        let scale = self.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2.0
        
        // 1. 获取当前区域的总物理像素宽度
        let totalPhysicalWidth = rect.width * scale
        
        // 2. 每个 cell 的物理像素宽度向下取整，保证物理上最少 2 像素宽（1 像素柱条 + 1 像素间隙）
        let cellPhysicalWidthRounded = max(2.0, floor(totalPhysicalWidth / CGFloat(targetBarCount)))
        
        // 3. 计算物理像素下的柱条宽度：通过 cellWidthPercentage (72%) 进行比例分配并取整
        var barPhysicalWidth = round(cellPhysicalWidthRounded * cellWidthPercentage)
        // 确保柱条宽度至少为 1 物理像素，且比 cellWidth 至少窄 1 物理像素，给间隙留下至少 1 像素空间
        barPhysicalWidth = max(1.0, min(barPhysicalWidth, cellPhysicalWidthRounded - 1.0))
        
        let gapPhysicalWidth = cellPhysicalWidthRounded - barPhysicalWidth
        
        // 4. 计算所有 cell 使用的总物理宽度
        let totalUsedPhysicalWidth = cellPhysicalWidthRounded * CGFloat(targetBarCount) - gapPhysicalWidth
        
        // 5. 计算未分配的富余物理像素
        let remainingPhysicalWidth = max(0.0, totalPhysicalWidth - totalUsedPhysicalWidth)
        
        // 6. 物理侧边距向下取整，折算回逻辑像素，保证侧边距在物理上也是完美像素对齐的
        let leftSidePaddingPhysical = floor(remainingPhysicalWidth / 2.0)
        let sidePadding = leftSidePaddingPhysical / scale
        
        // 折算成逻辑像素的 cellWidth 和 barWidth
        let logicalCellWidth = cellPhysicalWidthRounded / scale
        let logicalBarWidth = barPhysicalWidth / scale
        
        let segHeight = CGFloat(spec.segmentHeight)
        let segGap = CGFloat(spec.segmentGap)
        let stepHeight = segHeight + segGap
        let totalSegments = max(1, Int(rect.height / stepHeight))
        
        if continuousSpectrum {
            let gradient = getGradient(isFlame: flameColorMode)
            let path = CGMutablePath()
            var hasPath = false
            
            let peakPath = CGMutablePath()
            var hasPeakPath = false
            
            for i in 0..<targetBarCount {
                let x = rect.minX + sidePadding + CGFloat(i) * logicalCellWidth
                let level = smoothResampleBuffer[i]
                
                if level > 0 {
                    // 纵向高度也进行物理像素取整，使顶部切割平滑清晰
                    let rawHeight = rect.height * CGFloat(level)
                    let h = floor(rawHeight * scale) / scale
                    let fillRect = CGRect(x: x, y: rect.minY, width: logicalBarWidth, height: h)
                    path.addRect(fillRect)
                    hasPath = true
                }
                
                let peakLevel = peaksResampleBuffer[i]
                if peakLevel > 0 {
                    // 纵向峰值块 y 坐标同样进行物理像素取整
                    let rawPeakY = rect.minY + rect.height * CGFloat(peakLevel)
                    let peakY = floor(rawPeakY * scale) / scale
                    let peakRect = CGRect(x: x, y: peakY, width: logicalBarWidth, height: 2.0)
                    peakPath.addRect(peakRect)
                    hasPeakPath = true
                }
            }
            
            if hasPath && gradient != nil {
                context.saveGState()
                context.addPath(path)
                context.clip()
                context.drawLinearGradient(
                    gradient!,
                    start: CGPoint(x: rect.minX, y: rect.minY),
                    end: CGPoint(x: rect.minX, y: rect.maxY),
                    options: []
                )
                context.restoreGState()
            }
            
            if hasPeakPath {
                context.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
                context.addPath(peakPath)
                context.fillPath()
            }
        } else {
            let colorLUT = getColorLUT(segmentCount: totalSegments, isFlame: flameColorMode)
            
            if rectsBySegmentCache.count < totalSegments {
                while rectsBySegmentCache.count < totalSegments {
                    rectsBySegmentCache.append([])
                }
            }
            
            for seg in 0..<totalSegments {
                rectsBySegmentCache[seg].removeAll(keepingCapacity: true)
            }
            peakRectsCache.removeAll(keepingCapacity: true)
            
            for i in 0..<targetBarCount {
                let x = rect.minX + sidePadding + CGFloat(i) * logicalCellWidth
                let level = smoothResampleBuffer[i]
                
                let activeSegments = min(totalSegments, Int(Float(totalSegments) * level))
                for seg in 0..<activeSegments {
                    let y = rect.minY + CGFloat(seg) * stepHeight
                    let segRect = CGRect(x: x, y: y, width: logicalBarWidth, height: segHeight)
                    rectsBySegmentCache[seg].append(segRect)
                }
                
                let peakLevel = peaksResampleBuffer[i]
                let peakSeg = min(totalSegments, Int(Float(totalSegments) * peakLevel))
                if peakSeg > 0 {
                    let peakY = rect.minY + CGFloat(peakSeg - 1) * stepHeight
                    let peakRect = CGRect(x: x, y: peakY, width: logicalBarWidth, height: segHeight)
                    peakRectsCache.append(peakRect)
                }
            }
            
            for seg in 0..<totalSegments {
                let rects = rectsBySegmentCache[seg]
                if !rects.isEmpty {
                    let color = colorLUT[min(seg, colorLUT.count - 1)]
                    context.setFillColor(color.cgColor)
                    context.fill(rects)
                }
            }
            
            if !peakRectsCache.isEmpty {
                context.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
                context.fill(peakRectsCache)
            }
        }
    }
    
    private func resample(_ source: [Float], to targetCount: Int, result: inout [Float]) {
        if result.count != targetCount {
            result = [Float](repeating: 0, count: targetCount)
        }
        guard !source.isEmpty else {
            for i in 0..<targetCount { result[i] = 0 }
            return
        }
        if source.count == targetCount {
            for i in 0..<targetCount { result[i] = source[i] }
            return
        }
        
        let scale = Double(source.count) / Double(targetCount)
        for i in 0..<targetCount {
            let start = Int(floor(Double(i) * scale))
            let end = min(source.count - 1, Int(ceil(Double(i + 1) * scale) - 1))
            var maxValue: Float = 0
            if start <= end {
                for j in start...end {
                    maxValue = max(maxValue, source[j])
                }
            } else {
                maxValue = source[min(source.count - 1, start)]
            }
            result[i] = maxValue
        }
    }
    
    private func getGradient(isFlame: Bool) -> CGGradient? {
        if isFlame {
            if let cached = flameGradient { return cached }
            let colors = [
                NSColor(red: 0.85, green: 0, blue: 0, alpha: 1.0).cgColor,
                NSColor(red: 1.0, green: 0.4, blue: 0, alpha: 1.0).cgColor,
                NSColor(red: 1.0, green: 0.9, blue: 0.1, alpha: 1.0).cgColor,
                NSColor(red: 1.0, green: 1.0, blue: 0.9, alpha: 1.0).cgColor
            ] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let locations: [CGFloat] = [0.0, 0.3, 0.7, 1.0]
            flameGradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations)
            return flameGradient
        } else {
            if let cached = classicGradient { return cached }
            let colors = [
                NSColor(red: 0, green: 1.0, blue: 0, alpha: 1.0).cgColor,
                NSColor(red: 0.8, green: 1.0, blue: 0, alpha: 1.0).cgColor,
                NSColor(red: 1.0, green: 0.6, blue: 0, alpha: 1.0).cgColor,
                NSColor(red: 1.0, green: 0, blue: 0, alpha: 1.0).cgColor
            ] as CFArray
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let locations: [CGFloat] = [0.0, 0.3, 0.7, 1.0]
            classicGradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: locations)
            return classicGradient
        }
    }
    
    private func getColorLUT(segmentCount: Int, isFlame: Bool) -> [NSColor] {
        if segmentCount == cachedSegmentCount && isFlame == cachedIsFlame && !cachedColorLUT.isEmpty {
            return cachedColorLUT
        }
        
        var lut = [NSColor]()
        lut.reserveCapacity(segmentCount)
        for seg in 0..<segmentCount {
            let ratio = Float(seg) / Float(max(1, segmentCount - 1))
            if isFlame {
                if ratio < 0.20 {
                    let t = Double(ratio / 0.20)
                    lut.append(NSColor(red: 0.85 + t * 0.15, green: t * 0.25, blue: 0, alpha: 1.0))
                } else if ratio < 0.65 {
                    let t = Double((ratio - 0.20) / 0.45)
                    lut.append(NSColor(red: 1.0, green: 0.25 + t * 0.65, blue: t * 0.1, alpha: 1.0))
                } else {
                    let t = Double((ratio - 0.65) / 0.35)
                    lut.append(NSColor(red: 1.0, green: 0.9 + t * 0.1, blue: t * 0.9, alpha: 1.0))
                }
            } else {
                if ratio < 0.25 {
                    let t = Double(ratio / 0.25)
                    lut.append(NSColor(red: t * 0.6, green: 1.0, blue: 0, alpha: 1.0))
                } else if ratio < 0.60 {
                    let t = Double((ratio - 0.25) / 0.35)
                    lut.append(NSColor(red: 0.6 + t * 0.4, green: 1.0 - t * 0.4, blue: 0, alpha: 1.0))
                } else {
                    let t = Double((ratio - 0.60) / 0.40)
                    lut.append(NSColor(red: 1.0, green: 0.6 - t * 0.6, blue: 0, alpha: 1.0))
                }
            }
        }
        
        cachedColorLUT = lut
        cachedSegmentCount = segmentCount
        cachedIsFlame = isFlame
        return lut
    }
    
    deinit {
        stopDecayTimer()
        NotificationCenter.default.removeObserver(self)
    }
}

