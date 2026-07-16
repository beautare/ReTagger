//
//  GoogleOAuthConfig.swift
//  ReTagger
//
//  Created by Antigravity on 2026/01/06.
//

import Foundation

/// Configuration for Google OAuth in ReTagger
///
/// To set up:
/// 1. Go to Google Cloud Console (https://console.cloud.google.com)
/// 2. Create a new OAuth 2.0 Client ID with type "Desktop app"
/// 3. Put it in `.env.local` at the repository root: GOOGLE_CLIENT_ID=...
enum GoogleOAuthConfig {

    /// Google OAuth Client ID for ReTagger macOS app
    /// Format: {numbers}-{letters}.apps.googleusercontent.com
    ///
    /// 统一从 .env.local 读取（开发时读仓库根目录，发布构建由
    /// “Embed .env.local” 构建阶段将该文件拷入 App 包内供运行时读取），
    /// 仓库中不保留真实 Client ID
    static var clientId: String {
        EnvironmentParser.getValue(for: "GOOGLE_CLIENT_ID", defaultValue: "YOUR_CLIENT_ID.apps.googleusercontent.com")
    }

    /// OAuth redirect URI，使用 loopback 地址。
    /// Google 已废弃 Desktop 类型 client 的自定义 URL Scheme 重定向方案
    /// （"Custom URI schemes are no longer supported due to the risk of app impersonation"），
    /// 现在要求使用 http://127.0.0.1:{port} 接收系统浏览器的授权回调。
    static func redirectUri(port: UInt16) -> String {
        "http://127.0.0.1:\(port)/oauth2redirect"
    }

    /// OAuth scopes requested
    static let scopes = ["openid", "email", "profile"]

    /// Google OAuth authorization endpoint
    static let authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"

    /// Builds the complete OAuth authorization URL with PKCE
    /// - Parameters:
    ///   - codeChallenge: The PKCE code challenge
    ///   - redirectUri: loopback 回调地址，需与后续换取 token 时提交的值完全一致
    ///   - state: CSRF 校验用的随机串
    /// - Returns: The complete authorization URL
    static func buildAuthURL(codeChallenge: String, redirectUri: String, state: String) -> URL? {
        var components = URLComponents(string: authorizationEndpoint)

        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: PKCEHelper.codeChallengeMethod),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state)
        ]

        return components?.url
    }
}
