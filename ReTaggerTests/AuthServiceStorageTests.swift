//
//  AuthServiceStorageTests.swift
//  ReTaggerTests
//
//  验证 AuthService 在 UserDefaults 中的凭据持久化与清除逻辑
//

import Testing
import Foundation
@testable import ReTagger

@Suite("AuthService Storage Tests", .serialized)
struct AuthServiceStorageTests {

    private func cleanup() {
        UserDefaults.standard.removeObject(forKey: AuthStorageKeys.userToken)
        UserDefaults.standard.removeObject(forKey: AuthStorageKeys.cachedUser)
        UserDefaults.standard.removeObject(forKey: AuthStorageKeys.lastLoginEmail)
    }

    @Test @MainActor
    func testTokenAndUserPersistenceInUserDefaults() async throws {
        cleanup()
        defer { cleanup() }

        let deviceTokenManager = DeviceTokenManager(baseURL: "https://example.com")
        let authService = AuthService(deviceTokenManager: deviceTokenManager)

        #expect(!authService.isAuthenticated)
        #expect(authService.currentUser == nil)

        // 模拟登录成功写入 Token 和 User
        let dummyToken = "test.jwt.token"
        let dummyUser = UserResponse(
            id: 1001,
            username: "tester",
            email: "test@example.com",
            displayName: "Test User",
            balance: 50
        )

        // 设置 currentUser 会触发 persistCurrentUser 写入 UserDefaults
        authService.currentUser = dummyUser

        // 通过直接注入持久化数据来测试恢复
        UserDefaults.standard.set(dummyToken, forKey: AuthStorageKeys.userToken)

        // 创建新的 AuthService 实例，验证能够正确从 UserDefaults 恢复
        let restoredAuthService = AuthService(deviceTokenManager: deviceTokenManager)
        #expect(restoredAuthService.isAuthenticated)
        #expect(restoredAuthService.currentUser?.id == 1001)
        #expect(restoredAuthService.currentUser?.email == "test@example.com")
        #expect(restoredAuthService.balance == 50)

        // 验证 logout 会彻底清理持久化数据
        restoredAuthService.logout()
        #expect(!restoredAuthService.isAuthenticated)
        #expect(restoredAuthService.currentUser == nil)
        #expect(restoredAuthService.balance == nil)

        #expect(UserDefaults.standard.string(forKey: AuthStorageKeys.userToken) == nil)
        #expect(UserDefaults.standard.data(forKey: AuthStorageKeys.cachedUser) == nil)
    }
}
