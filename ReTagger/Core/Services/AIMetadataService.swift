//
//  AIMetadataService.swift
//  ReTagger
//
//  AI元数据处理服务
//

import Foundation
import Combine
import OSLog

/// AI元数据处理服务协议
protocol AIMetadataServiceProtocol {
    func processMetadata(
        _ metadata: [AudioMetadata],
        options: MetadataProcessingRequest.ProcessingOptions?,
        fileNamingFormat: FileNamingFormat
    ) async throws -> [AudioMetadata]

    func processBatch(
        _ metadata: [AudioMetadata],
        options: MetadataProcessingRequest.ProcessingOptions?,
        batchSize: Int,
        fileNamingFormat: FileNamingFormat
    ) async throws -> [AudioMetadata]

    func applyCorrections(
        _ metadata: [AudioMetadata],
        writeToFiles: Bool
    ) async throws -> [AudioMetadata]
}

// MARK: - AIMetadataService Implementation

@MainActor
class AIMetadataService: AIMetadataServiceProtocol, ObservableObject {

    // MARK: - Published Properties

    @Published var isProcessing: Bool = false
    @Published var progress: Double = 0.0
    @Published var currentOperation: String = ""

    // MARK: - Dependencies

    private let networkService: NetworkServiceProtocol
    private let metadataService: MetadataServiceProtocol
    private let logEncoder: JSONEncoder

    // MARK: - Initialization

    init(
        networkService: NetworkServiceProtocol,
        metadataService: MetadataServiceProtocol
    ) {
        self.networkService = networkService
        self.metadataService = metadataService
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        self.logEncoder = encoder
    }

    // MARK: - Process Metadata

    /// 处理元数据：调用AI服务获取修正建议
    func processMetadata(
        _ metadata: [AudioMetadata],
        options: MetadataProcessingRequest.ProcessingOptions? = nil,
        fileNamingFormat: FileNamingFormat
    ) async throws -> [AudioMetadata] {

        guard !metadata.isEmpty else {
            Logger.ai.warning("元数据列表为空，跳过处理")
            return metadata
        }

        isProcessing = true
        progress = 0.0
        currentOperation = "准备发送元数据到AI服务..."
        defer {
            isProcessing = false
            progress = 1.0
            currentOperation = ""
        }

        Logger.ai.info("开始AI元数据处理，文件数: \(metadata.count)")

        // 1. 构建请求
        let resolvedOptions = options ?? MetadataProcessingRequest.ProcessingOptions.default
        currentOperation = "构建请求数据..."
        let request = buildRequest(from: metadata, options: resolvedOptions)
        progress = 0.1
        logAIRequestPayload(request, context: "单文件")

        // 2. 调用网络服务
        currentOperation = "调用AI服务处理元数据..."
        let response: MetadataProcessingResponse
        do {
            response = try await networkService.processMetadata(request)
            logAIResponsePayload(response, context: "单文件")
            progress = 0.7
        } catch {
            Logger.ai.error("AI处理失败: \(error.localizedDescription)")
            throw mapToAIProcessingError(error)
        }

        // 3. 应用响应到元数据
        currentOperation = "应用AI修正结果..."
        let updatedMetadata = applyResponse(response, to: metadata, format: fileNamingFormat)
        progress = 0.9
        let processingTime = response.stats.processingTimeMs.map { "\($0)ms" } ?? "未知"
        let provider = response.stats.aiProvider ?? "未知"
        let model = response.stats.modelName ?? "未知"
        Logger.ai.info("""
            AI元数据处理完成 - \
            成功: \(response.stats.successCount), \
            失败: \(response.stats.failedCount), \
            耗时: \(processingTime), \
            缓存: \(response.fromCache), \
            提供商: \(provider), \
            模型: \(model)
            """)

        currentOperation = "完成"
        progress = 1.0

        return updatedMetadata
    }

    /// 批量处理：支持分批发送大量文件
    func processBatch(
        _ metadata: [AudioMetadata],
        options: MetadataProcessingRequest.ProcessingOptions? = nil,
        batchSize: Int = 20,
        fileNamingFormat: FileNamingFormat
    ) async throws -> [AudioMetadata] {

        guard !metadata.isEmpty else {
            Logger.ai.warning("元数据列表为空，跳过批量处理")
            return metadata
        }

        isProcessing = true
        progress = 0.0
        currentOperation = "准备批量处理..."
        defer {
            isProcessing = false
            progress = 1.0
            currentOperation = ""
        }

        Logger.ai.info("开始批量AI元数据处理，文件数: \(metadata.count), 批大小: \(batchSize)")

        // 1. 构建请求
        let resolvedOptions = options ?? MetadataProcessingRequest.ProcessingOptions.default
        currentOperation = "构建批量请求数据..."
        let request = buildRequest(from: metadata, options: resolvedOptions)
        progress = 0.1
        logAIRequestPayload(request, context: "批量")

        // 2. 调用批量处理服务
        currentOperation = "调用AI批量处理服务..."
        let response: MetadataProcessingResponse
        do {
            response = try await networkService.processBatch(request, batchSize: batchSize)
            logAIResponsePayload(response, context: "批量")
            progress = 0.7
        } catch {
            Logger.ai.error("批量AI处理失败: \(error.localizedDescription)")
            throw mapToAIProcessingError(error)
        }

        // 3. 应用响应到元数据
        currentOperation = "应用AI批量修正结果..."
        let updatedMetadata = applyResponse(response, to: metadata, format: fileNamingFormat)
        progress = 0.9
        let processingTime = response.stats.processingTimeMs.map { "\($0)ms" } ?? "未知"
        let provider = response.stats.aiProvider ?? "未知"
        let model = response.stats.modelName ?? "未知"
        Logger.ai.info("""
            批量AI元数据处理完成 - \
            成功: \(response.stats.successCount), \
            失败: \(response.stats.failedCount), \
            耗时: \(processingTime), \
            提供商: \(provider), \
            模型: \(model)
            """)

        currentOperation = "完成"
        progress = 1.0

        return updatedMetadata
    }

    // MARK: - Apply Corrections

    /// 应用修正：将AI建议的元数据写入文件
    func applyCorrections(
        _ metadata: [AudioMetadata],
        writeToFiles: Bool = true
    ) async throws -> [AudioMetadata] {

        guard writeToFiles else {
            Logger.ai.info("仅返回元数据，不写入文件")
            return metadata
        }

        isProcessing = true
        progress = 0.0
        currentOperation = "准备写入元数据到文件..."
        defer {
            isProcessing = false
            progress = 1.0
            currentOperation = ""
        }

        Logger.ai.info("开始应用元数据修正到文件，文件数: \(metadata.count)")

        var updatedMetadata = metadata
        let totalCount = metadata.count
        var successCount = 0
        var failedCount = 0

        for (index, var item) in metadata.enumerated() {
            // 仅处理有修正数据的项
            guard item.hasEffectiveCorrections else {
                progress = Double(index + 1) / Double(totalCount)
                continue
            }

            currentOperation = "写入文件 (\(index + 1)/\(totalCount)): \(item.fileName)"

            do {
                // 写入元数据到文件
                try await metadataService.writeMetadata(item, to: item.filePath)

                // 更新状态为已完成
                item.processingState = .completed
                updatedMetadata[index] = item
                successCount += 1

                Logger.ai.debug("成功写入元数据: \(item.fileName)")

            } catch {
                // 标记为失败
                item.processingState = .failed
                item.error = error.localizedDescription
                updatedMetadata[index] = item
                failedCount += 1

                Logger.ai.error("写入元数据失败: \(item.fileName), 错误: \(error.localizedDescription)")
            }

            progress = Double(index + 1) / Double(totalCount)
        }

        Logger.ai.info("元数据写入完成 - 成功: \(successCount), 失败: \(failedCount)")

        currentOperation = "完成"
        progress = 1.0

        return updatedMetadata
    }

    // MARK: - Logging

    private func logAIRequestPayload(
        _ request: MetadataProcessingRequest,
        context: String
    ) {
        guard let json = encodeForLog(request) else {
            Logger.ai.error("AI打标签\(context)请求日志编码失败")
            return
        }
        Logger.ai.debug("AI打标签\(context)发送: \(json, privacy: .public)")
    }

    private func logAIResponsePayload(
        _ response: MetadataProcessingResponse,
        context: String
    ) {
        guard let json = encodeForLog(response) else {
            Logger.ai.error("AI打标签\(context)响应日志编码失败")
            return
        }
        Logger.ai.debug("AI打标签\(context)收到: \(json, privacy: .public)")
    }

    private func encodeForLog<T: Encodable>(_ value: T) -> String? {
        guard let data = try? logEncoder.encode(value) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Helper Methods

    /// 从音频元数据数组构建网络请求
    private func buildRequest(
        from metadata: [AudioMetadata],
        options: MetadataProcessingRequest.ProcessingOptions
    ) -> MetadataProcessingRequest {

        let files = metadata.map { item in
            MetadataProcessingRequest.FileMetadata(
                filePath: item.filePath.path,
                fileName: item.fileName,
                fileSize: getFileSize(at: item.filePath),
                title: item.originalTitle,
                artist: item.originalArtist,
                album: item.originalAlbum,
                genre: item.originalGenre,
                year: item.originalYear,
                albumArtist: item.originalAlbumArtist,
                composer: item.originalComposer,
                comment: item.originalComment,
                duration: item.duration.map { Int($0) },
                bitrate: item.bitrate,
                format: item.format?.lowercased() ?? item.filePath.pathExtension.lowercased()
            )
        }

        return MetadataProcessingRequest(files: files, options: options)
    }

    /// 将网络响应应用到AudioMetadata数组
    private func applyResponse(
        _ response: MetadataProcessingResponse,
        to metadata: [AudioMetadata],
        format: FileNamingFormat
    ) -> [AudioMetadata] {

        var updatedMetadata = metadata

        // 创建文件路径到响应结果的映射
        var resultMap: [String: MetadataProcessingResponse.CorrectedMetadata] = [:]
        for result in response.results {
            resultMap[result.filePath] = result
        }

        // 应用每个结果到对应的元数据
        for (index, var item) in metadata.enumerated() {
            let filePath = item.filePath.path

            guard let result = resultMap[filePath] else {
                Logger.ai.warning("未找到文件的处理结果: \(filePath)")
                item.processingState = .failed
                item.error = "未找到处理结果"
                updatedMetadata[index] = item
                continue
            }

            // 根据状态更新元数据
            switch result.status.uppercased() {
            case "SUCCESS":
                // 应用AI修正的元数据
                item.correctedTitle = result.correctedTitle
                item.correctedArtist = result.correctedArtist
                item.correctedAlbum = result.correctedAlbum
                item.correctedGenre = result.correctedGenre
                item.correctedYear = result.correctedYear
                item.correctedAlbumArtist = result.correctedAlbumArtist
                item.correctedComposer = result.correctedComposer
                item.correctedComment = result.correctedComment

                let title = result.correctedTitle ?? item.originalTitle ?? ""
                let artist = result.correctedArtist ?? item.originalArtist ?? ""
                let ext = item.filePath.pathExtension
                
                let baseName: String
                switch format {
                case .titleArtist:
                    baseName = artist.isEmpty ? title : "\(title) - \(artist)"
                case .artistTitle:
                    baseName = artist.isEmpty ? title : "\(artist) - \(title)"
                case .titleOnly:
                    baseName = title
                }
                
                let sanitizedName = baseName.replacingOccurrences(of: "/", with: "_")
                                            .replacingOccurrences(of: ":", with: "_")
                                            .trimmingCharacters(in: .whitespacesAndNewlines)
                
                let newFileName = sanitizedName.isEmpty ? item.fileName : "\(sanitizedName).\(ext)"

                // 应用文件操作建议
                item.suggestedFileName = newFileName
                item.suggestedFolderPath = result.suggestedFolderPath

                // 应用置信度和备注
                item.confidence = result.confidence
                item.aiNotes = result.notes
                item.error = nil
                item.processingState = item.hasEffectiveCorrections ? .awaitingConfirmation : .completed
                Logger.ai.debug("成功应用AI修正: \(item.fileName)")

            case "PARTIAL":
                // 部分成功，仅应用有效的字段
                item.correctedTitle = result.correctedTitle
                item.correctedArtist = result.correctedArtist
                item.correctedAlbum = result.correctedAlbum
                item.correctedGenre = result.correctedGenre
                item.correctedYear = result.correctedYear
                item.correctedAlbumArtist = result.correctedAlbumArtist
                item.correctedComposer = result.correctedComposer
                item.correctedComment = result.correctedComment

                item.confidence = result.confidence
                item.aiNotes = result.notes
                item.error = nil
                item.processingState = item.hasEffectiveCorrections ? .awaitingConfirmation : .completed
                Logger.ai.warning("部分成功应用AI修正: \(item.fileName)")

            case "FAILED":
                item.processingState = .failed
                item.error = result.errorMessage ?? "AI处理失败"
                Logger.ai.error("AI处理失败: \(item.fileName), 错误: \(item.error ?? "未知")")

            case "NO_CHANGE":
                item.processingState = .completed
                item.aiNotes = "元数据无需修改"
                Logger.ai.debug("元数据无需修改: \(item.fileName)")

            default:
                item.processingState = .failed
                item.error = "未知处理状态: \(result.status)"
                Logger.ai.error("未知处理状态: \(result.status), 文件: \(item.fileName)")
            }

            updatedMetadata[index] = item
        }

        return updatedMetadata
    }

    /// 获取文件大小
    private func getFileSize(at url: URL) -> Int64? {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return attributes[.size] as? Int64
        } catch {
            Logger.ai.warning("无法获取文件大小: \(url.path)")
            return nil
        }
    }

    private func mapToAIProcessingError(_ error: Error) -> ReTaggerError {
        if let retaggerError = error as? ReTaggerError {
            if case ReTaggerError.apiError(let code, _) = retaggerError, code == 401 || code == 403 {
                return .aiProcessingFailed("授权失效，已尝试刷新令牌，请重试。")
            }
            return retaggerError
        }
        return .aiProcessingFailed(error.localizedDescription)
    }
}
