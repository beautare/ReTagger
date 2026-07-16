//
//  AuthService.swift
//  ReTagger
//
//  Created by Antigravity on 2025/12/03.
//

import Foundation
import Combine
import OSLog
import AppKit

enum AuthStorageKeys {
    static let userToken = "vip.retagger.userToken"
    static let lastLoginEmail = "vip.retagger.lastLoginEmail"
    static let cachedUser = "vip.retagger.cachedUser"
}

@MainActor
class AuthService: AuthTokenProviding, ObservableObject {
    
    // MARK: - Properties
    
    @Published var currentUser: UserResponse? {
        didSet {
            persistCurrentUser(currentUser)
        }
    }
    @Published var isAuthenticated: Bool = false
    /// 剩余点数。唯一写入口为 applyBalance(_:)，与 currentUser.balance 保持同步
    @Published private(set) var balance: Int?

    /// 最近一次用户 token 收到 401/403 的时间。
    /// 首次 401 不立即登出（可能是后端瞬时故障），等待 NetworkService
    /// 的一次自动重试；短时间窗口内第二次 401 才确认 token 失效并登出。
    private var lastUnauthorizedAt: Date?
    private static let unauthorizedConfirmationWindow: TimeInterval = 30
    
    private let deviceTokenManager: DeviceTokenManager
    weak var networkService: NetworkServiceProtocol?
    

    
    private var token: String? {
        didSet {
            isAuthenticated = token != nil
            if let token = token {
                KeychainStore.setString(token, forKey: AuthStorageKeys.userToken)
            } else {
                KeychainStore.removeValue(forKey: AuthStorageKeys.userToken)
            }
        }
    }

    // MARK: - Initialization

    init(deviceTokenManager: DeviceTokenManager) {
        self.deviceTokenManager = deviceTokenManager
        self.token = Self.loadPersistedToken()
        if let cachedUser = Self.loadPersistedUser() {
            self.currentUser = cachedUser
            self.balance = cachedUser.balance
        } else {
            self.currentUser = nil
            self.balance = nil
        }
        self.isAuthenticated = self.token != nil
    }

    /// 从 Keychain 读取缓存的用户资料；若发现历史版本遗留在 UserDefaults 的明文数据，
    /// 迁移到 Keychain 并清除旧存储（与 token 的处理一致）。
    private static func loadPersistedUser() -> UserResponse? {
        if let json = KeychainStore.string(forKey: AuthStorageKeys.cachedUser),
           let data = json.data(using: .utf8),
           let cachedUser = try? JSONDecoder().decode(UserResponse.self, from: data) {
            return cachedUser
        }
        if let data = UserDefaults.standard.data(forKey: AuthStorageKeys.cachedUser) {
            UserDefaults.standard.removeObject(forKey: AuthStorageKeys.cachedUser)
            if let cachedUser = try? JSONDecoder().decode(UserResponse.self, from: data) {
                if let json = String(data: data, encoding: .utf8) {
                    KeychainStore.setString(json, forKey: AuthStorageKeys.cachedUser)
                }
                Logger.auth.info("已将缓存用户资料从 UserDefaults 迁移至 Keychain")
                return cachedUser
            }
        }
        return nil
    }

    /// 从 Keychain 读取持久化 token；若发现历史版本遗留在 UserDefaults 的明文 token，
    /// 迁移到 Keychain 并清除旧存储。
    private static func loadPersistedToken() -> String? {
        if let token = KeychainStore.string(forKey: AuthStorageKeys.userToken) {
            return token
        }
        if let legacyToken = UserDefaults.standard.string(forKey: AuthStorageKeys.userToken) {
            KeychainStore.setString(legacyToken, forKey: AuthStorageKeys.userToken)
            UserDefaults.standard.removeObject(forKey: AuthStorageKeys.userToken)
            Logger.auth.info("已将登录 token 从 UserDefaults 迁移至 Keychain")
            return legacyToken
        }
        return nil
    }

    // MARK: - AuthTokenProviding
    
    func authorizationHeaders() async throws -> [String : String] {
        // 改进：互斥认证策略
        // 如果用户已登录，只发送用户 Token (Authorization)
        // 只有在未登录时，才发送设备 Token (X-API-Token)
        
        if let token = self.token {
            return ["Authorization": "Bearer \(token)"]
        } else {
            return try await deviceTokenManager.authorizationHeaders()
        }
    }
    
    func handleUnauthorizedResponse() async {
        // 401 可能来自用户 token 或设备 token。用户 token 不在首次 401 时登出：
        // NetworkService 会自动重试一次，只有确认窗口内连续两次 401 才判定 token 失效，
        // 避免后端瞬时故障把用户误踢下线。
        if token != nil {
            let now = Date()
            if let last = lastUnauthorizedAt,
               now.timeIntervalSince(last) < Self.unauthorizedConfirmationWindow {
                lastUnauthorizedAt = nil
                Logger.auth.warning("User token rejected twice in a row, logging out locally.")
                self.logout()
            } else {
                lastUnauthorizedAt = now
                Logger.auth.warning("User token got 401/403, awaiting retry confirmation before logout.")
            }
        }
        await deviceTokenManager.handleUnauthorizedResponse()
    }
    
    func updateBackendURL(_ newBaseURL: String) async {
        await deviceTokenManager.updateBackendURL(newBaseURL)
    }
    
    func updateQuota(remaining: Int) async {
        applyBalance(remaining)
    }

    /// balance 的唯一写入口：同时同步已登录用户缓存里的余额，保证两处数据一致
    private func applyBalance(_ newBalance: Int?) {
        balance = newBalance
        if let newBalance,
           var user = currentUser,
           user.balance != newBalance {
            user.balance = newBalance
            currentUser = user
        }
    }
    
    // MARK: - API Methods
    
    func login(request: LoginRequest) async throws {
        guard let networkService = networkService else { return }
        
        do {
            let response: ApiResponse<LoginResponse> = try await networkService.request(
                endpoint: "/api/v1/users/login",
                method: .POST,
                body: request,
                retryOnAuthFailure: false
            )
            
            self.token = response.data.token
            UserDefaults.standard.set(request.email, forKey: AuthStorageKeys.lastLoginEmail)
            if let assembledUser = makeUser(from: response.data, fallbackEmail: request.email) {
                self.currentUser = assembledUser
                applyBalance(assembledUser.balance)
            } else {
                self.currentUser = nil
                Logger.auth.warning("Login response did not include user payload.")
            }
        } catch let error as ReTaggerError {
            // 检查是否是设备令牌过期导致的认证失败
            if case .apiError(let code, let message) = error,
               (code == 401 || code == 403),
               message.contains("凭证") || message.contains("credential") || message.contains("token") {
                Logger.auth.warning("登录失败，检测到可能是设备令牌过期，清除本地缓存后重试")
                
                // 清除过期的设备令牌
                await deviceTokenManager.handleUnauthorizedResponse()
                
                // 重试登录请求
                let retryResponse: ApiResponse<LoginResponse> = try await networkService.request(
                    endpoint: "/api/v1/users/login",
                    method: .POST,
                    body: request,
                    retryOnAuthFailure: false
                )
                
                self.token = retryResponse.data.token
                UserDefaults.standard.set(request.email, forKey: AuthStorageKeys.lastLoginEmail)
                if let assembledUser = makeUser(from: retryResponse.data, fallbackEmail: request.email) {
                    self.currentUser = assembledUser
                    applyBalance(assembledUser.balance)
                } else {
                    self.currentUser = nil
                    Logger.auth.warning("Login response did not include user payload.")
                }
                return
            }
            throw error
        } catch {
            throw error
        }
    }
    
    func register(request: RegisterRequest) async throws {
        guard let networkService = networkService else { return }
        
        do {
            let response: ApiResponse<RegisterResponse> = try await networkService.request(
                endpoint: "/api/v1/users/register",
                method: .POST,
                body: request
            )
            
            self.token = response.data.token
            if let user = response.data.user {
                self.currentUser = user
                applyBalance(user.balance)
            } else {
                self.currentUser = nil
                Logger.auth.warning("Register response did not include user payload.")
            }
        } catch {
            throw error
        }
    }
    
    func logout() {
        self.token = nil
        self.currentUser = nil
        applyBalance(nil)

        // 登出后，立即刷新一次以获取游客配额；失败不阻断登出，但要留下可追踪日志
        Task {
            do {
                try await fetchProfile()
            } catch {
                Logger.auth.warning("登出后刷新游客配额失败：\(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    func fetchProfile() async throws {
        // 允许未登录状态下调用，获取设备配额
        guard let networkService = networkService else { return }
        
        let tokenStatus: ApiResponse<TokenCheckResponse> = try await networkService.request(
            endpoint: "/api/v1/tokens/check",
            method: .GET,
            body: nil as String?
        )
        
        // 竞态条件检查：如果当前我们认为已登录，但返回结果里没有用户数据（说明可能是个滞后的游客请求），
        // 则忽略这次更新，防止覆盖正确的用户数据。
        if self.isAuthenticated && tokenStatus.data.user == nil {
            Logger.auth.warning("Ignored stale guest profile response while authenticated")
            return
        }
        
        // 更新全局 balance（applyBalance 会同步 currentUser.balance）
        if let balance = tokenStatus.data.remainingRequests {
            applyBalance(balance)
        }
    }
    
    func redeemVoucher(code: String) async throws -> VoucherRedeemResponse {
        guard let networkService = networkService else {
            throw ReTaggerError.networkError("Network service not initialized")
        }
        
        let request = VoucherRedeemRequest(voucherCode: code)
        let response: ApiResponse<VoucherRedeemResponse> = try await networkService.request(
            endpoint: "/api/v1/vouchers/redeem",
            method: .POST,
            body: request
        )
        
        // 立即更新本地余额
        applyBalance(response.data.balance)

        // 同时尝试刷新完整 profile；失败不影响兑换结果，但记录日志便于排查
        do {
            try await fetchProfile()
        } catch {
            Logger.auth.warning("兑换后刷新账户信息失败：\(error.localizedDescription, privacy: .public)")
        }

        return response.data
    }
    
    func forgotPassword(email: String) async throws {
        guard let networkService = networkService else { return }
        
        let request = ForgotPasswordRequest(email: email)
        let _: ApiResponse<String> = try await networkService.request(
            endpoint: "/api/v1/users/forgot-password",
            method: .POST,
            body: request
        )
    }
    
    func resendEmailVerification(email: String) async throws {
        guard let networkService = networkService else { return }
        
        let request = ResendVerificationRequest(email: email)
        let _: ApiResponse<String> = try await networkService.request(
            endpoint: "/api/v1/users/resend-verification",
            method: .POST,
            body: request
        )
    }
    
    func deleteAccount() async throws {
        guard let networkService = networkService, self.token != nil else {
            throw ReTaggerError.networkError("Not authenticated")
        }
        
        // 后端要求 RegistrationSource 头用于验证
        let _: ApiResponse<DeleteAccountResponse> = try await networkService.request(
            endpoint: "/api/v1/users/delete-account",
            method: .DELETE,
            body: nil as String?,
            additionalHeaders: ["RegistrationSource": "retagger"]
        )
        
        // 删除成功后清除本地状态
        self.logout()
    }

        
    // MARK: - Google OAuth (Client-Side PKCE, loopback redirect)

    /// 发起 Google 登录：起本地 loopback 回调服务、用系统浏览器打开授权页、
    /// 等待授权码回调后与后端换取登录态。
    ///
    /// Google 已废弃 Desktop 类型 client 的自定义 URL Scheme 重定向，要求
    /// 原生应用改用 loopback 地址 + 系统浏览器（而非内嵌 WebView）完成授权。
    func signInWithGoogle() async throws {
        let server = try await GoogleOAuthLoopbackServer.start()
        defer { server.stop() }

        let redirectUri = GoogleOAuthConfig.redirectUri(port: server.port)
        let codeVerifier = PKCEHelper.generateCodeVerifier()
        let codeChallenge = PKCEHelper.generateCodeChallenge(from: codeVerifier)
        let state = PKCEHelper.generateCodeVerifier()

        guard let url = GoogleOAuthConfig.buildAuthURL(
            codeChallenge: codeChallenge,
            redirectUri: redirectUri,
            state: state
        ) else {
            throw ReTaggerError.networkError("Failed to build Google OAuth URL")
        }

        guard NSWorkspace.shared.open(url) else {
            throw ReTaggerError.networkError("无法打开系统浏览器完成 Google 登录")
        }

        let callback = try await server.waitForCallback()
        guard callback.state == state else {
            throw ReTaggerError.networkError("授权回调校验失败，请重新登录")
        }

        guard let networkService = networkService else { return }

        let request = NativeOAuthRequest(
            code: callback.code,
            redirectUri: redirectUri,
            codeVerifier: codeVerifier
        )

        let response: ApiResponse<OAuthResponse> = try await networkService.request(
            endpoint: "/api/v1/users/oauth",
            method: .POST,
            body: request
        )

        try await handleOAuthResponse(response.data)
    }
    
    /// Handles the Apple Sign In callback
    /// - Parameters:
    ///   - code: The authorization code from Apple
    ///   - givenName: Optional given name
    ///   - familyName: Optional family name
    func handleAppleCallback(code: String, givenName: String?, familyName: String?) async throws {
        guard let networkService = networkService else { return }
        
        var fullName: NativeOAuthRequest.AppleFullName?
        if givenName != nil || familyName != nil {
            fullName = NativeOAuthRequest.AppleFullName(givenName: givenName, familyName: familyName)
        }
        
        let request = NativeOAuthRequest(
            provider: "apple",
            code: code,
            usePkce: false, // Native Apple Sign In doesn't use manual PKCE
            fullName: fullName,
            clientId: Bundle.main.bundleIdentifier
        )
        
        let response: ApiResponse<OAuthResponse> = try await networkService.request(
            endpoint: "/api/v1/users/oauth",
            method: .POST,
            body: request
        )
        
        try await handleOAuthResponse(response.data)
    }
    
    private func handleOAuthResponse(_ oauthData: OAuthResponse) async throws {
        self.token = oauthData.token
        
        self.currentUser = UserResponse(
            id: oauthData.userId,
            username: oauthData.username ?? oauthData.email ?? "",
            email: oauthData.email ?? "",
            displayName: oauthData.displayName,
            avatarUrl: nil,
            role: nil,
            balance: oauthData.balance,
            isEmailVerified: true,
            registrationSource: "oauth",
            proxyUrl: oauthData.proxyUrl
        )
        applyBalance(oauthData.balance)

        do {
            try await fetchProfile()
        } catch {
            Logger.auth.warning("OAuth 登录后刷新账户信息失败：\(error.localizedDescription, privacy: .public)")
        }
    }
}

// Helper for ApiResponse wrapper
struct ApiResponse<T: Codable>: Codable {
    let code: Int
    let message: String
    let data: T
}

// MARK: - Private Helpers

private extension AuthService {
    func makeUser(from response: LoginResponse, fallbackEmail: String) -> UserResponse? {
        if let user = response.user {
            return user
        }
        
        guard
            let userId = response.user?.id ?? response.userId,
            let username = response.user?.username ?? response.username
        else {
            return nil
        }
        
        let email = response.user?.email ?? response.email ?? fallbackEmail
        return UserResponse(
            id: userId,
            username: username,
            email: email,
            displayName: response.displayName ?? response.user?.displayName ?? username,
            avatarUrl: response.user?.avatarUrl,
            role: response.user?.role,
            balance: response.balance ?? response.user?.balance,
            isEmailVerified: response.user?.isEmailVerified,
            registrationSource: response.user?.registrationSource,
            createdAt: response.user?.createdAt,
            updatedAt: response.user?.updatedAt,
            userLevel: response.user?.userLevel,
            userStatus: response.user?.userStatus,
            registrationDate: response.user?.registrationDate,
            lastLogin: response.user?.lastLogin,
            confirmationStatus: response.user?.confirmationStatus,
            proxyUrl: response.proxyUrl ?? response.user?.proxyUrl
        )
    }

    func persistCurrentUser(_ user: UserResponse?) {
        if let user,
           let data = try? JSONEncoder().encode(user),
           let json = String(data: data, encoding: .utf8) {
            KeychainStore.setString(json, forKey: AuthStorageKeys.cachedUser)
        } else {
            KeychainStore.removeValue(forKey: AuthStorageKeys.cachedUser)
        }
    }
}
