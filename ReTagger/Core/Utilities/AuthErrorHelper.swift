//
//  AuthErrorHelper.swift
//  ReTagger
//
//  统一的认证错误处理工具，提供友好的本地化错误消息。
//

import Foundation

/// 认证错误处理工具
enum AuthErrorHelper {

    /// 将错误转换为用户友好的消息（跟随应用内语言设置）
    /// - Parameters:
    ///   - error: 原始错误
    ///   - localization: 应用语言管理器
    /// - Returns: 本地化的友好错误消息
    @MainActor
    static func friendlyMessage(from error: Error, localization: LocalizationManager) -> String {
        if let retaggerError = error as? ReTaggerError {
            switch retaggerError {
            case .apiError(let code, let payload):
                if let parsed = parseBackendMessage(payload) {
                    return parsed
                }
                switch code {
                case 400:
                    return localization.string("error.invalid_request")
                case 401:
                    return localization.string("error.auth_failed")
                case 403:
                    return localization.string("error.access_denied")
                case 404:
                    return localization.string("error.endpoint_not_found")
                case 429:
                    return localization.string("error.rate_limit")
                case 500...599:
                    return localization.string("error.server_error")
                default:
                    return payload
                }
            case .networkError(let message):
                if message.contains("Failed to decode response") {
                    return localization.string("error.unparseable_response")
                }
                return message
            default:
                break
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet, .timedOut:
                return localization.string("error.network_unavailable")
            default:
                break
            }
        }

        let localizedDescription = error.localizedDescription
        return localizedDescription.isEmpty
            ? localization.string("error.unknown")
            : localizedDescription
    }

    /// 尝试从后端响应 JSON 中解析错误消息
    /// - Parameter raw: 原始 JSON 字符串
    /// - Returns: 解析出的消息，如果解析失败则返回 nil
    static func parseBackendMessage(_ raw: String) -> String? {
        struct Payload: Decodable {
            let message: String?
        }
        guard let data = raw.data(using: .utf8) else { return nil }
        if let payload = try? JSONDecoder().decode(Payload.self, from: data),
           let message = payload.message,
           !message.isEmpty {
            return message
        }
        return nil
    }
}
