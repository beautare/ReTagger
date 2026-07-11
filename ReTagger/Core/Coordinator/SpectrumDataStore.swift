//
//  SpectrumDataStore.swift
//  ReTagger
//
//  独立的频谱数据容器，将高频更新（30fps）隔离在专用 ObservableObject 中，
//  避免频谱数据变化触发 PlaybackBarView 整棵视图树的 body 重新求值。
//

import Combine
import Foundation

@MainActor
final class SpectrumDataStore: ObservableObject {
    /// 实时频谱数据（左右声道各 40 个频带，共 80 个归一化幅度 0-1）
    @Published private(set) var spectrumData: [Float] = []

    private var cancellable: AnyCancellable?

    /// 将上游频谱数据流接入本容器
    func bind(to publisher: AnyPublisher<[Float], Never>) {
        cancellable = publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] bands in
                self?.spectrumData = bands
            }
    }
}
