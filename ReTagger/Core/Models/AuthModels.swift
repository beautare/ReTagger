//
//  AuthModels.swift
//  ReTagger
//
//  Created by Antigravity on 2025/12/03.
//

import Foundation
import Combine

// MARK: - User Models

struct UserResponse: Codable, Identifiable {
    let id: Int
    let username: String
    let email: String
    let displayName: String?
    let avatarUrl: String?
    let role: String?
    var balance: Int?
    let isEmailVerified: Bool?
    let registrationSource: String?
    let createdAt: String?
    let updatedAt: String?
    let userLevel: String?
    let userStatus: String?
    let registrationDate: String?
    let lastLogin: String?
    let confirmationStatus: Bool?
    let proxyUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId
        case username
        case email
        case displayName
        case avatarUrl
        case role
        case balance
        case isEmailVerified
        case registrationSource
        case createdAt
        case updatedAt
        case userLevel
        case userStatus
        case registrationDate
        case lastLogin
        case confirmationStatus
        case proxyUrl
    }
    
    init(
        id: Int,
        username: String,
        email: String,
        displayName: String? = nil,
        avatarUrl: String? = nil,
        role: String? = nil,
        balance: Int? = nil,
        isEmailVerified: Bool? = nil,
        registrationSource: String? = nil,
        createdAt: String? = nil,
        updatedAt: String? = nil,
        userLevel: String? = nil,
        userStatus: String? = nil,
        registrationDate: String? = nil,
        lastLogin: String? = nil,
        confirmationStatus: Bool? = nil,
        proxyUrl: String? = nil
    ) {
        self.id = id
        self.username = username
        self.email = email
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.role = role
        self.balance = balance
        self.isEmailVerified = isEmailVerified
        self.registrationSource = registrationSource
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.userLevel = userLevel
        self.userStatus = userStatus
        self.registrationDate = registrationDate
        self.lastLogin = lastLogin
        self.confirmationStatus = confirmationStatus
        self.proxyUrl = proxyUrl
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decodeIfPresent(Int.self, forKey: .id)
            ?? container.decode(Int.self, forKey: .userId)
        let username = try container.decode(String.self, forKey: .username)
        let email = try container.decode(String.self, forKey: .email)
        
        self.init(
            id: id,
            username: username,
            email: email,
            displayName: try container.decodeIfPresent(String.self, forKey: .displayName),
            avatarUrl: try container.decodeIfPresent(String.self, forKey: .avatarUrl),
            role: try container.decodeIfPresent(String.self, forKey: .role),
            balance: try container.decodeIfPresent(Int.self, forKey: .balance),
            isEmailVerified: try container.decodeIfPresent(Bool.self, forKey: .isEmailVerified),
            registrationSource: try container.decodeIfPresent(String.self, forKey: .registrationSource),
            createdAt: try container.decodeIfPresent(String.self, forKey: .createdAt),
            updatedAt: try container.decodeIfPresent(String.self, forKey: .updatedAt),
            userLevel: try container.decodeIfPresent(String.self, forKey: .userLevel),
            userStatus: try container.decodeIfPresent(String.self, forKey: .userStatus),
            registrationDate: try container.decodeIfPresent(String.self, forKey: .registrationDate),
            lastLogin: try container.decodeIfPresent(String.self, forKey: .lastLogin),
            confirmationStatus: try container.decodeIfPresent(Bool.self, forKey: .confirmationStatus),
            proxyUrl: try container.decodeIfPresent(String.self, forKey: .proxyUrl)
        )
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(username, forKey: .username)
        try container.encode(email, forKey: .email)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encodeIfPresent(balance, forKey: .balance)
        try container.encodeIfPresent(isEmailVerified, forKey: .isEmailVerified)
        try container.encodeIfPresent(registrationSource, forKey: .registrationSource)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(userLevel, forKey: .userLevel)
        try container.encodeIfPresent(userStatus, forKey: .userStatus)
        try container.encodeIfPresent(registrationDate, forKey: .registrationDate)
        try container.encodeIfPresent(lastLogin, forKey: .lastLogin)
        try container.encodeIfPresent(confirmationStatus, forKey: .confirmationStatus)
        try container.encodeIfPresent(proxyUrl, forKey: .proxyUrl)
    }
}

// MARK: - Auth Requests

struct LoginRequest: Codable {
    let email: String
    let password: String
}

struct RegisterRequest: Codable {
    let email: String
    let password: String
    let username: String?
    let displayName: String?
    let registrationSource: String
    let referralCode: String?
    let deviceFingerprint: String?
    let policyAcceptance: PolicyAcceptanceRequest?
}

struct ForgotPasswordRequest: Codable {
    let email: String
}

struct ResetPasswordRequest: Codable {
    let token: String
    let newPassword: String
}

struct EmailVerificationRequest: Codable {
    let token: String
}

struct ResendVerificationRequest: Codable {
    let email: String
}

// MARK: - Auth Responses

struct LoginResponse: Codable {
    let token: String
    let user: UserResponse?
    let expiresIn: Int?
    let username: String?
    let userId: Int?
    let proxyUrl: String?
    let balance: Int?
    let email: String?
    let displayName: String?
}

struct TokenCheckResponse: Codable {
    let user: UserResponse?
    let remainingRequests: Int?
}

struct RegisterResponse: Codable {
    let token: String
    let user: UserResponse?
    let expiresIn: Int?
    let username: String?
    let userId: Int?
    let email: String?
    let displayName: String?
}

// MARK: - Voucher Models

struct VoucherRedeemRequest: Codable {
    let voucherCode: String
}

struct VoucherRedeemResponse: Codable {
    // 必填字段
    let voucherCode: String
    let userId: Int
    let balance: Int
    let redeemedAt: String
    
    // 可选字段（后端实际返回但原模型定义错误或缺失的）
    let id: Int?
    let type: String?
    let value: Int?
    let alias: String?
    let email: String?
    let token: String?
    
    enum CodingKeys: String, CodingKey {
        case voucherCode, userId, balance, redeemedAt
        case id, type, value, alias, email, token
    }
}

// MARK: - Native OAuth Models (Client-Side PKCE)

/// Request for native OAuth login with PKCE
/// Request for native OAuth login with PKCE
struct NativeOAuthRequest: Codable {
    let provider: String
    let code: String
    let redirectUri: String?
    let codeVerifier: String?
    let usePkce: Bool
    let fullName: AppleFullName?
    let clientId: String?
    
    struct AppleFullName: Codable {
        let givenName: String?
        let familyName: String?
    }
    
    // Initializer for Google (PKCE)
    init(provider: String = "google", code: String, redirectUri: String, codeVerifier: String) {
        self.provider = provider
        self.code = code
        self.redirectUri = redirectUri
        self.codeVerifier = codeVerifier
        self.usePkce = true
        self.fullName = nil
        self.clientId = nil
    }
    
    // Initializer for Apple (Native, No PKCE)
    init(provider: String = "apple", code: String, usePkce: Bool = false, fullName: AppleFullName? = nil, clientId: String? = nil) {
        self.provider = provider
        self.code = code
        self.redirectUri = nil
        self.codeVerifier = nil
        self.usePkce = usePkce
        self.fullName = fullName
        self.clientId = clientId
    }
}

struct OAuthResponse: Codable {
    let token: String
    let userId: Int
    let newUser: Bool
    let username: String?
    let displayName: String?
    let email: String?
    let proxyUrl: String?
    let balance: Int?
    let tokenExpiryTime: String?
    
    // Convenience property for backward compatibility
    var isNewUser: Bool { newUser }
}

// MARK: - Account Management Models

struct DeleteAccountResponse: Codable {
    let message: String?
}

/// 策略接受请求，字段与后端 PolicyAcceptanceRequest 对齐
struct PolicyAcceptanceRequest: Codable {
    let version: String
    let agreedAt: String
    let document: String
    let source: String
    let locale: String

    /// 生成当前策略接受记录
    static func generate() -> PolicyAcceptanceRequest {
        PolicyAcceptanceRequest(
            version: "1.0",
            agreedAt: ISO8601DateFormatter().string(from: Date()),
            document: "terms_and_privacy",
            source: "retagger",
            locale: Locale.current.identifier
        )
    }
}
