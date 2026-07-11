//
//  TimelineScheduler.swift
//  ReTagger
//
//  管理播放时间轴刷新的调度器，根据可见性自动降频或暂停。
//  通过闭包式 timeProvider 解耦具体播放引擎，支持 AVPlayer / AVAudioEngine 等任意实现。
//

import Foundation

enum TimelineVisibility: Equatable {
    case interactive
    case visible
    case hidden
    case background
}

final class TimelineScheduler {
    enum Activity: Equatable {
        /// 正常交互状态，高频刷新（0.25s）
        case interactive
        /// 空闲/不可见状态，低频刷新（1.0s）
        case idle
        /// 完全挂起，停止定时器
        case suspended
    }

    /// 时间提供闭包，返回当前播放时间（秒）。返回 nil 表示无有效时间。
    private var timeProvider: (() -> TimeInterval?)?
    /// 时间更新回调，在主线程调用
    private var handler: ((TimeInterval) -> Void)?
    private var activity: Activity = .suspended
    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(
        label: "com.retagger.timeline-scheduler",
        qos: .userInteractive
    )

    /// 配置调度器
    /// - Parameters:
    ///   - timeProvider: 在定时器队列调用，返回当前播放时间
    ///   - handler: 在主线程调用，接收最新播放时间
    func configure(
        timeProvider: @escaping () -> TimeInterval?,
        handler: @escaping (TimeInterval) -> Void
    ) {
        self.timeProvider = timeProvider
        self.handler = handler
        applyActivity(activity)
    }

    func updateActivity(_ newActivity: Activity) {
        guard newActivity != activity else { return }
        activity = newActivity
        applyActivity(newActivity)
    }

    private func applyActivity(_ activity: Activity) {
        stopTimer()
        guard timeProvider != nil, handler != nil else { return }

        let interval: TimeInterval
        switch activity {
        case .interactive:
            interval = 0.25
        case .idle:
            interval = 1.0
        case .suspended:
            return
        }

        let source = DispatchSource.makeTimerSource(queue: timerQueue)
        source.schedule(deadline: .now(), repeating: interval)
        source.setEventHandler { [weak self] in
            guard let self,
                  let provider = self.timeProvider,
                  let callback = self.handler else { return }
            if let time = provider() {
                DispatchQueue.main.async {
                    callback(time)
                }
            }
        }
        source.resume()
        timer = source
    }

    private func stopTimer() {
        timer?.cancel()
        timer = nil
    }

    deinit {
        stopTimer()
    }
}
