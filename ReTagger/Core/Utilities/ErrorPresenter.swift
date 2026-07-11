//
//  ErrorPresenter.swift
//  ReTagger
//
//  User-friendly error presentation and recovery
//

import Foundation
import SwiftUI

/// 用户友好的错误展示器
@MainActor
struct ErrorPresenter {

    // MARK: - Error Alert Model

    /// 错误警告信息模型
    struct ErrorAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let primaryAction: ActionButton
        let secondaryAction: ActionButton?

        /// 操作按钮
        struct ActionButton {
            let title: String
            let style: ButtonStyle
            let handler: (() -> Void)?

            enum ButtonStyle {
                case `default`
                case cancel
                case destructive
            }
        }
    }

    // MARK: - Present Error

    /// 将 ReTaggerError 转换为用户友好的错误警告（跟随应用内语言设置）
    /// - Parameters:
    ///   - error: ReTagger 错误
    ///   - localization: 应用语言管理器
    /// - Returns: 错误警告信息
    static func present(_ error: ReTaggerError, localization: LocalizationManager) -> ErrorAlert {
        switch error {
        case .fileSystemError(let message):
            return ErrorAlert(
                title: localization.string("error.filesystem"),
                message: localization.string("error_alert.filesystem.message", arguments: message as NSString),
                primaryAction: okAction(localization),
                secondaryAction: nil
            )

        case .permissionDenied(let url):
            let fileName = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
            return ErrorAlert(
                title: localization.string("error_alert.permission.title"),
                message: localization.string("error_alert.permission.message", arguments: fileName as NSString),
                primaryAction: gotItAction(localization),
                secondaryAction: nil
            )

        case .metadataReadError(let url):
            return ErrorAlert(
                title: localization.string("error.metadata_read_failed"),
                message: localization.string("error_alert.metadata_read.message", arguments: url.lastPathComponent as NSString),
                primaryAction: .init(
                    title: localization.string("common.skip"),
                    style: .default,
                    handler: nil
                ),
                secondaryAction: revealAction(localization, url: url)
            )

        case .metadataWriteError(let url):
            return ErrorAlert(
                title: localization.string("error_alert.metadata_write.title"),
                message: localization.string("error_alert.metadata_write.message", arguments: url.lastPathComponent as NSString),
                primaryAction: .init(
                    title: localization.string("common.retry"),
                    style: .default,
                    handler: nil
                ),
                secondaryAction: .init(
                    title: localization.string("common.skip"),
                    style: .cancel,
                    handler: nil
                )
            )

        case .metadataUnsupportedFormat(let url):
            return ErrorAlert(
                title: localization.string("error.write_not_supported"),
                message: localization.string("error_alert.unsupported_format.message", arguments: url.lastPathComponent as NSString),
                primaryAction: gotItAction(localization),
                secondaryAction: revealAction(localization, url: url)
            )

        case .networkError(let message):
            return ErrorAlert(
                title: localization.string("error_alert.network.title"),
                message: localization.string("error_alert.network.message", arguments: message as NSString),
                primaryAction: .init(
                    title: localization.string("common.retry"),
                    style: .default,
                    handler: nil
                ),
                secondaryAction: nil
            )

        case .apiError(let statusCode, let message):
            let explanation: String
            switch statusCode {
            case 400:
                explanation = localization.string("error.invalid_request")
            case 401:
                explanation = localization.string("error.unauthorized")
            case 403:
                explanation = localization.string("error.access_denied")
            case 404:
                explanation = localization.string("error.endpoint_not_found")
            case 429:
                explanation = localization.string("error.rate_limit")
            case 500...599:
                explanation = localization.string("error.server_error")
            default:
                explanation = message
            }
            return ErrorAlert(
                title: localization.string("error_alert.api.title", arguments: statusCode),
                message: explanation,
                primaryAction: okAction(localization),
                secondaryAction: nil
            )

        case .invalidResponse:
            return ErrorAlert(
                title: localization.string("error_alert.invalid_response.title"),
                message: localization.string("error_alert.invalid_response.message"),
                primaryAction: okAction(localization),
                secondaryAction: nil
            )

        case .aiProcessingFailed(let message):
            return ErrorAlert(
                title: localization.string("error_alert.ai_failed.title"),
                message: localization.string("error_alert.ai_failed.message", arguments: message as NSString),
                primaryAction: .init(
                    title: localization.string("common.retry"),
                    style: .default,
                    handler: nil
                ),
                secondaryAction: nil
            )

        case .backupFailed(let url):
            return ErrorAlert(
                title: localization.string("error_alert.backup_failed.title"),
                message: localization.string("error_alert.backup_failed.message", arguments: url.lastPathComponent as NSString),
                primaryAction: .init(
                    title: localization.string("error_alert.backup_failed.cancel"),
                    style: .cancel,
                    handler: nil
                ),
                secondaryAction: .init(
                    title: localization.string("error_alert.backup_failed.continue"),
                    style: .destructive,
                    handler: nil
                )
            )

        case .invalidSettings(let message):
            return ErrorAlert(
                title: localization.string("error_alert.invalid_settings.title"),
                message: localization.string("error_alert.invalid_settings.message", arguments: message as NSString),
                primaryAction: .init(
                    title: localization.string("error_alert.invalid_settings.open_settings"),
                    style: .default,
                    handler: nil
                ),
                secondaryAction: .init(
                    title: localization.string("common.cancel"),
                    style: .cancel,
                    handler: nil
                )
            )

        case .operationCancelled:
            return ErrorAlert(
                title: localization.string("error_alert.cancelled.title"),
                message: localization.string("error.user_cancelled"),
                primaryAction: okAction(localization),
                secondaryAction: nil
            )
        }
    }

    // MARK: - Common Actions

    private static func okAction(_ localization: LocalizationManager) -> ErrorAlert.ActionButton {
        .init(title: localization.string("common.ok"), style: .default, handler: nil)
    }

    private static func gotItAction(_ localization: LocalizationManager) -> ErrorAlert.ActionButton {
        .init(title: localization.string("common.got_it"), style: .default, handler: nil)
    }

    private static func revealAction(_ localization: LocalizationManager, url: URL) -> ErrorAlert.ActionButton {
        .init(
            title: localization.string("action.reveal_in_finder"),
            style: .default,
            handler: {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        )
    }
}

// MARK: - SwiftUI Integration

extension ErrorPresenter.ErrorAlert {
    /// 转换为 SwiftUI Alert
    func toSwiftUIAlert(onDismiss: @escaping () -> Void = {}) -> Alert {
        if let secondary = secondaryAction {
            return Alert(
                title: Text(title),
                message: Text(message),
                primaryButton: buttonToAlertButton(primaryAction, onDismiss: onDismiss),
                secondaryButton: buttonToAlertButton(secondary, onDismiss: onDismiss)
            )
        } else {
            return Alert(
                title: Text(title),
                message: Text(message),
                dismissButton: buttonToAlertButton(primaryAction, onDismiss: onDismiss)
            )
        }
    }

    private func buttonToAlertButton(
        _ button: ErrorPresenter.ErrorAlert.ActionButton,
        onDismiss: @escaping () -> Void
    ) -> Alert.Button {
        let action = {
            button.handler?()
            onDismiss()
        }

        switch button.style {
        case .default:
            return .default(Text(button.title), action: action)
        case .cancel:
            return .cancel(Text(button.title), action: action)
        case .destructive:
            return .destructive(Text(button.title), action: action)
        }
    }
}
