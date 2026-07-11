//
//  ReTaggerError.swift
//  ReTagger
//
//  Custom error types for the application
//

import Foundation

/// Custom errors for ReTagger application
enum ReTaggerError: LocalizedError {
    case fileSystemError(String)
    case permissionDenied(URL)
    case metadataReadError(URL)
    case metadataWriteError(URL)
    case metadataUnsupportedFormat(URL)
    case networkError(String)
    case apiError(statusCode: Int, message: String)
    case invalidResponse
    case aiProcessingFailed(String)
    case backupFailed(URL)
    case invalidSettings(String)
    case operationCancelled

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .fileSystemError(let msg):
            return "File system error: \(msg)"
        case .permissionDenied(let url):
            return "Permission denied for: \(url.path)"
        case .metadataReadError(let url):
            return "Failed to read metadata from: \(url.lastPathComponent)"
        case .metadataWriteError(let url):
            return "Failed to write metadata to: \(url.lastPathComponent)"
        case .metadataUnsupportedFormat(let url):
            return "当前文件编码不支持写入：\(url.lastPathComponent)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .apiError(let code, let msg):
            return "API error (\(code)): \(msg)"
        case .invalidResponse:
            return "Invalid response from server"
        case .aiProcessingFailed(let msg):
            return "AI processing failed: \(msg)"
        case .backupFailed(let url):
            return "Failed to create backup for: \(url.lastPathComponent)"
        case .invalidSettings(let msg):
            return "Invalid settings: \(msg)"
        case .operationCancelled:
            return "Operation was cancelled"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "Please select a directory that you have permission to access."
        case .networkError:
            return "Please check your internet connection and try again."
        case .apiError:
            return "Please verify your API key and backend URL in settings."
        case .invalidSettings:
            return "Please check your settings and try again."
        default:
            return nil
        }
    }
}
