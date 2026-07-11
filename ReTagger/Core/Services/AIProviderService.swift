//
//  AIProviderService.swift
//  ReTagger
//
//  Service for managing AI provider integrations
//

import Foundation

/// Provider capabilities information
struct ProviderCapabilities {
    let maxBatchSize: Int
    let supportsFileRenaming: Bool
    let supportsFolderReorganization: Bool
    let estimatedProcessingTime: TimeInterval

    static let gemini = ProviderCapabilities(
        maxBatchSize: 50,
        supportsFileRenaming: true,
        supportsFolderReorganization: true,
        estimatedProcessingTime: 3.0
    )

    static let chatgpt = ProviderCapabilities(
        maxBatchSize: 30,
        supportsFileRenaming: true,
        supportsFolderReorganization: true,
        estimatedProcessingTime: 2.5
    )

    static let grok = ProviderCapabilities(
        maxBatchSize: 40,
        supportsFileRenaming: true,
        supportsFolderReorganization: true,
        estimatedProcessingTime: 2.8
    )
}

/// Protocol defining AI provider operations
protocol AIProviderServiceProtocol {
    func configure(provider: AIProvider, apiKey: String)
    func currentProvider() -> AIProvider
    func validateAPIKey() async throws -> Bool
    func getCapabilities() -> ProviderCapabilities
}

// MARK: - AIProviderService Implementation

@MainActor
class AIProviderService: AIProviderServiceProtocol {

    private var provider: AIProvider
    private var apiKey: String
    private let networkService: NetworkService

    // MARK: - Initialization

    init(provider: AIProvider = .gemini, apiKey: String = "", networkService: NetworkService) {
        self.provider = provider
        self.apiKey = apiKey
        self.networkService = networkService
    }

    // MARK: - Configuration

    func configure(provider: AIProvider, apiKey: String) {
        self.provider = provider
        self.apiKey = apiKey
    }

    func currentProvider() -> AIProvider {
        return provider
    }

    // MARK: - Validation

    func validateAPIKey() async throws -> Bool {
        // Attempt a health check to validate connectivity
        // In a real implementation, this would make a lightweight API call
        // to verify the API key with the selected provider
        do {
            return try await networkService.healthCheck()
        } catch {
            throw ReTaggerError.apiError(statusCode: 401, message: "Invalid API key")
        }
    }

    // MARK: - Capabilities

    func getCapabilities() -> ProviderCapabilities {
        switch provider {
        case .gemini:
            return .gemini
        case .chatgpt:
            return .chatgpt
        case .grok:
            return .grok
        }
    }

    // MARK: - Batch Processing

    func createBatchRequest(
        for metadata: [AudioMetadata],
        options: AIBatchRequest.RequestOptions
    ) -> AIBatchRequest {
        let files = metadata.map { AIBatchRequest.FileMetadata(from: $0) }
        return AIBatchRequest(files: files, provider: provider, options: options)
    }

    func splitIntoBatches(_ metadata: [AudioMetadata]) -> [[AudioMetadata]] {
        let capabilities = getCapabilities()
        let batchSize = capabilities.maxBatchSize

        var batches: [[AudioMetadata]] = []
        for i in stride(from: 0, to: metadata.count, by: batchSize) {
            let end = min(i + batchSize, metadata.count)
            batches.append(Array(metadata[i..<end]))
        }

        return batches
    }
}
