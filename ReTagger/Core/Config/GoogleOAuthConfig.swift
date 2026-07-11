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
    
    /// OAuth redirect URI - uses reverse client ID format for native apps
    /// This is automatically derived from the clientId
    static var redirectUri: String {
        // Convert from "123456.apps.googleusercontent.com" to "com.googleusercontent.apps.123456:/oauth2redirect"
        let prefix = clientId.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(prefix):/oauth2redirect"
    }
    
    /// OAuth scopes requested
    static let scopes = ["openid", "email", "profile"]
    
    /// Google OAuth authorization endpoint
    static let authorizationEndpoint = "https://accounts.google.com/o/oauth2/v2/auth"
    
    /// Builds the complete OAuth authorization URL with PKCE
    /// - Parameters:
    ///   - codeChallenge: The PKCE code challenge
    ///   - state: Optional state parameter for CSRF protection
    /// - Returns: The complete authorization URL
    static func buildAuthURL(codeChallenge: String, state: String? = nil) -> URL? {
        print("[GoogleOAuthConfig] clientId: \(clientId)")
        print("[GoogleOAuthConfig] redirectUri: \(redirectUri)")
        var components = URLComponents(string: authorizationEndpoint)
        
        var queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: PKCEHelper.codeChallengeMethod),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        
        if let state = state {
            queryItems.append(URLQueryItem(name: "state", value: state))
        }
        
        components?.queryItems = queryItems
        return components?.url
    }
}
