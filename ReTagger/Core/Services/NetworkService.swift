//
//  NetworkService.swift
//  ReTagger
//
//  HTTP client for backend communication
//

import Foundation
import OSLog

/// HTTP methods
enum HTTPMethod: String {
    case GET, POST, PUT, DELETE
}

/// Protocol defining network operations
protocol NetworkServiceProtocol: AnyObject {
    func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod,
        body: Encodable?,
        retryOnAuthFailure: Bool,
        additionalHeaders: [String: String]?
    ) async throws -> T

    func processMetadata(_ request: AIBatchRequest) async throws -> AIBatchResponse
    func processMetadata(_ request: MetadataProcessingRequest) async throws -> MetadataProcessingResponse
    func processBatch(_ request: MetadataProcessingRequest, batchSize: Int) async throws -> MetadataProcessingResponse
    func healthCheck() async throws -> Bool
}

extension NetworkServiceProtocol {
    /// Default implementation with just additionalHeaders optional
    func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod,
        body: Encodable? = nil,
        additionalHeaders: [String: String]? = nil
    ) async throws -> T {
        try await request(
            endpoint: endpoint,
            method: method,
            body: body,
            retryOnAuthFailure: true,
            additionalHeaders: additionalHeaders
        )
    }
    
    /// Implementation with retryOnAuthFailure parameter and additionalHeaders optional
    func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod,
        body: Encodable?,
        retryOnAuthFailure: Bool,
        additionalHeaders: [String: String]? = nil
    ) async throws -> T {
        try await request(
            endpoint: endpoint,
            method: method,
            body: body,
            retryOnAuthFailure: retryOnAuthFailure,
            additionalHeaders: additionalHeaders
        )
    }
}

// MARK: - NetworkService Implementation

@MainActor
class NetworkService: NetworkServiceProtocol {

    private var baseURL: String
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let tokenProvider: (any AuthTokenProviding)?
    private let logDateFormatter: DateFormatter
    private let sensitiveJSONKeys: Set<String> = ["password", "token", "authorization", "devicefingerprint", "refresh_token"]
    private let sensitiveHeaderFields: Set<String> = ["authorization"]

    // MARK: - Initialization

    init(baseURL: String, tokenProvider: (any AuthTokenProviding)? = nil) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Constants.API.defaultTimeout
        configuration.timeoutIntervalForResource = Constants.API.aiProcessingTimeout
        self.session = URLSession(configuration: configuration)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        self.logDateFormatter = formatter

        // Configure encoder/decoder
        encoder.keyEncodingStrategy = .useDefaultKeys
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func updateBaseURL(_ newBaseURL: String) {
        guard baseURL != newBaseURL else { return }
        Logger.network.info("Updating base URL to \(newBaseURL, privacy: .public)")
        baseURL = newBaseURL
        if let tokenProvider {
            Task {
                await tokenProvider.updateBackendURL(newBaseURL)
            }
        }
    }

    // MARK: - Generic Request

    func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod,
        body: Encodable?,
        retryOnAuthFailure: Bool,
        additionalHeaders: [String: String]? = nil
    ) async throws -> T {
        try await performRequest(
            endpoint: endpoint,
            method: method,
            body: body,
            retryOnAuthFailure: retryOnAuthFailure,
            retryingAfterAuthFailure: false,
            additionalHeaders: additionalHeaders
        )
    }

    private func performRequest<T: Decodable>(
        endpoint: String,
        method: HTTPMethod,
        body: Encodable?,
        retryOnAuthFailure: Bool,
        retryingAfterAuthFailure: Bool,
        additionalHeaders: [String: String]? = nil
    ) async throws -> T {
        let startTime = Logger.performance.logOperationStart("NetworkRequest[\(method.rawValue)]")
        
        // Construct URL
        guard let url = URL(string: baseURL + endpoint) else {
            Logger.network.error("Invalid URL: \(self.baseURL + endpoint)")
            throw ReTaggerError.networkError("Invalid URL: \(baseURL + endpoint)")
        }
        
        Logger.network.info("[\(self.currentTimestamp())] [\(method.rawValue)] \(url.absoluteString)")


        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        // Add body if present
        if let body = body {
            do {
                request.httpBody = try encoder.encode(body)
                Logger.network.debug("Request body size: \(request.httpBody?.count ?? 0) bytes")
            } catch {
                Logger.network.error("Failed to encode request body: \(error.localizedDescription)")
                throw ReTaggerError.networkError("Failed to encode request body: \(error.localizedDescription)")
            }
        }

        // Perform request with retry logic
        let maxRetries = 3
        var lastError: Error?

        for attempt in 0..<maxRetries {
            if attempt > 0 {
                Logger.network.info("[\(self.currentTimestamp())] Retry attempt \(attempt + 1)/\(maxRetries)")
            }

            do {
                let attemptNumber = attempt + 1
                var attemptRequest = request

                if let tokenProvider {
                    let headers = try await tokenProvider.authorizationHeaders()
                    for (key, value) in headers {
                        attemptRequest.setValue(value, forHTTPHeaderField: key)
                    }
                }
                
                // Apply additional headers
                if let additionalHeaders {
                    for (key, value) in additionalHeaders {
                        attemptRequest.setValue(value, forHTTPHeaderField: key)
                    }
                }

                logRequestDetails(attempt: attemptNumber, request: attemptRequest)
                let (data, response) = try await session.data(for: attemptRequest)

                guard let httpResponse = response as? HTTPURLResponse else {
                    Logger.network.error("Invalid response type")
                    throw ReTaggerError.invalidResponse
                }

                logResponseDetails(attempt: attemptNumber, response: httpResponse, data: data)

                // 捕获配额更新
                if let quotaString = httpResponse.value(forHTTPHeaderField: "X-Remaining-Requests"),
                   let quota = Int(quotaString),
                   let tokenProvider = self.tokenProvider {
                    Task {
                        await tokenProvider.updateQuota(remaining: quota)
                    }
                }

                // Handle HTTP errors
                guard (200...299).contains(httpResponse.statusCode) else {
                    let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"

                    if (httpResponse.statusCode == 401 || httpResponse.statusCode == 403) {
                        let apiError = ReTaggerError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
                        lastError = apiError
                        Logger.network.error("Authorization failed [\(httpResponse.statusCode)]: \(errorMessage)")

                        if retryOnAuthFailure, let tokenProvider {
                            await tokenProvider.handleUnauthorizedResponse()

                            if !retryingAfterAuthFailure {
                                Logger.network.info("Retrying request after refreshing authentication token")
                                return try await self.performRequest(
                                    endpoint: endpoint,
                                    method: method,
                                    body: body,
                                    retryOnAuthFailure: retryOnAuthFailure,
                                    retryingAfterAuthFailure: true,
                                    additionalHeaders: additionalHeaders
                                )
                            } else if attempt < maxRetries - 1 {
                                continue
                            }
                        }
                        
                        throw apiError
                    }

                    Logger.network.error("API error [\(httpResponse.statusCode)]: \(errorMessage)")
                    throw ReTaggerError.apiError(
                        statusCode: httpResponse.statusCode,
                        message: errorMessage
                    )
                }

                // Decode response
                do {
                    let result = try decoder.decode(T.self, from: data)
                    Logger.network.info("[\(self.currentTimestamp())] Request completed successfully")
                    Logger.performance.logOperationEnd("NetworkRequest[\(method.rawValue)]", startTime: startTime)
                    return result
                } catch {
                    let rawBody = String(data: data, encoding: .utf8) ?? "<non-UTF8 response>"
                    Logger.network.error("Failed to decode response: \(error.localizedDescription)")
                    Logger.network.error("Response body: \(rawBody)")
                    throw ReTaggerError.networkError("Failed to decode response: \(error.localizedDescription)")
                }

            } catch {
                lastError = error
                Logger.network.logOperationFailed("NetworkRequest", error: error)

                // Don't retry on certain errors
                if case ReTaggerError.apiError(let code, _) = error, code == 401 || code == 403 || code == 429 {
                    Logger.network.error("Non-retryable error (status \(code)), aborting")
                    throw error
                }
                
                // Don't retry on decoding errors
                if case ReTaggerError.networkError(let message) = error, message.contains("Failed to decode") {
                    Logger.network.error("Decoding error is non-retryable, aborting")
                    throw error
                }

                // Exponential backoff
                if attempt < maxRetries - 1 {
                    let delay = pow(2.0, Double(attempt))
                    Logger.network.info("[\(self.currentTimestamp())] Waiting \(String(format: "%.1f", delay))s before retry")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        // All retries failed
        Logger.network.error("[\(self.currentTimestamp())] Request failed after \(maxRetries) attempts")
        throw lastError ?? ReTaggerError.networkError("Request failed after \(maxRetries) attempts")
    }

    // MARK: - Specific Endpoints

    // 遗留方法（向后兼容）
    func processMetadata(_ request: AIBatchRequest) async throws -> AIBatchResponse {
        return try await self.request(
            endpoint: Constants.API.endpoint,
            method: .POST,
            body: request
        )
    }

    // 新的元数据处理方法
    func processMetadata(_ request: MetadataProcessingRequest) async throws -> MetadataProcessingResponse {
        Logger.network.info("开始元数据处理，文件数: \(request.files.count)")

        let response: MetadataProcessingResponse = try await self.request(
            endpoint: Constants.API.metadataProcess,
            method: .POST,
            body: request
        )

        let processingTime = response.stats.processingTimeMs.map { "\($0)ms" } ?? "未知"
        let provider = response.stats.aiProvider ?? "未知"
        let model = response.stats.modelName ?? "未知"

        Logger.network.info("""
            元数据处理完成 - \
            成功:\(response.stats.successCount) \
            失败:\(response.stats.failedCount) \
            耗时:\(processingTime) \
            缓存:\(response.fromCache) \
            提供商:\(provider) \
            模型:\(model)
            """)

        return response
    }

    // 批量处理（支持分批）
    func processBatch(
        _ request: MetadataProcessingRequest,
        batchSize: Int = 20
    ) async throws -> MetadataProcessingResponse {
        Logger.network.info("开始批量元数据处理，文件数: \(request.files.count), 批大小: \(batchSize)")

        let endpoint = "\(Constants.API.metadataBatch)?batchSize=\(batchSize)"
        let response: MetadataProcessingResponse = try await self.request(
            endpoint: endpoint,
            method: .POST,
            body: request
        )
        let processingTime = response.stats.processingTimeMs.map { "\($0)ms" } ?? "未知"
        let provider = response.stats.aiProvider ?? "未知"
        let model = response.stats.modelName ?? "未知"

        Logger.network.info("批量处理完成 - 耗时:\(processingTime) 提供商:\(provider) 模型:\(model)")
        return response
    }

    func healthCheck() async throws -> Bool {
        Logger.network.info("Performing health check")

        struct HealthResponse: Codable {
            let status: String
        }

        do {
            let response: HealthResponse = try await request(
                endpoint: Constants.API.healthCheckEndpoint,
                method: .GET,
                body: nil as String?
            )
            let normalizedStatus = response.status.uppercased()
            let isHealthy = normalizedStatus == "UP" || normalizedStatus == "OK" || normalizedStatus == "HEALTHY"
            Logger.network.info("Health check result: \(isHealthy ? "healthy" : "unhealthy")")
            return isHealthy
        } catch {
            Logger.network.error("Health check failed: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - Logging Helpers

private extension NetworkService {
    func currentTimestamp() -> String {
        logDateFormatter.string(from: Date())
    }
    
    func logRequestDetails(attempt: Int, request: URLRequest) {
        let timestamp = currentTimestamp()
        let method = request.httpMethod ?? "UNKNOWN"
        let urlString = request.url?.absoluteString ?? "unknown"
        let headersString = sanitizedHeadersString(from: request.allHTTPHeaderFields)
        let bodyString = sanitizedJSONString(from: request.httpBody) ?? "None"
        Logger.network.info("[\(timestamp)] Request #\(attempt) \(method) \(urlString)\nHeaders: \(headersString)\nBody: \(bodyString)")
    }
    
    func logResponseDetails(attempt: Int, response: HTTPURLResponse, data: Data) {
        let timestamp = currentTimestamp()
        let urlString = response.url?.absoluteString ?? "unknown"
        let bodyString = sanitizedJSONString(from: data) ?? (String(data: data, encoding: .utf8) ?? "<binary>")
        Logger.network.info("[\(timestamp)] Response #\(attempt) \(response.statusCode) from \(urlString)\nBody: \(bodyString)")
    }
    
    func sanitizedHeadersString(from headers: [String: String]?) -> String {
        guard let headers, !headers.isEmpty else { return "None" }
        let sanitizedPairs = headers.map { key, value -> String in
            let lowerKey = key.lowercased()
            if sensitiveHeaderFields.contains(lowerKey) {
                return "\(key): ***"
            }
            return "\(key): \(value)"
        }
        return sanitizedPairs.sorted().joined(separator: ", ")
    }
    
    func sanitizedJSONString(from data: Data?) -> String? {
        guard let data, !data.isEmpty else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: data) {
            let sanitized = sanitizeJSONObject(object)
            if JSONSerialization.isValidJSONObject(sanitized),
               let sanitizedData = try? JSONSerialization.data(withJSONObject: sanitized, options: [.prettyPrinted]) {
                return String(data: sanitizedData, encoding: .utf8)
            }
        }
        return String(data: data, encoding: .utf8)
    }
    
    func sanitizeJSONObject(_ object: Any) -> Any {
        if var dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                if let _ = value as? String,
                   sensitiveJSONKeys.contains(key.lowercased()) {
                    dictionary[key] = "***"
                } else {
                    dictionary[key] = sanitizeJSONObject(value)
                }
            }
            return dictionary
        } else if var array = object as? [Any] {
            for index in array.indices {
                array[index] = sanitizeJSONObject(array[index])
            }
            return array
        }
        return object
    }
}
