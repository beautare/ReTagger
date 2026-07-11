//
//  MetadataWriter.swift
//  ReTagger
//
//  抽象元数据写入后端，便于后续替换为 TagLib 等实现。
//

import Foundation

@MainActor
protocol MetadataWriter {
    func write(_ metadata: AudioMetadata, to url: URL) async throws
}
