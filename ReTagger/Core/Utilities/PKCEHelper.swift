//
//  PKCEHelper.swift
//  ReTagger
//
//  Created by Antigravity on 2026/01/06.
//

import Foundation
import CryptoKit

/// PKCE (Proof Key for Code Exchange) helper for OAuth 2.0
/// Implements RFC 7636 for secure authorization code flow in native apps
enum PKCEHelper {
    
    /// Generates a cryptographically random code verifier
    /// - Returns: A random string between 43-128 characters using URL-safe base64 encoding
    static func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    /// Generates a code challenge from the code verifier using SHA-256
    /// - Parameter verifier: The code verifier string
    /// - Returns: Base64 URL-encoded SHA-256 hash of the verifier
    static func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    /// The code challenge method - always S256 (SHA-256)
    static let codeChallengeMethod = "S256"
}
