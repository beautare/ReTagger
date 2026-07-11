//
//  DeviceTokenManager.swift
//  ReTagger
//
//  负责与后端交换设备令牌，并在网络请求间复用。
//

import Darwin
import Foundation
import OSLog

/// 提供认证头的协议，供网络层注入
protocol AuthTokenProviding: AnyObject {
    func authorizationHeaders() async throws -> [String: String]
    func handleUnauthorizedResponse() async
    func updateBackendURL(_ newBaseURL: String) async
    func updateQuota(remaining: Int) async
}

/// 管理设备令牌的 actor，确保并发场景下只有一次刷新
actor DeviceTokenManager: AuthTokenProviding {

    private enum StorageKeys {
        static let token = "vip.retagger.deviceToken"
        static let deviceId = "vip.retagger.deviceIdentifier"
    }

    private var baseURL: String
    private var cachedToken: String?
    private var refreshTask: Task<String, Error>?
    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(baseURL: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        self.cachedToken = UserDefaults.standard.string(forKey: StorageKeys.token)
    }

    // MARK: - AuthTokenProviding

    func authorizationHeaders() async throws -> [String: String] {
        let token = try await resolveToken(forceRefresh: false)
        return ["X-API-Token": token]
    }

    func handleUnauthorizedResponse() async {
        await logAuth { logger in
            logger.warning("设备令牌收到 401/403，准备刷新")
        }
        invalidateCachedToken()
    }

    func updateBackendURL(_ newBaseURL: String) async {
        guard !newBaseURL.isEmpty, baseURL != newBaseURL else { return }
        await logAuth { logger in
            logger.info("更新设备令牌服务的后端地址: \(newBaseURL, privacy: .public)")
        }
        baseURL = newBaseURL
        invalidateCachedToken()
    }
    
    func updateQuota(remaining: Int) async {
        // DeviceTokenManager 本身不需要响应配额更新，
        // 但为了满足协议，这里留空。实际上 AuthService 会处理这个调用。
    }

    // MARK: - Token Lifecycle

    private func resolveToken(forceRefresh: Bool) async throws -> String {
        if !forceRefresh, let token = cachedToken, !token.isEmpty {
            return token
        }

        if !forceRefresh, let stored = storedToken(), !stored.isEmpty {
            cachedToken = stored
            return stored
        }

        return try await refreshToken()
    }

    private func refreshToken() async throws -> String {
        if let task = refreshTask {
            return try await task.value
        }

        let task = Task<String, Error> {
            try Task.checkCancellation()
            return try await self.performRefresh()
        }

        refreshTask = task

        do {
            let token = try await task.value
            refreshTask = nil
            return token
        } catch {
            refreshTask = nil
            invalidateCachedToken()
            throw error
        }
    }

    private func invalidateCachedToken() {
        cachedToken = nil
        UserDefaults.standard.removeObject(forKey: StorageKeys.token)
    }

    private func performRefresh() async throws -> String {
        try Task.checkCancellation()
        let request = try await buildRequest()
        await logAuth { logger in
            logger.info("请求设备令牌: \(request.url?.absoluteString ?? "unknown", privacy: .public)")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            await logAuth { logger in
                logger.error("设备令牌响应类型错误")
            }
            throw ReTaggerError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            await logAuth { logger in
                logger.error("设备令牌请求失败，状态码: \(httpResponse.statusCode)")
            }
            throw ReTaggerError.apiError(statusCode: httpResponse.statusCode, message: message)
        }

        let token = try await MainActor.run { () -> String in
            let payload = try decoder.decode(DeviceTokenResponse.self, from: data)
            return payload.data.token.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        persistToken(token)
        cachedToken = token
        await logAuth { logger in
            logger.info("设备令牌刷新成功")
        }
        return token
    }

    // MARK: - Request Helpers

    private func buildRequest() async throws -> URLRequest {
        let endpoint = await MainActor.run { Constants.API.deviceToken }
        guard let url = URL(string: baseURL + endpoint) else {
            throw ReTaggerError.networkError("Invalid token endpoint")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (appVersion, buildNumber) = await fetchAppInfo()
        let deviceId = resolveDeviceIdentifier()

        let body = try await MainActor.run { () throws -> Data in
            let payload = DeviceTokenRequest(
                deviceType: "macOS",
                deviceModel: Self.hardwareModel(),
                osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                deviceId: deviceId,
                appVersion: appVersion,
                appBuildNumber: buildNumber
            )
            return try encoder.encode(payload)
        }
        request.httpBody = body

        return request
    }

    private func resolveDeviceIdentifier() -> String {
        if let existing = UserDefaults.standard.string(forKey: StorageKeys.deviceId), !existing.isEmpty {
            return existing
        }
        let newIdentifier = UUID().uuidString
        UserDefaults.standard.set(newIdentifier, forKey: StorageKeys.deviceId)
        return newIdentifier
    }

    private func storedToken() -> String? {
        UserDefaults.standard.string(forKey: StorageKeys.token)
    }

    private func persistToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: StorageKeys.token)
    }

    nonisolated private static func hardwareModel() -> String {
        var size: size_t = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "UnknownMac" }
        var machine = [CChar](repeating: 0, count: Int(size))
        sysctlbyname("hw.model", &machine, &size, nil, 0)
        return String(cString: machine)
    }

    private func logAuth(_ action: @Sendable @escaping (Logger) -> Void) async {
        await MainActor.run {
            action(Logger.auth)
        }
    }

    private func fetchAppInfo() async -> (String?, String?) {
        await MainActor.run {
            let info = Bundle.main.infoDictionary
            let version = info?["CFBundleShortVersionString"] as? String
            let build = info?["CFBundleVersion"] as? String
            return (version, build)
        }
    }
}
