//
//  SpectrumAnalyzer.swift
//  ReTagger
//
//  基于 Accelerate vDSP 的实时 FFT 频谱分析器，
//  从音频 tap 接收 PCM 缓冲区，输出对数分布的频带幅度。
//

import Accelerate
import AVFoundation
import Combine
import AppKit

final class SpectrumAnalyzer {
    /// FFT 窗口大小（2 的幂次，2048 ≈ 46ms @44.1kHz，平衡精度与延迟）
    let fftSize: Int
    /// 输出频带数量（映射为可视化柱条数量）
    let bandCount: Int

    // MARK: - vDSP 预分配资源（初始化时一次性创建，全程复用）

    private let fftSetup: FFTSetup
    private let log2n: vDSP_Length
    private var hanningWindow: [Float]
    private var fftInputBuffer: [Float]
    private var realPart: [Float]
    private var imagPart: [Float]
    private var magnitudes: [Float]
    private var leftPartBands: [Float]
    private var rightPartBands: [Float]
    private var combinedBands: [Float]

    // MARK: - 输出
    
    // 频带索引映射缓存，避免在音频线程高频重复执行 pow/log 计算
    private var cachedSampleRate: Float = 0
    private var bandBinRanges: [(low: Int, high: Int)] = []

    private let bandsSubject: CurrentValueSubject<[Float], Never>

    // MARK: - 前后台状态与通知监听

    private var isAppActive = true
    private var activeObserver: Any?
    private var resignObserver: Any?

    /// 频带幅度数据流（归一化 0-1，主线程发布）
    var bandsPublisher: AnyPublisher<[Float], Never> {
        bandsSubject.eraseToAnyPublisher()
    }

    /// 当前频带快照
    var currentBands: [Float] {
        bandsSubject.value
    }

    // MARK: - 节流控制

    /// 限制发布频率，避免主线程过载
    private var lastPublishTime: CFTimeInterval = 0
    private let publishInterval: CFTimeInterval = 1.0 / 30.0

    // MARK: - 初始化

    init(fftSize: Int = 2048, bandCount: Int = 40) {
        precondition(fftSize > 0 && (fftSize & (fftSize - 1)) == 0, "fftSize 必须为 2 的幂次")

        self.fftSize = fftSize
        self.bandCount = bandCount
        self.log2n = vDSP_Length(log2(Double(fftSize)))

        // 创建 FFT 配置（一次性开销）
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            fatalError("vDSP_create_fftsetup 失败")
        }
        self.fftSetup = setup

        // 预分配缓冲区
        self.hanningWindow = [Float](repeating: 0, count: fftSize)
        self.fftInputBuffer = [Float](repeating: 0, count: fftSize)
        self.realPart = [Float](repeating: 0, count: fftSize / 2)
        self.imagPart = [Float](repeating: 0, count: fftSize / 2)
        self.magnitudes = [Float](repeating: 0, count: fftSize / 2)
        self.leftPartBands = [Float](repeating: 0, count: bandCount)
        self.rightPartBands = [Float](repeating: 0, count: bandCount)
        self.combinedBands = [Float](repeating: 0, count: bandCount * 2)

        self.bandsSubject = CurrentValueSubject([Float](repeating: 0, count: bandCount * 2))

        // 生成 Hanning 窗函数（减少频谱泄漏）
        vDSP_hann_window(&hanningWindow, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))

        self.activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isAppActive = true
        }

        self.resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.isAppActive = false
            self?.reset()
        }
    }

    deinit {
        vDSP_destroy_fftsetup(fftSetup)
        if let observer = activeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = resignObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - 处理（在音频线程调用）

    /// 处理来自 audio tap 的 PCM 缓冲区
    /// - 此方法在音频渲染线程调用，内部计算也在该线程完成，仅最终结果 dispatch 到主线程
    func process(buffer: AVAudioPCMBuffer) {
        guard isAppActive else { return }

        // 节流：30fps 发布上限
        let now = CACurrentMediaTime()
        guard now - lastPublishTime >= publishInterval else { return }

        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let sampleRate = Float(buffer.format.sampleRate)
        let copyCount = min(frameCount, fftSize)

        // 零分配计算左右声道，直接写入预分配的成员数组
        analyzeChannel(samples: channelData[0], copyCount: copyCount, sampleRate: sampleRate, result: &leftPartBands)
        if buffer.format.channelCount >= 2 {
            analyzeChannel(samples: channelData[1], copyCount: copyCount, sampleRate: sampleRate, result: &rightPartBands)
        } else {
            for i in 0..<bandCount {
                rightPartBands[i] = leftPartBands[i]
            }
        }

        // 拼装 combinedBands 缓存数组，绝对免除数组合并时的堆分配
        for i in 0..<bandCount {
            combinedBands[i] = leftPartBands[i]
            combinedBands[i + bandCount] = rightPartBands[i]
        }
        
        lastPublishTime = now
        let bandsToSend = combinedBands

        DispatchQueue.main.async { [weak self] in
            self?.bandsSubject.send(bandsToSend)
        }
    }

    /// 重置频谱数据（暂停/停止时调用）
    func reset() {
        bandsSubject.send([Float](repeating: 0, count: bandCount * 2))
    }

    // MARK: - 核心计算逻辑
    
    private func analyzeChannel(samples: UnsafePointer<Float>, copyCount: Int, sampleRate: Float, result: inout [Float]) {
        // 清零 + 拷贝 + 加窗
        _ = fftInputBuffer.withUnsafeMutableBufferPointer { buf in
            memset(buf.baseAddress!, 0, fftSize * MemoryLayout<Float>.size)
        }
        vDSP_vmul(samples, 1, hanningWindow, 1, &fftInputBuffer, 1, vDSP_Length(copyCount))

        // 通过 withUnsafeMutableBufferPointer 显式借出 realPart 和 imagPart 指针以构造 DSPSplitComplex，
        // 确保指针生命周期完全覆盖 FFT 计算区间，彻底消除 swiftc 编译警告。
        realPart.withUnsafeMutableBufferPointer { realPtr in
            imagPart.withUnsafeMutableBufferPointer { imagPtr in
                var splitComplex = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                
                fftInputBuffer.withUnsafeBufferPointer { ptr in
                    ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(fftSize / 2))
                    }
                }

                // 执行前向 FFT
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                // 计算幅度平方：magnitude^2 = re^2 + im^2
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))

                // vDSP FFT 功率谱归一化
                var scale = 4.0 / Float(fftSize * fftSize)
                vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(fftSize / 2))

                mapToBands(sampleRate: sampleRate, result: &result)
            }
        }
    }

    // MARK: - 频带映射

    private func setupBandBinRanges(sampleRate: Float) {
        cachedSampleRate = sampleRate
        bandBinRanges.removeAll(keepingCapacity: true)
        
        let binCount = fftSize / 2
        let binWidth = sampleRate / Float(fftSize)
        
        let minFreq: Float = 20.0
        let maxFreq = min(12000.0, sampleRate / 2.0)
        let logMin = log10(minFreq)
        let logMax = log10(maxFreq)

        for i in 0..<bandCount {
            let logLow = logMin + (logMax - logMin) * Float(i) / Float(bandCount)
            let logHigh = logMin + (logMax - logMin) * Float(i + 1) / Float(bandCount)
            let freqLow = pow(10, logLow)
            let freqHigh = pow(10, logHigh)

            let binLow = max(1, Int(freqLow / binWidth))
            let binHigh = min(binCount - 1, Int(freqHigh / binWidth))
            bandBinRanges.append((low: binLow, high: binHigh))
        }
    }

    /// 将 FFT bin 按对数频率分布映射到 bandCount 个频带
    private func mapToBands(sampleRate: Float, result: inout [Float]) {
        if sampleRate != cachedSampleRate || bandBinRanges.count != bandCount {
            setupBandBinRanges(sampleRate: sampleRate)
        }

        for i in 0..<bandCount {
            let range = bandBinRanges[i]
            let binLow = range.low
            let binHigh = range.high

            guard binLow <= binHigh else {
                result[i] = 0
                continue
            }

            var peak: Float = 0
            for bin in binLow...binHigh {
                peak = max(peak, magnitudes[bin])
            }

            result[i] = peak
        }

        // 转换为 dB 刻度并归一化到 0-1
        let minDB: Float = -48.0
        let maxDB: Float = -10.0

        for i in 0..<bandCount {
            var db: Float = minDB
            if result[i] > 0 {
                db = 10.0 * log10(result[i])
            }

            // 强力静音门限 (Noise Gate)
            if db < -44.0 {
                result[i] = 0.0
                continue
            }

            let volumeRatio = max(0, min(1, (db - (-44.0)) / 10.0))
            let eqCompensation = Float(i) * (8.0 / Float(bandCount - 1)) * volumeRatio
            let compensatedDB = db + eqCompensation

            let normalized = (compensatedDB - minDB) / (maxDB - minDB)
            result[i] = max(0, min(1, normalized))
        }
    }
}
