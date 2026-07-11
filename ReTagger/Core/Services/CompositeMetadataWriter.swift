//
//  CompositeMetadataWriter.swift
//  ReTagger
//
//  先尝试主写入器，失败时回退到备用实现。
//

import Foundation
import OSLog

@MainActor
final class CompositeMetadataWriter: MetadataWriter {
    private let primary: any MetadataWriter
    private let fallback: any MetadataWriter

    init(primary: any MetadataWriter, fallback: any MetadataWriter) {
        self.primary = primary
        self.fallback = fallback
    }

    func write(_ metadata: AudioMetadata, to url: URL) async throws {
        do {
            try await primary.write(metadata, to: url)
        } catch let retaggerError as ReTaggerError {
            guard case .metadataUnsupportedFormat = retaggerError else {
                throw retaggerError
            }
            Logger.metadata.notice("主写入器不支持该文件，回退到备用实现：\(url.lastPathComponent, privacy: .public)")
            try await fallback.write(metadata, to: url)
        } catch {
            throw error
        }
    }
}
